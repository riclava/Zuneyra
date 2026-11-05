import SwiftUI

private extension View {
    func playlistError(_ message: Binding<String?>) -> some View {
        alert(String(localized: "无法更新歌单"), isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button(String(localized: "好")) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}

struct PlaylistArtwork: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let tracks: [Track]
    var body: some View {
        GeometryReader { proxy in
            if tracks.isEmpty {
                ZStack {
                    Rectangle().fill(Sunset.panel(scheme))
                    ForEach(0..<3) { index in
                        Circle().stroke(Sunset.secondary(scheme).opacity(0.14), lineWidth: 1)
                            .frame(width: proxy.size.width * (0.52 + Double(index) * 0.15))
                    }
                    Circle().fill(Sunset.accent(scheme)).frame(width: proxy.size.width * 0.12, height: proxy.size.width * 0.12)
                    Circle().fill(Sunset.elevated(scheme)).frame(width: proxy.size.width * 0.025, height: proxy.size.width * 0.025)
                }
            } else if tracks.count == 1, let first = tracks.first {
                CoverArt(track: first, repository: store.repository)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(0..<4) { index in
                        Group {
                            if tracks.indices.contains(index) { CoverArt(track: tracks[index], repository: store.repository, cornerRadius: 0) }
                            else { Rectangle().fill(Sunset.panel(scheme)) }
                        }.frame(width: (proxy.size.width - 2) / 2, height: (proxy.size.width - 2) / 2).clipped()
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(Sunset.stroke(scheme), lineWidth: 1) }
        .accessibilityHidden(true)
    }
}

func playlistDuration(_ tracks: [Track]) -> String {
    let seconds = tracks.reduce(0.0) { $0 + $1.duration }
    let minutes = Int(max(0, seconds.isFinite ? seconds : 0)) / 60
    if minutes >= 60 { return String(localized: "\(minutes / 60) 小时 \(minutes % 60) 分钟") }
    let remainder = Int(max(0, seconds.isFinite ? seconds : 0)) % 60
    return minutes > 0 ? String(localized: "\(minutes) 分钟 \(remainder) 秒") : String(localized: "\(remainder) 秒")
}

struct PlaylistLibraryView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let query: String
    @State private var creating = false
    private var filtered: [Playlist] { store.playlists.filter { query.isEmpty || $0.name.localizedStandardContains(query) } }
    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 190, maximum: 320), spacing: 28)]
        #else
        return [GridItem(.adaptive(minimum: 145, maximum: 280), spacing: 20)]
        #endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "歌单")).font(.system(.largeTitle, design: .serif).weight(.medium)).accessibilityAddTraits(.isHeader)
                    Text(query.isEmpty ? String(localized: "\(store.playlists.count) 个歌单 · 你的私人选集") : String(localized: "找到 \(filtered.count) 个歌单"))
                        .font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { creating = true } label: { Label(String(localized: "新建歌单"), systemImage: "plus") }
                    .buttonStyle(StudioButtonStyle(prominent: true))
                    .disabled(store.isBusy)
            }
            Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
            if store.isLoading { ProgressView(String(localized: "正在读取歌单…")) }
            else if filtered.isEmpty {
                StudioEmptyState(symbol: "music.note.list", title: query.isEmpty ? String(localized: "为喜欢的音乐，留一个位置") : String(localized: "没有找到歌单"), detail: query.isEmpty ? String(localized: "创建一份私人选集，收录音乐库中的歌曲。") : String(localized: "试试其他歌单名称。"))
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                    ForEach(filtered) { playlist in
                        let tracks = store.playlistTracks(playlist.id)
                        NavigationLink(value: playlist.id) {
                            playlistCard(playlist, tracks: tracks)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "歌单 \(playlist.name)，\(tracks.count) 首，\(playlistDuration(tracks))"))
                    }
                }
            }
        }
        .tint(Sunset.accent(scheme))
        .sheet(isPresented: $creating) { PlaylistNameForm() }
    }

    private func playlistCard(_ playlist: Playlist, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaylistArtwork(tracks: Array(tracks.prefix(4)))
                .padding(7)
                .background(Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(Sunset.stroke(scheme), lineWidth: 1) }
                .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.06), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name).font(.system(.title3, design: .serif).weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "\(tracks.count) 首 · \(playlistDuration(tracks))"))
                    .font(.caption).foregroundStyle(Sunset.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
        VStack(spacing: 0) {
            CollectionSheetHeader(title: playlistID == nil ? String(localized: "新建歌单") : String(localized: "重命名歌单"), close: { dismiss() })
                .disabled(store.isEditingPlaylists)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "歌单名称")).font(.subheadline.weight(.medium))
                    TextField(String(localized: "输入名称"), text: $name).autocorrectionDisabled().onSubmit { save() }
                        .textFieldStyle(.plain).padding(12)
                        .background(Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(Sunset.stroke(scheme), lineWidth: 1) }
                        .accessibilityLabel(String(localized: "歌单名称"))
                    HStack(alignment: .top) {
                        Text(String(localized: "最多 100 个字符。"))
                        Spacer(minLength: 8)
                        Text("\(name.count) / 100").monospacedDigit()
                    }.font(.footnote).foregroundStyle(Sunset.secondary(scheme))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }
            HStack(spacing: 12) {
                Button(String(localized: "取消")) { dismiss() }.buttonStyle(StudioButtonStyle())
                    .disabled(store.isEditingPlaylists)
                Spacer(minLength: 8)
                Button(String(localized: "保存")) { save() }.buttonStyle(StudioButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction).disabled(!valid || store.isBusy)
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea())
        .tint(Sunset.accent(scheme)).playlistError($error).interactiveDismissDisabled(store.isEditingPlaylists)
        .collectionSheetChrome()
        #if os(macOS)
        .frame(width: 440, height: 320)
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
        VStack(spacing: 0) {
            CollectionSheetHeader(title: String(localized: "添加到歌单"), subtitle: String(localized: "已选择 \(tracks.count) 首歌曲"), close: { dismiss() })
                .disabled(store.isEditingPlaylists)
            List {
                Section {
                    TextField(String(localized: "新歌单名称"), text: $name).autocorrectionDisabled().listRowBackground(Color.clear)
                    Button { add(to: nil) } label: {
                        Label(String(localized: "新建并加入"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 32)
                    }
                        .buttonStyle(StudioButtonStyle(prominent: true))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100 || store.isBusy || tracks.isEmpty)
                        .listRowBackground(Color.clear)
                } header: { Text(String(localized: "为 \(tracks.count) 首歌曲新建歌单")) }
                Section(String(localized: "已有歌单")) {
                    if store.playlists.isEmpty { Text(String(localized: "还没有歌单，也可以在上方直接新建。")).foregroundStyle(.secondary).listRowBackground(Color.clear) }
                    ForEach(store.playlists) { playlist in
                        Button { add(to: playlist.id) } label: {
                            HStack(spacing: 12) {
                                PlaylistArtwork(tracks: Array(store.playlistTracks(playlist.id).prefix(4))).frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name).font(.body.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                    Text(String(localized: "\(playlist.trackIDs.count) 首")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(Sunset.accent(scheme))
                            }.frame(minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(store.isBusy || tracks.isEmpty).accessibilityLabel(String(localized: "加入歌单 \(playlist.name)"))
                            .listRowBackground(Color.clear)
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(Sunset.background(scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea())
        .tint(Sunset.accent(scheme)).playlistError($error).interactiveDismissDisabled(store.isEditingPlaylists)
        .collectionSheetChrome()
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
                    title = store.playlists.first { $0.id == id }?.name ?? String(localized: "歌单")
                } else { title = try await store.createPlaylist(name: name, tracks: tracks).name }
                store.playlistNotice = String(localized: "已加入「\(title)」，已有歌曲不会重复添加。")
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
        VStack(spacing: 0) {
            CollectionSheetHeader(title: String(localized: "歌单"), back: { dismiss() })
            if let playlist {
                editingActions
                    .padding(.horizontal, 24).padding(.bottom, 12)
                List {
                    Section {
                        playlistHeading(playlist)
                        playbackActions
                    }.listRowBackground(Color.clear)
                    Section {
                        if tracks.isEmpty {
                            VStack(spacing: 16) {
                                StudioEmptyState(symbol: "music.note", title: String(localized: "歌单还没有歌曲"), detail: String(localized: "从音乐库中选择歌曲，添加到这个歌单。"))
                                Button(String(localized: "添加歌曲"), systemImage: "plus") { adding = true }
                                    .buttonStyle(StudioButtonStyle(prominent: true)).disabled(store.isBusy)
                            }.frame(maxWidth: .infinity).padding(.vertical, 24)
                        }
                        ForEach(tracks) { track in songRow(track) }
                            .onMove { offsets, destination in perform { try await store.movePlaylistTracks(playlistID, from: offsets, to: destination) } }
                            .onDelete { offsets in
                                let ids = Set(offsets.compactMap { tracks.indices.contains($0) ? tracks[$0].id : nil })
                                perform { try await store.removeFromPlaylist(playlistID, trackIDs: ids) }
                            }
                    } header: { Text(String(localized: "歌曲")) } footer: { Text(sorting ? String(localized: "拖动歌曲右侧的把手调整顺序，完成后点击“完成排序”。") : String(localized: "从歌单移除歌曲不会删除音乐库文件。")) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                #if os(iOS)
                .environment(\.editMode, .constant(sorting ? .active : .inactive))
                #endif
                .disabled(store.isEditingPlaylists || store.isManaging)
                .sheet(isPresented: $renaming) { PlaylistNameForm(playlistID: playlistID, name: playlist.name) }
                .sheet(isPresented: $adding) { PlaylistTrackPicker(playlistID: playlistID) }
            } else {
                StudioEmptyState(symbol: "music.note.list", title: String(localized: "歌单已移除"), detail: String(localized: "返回音乐库，查看其他歌单。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea()).tint(Sunset.accent(scheme)).playlistError($error)
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onChange(of: tracks.isEmpty) { _, empty in if empty { sorting = false } }
        .confirmationDialog(String(localized: "删除歌单？"), isPresented: $deleting, titleVisibility: .visible) {
            Button(String(localized: "删除歌单"), role: .destructive) { perform { try await store.deletePlaylist(playlistID); dismiss() } }
        } message: { Text(String(localized: "只删除歌单及其中的排列记录，音乐库文件和当前播放队列会保留。")) }
    }
    private var editingActions: some View {
        HStack(spacing: 12) {
            Button(String(localized: "添加歌曲"), systemImage: "plus") { adding = true }
                .buttonStyle(StudioButtonStyle()).disabled(store.isBusy)
            Spacer(minLength: 8)
            if sorting {
                Button(String(localized: "完成排序")) { sorting = false }.buttonStyle(StudioButtonStyle())
            } else {
                Menu {
                    Button(String(localized: "重命名"), systemImage: "pencil") { renaming = true }
                    #if os(iOS)
                    Button(String(localized: "调整顺序"), systemImage: "arrow.up.arrow.down") { sorting = true }.disabled(tracks.count < 2)
                    #endif
                    Button(String(localized: "下一首播放"), systemImage: "text.line.first.and.arrowtriangle.forward") { store.insertNext(tracks) }.disabled(tracks.isEmpty)
                    Button(String(localized: "稍后播放"), systemImage: "text.badge.plus") { store.appendToQueue(tracks) }.disabled(tracks.isEmpty)
                    Divider()
                    Button(String(localized: "删除歌单"), systemImage: "trash", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 44)
                .accessibilityLabel(String(localized: "歌单操作")).disabled(store.isBusy)
            }
        }
    }

    private func playlistHeading(_ playlist: Playlist) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24)) : AnyLayout(HStackLayout(alignment: .center, spacing: 24))
        return layout {
            PlaylistArtwork(tracks: Array(tracks.prefix(4)))
                #if os(macOS)
                .frame(width: 172, height: 172)
                #else
                .frame(width: 128, height: 128)
                #endif
                .padding(7)
                .background(Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(Sunset.stroke(scheme), lineWidth: 1) }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "私人选集")).font(.caption).foregroundStyle(Sunset.accent(scheme))
                Text(playlist.name).font(.system(.title, design: .serif).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "\(tracks.count) 首 · \(playlistDuration(tracks))")).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 20)
    }

    private var playbackActions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button { store.playPlaylist(playlistID) } label: { Label(String(localized: "播放全部"), systemImage: "play.fill") }
                .buttonStyle(StudioButtonStyle(prominent: true))
            Button { store.playPlaylist(playlistID, shuffled: true) } label: { Label(String(localized: "随机播放"), systemImage: "shuffle") }
                .buttonStyle(StudioButtonStyle())
        }
        .font(.subheadline.weight(.semibold))
        .disabled(tracks.isEmpty || store.isManaging)
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
            }.buttonStyle(.plain).accessibilityLabel(String(localized: "歌单播放 \(track.title)"))
            Menu {
                if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                    Button(String(localized: "上移"), systemImage: "arrow.up") { move(index, to: index - 1) }.disabled(index == 0)
                    Button(String(localized: "下移"), systemImage: "arrow.down") { move(index, to: index + 2) }.disabled(index == tracks.count - 1)
                }
                Button(String(localized: "下一首播放")) { store.insertNext([track]) }
                Button(String(localized: "稍后播放")) { store.appendToQueue([track]) }
                Button(String(localized: "从歌单移除"), systemImage: "minus.circle") { perform { try await store.removeFromPlaylist(playlistID, trackIDs: [track.id]) } }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(String(localized: "歌单歌曲操作 \(track.title)"))
        }.frame(minHeight: 44).padding(.vertical, 4).listRowBackground(Color.clear).listRowSeparatorTint(Sunset.stroke(scheme))
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
        VStack(spacing: 0) {
            CollectionSheetHeader(title: String(localized: "选择歌曲"), close: { dismiss() })
                .disabled(store.isEditingPlaylists)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Sunset.secondary(scheme)).accessibilityHidden(true)
                TextField(String(localized: "搜索音乐库"), text: $query)
                    .textFieldStyle(.plain).autocorrectionDisabled().submitLabel(.search)
                    .accessibilityLabel(String(localized: "搜索音乐库"))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(Sunset.secondary(scheme)).accessibilityLabel(String(localized: "清除搜索"))
                }
            }
            .padding(.leading, 14).padding(.trailing, query.isEmpty ? 14 : 0).frame(minHeight: 44)
            .background(Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 24).padding(.bottom, 12)
            List {
                if store.tracks.isEmpty {
                    StudioEmptyState(symbol: "music.note", title: String(localized: "音乐库还没有歌曲"), detail: String(localized: "先回到音乐库导入音乐，再将歌曲添加到歌单。"))
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if filtered.isEmpty {
                    VStack(spacing: 16) {
                        StudioEmptyState(symbol: "magnifyingglass", title: String(localized: "没有找到歌曲"), detail: String(localized: "没有与“\(query)”匹配的歌曲，试试歌曲、艺术家或专辑名称。"))
                        Button(String(localized: "清除搜索")) { query = "" }.buttonStyle(StudioButtonStyle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if filtered.allSatisfy({ existing.contains($0.id) }) {
                    Text(query.isEmpty ? String(localized: "音乐库中的歌曲已全部加入这个歌单。") : String(localized: "这些搜索结果已在歌单中。"))
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
                                if existing.contains(track.id) { Text(String(localized: "已添加到歌单")).font(.caption).foregroundStyle(.secondary) }
                            }.fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(existing.contains(track.id) || store.isBusy)
                    .accessibilityLabel(String(localized: "添加歌曲 \(track.title)"))
                    .accessibilityValue(existing.contains(track.id) ? String(localized: "已添加到歌单") : selected.contains(track.id) ? String(localized: "已选择") : String(localized: "未选择"))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            HStack(spacing: 12) {
                Button(String(localized: "取消")) { dismiss() }.buttonStyle(StudioButtonStyle())
                    .disabled(store.isEditingPlaylists)
                Spacer(minLength: 8)
                Button(String(localized: "添加 \(selected.count) 首")) {
                    Task {
                        do { try await store.addToPlaylist(playlistID, tracks: store.tracks.filter { selected.contains($0.id) }); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(StudioButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction).disabled(selected.isEmpty || store.isBusy)
            }.padding(.horizontal, 24).padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme).ignoresSafeArea())
        .tint(Sunset.accent(scheme)).playlistError($error).interactiveDismissDisabled(store.isEditingPlaylists)
        .collectionSheetChrome()
        #if os(macOS)
        .frame(width: 580, height: 620)
        #endif
    }
}
