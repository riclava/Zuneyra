import Foundation
import AVFoundation
import CryptoKit
import SQLite3

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let trackNumber: Int
    let duration: Double
    let filename: String
    let digest: String
    let artwork: String?
    var favorite = false
    var albumKey: String { album + "\u{1F}" + albumArtist }
}

struct ImportReport: Sendable {
    var added = 0
    var duplicates = 0
    var failures: [String] = []
    var summary: String { "已导入 \(added) 首，跳过 \(duplicates) 首重复音乐" }
}

/// Owns all file and database I/O, away from the UI actor.
actor MusicRepository {
    let root: URL
    private var database: OpaquePointer?
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "alac", "flac", "wav", "aif", "aiff"]

    init(root: URL = URL.applicationSupportDirectory.appending(path: "Zuneyra", directoryHint: .isDirectory)) {
        self.root = root
    }

    deinit { if let database { sqlite3_close(database) } }

    private func open() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(at: root.appending(path: "Media"), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(root.appending(path: "library.sqlite").path, &db) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw failure("无法打开音乐库数据库")
        }
        database = db
        do {
            try execute("CREATE TABLE IF NOT EXISTS tracks (id TEXT PRIMARY KEY, digest TEXT UNIQUE NOT NULL, payload BLOB NOT NULL)")
            try execute("PRAGMA user_version = 1")
            // Incomplete imports never have a database row. Clean only our staging files.
            let staging = root.appending(path: "Staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for url in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
                try? FileManager.default.removeItem(at: url)
            }
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
            #endif
        } catch {
            sqlite3_close(db); database = nil; throw error
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Zuneyra.Library", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw failure(String(cString: sqlite3_errmsg(database)))
        }
    }
    func load() throws -> [Track] {
        try open()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM tracks ORDER BY rowid DESC", -1, &statement, nil) == SQLITE_OK else { throw failure("无法读取音乐库") }
        defer { sqlite3_finalize(statement) }
        var tracks: [Track] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            let size = Int(sqlite3_column_bytes(statement, 0))
            guard let bytes = sqlite3_column_blob(statement, 0) else { throw failure("音乐库记录损坏") }
            tracks.append(try JSONDecoder().decode(Track.self, from: Data(bytes: bytes, count: size)))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw failure("音乐库读取未完成") }
        return tracks
    }
    func save(_ track: Track) throws {
        try open()
        let payload = try JSONEncoder().encode(track)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO tracks(id,digest,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw failure("无法保存音乐库") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, track.id.uuidString, -1, transient)
        sqlite3_bind_text(statement, 2, track.digest, -1, transient)
        _ = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(payload.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("无法保存歌曲：\(String(cString: sqlite3_errmsg(database)))") }
    }
    func mediaURL(for track: Track) -> URL { root.appending(path: "Media/\(track.filename)") }
    func artworkData(for track: Track) throws -> Data? {
        guard let artwork = track.artwork else { return nil }
        return try Data(contentsOf: root.appending(path: "Media/\(artwork)"))
    }

    func importFiles(_ urls: [URL], progress: @Sendable (Int, Int) async -> Void) async throws -> ImportReport {
        let existing = try load()
        var hashes = Set(existing.map(\.digest))
        var report = ImportReport()
        // Hold directory authorization throughout enumeration and all child reads.
        let access = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { access.forEach { $0.stopAccessingSecurityScopedResource() } }
        var files: [URL] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { report.failures.append("无法读取文件夹：\(url.lastPathComponent)"); continue }
                while let child = enumerator.nextObject() as? URL {
                    let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values.isRegularFile == true && values.isSymbolicLink != true && Self.extensions.contains(child.pathExtension.lowercased()) { files.append(child) }
                }
            } else { files.append(url) }
        }
        for (index, url) in files.enumerated() {
            if Task.isCancelled { break }
            do {
                guard Self.extensions.contains(url.pathExtension.lowercased()) else { throw failure("不支持的文件格式") }
                let track = try await ingest(url, knownHashes: hashes)
                if let track { hashes.insert(track.digest); report.added += 1 } else { report.duplicates += 1 }
            } catch { report.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            await progress(index + 1, files.count)
        }
        return report
    }

    private func ingest(_ source: URL, knownHashes: Set<String>) async throws -> Track? {
        let id = UUID()
        let name = "\(id.uuidString).\(source.pathExtension.lowercased())"
        let staging = root.appending(path: "Staging/\(name)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinated in
            do { try FileManager.default.copyItem(at: coordinated, to: staging) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError as NSError? { throw error }
        let file = try FileHandle(forReadingFrom: staging)
        defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        if knownHashes.contains(digest) { return nil }
        let asset = AVURLAsset(url: staging)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw failure("无法解码此音频") }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw failure("音频时长无效") }
        let metadata = try await asset.load(.commonMetadata)
        func text(_ key: AVMetadataKey) async -> String? {
            guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
            let value = try? await item.load(.stringValue)
            return value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        let title = await text(.commonKeyTitle) ?? source.deletingPathExtension().lastPathComponent
        let artist = await text(.commonKeyArtist) ?? "未知艺术家"
        let album = await text(.commonKeyAlbumName) ?? "未命名专辑"
        var artworkName: String?
        if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }), let data = try? await item.load(.dataValue), data.count <= 12_000_000 {
            artworkName = "\(id.uuidString).artwork"
            try data.write(to: root.appending(path: "Media/\(artworkName!)"), options: .atomic)
        }
        let fullMetadata = (try? await asset.load(.metadata)) ?? []
        var albumArtist = artist
        var trackNumber = 0
        for item in fullMetadata {
            let identifier = item.identifier?.rawValue ?? ""
            if identifier.hasSuffix("TPE2") || identifier.hasSuffix("aART"), let value = try? await item.load(.stringValue), !value.isEmpty { albumArtist = value }
            if identifier.hasSuffix("TRCK"), let value = try? await item.load(.stringValue) { trackNumber = Int(value.split(separator: "/").first.map(String.init) ?? "") ?? 0 }
            if identifier.hasSuffix("trkn"), let data = try? await item.load(.dataValue), data.count >= 4 { trackNumber = Int(data[2]) * 256 + Int(data[3]) }
        }
        let track = Track(id: id, title: title, artist: artist, album: album, albumArtist: albumArtist, trackNumber: trackNumber, duration: duration, filename: name, digest: digest, artwork: artworkName)
        let destination = root.appending(path: "Media/\(name)")
        do {
            try FileManager.default.moveItem(at: staging, to: destination)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            #endif
            try save(track)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if let artworkName { try? FileManager.default.removeItem(at: root.appending(path: "Media/\(artworkName)")) }
            throw error
        }
        return track
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
