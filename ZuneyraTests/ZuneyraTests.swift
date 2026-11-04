import Foundation
import Testing
import SQLite3
@testable import Zuneyra

struct ZuneyraTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "Quiet Test.wav")
        // One second of 8 kHz mono 16-bit PCM silence, entirely generated for tests.
        var data = Data()
        func text(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ x: UInt32) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(16036); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16); text("data"); u32(16000); data.append(Data(repeating: 0, count: 16000))
        try data.write(to: source)
        return (root, source)
    }

    @Test func importDeduplicatesAndPersistsManagedCopy() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appending(path: "Library")
        let repository = MusicRepository(root: location)
        let report = try await repository.importFiles([source, source]) { _, _ in }
        #expect(report.added == 1)
        #expect(report.duplicates == 1)
        #expect(report.failures.isEmpty)
        var track = try #require(try await repository.load().first)
        #expect(track.title == "Quiet Test")
        #expect(abs(track.duration - 1) < 0.01)
        track.favorite = true
        try await repository.save(track)
        try FileManager.default.removeItem(at: source)
        let reopened = MusicRepository(root: location)
        let restored = try await reopened.load()
        #expect(restored.count == 1)
        #expect(restored.first?.favorite == true)
        #expect(restored.first?.id == track.id)
        let managed = await reopened.mediaURL(for: track)
        #expect(FileManager.default.fileExists(atPath: managed.path))
    }

    @Test func damagedAudioDoesNotBlockOtherFiles() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = root.appending(path: "broken.mp3")
        try Data("not audio".utf8).write(to: broken)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        let report = try await repository.importFiles([broken, source]) { _, _ in }
        #expect(report.failures.count == 1)
        #expect(report.added == 1)
        #expect(try await repository.load().count == 1)
        let staging = root.appending(path: "Library/Staging")
        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
    }

    @Test func folderImportAndRenamedDuplicate() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: folder.appending(path: "Renamed.wav"))
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importFiles([source]) { _, _ in }
        let report = try await repository.importFiles([folder]) { _, _ in }
        #expect(report.duplicates == 1)
        #expect(try await repository.load().count == 1)
    }
    @Test @MainActor func playbackQueueSeekAndPausedRestoration() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let second = root.appending(path: "Second.wav")
        var audio = try Data(contentsOf: source); audio[audio.count - 1] = 1
        try audio.write(to: second)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importFiles([source, second]) { _, _ in }
        let suite = UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = PlayerStore(repository: repository, preferences: preferences)
        await store.load()
        let first = try #require(store.tracks.first)
        store.play(first, context: store.tracks)
        // Simulator audio startup varies; assert actual readiness with a bounded wait.
        for _ in 0..<100 {
            if store.isPlaying || store.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.isPlaying)
        store.pause()
        #expect(store.errorMessage == nil)
        #expect(store.current?.id == first.id)
        store.seek(to: 0.4)
        #expect(store.position == 0.4)
        let restored = PlayerStore(repository: repository, preferences: preferences)
        await restored.load()
        #expect(restored.current?.id == first.id)
        #expect(abs(restored.position - 0.4) < 0.05)
        #expect(!restored.isPlaying)
        store.next()
        try await Task.sleep(for: .milliseconds(200))
        store.pause()
        #expect(store.current?.id == store.tracks.last?.id)
        #expect(store.errorMessage == nil)
    }

    @Test func finderImportRemembersFilesAndPreservesSources() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        let album = documents.appending(path: "My Album")
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        let received = album.appending(path: "Quiet Test.wav")
        try FileManager.default.copyItem(at: source, to: received)
        try Data("ignore".utf8).write(to: documents.appending(path: "notes.txt"))
        try Data("ignore".utf8).write(to: documents.appending(path: ".partial.wav"))
        let library = root.appending(path: "Library")
        let repository = MusicRepository(root: library)
        let first = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(first.added == 1)
        #expect(first.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: received.path))
        // A new repository simulates reopening the app; its private ledger persists.
        let reopened = MusicRepository(root: library)
        let second = try await reopened.importSharedDocuments(from: documents) { _, _ in }
        #expect(second.added == 0)
        #expect(second.duplicates == 0)
        let renamed = documents.appending(path: "Another name.wav")
        try FileManager.default.copyItem(at: source, to: renamed)
        let duplicate = try await reopened.importSharedDocuments(from: documents) { _, _ in }
        #expect(duplicate.duplicates == 1)
        #expect(try await reopened.load().count == 1)
        try FileManager.default.removeItem(at: documents)
        let track = try #require(try await reopened.load().first)
        let managed = await reopened.mediaURL(for: track)
        #expect(FileManager.default.fileExists(atPath: managed.path))
    }

    @Test func finderImportRetriesRepairedFiles() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let broken = documents.appending(path: "Broken.wav")
        try Data("incomplete".utf8).write(to: broken)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        let first = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(first.failures.count == 1)
        #expect(try await repository.load().isEmpty)
        try Data(contentsOf: source).write(to: broken, options: .atomic)
        let repaired = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(repaired.added == 1)
        #expect(repaired.failures.isEmpty)
        let unchanged = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(unchanged.added == 0 && unchanged.duplicates == 0)
        let another = documents.appending(path: "Cancelled.wav")
        try FileManager.default.copyItem(at: source, to: another)
        let cancelled = Task { try await repository.importSharedDocuments(from: documents) { _, _ in } }
        cancelled.cancel()
        #expect(try await cancelled.value.cancelled)
        #expect(try await repository.importHistory().first?.report.cancelled == true)
        #expect(FileManager.default.fileExists(atPath: another.path))
    }

    @Test @MainActor func finderImportRunsOnLoadAndForegroundScan() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: documents.appending(path: "First.wav"))
        let suite = UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = PlayerStore(repository: MusicRepository(root: root.appending(path: "Library")), preferences: preferences, sharedDocumentsURL: documents)
        await store.load()
        for _ in 0..<100 { if !store.isImporting { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(store.tracks.count == 1)
        store.importReport = nil
        var audio = try Data(contentsOf: source); audio[audio.count - 1] = 1
        try audio.write(to: documents.appending(path: "Second.wav"))
        store.scanSharedDocuments()
        store.scanSharedDocuments() // Repeated scene activation cannot start a second import.
        for _ in 0..<100 { if !store.isImporting { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(store.tracks.count == 2)
        #expect(store.importReport?.added == 1)
        #expect(store.errorMessage == nil)
        store.importReport = nil
        try FileManager.default.copyItem(at: source, to: documents.appending(path: "Duplicate.wav"))
        store.scanSharedDocuments()
        for _ in 0..<100 { if !store.isImporting { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(!store.isImporting)
        #expect(store.tracks.count == 2)
        #expect(store.importReport == nil)
        #expect(store.history.first?.report.duplicates == 1)
        store.importFiles([source])
        for _ in 0..<100 { if !store.isImporting { break }; try await Task.sleep(for: .milliseconds(50)) }
        #expect(store.importReport?.duplicates == 1)
    }

    @Test func finderImportDefersChangingFiles() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let received = documents.appending(path: "Transferring.wav")
        try FileManager.default.copyItem(at: source, to: received)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        // Change the file after discovery, without depending on scheduler timing.
        let pending = try await repository.importSharedDocuments(from: documents) { completed, _ in
            guard completed == 0 else { return }
            do {
                var bytes = try Data(contentsOf: received); bytes[bytes.count - 1] = 1
                try bytes.write(to: received, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: received.path)
            } catch { Issue.record(error) }
        }
        #expect(pending.added == 0)
        #expect(pending.failures.isEmpty)
        #expect(try await repository.load().isEmpty)
        let completed = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(completed.added == 1)
        #expect(completed.failures.isEmpty)
    }

    #if os(iOS)
    @Test func installedAppEnablesFinderFileSharing() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool == true)
    }
    #endif

    private func id3v1(title: Data, artist: Data, album: Data) -> Data {
        var tag = Data("TAG".utf8)
        for field in [title, artist, album] { tag.append(field.prefix(30)); tag.append(Data(repeating: 0, count: max(0, 30 - field.count))) }
        tag.append(Data(repeating: 0, count: 35))
        return tag
    }

    @Test func legacyChineseTagsRepairExistingLibraryWithoutChangingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.load()
        let title = Data([0xc6, 0xdf, 0xc0, 0xef, 0xcf, 0xe3]) // 七里香 in GBK
        let artist = Data([0xd6, 0xdc, 0xbd, 0xdc, 0xc2, 0xd7]) // 周杰伦 in GBK
        let album = Data([0xb7, 0xb6, 0xcc, 0xd8, 0xce, 0xf7]) // 范特西 in GBK
        let audio = Data("read-only audio placeholder".utf8) + id3v1(title: title, artist: artist, album: album)
        let original = Track(id: UUID(), title: String(data: title, encoding: .isoLatin1)!, artist: String(data: artist, encoding: .isoLatin1)!, album: String(data: album, encoding: .isoLatin1)!, albumArtist: String(data: artist, encoding: .isoLatin1)!, trackNumber: 7, duration: 180, filename: "legacy.mp3", digest: "unchanged-hash", artwork: nil, favorite: true)
        let url = await repository.mediaURL(for: original)
        try audio.write(to: url)
        try await repository.save(original)
        let repaired = try #require(try await repository.load().first)
        #expect(repaired.title == "七里香")
        #expect(repaired.artist == "周杰伦")
        #expect(repaired.album == "范特西")
        #expect(repaired.albumArtist == "周杰伦")
        #expect(repaired.id == original.id && repaired.digest == original.digest && repaired.favorite)
        #expect(try Data(contentsOf: url) == audio)
        #expect(try await repository.load().first == repaired)
        let metadata = try #require(try LegacyID3Metadata(url: url))
        #expect(metadata.correctedTitle("七里香（现场）") == "七里香（现场）")
    }

    @Test func accentedWesternMetadataIsNotReinterpretedAsChinese() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let name = "Björk"
        let title = "Crème Brûlée"
        try id3v1(title: title.data(using: .isoLatin1)!, artist: name.data(using: .isoLatin1)!, album: Data("Debut".utf8)).write(to: url)
        let metadata = try #require(try LegacyID3Metadata(url: url))
        #expect(metadata.correctedTitle(title) == title)
        #expect(metadata.correctedArtist(name) == name)
    }

    @Test func historyPersistsFailuresAndSupportsRetry() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let broken = root.appending(path: "Needs retry.wav")
        try Data("incomplete transfer".utf8).write(to: broken)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importFiles([broken]) { _, _ in }
        let reopened = MusicRepository(root: root.appending(path: "Library"))
        let record = try #require(try await reopened.importHistory().first)
        #expect(record.report.failureItems.count == 1)
        #expect(record.report.failureItems.first?.filename == broken.lastPathComponent)
        try Data(contentsOf: source).write(to: broken, options: .atomic)
        let result = try await reopened.importFiles(record.report.failureItems.map { $0.resolvedURL() }) { _, _ in }
        #expect(result.added == 1 && result.failures.isEmpty)
        #expect(try await reopened.importHistory().count == 2)
        #expect(try await reopened.load().count == 1)
    }

    @Test @MainActor func deletingCurrentTrackStopsPlaybackAndPreservesIncomingOriginal() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let received = documents.appending(path: "Original.wav")
        try FileManager.default.copyItem(at: source, to: received)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importSharedDocuments(from: documents) { _, _ in }
        let suite = UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = PlayerStore(repository: repository, preferences: preferences, sharedDocumentsURL: nil)
        await store.load()
        let track = try #require(store.tracks.first)
        store.play(track, context: store.tracks)
        for _ in 0..<100 { if store.isPlaying { break }; try await Task.sleep(for: .milliseconds(20)) }
        store.toggleFavorite(track) // A queued favorite update cannot resurrect a deleted row.
        #expect(await store.deleteTracks([track.id]))
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await repository.load().isEmpty)
        #expect(try await repository.toggleFavorite(id: track.id) == nil)
        #expect(store.current == nil && !store.isPlaying && store.queue.isEmpty)
        #expect(store.tracks.isEmpty)
        #expect(preferences.data(forKey: "playbackSession") == nil)
        #expect(FileManager.default.fileExists(atPath: received.path))
        let managed = await repository.mediaURL(for: track)
        #expect(!FileManager.default.fileExists(atPath: managed.path))
        let scan = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(scan.added == 0) // An unchanged incoming file does not undo a user's deletion.
    }

    @Test func cleanupPreservesChangedUnimportedAndCorruptedCopySources() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let imported = documents.appending(path: "Imported.wav")
        try FileManager.default.copyItem(at: source, to: imported)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importSharedDocuments(from: documents) { _, _ in }
        let changed = documents.appending(path: "Changed.wav")
        var bytes = try Data(contentsOf: source); bytes[bytes.count - 1] = 1
        try bytes.write(to: changed)
        let broken = documents.appending(path: "broken.wav")
        try Data("incomplete".utf8).write(to: broken)
        let note = documents.appending(path: "notes.txt")
        try Data("keep me".utf8).write(to: note)
        let usage = try await repository.storageUsage(documents: documents)
        #expect(usage.incomingFiles == 4 && usage.audio > 0 && usage.incoming > usage.audio)
        let first = try await repository.cleanImportedDocuments(documents)
        #expect(first.removed == 1 && first.skipped == 3)
        #expect(FileManager.default.fileExists(atPath: changed.path))
        #expect(FileManager.default.fileExists(atPath: broken.path))
        #expect(FileManager.default.fileExists(atPath: note.path))
        try FileManager.default.copyItem(at: source, to: imported)
        let track = try #require(try await repository.load().first)
        let managed = await repository.mediaURL(for: track)
        try Data("corrupted managed copy".utf8).write(to: managed)
        let second = try await repository.cleanImportedDocuments(documents)
        #expect(second.removed == 0)
        #expect(FileManager.default.fileExists(atPath: imported.path))
        // Cleanup must also forget the incoming path's old scan marker. After
        // deleting the library copy, a fresh transfer can have identical metadata.
        try Data(contentsOf: source).write(to: managed)
        _ = try await repository.cleanImportedDocuments(documents)
        _ = try await repository.deleteTracks([track.id])
        try FileManager.default.copyItem(at: source, to: imported)
        let freshTransfer = try await repository.importSharedDocuments(from: documents) { _, _ in }
        #expect(freshTransfer.added == 2) // The retransferred original and Changed.wav.
        #expect(try await repository.load().contains(where: { $0.title == "Imported" }))
    }

    @Test func failedDatabaseDeletionRestoresStagedAudio() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appending(path: "Library")
        let repository = MusicRepository(root: library)
        _ = try await repository.importFiles([source]) { _, _ in }
        let track = try #require(try await repository.load().first)
        var db: OpaquePointer?
        #expect(sqlite3_open(library.appending(path: "library.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER block_deletion BEFORE DELETE ON tracks BEGIN SELECT RAISE(ABORT, 'test failure'); END", nil, nil, nil) == SQLITE_OK)
        do { _ = try await repository.deleteTracks([track.id]); Issue.record("Deletion should fail") } catch { }
        #expect(try await repository.load().count == 1)
        let managed = await repository.mediaURL(for: track)
        #expect(try Data(contentsOf: managed) == Data(contentsOf: source))
    }

    @Test func interruptedDeletionRestoresBeforeCommitAndPurgesAfterCommit() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appending(path: "Library")
        let repository = MusicRepository(root: library)
        _ = try await repository.importFiles([source]) { _, _ in }
        let track = try #require(try await repository.load().first)
        let managed = await repository.mediaURL(for: track)
        let job = library.appending(path: "Trash/test-job")
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        let manifest = DeletionManifest(entries: [.init(trackID: track.id, files: [track.filename])])
        try JSONEncoder().encode(manifest).write(to: job.appending(path: "manifest.json"))
        try FileManager.default.moveItem(at: managed, to: job.appending(path: track.filename))
        let reopened = MusicRepository(root: library)
        #expect(try await reopened.load().count == 1)
        #expect(FileManager.default.fileExists(atPath: managed.path))
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: job.appending(path: "manifest.json"))
        try FileManager.default.moveItem(at: managed, to: job.appending(path: track.filename))
        var db: OpaquePointer?
        #expect(sqlite3_open(library.appending(path: "library.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "DELETE FROM tracks", nil, nil, nil) == SQLITE_OK)
        let afterCommit = MusicRepository(root: library)
        #expect(try await afterCommit.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: job.path))
    }

    @Test func artworkCacheRebuildsFromEmbeddedCover() async throws {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        let source = try #require(bundle.url(forResource: "silence-with-cover", withExtension: "mp3"))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        let report = try await repository.importFiles([source]) { _, _ in }
        #expect(report.added == 1)
        let track = try #require(try await repository.load().first)
        let original = try #require(try await repository.artworkData(for: track))
        #expect(try await repository.storageUsage(documents: nil).artwork > 0)
        let cleaned = try await repository.clearArtworkCache()
        #expect(cleaned.removed == 1)
        #expect(try await repository.storageUsage(documents: nil).artwork == 0)
        let rebuilt = try await repository.artworkData(for: track)
        #expect(rebuilt == original)
        #expect(try await repository.storageUsage(documents: nil).audio > 0)
    }

}

private final class FixtureBundleMarker: NSObject {}
