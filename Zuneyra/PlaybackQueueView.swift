import SwiftUI

struct PlaybackModesView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button { store.toggleShuffle() } label: {
                Label(store.queueState.shuffle ? "随机播放" : "顺序播放", systemImage: store.queueState.shuffle ? "shuffle" : "arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(store.queueState.shuffle ? Sunset.accent(scheme).opacity(0.12) : Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("shuffleMode")
            .accessibilityValue(store.queueState.shuffle ? "已开启随机播放" : "按队列顺序播放")
            .accessibilityHint("切换顺序播放和随机播放")
            .foregroundStyle(store.queueState.shuffle ? Sunset.accent(scheme) : .primary)
            Button { store.cycleRepeatMode() } label: {
                Label(store.queueState.repeatMode.title, systemImage: store.queueState.repeatMode.symbol)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(store.queueState.repeatMode == .off ? Sunset.panel(scheme) : Sunset.accent(scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("repeatMode")
            .accessibilityValue(store.queueState.repeatMode.title)
            .accessibilityHint("依次切换不循环、列表循环和单曲循环")
            .foregroundStyle(store.queueState.repeatMode == .off ? .primary : Sunset.accent(scheme))
        }.buttonStyle(.plain).font(.subheadline.weight(.medium)).disabled(store.isManaging)
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
                        Text(sorting ? "拖动歌曲右侧的把手调整顺序，完成后点击“完成排序”。" : "从队列移除不会删除音乐库中的歌曲。")
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if sorting {
                    Button("完成排序") { sorting = false }
                        .accessibilityIdentifier("finishQueueSorting")
                } else {
                    Menu {
                        #if os(iOS)
                        Button("调整顺序", systemImage: "arrow.up.arrow.down") { sorting = true }
                            .disabled(store.queueState.upcoming.count < 2)
                        #endif
                        Button("清空待播", systemImage: "text.badge.minus") { store.clearUpcoming() }
                    } label: { Label("队列操作", systemImage: "ellipsis.circle") }
                    .disabled(store.queueState.upcoming.isEmpty || store.isManaging)
                    .accessibilityIdentifier("queueActions")
                }
            }
            if showsClose {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .tint(Sunset.accent(scheme))
        .onChange(of: store.queueState.upcoming.isEmpty) { _, empty in
            if empty { sorting = false }
        }
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
                                Text(track.title).font(.body.weight(.medium)).foregroundStyle(current ? Sunset.accent(scheme) : .primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }.lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if current {
                                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(Sunset.accent(scheme))
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
                    .listRowBackground(current ? Sunset.accent(scheme).opacity(0.08) : Sunset.panel(scheme))
                    .moveDisabled(!pending)
                    .deleteDisabled(!pending)
            }
        }
    }
}
