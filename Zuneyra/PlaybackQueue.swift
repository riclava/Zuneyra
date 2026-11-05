import Foundation

struct QueueEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let trackID: UUID
    init(trackID: UUID) { id = UUID(); self.trackID = trackID }
}

enum QueueRepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    var title: String { switch self { case .off: String(localized: "关闭循环"); case .all: String(localized: "列表循环"); case .one: String(localized: "单曲循环") } }
    var symbol: String { self == .one ? "repeat.1" : "repeat" }
    var next: Self { switch self { case .off: .all; case .all: .one; case .one: .off } }
}

/// The player presents mutually exclusive modes; legacy shuffle/repeat combinations
/// are displayed as shuffle and normalized on the next explicit mode change.
enum PlaybackMode: CaseIterable {
    case sequential, repeatAll, repeatOne, shuffle
    var title: String { switch self {
    case .sequential: String(localized: "顺序播放")
    case .repeatAll: String(localized: "列表循环")
    case .repeatOne: String(localized: "单曲循环")
    case .shuffle: String(localized: "随机播放")
    } }
    var symbol: String { switch self {
    case .sequential: "arrow.right"
    case .repeatAll: "repeat"
    case .repeatOne: "repeat.1"
    case .shuffle: "shuffle"
    } }
    var next: Self { switch self {
    case .sequential: .repeatAll
    case .repeatAll: .repeatOne
    case .repeatOne: .shuffle
    case .shuffle: .sequential
    } }
}

/// A cycle contains unique entry IDs even when the underlying tracks repeat.
/// Past/current/upcoming are separate, so edits never relocate the playing item.
struct PlaybackQueue: Codable, Equatable, Sendable {
    private(set) var canonical: [QueueEntry] = []
    private(set) var past: [UUID] = []
    private(set) var currentID: UUID?
    private(set) var upcoming: [UUID] = []
    private(set) var shuffle = false
    private(set) var repeatMode: QueueRepeatMode = .off
    private var seed: UInt64

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { self.seed = seed }
    var currentEntry: QueueEntry? { canonical.first { $0.id == currentID } }
    var orderedEntries: [QueueEntry] {
        let byID = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })
        return (past + (currentID.map { [$0] } ?? []) + upcoming).compactMap { byID[$0] }
    }
    var upcomingEntries: [QueueEntry] {
        let byID = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })
        return upcoming.compactMap { byID[$0] }
    }
    var pastEntries: [QueueEntry] {
        let byID = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })
        return past.compactMap { byID[$0] }
    }
    mutating func replace(trackIDs: [UUID], selectedIndex: Int?) {
        canonical = trackIDs.map { QueueEntry(trackID: $0) }
        past = []; upcoming = []; currentID = nil
        if let index = selectedIndex, canonical.indices.contains(index) {
            currentID = canonical[index].id
            if shuffle { upcoming = randomized(canonical.map(\.id).filter { $0 != currentID }) }
            else { past = canonical.prefix(index).map(\.id); upcoming = canonical.dropFirst(index + 1).map(\.id) }
        } else {
            upcoming = canonical.map(\.id)
            if shuffle { upcoming = randomized(upcoming) }
        }
    }
    mutating func setShuffle(_ enabled: Bool) {
        guard enabled != shuffle else { return }
        shuffle = enabled
        if enabled { upcoming = randomized(upcoming) }
        else {
            let pending = Set(upcoming)
            upcoming = canonical.map(\.id).filter { pending.contains($0) }
        }
    }
    var playbackMode: PlaybackMode {
        if shuffle { return .shuffle }
        switch repeatMode {
        case .off: return .sequential
        case .all: return .repeatAll
        case .one: return .repeatOne
        }
    }
    mutating func cyclePlaybackMode() {
        let next = playbackMode.next
        setShuffle(next == .shuffle)
        setRepeat(next == .repeatAll ? .all : next == .repeatOne ? .one : .off)
    }
    mutating func setRepeat(_ mode: QueueRepeatMode) { repeatMode = mode }
    mutating func insertNext(trackIDs: [UUID]) {
        let additions = trackIDs.map { QueueEntry(trackID: $0) }
        let index = canonical.firstIndex { $0.id == currentID }.map { $0 + 1 } ?? 0
        canonical.insert(contentsOf: additions, at: index)
        upcoming.insert(contentsOf: additions.map(\.id), at: 0)
    }
    mutating func append(trackIDs: [UUID]) {
        let additions = trackIDs.map { QueueEntry(trackID: $0) }
        canonical.append(contentsOf: additions)
        upcoming.append(contentsOf: additions.map(\.id))
    }
    @discardableResult mutating func select(_ id: UUID) -> QueueEntry? {
        let order = orderedEntries.map(\.id)
        guard let index = order.firstIndex(of: id) else { return nil }
        past = Array(order.prefix(index))
        currentID = id
        upcoming = Array(order.dropFirst(index + 1))
        return currentEntry
    }
    @discardableResult mutating func advance(naturally: Bool = false) -> QueueEntry? {
        if naturally, repeatMode == .one, let currentEntry { return currentEntry }
        if upcoming.isEmpty {
            guard repeatMode == .all, !canonical.isEmpty else { return nil }
            let previousID = currentID
            var next = canonical.map(\.id)
            if shuffle {
                next = randomized(next)
                if next.count > 1, next.first == previousID { next.swapAt(0, 1) }
            }
            past = []; currentID = nil; upcoming = next
        }
        if let currentID { past.append(currentID) }
        currentID = upcoming.removeFirst()
        return currentEntry
    }
    @discardableResult mutating func previous() -> QueueEntry? {
        guard let previous = past.popLast() else { return currentEntry }
        if let currentID { upcoming.insert(currentID, at: 0) }
        currentID = previous
        return currentEntry
    }
    mutating func remove(_ ids: Set<UUID>) {
        canonical.removeAll { ids.contains($0.id) }
        past.removeAll { ids.contains($0) }
        upcoming.removeAll { ids.contains($0) }
        if let currentID, ids.contains(currentID) { self.currentID = nil }
    }
    mutating func removeTracks(_ trackIDs: Set<UUID>) {
        remove(Set(canonical.filter { trackIDs.contains($0.trackID) }.map(\.id)))
    }
    mutating func clearUpcoming() { remove(Set(upcoming)) }
    mutating func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty, destination >= 0, destination <= upcoming.count,
              offsets.allSatisfy({ upcoming.indices.contains($0) }) else { return }
        let moved = offsets.sorted().map { upcoming[$0] }
        var remaining = upcoming.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
        upcoming = remaining
        // Explicit ordering becomes the new baseline, including when shuffled.
        canonical = orderedEntries
    }
    /// Validate decoded state and remove entries whose library records disappeared.
    mutating func reconcile(validTrackIDs: Set<UUID>) {
        var seen = Set<UUID>()
        canonical = canonical.filter { validTrackIDs.contains($0.trackID) && seen.insert($0.id).inserted }
        let valid = Set(canonical.map(\.id))
        if let currentID, !valid.contains(currentID) { self.currentID = nil }
        var claimed = Set<UUID>()
        if let currentID { claimed.insert(currentID) }
        past = past.filter { valid.contains($0) && claimed.insert($0).inserted }
        upcoming = upcoming.filter { valid.contains($0) && claimed.insert($0).inserted }
        upcoming += canonical.map(\.id).filter { !claimed.contains($0) }
    }
    private mutating func randomized(_ ids: [UUID]) -> [UUID] {
        var result = ids
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            seed &+= 0x9E3779B97F4A7C15
            var value = seed
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            result.swapAt(index, Int(value % UInt64(index + 1)))
        }
        return result
    }
}

struct PlaybackSnapshot: Codable {
    var version = 2
    let queue: PlaybackQueue
    let position: Double
}
