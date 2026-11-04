import Foundation
import Testing
import SQLite3
@testable import Zuneyra

struct PlaylistTests {
    private func track(_ index: Int) -> Track {
        Track(id: UUID(), title: "Track \(index)", artist: "Test", album: "Tests", albumArtist: "Test", trackNumber: index, duration: 30, filename: "\(UUID().uuidString).wav", digest: "digest-\(index)", artwork: nil, metadataRepairVersion: 1)
    }
    private func fixture() async throws -> (URL, MusicRepository, [Track]) {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = MusicRepository(root: root)
        let tracks = (0..<4).map(track)
        for track in tracks {
            try await repository.save(track)
            try Data("generated placeholder".utf8).write(to: await repository.mediaURL(for: track))
        }
        return (root, repository, tracks)
    }
    private func sql(_ root: URL, _ sql: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(root.appending(path: "library.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "Test.SQLite", code: 1) }
    }

    @Test func versionOneMigrationPreservesTracksAndFavorites() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var original = track(1); original.favorite = true
        let hex = try JSONEncoder().encode(original).map { String(format: "%02x", $0) }.joined()
        try sql(root, "CREATE TABLE tracks(id TEXT PRIMARY KEY,digest TEXT UNIQUE NOT NULL,payload BLOB NOT NULL); CREATE TABLE import_history(id TEXT PRIMARY KEY,payload BLOB NOT NULL); INSERT INTO tracks VALUES('\(original.id.uuidString)','\(original.digest)',X'\(hex)'); PRAGMA user_version=1")
        let repository = MusicRepository(root: root)
        #expect(try await repository.load() == [original])
        #expect(try await repository.loadPlaylists().isEmpty)
        let created = try await repository.createPlaylist(name: "  Road Trip  ", trackIDs: [original.id])
        #expect(created.name == "Road Trip")
        let reopened = MusicRepository(root: root)
        #expect(try await reopened.load() == [original])
        #expect(try await reopened.loadPlaylists() == [created])
    }

    @Test func createRenameDeduplicateAndPersistIndependentMemberships() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try await repository.createPlaylist(name: "夜行 ' 音乐", trackIDs: [tracks[2].id, tracks[0].id, tracks[2].id])
        let b = try await repository.createPlaylist(name: "同一首歌", trackIDs: [tracks[0].id])
        try await repository.addToPlaylist(a.id, trackIDs: [tracks[0].id, tracks[1].id, tracks[1].id])
        try await repository.renamePlaylist(a.id, name: "  音乐 🎵  ")
        let saved = try #require(try await repository.loadPlaylists().first { $0.id == a.id })
        #expect(saved.trackIDs == [tracks[2].id, tracks[0].id, tracks[1].id])
        #expect(saved.name == "音乐 🎵" && saved.createdAt == a.createdAt && saved.updatedAt >= a.updatedAt)
        let reopened = MusicRepository(root: root)
        #expect(try await reopened.loadPlaylists().first { $0.id == a.id } == saved)
        #expect(try await reopened.loadPlaylists().first { $0.id == b.id } == b)
    }

    @Test func movesAndRemovalDoNotDeleteLibraryOrOtherPlaylists() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try await repository.createPlaylist(name: "A", trackIDs: tracks.map(\.id))
        let b = try await repository.createPlaylist(name: "B", trackIDs: tracks.map(\.id))
        try await repository.movePlaylistTracks(a.id, from: IndexSet([0, 2]), to: 4)
        #expect(try await repository.loadPlaylists().first { $0.id == a.id }?.trackIDs == [tracks[1].id, tracks[3].id, tracks[0].id, tracks[2].id])
        try await repository.removeFromPlaylist(a.id, trackIDs: [tracks[3].id])
        try await repository.deletePlaylist(a.id)
        #expect(try await repository.loadPlaylists() == [b])
        #expect(try await repository.load().count == 4)
        #expect(FileManager.default.fileExists(atPath: await repository.mediaURL(for: tracks[3]).path))
    }

    @Test func invalidNamesStaleIDsAndInvalidMovesLeaveRecordsUntouched() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in [" \n ", String(repeating: "乐", count: 101), "bad\0name"] {
            do { _ = try await repository.createPlaylist(name: name); Issue.record("Invalid name accepted") } catch { }
        }
        let playlist = try await repository.createPlaylist(name: "A", trackIDs: tracks.map(\.id))
        do { try await repository.addToPlaylist(playlist.id, trackIDs: [UUID()]); Issue.record("Stale track accepted") } catch { }
        do { try await repository.movePlaylistTracks(playlist.id, from: IndexSet(integer: 10), to: 0); Issue.record("Invalid move accepted") } catch { }
        #expect(try await repository.loadPlaylists() == [playlist])
        try await repository.deletePlaylist(playlist.id)
        do { try await repository.renamePlaylist(playlist.id, name: "resurrect"); Issue.record("Deleted playlist recreated") } catch { }
        do { try await repository.addToPlaylist(playlist.id, trackIDs: [tracks[0].id]); Issue.record("Deleted playlist recreated") } catch { }
        #expect(try await repository.loadPlaylists().isEmpty)
    }

    @Test func trackDeletionCascadesAndCanAppendAfterPositionGaps() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try await repository.createPlaylist(name: "A", trackIDs: tracks.prefix(3).map(\.id))
        let b = try await repository.createPlaylist(name: "B", trackIDs: [tracks[1].id])
        _ = try await repository.deleteTracks([tracks[1].id])
        #expect(try await repository.loadPlaylists().first { $0.id == b.id }?.trackIDs.isEmpty == true)
        try await repository.addToPlaylist(a.id, trackIDs: [tracks[3].id])
        #expect(try await repository.loadPlaylists().first { $0.id == a.id }?.trackIDs == [tracks[0].id, tracks[2].id, tracks[3].id])
    }

    @Test func failedReorderRollsBackItemsAndTimestamp() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let playlist = try await repository.createPlaylist(name: "A", trackIDs: tracks.map(\.id))
        try sql(root, "CREATE TRIGGER block_item BEFORE INSERT ON playlist_items BEGIN SELECT RAISE(ABORT,'test failure'); END")
        do { try await repository.movePlaylistTracks(playlist.id, from: IndexSet(integer: 0), to: 4); Issue.record("Reorder should fail") } catch { }
        #expect(try await repository.loadPlaylists() == [playlist])
        do { _ = try await repository.createPlaylist(name: "Should roll back", trackIDs: [tracks[0].id]); Issue.record("Create should fail") } catch { }
        #expect(try await repository.loadPlaylists() == [playlist])
    }

    @Test func failedTrackDeletionPreservesMembershipAndAudio() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let playlist = try await repository.createPlaylist(name: "A", trackIDs: tracks.map(\.id))
        try sql(root, "CREATE TRIGGER block_track BEFORE DELETE ON tracks BEGIN SELECT RAISE(ABORT,'test failure'); END")
        do { _ = try await repository.deleteTracks([tracks[0].id]); Issue.record("Delete should fail") } catch { }
        #expect(try await repository.loadPlaylists() == [playlist])
        #expect(FileManager.default.fileExists(atPath: await repository.mediaURL(for: tracks[0]).path))
    }

    @Test @MainActor func storeRestoresPlaylistsAndQueueIsIndependentOfEditing() async throws {
        let (root, repository, tracks) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = PlayerStore(repository: repository, preferences: preferences, sharedDocumentsURL: nil)
        await store.load()
        let playlist = try await store.createPlaylist(name: "A", tracks: tracks)
        store.appendToQueue(store.playlistTracks(playlist.id))
        let queued = store.queueState
        try await store.movePlaylistTracks(playlist.id, from: IndexSet(integer: 0), to: 4)
        try await store.removeFromPlaylist(playlist.id, trackIDs: [tracks[1].id])
        #expect(store.queueState == queued)
        let reopened = PlayerStore(repository: repository, preferences: preferences, sharedDocumentsURL: nil)
        await reopened.load()
        #expect(reopened.playlists == store.playlists && reopened.queueState == queued && !reopened.isPlaying)
        #expect(reopened.playlistTracks(playlist.id).map(\.id) == [tracks[2].id, tracks[3].id, tracks[0].id])
        #expect(await reopened.deleteTracks([tracks[3].id]))
        #expect(reopened.playlistTracks(playlist.id).map(\.id) == [tracks[2].id, tracks[0].id])
        try await reopened.deletePlaylist(playlist.id)
        #expect(reopened.playlists.isEmpty && reopened.queue.count == 3)
    }
}
