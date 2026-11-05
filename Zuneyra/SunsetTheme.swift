import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Raspberry red and cream echo the app icon; wine-tinted neutrals frame the collection.
enum Sunset {
    static let brand = color(0xD50043)
    static let ink = color(0x281A21)
    static let paper = color(0xFFF9DF)
    static let sleeveColors = [color(0xEAD9B4), color(0xE6C5CF), color(0xDFCCD1), color(0xD8CADB)]

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0xFF7C9F) : color(0xBF003C)
    }
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0x1D141B) : color(0xFFFAF0)
    }
    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0x281B24) : color(0xF7EFDF)
    }
    static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0x33212C) : color(0xFFFDF6)
    }
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? paper.opacity(0.14) : color(0xDFD1CC)
    }
    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0xC7ADB7) : color(0x705B63)
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 18)
            #if os(macOS)
            .frame(minHeight: 36)
            #else
            .frame(minHeight: 44)
            #endif
            .foregroundStyle(prominent ? Sunset.paper : Color.primary)
            .background(prominent ? Sunset.brand : Sunset.elevated(scheme), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(prominent ? Color.clear : Sunset.stroke(scheme), lineWidth: 1) }
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct StudioIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            #if os(macOS)
            .frame(minWidth: 34, minHeight: 34)
            #else
            .frame(minWidth: 44, minHeight: 44)
            #endif
            .background(configuration.isPressed ? Sunset.panel(scheme) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct StudioMark: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 1.3)
            Circle().strokeBorder(lineWidth: 0.7).padding(5)
            Circle().strokeBorder(lineWidth: 0.7).padding(9)
            Circle().frame(width: 4, height: 4)
        }.frame(width: 30, height: 30).accessibilityHidden(true)
    }
}

struct StudioEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
                .foregroundStyle(Sunset.accent(scheme))
                .frame(width: 58, height: 58)
                .background(Sunset.panel(scheme), in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.system(.title2, design: .serif, weight: .medium)).foregroundStyle(.primary)
            Text(detail).font(.subheadline).foregroundStyle(Sunset.secondary(scheme))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).frame(maxWidth: 340).padding(24)
    }
}

struct CoverArt: View {
    let track: Track
    let repository: MusicRepository
    var cornerRadius: CGFloat = 4
    @State private var image: Image?
    private struct ArtworkKey: Hashable { let trackID: UUID; let artwork: String? }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image { image.resizable().scaledToFill() }
                else {
                    AlbumSleeve(track: track)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel(String(localized: "\(track.album) 专辑封面"))
        .task(id: ArtworkKey(trackID: track.id, artwork: track.artwork)) {
            image = nil
            guard let data = try? await repository.artworkData(for: track), !Task.isCancelled else { return }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
            image = Image(decorative: cg, scale: 1)
        }
    }
}

/// One cover design for the library, player, and system Now Playing artwork.
struct AlbumSleeve: View {
    let track: Track
    private var coverColor: Color {
        let colors = Sunset.sleeveColors
        let index = track.album.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return colors[index]
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                    Rectangle().fill(coverColor)
                    ZStack {
                        Circle().fill(Sunset.ink.opacity(0.86))
                        ForEach(0..<6) { ring in
                            Circle().strokeBorder(coverColor.opacity(0.15), lineWidth: 0.6).padding(CGFloat(8 + ring * 5))
                        }
                        Circle().fill(coverColor).frame(width: proxy.size.width * 0.18, height: proxy.size.width * 0.18)
                        Circle().fill(Sunset.ink).frame(width: 3, height: 3)
                    }
                    .frame(width: proxy.size.width * (proxy.size.width > 100 ? 0.60 : 0.75),
                           height: proxy.size.width * (proxy.size.width > 100 ? 0.60 : 0.75))
                    .offset(x: proxy.size.width * 0.24, y: -proxy.size.width * (proxy.size.width > 100 ? 0.27 : 0.19))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    if proxy.size.width > 100 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("ZUNEYRA")
                                .font(.system(size: proxy.size.width * 0.033, weight: .medium, design: .serif))
                                .tracking(proxy.size.width * 0.005)
                                .padding(proxy.size.width * 0.07)
                            Spacer(minLength: 0)
                            VStack(alignment: .leading, spacing: proxy.size.width * 0.025) {
                                Text(track.album)
                                    .font(.system(size: proxy.size.width * 0.11, weight: .medium, design: .serif))
                                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                                Text(track.albumArtist)
                                    .font(.system(size: proxy.size.width * 0.05)).lineLimit(1).opacity(0.75)
                            }
                            .padding(.horizontal, proxy.size.width * 0.07)
                            .padding(.top, proxy.size.width * 0.04)
                            .padding(.bottom, proxy.size.width * 0.07)
                            .frame(width: proxy.size.width, height: proxy.size.height * 0.47, alignment: .bottomLeading)
                            .background(coverColor)
                        }.foregroundStyle(Sunset.ink)
                    }

            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.aspectRatio(1, contentMode: .fit)
    }
}

func playbackTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d", value / 60, value % 60)
}
