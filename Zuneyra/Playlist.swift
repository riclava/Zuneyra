import Foundation

struct Playlist: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var trackIDs: [UUID]
}

extension Array {
    /// Matches SwiftUI's move destination (before removing the source indexes).
    func moving(from offsets: IndexSet, to destination: Int) -> [Element]? {
        guard !offsets.isEmpty, destination >= 0, destination <= count,
              offsets.allSatisfy({ indices.contains($0) }) else { return nil }
        let moved = offsets.sorted().map { self[$0] }
        var result = enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
        return result
    }
}
