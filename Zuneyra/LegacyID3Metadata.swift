import Foundation
import CoreFoundation

/// Some legacy Chinese MP3s store GBK/GB18030 in ID3v1's Latin-1 fields.
/// Only correct an exact Latin-1 interpretation of the raw field, and only
/// when a clearly Chinese artist establishes the legacy encoding context.
struct LegacyID3Metadata {
    let title: Data
    let artist: Data
    let album: Data
    private static let chineseEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    init?(url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 128 else { return nil }
        try file.seek(toOffset: size - 128)
        guard let bytes = try file.read(upToCount: 128), bytes.count == 128, bytes.prefix(3) == Data("TAG".utf8) else { return nil }
        func field(_ range: Range<Int>) -> Data {
            var data = Data(bytes[range])
            while data.last == 0 || data.last == 32 { data.removeLast() }
            return data
        }
        title = field(3..<33); artist = field(33..<63); album = field(63..<93)
    }

    private func chinese(_ bytes: Data) -> String? {
        guard bytes.contains(where: { $0 >= 128 }), let value = String(data: bytes, encoding: Self.chineseEncoding), value.data(using: Self.chineseEncoding) == bytes else { return nil }
        return value
    }
    private var hasChineseContext: Bool {
        guard let value = chinese(artist) else { return false }
        let scalars = value.unicodeScalars
        let count = scalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        return count >= 2 && scalars.allSatisfy { (0x3400...0x9FFF).contains($0.value) || CharacterSet.whitespaces.contains($0) || "·・&".unicodeScalars.contains($0) }
    }
    func correctedTitle(_ value: String?) -> String? { corrected(value, field: title) }
    func correctedArtist(_ value: String?) -> String? { corrected(value, field: artist) }
    func correctedAlbum(_ value: String?) -> String? { corrected(value, field: album) }

    private func corrected(_ value: String?, field: Data) -> String? {
        guard hasChineseContext, let decoded = chinese(field) else { return value }
        // Valid Unicode ID3v2 and accented Western metadata remain untouched.
        guard value == nil || value == String(data: field, encoding: .isoLatin1) else { return value }
        return decoded
    }
}
