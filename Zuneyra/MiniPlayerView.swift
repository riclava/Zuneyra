import SwiftUI

/// Keep progress observation local so ticking playback does not rebuild the music library.
struct MiniPlayerView: View {
    @Environment(PlayerStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let track: Track
    var openPlayer: () -> Void
    var openQueue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                Rectangle().fill(Sunset.paper.opacity(0.10))
                Rectangle().fill(Sunset.accent(.dark))
                    .frame(width: proxy.size.width * min(1, max(0, store.position / max(track.duration, 0.01))))
            }.frame(height: 2).accessibilityHidden(true)
            HStack(spacing: 16) {
                Button { openPlayer() } label: {
                    HStack(spacing: 14) {
                        CoverArt(track: track, repository: store.repository, cornerRadius: 4)
                            .frame(width: 50, height: 50).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.system(.subheadline, design: .serif).weight(.semibold))
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            Text(track.artist).font(.caption).foregroundStyle(Sunset.paper.opacity(0.62)).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开正在播放：\(track.title)")
                    .accessibilityHint("打开完整播放器与播放队列")

                HStack(spacing: 8) {
                    #if os(macOS)
                    Button { store.previous() } label: {
                        Image(systemName: "backward.end.fill").frame(width: 40, height: 44)
                    }.accessibilityLabel("上一首")
                    #endif
                    Button { store.toggle() } label: {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .background(Sunset.brand, in: Circle())
                            .foregroundStyle(Sunset.paper)
                    }.accessibilityLabel(store.isPlaying ? "暂停" : "播放")
                    if !dynamicTypeSize.isAccessibilitySize {
                        Button { store.next() } label: {
                            Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("下一首")
                    }
                }.disabled(store.isManaging)
                #if os(macOS)
                PlaybackTimeline(track: track).id(track.id).frame(width: 180).padding(.horizontal, 12)
                Button { openQueue() } label: {
                    Image(systemName: "list.bullet").frame(width: 44, height: 44)
                }.accessibilityLabel("播放队列")
                #endif
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .foregroundStyle(Sunset.paper)
        .background(Sunset.ink)
        .tint(Sunset.accent(.dark))
        .environment(\.colorScheme, .dark)
    }
}
