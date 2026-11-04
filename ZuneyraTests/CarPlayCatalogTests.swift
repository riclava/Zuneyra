import Foundation
import Testing
@testable import Zuneyra

struct CarPlayCatalogTests {
    private func tracks() -> [Track] {
        (0..<5).map { Track(id: UUID(), title: "Song \($0)", artist: $0 < 3 ? "Artist A" : "Artist B", album: "Album", albumArtist: $0 < 3 ? "Artist A" : "Artist B", trackNumber: $0, duration: 30, filename: "\($0).wav", digest: "\($0)", artwork: nil, favorite: $0 % 2 == 0, metadataRepairVersion: 1) }
    }
    @Test func catalogSeparatesAlbumArtistsAndResolvesPlaylistOrder() {
        let songs = tracks(), id = UUID()
        let playlist = Playlist(id: id, name: "Road", createdAt: Date(), updatedAt: Date(), trackIDs: [songs[4].id, songs[0].id, UUID()])
        let catalog = CarPlayCatalog(tracks: songs.reversed(), playlists: [playlist], queue: PlaybackQueue())
        #expect(catalog.rows(for: .albums).count == 2)
        #expect(catalog.rows(for: .artists).count == 2)
        #expect(catalog.tracks(for: .playlist(id)).map(\.id) == [songs[4].id, songs[0].id])
        #expect(catalog.tracks(for: .favorites).map(\.id) == [songs[0].id, songs[2].id, songs[4].id])
        #expect(catalog.tracks(for: .album(songs[0].albumKey)).map(\.id) == songs.prefix(3).map(\.id))
        #expect(catalog.rows(for: .playlist(id)).first?.action == .playAll(.playlist(id), shuffled: false))
    }
    @Test func paginationHasNoLostRowsAndClampsAfterDeletion() {
        let songs = tracks(), catalog = CarPlayCatalog(tracks: songs, playlists: [], queue: PlaybackQueue())
        let rows = catalog.rows(for: .artist("Artist A"))
        let a = CarPlayPage.make(rows: rows, index: 0, size: 2)
        let b = CarPlayPage.make(rows: rows, index: 1, size: 2)
        let c = CarPlayPage.make(rows: rows, index: 2, size: 2)
        #expect(a.rows + b.rows + c.rows == rows)
        #expect(a.previous == nil && a.next == 1 && c.previous == 1 && c.next == nil)
        #expect(CarPlayPage.make(rows: [], index: 99, size: 0).index == 0)
        #expect(CarPlayPage.make(rows: Array(rows.prefix(1)), index: 4, size: 2).rows.count == 1)
    }
    @Test func queueUsesOccurrenceIDsAndExcludesPast() {
        let songs = tracks()
        var queue = PlaybackQueue()
        queue.replace(trackIDs: [songs[0].id, songs[0].id, songs[1].id], selectedIndex: 1)
        let catalog = CarPlayCatalog(tracks: songs, playlists: [], queue: queue)
        let rows = catalog.rows(for: .queue)
        #expect(rows.count == 2)
        #expect(rows[0].action == .queueEntry(queue.currentID!))
        #expect(rows[0].id != queue.past[0].uuidString)
        #expect(catalog.rows(for: .playlist(UUID())).isEmpty)
    }
    @Test @MainActor func coldStartupIsSharedWithoutPhoneScene() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root), songs = tracks()
        for song in songs { try await repository.save(song) }
        let list = try await repository.createPlaylist(name: "Cold launch", trackIDs: [songs[1].id, songs[0].id])
        let suite = UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let store = PlayerStore(repository: repository, preferences: prefs, sharedDocumentsURL: nil)
        var preparations = 0
        let session = AppSession(store: store, prepare: { _ in preparations += 1; try await Task.sleep(for: .milliseconds(30)) })
        async let car: Void = session.start()
        async let phone: Void = session.start()
        _ = await (car, phone)
        await session.start()
        #expect(preparations == 1 && !store.isLoading && store.tracks.count == 5)
        #expect(store.playlists == [list] && store.current == nil && !store.isPlaying)
        #expect(store.queue.isEmpty)
    }
    #if os(iOS)
    #if !targetEnvironment(simulator)
    @Test func databaseAndMediaDirectoryAreReadableAfterFirstUnlock() async throws {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MusicRepository(root: root)
        _ = try await repository.load()
        for url in [root.appending(path: "library.sqlite"), root.appending(path: "Media")] {
            let protection = try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? String
            #expect(protection == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        }
    }
    #endif
    @Test func installedManifestRegistersAudioCarPlayScene() throws {
        let manifest = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
        let configs = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        let car = try #require(configs["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]])
        #expect(car.first?["UISceneClassName"] as? String == "CPTemplateApplicationScene")
        #expect(car.first?["UISceneDelegateClassName"] as? String == "Zuneyra.CarPlaySceneDelegate")
    }
    #endif
}
