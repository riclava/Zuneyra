import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Sunset {
    static let coral = Color(red: 0.85, green: 0.23, blue: 0.16)
    static let peach = Color(red: 1, green: 0.70, blue: 0.61)
    static let amber = Color(red: 1, green: 0.79, blue: 0.30)
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.13, green: 0.085, blue: 0.10) : Color(red: 1, green: 0.975, blue: 0.95) }
    static func panel(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.20, green: 0.13, blue: 0.15) : Color(red: 0.98, green: 0.92, blue: 0.88) }
}

struct CoverArt: View {
    let track: Track
    let repository: MusicRepository
    @State private var image: Image?
    private struct ArtworkKey: Hashable { let trackID: UUID; let artwork: String? }
    private var warmColor: Color { [Sunset.coral, .orange, .pink, .purple][Int(track.digest.prefix(2), radix: 16).map { $0 % 4 } ?? 0] }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let image { image.resizable().scaledToFill() }
                else {
                    Rectangle().fill(LinearGradient(colors: [Sunset.peach, warmColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().fill(Sunset.amber).frame(width: proxy.size.width * 0.5).offset(x: proxy.size.width * 0.45, y: proxy.size.height * 0.3)
                    Ellipse().fill(warmColor).frame(width: proxy.size.width * 1.5, height: proxy.size.height * 0.6).rotationEffect(.degrees(-18)).offset(x: -proxy.size.width * 0.2, y: proxy.size.height * 0.64)
                    if proxy.size.width > 100 {
                        Text(track.album.uppercased()).font(.system(size: proxy.size.width * 0.15, weight: .heavy, design: .rounded)).tracking(-1).foregroundStyle(Color(red: 0.30, green: 0.08, blue: 0.13)).lineLimit(3).padding(proxy.size.width * 0.1)
                    }
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("\(track.album) 专辑封面")
        .task(id: ArtworkKey(trackID: track.id, artwork: track.artwork)) {
            image = nil
            guard let data = try? await repository.artworkData(for: track), !Task.isCancelled else { return }
            // Decode a thumbnail rather than a full-resolution embedded cover.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
            image = Image(decorative: cg, scale: 1)
        }
    }
}

func playbackTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d", value / 60, value % 60)
}
