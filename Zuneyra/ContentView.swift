import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: LibrarySection = .albums
    @State private var query = ""
    @State private var songSort: LibrarySongSort = .recent
    @FocusState private var searchFocused: Bool
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
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 145, maximum: 300), spacing: 20)]
    }

    var body: some View {
        @Bindable var store = store
        Group {
            #if os(macOS)
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 25) {
                    Label("Zuneyra", systemImage: "waveform").font(.system(size: 24, weight: .heavy)).foregroundStyle(Sunset.accent(scheme)).padding(.horizontal, 12).padding(.top, 22)
                    Text("音乐库").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                    ForEach(LibrarySection.allCases) { item in
                        Button { switchSection(item) } label: {
                            Label(item.rawValue, systemImage: item.icon).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(section == item ? Sunset.coral : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(section == item ? .white : .primary)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Label("音乐已保存在本机", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary).padding(12)
                }.padding(12).background(Sunset.panel(scheme)).navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 250)
            } detail: { navigationContent }
            #else
            navigationContent
            #endif
        }
        .tint(Sunset.accent(scheme))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let current = store.current {
                MiniPlayerView(track: current, openPlayer: { searchFocused = false; showingPlayer = true }, openQueue: { showingQueue = true })
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): store.importFiles(urls); case .failure(let error): store.errorMessage = error.localizedDescription }
        }
        .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil && !showingManagement && playlistAddRequest == nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("好") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .alert("操作结果", isPresented: Binding(get: { store.managementMessage != nil && !showingManagement }, set: { if !$0 { store.managementMessage = nil } })) {
            Button("好") { store.managementMessage = nil }
        } message: { Text(store.managementMessage ?? "") }
        .alert("删除 \(selectedIDs.count) 首歌曲？", isPresented: $confirmDelete) {
            Button("删除音频副本", role: .destructive) {
                let ids = selectedIDs
                Task { if await store.deleteTracks(ids) { selectedIDs.removeAll(); selecting = false } }
            }.disabled(store.isBusy)
            Button("取消", role: .cancel) { }
        } message: {
            Text("将从音乐库、收藏及所有歌单中移除所选歌曲，并删除约 \(StorageUsage.formatted(deletionBytes)) 的本机音频副本。原位置和 Finder 传入文件保留。若包含正在播放的歌曲，播放会停止。此操作不可撤销。")
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
        NavigationStack {
            VStack(spacing: 0) {
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
                        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                        .frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: section) { _, _ in scroll.scrollTo("libraryTop", anchor: .top) }
                    .onChange(of: selectedAlbum) { _, _ in scroll.scrollTo("libraryTop", anchor: .top) }
                }
            }
            .background(Sunset.background(scheme))
            .navigationTitle("Zuneyra")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("播放队列", systemImage: "list.bullet") { showingQueue = true }
                        .accessibilityIdentifier("queueToolbar")
                }
                ToolbarItem(placement: .automatic) {
                    Button("音乐库管理", systemImage: "internaldrive") { managementTab = 0; showingManagement = true }
                        .accessibilityIdentifier("libraryManagement")
                }
                ToolbarItem(placement: .primaryAction) {
                    #if os(iOS)
                    Menu {
                        Button("选择文件或文件夹", systemImage: "folder") { importing = true }
                        Button("导入电脑传入的音乐", systemImage: "cable.connector") { store.scanSharedDocuments() }
                    } label: { Label("导入音乐", systemImage: "plus") }
                    .disabled(store.isBusy).accessibilityIdentifier("importMusic")
                    #else
                    Button("导入音乐", systemImage: "plus") { importing = true }
                        .disabled(store.isBusy).accessibilityIdentifier("importMusic")
                    #endif
                }
            }
        }
    }

    private func switchSection(_ item: LibrarySection) {
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
            TextField(section == .playlists ? "搜索歌单" : selectedAlbum == nil ? "歌曲、专辑、艺术家" : "搜索此专辑", text: $query)
                .textFieldStyle(.plain).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search)
                .onSubmit { searchFocused = false }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(section == .playlists ? "搜索歌单" : selectedAlbum == nil ? "搜索音乐库" : "搜索此专辑")
                .accessibilityIdentifier("librarySearchField")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0).frame(minHeight: 48)
        .background(Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibrarySection.allCases) { item in
                    Button { switchSection(item) } label: {
                        Text(item == .favorites ? "收藏" : item.rawValue)
                            .font(.subheadline.weight(section == item ? .semibold : .medium))
                            .fixedSize().padding(.horizontal, 15).frame(minHeight: 44)
                            .background(section == item ? Sunset.coral : .clear, in: Capsule())
                            .foregroundStyle(section == item ? .white : .primary)
                    }
                    .buttonStyle(.plain).accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }.padding(.horizontal, 20)
        }.padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var importProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(store.importProgress).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button("取消") { store.cancelImport() }.font(.subheadline).frame(minHeight: 44)
        }.padding(.horizontal, 20).padding(.vertical, 4)
            .background(Sunset.panel(scheme))
            .accessibilityElement(children: .contain)
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
            Text(notice).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button { store.playlistNotice = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("关闭歌单提示")
        }.foregroundStyle(Sunset.accent(scheme)).padding(.leading, 20).padding(.trailing, 8)
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("已选 \(selectedIDs.count) 首").font(.subheadline.weight(.semibold))
                Spacer()
                Button(selectedIDs.isSuperset(of: Set(filtered.map(\.id))) && !filtered.isEmpty ? "取消全选" : "全选当前结果") {
                    let visible = Set(filtered.map(\.id))
                    if selectedIDs.isSuperset(of: visible) { selectedIDs.subtract(visible) }
                    else { selectedIDs.formUnion(visible) }
                }.font(.subheadline).frame(minHeight: 44)
            }
            HStack {
                Menu {
                    Button("添加到歌单", systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: selectedTracks) }
                    Button("下一首播放") { store.insertNext(selectedTracks) }
                    Button("稍后播放") { store.appendToQueue(selectedTracks) }
                } label: { Label("更多操作", systemImage: "ellipsis.circle").frame(minHeight: 44) }
                .disabled(selectedIDs.isEmpty || store.isBusy).accessibilityIdentifier("selectedTracksActions")
                Spacer()
                Button("删除", systemImage: "trash", role: .destructive) { beginDeletion(selectedIDs) }
                    .frame(minHeight: 44).disabled(selectedIDs.isEmpty || store.isBusy)
                    .accessibilityIdentifier("deleteSelectedTracks")
                Button("完成") { selecting = false; selectedIDs.removeAll() }.frame(minHeight: 44)
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
                Button { selectedAlbum = nil; query = ""; searchFocused = false } label: {
                    Label("所有专辑", systemImage: "chevron.left").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(Sunset.accent(scheme))
            }
            if let album = albumContents.first {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        CoverArt(track: album, repository: store.repository).frame(width: 104, height: 104).accessibilityHidden(true)
                        albumHeading(album)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        CoverArt(track: album, repository: store.repository).frame(width: 140, height: 140).accessibilityHidden(true)
                        albumHeading(album)
                    }
                }
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center))
                layout {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(searchTerm.isEmpty ? section.rawValue : "搜索结果").font(.largeTitle.bold())
                        Text(librarySummary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if !store.tracks.isEmpty && !selecting { selectionButton }
                }
            }
        }
    }
    private func albumHeading(_ album: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(album.album).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Text(album.albumArtist).font(.subheadline).foregroundStyle(.secondary)
            Text("\(albumContents.count) 首 · \(playlistDuration(albumContents))").font(.footnote).foregroundStyle(.secondary)
            if !selecting { selectionButton }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var selectionButton: some View {
        Button("选择") { selecting = true; selectedIDs.removeAll(); searchFocused = false }
            .font(.subheadline).frame(minWidth: 44, minHeight: 44)
            .disabled(store.isBusy).accessibilityIdentifier("selectTracks")
    }
    private var librarySummary: String {
        if !searchTerm.isEmpty { return "找到 \(filtered.count) 首歌曲" }
        switch section {
        case .albums: return "\(albums.count) 张专辑 · \(filtered.count) 首歌曲"
        case .artists: return "\(Set(filtered.map(\.artist)).count) 位艺术家 · \(filtered.count) 首歌曲"
        case .favorites: return "\(filtered.count) 首喜欢的音乐"
        default: return "\(filtered.count) 首歌曲 · 保存在本机"
        }
    }

    @ViewBuilder private var libraryContent: some View {
        if store.isLoading {
            ProgressView("正在读取音乐库…").frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if store.tracks.isEmpty {
            ContentUnavailableView {
                Label("让喜欢的音乐，随身同行", systemImage: "music.note.house")
            } description: {
                Text("从“文件”中选择歌曲或整个文件夹，\n导入后即可离线聆听，无需账号。")
            } actions: {
                Button("导入音乐", systemImage: "plus") { importing = true }
                    .buttonStyle(.borderedProminent).tint(Sunset.coral).controlSize(.large).disabled(store.isBusy)
            }.padding(.vertical, 20)
            VStack(alignment: .leading, spacing: 12) {
                Text("支持 FLAC、ALAC、MP3、AAC、WAV、AIFF").font(.footnote)
                #if os(iOS)
                Label("从电脑导入：连接 Mac，在 Finder → iPhone → 文件 → Zuneyra 中拖入音乐，再打开本应用。", systemImage: "cable.connector")
                    .font(.footnote)
                #endif
            }.foregroundStyle(.secondary).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 16))
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label(searchTerm.isEmpty ? "收藏你的第一首歌" : "没有找到音乐", systemImage: searchTerm.isEmpty ? "heart" : "magnifyingglass")
            } description: {
                Text(searchTerm.isEmpty ? "在歌曲的更多菜单中点“收藏”，喜欢的音乐就会出现在这里。" : "没有与“\(searchTerm)”匹配的歌曲。试试歌曲、专辑或艺术家名称。")
            } actions: {
                if !searchTerm.isEmpty {
                    Button("清除搜索") { query = "" }.buttonStyle(.bordered)
                } else {
                    Button("浏览歌曲") { switchSection(.songs) }.buttonStyle(.bordered)
                }
            }
        } else if section == .albums && selectedAlbum == nil && searchTerm.isEmpty && !selecting {
            albumGrid
        } else if section == .artists && selectedAlbum == nil && searchTerm.isEmpty && !selecting {
            artistList
        } else {
            if !selecting { playbackActions }
            songList(filtered)
        }
    }

    private var albumGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 26) {
            ForEach(albums, id: \.first!.albumKey) { album in
                Button { selectedAlbum = album[0].albumKey } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        CoverArt(track: album[0], repository: store.repository).accessibilityHidden(true)
                        Text(album[0].album).font(.headline).lineLimit(2)
                        Text(album[0].albumArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(album.count) 首歌曲").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("专辑 \(album[0].album)")
                .contextMenu {
                    Button("播放全部", systemImage: "play.fill") { playAll(album) }
                    Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext(album) }
                    Button("添加到歌单", systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: album) }.disabled(store.isBusy)
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
                            Text("\(songs.count) 首歌曲").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                Divider().opacity(0.5)
            }
        }
    }

    private var playbackActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { playButtons; Spacer(minLength: 0); sortMenu }
            VStack(alignment: .leading, spacing: 8) { playButtons; sortMenu }
        }
    }
    private var playButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { playAll(filtered) } label: { Label("播放全部", systemImage: "play.fill").frame(minHeight: 28) }
                .buttonStyle(.borderedProminent).tint(Sunset.coral)
            Button { playAll(filtered, shuffled: true) } label: { Label("随机播放", systemImage: "shuffle").frame(minHeight: 28) }
                .buttonStyle(.bordered)
        }.font(.subheadline.weight(.semibold)).disabled(store.isManaging)
    }
    @ViewBuilder private var sortMenu: some View {
        if selectedAlbum == nil {
            Menu {
                Picker("排序方式", selection: $songSort) {
                    ForEach(LibrarySongSort.allCases) { order in Text(order.title).tag(order) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 44, height: 44) }
            .accessibilityLabel("排序：\(songSort.title)").accessibilityIdentifier("librarySort")
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
        LazyVStack(spacing: 0) {
            ForEach(tracks) { track in
                HStack(spacing: 8) {
                    Button {
                        if selecting && allowSelection {
                            if selectedIDs.contains(track.id) { selectedIDs.remove(track.id) } else { selectedIDs.insert(track.id) }
                        } else { searchFocused = false; store.play(track, context: tracks) }
                    } label: {
                        HStack(spacing: 12) {
                            if selecting && allowSelection {
                                Image(systemName: selectedIDs.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Sunset.accent(scheme)).frame(width: 26)
                            }
                            CoverArt(track: track, repository: store.repository).frame(width: 48, height: 48).accessibilityHidden(true)
                                .overlay(alignment: .bottomTrailing) {
                                    if store.current?.id == track.id {
                                        Image(systemName: store.isPlaying ? "waveform" : "pause.fill")
                                            .font(.caption2.bold()).foregroundStyle(.white).padding(5)
                                            .background(Sunset.coral, in: Circle()).offset(x: 4, y: 4)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(track.title).font(.body.weight(.medium))
                                    .foregroundStyle(store.current?.id == track.id ? Sunset.accent(scheme) : .primary)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                                Text(track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text(playbackTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("play-track-\(track.id)")
                        .accessibilityLabel((selecting && allowSelection ? "选择 " : "播放 ") + track.title)
                        .accessibilityValue(selecting && allowSelection ? (selectedIDs.contains(track.id) ? "已选择" : "未选择") : store.current?.id == track.id ? (store.isPlaying ? "正在播放" : "已暂停") : track.artist)
                    if !selecting || !allowSelection {
                        if track.favorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Sunset.accent(scheme)).accessibilityLabel("已收藏") }
                        Menu { songActions(track) } label: {
                            Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 44, height: 48).contentShape(Rectangle())
                        }.menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel("歌曲操作 \(track.title)").accessibilityIdentifier("trackActions-\(track.id)")
                    }
                }.padding(.vertical, 10)
                    .contextMenu { if allowSelection { songActions(track) } }
                Divider().opacity(0.5).padding(.leading, selecting ? 86 : 60)
            }
        }
    }
    @ViewBuilder private func songActions(_ track: Track) -> some View {
        Button(track.favorite ? "取消收藏" : "收藏", systemImage: track.favorite ? "heart.slash" : "heart") { store.toggleFavorite(track) }.disabled(store.isBusy)
        Button("添加到歌单", systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: [track]) }.disabled(store.isBusy)
        Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext([track]) }.disabled(store.isBusy)
        Button("稍后播放", systemImage: "text.badge.plus") { store.appendToQueue([track]) }.disabled(store.isBusy)
        Divider()
        Button("从音乐库删除", systemImage: "trash", role: .destructive) { beginDeletion([track.id]) }.disabled(store.isBusy)
    }

    private var importResultTitle: String {
        guard let report = store.importReport else { return "导入结果" }
        if report.cancelled { return "导入已停止" }
        if !report.failures.isEmpty { return report.added > 0 || report.duplicates > 0 ? "部分文件未能导入" : "未能导入音乐" }
        return report.added == 0 ? "音乐已在库中" : "导入完成"
    }
    private var importResultSymbol: String {
        guard let report = store.importReport else { return "tray" }
        if report.cancelled { return "pause.circle" }
        return report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle"
    }
    private var importResults: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(importResultTitle, systemImage: importResultSymbol).font(.title2.bold()).foregroundStyle(Sunset.accent(scheme))
                    if let report = store.importReport {
                        Text(report.summary)
                        if report.added > 0 { Text("新导入的音乐已保存在本机，可以离线聆听。").foregroundStyle(.secondary) }
                        if report.cancelled { Text("已完成的歌曲会保留，未完成的文件可以重新导入。").foregroundStyle(.secondary) }
                        if !report.failures.isEmpty { Text("\(report.failures.count) 个文件未能导入").font(.headline); ForEach(Array(report.failures.enumerated()), id: \.offset) { _, message in Text(message).font(.caption).textSelection(.enabled) } }
                        if !report.failureItems.isEmpty {
                            Button("重试失败文件", systemImage: "arrow.clockwise") {
                                let urls = report.failureItems.map { $0.resolvedURL() }
                                store.importReport = nil
                                store.importFiles(urls)
                            }.disabled(store.isBusy)
                        }
                        Button("查看导入记录") { managementTab = 1; openManagementAfterReport = true; store.importReport = nil }
                    }
                }.padding(24)
            }.background(Sunset.background(scheme)).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { store.importReport = nil } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 360)
        #endif
    }
}
