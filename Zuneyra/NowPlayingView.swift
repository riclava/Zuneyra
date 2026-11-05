import SwiftUI
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    @State private var companion = 1
    @State private var navigation = PageNavigation<Int>()

    var body: some View {
        NavigationStack(path: Binding(get: { navigation.path }, set: { navigation.setPath($0) })) {
            VStack(spacing: 0) {
                CollectionSheetHeader(title: String(localized: "正在聆听"), subtitle: String(localized: "ZUNEYRA · 私人唱片室"), close: { dismiss() })
                GeometryReader { geometry in
                    let layout = AdaptiveLayout(size: geometry.size, accessibility: typeSize.isAccessibilitySize)
                    HStack(spacing: 0) {
                        ScrollView {
                            if let track = store.current {
                                player(track, size: geometry.size, horizontal: layout.horizontalPlayer && !layout.playerCompanion)
                            } else {
                                StudioEmptyState(symbol: "play.square", title: String(localized: "尚未播放"), detail: String(localized: "从音乐库选择一首歌曲，开始聆听。"))
                                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            }
                        }
                        Group {
                            VStack(spacing: 0) {
                                Picker(String(localized: "正在聆听"), selection: $companion) {
                                    Text(String(localized: "播放队列")).tag(1)
                                    Text(String(localized: "歌词")).tag(2)
                                }.pickerStyle(.segmented).padding()
                                if companion == 2 {
                                    LyricsView(embedded: true)
                                } else {
                                    PlaybackQueueView(showsClose: false, embedded: true)
                                }
                            }
                            .frame(width: max(360, geometry.size.width * 0.45))
                            .overlay(alignment: .leading) { Rectangle().fill(Sunset.stroke(scheme)).frame(width: 1) }
                        }
                        .frame(width: layout.playerCompanion ? geometry.size.width * 0.45 : 0)
                        .clipped()
                        .opacity(layout.playerCompanion ? 1 : 0)
                        .allowsHitTesting(layout.playerCompanion)
                        .accessibilityHidden(!layout.playerCompanion)
                    }

                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                LinearGradient(colors: [Sunset.panel(scheme), Sunset.background(scheme), Sunset.background(scheme)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .collectionSheetChrome()
            .navigationDestination(for: Int.self) { value in
                if value == 2 { LyricsView() } else { PlaybackQueueView(showsClose: false) }
            }
        }
        .edgeNavigation(
            back: navigation.canGoBack ? { navigation.back() } : nil,
            forward: navigation.canGoForward ? { navigation.forward() } : nil
        )
        .tint(Sunset.accent(scheme))
        #if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 480, idealHeight: 640, maxHeight: 700)
        #endif
    }

    private func player(_ track: Track, size: CGSize, horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
        return layout {
            CoverArt(track: track, repository: store.repository, cornerRadius: 12)
                .frame(maxWidth: typeSize.isAccessibilitySize ? 120 : (horizontal ? min(300, size.width * 0.32) : min(320, max(160, size.height * 0.40))))
                .accessibilityHidden(true)
            VStack(spacing: 20) {
                trackDetails(track)
                PlaybackTimeline(track: track).id(track.id)
                transportControls
                PlaybackModesView()
                ViewThatFits(in: .horizontal) {
                    HStack { replayGainLabel; Spacer(); replayGainPicker }
                    VStack(alignment: .leading) { replayGainLabel; replayGainPicker }
                }
                VStack(spacing: 4) {
                    queueLink
                    NavigationLink(String(localized: "歌词"), value: 2).frame(minHeight: 44)
                    Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1)
                    outputDetails(track)
                }
                .padding(12)
                .background(Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        .frame(maxWidth: horizontal ? 1000 : 460)
        .frame(maxWidth: .infinity)
    }

    private var replayGainLabel: some View {
        Text("ReplayGain").font(.subheadline).foregroundStyle(.secondary)
    }

    private var replayGainPicker: some View {
        Picker("ReplayGain", selection: Binding(get: { store.replayGainMode }, set: { store.setReplayGainMode($0) })) {
            ForEach(ReplayGainMode.allCases) { mode in Text(mode.title).tag(mode) }
        }.labelsHidden()
    }

    private func trackDetails(_ track: Track) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.isPlaying ? String(localized: "正在播放") : String(localized: "已暂停"), systemImage: store.isPlaying ? "waveform" : "pause.circle")
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
            .accessibilityLabel(track.favorite ? String(localized: "取消收藏 \(track.title)") : String(localized: "收藏 \(track.title)"))
            .accessibilityValue(track.favorite ? String(localized: "已收藏") : String(localized: "未收藏"))
            .disabled(store.isManaging)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 16) {
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill").font(.title3).frame(width: 56, height: 56)
            }.accessibilityLabel(String(localized: "上一首"))
            Button { store.toggle() } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: 76, height: 76)
                    .background(Sunset.brand, in: Circle())
                    .foregroundStyle(Sunset.paper)
                    .shadow(color: Sunset.brand.opacity(0.20), radius: 12, x: 0, y: 6)
            }.accessibilityLabel(store.isPlaying ? String(localized: "暂停") : String(localized: "播放"))
            Button { store.next() } label: {
                Image(systemName: "forward.end.fill").font(.title3).frame(width: 56, height: 56)
            }.accessibilityLabel(String(localized: "下一首"))
        }
        .buttonStyle(.plain)
        .disabled(store.isManaging)
    }

    private var queueLink: some View {
        NavigationLink(value: 1) {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.subheadline).foregroundStyle(Sunset.accent(scheme))
                Text(String(localized: "播放队列")).font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text(String(localized: "\(store.queueState.upcoming.count) 首待播"))
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
            .accessibilityLabel(String(localized: "音频格式 \(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO")"))
    }

    @ViewBuilder private var audioOutput: some View {
        #if os(iOS)
        HStack(spacing: 4) {
            Text(String(localized: "音频输出")).font(.caption).foregroundStyle(Sunset.secondary(scheme))
                .accessibilityHidden(true)
            AudioOutputPicker().frame(width: 48, height: 48)
        }
        #else
        Label(String(localized: "本机播放"), systemImage: "speaker.wave.2").font(.caption).foregroundStyle(Sunset.secondary(scheme))
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
            .accessibilityLabel(String(localized: "播放进度"))
            .accessibilityValue(String(localized: "\(playbackTime(position))，共 \(playbackTime(duration))"))
            .accessibilityHint(String(localized: "每次调整可前进或后退 10 秒"))
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
                Text("−" + playbackTime(duration - position)).accessibilityLabel(String(localized: "剩余 \(playbackTime(duration - position))"))
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
