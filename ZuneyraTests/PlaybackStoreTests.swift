import Foundation
import Testing
import MediaPlayer
@testable import Zuneyra

@Suite(.serialized)
@MainActor struct PlaybackStoreTests {
    @MainActor private struct Fixture {
        let root: URL
        let suite: String
        let preferences: UserDefaults
        let repository: MusicRepository
        let store: PlayerStore
        let tracks: [Track]
        init() async throws {
            root = .temporaryDirectory.appending(path: UUID().uuidString)
            suite = UUID().uuidString
            preferences = UserDefaults(suiteName: suite)!
            repository = MusicRepository(root: root)
            _ = try await repository.load()
            // Generated 30-second PCM avoids incidental natural endings during edits.
            var bytes = Data()
            func text(_ s: String) { bytes.append(contentsOf: s.utf8) }
            func u32(_ x: UInt32) { var x = x.littleEndian; withUnsafeBytes(of: &x) { bytes.append(contentsOf: $0) } }
            func u16(_ x: UInt16) { var x = x.littleEndian; withUnsafeBytes(of: &x) { bytes.append(contentsOf: $0) } }
            text("RIFF"); u32(480036); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16); text("data"); u32(480000); bytes.append(Data(repeating: 0, count: 480000))
            var saved: [Track] = []
            for index in 0..<3 {
                let track = Track(id: UUID(), title: "Queue \(index)", artist: "Generated", album: "Tests", albumArtist: "Generated", trackNumber: index, duration: 30, filename: "queue-\(index).wav", digest: "queue-\(index)", artwork: nil, metadataRepairVersion: 1)
                try bytes.write(to: await repository.mediaURL(for: track))
                try await repository.save(track)
                saved.append(track)
            }
            tracks = saved
            store = PlayerStore(repository: repository, preferences: preferences, sharedDocumentsURL: nil)
            await store.load()
        }
        func reopened() -> PlayerStore { PlayerStore(repository: repository, preferences: preferences, sharedDocumentsURL: nil) }
        func clean() { store.pause(); preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition(), "Playback transition did not finish within five seconds")
    }

    @Test func duplicateEntryPlaybackAndQueueEditsKeepCurrentPosition() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        store.play(f.tracks[0], context: f.tracks)
        try await wait { store.isPlaying }
        store.pause(); store.seek(to: 8)
        let currentID = store.queueState.currentID
        store.insertNext([f.tracks[0], f.tracks[1]])
        let duplicate = store.queueState.upcoming[0]
        store.moveUpcoming(from: IndexSet(integer: 1), to: 0)
        store.appendToQueue([f.tracks[2]])
        #expect(store.current?.id == f.tracks[0].id && store.queueState.currentID == currentID)
        #expect(abs(store.position - 8) < 0.1 && !store.isPlaying)
        store.playQueueEntry(duplicate)
        try await wait { store.isPlaying }
        #expect(store.queueState.currentID == duplicate && store.current?.id == f.tracks[0].id)
        store.removeQueueEntry(duplicate)
        #expect(store.current == nil && !store.isPlaying)
        #expect(store.tracks.count == 3)
        #expect(FileManager.default.fileExists(atPath: await f.repository.mediaURL(for: f.tracks[0]).path))
        let reopened = f.reopened()
        await reopened.load()
        #expect(reopened.current == nil && !reopened.isPlaying)
        #expect(reopened.queueState == store.queueState)
    }

    @Test func snapshotRestoresModesExactOrderAndPositionPaused() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        store.play(f.tracks[0], context: f.tracks)
        try await wait { store.isPlaying }
        store.pause(); store.seek(to: 7.25)
        store.appendToQueue([f.tracks[0]])
        store.toggleShuffle(); store.cycleRepeatMode(); store.cycleRepeatMode()
        let saved = store.queueState
        let reopened = f.reopened()
        await reopened.load()
        #expect(reopened.queueState == saved)
        #expect(reopened.queueState.shuffle && reopened.queueState.repeatMode == .one)
        #expect(abs(reopened.position - 7.25) < 0.1 && !reopened.isPlaying)
        store.clearUpcoming()
        #expect(store.current != nil && store.queueState.upcoming.isEmpty)
        let cleared = f.reopened()
        await cleared.load()
        #expect(cleared.queueState == store.queueState && !cleared.isPlaying)
    }

    @Test func queueWithoutCurrentAndEmptyModesSurviveRestart() async throws {
        let f = try await Fixture(); defer { f.clean() }
        f.store.appendToQueue(f.tracks)
        f.store.toggleShuffle(); f.store.cycleRepeatMode()
        let reopened = f.reopened()
        await reopened.load()
        #expect(reopened.current == nil && !reopened.isPlaying)
        #expect(reopened.queueState == f.store.queueState)
        reopened.resume()
        try await wait { reopened.isPlaying }
        reopened.pause()
        #expect(reopened.current != nil)
        for entry in reopened.queueState.canonical { reopened.removeQueueEntry(entry.id) }
        let empty = f.reopened()
        await empty.load()
        #expect(empty.queue.isEmpty && empty.queueState.shuffle && empty.queueState.repeatMode == .all)
        #expect(!empty.isPlaying)
    }

    @Test func legacySessionsMigrateAndDeletedLibraryRowsArePruned() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let ids = f.tracks.map { $0.id.uuidString }
        let legacy: [String: Any] = ["current": ids[1], "queue": ids, "position": 4.5]
        f.preferences.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "playbackSession")
        let restored = f.reopened()
        await restored.load()
        #expect(restored.current?.id == f.tracks[1].id && !restored.isPlaying)
        #expect(abs(restored.position - 4.5) < 0.1)
        let data = try #require(f.preferences.data(forKey: "playbackSession"))
        #expect(try JSONDecoder().decode(PlaybackSnapshot.self, from: data).version == 2)
        _ = try await f.repository.deleteTracks([f.tracks[1].id])
        let pruned = f.reopened()
        await pruned.load()
        #expect(pruned.current == nil && pruned.queue.count == 2 && !pruned.isPlaying)
    }

    @Test func missingFilesSkipOnAdvanceAndStopBoundedlyUnderRepeat() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        store.play(f.tracks[0], context: f.tracks)
        try await wait { store.isPlaying }
        store.pause()
        try FileManager.default.removeItem(at: await f.repository.mediaURL(for: f.tracks[1]))
        store.next()
        try await wait { store.current?.id == f.tracks[2].id && store.isPlaying }
        store.pause()
        #expect(store.queueNotice != nil)
        store.play(f.tracks[1], context: f.tracks)
        try await wait { store.errorMessage != nil }
        #expect(store.current?.id == f.tracks[1].id && !store.isPlaying)
        store.errorMessage = nil
        store.play(f.tracks[2], context: f.tracks)
        try await wait { store.isPlaying }
        store.pause()
        store.cycleRepeatMode() // repeat all
        for track in [f.tracks[0], f.tracks[2]] { try FileManager.default.removeItem(at: await f.repository.mediaURL(for: track)) }
        store.next()
        try await wait { store.errorMessage != nil }
        #expect(!store.isPlaying)
        store.errorMessage = nil
        store.cycleRepeatMode() // repeat one, missing current cannot loop forever
        store.next(automatically: true)
        try await wait { store.errorMessage != nil }
        #expect(!store.isPlaying)
        let restored = f.reopened()
        await restored.load()
        #expect(restored.current != nil && !restored.isPlaying && restored.errorMessage != nil)
        #expect(restored.queue.count == 3)
    }

    @Test func realAudioCompletionRepeatsOneAndWrapsAll() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        store.play(f.tracks[0], context: f.tracks)
        try await wait { store.isPlaying }
        store.cycleRepeatMode(); store.cycleRepeatMode()
        let repeatedID = store.queueState.currentID
        store.seek(to: 29.6)
        try await wait { store.position < 2 && store.isPlaying }
        #expect(store.queueState.currentID == repeatedID)
        store.next()
        try await wait { store.current?.id == f.tracks[1].id && store.isPlaying }
        store.play(f.tracks[2], context: f.tracks)
        store.cycleRepeatMode(); store.cycleRepeatMode() // one -> off -> all
        try await wait { store.isPlaying }
        store.seek(to: 29.6)
        try await wait { store.current?.id == f.tracks[0].id && store.isPlaying }
        #expect(store.queueState.past.isEmpty && store.errorMessage == nil)
    }

    @Test func playlistPlaybackCopiesSavedOrderAndSurvivesPlaylistDeletion() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        let playlist = try await store.createPlaylist(name: "Playback", tracks: f.tracks)
        try await store.movePlaylistTracks(playlist.id, from: IndexSet(integer: 0), to: 3)
        store.playPlaylist(playlist.id)
        try await wait { store.isPlaying }
        store.pause()
        let queued = store.queueState
        #expect(store.current?.id == f.tracks[1].id)
        #expect(store.queue.map(\.id) == [f.tracks[1].id, f.tracks[2].id, f.tracks[0].id])
        try await store.removeFromPlaylist(playlist.id, trackIDs: [f.tracks[1].id])
        try await store.deletePlaylist(playlist.id)
        #expect(store.queueState == queued && store.current?.id == f.tracks[1].id)
    }

    @Test func shuffledPlaylistUsesOnlyItsMembersAndNormalPlayDisablesShuffle() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        let playlist = try await store.createPlaylist(name: "Shuffle", tracks: Array(f.tracks.prefix(2)))
        store.cycleRepeatMode()
        store.playPlaylist(playlist.id, shuffled: true)
        try await wait { store.isPlaying }
        store.pause()
        #expect(Set(store.queue.map(\.id)) == Set(f.tracks.prefix(2).map(\.id)))
        #expect(store.queueState.shuffle && store.queueState.repeatMode == .all)
        store.playPlaylist(playlist.id, startingAt: f.tracks[1].id)
        try await wait { store.isPlaying }
        #expect(!store.queueState.shuffle && store.queueState.repeatMode == .all)
        #expect(store.current?.id == f.tracks[1].id && store.queue.map(\.id) == f.tracks.prefix(2).map(\.id))
    }

    @Test func carPlayActionsSharePhoneQueueAndPublishPlaybackModes() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        let playlist = try await store.createPlaylist(name: "CarPlay", tracks: [f.tracks[1], f.tracks[0]])
        #expect(store.performCarPlayAction(.playAll(.playlist(playlist.id), shuffled: false)))
        try await wait { store.isPlaying }
        #expect(store.current?.id == f.tracks[1].id && store.queue.map(\.id) == [f.tracks[1].id, f.tracks[0].id])
        let second = try #require(store.queueState.upcoming.first)
        #expect(store.performCarPlayAction(.queueEntry(second)))
        try await wait { store.current?.id == f.tracks[0].id && store.isPlaying }
        store.setShuffle(true); store.setRepeatMode(.one)
        let remote = MPRemoteCommandCenter.shared()
        #expect(remote.changeShuffleModeCommand.currentShuffleType == .items)
        #expect(remote.changeRepeatModeCommand.currentRepeatType == .one)
        let info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        #expect(info[MPMediaItemPropertyTitle] as? String == f.tracks[0].title)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        store.pause()
        try await store.deletePlaylist(playlist.id)
        #expect(!store.performCarPlayAction(.playAll(.playlist(playlist.id), shuffled: false)))
        #expect(store.errorMessage != nil && !store.isPlaying)
        #expect(!store.performCarPlayAction(.queueEntry(UUID())))
    }

    @Test func carPlayMissingFileSelectionStopsAndPreservesRecoverableQueue() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        let playlist = try await store.createPlaylist(name: "Missing", tracks: f.tracks)
        try FileManager.default.removeItem(at: await f.repository.mediaURL(for: f.tracks[1]))
        #expect(store.performCarPlayAction(.play(f.tracks[1].id, .playlist(playlist.id))))
        try await wait { store.errorMessage != nil }
        #expect(!store.isPlaying && store.current?.id == f.tracks[1].id && store.queue.count == 3)
        #expect(store.performCarPlayAction(.play(f.tracks[2].id, .playlist(playlist.id))))
        try await wait { store.isPlaying }
        #expect(store.current?.id == f.tracks[2].id)
    }

    @Test func restorationAtEndOfRepeatingQueueStaysPaused() async throws {
        let f = try await Fixture(); defer { f.clean() }
        var queue = PlaybackQueue()
        queue.replace(trackIDs: f.tracks.map(\.id), selectedIndex: 2)
        queue.setRepeat(.all)
        f.preferences.set(try JSONEncoder().encode(PlaybackSnapshot(queue: queue, position: 30)), forKey: "playbackSession")
        let restored = f.reopened()
        await restored.load()
        try await Task.sleep(for: .milliseconds(200))
        #expect(restored.queueState == queue && restored.current?.id == f.tracks[2].id)
        #expect(restored.position == 30 && !restored.isPlaying)
    }

    @Test func latestPlayAndImmediatePauseWinOverPendingPreparation() async throws {
        let f = try await Fixture(); defer { f.clean() }
        let store = f.store
        store.play(f.tracks[0], context: f.tracks)
        store.play(f.tracks[2], context: f.tracks)
        store.pause()
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.current?.id == f.tracks[2].id && !store.isPlaying)
        store.play(f.tracks[0], context: f.tracks)
        store.next(); store.next(); store.pause()
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.current?.id == f.tracks[2].id && store.queueState.past.count == 2 && !store.isPlaying)
        store.resume()
        try await wait { store.isPlaying }
        store.next(automatically: true) // last entry, repeat off -> stop
        try await wait { !store.isPlaying }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.current?.id == f.tracks[2].id && store.position == 30)
        #expect(store.errorMessage == nil)
    }
}
