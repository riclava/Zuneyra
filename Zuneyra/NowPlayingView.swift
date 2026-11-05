import SwiftUI
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingAudioSettings = false
    @State private var showingTrackInfo = false
    @State private var trackToAddToPlaylist: Track?
    @State private var showingLyrics = false
    @State private var navigation = PageNavigation<Int>()

    var body: some View {
        NavigationStack(path: Binding(get: { navigation.path }, set: { navigation.setPath($0) })) {
            VStack(spacing: 0) {
                CollectionSheetHeader(title: String(localized: "正在聆听"), subtitle: String(localized: "ZUNEYRA · 私人唱片室"), close: { dismiss() })
                GeometryReader { geometry in
                    let layout = AdaptiveLayout(size: geometry.size, accessibility: typeSize.isAccessibilitySize)
                    HStack(spacing: 0) {
                        Group {
                            if let track = store.current {
                                player(track, horizontal: geometry.size.width >= 600 && !layout.playerCompanion && !typeSize.isAccessibilitySize, compact: geometry.size.height < 560)
                            } else {
                                StudioEmptyState(symbol: "play.square", title: String(localized: "尚未播放"), detail: String(localized: "从音乐库选择一首歌曲，开始聆听。"))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Group {
                            PlaybackQueueView(showsClose: false, embedded: true)
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
            .navigationDestination(for: Int.self) { _ in
                PlaybackQueueView(showsClose: false)
            }
        }
        .edgeNavigation(
            back: { if navigation.canGoBack { navigation.back() } else { dismiss() } },
            forward: navigation.canGoForward ? { navigation.forward() } : nil
        )
        .tint(Sunset.accent(scheme))
        .sheet(item: $trackToAddToPlaylist) { track in
            AddToPlaylistView(tracks: [track], onComplete: { trackToAddToPlaylist = nil })
                .environment(store)
        }
        #if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 480, idealHeight: 640, maxHeight: 700)
        #endif
    }

    private func player(_ track: Track, horizontal: Bool, compact: Bool) -> some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: compact ? 8 : 20))
        return VStack(spacing: compact ? 8 : 20) {
            layout {
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        let side = max(0, min(300, min(geometry.size.width, geometry.size.height)))
                        ZStack {
                            // Keep both layers mounted so artwork is not reloaded on each toggle.
                            Button { showingLyrics = true } label: {
                                CoverArt(track: track, repository: store.repository, cornerRadius: 12)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "quote.bubble")
                                            .font(.body.weight(.medium))
                                            .frame(width: 44, height: 44)
                                            .background(Sunset.panel(scheme).opacity(0.94), in: Circle())
                                            .padding(8)
                                    }
                            }
                            .buttonStyle(ArtworkModeButtonStyle())
                            .accessibilityLabel(String(localized: "显示歌词"))
                            .accessibilityHint(String(localized: "点击封面切换到歌词模式"))
                            .compositingGroup()
                            .opacity(showingLyrics ? 0 : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showingLyrics)
                            .allowsHitTesting(!showingLyrics)
                            .accessibilityHidden(showingLyrics)

                            LyricsView { showingLyrics = false }
                                .compositingGroup()
                                .opacity(showingLyrics ? 1 : 0)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showingLyrics)
                                .allowsHitTesting(showingLyrics)
                                .accessibilityHidden(!showingLyrics)
                        }
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if horizontal && compact { utilityLinks }
                }
                VStack(spacing: compact ? 4 : 16) {
                    trackDetails(track, compact: compact)
                    if !compact { Rectangle().fill(Sunset.stroke(scheme)).frame(height: 1) }
                    if !horizontal || !compact { utilityLinks }
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Keep the seek bar and transport together, anchored above the safe area.
            VStack(spacing: compact ? 4 : 16) {
                PlaybackTimeline(track: track).id(track.id)
                PlayerTransportControls(compact: compact)
            }
            .frame(maxWidth: 460)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)
        }
        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, compact ? 8 : 20)
        .frame(maxWidth: horizontal ? 1000 : 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var utilityLinks: some View {
        HStack(spacing: 0) {
            Button { showingTrackInfo = true } label: {
                Image(systemName: "info.circle").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "歌曲信息"))
            .help(String(localized: "歌曲信息"))
            .popover(isPresented: $showingTrackInfo) {
                trackInfo
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
            Spacer(minLength: 0)
            Button {
                trackToAddToPlaylist = store.current
            } label: {
                Image(systemName: "text.badge.plus").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "添加到歌单"))
            .help(String(localized: "添加到歌单"))
            .disabled(store.current == nil || store.isBusy)
            Spacer(minLength: 0)
            audioOutput
            Spacer(minLength: 0)
            Button { showingAudioSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "播放设置"))
            .accessibilityValue(store.replayGainMode.title)
            .popover(isPresented: $showingAudioSettings) {
                audioSettings
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
            Spacer(minLength: 0)
            if let track = store.current {
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
        .font(.subheadline)
        .foregroundStyle(Sunset.secondary(scheme))
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "歌曲信息")).font(.headline)
                Spacer()
                Button { showingTrackInfo = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "关闭"))
            }
            if let track = store.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(track.title).font(.headline).textSelection(.enabled)
                        Text(track.artist).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
                        LabeledContent(String(localized: "专辑"), value: track.album)
                        LabeledContent(String(localized: "时长"), value: playbackTime(track.duration.isFinite ? max(0, track.duration) : 0))
                        LabeledContent(String(localized: "文件格式")) { fileFormat(track) }
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Sunset.panel(scheme))
    }

    private var audioSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "音量均衡")).font(.headline)
                    Text("ReplayGain").font(.caption).foregroundStyle(Sunset.secondary(scheme))
                }
                Spacer()
                Button { showingAudioSettings = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "关闭"))
            }
            Text(String(localized: "根据音乐文件中的增益信息，减少歌曲之间的音量差异。"))
                .font(.caption).foregroundStyle(Sunset.secondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                ForEach(ReplayGainMode.allCases) { mode in
                    Button { store.setReplayGainMode(mode) } label: {
                        Text(mode.shortTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(store.replayGainMode == mode ? Sunset.brand : .clear, in: Capsule())
                            .foregroundStyle(store.replayGainMode == mode ? Sunset.paper : Sunset.secondary(scheme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(store.replayGainMode == mode ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Sunset.secondary(scheme).opacity(0.08), in: Capsule())
            .disabled(store.isManaging)
        }
        .padding(16)
        .frame(width: 300)
        .background(Sunset.panel(scheme))
    }

    private func trackDetails(_ track: Track, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(track.title)
                .font(.system(compact ? .headline : .title, design: .serif).weight(.semibold))
                .lineLimit(compact ? 1 : 2)
                .accessibilityAddTraits(.isHeader)
            Text("\(track.artist) · \(track.album)")
                .lineLimit(1).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileFormat(_ track: Track) -> some View {
        Text(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO")
            .font(.caption2.weight(.medium)).tracking(1.2)
            .foregroundStyle(Sunset.secondary(scheme))
            .accessibilityLabel(String(localized: "音频格式 \(track.filename.components(separatedBy: ".").last?.uppercased() ?? "AUDIO")"))
    }

    @ViewBuilder private var audioOutput: some View {
        #if os(iOS)
        AudioOutputPicker().frame(width: 44, height: 44)
            .accessibilityLabel(String(localized: "音频输出"))
        #else
        Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
            .accessibilityLabel(String(localized: "本机播放"))
            .help(String(localized: "本机播放"))
        #endif
    }
}

/// Artwork is a mode switch, not a tinted control: retain its colors while pressed.
private struct ArtworkModeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Fixed transport controls remain available in both artwork and lyrics modes.
struct PlayerTransportControls: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    var compact = false

    var body: some View {
        HStack(spacing: 0) {
            Button { store.cyclePlaybackMode() } label: {
                Image(systemName: store.queueState.playbackMode.symbol)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .bottom) {
                        if store.queueState.playbackMode != .sequential {
                            Circle().fill(Sunset.accent(scheme)).frame(width: 4, height: 4)
                        }
                    }
            }
            .foregroundStyle(store.queueState.playbackMode == .sequential ? Sunset.secondary(scheme) : Sunset.accent(scheme))
            .accessibilityLabel(String(localized: "播放模式"))
            .accessibilityValue(store.queueState.playbackMode.title)
            .accessibilityHint(String(localized: "依次切换顺序播放、列表循环、单曲循环和随机播放"))
            .help(store.queueState.playbackMode.title)
            Spacer(minLength: 0)
            Button { store.previous() } label: {
                Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel(String(localized: "上一首"))
            Spacer(minLength: 0)
            Button { store.toggle() } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .frame(width: compact ? 56 : 72, height: compact ? 56 : 72)
                    .background(Sunset.brand, in: Circle())
                    .foregroundStyle(Sunset.paper)
            }.accessibilityLabel(store.isPlaying ? String(localized: "暂停") : String(localized: "播放"))
            Spacer(minLength: 0)
            Button { store.next() } label: {
                Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel(String(localized: "下一首"))
            Spacer(minLength: 0)
            NavigationLink(value: 1) {
                Image(systemName: "music.note.list").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "播放队列"))
            .accessibilityValue(String(localized: "\(store.queueState.upcoming.count) 首待播"))
        }
        .buttonStyle(.plain)
        .disabled(store.isManaging)
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
