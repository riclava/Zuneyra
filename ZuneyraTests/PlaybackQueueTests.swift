import Foundation
import Testing
@testable import Zuneyra

struct PlaybackQueueTests {
    @Test func occurrencesAreIndependentAndInsertionsDoNotAutoplay() throws {
        let a = UUID(), b = UUID(), c = UUID()
        var queue = PlaybackQueue(seed: 1)
        queue.append(trackIDs: [a, a])
        #expect(queue.currentEntry == nil)
        #expect(Set(queue.upcoming).count == 2)
        let second = queue.upcoming[1]
        queue.remove([queue.upcoming[0]])
        #expect(queue.upcoming == [second])
        queue.insertNext(trackIDs: [b, c])
        #expect(queue.upcomingEntries.map(\.trackID) == [b, c, a])
        #expect(queue.advance()?.trackID == b)
        queue.append(trackIDs: [b])
        #expect(queue.currentEntry?.trackID == b)
        #expect(queue.upcomingEntries.map(\.trackID) == [c, a, b])
        queue.select(second)
        #expect(queue.currentID == second)
        #expect(queue.pastEntries.map(\.trackID) == [b, c])
    }

    @Test func pendingEditsPreserveCurrentAndHistory() {
        let ids = (0..<5).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.replace(trackIDs: ids, selectedIndex: 1)
        let current = queue.currentID, past = queue.past
        queue.moveUpcoming(from: IndexSet([0, 2]), to: 3)
        #expect(queue.upcomingEntries.map(\.trackID) == [ids[3], ids[2], ids[4]])
        #expect(queue.currentID == current && queue.past == past)
        let order = queue.orderedEntries
        queue.moveUpcoming(from: IndexSet(integer: 9), to: 0)
        queue.moveUpcoming(from: IndexSet(integer: 0), to: -1)
        #expect(queue.orderedEntries == order)
        queue.setShuffle(true); queue.setShuffle(false)
        #expect(queue.orderedEntries == order)
        queue.clearUpcoming()
        #expect(queue.upcoming.isEmpty)
        #expect(queue.currentID == current && queue.past == past)
        #expect(queue.canonical.count == 2)
    }

    @Test func shuffleOnlyChangesPendingAndPreviousFollowsActualOrder() {
        let ids = (0..<12).map { _ in UUID() }
        var queue = PlaybackQueue(seed: 42)
        queue.replace(trackIDs: ids, selectedIndex: 2)
        var same = queue
        let current = queue.currentID, past = queue.past, original = queue.upcoming
        queue.setShuffle(true); same.setShuffle(true)
        #expect(queue.upcoming == same.upcoming && queue.upcoming != original)
        #expect(Set(queue.upcoming) == Set(original))
        #expect(queue.currentID == current && queue.past == past)
        let next = queue.advance()
        #expect(queue.previous()?.id == current)
        #expect(queue.advance() == next)
        let remaining = Set(queue.upcoming)
        queue.setShuffle(false)
        #expect(queue.upcoming == queue.canonical.map(\.id).filter { remaining.contains($0) })
    }

    @Test func repeatOneAppliesOnlyToNaturalCompletionAndAllWraps() {
        let a = UUID(), b = UUID()
        var queue = PlaybackQueue(seed: 42)
        queue.replace(trackIDs: [a, b], selectedIndex: 0)
        let first = queue.currentID
        queue.setRepeat(.one)
        #expect(queue.advance(naturally: true)?.id == first)
        #expect(queue.advance()?.trackID == b)
        #expect(queue.advance() == nil)
        queue.setRepeat(.all)
        #expect(queue.advance()?.id == first)
        #expect(queue.past.isEmpty)
        queue.setShuffle(true)
        _ = queue.advance()
        let last = queue.currentID
        #expect(queue.advance()?.id != last)
        #expect(queue.past.isEmpty)
    }

    @Test func snapshotsPreserveOccurrenceIdentityAndReconcileMissingRows() throws {
        let ids = (0..<5).map { _ in UUID() }
        var queue = PlaybackQueue(seed: 4)
        queue.replace(trackIDs: ids + [ids[0]], selectedIndex: 1)
        queue.setShuffle(true); queue.setRepeat(.all)
        _ = queue.advance()
        let snapshot = PlaybackSnapshot(queue: queue, position: 12.3)
        let restored = try JSONDecoder().decode(PlaybackSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.version == 2 && restored.position == 12.3 && restored.queue == queue)
        var reconciled = restored.queue
        reconciled.reconcile(validTrackIDs: Set(ids))
        #expect(reconciled == queue)
        let removedTrack = try #require(queue.currentEntry?.trackID)
        reconciled.reconcile(validTrackIDs: Set(ids.filter { $0 != removedTrack }))
        #expect(reconciled.currentEntry == nil)
        #expect(!reconciled.orderedEntries.contains { $0.trackID == removedTrack })
        #expect(reconciled.orderedEntries.count == reconciled.canonical.count)
    }

    @Test func emptyAndSingleEntryQueuesHaveBoundedTransitions() {
        var queue = PlaybackQueue()
        queue.setRepeat(.all)
        #expect(queue.advance() == nil && queue.previous() == nil)
        queue.append(trackIDs: [UUID()])
        let first = queue.advance()
        #expect(queue.advance() == first)
        #expect(queue.previous() == first)
        queue.removeTracks([first!.trackID])
        #expect(queue.currentID == nil && queue.canonical.isEmpty)
        #expect(queue.advance() == nil)
    }
}
