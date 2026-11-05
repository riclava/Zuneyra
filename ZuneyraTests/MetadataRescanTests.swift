import Foundation
import Testing
@testable import Zuneyra

struct MetadataRescanTests {
    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: MetadataBundleMarker.self)
        return try #require(bundle.url(forResource: name, withExtension: nil, subdirectory: "Formats") ?? bundle.url(forResource: name, withExtension: nil))
    }

    private func legacy(_ track: Track) throws -> Track {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        for key in ["discNumber", "lyrics", "replayGain", "artwork"] { json.removeValue(forKey: key) }
        json["title"] = "Legacy title"; json["artist"] = "Legacy artist"
        json["album"] = "Legacy album"; json["albumArtist"] = "Legacy album artist"
        json["trackNumber"] = 0; json["favorite"] = true
        return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func legacyLibraryRescanRestoresTagsWithoutChangingIdentityOrPlaylists() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.importFiles([fixture("test-lyrics.flac")]) { _, _ in }
        let old = try legacy(#require(try await repository.load().first))
        try await repository.save(old)
        let playlist = try await repository.createPlaylist(name: "Keep order", trackIDs: [old.id])
        let media = await repository.mediaURL(for: old)
        let bytes = try Data(contentsOf: media)
        let report = try await repository.rescanMetadata { _, _ in }
        #expect(report.scanned == 1 && report.updated == 1 && report.failures.isEmpty)
        let updated = try #require(try await repository.load().first)
        #expect(updated.id == old.id && updated.filename == old.filename && updated.digest == old.digest)
        #expect(updated.title == "Format Test" && updated.artist == "Generated" && updated.album == "Codec Matrix")
        #expect(updated.discNumber == 2 && updated.trackNumber == 2 && updated.replayGain?.trackGain == -6)
        #expect(updated.favorite && updated.sourceBookmark == old.sourceBookmark)
        #expect(updated.lyrics == "[00:00.50]Generated lyric")
        #expect(try Data(contentsOf: media) == bytes)
        let reopened = MusicRepository(root: root)
        #expect(try await reopened.load().first == updated)
        #expect(try await reopened.loadPlaylists() == [playlist])
        #expect(try await repository.rescanMetadata { _, _ in }.updated == 0)
    }

    @Test func rescanFillsMissingLyricsButPreservesExistingLyricsAndAbsentFields() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.importFiles([fixture("test.flac")]) { _, _ in }
        var track = try #require(try await repository.load().first)
        let media = await repository.mediaURL(for: track)
        let sidecar = media.deletingPathExtension().appendingPathExtension("lrc")
        try "[00:00.50]Sidecar lyrics".write(to: sidecar, atomically: true, encoding: .utf8)
        _ = try await repository.rescanMetadata { _, _ in }
        #expect(try await repository.load().first?.lyrics == "[00:00.50]Sidecar lyrics")
        track.lyrics = "My edited lyrics"; track.replayGain?.albumGain = -9
        try await repository.save(track)
        _ = try await repository.rescanMetadata { _, _ in }
        let updated = try #require(try await repository.load().first)
        #expect(updated.lyrics == "My edited lyrics" && updated.replayGain?.albumGain == -9)
    }

    @Test func rescanRestoresArtworkAndPreservesMetadataWhenTagsAreAbsent() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        let source = try #require(Bundle(for: MetadataBundleMarker.self).url(forResource: "silence-with-cover", withExtension: "mp3"))
        _ = try await repository.importFiles([source]) { _, _ in }
        let imported = try #require(try await repository.load().first)
        let artwork = try #require(try await repository.artworkData(for: imported))
        var old = try legacy(imported)
        old.discNumber = 7; old.lyrics = "Manual lyrics"; old.replayGain = ReplayGain(trackGain: -3)
        try await repository.save(old)
        _ = try await repository.clearArtworkCache()
        #expect(try await repository.rescanMetadata { _, _ in }.updated == 1)
        let updated = try #require(try await repository.load().first)
        #expect(updated.title == old.title && updated.album == old.album && updated.artist == old.artist)
        #expect(updated.discNumber == 7 && updated.lyrics == "Manual lyrics" && updated.replayGain?.trackGain == -3)
        #expect(updated.artwork != nil)
        #expect(try await repository.artworkData(for: updated) == artwork)
        #expect(try await repository.rescanMetadata { _, _ in }.updated == 0)
    }

    @Test func missingAndChangedAudioAreReportedWithoutBlockingOtherTracks() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.importFiles([fixture("test.flac"), fixture("test.mp3"), fixture("test.wav")]) { _, _ in }
        let tracks = try await repository.load()
        for track in tracks {
            try await repository.save(legacy(track))
            let media = await repository.mediaURL(for: track)
            if track.filename.hasSuffix(".mp3") { try Data("changed".utf8).write(to: media) }
            if track.filename.hasSuffix(".wav") { try FileManager.default.removeItem(at: media) }
        }
        let report = try await repository.rescanMetadata { _, _ in }
        #expect(report.scanned == 3 && report.updated == 1 && report.failures.count == 2)
        let updated = try await repository.load()
        #expect(updated.count == 3)
        #expect(updated.first { $0.filename.hasSuffix(".flac") }?.title == "Format Test")
        #expect(updated.filter { !$0.filename.hasSuffix(".flac") }.allSatisfy { $0.title == "Legacy title" })
    }

    @Test func canceledRescanKeepsCompletedUpdates() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.importFiles([fixture("test.flac"), fixture("test.mp3")]) { _, _ in }
        for track in try await repository.load() { try await repository.save(legacy(track)) }
        let job = Task {
            try await repository.rescanMetadata { completed, _ in
                if completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let report = try await job.value
        #expect(report.cancelled && report.scanned == 1 && report.updated == 1)
        #expect(try await repository.load().filter { $0.title == "Format Test" }.count == 1)
        #expect(try await repository.rescanMetadata { _, _ in }.updated == 1)
    }

    @Test func editsAndDeletionAfterSnapshotAreNotOverwritten() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.importFiles([fixture("test.flac"), fixture("test.mp3")]) { _, _ in }
        let tracks = try await repository.load()
        let kept = try #require(tracks.first), removed = try #require(tracks.last)
        _ = try await repository.rescanMetadata { completed, _ in
            if completed == 0 {
                _ = try? await repository.deleteTracks([removed.id])
                var edited = kept; edited.favorite = true; edited.lyrics = "User edit"
                try? await repository.save(edited)
            }
        }
        let result = try await repository.load()
        #expect(result.count == 1 && result.first?.id == kept.id)
        #expect(result.first?.favorite == true && result.first?.lyrics == "User edit")
    }

    @Test @MainActor func storeRescanPreservesPausedQueueAndRefreshesCurrentMetadata() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.importFiles([fixture("test.flac")]) { _, _ in }
        let track = try legacy(#require(try await repository.load().first))
        try await repository.save(track)
        let store = PlayerStore(repository: repository, preferences: preferences, sharedDocumentsURL: nil)
        await store.load()
        store.play(track, context: [track])
        defer { store.pause() }
        for _ in 0..<200 {
            if store.isPlaying { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.isPlaying)
        store.pause(); store.seek(to: 0.75); store.appendToQueue([track])
        let queue = store.queueState
        store.rescanMetadata()
        for _ in 0..<200 {
            if !store.isRescanningMetadata { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!store.isRescanningMetadata && store.errorMessage == nil && store.managementMessage != nil)
        #expect(store.queueState == queue && !store.isPlaying && abs(store.position - 0.75) < 0.1)
        #expect(store.current?.id == track.id && store.current?.title == "Format Test")
        #expect(store.current?.replayGain?.trackGain == -6)
    }

    #if os(macOS)
    @Test func referencedAudioRescanPreservesBookmarkAndSource() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "source.flac")
        try FileManager.default.copyItem(at: fixture("test.flac"), to: source)
        let bytes = try Data(contentsOf: source)
        let repository = MusicRepository(root: root.appending(path: "Library"))
        _ = try await repository.importFiles([source], referencing: true) { _, _ in }
        let track = try legacy(#require(try await repository.load().first))
        try await repository.save(track)
        #expect(try await repository.rescanMetadata { _, _ in }.updated == 1)
        let updated = try #require(try await repository.load().first)
        #expect(updated.sourceBookmark == track.sourceBookmark && updated.sourceBookmark != nil)
        #expect(updated.discNumber == 2 && updated.replayGain?.trackGain == -6)
        #expect(try Data(contentsOf: source) == bytes)
    }
    #endif
}

private final class MetadataBundleMarker: NSObject {}
