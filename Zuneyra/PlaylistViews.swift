import SwiftUI

private extension View {
    func playlistError(_ message: Binding<String?>) -> some View {
        alert("无法更新歌单", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("好") { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}

struct PlaylistArtwork: View {
    @Environment(PlayerStore.self) private var store
    let tracks: [Track]
    var body: some View {
        GeometryReader { proxy in
            if tracks.count == 1, let first = tracks.first {
                CoverArt(track: first, repository: store.repository)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(0..<4) { index in
                        Group {
                            if tracks.indices.contains(index) { CoverArt(track: tracks[index], repository: store.repository) }
                            else {
                                Rectangle().fill(LinearGradient(colors: [Sunset.peach, Sunset.coral], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay { Image(systemName: "music.note").font(.system(size: proxy.size.width * 0.15, weight: .bold)).foregroundStyle(.white.opacity(0.8)) }
                            }
                        }.frame(width: (proxy.size.width - 2) / 2, height: (proxy.size.width - 2) / 2).clipped()
                    }
                }
            }
        }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
    }
}

func playlistDuration(_ tracks: [Track]) -> String {
    let seconds = tracks.reduce(0.0) { $0 + $1.duration }
    let minutes = Int(max(0, seconds.isFinite ? seconds : 0)) / 60
    if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟" }
    let remainder = Int(max(0, seconds.isFinite ? seconds : 0)) % 60
    return minutes > 0 ? "\(minutes) 分钟 \(remainder) 秒" : "\(remainder) 秒"
}

struct PlaylistLibraryView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let query: String
    @State private var creating = false
    private var filtered: [Playlist] { store.playlists.filter { query.isEmpty || $0.name.localizedStandardContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 7) {
                    Text("歌单").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(query.isEmpty ? "\(store.playlists.count) 个歌单 · 保存在本机" : "找到 \(filtered.count) 个歌单")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { creating = true } label: {
                    Label("新建歌单", systemImage: "plus").frame(minHeight: 32).fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderedProminent).tint(Sunset.coral)
                .disabled(store.isBusy).accessibilityIdentifier("createPlaylist")
            }
            if store.isLoading { ProgressView("正在读取歌单…") }
            else if filtered.isEmpty {
                ContentUnavailableView(query.isEmpty ? "给喜欢的音乐一个位置" : "没有找到歌单", systemImage: "music.note.list", description: Text(query.isEmpty ? "创建自己的歌单，按心情、场景或旅程收藏歌曲。" : "试试其他歌单名称。"))
            } else {
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 145, maximum: 260), spacing: 22)], alignment: .leading, spacing: 25) {
                    ForEach(filtered) { playlist in
                        let tracks = store.playlistTracks(playlist.id)
                        NavigationLink { PlaylistDetailView(playlistID: playlist.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                PlaylistArtwork(tracks: Array(tracks.prefix(4)))
                                Text(playlist.name).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                Text("\(tracks.count) 首 · \(playlistDuration(tracks))").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("歌单 \(playlist.name)")
                    }
                }
            }
        }
        .tint(Sunset.accent(scheme))
        .sheet(isPresented: $creating) { PlaylistNameForm() }
    }
}

struct PlaylistNameForm: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let playlistID: UUID?
    @State private var name: String
    @State private var error: String?
    init(playlistID: UUID? = nil, name: String = "") { self.playlistID = playlistID; _name = State(initialValue: name) }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100 }
    var body: some View {
        NavigationStack {
            Form {
                TextField("歌单名称", text: $name).autocorrectionDisabled().accessibilityIdentifier("playlistNameField").onSubmit { save() }
                Text("为你的音乐取个名字，最多 100 个字符。").font(.footnote).foregroundStyle(.secondary)
            }.scrollContentBackground(.hidden).background(Sunset.background(scheme))
                .navigationTitle(playlistID == nil ? "新建歌单" : "重命名歌单")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isEditingPlaylists) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }.disabled(!valid || store.isBusy).accessibilityIdentifier("savePlaylistName")
                    }
                }
        }.tint(Sunset.accent(scheme)).playlistError($error).interactiveDismissDisabled(store.isEditingPlaylists)
        #if os(macOS)
        .frame(width: 440, height: 240)
        #endif
    }
    private func save() {
        guard valid, !store.isBusy else { return }
        Task {
            do {
                if let playlistID { try await store.renamePlaylist(playlistID, name: name) }
                else { _ = try await store.createPlaylist(name: name) }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct AddToPlaylistView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let tracks: [Track]
    var onComplete: (() -> Void)? = nil
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("新歌单名称", text: $name).autocorrectionDisabled().accessibilityIdentifier("newPlaylistFromTracksName")
                    Button { add(to: nil) } label: {
                        Label("新建并加入", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 32)
                    }
                        .buttonStyle(.borderedProminent).tint(Sunset.coral)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100 || store.isBusy || tracks.isEmpty)
                        .accessibilityIdentifier("createPlaylistWithTracks")
                } header: { Text("为 \(tracks.count) 首歌曲新建歌单") }
                Section("已有歌单") {
                    if store.playlists.isEmpty { Text("还没有歌单，也可以在上方直接新建。").foregroundStyle(.secondary) }
                    ForEach(store.playlists) { playlist in
                        Button { add(to: playlist.id) } label: {
                            HStack(spacing: 12) {
                                PlaylistArtwork(tracks: Array(store.playlistTracks(playlist.id).prefix(4))).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name).font(.body.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                    Text("\(playlist.trackIDs.count) 首").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Sunset.accent(scheme))
                            }.frame(minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(store.isBusy || tracks.isEmpty).accessibilityLabel("加入歌单 \(playlist.name)")
                    }
                }
            }.scrollContentBackground(.hidden).background(Sunset.background(scheme))
                .navigationTitle("添加到歌单")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(store.isEditingPlaylists) } }
        }.tint(Sunset.accent(scheme)).playlistError($error).interactiveDismissDisabled(store.isEditingPlaylists)
        #if os(macOS)
        .frame(width: 520, height: 580)
        #endif
    }
    private func add(to id: UUID?) {
        Task {
            do {
                let title: String
                if let id {
                    try await store.addToPlaylist(id, tracks: tracks)
                    title = store.playlists.first { $0.id == id }?.name ?? "歌单"
                } else { title = try await store.createPlaylist(name: name, tracks: tracks).name }
                store.playlistNotice = "已加入「\(title)」，已有歌曲不会重复添加。"
                if let onComplete { onComplete() } else { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let playlistID: UUID
    @State private var renaming = false
    @State private var adding = false
    @State private var sorting = false
    @State private var deleting = false
    @State private var error: String?
    private var playlist: Playlist? { store.playlists.first { $0.id == playlistID } }
    private var tracks: [Track] { store.playlistTracks(playlistID) }
    var body: some View {
        Group {
            if let playlist {
                List {
                    Section {
                        let headerLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 20))
                        headerLayout {
                            PlaylistArtwork(tracks: Array(tracks.prefix(4))).frame(width: 100, height: 100)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(playlist.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                                Text("\(tracks.count) 首 · \(playlistDuration(tracks))").font(.subheadline).foregroundStyle(.secondary)
                                Text("保存在本机").font(.caption).foregroundStyle(Sunset.accent(scheme))
                            }
                        }.padding(.vertical, 12)
                        playbackActions
                    }.listRowBackground(Sunset.panel(scheme))
                    Section {
                        if tracks.isEmpty {
                            ContentUnavailableView {
                                Label("歌单还没有歌曲", systemImage: "music.note")
                            } description: {
                                Text("从音乐库中挑选歌曲，组成你的专属歌单。")
                            } actions: {
                                Button("添加歌曲", systemImage: "plus") { adding = true }.disabled(store.isBusy)
                            }
                        }
                        ForEach(tracks) { track in songRow(track) }
                            .onMove { offsets, destination in perform { try await store.movePlaylistTracks(playlistID, from: offsets, to: destination) } }
                            .onDelete { offsets in
                                let ids = Set(offsets.compactMap { tracks.indices.contains($0) ? tracks[$0].id : nil })
                                perform { try await store.removeFromPlaylist(playlistID, trackIDs: ids) }
                            }
                    } header: { Text("歌曲") } footer: { Text(sorting ? "拖动歌曲右侧的把手调整顺序，完成后点击“完成排序”。" : "从歌单移除歌曲不会删除音乐库文件。") }
                }
                .scrollContentBackground(.hidden)
                #if os(iOS)
                .environment(\.editMode, .constant(sorting ? .active : .inactive))
                #endif
                .disabled(store.isEditingPlaylists || store.isManaging)
                .navigationTitle(playlist.name)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("添加歌曲", systemImage: "plus") { adding = true }.disabled(store.isBusy).accessibilityIdentifier("addPlaylistSongs")
                    }
                    ToolbarItem(placement: .automatic) {
                        if sorting {
                            Button("完成排序") { sorting = false }.accessibilityIdentifier("finishPlaylistSorting")
                        } else {
                            Menu {
                                Button("重命名", systemImage: "pencil") { renaming = true }
                                #if os(iOS)
                                Button("调整顺序", systemImage: "arrow.up.arrow.down") { sorting = true }.disabled(tracks.count < 2)
                                #endif
                                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext(tracks) }.disabled(tracks.isEmpty)
                                Button("稍后播放", systemImage: "text.badge.plus") { store.appendToQueue(tracks) }.disabled(tracks.isEmpty)
                                Divider()
                                Button("删除歌单", systemImage: "trash", role: .destructive) { deleting = true }
                            } label: { Label("歌单操作", systemImage: "ellipsis.circle") }
                            .disabled(store.isBusy).accessibilityIdentifier("playlistActions")
                        }
                    }
                }
                .sheet(isPresented: $renaming) { PlaylistNameForm(playlistID: playlistID, name: playlist.name) }
                .sheet(isPresented: $adding) { PlaylistTrackPicker(playlistID: playlistID) }
            } else {
                ContentUnavailableView("歌单已移除", systemImage: "music.note.list")
            }
        }
        .background(Sunset.background(scheme)).tint(Sunset.accent(scheme)).playlistError($error)
        .onChange(of: tracks.isEmpty) { _, empty in if empty { sorting = false } }
        .confirmationDialog("删除歌单？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) { perform { try await store.deletePlaylist(playlistID); dismiss() } }
        } message: { Text("只删除歌单及其中的排列记录，音乐库文件和当前播放队列会保留。") }
    }
    private var playbackActions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { store.playPlaylist(playlistID) } label: {
                Label("播放全部", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 12)
                    .foregroundStyle(.white)
                    .background(Sunset.coral, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityIdentifier("playPlaylist")
            Button { store.playPlaylist(playlistID, shuffled: true) } label: {
                Label("随机播放", systemImage: "shuffle")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 12)
                    .foregroundStyle(Sunset.accent(scheme))
                    .background(Sunset.accent(scheme).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityIdentifier("shufflePlaylist")
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.plain)
        .disabled(tracks.isEmpty || store.isManaging)
        .opacity(tracks.isEmpty || store.isManaging ? 0.5 : 1)
    }
    private func songRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Button { store.playPlaylist(playlistID, startingAt: track.id) } label: {
                HStack(spacing: 12) {
                    CoverArt(track: track, repository: store.repository).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.body.weight(.medium))
                        Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        if typeSize.isAccessibilitySize { Text(playbackTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }.lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize { Text(playbackTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("歌单播放 \(track.title)").accessibilityIdentifier("playlistTrack-\(track.id)")
            Menu {
                if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    Button("上移", systemImage: "arrow.up") { move(index, to: index - 1) }.disabled(index == 0)
                    Button("下移", systemImage: "arrow.down") { move(index, to: index + 2) }.disabled(index == tracks.count - 1)
                }
                Button("下一首播放") { store.insertNext([track]) }
                Button("稍后播放") { store.appendToQueue([track]) }
                Button("从歌单移除", systemImage: "minus.circle") { perform { try await store.removeFromPlaylist(playlistID, trackIDs: [track.id]) } }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("歌单歌曲操作 \(track.title)")
        }.padding(.vertical, 4).listRowBackground(Sunset.panel(scheme))
    }
    private func move(_ index: Int, to destination: Int) { perform { try await store.movePlaylistTracks(playlistID, from: IndexSet(integer: index), to: destination) } }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task { do { try await action() } catch { self.error = error.localizedDescription } }
    }
}

struct PlaylistTrackPicker: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let playlistID: UUID
    @State private var query = ""
    @State private var selected = Set<UUID>()
    @State private var error: String?
    private var existing: Set<UUID> { Set(store.playlists.first { $0.id == playlistID }?.trackIDs ?? []) }
    private var filtered: [Track] { store.tracks.filter { LibraryPresentation.matches($0, query: query) } }
    var body: some View {
        NavigationStack {
            List {
                if store.tracks.isEmpty {
                    ContentUnavailableView("音乐库还没有歌曲", systemImage: "music.note", description: Text("先回到音乐库导入音乐，再将歌曲添加到歌单。"))
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("没有找到歌曲", systemImage: "magnifyingglass")
                    } description: {
                        Text("没有与“\(query)”匹配的歌曲，试试歌曲、艺术家或专辑名称。")
                    } actions: {
                        Button("清除搜索") { query = "" }
                    }
                } else if filtered.allSatisfy({ existing.contains($0.id) }) {
                    Text(query.isEmpty ? "音乐库中的歌曲已全部加入这个歌单。" : "这些搜索结果已在歌单中。")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(filtered) { track in
                    Button {
                        if selected.contains(track.id) { selected.remove(track.id) } else { selected.insert(track.id) }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: existing.contains(track.id) || selected.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Sunset.accent(scheme)).frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                if existing.contains(track.id) { Text("已添加到歌单").font(.caption).foregroundStyle(.secondary) }
                            }.fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(existing.contains(track.id) || store.isBusy)
                    .accessibilityLabel("添加歌曲 \(track.title)")
                    .accessibilityValue(existing.contains(track.id) ? "已添加到歌单" : selected.contains(track.id) ? "已选择" : "未选择")
                }
            }
            .searchable(text: $query, prompt: "搜索音乐库")
            .scrollContentBackground(.hidden).background(Sunset.background(scheme)).navigationTitle("选择歌曲")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.isEditingPlaylists) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加 \(selected.count) 首") {
                        Task {
                            do { try await store.addToPlaylist(playlistID, tracks: store.tracks.filter { selected.contains($0.id) }); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(selected.isEmpty || store.isBusy).accessibilityIdentifier("confirmAddPlaylistSongs")
                }
            }
        }.tint(Sunset.accent(scheme)).playlistError($error).interactiveDismissDisabled(store.isEditingPlaylists)
        #if os(macOS)
        .frame(width: 580, height: 620)
        #endif
    }
}
