import SwiftUI

struct PlaybackModesView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            SwipeSafeButton { store.toggleShuffle() } label: {
                Label(store.queueState.shuffle ? String(localized: "随机播放") : String(localized: "顺序播放"), systemImage: store.queueState.shuffle ? "shuffle" : "arrow.right")
            }
            .buttonStyle(StudioButtonStyle(prominent: store.queueState.shuffle))
            .accessibilityValue(store.queueState.shuffle ? String(localized: "已开启随机播放") : String(localized: "按队列顺序播放"))
            .accessibilityHint(String(localized: "切换顺序播放和随机播放"))
            .accessibilityAddTraits(store.queueState.shuffle ? .isSelected : [])
            SwipeSafeButton { store.cycleRepeatMode() } label: {
                Label(store.queueState.repeatMode.title, systemImage: store.queueState.repeatMode.symbol)
            }
            .buttonStyle(StudioButtonStyle(prominent: store.queueState.repeatMode != .off))
            .accessibilityValue(store.queueState.repeatMode.title)
            .accessibilityHint(String(localized: "依次切换不循环、列表循环和单曲循环"))
            .accessibilityAddTraits(store.queueState.repeatMode != .off ? .isSelected : [])
        }.font(.subheadline.weight(.medium)).disabled(store.isManaging)
    }
}

struct PlaybackQueueView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var sorting = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var showsClose = true
    var embedded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CollectionSheetHeader(
                title: String(localized: "播放队列"),
                subtitle: String(localized: "\(store.queueState.canonical.count) 首歌曲"),
                back: showsClose || embedded ? nil : { dismiss() },
                close: showsClose && !embedded ? { dismiss() } : nil
                )
                if embedded {
                    queueActions.padding(.trailing, 16)
                }
            }
            queueControls
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 20)
            Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
            if let notice = store.queueNotice {
                Text(notice).font(.footnote).foregroundStyle(Sunset.secondary(scheme)).padding(.horizontal, 20).padding(.vertical, 10)
            }
            if store.queueState.canonical.isEmpty {
                StudioEmptyState(symbol: "list.bullet", title: String(localized: "队列还没有音乐"), detail: String(localized: "在歌曲菜单中选择“下一首播放”或“稍后播放”。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !store.queueState.past.isEmpty {
                        Section {
                            DisclosureGroup(String(localized: "已播放 · \(store.queueState.past.count) 首")) {
                                ForEach(store.queueState.pastEntries) { entry in queueRow(entry) }
                            }
                        }
                    }
                    if let entry = store.queueState.currentEntry {
                        Section(String(localized: "当前歌曲")) { queueRow(entry, current: true) }
                    }
                    Section {
                        ForEach(store.queueState.upcomingEntries) { entry in queueRow(entry, pending: true) }
                            .onMove { store.moveUpcoming(from: $0, to: $1) }
                            .onDelete { offsets in
                                let entries = store.queueState.upcomingEntries
                                for index in offsets where entries.indices.contains(index) { store.removeQueueEntry(entries[index].id) }
                            }
                        if store.queueState.upcoming.isEmpty {
                            Text(String(localized: "没有待播歌曲")).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(String(localized: "接下来 · \(store.queueState.upcoming.count) 首"))
                    } footer: {
                        Text(sorting ? String(localized: "拖动歌曲右侧的把手调整顺序，完成后点击“完成排序”。") : String(localized: "从队列移除不会删除音乐库中的歌曲。"))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .guardActionsWhileScrolling()
                .padding(.horizontal, embedded ? 16 : 0)
                #if os(iOS)
                .environment(\.editMode, .constant(sorting ? .active : .inactive))
                #endif
                .disabled(store.isManaging)
            }
        }
        // Keep the header and empty state anchored within the full navigation destination.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Sunset.background(scheme))
        .collectionSheetChrome()
        .tint(Sunset.accent(scheme))
        .onChange(of: store.queueState.upcoming.isEmpty) { _, empty in
            if empty { sorting = false }
        }
    }

    @ViewBuilder private var queueControls: some View {
        if embedded {
            PlaybackModesView().frame(maxWidth: .infinity, alignment: .leading)
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                PlaybackModesView()
                queueActions
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    PlaybackModesView()
                    Spacer(minLength: 8)
                    queueActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    PlaybackModesView()
                    queueActions
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var queueActions: some View {
        if sorting {
            Button(String(localized: "完成排序")) { sorting = false }
                .buttonStyle(StudioButtonStyle())
        } else {
            Menu {
                #if os(iOS)
                Button(String(localized: "调整顺序"), systemImage: "arrow.up.arrow.down") { sorting = true }
                    .disabled(store.queueState.upcoming.count < 2)
                #endif
                Button(String(localized: "清空待播"), systemImage: "text.badge.minus") { store.clearUpcoming() }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(String(localized: "队列操作"))
            .disabled(store.queueState.upcoming.isEmpty || store.isManaging)
        }
    }

    private func queueRow(_ entry: QueueEntry, current: Bool = false, pending: Bool = false) -> some View {
        Group {
            if let track = store.track(for: entry) {
                HStack(spacing: 12) {
                    SwipeSafeButton {
                        if current { store.toggle() } else { store.playQueueEntry(entry.id) }
                    } label: {
                        HStack(spacing: 12) {
                            CoverArt(track: track, repository: store.repository).frame(width: 40, height: 40).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title).font(.body.weight(.medium)).foregroundStyle(current ? Sunset.accent(scheme) : .primary)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }.lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if !typeSize.isAccessibilitySize {
                                Text(playbackTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(Sunset.secondary(scheme))
                            }
                            if current {
                                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(Sunset.accent(scheme))
                            }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .protectLibraryAction()
                    .accessibilityLabel(current ? (store.isPlaying ? String(localized: "暂停 ") : String(localized: "继续播放 ")) + track.title : String(localized: "播放 ") + track.title)
                    Menu {
                        if pending, let index = store.queueState.upcoming.firstIndex(of: entry.id) {
                            Button(String(localized: "移到下一首"), systemImage: "text.line.first.and.arrowtriangle.forward") {
                                store.moveUpcoming(from: IndexSet(integer: index), to: 0)
                            }.disabled(index == 0)
                            Button(String(localized: "上移"), systemImage: "arrow.up") { store.moveUpcomingEntry(entry.id, direction: -1) }.disabled(index == 0)
                            Button(String(localized: "下移"), systemImage: "arrow.down") { store.moveUpcomingEntry(entry.id, direction: 1) }.disabled(index == store.queueState.upcoming.count - 1)
                        }
                        Button(String(localized: "移出队列"), systemImage: "minus.circle") { store.removeQueueEntry(entry.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .menuStyle(.borderlessButton)
                    .protectLibraryAction()
                    .fixedSize()
                    .accessibilityLabel(String(localized: "队列操作 \(track.title)"))
                }.frame(minHeight: 44).padding(.vertical, 4)
                    .listRowBackground(current ? Sunset.accent(scheme).opacity(0.08) : .clear)
                    .listRowSeparatorTint(Sunset.stroke(scheme))
                    .moveDisabled(!pending)
                    .deleteDisabled(!pending)
            }
        }
    }
}
