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
            VStack(spacing: 0) {
                CollectionSheetHeader(title: "正在聆听", subtitle: "ZUNEYRA · 私人唱片室", close: { dismiss() })
                GeometryReader { geometry in
                    ScrollView {
                        if let track = store.current {
                            VStack(spacing: 24) {
                                CoverArt(track: track, repository: store.repository, cornerRadius: 12)
                                    .frame(maxWidth: typeSize.isAccessibilitySize ? 120 : min(320, max(160, geometry.size.height * 0.40)))
                                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                                    .shadow(color: Sunset.ink.opacity(scheme == .dark ? 0.4 : 0.18), radius: 24, x: 0, y: 14)
                                    .accessibilityHidden(true)

                                trackDetails(track)
                                VStack(spacing: 12) {
                                    PlaybackTimeline(track: track).id(track.id)
                                    transportControls
                                    PlaybackModesView()
                                }
                                VStack(spacing: 4) {
                                    queueLink
                                    Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
                                    outputDetails(track)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Sunset.elevated(scheme).opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Sunset.stroke(scheme), lineWidth: 1) }
                            }
                            .padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 24)
                            .frame(maxWidth: 460)
                            .frame(maxWidth: .infinity)
                        } else {
                            StudioEmptyState(symbol: "play.square", title: "尚未播放", detail: "从音乐库选择一首歌曲，开始聆听。")
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                LinearGradient(colors: [Sunset.panel(scheme), Sunset.background(scheme), Sunset.background(scheme)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .collectionSheetChrome()
        }
        .tint(Sunset.accent(scheme))
        #if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 480, idealHeight: 640, maxHeight: 700)
        #endif
    }

    private func trackDetails(_ track: Track) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.isPlaying ? "正在播放" : "已暂停", systemImage: store.isPlaying ? "waveform" : "pause.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(Sunset.accent(scheme))
                Text(track.title)
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(track.artist).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
                Text(track.album).font(.caption).foregroundStyle(Sunset.secondary(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.toggleFavorite(track) } label: {
                Image(systemName: track.favorite ? "heart.fill" : "heart")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .background(track.favorite ? Sunset.accent(scheme).opacity(0.10) : .clear, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Sunset.accent(scheme))
            .accessibilityLabel(track.favorite ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
            .accessibilityValue(track.favorite ? "已收藏" : "未收藏")
            .disabled(store.isManaging)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 32) {
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill").font(.title3).frame(width: 56, height: 56)
            }.accessibilityLabel("上一首")
            Button { store.toggle() } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 76, height: 76)
                    .background(Sunset.brand, in: Circle())
                    .foregroundStyle(Sunset.paper)
                    .shadow(color: Sunset.brand.opacity(0.20), radius: 12, x: 0, y: 6)
            }.accessibilityLabel(store.isPlaying ? "暂停" : "播放")
            Button { store.next() } label: {
                Image(systemName: "forward.end.fill").font(.title3).frame(width: 56, height: 56)
            }.accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
        .disabled(store.isManaging)
    }

    private var queueLink: some View {
        NavigationLink { PlaybackQueueView(showsClose: false) } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.subheadline).foregroundStyle(Sunset.accent(scheme))
                Text("播放队列").font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text("\(store.queueState.upcoming.count) 首待播")
                    .font(.caption.monospacedDigit()).foregroundStyle(Sunset.secondary(scheme))
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Sunset.secondary(scheme))
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            .font(.caption2.weight(.medium)).tracking(1.2)
            .foregroundStyle(Sunset.secondary(scheme))
            .accessibilityLabel("音频格式 \(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO")")
    }

    @ViewBuilder private var audioOutput: some View {
        #if os(iOS)
        HStack(spacing: 4) {
            Text("音频输出").font(.caption).foregroundStyle(Sunset.secondary(scheme))
                .accessibilityHidden(true)
            AudioOutputPicker().frame(width: 48, height: 48)
        }
        #else
        Label("本机播放", systemImage: "speaker.wave.2").font(.caption).foregroundStyle(Sunset.secondary(scheme))
        #endif
    }
}

/// Preview changes while dragging; only send the final position to the playback engine.
struct PlaybackTimeline: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
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
                Text(playbackTime(position))
                Spacer()
                Text("−" + playbackTime(duration - position)).accessibilityLabel("剩余 \(playbackTime(duration - position))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Sunset.secondary(scheme))
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
