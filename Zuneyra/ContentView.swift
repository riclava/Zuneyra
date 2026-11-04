import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: LibrarySection = .albums
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedAlbum: String?
    @State private var importing = false
    @State private var showingPlayer = false
    @State private var showingQueue = false

    enum LibrarySection: String, CaseIterable, Identifiable {
        case albums = "专辑", songs = "歌曲", artists = "艺术家", favorites = "我的收藏"
        var id: String { rawValue }
        var icon: String { switch self { case .albums: "opticaldisc"; case .songs: "music.note"; case .artists: "person.2"; case .favorites: "heart" } }
    }
    private var filtered: [Track] {
        store.tracks.filter { track in
            (section != .favorites || track.favorite) && (selectedAlbum == nil || track.albumKey == selectedAlbum) && (query.isEmpty || [track.title, track.artist, track.album].contains { $0.localizedStandardContains(query) })
        }
    }
    private var albums: [[Track]] {
        Dictionary(grouping: filtered, by: \.albumKey).values.map { $0.sorted { $0.trackNumber == $1.trackNumber ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.trackNumber < $1.trackNumber } }.sorted { $0[0].album.localizedStandardCompare($1[0].album) == .orderedAscending }
    }

    var body: some View {
        @Bindable var store = store
        Group {
            #if os(macOS)
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 25) {
                    Label("Zuneyra", systemImage: "waveform").font(.system(size: 24, weight: .heavy)).foregroundStyle(Sunset.coral).padding(.horizontal, 12).padding(.top, 22)
                    Text("音乐库").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                    ForEach(LibrarySection.allCases) { item in
                        Button { section = item; selectedAlbum = nil } label: {
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
        .tint(Sunset.coral)
        .safeAreaInset(edge: .bottom, spacing: 0) { if let current = store.current { miniPlayer(current) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .folder], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): store.importFiles(urls); case .failure(let error): store.errorMessage = error.localizedDescription }
        }
        .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("好") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .sheet(isPresented: $showingPlayer) { fullPlayer }
        .sheet(isPresented: $showingQueue) { queueView }
        .sheet(isPresented: Binding(get: { store.importReport != nil }, set: { if !$0 { store.importReport = nil } })) { importResults }
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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索你的音乐", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("librarySearchField")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("清除搜索")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }
                .padding(12)
                .background(Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24).padding(.vertical, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        #if os(iOS)
                        HStack {
                            ForEach(LibrarySection.allCases) { item in
                                Button { section = item; selectedAlbum = nil } label: { Label(item.rawValue, systemImage: item.icon).font(.caption).labelStyle(.titleOnly).padding(.vertical, 10).frame(maxWidth: .infinity).background(section == item ? Sunset.coral : Sunset.panel(scheme), in: Capsule()).foregroundStyle(section == item ? .white : .primary) }
                            }
                        }.buttonStyle(.plain)
                        #endif
                        if selectedAlbum != nil {
                            Button { selectedAlbum = nil } label: { Label("所有专辑", systemImage: "chevron.left") }.buttonStyle(.plain)
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("YOUR MUSIC, OFFLINE").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Sunset.coral)
                            Text(selectedAlbum == nil ? section.rawValue : filtered.first?.album ?? "专辑").font(.system(size: 32, weight: .bold))
                            Text("\(filtered.count) 首歌曲 · 全部离线可用").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if store.isImporting {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(store.importProgress).font(.subheadline)
                                Spacer()
                                Button("取消") { store.cancelImport() }
                            }.padding().background(Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if store.isLoading { ProgressView("正在读取音乐库…").frame(maxWidth: .infinity).padding(60) }
                        else if store.tracks.isEmpty {
                            ContentUnavailableView {
                                Label("把喜欢的音乐带进来", systemImage: "waveform")
                            } description: { Text("导入你的音乐文件，收藏每一种节奏。\nFLAC · ALAC · MP3 · AAC · WAV · AIFF") } actions: {
                                Button("导入音乐", systemImage: "plus") { importing = true }.buttonStyle(.borderedProminent).disabled(store.isImporting)
                            }.padding(.vertical, 55)
                            #if os(iOS)
                            Label("也可以连接 Mac，在 Finder → iPhone → 文件 → Zuneyra 中拖入音乐，传输完成后打开本应用。", systemImage: "cable.connector")
                                .font(.footnote).foregroundStyle(.secondary)
                            #endif
                        } else if filtered.isEmpty {
                            ContentUnavailableView("这里还很安静", systemImage: "music.note", description: Text(query.isEmpty ? "收藏喜欢的歌曲，让它们出现在这里。" : "试试其他歌曲、专辑或艺术家名称。"))
                        } else if section == .albums && selectedAlbum == nil && query.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 260), spacing: 22)], alignment: .leading, spacing: 25) {
                                ForEach(albums, id: \.first!.albumKey) { album in
                                    Button { selectedAlbum = album[0].albumKey } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            CoverArt(track: album[0], repository: store.repository)
                                            Text(album[0].album).font(.headline).lineLimit(1)
                                            Text(album[0].albumArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityLabel("专辑 \(album[0].album)")
                                }
                            }
                        } else if section == .artists && selectedAlbum == nil && query.isEmpty {
                            ForEach(Array(Set(filtered.map(\.artist))).sorted(), id: \.self) { artist in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(artist).font(.title2.bold())
                                    songList(filtered.filter { $0.artist == artist })
                                }
                            }
                        } else {
                            Button("播放全部", systemImage: "play.fill") { if let first = filtered.first { store.play(first, context: filtered) } }.buttonStyle(.borderedProminent)
                            songList(filtered)
                        }
                    }.padding(24).frame(maxWidth: 1150, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
            .background(Sunset.background(scheme))
            .navigationTitle("Zuneyra")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    #if os(iOS)
                    Menu {
                        Button("选择文件或文件夹", systemImage: "folder") { importing = true }
                        Button("导入电脑传入的音乐", systemImage: "cable.connector") { store.scanSharedDocuments() }
                    } label: {
                        Label("导入音乐", systemImage: "plus")
                    }.disabled(store.isImporting).accessibilityIdentifier("importMusic")
                    #else
                    Button("导入音乐", systemImage: "plus") { importing = true }.disabled(store.isImporting).accessibilityIdentifier("importMusic")
                    #endif
                }
            }
        }
    }

    private func songList(_ tracks: [Track]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks) { track in
                HStack(spacing: 12) {
                    Button { store.play(track, context: tracks) } label: {
                        HStack(spacing: 12) {
                            CoverArt(track: track, repository: store.repository).frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.body.weight(.medium)).foregroundStyle(store.current?.id == track.id ? Sunset.coral : .primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(playbackTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("play-track-\(track.id)")
                        .accessibilityLabel("播放 \(track.title)")
                    Button { store.toggleFavorite(track) } label: { Image(systemName: track.favorite ? "heart.fill" : "heart").foregroundStyle(Sunset.coral).frame(width: 38, height: 44) }.buttonStyle(.plain).accessibilityLabel(track.favorite ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
                }.padding(.vertical, 10)
                Divider().opacity(0.5)
            }
        }
    }
    private func miniPlayer(_ track: Track) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Button { showingPlayer = true } label: {
                    HStack(spacing: 12) {
                        CoverArt(track: track, repository: store.repository).frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 3) { Text(track.title).font(.subheadline.bold()).lineLimit(1); Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开正在播放：\(track.title)")
                Button { store.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 36, height: 44) }.accessibilityLabel("上一首")
                Button { store.toggle() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44).background(Sunset.coral, in: Circle()).foregroundStyle(.white) }.accessibilityLabel(store.isPlaying ? "暂停" : "播放")
                Button { store.next() } label: { Image(systemName: "forward.end.fill").frame(width: 36, height: 44) }.accessibilityLabel("下一首")
                #if os(macOS)
                Slider(value: Binding(get: { store.position }, set: { store.seek(to: $0) }), in: 0...max(track.duration, 0.01)).frame(maxWidth: 220).accessibilityLabel("播放进度")
                #endif
                Button { showingQueue = true } label: { Image(systemName: "list.bullet").frame(width: 36, height: 44) }.accessibilityLabel("播放队列")
            }.buttonStyle(.plain).padding(14).background(Sunset.panel(scheme))
        }
    }
    private var fullPlayer: some View {
        NavigationStack {
            ScrollView {
                if let track = store.current {
                    VStack(spacing: 26) {
                        CoverArt(track: track, repository: store.repository).frame(maxWidth: 380)
                        VStack(spacing: 7) { Text(track.title).font(.title2.bold()); Text(track.artist).foregroundStyle(.secondary) }
                        VStack(spacing: 8) {
                            Slider(value: Binding(get: { store.position }, set: { store.seek(to: $0) }), in: 0...max(track.duration, 0.01)).accessibilityLabel("播放进度")
                            HStack { Text(playbackTime(store.position)); Spacer(); Text(playbackTime(track.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 40) {
                            Button { store.previous() } label: { Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 54) }.accessibilityLabel("上一首")
                            Button { store.toggle() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 66, height: 66).background(Sunset.coral, in: Circle()).foregroundStyle(.white) }.accessibilityLabel(store.isPlaying ? "暂停" : "播放")
                            Button { store.next() } label: { Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 54) }.accessibilityLabel("下一首")
                        }.buttonStyle(.plain)
                        HStack {
                            Button { store.toggleFavorite(track) } label: { Label(track.favorite ? "已收藏" : "收藏", systemImage: track.favorite ? "heart.fill" : "heart") }
                            Spacer()
                            Text(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO").font(.caption.monospaced())
                        }.buttonStyle(.plain)
                    }.padding(28).frame(maxWidth: 460).frame(maxWidth: .infinity)
                }
            }.background(Sunset.background(scheme)).navigationTitle("正在播放").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingPlayer = false } } }
        }.tint(Sunset.coral)
        #if os(macOS)
        .frame(width: 460, height: 720)
        #endif
    }
    private var queueView: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 15) { Text("\(store.queue.count) 首音乐").foregroundStyle(.secondary); songList(store.queue) }.padding(24) }.background(Sunset.background(scheme)).navigationTitle("接下来播放").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingQueue = false } } }
        }
        #if os(macOS)
        .frame(width: 520, height: 520)
        #endif
    }
    private var importResults: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("导入完成", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(Sunset.coral)
                    if let report = store.importReport {
                        Text(report.summary)
                        if report.failures.isEmpty { Text("音乐已保存在本机，可以随时离线聆听。").foregroundStyle(.secondary) }
                        else { Text("\(report.failures.count) 个文件未能导入").font(.headline); ForEach(Array(report.failures.enumerated()), id: \.offset) { _, message in Text(message).font(.caption).textSelection(.enabled) } }
                    }
                }.padding(24)
            }.background(Sunset.background(scheme)).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { store.importReport = nil } } }
        }
        #if os(macOS)
        .frame(width: 480, height: 360)
        #endif
    }
}
