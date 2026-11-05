import Foundation

/// Bounded readers for tags that AVFoundation does not consistently expose.
struct ExtendedMetadata {
    var values: [String: String] = [:]
    var artwork: Data?
    var replayGain: ReplayGain {
        var gain = ReplayGain()
        for (key, value) in values { gain.set(key, value: value) }
        return gain
    }
    init(url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let signature = try file.read(upToCount: 4) else { return }
        if signature == Data("fLaC".utf8) {
            var total = 0
            while let header = try file.read(upToCount: 4), header.count == 4 {
                let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
                total += size
                guard total <= 32_000_000, let data = try file.read(upToCount: size), data.count == size else { return }
                if header[0] & 127 == 4 { readComments(data) }
                if header[0] & 127 == 6 { readPicture(data) }
                if header[0] & 128 != 0 { break }
            }
        } else if signature.prefix(3) == Data("ID3".utf8) {
            try file.seek(toOffset: 0)
            guard let header = try file.read(upToCount: 10), header.count == 10,
                  [3, 4].contains(header[3]), header[5] == 0,
                  header[6..<10].allSatisfy({ $0 < 128 }) else { return }
            let size = header[6..<10].reduce(0) { ($0 << 7) | Int($1) }
            guard size <= 16_000_000, let data = try file.read(upToCount: size), data.count == size else { return }
            var offset = 0
            while offset + 10 <= data.count {
                let id = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
                let length = data[offset+4..<offset+8].reduce(0) { ($0 << (header[3] == 4 ? 7 : 8)) | Int($1) }
                guard length > 0, length <= data.count - offset - 10 else { break }
                if id == "TXXX", data[offset+8] == 0, data[offset+9] == 0 {
                    let body = Data(data[offset+10..<offset+10+length])
                    if let encoding = body.first {
                        let charset: String.Encoding? = switch encoding { case 0: .isoLatin1; case 1: .utf16; case 2: .utf16BigEndian; case 3: .utf8; default: nil }
                        if let charset, let text = String(data: body.dropFirst(), encoding: charset) {
                            let parts = text.components(separatedBy: "\0")
                            if parts.count >= 2 { values[parts[0].uppercased()] = parts[1] }
                        }
                    }
                }
                offset += 10 + length
            }
        }
    }
    private mutating func readComments(_ data: Data) {
        var offset = 0
        func number() -> Int? {
            guard offset + 4 <= data.count else { return nil }
            defer { offset += 4 }
            return (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard let vendor = number(), vendor <= data.count - offset else { return }
        offset += vendor
        guard let count = number(), count <= 100_000 else { return }
        for _ in 0..<count {
            guard let length = number(), length <= data.count - offset else { return }
            if let text = String(data: data[offset..<offset+length], encoding: .utf8), let split = text.firstIndex(of: "=") {
                let key = String(text[..<split]).uppercased(), value = String(text[text.index(after: split)...])
                if values[key] == nil { values[key] = value }
            }
            offset += length
        }
    }
    private mutating func readPicture(_ data: Data) {
        var offset = 0
        func number() -> Int? {
            guard offset + 4 <= data.count else { return nil }
            defer { offset += 4 }
            return data[offset..<offset+4].reduce(0) { ($0 << 8) | Int($1) }
        }
        guard let type = number(), let mime = number(), mime <= data.count - offset else { return }
        offset += mime
        guard let description = number(), description <= data.count - offset else { return }
        offset += description
        for _ in 0..<4 { guard number() != nil else { return } }
        guard let length = number(), length <= 12_000_000, length <= data.count - offset, type == 3 || artwork == nil else { return }
        artwork = Data(data[offset..<offset+length])
    }
}
