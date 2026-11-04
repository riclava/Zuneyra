import SwiftUI

/// Keep progress observation local so ticking playback does not rebuild the music library.
struct MiniPlayerView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let track: Track
    var openPlayer: () -> Void
    var openQueue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                Rectangle().fill(Sunset.accent(scheme).opacity(0.15))
                Rectangle().fill(Sunset.accent(scheme))
                    .frame(width: proxy.size.width * min(1, max(0, store.position / max(track.duration, 0.01))))
            }.frame(height: 2).accessibilityHidden(true)
            HStack(spacing: 8) {
                Button { openPlayer() } label: {
                    HStack(spacing: 12) {
                        CoverArt(track: track, repository: store.repository).frame(width: 46, height: 46).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开正在播放：\(track.title)")
                    .accessibilityHint("打开完整播放器与播放队列")
                #if os(macOS)
                Button { store.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("上一首")
                #endif
                Button { store.toggle() } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44).background(Sunset.coral, in: Circle()).foregroundStyle(.white)
                }.accessibilityLabel(store.isPlaying ? "暂停" : "播放")
                if !dynamicTypeSize.isAccessibilitySize {
                    Button { store.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("下一首")
                }
                #if os(macOS)
                PlaybackTimeline(track: track).id(track.id).frame(width: 180)
                Button { openQueue() } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }.accessibilityLabel("播放队列")
                #endif
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Sunset.panel(scheme))
    }
}
