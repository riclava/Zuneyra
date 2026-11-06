import SwiftUI

/// A real album from the library, with explicit playback and browsing actions.
struct CollectionFeatureView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let track: Track
    let repository: MusicRepository
    let summary: String
    let isCurrent: Bool
    let isPlaying: Bool
    let disabled: Bool
    var play: () -> Void
    var browse: () -> Void
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if compact && !typeSize.isAccessibilitySize {
                HStack(spacing: 16) {
                    sleeve.frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isCurrent ? String(localized: "最近聆听") : String(localized: "从一张专辑开始"))
                            .font(.caption.weight(.medium)).foregroundStyle(Sunset.accent(scheme))
                        Text(track.album).font(.system(.title3, design: .serif, weight: .medium))
                            .lineLimit(1).accessibilityAddTraits(.isHeader)
                        Text(track.albumArtist + " · " + summary)
                            .font(.caption).foregroundStyle(Sunset.secondary(scheme)).lineLimit(1)
                        HStack(spacing: 8) {
                            SwipeSafeButton(action: play) {
                                Image(systemName: "play.fill").frame(width: 44, height: 44)
                                    .foregroundStyle(.white)
                                    .background(Sunset.accent(scheme), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).protectLibraryAction().disabled(disabled)
                                .accessibilityLabel(isCurrent ? String(localized: "继续聆听") : String(localized: "播放专辑"))
                            browseButton
                        }
                    }.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                }
            }
            if !typeSize.isAccessibilitySize {
                HStack(spacing: compact ? 24 : 36) {
                    VStack(alignment: .leading, spacing: compact ? 14 : 22) {
                        heading
                        actions
                    }.frame(minWidth: 230, maxWidth: .infinity, alignment: .leading)
                    sleeve.frame(width: compact ? 160 : 208, height: compact ? 160 : 208)
                }
            }
            VStack(alignment: .leading, spacing: 20) {
                if typeSize.isAccessibilitySize {
                    sleeve.frame(width: 132, height: 132)
                    heading
                } else {
                    HStack(alignment: .center, spacing: 20) {
                        sleeve.frame(width: 108, height: 108)
                        heading
                    }
                }
                actions
            }
        }
        .padding(compact ? 16 : 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sunset.panel(scheme).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isCurrent ? String(localized: "最近聆听") : String(localized: "从一张专辑开始"))
                .font(.caption.weight(.medium)).foregroundStyle(Sunset.accent(scheme))
            Text(track.album).font(.system(.title2, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(track.albumArtist).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
            Text(summary).font(.caption).foregroundStyle(Sunset.secondary(scheme))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sleeve: some View {
        CoverArt(track: track, repository: repository, cornerRadius: 2)
            .padding(5).background(Sunset.elevated(scheme))
            .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.14), radius: 12, x: 0, y: 7)
            .rotationEffect(.degrees(-3))
            .accessibilityHidden(true)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { playButton; browseButton }
            VStack(alignment: .leading, spacing: 8) { playButton; browseButton }
        }
    }
    private var playButton: some View {
        SwipeSafeButton(action: play) {
            Label(isCurrent ? (isPlaying ? String(localized: "打开播放器") : String(localized: "继续聆听")) : String(localized: "播放专辑"), systemImage: "play.fill")
        }.buttonStyle(StudioButtonStyle(prominent: true)).protectLibraryAction().disabled(disabled)
    }
    private var browseButton: some View {
        SwipeSafeButton(action: browse) {
            HStack(spacing: 8) { Text(String(localized: "查看专辑")); Image(systemName: "arrow.up.right").font(.caption) }
                .font(.subheadline).frame(minHeight: 44)
        }.buttonStyle(.plain).protectLibraryAction().foregroundStyle(Sunset.secondary(scheme))
    }
}
