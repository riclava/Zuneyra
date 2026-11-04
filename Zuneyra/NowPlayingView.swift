import SwiftUI
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    if let track = store.current {
                        VStack(spacing: 24) {
                            CoverArt(track: track, repository: store.repository)
                                .frame(maxWidth: typeSize.isAccessibilitySize ? 140 : min(300, max(140, geometry.size.height * 0.34)))
                                .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.08), radius: 20, y: 10)
                                .accessibilityHidden(true)

                            trackDetails(track)
                            PlaybackTimeline(track: track).id(track.id)
                            transportControls
                            PlaybackModesView()
                            queueLink
                            outputDetails(track)
                        }
                        .padding(24)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView("还没有正在播放的音乐", systemImage: "music.note", description: Text("从音乐库选择一首歌曲，开始聆听。"))
                    }
                }
            }
            .background(Sunset.background(scheme))
            .navigationTitle("正在播放")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .tint(Sunset.accent(scheme))
        #if os(macOS)
        .frame(width: 480, height: 760)
        #endif
    }

    private func trackDetails(_ track: Track) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(track.title)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(track.artist).font(.body).foregroundStyle(.secondary)
                Text(track.album).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.toggleFavorite(track) } label: {
                Image(systemName: track.favorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(Sunset.panel(scheme), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Sunset.accent(scheme))
            .accessibilityLabel(track.favorite ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
            .accessibilityValue(track.favorite ? "已收藏" : "未收藏")
            .disabled(store.isManaging)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 36) {
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill").font(.title2).frame(width: 56, height: 64)
            }.accessibilityLabel("上一首")
            Button { store.toggle() } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title.weight(.semibold))
                    .frame(width: 76, height: 76)
                    .background(Sunset.coral, in: Circle())
                    .foregroundStyle(.white)
            }.accessibilityLabel(store.isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("playerTransportToggle")
            Button { store.next() } label: {
                Image(systemName: "forward.end.fill").font(.title2).frame(width: 56, height: 64)
            }.accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
        .disabled(store.isManaging)
    }

    private var queueLink: some View {
        NavigationLink { PlaybackQueueView(showsClose: false) } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet").font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("播放队列").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(store.queueState.upcoming.isEmpty ? "没有待播歌曲" : "接下来还有 \(store.queueState.upcoming.count) 首")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Sunset.panel(scheme), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playerQueue")
    }

    private func outputDetails(_ track: Track) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                fileFormat(track)
                Spacer()
                audioOutput
            }
            VStack(spacing: 8) {
                audioOutput
                fileFormat(track)
            }
        }
    }

    private func fileFormat(_ track: Track) -> some View {
        Text(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO")
            .font(.caption.monospaced().weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Sunset.panel(scheme), in: Capsule())
            .accessibilityLabel("音频格式 \(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO")")
    }

    @ViewBuilder private var audioOutput: some View {
        #if os(iOS)
        HStack(spacing: 4) {
            Text("音频输出").font(.subheadline).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            AudioOutputPicker().frame(width: 48, height: 48)
        }
        #else
        Label("本机播放", systemImage: "speaker.wave.2").font(.caption).foregroundStyle(.secondary)
        #endif
    }
}

/// Preview changes while dragging; only send the final position to the playback engine.
struct PlaybackTimeline: View {
    @Environment(PlayerStore.self) private var store
    let track: Track
    @State private var preview: Double?
    private var duration: Double { track.duration.isFinite ? max(0, track.duration) : 0 }
    private var position: Double { min(max(0, preview ?? store.position), duration) }

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { position }, set: { preview = $0 }), in: 0...max(duration, 0.01)) { editing in
                if editing {
                    if preview == nil { preview = position }
                } else {
                    if let preview { store.seek(to: preview) }
                    preview = nil
                }
            }
            .disabled(duration <= 0 || store.isManaging)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(playbackTime(position))，共 \(playbackTime(duration))")
            .accessibilityHint("每次调整可前进或后退 10 秒")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: store.seek(to: min(duration, position + 10))
                case .decrement: store.seek(to: max(0, position - 10))
                @unknown default: break
                }
                preview = nil
            }
            HStack {
                Text(playbackTime(position)).accessibilityIdentifier("playbackElapsed")
                Spacer()
                Text("−" + playbackTime(duration - position)).accessibilityLabel("剩余 \(playbackTime(duration - position))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

#if os(iOS)
private struct AudioOutputPicker: UIViewRepresentable {
    @Environment(\.colorScheme) private var scheme

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(Sunset.accent(scheme))
        view.activeTintColor = UIColor(Sunset.accent(scheme))
    }
}
#endif
