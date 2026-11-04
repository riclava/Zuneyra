import Foundation

enum LibrarySongSort: String, CaseIterable, Identifiable {
    case recent, title, artist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "最近添加"
        case .title: "歌曲名称"
        case .artist: "艺术家"
        }
    }

    func apply(to tracks: [Track]) -> [Track] {
        switch self {
        case .recent:
            return tracks
        case .title:
            return tracks.sorted(by: libraryTitlePrecedes)
        case .artist:
            return tracks.sorted { lhs, rhs in
                let comparison = lhs.artist.localizedStandardCompare(rhs.artist)
                return comparison == .orderedSame
                    ? libraryTitlePrecedes(lhs, rhs)
                    : comparison == .orderedAscending
            }
        }
    }
}

enum LibraryPresentation {
    static func albumTracks(_ tracks: [Track]) -> [Track] {
        tracks.sorted { lhs, rhs in
            let lhsNumbered = lhs.trackNumber > 0
            let rhsNumbered = rhs.trackNumber > 0
            if lhsNumbered != rhsNumbered { return lhsNumbered }
            if lhsNumbered, lhs.trackNumber != rhs.trackNumber {
                return lhs.trackNumber < rhs.trackNumber
            }
            return libraryTitlePrecedes(lhs, rhs)
        }
    }

    static func matches(_ track: Track, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [track.title, track.artist, track.album, track.albumArtist, track.filename]
            .contains { $0.localizedStandardContains(query) }
    }
}

private func libraryTitlePrecedes(_ lhs: Track, _ rhs: Track) -> Bool {
    let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
    if titleComparison != .orderedSame { return titleComparison == .orderedAscending }
    let filenameComparison = lhs.filename.localizedStandardCompare(rhs.filename)
    if filenameComparison != .orderedSame { return filenameComparison == .orderedAscending }
    return lhs.id.uuidString < rhs.id.uuidString
}
