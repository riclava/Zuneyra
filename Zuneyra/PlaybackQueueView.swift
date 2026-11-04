import SwiftUI

struct PlaybackModesView: View {
    @Environment(PlayerStore.self) private var store
    var body: some View {
        HStack {
            Button { store.toggleShuffle() } label: {
                Label(store.queueState.shuffle ? "随机播放" : "顺序播放", systemImage: store.queueState.shuffle ? "shuffle" : "arrow.right").frame(minHeight: 44)
            }
            .accessibilityIdentifier("shuffleMode")
            .foregroundStyle(store.queueState.shuffle ? Sunset.coral : .secondary)
            Spacer()
            Button { store.cycleRepeatMode() } label: {
                Label(store.queueState.repeatMode.title, systemImage: store.queueState.repeatMode.symbol).frame(minHeight: 44)
            }
            .accessibilityIdentifier("repeatMode")
            .foregroundStyle(store.queueState.repeatMode == .off ? .secondary : Sunset.coral)
        }.buttonStyle(.plain).font(.subheadline).disabled(store.isManaging)
    }
}

struct PlaybackQueueView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var sorting = false
    var showsClose = true

    var body: some View {
        VStack(spacing: 0) {
            PlaybackModesView().padding(20)
            if let notice = store.queueNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
            }
            if store.queueState.canonical.isEmpty {
                ContentUnavailableView("队列还没有音乐", systemImage: "list.bullet", description: Text("在歌曲菜单中选择“下一首播放”或“稍后播放”。"))
            } else {
                List {
                    if !store.queueState.past.isEmpty {
                        Section {
                            DisclosureGroup("已播放 · \(store.queueState.past.count) 首") {
                                ForEach(store.queueState.pastEntries) { entry in queueRow(entry) }
                            }
                        }
                    }
                    if let entry = store.queueState.currentEntry {
                        Section("当前歌曲") { queueRow(entry, current: true) }
                    }
                    Section {
                        ForEach(store.queueState.upcomingEntries) { entry in queueRow(entry, pending: true) }
                            .onMove { store.moveUpcoming(from: $0, to: $1) }
                            .onDelete { offsets in
                                let entries = store.queueState.upcomingEntries
                                for index in offsets where entries.indices.contains(index) { store.removeQueueEntry(entries[index].id) }
                            }
                        if store.queueState.upcoming.isEmpty {
                            Text("没有待播歌曲").foregroundStyle(.secondary).accessibilityIdentifier("emptyUpcoming")
                        }
                    } header: {
                        Text("接下来 · \(store.queueState.upcoming.count) 首")
                    } footer: {
                        Text("从队列移除不会删除音乐库中的歌曲。")
                    }
                }
                .scrollContentBackground(.hidden)
                #if os(iOS)
                .environment(\.editMode, .constant(sorting ? .active : .inactive))
                #endif
                .disabled(store.isManaging)
            }
        }
        .background(Sunset.background(scheme))
        .navigationTitle("播放队列")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    #if os(iOS)
                    Button(sorting ? "完成排序" : "调整顺序", systemImage: "arrow.up.arrow.down") { sorting.toggle() }
                    #endif
                    Button("清空待播", systemImage: "text.badge.minus") { store.clearUpcoming() }
                } label: { Label("队列操作", systemImage: "ellipsis.circle") }
                .disabled(store.queueState.upcoming.isEmpty || store.isManaging)
                .accessibilityIdentifier("queueActions")
            }
            if showsClose {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .tint(Sunset.coral)
    }

    private func queueRow(_ entry: QueueEntry, current: Bool = false, pending: Bool = false) -> some View {
        Group {
            if let track = store.track(for: entry) {
                HStack(spacing: 12) {
                    Button {
                        if current { store.toggle() } else { store.playQueueEntry(entry.id) }
                    } label: {
                        HStack(spacing: 12) {
                            CoverArt(track: track, repository: store.repository).frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.body.weight(.medium)).foregroundStyle(current ? Sunset.coral : .primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }.lineLimit(1)
                            Spacer(minLength: 0)
                            if current {
                                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(Sunset.coral)
                            }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(current ? (store.isPlaying ? "暂停 " : "继续播放 ") + track.title : "播放 " + track.title)
                    .accessibilityIdentifier("queueEntry-\(entry.id)")
                    Menu {
                        if pending, let index = store.queueState.upcoming.firstIndex(of: entry.id) {
                            Button("移到下一首", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                store.moveUpcoming(from: IndexSet(integer: index), to: 0)
                            }.disabled(index == 0)
                            Button("上移", systemImage: "arrow.up") { store.moveUpcomingEntry(entry.id, direction: -1) }.disabled(index == 0)
                            Button("下移", systemImage: "arrow.down") { store.moveUpcomingEntry(entry.id, direction: 1) }.disabled(index == store.queueState.upcoming.count - 1)
                        }
                        Button("移出队列", systemImage: "minus.circle") { store.removeQueueEntry(entry.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("队列操作 \(track.title)")
                    .accessibilityIdentifier("queueEntryActions-\(entry.id)")
                }.padding(.vertical, 4)
                    .listRowBackground(Sunset.panel(scheme))
                    .moveDisabled(!pending)
                    .deleteDisabled(!pending)
            }
        }
    }
}
