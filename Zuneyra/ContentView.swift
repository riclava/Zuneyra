import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: LibrarySection = .albums
    @State private var navigationGeneration = 0
    @State private var query = ""
    @State private var songSort: LibrarySongSort = .recent
    @FocusState private var searchFocused: Bool
    @State private var playlistNavigation = PageNavigation<UUID>()
    @State private var albumBackQuery = ""
    @State private var forwardAlbum: (key: String, query: String)?
    @State private var selectedAlbum: String?
    @State private var importing = false
    @State private var showingPlayer = false
    @State private var showingQueue = false
    @State private var showingManagement = false
    @State private var playlistAddRequest: PlaylistAddRequest?
    private struct PlaylistAddRequest: Identifiable { let id = UUID(); let tracks: [Track] }
    @State private var managementTab = 0
    @State private var openManagementAfterReport = false
    @State private var selecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var confirmDelete = false
    @State private var deletionBytes: Int64 = 0

    enum LibrarySection: String, CaseIterable, Identifiable {
        case albums = "专辑", songs = "歌曲", artists = "艺术家", favorites = "我的收藏", playlists = "歌单"
        var id: String { rawValue }
        var title: String { NSLocalizedString(rawValue, comment: "Library category") }
        var icon: String { switch self { case .albums: "opticaldisc"; case .songs: "music.note"; case .artists: "person.2"; case .favorites: "heart"; case .playlists: "music.note.list" } }
    }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var albumContents: [Track] {
        LibraryPresentation.albumTracks(store.tracks.filter { $0.albumKey == selectedAlbum })
    }
    private var filtered: [Track] {
        let matches = store.tracks.filter { track in
            (section != .favorites || track.favorite)
                && (selectedAlbum == nil || track.albumKey == selectedAlbum)
                && LibraryPresentation.matches(track, query: query)
        }
        return selectedAlbum == nil ? songSort.apply(to: matches) : LibraryPresentation.albumTracks(matches)
    }
    private var albums: [[Track]] {
        Dictionary(grouping: filtered, by: \.albumKey).values
            .map { LibraryPresentation.albumTracks($0) }
            .sorted { $0[0].albumKey.localizedStandardCompare($1[0].albumKey) == .orderedAscending }
    }
    private var gridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 190, maximum: 300), spacing: 26)]
        #else
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 250 : 145, maximum: 280), spacing: 20)]
        #endif
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Group {
                #if os(macOS)
                HStack(spacing: 0) {
                    sidebar.frame(width: 210)
                    Rectangle().fill(Sunset.stroke(scheme)).frame(width: 1)
                    navigationContent
                }
                #else
                navigationContent
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let current = store.current {
                MiniPlayerView(track: current, openPlayer: { searchFocused = false; showingPlayer = true }, openQueue: { showingQueue = true })
            }
        }
        .tint(Sunset.accent(scheme))
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): store.importFiles(urls); case .failure(let error): store.errorMessage = error.localizedDescription }
        }
        .alert(String(localized: "无法完成操作"), isPresented: Binding(get: { store.errorMessage != nil && !showingManagement && playlistAddRequest == nil }, set: { if !$0 { store.errorMessage = nil } })) { Button(String(localized: "好")) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .alert(String(localized: "操作结果"), isPresented: Binding(get: { store.managementMessage != nil && !showingManagement }, set: { if !$0 { store.managementMessage = nil } })) {
            Button(String(localized: "好")) { store.managementMessage = nil }
        } message: { Text(store.managementMessage ?? "") }
        .alert(String(localized: "删除 \(selectedIDs.count) 首歌曲？"), isPresented: $confirmDelete) {
            Button(String(localized: "删除音频副本"), role: .destructive) {
                let ids = selectedIDs
                Task { if await store.deleteTracks(ids) { selectedIDs.removeAll(); selecting = false } }
            }.disabled(store.isBusy)
            Button(String(localized: "取消"), role: .cancel) { }
        } message: {
            Text(String(localized: "将从音乐库、收藏及所有歌单中移除所选歌曲，并删除约 \(StorageUsage.formatted(deletionBytes)) 的本机音频副本。原位置和 Finder 传入文件保留。若包含正在播放的歌曲，播放会停止。此操作不可撤销。"))
        }
        .sheet(item: $playlistAddRequest) { request in AddToPlaylistView(tracks: request.tracks, onComplete: { playlistAddRequest = nil }) }
        .sheet(isPresented: $showingManagement) { LibraryManagementView(initialTab: managementTab).environment(store) }
        .onChange(of: store.tracks.map(\.id)) { _, ids in
            selectedIDs.formIntersection(Set(ids))
            if let key = selectedAlbum, !store.tracks.contains(where: { $0.albumKey == key }) { selectedAlbum = nil }
        }
        .sheet(isPresented: $showingPlayer) { NowPlayingView().environment(store) }
        .sheet(isPresented: $showingQueue) {
            NavigationStack { PlaybackQueueView() }.environment(store)
            #if os(macOS)
            .frame(width: 600, height: 650)
            #endif
        }
        .sheet(isPresented: Binding(get: { store.importReport != nil && !showingManagement }, set: { if !$0 { store.importReport = nil } }), onDismiss: {
            if openManagementAfterReport { openManagementAfterReport = false; showingManagement = true }
        }) { importResults }
        .onChange(of: scenePhase) { _, value in
            if value == .active { store.scanSharedDocuments() }
            else { store.saveSession() }
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 580)
        #endif
    }

    private var navigationContent: some View {
        NavigationStack(path: Binding(get: { playlistNavigation.path }, set: { playlistNavigation.setPath($0) })) {
            VStack(spacing: 0) {
                workspaceBar
                searchField
                #if os(iOS)
                sectionPicker
                #endif
                if store.isImporting { importProgress }
                if let notice = store.playlistNotice { noticeBanner(notice) }
                if selecting { selectionBar }
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if section == .playlists {
                                PlaylistLibraryView(query: searchTerm)
                            } else {
                                libraryHeader
                                libraryContent
                            }
                        }
                        .id("libraryTop")
                        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
                        .frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: section) { _, _ in scroll.scrollTo("libraryTop", anchor: .top) }
                    .onChange(of: selectedAlbum) { _, _ in scroll.scrollTo("libraryTop", anchor: .top) }
                }
            }
            .background(Sunset.background(scheme))
            .navigationDestination(for: UUID.self) { PlaylistDetailView(playlistID: $0) }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
        .edgeNavigation(
            back: selectedAlbum != nil || playlistNavigation.canGoBack ? { navigateBack() } : nil,
            forward: canNavigateForward ? { navigateForward() } : nil
        )
        .id(navigationGeneration)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StudioMark().foregroundStyle(Sunset.accent(scheme))
                Text("Zuneyra").font(.system(size: 27, weight: .medium, design: .serif)).tracking(-1)
            }.padding(.horizontal, 16).padding(.top, 23).padding(.bottom, 30)
            Text("PRIVATE COLLECTION").font(.system(size: 9, weight: .medium)).tracking(1.8).foregroundStyle(Sunset.secondary(scheme))
                .padding(.horizontal, 22).padding(.bottom, 18)
            VStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { item in
                    Button { switchSection(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 14)).frame(width: 20)
                            Text(item.title).font(.system(size: 14, weight: section == item ? .medium : .regular))
                            Spacer(minLength: 4)
                            Text(sectionCount(item)).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Sunset.secondary(scheme))
                        }.padding(.horizontal, 12).frame(height: 43)
                            .foregroundStyle(section == item ? Sunset.accent(scheme) : .primary)
                            .background(section == item ? Sunset.accent(scheme).opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(alignment: .leading) {
                                if section == item { Circle().fill(Sunset.accent(scheme)).frame(width: 4, height: 4) }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }.padding(.horizontal, 10)
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
                Label(String(localized: "本地音乐 · 离线可用"), systemImage: "internaldrive")
                    .font(.system(size: 11)).foregroundStyle(Sunset.secondary(scheme))
            }.padding(18)
        }.frame(maxHeight: .infinity).background(Sunset.panel(scheme))
    }

    private func sectionCount(_ item: LibrarySection) -> String {
        switch item {
        case .albums: return String(Set(store.tracks.map(\.albumKey)).count)
        case .songs: return String(store.tracks.count)
        case .artists: return String(Set(store.tracks.map(\.artist)).count)
        case .favorites: return String(store.tracks.filter(\.favorite).count)
        case .playlists: return String(store.playlists.count)
        }
    }

    private var workspaceBar: some View {
        HStack(spacing: 6) {
            #if os(iOS)
            StudioMark().foregroundStyle(Sunset.accent(scheme))
            Text("Zuneyra").font(.system(.title2, design: .serif, weight: .medium)).tracking(-0.5).lineLimit(1)
            #else
            Text(String(localized: "你的私人音乐库")).font(.system(.subheadline, design: .serif)).foregroundStyle(Sunset.secondary(scheme))
            #endif
            Spacer(minLength: 0)
            Button { showingQueue = true } label: { Image(systemName: "list.bullet") }
                .buttonStyle(StudioIconButtonStyle()).accessibilityLabel(String(localized: "播放队列")).help(String(localized: "播放队列"))
            Button { managementTab = 0; showingManagement = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(StudioIconButtonStyle()).accessibilityLabel(String(localized: "音乐库管理")).help(String(localized: "音乐库管理"))
            #if os(iOS)
            Menu {
                Button(String(localized: "选择文件或文件夹"), systemImage: "folder") { importing = true }
                Button(String(localized: "导入电脑传入的音乐"), systemImage: "cable.connector") { store.scanSharedDocuments() }
            } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .menuStyle(.borderlessButton).accessibilityLabel(String(localized: "导入音乐")).disabled(store.isBusy)
            #else
            Button { importing = true } label: { Label(String(localized: "添加音乐"), systemImage: "plus") }
                .buttonStyle(StudioButtonStyle()).disabled(store.isBusy).padding(.leading, 8)
                .keyboardShortcut("o", modifiers: .command).accessibilityLabel(String(localized: "导入音乐"))
            #endif
        }.font(.subheadline).padding(.horizontal, 24).padding(.vertical, 10)
            .background(Sunset.background(scheme))
    }

    private var canNavigateForward: Bool {
        guard !selecting else { return false }
        if section == .playlists {
            return playlistNavigation.future.last.map { id in store.playlists.contains { $0.id == id } } ?? false
        }
        return selectedAlbum == nil && (forwardAlbum.map { visit in store.tracks.contains { $0.albumKey == visit.key } } ?? false)
    }
    private func openAlbum(_ key: String) {
        albumBackQuery = query
        forwardAlbum = nil
        selectedAlbum = key
        query = ""
        searchFocused = false
    }
    private func navigateBack() {
        searchFocused = false
        if playlistNavigation.canGoBack { playlistNavigation.back() }
        else if let selectedAlbum {
            forwardAlbum = (selectedAlbum, query)
            self.selectedAlbum = nil
            query = albumBackQuery
        }
    }
    private func navigateForward() {
        guard canNavigateForward else { return }
        searchFocused = false
        if section == .playlists { playlistNavigation.forward() }
        else if let visit = forwardAlbum {
            albumBackQuery = query
            selectedAlbum = visit.key
            query = visit.query
            forwardAlbum = nil
        }
    }

    private func switchSection(_ item: LibrarySection) {
        navigationGeneration += 1
        playlistNavigation = PageNavigation()
        forwardAlbum = nil
        albumBackQuery = ""
        section = item
        selectedAlbum = nil
        selecting = false
        selectedIDs.removeAll()
        searchFocused = false
        query = ""
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(section == .playlists ? String(localized: "搜索歌单") : selectedAlbum == nil ? String(localized: "歌曲、专辑、艺术家") : String(localized: "搜索此专辑"), text: $query)
                .textFieldStyle(.plain).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(section == .playlists ? String(localized: "搜索歌单") : selectedAlbum == nil ? String(localized: "搜索音乐库") : String(localized: "搜索此专辑"))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(String(localized: "清除搜索"))
            }
        }
        .padding(.leading, 12).padding(.trailing, query.isEmpty ? 12 : 0)
        #if os(macOS)
        .frame(minHeight: 36)
        #else
        .frame(minHeight: 44)
        #endif
        .background(Sunset.panel(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocused ? Sunset.accent(scheme) : .clear, lineWidth: 1) }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
        .frame(maxWidth: 1100).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(LibrarySection.allCases) { item in
                    Button { switchSection(item) } label: {
                        Text(item == .favorites ? String(localized: "收藏") : item.title)
                            .font(.subheadline.weight(section == item ? .semibold : .medium))
                            .fixedSize().frame(minHeight: 44)
                            .foregroundStyle(section == item ? Sunset.accent(scheme) : Sunset.secondary(scheme))
                            .overlay(alignment: .bottom) {
                                if section == item { Rectangle().fill(Sunset.accent(scheme)).frame(height: 2) }
                            }
                    }
                    .buttonStyle(.plain).accessibilityLabel(item.title)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }.padding(.horizontal, 24)
        }.overlay(alignment: .bottom) { Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1) }
    }

    private var importProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(store.importProgress).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "取消")) { store.cancelImport() }.font(.subheadline).frame(minHeight: 44)
        }.padding(.horizontal, 20).padding(.vertical, 4)
            .background(Sunset.panel(scheme))
            .accessibilityElement(children: .contain)
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
            Text(notice).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button { store.playlistNotice = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel(String(localized: "关闭歌单提示"))
        }.foregroundStyle(Sunset.accent(scheme)).padding(.leading, 20).padding(.trailing, 8)
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "已选 \(selectedIDs.count) 首")).font(.subheadline.weight(.semibold))
                Spacer()
                Button(selectedIDs.isSuperset(of: Set(filtered.map(\.id))) && !filtered.isEmpty ? String(localized: "取消全选") : String(localized: "全选当前结果")) {
                    let visible = Set(filtered.map(\.id))
                    if selectedIDs.isSuperset(of: visible) { selectedIDs.subtract(visible) }
                    else { selectedIDs.formUnion(visible) }
                }.font(.subheadline).frame(minHeight: 44)
            }
            HStack {
                Menu {
                    Button(String(localized: "添加到歌单"), systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: selectedTracks) }
                    Button(String(localized: "下一首播放")) { store.insertNext(selectedTracks) }
                    Button(String(localized: "稍后播放")) { store.appendToQueue(selectedTracks) }
                } label: { Label(String(localized: "更多操作"), systemImage: "ellipsis.circle").frame(minHeight: 44) }
                .disabled(selectedIDs.isEmpty || store.isBusy)
                Spacer()
                Button(String(localized: "删除"), systemImage: "trash", role: .destructive) { beginDeletion(selectedIDs) }
                    .frame(minHeight: 44).disabled(selectedIDs.isEmpty || store.isBusy)
                Button(String(localized: "完成")) { selecting = false; selectedIDs.removeAll() }.frame(minHeight: 44)
            }.font(.subheadline)
        }.padding(.horizontal, 20).background(Sunset.panel(scheme))
    }
    private var selectedTracks: [Track] {
        let visible = filtered
        let visibleIDs = Set(visible.map(\.id))
        return visible.filter { selectedIDs.contains($0.id) }
            + store.tracks.filter { selectedIDs.contains($0.id) && !visibleIDs.contains($0.id) }
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            if selectedAlbum != nil {
                Button { navigateBack() } label: {
                    Label(String(localized: "所有专辑"), systemImage: "chevron.left").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(Sunset.accent(scheme))
            }
            if let album = albumContents.first {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        CoverArt(track: album, repository: store.repository).frame(width: 220, height: 220)
                            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6).accessibilityHidden(true)
                        albumHeading(album).frame(minWidth: 250)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        CoverArt(track: album, repository: store.repository).frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6).frame(maxWidth: .infinity).accessibilityHidden(true)
                        albumHeading(album)
                    }
                }
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center))
                layout {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(searchTerm.isEmpty ? collectionTitle : String(localized: "搜索结果")).font(.system(.largeTitle, design: .serif, weight: .medium)).tracking(-0.5)
                        Text(librarySummary).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
                    }
                    #if os(macOS)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if section != .albums && !store.tracks.isEmpty && !selecting { selectionButton }
                    #endif
                }
            }
        }
    }
    private func albumHeading(_ album: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(album.album).font(.system(.largeTitle, design: .serif, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text(album.albumArtist).font(.subheadline).foregroundStyle(.secondary)
            Text(String(localized: "\(albumContents.count) 首 · \(playlistDuration(albumContents))")).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(String(localized: "播放全部"), systemImage: "play.fill") { playAll(filtered) }
                    .buttonStyle(AlbumActionButtonStyle(prominent: true))
                    .disabled(filtered.isEmpty || store.isManaging)
                    .help(String(localized: "播放全部"))
                Button(String(localized: "随机播放"), systemImage: "shuffle") { playAll(filtered, shuffled: true) }
                    .buttonStyle(AlbumActionButtonStyle())
                    .disabled(filtered.isEmpty || store.isManaging)
                    .help(String(localized: "随机播放"))
                albumFavoriteButton(album)
                    .buttonStyle(AlbumActionButtonStyle())
            }
            .labelStyle(.iconOnly)
            .padding(.top, 12)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func albumFavoriteButton(_ album: Track) -> some View {
        let songs = store.tracks.filter { $0.albumKey == album.albumKey }
        let favorite = !songs.isEmpty && songs.allSatisfy(\.favorite)
        return Button(favorite ? String(localized: "取消收藏专辑") : String(localized: "收藏专辑"), systemImage: favorite ? "heart.fill" : "heart") {
            store.toggleAlbumFavorite(album.albumKey)
        }
        .disabled(store.isBusy)
        .accessibilityValue(favorite ? String(localized: "已收藏") : String(localized: "未完整收藏"))
        .help(favorite ? String(localized: "取消收藏专辑") : String(localized: "收藏专辑"))
    }
    private var collectionTitle: String {
        switch section {
        case .albums: return String(localized: "唱片收藏")
        case .songs: return String(localized: "所有歌曲")
        case .artists: return String(localized: "艺术家")
        case .favorites: return String(localized: "心头所爱")
        case .playlists: return String(localized: "我的歌单")
        }
    }
    private var selectionButton: some View {
        Button(String(localized: "选择"), action: beginSelection)
            .buttonStyle(StudioButtonStyle()).disabled(store.isBusy)
    }
    private func beginSelection() {
        selecting = true
        selectedIDs.removeAll()
        searchFocused = false
    }
    private var librarySummary: String {
        if !searchTerm.isEmpty { return String(localized: "找到 \(filtered.count) 首歌曲") }
        switch section {
        case .albums: return String(localized: "\(albums.count) 张专辑 · \(filtered.count) 首歌曲")
        case .artists: return String(localized: "\(Set(filtered.map(\.artist)).count) 位艺术家 · \(filtered.count) 首歌曲")
        case .favorites: return String(localized: "\(filtered.count) 首喜欢的音乐")
        default: return String(localized: "\(filtered.count) 首歌曲 · 保存在本机")
        }
    }

    @ViewBuilder private var libraryContent: some View {
        if store.isLoading {
            ProgressView(String(localized: "正在读取音乐库…")).frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if store.tracks.isEmpty {
            VStack(spacing: 0) {
                StudioEmptyState(symbol: "opticaldisc", title: String(localized: "为喜欢的音乐，留一个位置"), detail: String(localized: "从一首歌、一张专辑开始。导入你的音乐，慢慢收藏，随时聆听。"))
                Button { importing = true } label: { Label(String(localized: "导入音乐"), systemImage: "plus") }
                    .buttonStyle(StudioButtonStyle(prominent: true)).disabled(store.isBusy)
                Text("FLAC / ALAC / MP3 / AAC / WAV / AIFF")
                    .font(.caption2.monospaced()).foregroundStyle(Sunset.secondary(scheme)).padding(.top, 24)
                #if os(iOS)
                Text(String(localized: "也可以通过 Mac 的 Finder 文件共享传入音乐。"))
                    .font(.caption).foregroundStyle(Sunset.secondary(scheme)).multilineTextAlignment(.center).padding(.top, 12)
                #endif
            }.padding(.vertical, 44).frame(maxWidth: .infinity)
        } else if filtered.isEmpty {
            VStack(spacing: 0) {
                StudioEmptyState(symbol: searchTerm.isEmpty ? "heart" : "magnifyingglass", title: searchTerm.isEmpty ? String(localized: "还没有收藏") : String(localized: "没有找到音乐"), detail: searchTerm.isEmpty ? String(localized: "在歌曲菜单中点“收藏”，喜欢的音乐会集中保存在这里。") : String(localized: "没有与“\(searchTerm)”匹配的歌曲。试试歌曲、专辑或艺术家名称。"))
                if !searchTerm.isEmpty {
                    Button(String(localized: "清除搜索")) { query = "" }.buttonStyle(StudioButtonStyle())
                } else {
                    Button(String(localized: "浏览歌曲")) { switchSection(.songs) }.buttonStyle(StudioButtonStyle())
                }
            }.padding(.vertical, 24).frame(maxWidth: .infinity)
        } else if section == .albums && selectedAlbum == nil && searchTerm.isEmpty && !selecting {
            if let first = featuredAlbum.first {
                CollectionFeatureView(track: first, repository: store.repository,
                    summary: String(localized: "\(featuredAlbum.count) 首歌曲 · \(playlistDuration(featuredAlbum))"),
                    isCurrent: store.current?.albumKey == first.albumKey, isPlaying: store.isPlaying, disabled: store.isManaging,
                    play: {
                        if store.current?.albumKey == first.albumKey {
                            if !store.isPlaying { store.resume() }
                            showingPlayer = true
                        } else { playAll(featuredAlbum) }
                    }, browse: { openAlbum(first.albumKey) })
            }
            albumGrid
        } else if section == .artists && selectedAlbum == nil && searchTerm.isEmpty && !selecting {
            #if os(iOS)
            HStack(spacing: 14) {
                Text(String(localized: "全部艺术家")).font(.system(.title3, design: .serif, weight: .medium))
                Rectangle().fill(Sunset.stroke(scheme).opacity(0.6)).frame(height: 1)
                listActionsMenu(groupedByArtist: true)
            }
            #endif
            artistList
        } else {
            if !selecting && selectedAlbum == nil { playbackActions }
            songList(filtered)
        }
    }

    private var featuredAlbum: [Track] {
        if let current = store.current, let album = albums.first(where: { $0.first?.albumKey == current.albumKey }) { return album }
        return albums.first ?? []
    }

    private var albumGrid: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Text(String(localized: "全部专辑")).font(.system(.title3, design: .serif, weight: .medium))
                Rectangle().fill(Sunset.stroke(scheme).opacity(0.6)).frame(height: 1)
                Text("\(albums.count)").font(.caption.monospacedDigit()).foregroundStyle(Sunset.secondary(scheme))
            }.padding(.top, 8)
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 30) {
                ForEach(albums, id: \.first!.albumKey) { album in
                    Button { openAlbum(album[0].albumKey) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            CoverArt(track: album[0], repository: store.repository)
                                .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.10), radius: 8, x: 0, y: 5)
                                .accessibilityHidden(true)
                            Text(album[0].album).font(.system(.headline, design: .serif, weight: .medium)).lineLimit(2).padding(.top, 3)
                            Text(album[0].albumArtist).font(.subheadline).foregroundStyle(Sunset.secondary(scheme)).lineLimit(1)
                            Text(String(localized: "\(album.count) 首歌曲")).font(.caption).foregroundStyle(Sunset.secondary(scheme))
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(String(localized: "专辑 \(album[0].album)"))
                    .contextMenu {
                        albumFavoriteButton(album[0])
                        Button(String(localized: "播放全部"), systemImage: "play.fill") { playAll(album) }
                        Button(String(localized: "下一首播放"), systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext(album) }
                        Button(String(localized: "添加到歌单"), systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: album) }.disabled(store.isBusy)
                    }
                }
            }
        }
    }

    private var artistList: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(Set(filtered.map(\.artist))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { artist in
                let songs = filtered.filter { $0.artist == artist }
                DisclosureGroup {
                    songList(songs).padding(.top, 12)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "person.fill").font(.title2).foregroundStyle(Sunset.accent(scheme))
                            .frame(width: 52, height: 52).background(Sunset.panel(scheme), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(artist).font(.headline).foregroundStyle(.primary)
                            Text(String(localized: "\(songs.count) 首歌曲")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Divider().opacity(0.5)
            }
        }
    }

    private var playbackActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { playButtons; Spacer(minLength: 0); listActions }
            VStack(alignment: .leading, spacing: 8) {
                playButtons
                #if os(iOS)
                HStack { Spacer(minLength: 0); listActions }
                #else
                listActions
                #endif
            }
        }
    }
    @ViewBuilder private var listActions: some View {
        #if os(iOS)
        if section == .songs || section == .artists || section == .favorites {
            listActionsMenu()
        } else {
            sortMenu
        }
        #else
        sortMenu
        #endif
    }
    private func listActionsMenu(groupedByArtist: Bool = false) -> some View {
        Menu {
            Button(String(localized: "选择歌曲"), systemImage: "checkmark.circle", action: beginSelection)
                .disabled(store.isBusy)
            Divider()
            if groupedByArtist {
                Button(String(localized: "播放全部"), systemImage: "play.fill") { playAll(filtered) }
                    .disabled(store.isManaging)
                Button(String(localized: "随机播放"), systemImage: "shuffle") { playAll(filtered, shuffled: true) }
                    .disabled(store.isManaging)
            } else {
                Picker(String(localized: "排序方式"), selection: $songSort) {
                    ForEach(LibrarySongSort.allCases) { order in Text(order.title).tag(order) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Sunset.secondary(scheme))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(String(localized: "列表操作"))
    }
    private var playButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { playAll(filtered) } label: { Label(String(localized: "播放全部"), systemImage: "play.fill").frame(minHeight: 28) }
                .buttonStyle(StudioButtonStyle(prominent: true))
            Button { playAll(filtered, shuffled: true) } label: { Label(String(localized: "随机播放"), systemImage: "shuffle").frame(minHeight: 28) }
                .buttonStyle(StudioButtonStyle())
        }.font(.subheadline.weight(.semibold)).disabled(store.isManaging)
    }
    @ViewBuilder private var sortMenu: some View {
        if selectedAlbum == nil {
            Menu {
                Picker(String(localized: "排序方式"), selection: $songSort) {
                    ForEach(LibrarySongSort.allCases) { order in Text(order.title).tag(order) }
                }
            } label: { Label(songSort.title, systemImage: "arrow.up.arrow.down").font(.caption).frame(minHeight: 44) }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel(String(localized: "排序：\(songSort.title)"))
        }
    }
    private func playAll(_ tracks: [Track], shuffled: Bool = false) {
        guard let first = shuffled ? tracks.randomElement() : tracks.first else { return }
        searchFocused = false
        store.setShuffle(shuffled)
        store.play(first, context: tracks)
    }

    private func beginDeletion(_ ids: Set<UUID>) {
        guard !store.isBusy, !ids.isEmpty else { return }
        Task {
            do {
                deletionBytes = try await store.repository.managedBytes(for: ids)
                selectedIDs = ids; confirmDelete = true
            } catch { store.errorMessage = error.localizedDescription }
        }
    }
    private func songList(_ tracks: [Track], allowSelection: Bool = true) -> some View {
        VStack(spacing: 0) {
            #if os(macOS)
            HStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text("#").frame(width: 24)
                    Text(String(localized: "歌曲 / 艺术家")).padding(.leading, 56).frame(maxWidth: .infinity, alignment: .leading)
                    if selectedAlbum == nil { Text(String(localized: "专辑")).frame(width: 140, alignment: .leading) }
                    Text(String(localized: "时长")).frame(width: 40, alignment: .trailing)
                }
                Color.clear.frame(width: 44, height: 1)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Sunset.secondary(scheme))
                .padding(.horizontal, 8).padding(.bottom, 10)
            Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
            #endif
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 8) {
                        Button {
                            if selecting && allowSelection {
                                if selectedIDs.contains(track.id) { selectedIDs.remove(track.id) } else { selectedIDs.insert(track.id) }
                            } else { searchFocused = false; store.play(track, context: tracks) }
                        } label: {
                            HStack(spacing: 12) {
                                if selecting && allowSelection {
                                    Image(systemName: selectedIDs.contains(track.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(Sunset.accent(scheme)).frame(width: 24)
                                } else {
                                    #if os(macOS)
                                    Text(String(format: "%02d", selectedAlbum != nil && track.trackNumber > 0 ? track.trackNumber : index + 1)).font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Sunset.secondary(scheme)).frame(width: 24)
                                    #endif
                                }
                                CoverArt(track: track, repository: store.repository).frame(width: trackCoverSize, height: trackCoverSize).accessibilityHidden(true)
                                    .overlay(alignment: .bottomTrailing) {
                                        if store.current?.id == track.id {
                                            Image(systemName: store.isPlaying ? "waveform" : "pause.fill")
                                                .font(.system(size: 8, weight: .bold)).foregroundStyle(Sunset.paper).padding(4)
                                                .background(Sunset.brand, in: RoundedRectangle(cornerRadius: 3)).offset(x: 3, y: 3)
                                        }
                                    }
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(track.title).font(.subheadline.weight(.medium))
                                            .foregroundStyle(store.current?.id == track.id ? Sunset.accent(scheme) : .primary)
                                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                                        if track.favorite {
                                            Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Sunset.accent(scheme)).accessibilityLabel(String(localized: "已收藏"))
                                        }
                                    }
                                    Text(track.artist).font(.caption).foregroundStyle(Sunset.secondary(scheme)).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                #if os(macOS)
                                if selectedAlbum == nil {
                                    Text(track.album).font(.system(size: 12)).foregroundStyle(Sunset.secondary(scheme))
                                        .lineLimit(1).frame(width: 140, alignment: .leading)
                                }
                                #endif
                                if !dynamicTypeSize.isAccessibilitySize {
                                    Text(playbackTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(Sunset.secondary(scheme)).frame(width: 40, alignment: .trailing)
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel((selecting && allowSelection ? String(localized: "选择 ") : String(localized: "播放 ")) + track.title)
                            .accessibilityValue(selecting && allowSelection ? (selectedIDs.contains(track.id) ? String(localized: "已选择") : String(localized: "未选择")) : store.current?.id == track.id ? (store.isPlaying ? String(localized: "正在播放") : String(localized: "已暂停")) : track.artist)
                        if !selecting || !allowSelection {
                            Menu { songActions(track) } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Sunset.secondary(scheme))
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 44)
                                .accessibilityLabel(String(localized: "歌曲操作 \(track.title)")).accessibilityValue(track.favorite ? String(localized: "已收藏") : "")
                        } else {
                            #if os(macOS)
                            Color.clear.frame(width: 44, height: 44)
                            #endif
                        }
                    }.padding(.horizontal, 8).padding(.vertical, 9)
                        .background(store.current?.id == track.id ? Sunset.accent(scheme).opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu { if allowSelection { songActions(track) } }
                    Rectangle().fill(Sunset.stroke(scheme).opacity(0.4)).frame(height: 1)
                }
            }
        }
    }
    private var trackCoverSize: CGFloat {
        44
    }
    @ViewBuilder private func songActions(_ track: Track) -> some View {
        Button(track.favorite ? String(localized: "取消收藏") : String(localized: "收藏"), systemImage: track.favorite ? "heart.slash" : "heart") { store.toggleFavorite(track) }.disabled(store.isBusy)
        Button(String(localized: "添加到歌单"), systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: [track]) }.disabled(store.isBusy)
        Button(String(localized: "下一首播放"), systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext([track]) }.disabled(store.isBusy)
        Button(String(localized: "稍后播放"), systemImage: "text.badge.plus") { store.appendToQueue([track]) }.disabled(store.isBusy)
        Divider()
        Button(String(localized: "从音乐库删除"), systemImage: "trash", role: .destructive) { beginDeletion([track.id]) }.disabled(store.isBusy)
    }

    private var importResultTitle: String {
        guard let report = store.importReport else { return String(localized: "导入结果") }
        if report.cancelled { return String(localized: "导入已停止") }
        if !report.failures.isEmpty { return report.added > 0 || report.duplicates > 0 ? String(localized: "部分文件未能导入") : String(localized: "未能导入音乐") }
        return report.added == 0 ? String(localized: "音乐已在库中") : String(localized: "导入完成")
    }
    private var importResultSymbol: String {
        guard let report = store.importReport else { return "tray" }
        if report.cancelled { return "pause.circle" }
        return report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle"
    }
    private var importResults: some View {
        VStack(spacing: 0) {
            CollectionSheetHeader(title: String(localized: "导入结果"), close: { store.importReport = nil })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(importResultTitle, systemImage: importResultSymbol).font(.title2.bold()).foregroundStyle(Sunset.accent(scheme))
                    if let report = store.importReport {
                        Text(report.summary)
                        if report.added > 0 { Text(String(localized: "新导入的音乐已保存在本机，可以离线聆听。")).foregroundStyle(.secondary) }
                        if report.cancelled { Text(String(localized: "已完成的歌曲会保留，未完成的文件可以重新导入。")).foregroundStyle(.secondary) }
                        if !report.failures.isEmpty { Text(String(localized: "\(report.failures.count) 个文件未能导入")).font(.headline); ForEach(Array(report.failures.enumerated()), id: \.offset) { _, message in Text(message).font(.caption).textSelection(.enabled) } }
                        if !report.failureItems.isEmpty {
                            Button(String(localized: "重试失败文件"), systemImage: "arrow.clockwise") {
                                let urls = report.failureItems.map { $0.resolvedURL() }
                                store.importReport = nil
                                store.importFiles(urls)
                            }.buttonStyle(StudioButtonStyle()).disabled(store.isBusy)
                        }
                        Button(String(localized: "查看导入记录")) { managementTab = 1; openManagementAfterReport = true; store.importReport = nil }
                            .buttonStyle(StudioButtonStyle())
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea())
        .tint(Sunset.accent(scheme))
        #if os(macOS)
        .frame(width: 480, height: 360)
        #endif
    }
}

private struct AlbumActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 52, height: 52)
            .foregroundStyle(prominent ? Sunset.paper : Sunset.accent(scheme))
            .background(prominent ? Sunset.brand : Sunset.panel(scheme), in: Circle())
            .contentShape(Circle())
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}
