import Foundation

enum CarPlayRoute: Hashable, Sendable {
    case playlists, favorites, albums, artists, playlist(UUID), album(String), artist(String), queue
}
enum CarPlayAction: Equatable, Sendable {
    case open(CarPlayRoute), play(UUID, CarPlayRoute), queueEntry(UUID), playAll(CarPlayRoute, shuffled: Bool)
}
struct CarPlayRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let action: CarPlayAction
    var trackID: UUID? = nil
}
struct CarPlayPage: Equatable {
    let rows: [CarPlayRow]
    let index: Int
    let previous: Int?
    let next: Int?
    static func make(rows: [CarPlayRow], index: Int, size: Int) -> Self {
        let size = max(1, size), last = max(0, (rows.count - 1) / size)
        let index = min(max(0, index), last), start = index * size
        return Self(rows: Array(rows.dropFirst(start).prefix(size)), index: index,
                    previous: index > 0 ? index - 1 : nil, next: index < last ? index + 1 : nil)
    }
}
struct CarPlayCatalog {
    let tracks: [Track]
    let playlists: [Playlist]
    let queue: PlaybackQueue
    func tracks(for route: CarPlayRoute) -> [Track] {
        switch route {
        case .favorites: return tracks.filter(\.favorite).sorted(by: songOrder)
        case .playlist(let id):
            let index = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            return playlists.first { $0.id == id }?.trackIDs.compactMap { index[$0] } ?? []
        case .album(let key): return tracks.filter { $0.albumKey == key }.sorted(by: songOrder)
        case .artist(let name): return tracks.filter { $0.artist == name }.sorted(by: songOrder)
        default: return []
        }
    }
    func rows(for route: CarPlayRoute) -> [CarPlayRow] {
        switch route {
        case .playlists:
            return playlists.map { .init(id: $0.id.uuidString, title: $0.name, detail: String(localized: "\($0.trackIDs.count) 首"), action: .open(.playlist($0.id))) }
        case .albums:
            return Dictionary(grouping: tracks, by: \.albumKey).values.compactMap { group in
                guard let track = group.first else { return nil }
                return CarPlayRow(id: track.albumKey, title: track.album, detail: String(localized: "\(track.albumArtist) · \(group.count) 首"), action: .open(.album(track.albumKey)), trackID: track.id)
            }.sorted { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artists:
            return Dictionary(grouping: tracks, by: \.artist).map { name, group in
                CarPlayRow(id: name, title: name, detail: String(localized: "\(group.count) 首"), action: .open(.artist(name)))
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .queue:
            let index = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            return ((queue.currentEntry.map { [$0] } ?? []) + queue.upcomingEntries).compactMap { entry in
                guard let track = index[entry.trackID] else { return nil }
                return .init(id: entry.id.uuidString, title: track.title, detail: track.artist, action: .queueEntry(entry.id), trackID: track.id)
            }
        default:
            let songs = tracks(for: route)
            guard !songs.isEmpty else { return [] }
            return [CarPlayRow(id: "play-all", title: String(localized: "播放全部"), detail: String(localized: "\(songs.count) 首"), action: .playAll(route, shuffled: false)),
                    CarPlayRow(id: "shuffle-all", title: String(localized: "随机播放"), detail: "", action: .playAll(route, shuffled: true))] + songs.map {
                .init(id: $0.id.uuidString, title: $0.title, detail: $0.artist, action: .play($0.id, route), trackID: $0.id)
            }
        }
    }
    func title(for route: CarPlayRoute) -> String {
        switch route {
        case .playlists: String(localized: "歌单")
        case .favorites: String(localized: "收藏")
        case .albums: String(localized: "专辑")
        case .artists: String(localized: "艺术家")
        case .playlist(let id): playlists.first { $0.id == id }?.name ?? String(localized: "歌单已移除")
        case .album(let key): tracks.first { $0.albumKey == key }?.album ?? String(localized: "专辑已移除")
        case .artist(let name): name
        case .queue: String(localized: "播放队列")
        }
    }
    private func songOrder(_ a: Track, _ b: Track) -> Bool {
        if a.albumKey != b.albumKey { return a.albumKey.localizedStandardCompare(b.albumKey) == .orderedAscending }
        if a.trackNumber != b.trackNumber { return a.trackNumber < b.trackNumber }
        if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }
}
