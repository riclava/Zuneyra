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
    var metadataRepairVersion: Int?
    var albumKey: String { album + "\u{1F}" + albumArtist }
}

struct ImportReport: Codable, Sendable {
    var added = 0
    var duplicates = 0
    var failures: [String] = []
    var failureItems: [ImportFailure] = []
    var cancelled = false
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
            try execute("CREATE TABLE IF NOT EXISTS import_history (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
            try execute("PRAGMA foreign_keys = ON")
            try migratePlaylists()
            try recoverDeletions()
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
        // Existing libraries need the same correction as newly imported files.
        // IDs, hashes, filenames and favorites remain stable; source audio is read-only.
        if tracks.contains(where: { $0.metadataRepairVersion != 1 }) {
            try execute("BEGIN TRANSACTION")
            do {
                for index in tracks.indices where tracks[index].metadataRepairVersion != 1 {
                    let old = tracks[index]
                    let url = mediaURL(for: old)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    let legacy = old.filename.lowercased().hasSuffix(".mp3") ? try? LegacyID3Metadata(url: url) : nil
                    let title = legacy?.correctedTitle(old.title) ?? old.title
                    let artist = legacy?.correctedArtist(old.artist) ?? old.artist
                    let album = legacy?.correctedAlbum(old.album) ?? old.album
                    let updated = Track(id: old.id, title: title, artist: artist, album: album, albumArtist: old.albumArtist == old.artist ? artist : old.albumArtist, trackNumber: old.trackNumber, duration: old.duration, filename: old.filename, digest: old.digest, artwork: old.artwork, favorite: old.favorite, metadataRepairVersion: 1)
                    try save(updated)
                    tracks[index] = updated
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
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
    func artworkData(for track: Track) async throws -> Data? {
        guard let artwork = track.artwork else { return nil }
        let url = root.appending(path: "Media/\(artwork)")
        if FileManager.default.fileExists(atPath: url.path) { return try Data(contentsOf: url) }
        let media = mediaURL(for: track)
        let items = try await AVURLAsset(url: media).load(.commonMetadata)
        guard let item = items.first(where: { $0.commonKey == .commonKeyArtwork }),
              let data = try await item.load(.dataValue), data.count <= 12_000_000,
              FileManager.default.fileExists(atPath: media.path) else { return nil }
        try data.write(to: url, options: .atomic)
        return data
    }

    private struct SharedFileStamp: Codable, Equatable {
        let size: Int
        let modified: Date

        init(url: URL) throws {
            // Enumeration URLs cache resource values. Re-read the filesystem on
            // every comparison or a transfer may incorrectly appear unchanged.
            var freshURL = url
            freshURL.removeAllCachedResourceValues()
            let values = try freshURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values.fileSize, let modified = values.contentModificationDate else {
                throw CocoaError(.fileReadUnknown)
            }
            self.size = size
            self.modified = modified
        }
    }

    /// Finder exposes Documents only; the database, ledger and managed copies stay private.
    /// Successful and duplicate imports are remembered, while failed/changed files can retry.
    func importSharedDocuments(from directory: URL, progress: @Sendable (Int, Int) async -> Void) async throws -> ImportReport {
        var hashes = Set(try load().map(\.digest))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledgerURL = root.appending(path: "shared-imports.json")
        var ledger: [String: SharedFileStamp] = [:]
        if FileManager.default.fileExists(atPath: ledgerURL.path) {
            ledger = try JSONDecoder().decode([String: SharedFileStamp].self, from: Data(contentsOf: ledgerURL))
        }
        var candidates: [(URL, SharedFileStamp)] = []
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw failure("无法读取电脑传入的文件")
        }
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true, Self.extensions.contains(url.pathExtension.lowercased()) else { continue }
            let stamp = try SharedFileStamp(url: url)
            if ledger[url.path] != stamp { candidates.append((url, stamp)) }
        }
        guard !candidates.isEmpty else { return ImportReport() }
        await progress(0, candidates.count)
        // Finder can still be writing when the app becomes active. Defer files that
        // change during this observation window, and verify again around the copy.
        do { try await Task.sleep(for: .milliseconds(750)) }
        catch is CancellationError {
            var report = ImportReport()
            report.cancelled = true
            try recordImport(report, source: "Finder 文件共享")
            return report
        }
        var report = ImportReport()
        for (index, candidate) in candidates.sorted(by: { $0.0.path < $1.0.path }).enumerated() {
            if Task.isCancelled { break }
            let (url, stamp) = candidate
            guard (try? SharedFileStamp(url: url)) == stamp else { continue }
            do {
                if let track = try await ingest(url, knownHashes: hashes, expectedSource: stamp) {
                    hashes.insert(track.digest)
                    report.added += 1
                } else { report.duplicates += 1 }
                ledger[url.path] = stamp
                try JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
            } catch is CancellationError { break }
            catch { report.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)"); report.failureItems.append(ImportFailure(source: url, reason: error.localizedDescription)) }
            await progress(index + 1, candidates.count)
        }
        report.cancelled = Task.isCancelled
        try recordImport(report, source: "Finder 文件共享")
        return report
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
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { report.failures.append("无法读取文件夹：\(url.lastPathComponent)"); report.failureItems.append(ImportFailure(source: url, reason: "无法读取文件夹，请重新选择来源授权")); continue }
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
            } catch is CancellationError { break }
            catch { report.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)"); report.failureItems.append(ImportFailure(source: url, reason: error.localizedDescription)) }
            await progress(index + 1, files.count)
        }
        report.cancelled = Task.isCancelled
        try recordImport(report, source: "文件导入")
        return report
    }

    private func ingest(_ source: URL, knownHashes: Set<String>, expectedSource: SharedFileStamp? = nil) async throws -> Track? {
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
        if let expectedSource, try SharedFileStamp(url: source) != expectedSource {
            throw failure("文件仍在传输，请传输完成后重试")
        }
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
        let rawTitle = await text(.commonKeyTitle)
        let rawArtist = await text(.commonKeyArtist)
        let rawAlbum = await text(.commonKeyAlbumName)
        let legacy = source.pathExtension.lowercased() == "mp3" ? try? LegacyID3Metadata(url: staging) : nil
        let title = legacy?.correctedTitle(rawTitle) ?? rawTitle ?? source.deletingPathExtension().lastPathComponent
        let artist = legacy?.correctedArtist(rawArtist) ?? rawArtist ?? "未知艺术家"
        let album = legacy?.correctedAlbum(rawAlbum) ?? rawAlbum ?? "未命名专辑"
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
        let track = Track(id: id, title: title, artist: artist, album: album, albumArtist: albumArtist, trackNumber: trackNumber, duration: duration, filename: name, digest: digest, artwork: artworkName, metadataRepairVersion: 1)
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

extension MusicRepository {
    func toggleFavorite(id: UUID) throws -> Track? {
        try open()
        // Read and update on the repository actor: a stale UI task must not
        // reinsert a track that a concurrent deletion has already removed.
        func read() throws -> Track? {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "SELECT payload FROM tracks WHERE id=?", -1, &statement, nil) == SQLITE_OK else { throw failure("无法读取收藏状态") }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, id.uuidString, -1, transient)
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return nil }
            guard code == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure("无法读取收藏状态") }
            return try JSONDecoder().decode(Track.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
        }
        guard var track = try read() else { return nil }
        track.favorite.toggle()
        try save(track)
        return track
    }

    func importHistory() throws -> [ImportRecord] {
        try open()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM import_history ORDER BY rowid DESC LIMIT 100", -1, &statement, nil) == SQLITE_OK else { throw failure("无法读取导入记录") }
        defer { sqlite3_finalize(statement) }
        var result: [ImportRecord] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { throw failure("导入记录损坏") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            result.append(try JSONDecoder().decode(ImportRecord.self, from: data))
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw failure("导入记录读取未完成") }
        return result
    }

    private func recordImport(_ report: ImportReport, source: String) throws {
        let record = ImportRecord(id: UUID(), date: Date(), source: source, report: report)
        let payload = try JSONEncoder().encode(record)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO import_history(id,payload) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK else { throw failure("无法保存导入记录") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, record.id.uuidString, -1, transient)
        _ = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(payload.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("无法保存导入记录") }
        try execute("DELETE FROM import_history WHERE rowid NOT IN (SELECT rowid FROM import_history ORDER BY rowid DESC LIMIT 100)")
    }

    private func fileBytes(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    private func regularFiles(in directory: URL) -> [URL] {
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        while let url = iterator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if values?.isRegularFile == true { files.append(url) }
        }
        return files
    }
    func storageUsage(documents: URL?) throws -> StorageUsage {
        try open()
        var usage = StorageUsage()
        for url in regularFiles(in: root.appending(path: "Media")) {
            if url.pathExtension == "artwork" { usage.artwork += fileBytes(url) }
            else { usage.audio += fileBytes(url) }
        }
        for url in regularFiles(in: root.appending(path: "Staging")) + regularFiles(in: root.appending(path: "Trash")) { usage.temporary += fileBytes(url) }
        for name in ["library.sqlite", "library.sqlite-wal", "library.sqlite-shm", "shared-imports.json"] { usage.database += fileBytes(root.appending(path: name)) }
        if let documents {
            let files = regularFiles(in: documents)
            usage.incomingFiles = files.count
            usage.incoming = files.reduce(0) { $0 + fileBytes($1) }
        }
        return usage
    }
    func managedBytes(for ids: Set<UUID>) throws -> Int64 {
        let selected = try load().filter { ids.contains($0.id) }
        return selected.reduce(0) { $0 + fileBytes(mediaURL(for: $1)) }
    }
    private func safeMediaURL(_ name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", URL(fileURLWithPath: name).lastPathComponent == name else { throw failure("音频文件路径无效") }
        return root.appending(path: "Media/\(name)")
    }
    private func storedIDs() throws -> Set<UUID> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id FROM tracks", -1, &statement, nil) == SQLITE_OK else { throw failure("无法核对删除记录") }
        defer { sqlite3_finalize(statement) }
        var result = Set<UUID>()
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: value)) { result.insert(id) }
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw failure("无法核对删除记录") }
        return result
    }
    /// Before a committed SQL deletion, restore staged files. After commit, purge them.
    private func recoverDeletions() throws {
        let directory = root.appending(path: "Trash")
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let ids = try storedIDs()
        for job in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard let data = try? Data(contentsOf: job.appending(path: "manifest.json")), let manifest = try? JSONDecoder().decode(DeletionManifest.self, from: data) else { continue }
            for entry in manifest.entries where ids.contains(entry.trackID) {
                for name in entry.files {
                    let destination = try safeMediaURL(name)
                    let staged = job.appending(path: name)
                    if FileManager.default.fileExists(atPath: staged.path) {
                        guard !FileManager.default.fileExists(atPath: destination.path) else { throw failure("删除恢复时发现文件冲突，已保留两份文件") }
                        try FileManager.default.moveItem(at: staged, to: destination)
                    }
                }
            }
            try FileManager.default.removeItem(at: job)
        }
    }
    func deleteTracks(_ ids: Set<UUID>) throws -> CleanupResult {
        let all = try load()
        let selected = all.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return CleanupResult() }
        let kept = all.filter { !ids.contains($0.id) }
        let referenced = Set(kept.flatMap { [$0.filename] + ($0.artwork.map { [$0] } ?? []) })
        let manifest = DeletionManifest(entries: selected.map { track in
            DeletionManifest.Entry(trackID: track.id, files: ([track.filename] + (track.artwork.map { [$0] } ?? [])).filter { !referenced.contains($0) })
        })
        let job = root.appending(path: "Trash/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: job.appending(path: "manifest.json"), options: .atomic)
        var bytes: Int64 = 0
        do {
            for name in Set(manifest.entries.flatMap(\.files)) {
                let original = try safeMediaURL(name)
                if FileManager.default.fileExists(atPath: original.path) {
                    bytes += fileBytes(original)
                    try FileManager.default.moveItem(at: original, to: job.appending(path: name))
                }
            }
            try execute("BEGIN TRANSACTION")
            do {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, "DELETE FROM tracks WHERE id=?", -1, &statement, nil) == SQLITE_OK else { throw failure("无法删除歌曲") }
                defer { sqlite3_finalize(statement) }
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                for track in selected {
                    sqlite3_reset(statement)
                    sqlite3_bind_text(statement, 1, track.id.uuidString, -1, transient)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("歌曲删除未完成") }
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        } catch {
            try recoverDeletions()
            throw error
        }
        var result = CleanupResult()
        result.removed = selected.count
        do { try FileManager.default.removeItem(at: job); result.bytes = bytes }
        catch { result.failures.append("歌曲已从音乐库移除，部分文件等待下次启动清理：\(error.localizedDescription)") }
        return result
    }
    private func contentDigest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty { hasher.update(data: bytes) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func cleanImportedDocuments(_ directory: URL) throws -> CleanupResult {
        // Verify the managed copies themselves as well as the incoming files. A
        // missing/corrupted library copy must never justify deleting an original.
        let tracks = Dictionary(uniqueKeysWithValues: try load().map { ($0.digest, $0) })
        var verified = Set<String>()
        var removedPaths = Set<String>()
        var result = CleanupResult()
        for url in regularFiles(in: directory) {
            guard Self.extensions.contains(url.pathExtension.lowercased()) else { result.skipped += 1; continue }
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var operationError: Error?
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinated in
                do {
                    let before = try SharedFileStamp(url: coordinated)
                    let digest = try contentDigest(coordinated)
                    guard let track = tracks[digest] else { result.skipped += 1; return }
                    if !verified.contains(digest) {
                        guard (try? contentDigest(mediaURL(for: track))) == digest else { result.skipped += 1; return }
                        verified.insert(digest)
                    }
                    guard try SharedFileStamp(url: coordinated) == before else { result.skipped += 1; return }
                    try FileManager.default.removeItem(at: coordinated)
                    removedPaths.insert(url.path)
                    result.removed += 1
                    result.bytes += Int64(before.size)
                } catch { operationError = error }
            }
            if let error = coordinationError ?? operationError as NSError? { result.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        // A future transfer may reuse the original name, size and modification
        // date. Forget cleaned paths so that such an explicit transfer is scanned.
        let ledgerURL = root.appending(path: "shared-imports.json")
        if !removedPaths.isEmpty, FileManager.default.fileExists(atPath: ledgerURL.path) {
            do {
                var ledger = try JSONDecoder().decode([String: SharedFileStamp].self, from: Data(contentsOf: ledgerURL))
                for path in removedPaths { ledger.removeValue(forKey: path) }
                try JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
            } catch { result.failures.append("文件已安全清理，但导入标记更新失败：\(error.localizedDescription)") }
        }
        return result
    }
    func clearArtworkCache() throws -> CleanupResult {
        try open()
        var result = CleanupResult()
        for url in regularFiles(in: root.appending(path: "Media")) where url.pathExtension == "artwork" {
            do {
                let bytes = fileBytes(url)
                try FileManager.default.removeItem(at: url)
                result.removed += 1; result.bytes += bytes
            } catch { result.failures.append(error.localizedDescription) }
        }
        return result
    }
}


extension MusicRepository {
    private func migratePlaylists() throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw failure("无法读取音乐库版本") }
        let code = sqlite3_step(statement)
        let version = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        guard code == SQLITE_ROW, version <= 2 else { throw failure("音乐库版本较新，请更新应用后再打开") }
        if version < 2 {
            try execute("BEGIN TRANSACTION")
            do {
                try execute("CREATE TABLE playlists (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, created REAL NOT NULL, modified REAL NOT NULL)")
                try execute("CREATE TABLE playlist_items (playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, position INTEGER NOT NULL, PRIMARY KEY(playlist_id,track_id), UNIQUE(playlist_id,position))")
                try execute("CREATE INDEX playlist_items_track ON playlist_items(track_id)")
                try execute("PRAGMA user_version = 2")
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }
    func loadPlaylists() throws -> [Playlist] {
        try open()
        var statement: OpaquePointer?
        let sql = "SELECT p.id,p.name,p.created,p.modified,i.track_id FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id=p.id ORDER BY p.created DESC,p.id,i.position"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw failure("无法读取歌单") }
        defer { sqlite3_finalize(statement) }
        var result: [Playlist] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: rawID)),
                  let rawName = sqlite3_column_text(statement, 1) else { throw failure("歌单记录损坏") }
            if result.last?.id != id {
                result.append(Playlist(id: id, name: String(cString: rawName), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)), updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)), trackIDs: []))
            }
            if let rawTrack = sqlite3_column_text(statement, 4) {
                guard let trackID = UUID(uuidString: String(cString: rawTrack)) else { throw failure("歌单歌曲记录损坏") }
                result[result.count - 1].trackIDs.append(trackID)
            }
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw failure("歌单读取未完成") }
        return result
    }
    private func playlist(_ id: UUID) throws -> Playlist {
        guard let playlist = try loadPlaylists().first(where: { $0.id == id }) else { throw failure("歌单已不存在，请返回歌单列表") }
        return playlist
    }
    private func playlistName(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 100 else { throw failure("歌单名称需为 1–100 个字符") }
        guard clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw failure("歌单名称不能包含换行或控制字符") }
        return clean
    }
    private func playlistStatement(_ sql: String, id: UUID, name: String? = nil, timestamp: Double? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw failure("无法更新歌单") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, id.uuidString, -1, transient)
        if let name { sqlite3_bind_text(statement, 2, name, -1, transient) }
        if let timestamp { sqlite3_bind_double(statement, 3, timestamp) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("无法更新歌单：\(String(cString: sqlite3_errmsg(database)))") }
    }
    private func uniqueValidPlaylistTracks(_ ids: [UUID]) throws -> [UUID] {
        let valid = try storedIDs()
        guard ids.allSatisfy({ valid.contains($0) }) else { throw failure("部分歌曲已从音乐库移除，请刷新后重试") }
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
    private func writePlaylistItems(_ id: UUID, ids: [UUID]) throws {
        try playlistStatement("DELETE FROM playlist_items WHERE playlist_id=?1", id: id)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT INTO playlist_items(playlist_id,track_id,position) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw failure("无法保存歌单歌曲") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, trackID) in ids.enumerated() {
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, id.uuidString, -1, transient)
            sqlite3_bind_text(statement, 2, trackID.uuidString, -1, transient)
            sqlite3_bind_int64(statement, 3, Int64(index))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("歌单保存未完成") }
        }
    }
    func createPlaylist(name: String, trackIDs: [UUID] = []) throws -> Playlist {
        try open()
        let name = try playlistName(name), ids = try uniqueValidPlaylistTracks(trackIDs)
        let id = UUID(), now = Date().timeIntervalSince1970
        try execute("BEGIN TRANSACTION")
        do {
            try playlistStatement("INSERT INTO playlists(id,name,created,modified) VALUES(?1,?2,?3,?3)", id: id, name: name, timestamp: now)
            try writePlaylistItems(id, ids: ids)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        return try playlist(id)
    }
    func renamePlaylist(_ id: UUID, name: String) throws {
        _ = try playlist(id)
        try playlistStatement("UPDATE playlists SET name=?2,modified=?3 WHERE id=?1", id: id, name: playlistName(name), timestamp: Date().timeIntervalSince1970)
    }
    func deletePlaylist(_ id: UUID) throws {
        _ = try playlist(id)
        try playlistStatement("DELETE FROM playlists WHERE id=?1", id: id)
    }
    private func replacePlaylistItems(_ id: UUID, ids: [UUID]) throws {
        try execute("BEGIN TRANSACTION")
        do {
            try writePlaylistItems(id, ids: ids)
            try playlistStatement("UPDATE playlists SET modified=?3 WHERE id=?1", id: id, timestamp: Date().timeIntervalSince1970)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func addToPlaylist(_ id: UUID, trackIDs: [UUID]) throws {
        let current = try playlist(id)
        let ids = try uniqueValidPlaylistTracks(current.trackIDs + trackIDs)
        if ids != current.trackIDs { try replacePlaylistItems(id, ids: ids) }
    }
    func removeFromPlaylist(_ id: UUID, trackIDs: Set<UUID>) throws {
        let current = try playlist(id)
        try replacePlaylistItems(id, ids: current.trackIDs.filter { !trackIDs.contains($0) })
    }
    func movePlaylistTracks(_ id: UUID, from offsets: IndexSet, to destination: Int) throws {
        let current = try playlist(id)
        guard let ids = current.trackIDs.moving(from: offsets, to: destination) else { throw failure("歌单内容已变化，请重试排序") }
        try replacePlaylistItems(id, ids: ids)
    }
}
