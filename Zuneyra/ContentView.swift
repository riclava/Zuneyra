import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var visibleLibraryItems: [LibrarySection: String] = [:]
    @State private var availableSize: CGSize = .zero
    @State private var section: LibrarySection = .albums
    // Rendering context for neighboring pages; interaction still belongs to the selected page.
    private var previewSection: LibrarySection?
    private var preparedTracks: [Track]?
    private var preparedAlbums: [[Track]]?
    private var renderedSection: LibrarySection { previewSection ?? section }
    private var renderedQuery: String { previewSection == nil ? query : "" }
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

    enum LibraryDragAxis {
        case horizontal, vertical

        static func resolve(locked: Self?, horizontal: CGFloat, vertical: CGFloat, canPage: Bool) -> Self {
            if let locked { return locked }
            return canPage && abs(horizontal) > abs(vertical) * 2 ? .horizontal : .vertical
        }
    }

    enum LibrarySection: String, CaseIterable, Identifiable {
        case albums = "专辑", songs = "歌曲", artists = "艺术家", favorites = "我的收藏", playlists = "歌单"
        var id: String { rawValue }

        /// Reserve both edges for history navigation; only deliberate horizontal swipes page categories.
        func destinationForSwipe(horizontal: CGFloat, vertical: CGFloat, startX: CGFloat, width: CGFloat) -> Self? {
            guard width > 48, startX > 24, startX < width - 24,
                  abs(horizontal) >= 64, abs(horizontal) > abs(vertical) * 2,
                  let index = Self.allCases.firstIndex(of: self) else { return nil }
            let next = index + (horizontal < 0 ? 1 : -1)
            return Self.allCases.indices.contains(next) ? Self.allCases[next] : nil
        }
        func destinationForRelease(horizontal: CGFloat, projected: CGFloat, startX: CGFloat, width: CGFloat) -> Self? {
            // Allow a deliberate short flick, but ignore tiny taps or a projection in the opposite direction.
            let sameDirection = horizontal * projected > 0
            let travel = abs(horizontal) >= 20 && sameDirection && abs(projected) > abs(horizontal) ? projected : horizontal
            return destinationForSwipe(horizontal: travel, vertical: 0, startX: startX, width: width)
        }
        func offsetForSwipe(horizontal: CGFloat, vertical: CGFloat, startX: CGFloat, width: CGFloat) -> CGFloat {
            guard width > 48, startX > 24, startX < width - 24,
                  abs(horizontal) > abs(vertical) * 2 else { return 0 }
            let hasNeighbor = destinationForSwipe(horizontal: horizontal < 0 ? -64 : 64,
                                                  vertical: 0, startX: startX, width: width) != nil
            let distance = min(abs(horizontal), width)
            // A little resistance communicates the boundary without wrapping categories.
            return (horizontal < 0 ? -1 : 1) * (hasNeighbor ? distance : min(28, distance * 0.15))
        }
        func distance(from other: Self) -> Int {
            (Self.allCases.firstIndex(of: self) ?? 0) - (Self.allCases.firstIndex(of: other) ?? 0)
        }
        var title: String { NSLocalizedString(rawValue, comment: "Library category") }
        var icon: String { switch self { case .albums: "opticaldisc"; case .songs: "music.note"; case .artists: "person.2"; case .favorites: "heart"; case .playlists: "music.note.list" } }
    }
    private var searchTerm: String { renderedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var albumContents: [Track] {
        LibraryPresentation.albumTracks(store.tracks.filter { $0.albumKey == selectedAlbum })
    }
    private var filtered: [Track] {
        if let preparedTracks { return preparedTracks }
        let matches = store.tracks.filter { track in
            (renderedSection != .favorites || track.favorite)
                && (selectedAlbum == nil || track.albumKey == selectedAlbum)
                && LibraryPresentation.matches(track, query: renderedQuery)
        }
        return selectedAlbum == nil ? songSort.apply(to: matches) : LibraryPresentation.albumTracks(matches)
    }
    private var albums: [[Track]] {
        if let preparedAlbums { return preparedAlbums }
        return Dictionary(grouping: filtered, by: \.albumKey).values
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

    private var usesSidebar: Bool {
        #if os(macOS)
        true
        #else
        AdaptiveLayout(size: availableSize, accessibility: dynamicTypeSize.isAccessibilitySize).showsSidebar
        #endif
    }

    private var compactFeature: Bool {
        #if os(iOS)
        !dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    var body: some View {
        @Bindable var store = store
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if usesSidebar {
                        sidebar.frame(width: 210)
                        Rectangle().fill(Sunset.stroke(scheme)).frame(width: 1)
                    }
                    navigationContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let current = store.current {
                    MiniPlayerView(track: current, expanded: AdaptiveLayout(size: availableSize, accessibility: dynamicTypeSize.isAccessibilitySize).expandedMiniPlayer, openPlayer: { searchFocused = false; showingPlayer = true }, openQueue: { showingQueue = true })
                }
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                availableSize = size
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
        #if os(iOS)
        .fullScreenCover(isPresented: $showingPlayer) { NowPlayingView().environment(store) }
        #else
        .sheet(isPresented: $showingPlayer) { NowPlayingView().environment(store) }
        #endif
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

    private var libraryContentWidth: CGFloat { availableSize.width - (usesSidebar ? 211 : 0) }
    private var canSwipeLibrary: Bool {
        selectedAlbum == nil && !playlistNavigation.canGoBack && !selecting
            && !showingPlayer && !showingQueue && !showingManagement && !importing
            && playlistAddRequest == nil
    }

    private var pagerSections: [LibrarySection] {
        guard selectedAlbum == nil, !selecting else { return [section] }
        return LibrarySection.allCases.filter { abs($0.distance(from: section)) <= 1 }
    }

    private func pageContents(for item: LibrarySection) -> some View {
        var renderer = self
        renderer.previewSection = item == section ? nil : item
        if item != .playlists {
            renderer.preparedTracks = renderer.filtered
            if item == .albums { renderer.preparedAlbums = renderer.albums }
        }
        return renderer.libraryPageContents
    }

    private var libraryPageContents: some View {
        VStack(alignment: .leading, spacing: 24) {
            if renderedSection == .playlists {
                PlaylistLibraryView(query: searchTerm) { id in
                    playlistNavigation.setPath(playlistNavigation.path + [id])
                }
            } else {
                libraryHeader
                libraryContent
            }
        }
        .id("libraryTop")
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
        .frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
    }

    private var navigationContent: some View {
        NavigationStack(path: Binding(get: { playlistNavigation.path }, set: { playlistNavigation.setPath($0) })) {
            VStack(spacing: 0) {
                workspaceBar
                searchField
                #if os(iOS)
                if !usesSidebar { sectionPicker }
                #endif
                if store.isImporting { importProgress }
                if let notice = store.playlistNotice { noticeBanner(notice) }
                if selecting { selectionBar }
                LibraryCategoryPager(
                    selection: section, items: pagerSections, width: libraryContentWidth,
                    enabled: canSwipeLibrary, select: switchSection
                ) { item in
                    ScrollViewReader { scroll in
                        ScrollView { pageContents(for: item) }
                            .guardActionsWhileScrolling()
                            .scrollPosition(id: Binding(
                                get: { visibleLibraryItems[item] },
                                set: { visibleLibraryItems[item] = $0 }
                            ), anchor: .top)
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: selectedAlbum) { _, _ in
                                if item == section { scroll.scrollTo("libraryTop", anchor: .top) }
                            }
                    }
                    .background(Sunset.background(scheme))
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
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StudioMark().foregroundStyle(Sunset.accent(scheme))
                Text("Zuneyra").font(.system(size: 27, weight: .medium, design: .serif)).tracking(-1)
            }.padding(.horizontal, 16).padding(.top, 23).padding(.bottom, 30)
            Text(String(localized: "私人收藏")).font(.system(size: 9, weight: .medium)).tracking(1.8).foregroundStyle(Sunset.secondary(scheme))
                .padding(.horizontal, 22).padding(.bottom, 18)
            VStack(spacing: 4) {
                ForEach(LibrarySection.allCases) { item in
                    SwipeSafeButton { switchSection(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 14)).frame(width: 20)
                            Text(item.title).font(.system(size: 14, weight: section == item ? .medium : .regular))
                            Spacer(minLength: 4)
                            Text(sectionCount(item)).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Sunset.secondary(scheme))
                        }.padding(.horizontal, 12).frame(minHeight: 44)
                            .foregroundStyle(section == item ? Sunset.accent(scheme) : .primary)
                            .background(section == item ? Sunset.accent(scheme).opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(alignment: .leading) {
                                if section == item { Circle().fill(Sunset.accent(scheme)).frame(width: 4, height: 4) }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).protectLibraryAction().accessibilityAddTraits(section == item ? .isSelected : [])
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
            if usesSidebar {
                Text(String(localized: "你的私人音乐库")).font(.system(.subheadline, design: .serif)).foregroundStyle(Sunset.secondary(scheme))
            } else {
                StudioMark().foregroundStyle(Sunset.accent(scheme))
                Text("Zuneyra").font(.system(.title2, design: .serif, weight: .medium)).tracking(-0.5).lineLimit(1)
            }
            #else
            Text(String(localized: "你的私人音乐库")).font(.system(.subheadline, design: .serif)).foregroundStyle(Sunset.secondary(scheme))
            #endif
            Spacer(minLength: 0)
            SwipeSafeButton { showingQueue = true } label: { Image(systemName: "list.bullet") }
                .buttonStyle(StudioIconButtonStyle()).protectLibraryAction().accessibilityLabel(String(localized: "播放队列")).help(String(localized: "播放队列"))
            SwipeSafeButton { managementTab = 0; showingManagement = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(StudioIconButtonStyle()).protectLibraryAction().accessibilityLabel(String(localized: "音乐库管理")).help(String(localized: "音乐库管理"))
            #if os(iOS)
            Menu {
                Button(String(localized: "选择文件或文件夹"), systemImage: "folder") { importing = true }
                Button(String(localized: "导入电脑传入的音乐"), systemImage: "cable.connector") { store.scanSharedDocuments() }
            } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .menuStyle(.borderlessButton).protectLibraryAction().accessibilityLabel(String(localized: "导入音乐")).disabled(store.isBusy)
            #else
            SwipeSafeButton { importing = true } label: { Label(String(localized: "添加音乐"), systemImage: "plus") }
                .buttonStyle(StudioButtonStyle()).protectLibraryAction().disabled(store.isBusy).padding(.leading, 8)
                .keyboardShortcut("o", modifiers: .command).accessibilityLabel(String(localized: "导入音乐"))
            #endif
        }.font(.subheadline).padding(.horizontal, 24).padding(.vertical, 10)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
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
                SwipeSafeButton { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.buttonStyle(.plain).protectLibraryAction().accessibilityLabel(String(localized: "清除搜索"))
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
        .padding(.horizontal, 24).padding(.top, compactFeature ? 4 : 16).padding(.bottom, 8)
        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }

    private var sectionPicker: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(LibrarySection.allCases) { item in
                        SwipeSafeButton { switchSection(item) } label: {
                            Text(item == .favorites ? String(localized: "收藏分类", defaultValue: "收藏", comment: "Compact navigation tab for the favorites collection, not the Favorite action") : item.title)
                                .font(.subheadline.weight(section == item ? .semibold : .medium))
                                .fixedSize().frame(minHeight: 44)
                                .foregroundStyle(section == item ? Sunset.accent(scheme) : Sunset.secondary(scheme))
                                .overlay(alignment: .bottom) {
                                    if section == item { Rectangle().fill(Sunset.accent(scheme)).frame(height: 2) }
                                }
                        }
                        .id(item)
                        .buttonStyle(.plain).protectLibraryAction().accessibilityLabel(item.title)
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 24)
            }
            .onChange(of: section, initial: true) { _, item in
                scroll.scrollTo(item, anchor: .center)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1) }
        }
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
            SwipeSafeButton { store.playlistNotice = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .buttonStyle(.plain).protectLibraryAction().accessibilityLabel(String(localized: "关闭歌单提示"))
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
                SwipeSafeButton { navigateBack() } label: {
                    Label(String(localized: "所有专辑"), systemImage: "chevron.left").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }.buttonStyle(.plain).protectLibraryAction().foregroundStyle(Sunset.accent(scheme))
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
                    if renderedSection != .albums && !store.tracks.isEmpty && !selecting { selectionButton }
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
                    .buttonStyle(AlbumActionButtonStyle(prominent: true)).protectLibraryAction()
                    .disabled(filtered.isEmpty || store.isManaging)
                    .help(String(localized: "播放全部"))
                Button(String(localized: "随机播放"), systemImage: "shuffle") { playAll(filtered, shuffled: true) }
                    .buttonStyle(AlbumActionButtonStyle()).protectLibraryAction()
                    .disabled(filtered.isEmpty || store.isManaging)
                    .help(String(localized: "随机播放"))
                albumFavoriteButton(album)
                    .buttonStyle(AlbumActionButtonStyle()).protectLibraryAction()
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
        switch renderedSection {
        case .albums: return String(localized: "唱片收藏")
        case .songs: return String(localized: "所有歌曲")
        case .artists: return String(localized: "艺术家")
        case .favorites: return String(localized: "心头所爱")
        case .playlists: return String(localized: "我的歌单")
        }
    }
    private var selectionButton: some View {
        Button(String(localized: "选择"), action: beginSelection)
            .buttonStyle(StudioButtonStyle()).protectLibraryAction().disabled(store.isBusy)
    }
    private func beginSelection() {
        selecting = true
        selectedIDs.removeAll()
        searchFocused = false
    }
    private var librarySummary: String {
        if !searchTerm.isEmpty { return String(localized: "找到 \(filtered.count) 首歌曲") }
        switch renderedSection {
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
                SwipeSafeButton { importing = true } label: { Label(String(localized: "导入音乐"), systemImage: "plus") }
                    .buttonStyle(StudioButtonStyle(prominent: true)).protectLibraryAction().disabled(store.isBusy)
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
                    Button(String(localized: "清除搜索")) { query = "" }.buttonStyle(StudioButtonStyle()).protectLibraryAction()
                } else {
                    Button(String(localized: "浏览歌曲")) { switchSection(.songs) }.buttonStyle(StudioButtonStyle()).protectLibraryAction()
                }
            }.padding(.vertical, 24).frame(maxWidth: .infinity)
        } else if renderedSection == .albums && selectedAlbum == nil && searchTerm.isEmpty && !selecting {
            if let first = featuredAlbum.first {
                CollectionFeatureView(track: first, repository: store.repository,
                    summary: String(localized: "\(featuredAlbum.count) 首歌曲 · \(playlistDuration(featuredAlbum))"),
                    isCurrent: store.current?.albumKey == first.albumKey, isPlaying: store.isPlaying, disabled: store.isManaging,
                    play: {
                        if store.current?.albumKey == first.albumKey {
                            if !store.isPlaying { store.resume() }
                            showingPlayer = true
                        } else { playAll(featuredAlbum) }
                    }, browse: { openAlbum(first.albumKey) }, compact: compactFeature)
            }
            albumGrid
        } else if renderedSection == .artists && selectedAlbum == nil && searchTerm.isEmpty && !selecting {
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
                    SwipeSafeButton { openAlbum(album[0].albumKey) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            CoverArt(track: album[0], repository: store.repository)
                                .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.10), radius: 8, x: 0, y: 5)
                                .accessibilityHidden(true)
                            Text(album[0].album).font(.system(.headline, design: .serif, weight: .medium)).lineLimit(2).padding(.top, 3)
                            Text(album[0].albumArtist).font(.subheadline).foregroundStyle(Sunset.secondary(scheme)).lineLimit(1)
                            Text(String(localized: "\(album.count) 首歌曲")).font(.caption).foregroundStyle(Sunset.secondary(scheme))
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).protectLibraryAction().accessibilityLabel(String(localized: "专辑 \(album[0].album)"))
                    .id("album:" + album[0].albumKey)
                    .contextMenu {
                        albumFavoriteButton(album[0])
                        Button(String(localized: "播放全部"), systemImage: "play.fill") { playAll(album) }
                        Button(String(localized: "下一首播放"), systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext(album) }
                        Button(String(localized: "添加到歌单"), systemImage: "music.note.list") { playlistAddRequest = PlaylistAddRequest(tracks: album) }.disabled(store.isBusy)
                    }
                }
            }.scrollTargetLayout()
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
                .disclosureGroupStyle(SwipeSafeDisclosureStyle())
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
        if renderedSection == .songs || renderedSection == .artists || renderedSection == .favorites {
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
        .menuStyle(.borderlessButton).protectLibraryAction().menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(String(localized: "列表操作"))
    }
    private var playButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            SwipeSafeButton { playAll(filtered) } label: { Label(String(localized: "播放全部"), systemImage: "play.fill").frame(minHeight: 28) }
                .buttonStyle(StudioButtonStyle(prominent: true)).protectLibraryAction()
            SwipeSafeButton { playAll(filtered, shuffled: true) } label: { Label(String(localized: "随机播放"), systemImage: "shuffle").frame(minHeight: 28) }
                .buttonStyle(StudioButtonStyle()).protectLibraryAction()
        }.font(.subheadline.weight(.semibold)).disabled(store.isManaging)
    }
    @ViewBuilder private var sortMenu: some View {
        if selectedAlbum == nil {
            Menu {
                Picker(String(localized: "排序方式"), selection: $songSort) {
                    ForEach(LibrarySongSort.allCases) { order in Text(order.title).tag(order) }
                }
            } label: { Label(songSort.title, systemImage: "arrow.up.arrow.down").font(.caption).frame(minHeight: 44) }
            .menuStyle(.borderlessButton).protectLibraryAction().fixedSize()
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
                        SwipeSafeButton {
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
                        }.buttonStyle(.plain).protectLibraryAction()
                            .accessibilityLabel((selecting && allowSelection ? String(localized: "选择 ") : String(localized: "播放 ")) + track.title)
                            .accessibilityValue(selecting && allowSelection ? (selectedIDs.contains(track.id) ? String(localized: "已选择") : String(localized: "未选择")) : store.current?.id == track.id ? (store.isPlaying ? String(localized: "正在播放") : String(localized: "已暂停")) : track.artist)
                        if !selecting || !allowSelection {
                            Menu { songActions(track) } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Sunset.secondary(scheme))
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.menuStyle(.borderlessButton).protectLibraryAction().menuIndicator(.hidden).frame(width: 44)
                                .accessibilityLabel(String(localized: "歌曲操作 \(track.title)")).accessibilityValue(track.favorite ? String(localized: "已收藏") : "")
                        } else {
                            #if os(macOS)
                            Color.clear.frame(width: 44, height: 44)
                            #endif
                        }
                    }.id("track:" + track.id.uuidString)
                        .padding(.horizontal, 8).padding(.vertical, 9)
                        .background(store.current?.id == track.id ? Sunset.accent(scheme).opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu { if allowSelection { songActions(track) } }
                    Rectangle().fill(Sunset.stroke(scheme).opacity(0.4)).frame(height: 1)
                }
            }.scrollTargetLayout()
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
                            }.buttonStyle(StudioButtonStyle()).protectLibraryAction().disabled(store.isBusy)
                        }
                        Button(String(localized: "查看导入记录")) { managementTab = 1; openManagementAfterReport = true; store.importReport = nil }
                            .buttonStyle(StudioButtonStyle()).protectLibraryAction()
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

/// Gesture updates invalidate only this lightweight container, not the library's filtering/grouping.
/// Page values are built by the parent once per data/navigation update and reused during a drag.
private struct LibraryCategoryPager<Page: View>: View {
    typealias Section = ContentView.LibrarySection
    typealias DragAxis = ContentView.LibraryDragAxis
    let selection: Section
    let items: [Section]
    let width: CGFloat
    let enabled: Bool
    let select: (Section) -> Void
    private let pages: [Page]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var gestureActive = false
    @State private var axis: DragAxis?
    @State private var offset: CGFloat = 0
    @State private var settling = false
    @State private var settlement = UUID()

    init(selection: Section, items: [Section], width: CGFloat, enabled: Bool,
         select: @escaping (Section) -> Void, @ViewBuilder content: (Section) -> Page) {
        self.selection = selection
        self.items = items
        self.width = width
        self.enabled = enabled
        self.select = select
        pages = items.map(content)
    }

    var body: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                pages[index]
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollDisabled(item != selection || axis == .horizontal || settling)
                    .offset(x: CGFloat(item.distance(from: selection)) * width + (reduceMotion ? 0 : offset))
                    .transformEnvironment(\.libraryActionsSuppressed) {
                        $0 = $0 || settling || (gestureActive && axis != nil)
                    }
                    .allowsHitTesting(item == selection)
                    .accessibilityHidden(item != selection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: selection)
        .coordinateSpace(name: "libraryPaging")
        .overlay {
            if settling {
                Color.clear.contentShape(Rectangle()).onTapGesture { }
            }
        }
        #if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("libraryPaging"))
                .updating($gestureActive) { _, active, _ in active = true }
                .onChanged { value in
                    guard enabled, !settling else { return }
                    let insideEdges = value.startLocation.x > 24 && value.startLocation.x < width - 24
                    if axis == nil {
                        axis = DragAxis.resolve(locked: nil, horizontal: value.translation.width,
                                                vertical: value.translation.height, canPage: insideEdges)
                    }
                    guard axis == .horizontal else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        offset = selection.offsetForSwipe(horizontal: value.translation.width, vertical: 0,
                                                          startX: value.startLocation.x, width: width)
                    }
                }
                .onEnded { value in
                    guard enabled, !settling, axis == .horizontal else { reset(); return }
                    let next = selection.destinationForRelease(horizontal: value.translation.width,
                                                              projected: value.predictedEndTranslation.width,
                                                              startX: value.startLocation.x, width: width)
                    finish(at: next)
                }
        )
        .onChange(of: gestureActive) { _, active in
            if !active && !settling { finish(at: nil) }
        }
        #endif
        .onChange(of: selection) { _, _ in reset() }
        .onChange(of: width) { _, _ in reset() }
        .onChange(of: enabled) { _, enabled in if !enabled { reset() } }
    }

    private func finish(at next: Section?) {
        guard axis == .horizontal else { reset(); return }
        let origin = selection
        let token = UUID()
        settlement = token
        settling = true
        let target = next.map { -CGFloat($0.distance(from: origin)) * width } ?? 0
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18), completionCriteria: .logicallyComplete) {
            offset = target
        } completion: {
            guard settlement == token, selection == origin else { return }
            // Rebase once after the pages reach their destination; do not animate a second reset.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if let next { select(next) }
                offset = 0
                axis = nil
                settling = false
            }
        }
    }

    private func reset() {
        settlement = UUID()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
            axis = nil
            settling = false
        }
    }
}
