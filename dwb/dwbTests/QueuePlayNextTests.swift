import Foundation
import XCTest

/// Tests for the Play Next ordered pending chain policy (P120.1).
///
/// Convention used throughout:
///   playbackSet = ["A","B","C","D","E","F"] at indices [0,1,2,3,4,5]
///   displayOrder = [0,1,2,3,4,5] (natural order)
///   currentDisplayIndex = index into displayOrder of currently playing item
///   pendingSetIndices = ordered FIFO chain of set indices waiting to play next
final class QueuePlayNextTests: XCTestCase {

    func testFailureAdvanceConsumesPlayNextFIFOOneItemAtATime() {
        var displayOrder = [0, 1, 2, 3, 4] // A, B, C, D, E
        var currentDisplayIndex = 0         // A
        var pending: [Int] = []

        XCTAssertTrue(PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 4, // E
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        ))
        XCTAssertTrue(PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 4, // D after E moved ahead of it
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        ))
        XCTAssertEqual(displayOrder, [0, 4, 3, 1, 2])
        XCTAssertEqual(pending, [4, 3])

        // Failure uses normal next navigation: A -> E, then E -> D.
        currentDisplayIndex += 1
        PlayNextChainPolicy.onPlaybackStarted(
            currentSetIndex: displayOrder[currentDisplayIndex],
            displayOrder: displayOrder,
            currentDisplayIndex: currentDisplayIndex,
            pendingSetIndices: &pending
        )
        XCTAssertEqual(displayOrder[currentDisplayIndex], 4)
        XCTAssertEqual(pending, [3])

        currentDisplayIndex += 1
        PlayNextChainPolicy.onPlaybackStarted(
            currentSetIndex: displayOrder[currentDisplayIndex],
            displayOrder: displayOrder,
            currentDisplayIndex: currentDisplayIndex,
            pendingSetIndices: &pending
        )
        XCTAssertEqual(displayOrder[currentDisplayIndex], 3)
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - 1. First Play Next selection moves immediately after current

    func test1_firstPlayNextMovesImmediatelyAfterCurrent() {
        var displayOrder = [0, 1, 2, 3, 4, 5] // A, B, C, D, E, F
        var currentDisplayIndex = 0           // playing A
        var pending: [Int] = []

        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 4,             // E
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(displayOrder, [0, 4, 1, 2, 3, 5]) // A, E, B, C, D, F
        XCTAssertEqual(currentDisplayIndex, 0)           // still playing A
        XCTAssertEqual(pending, [4])                     // E is pending #1
    }

    // MARK: - 2. Second selection appends after first pending item

    func test2_secondSelectionAppendsAfterFirstPendingItem() {
        var displayOrder = [0, 4, 1, 2, 3, 5] // A, E, B, C, D, F
        var currentDisplayIndex = 0           // playing A
        var pending: [Int] = [4]              // E is pending #1

        // User selects D (currently at displayIndex 4 in displayOrder, setIdx 3)
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 4,             // D
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(displayOrder, [0, 4, 3, 1, 2, 5]) // A, E, D, B, C, F
        XCTAssertEqual(currentDisplayIndex, 0)           // still playing A
        XCTAssertEqual(pending, [4, 3])                  // E (#1), D (#2)
    }

    // MARK: - 3. Third selection appends after the first two

    func test3_thirdSelectionAppendsAfterFirstTwo() {
        var displayOrder = [0, 4, 3, 1, 2, 5] // A, E, D, B, C, F
        var currentDisplayIndex = 0           // playing A
        var pending: [Int] = [4, 3]           // E (#1), D (#2)

        // User selects F (at displayIndex 5, setIdx 5)
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 5,             // F
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(displayOrder, [0, 4, 3, 5, 1, 2]) // A, E, D, F, B, C
        XCTAssertEqual(currentDisplayIndex, 0)           // still playing A
        XCTAssertEqual(pending, [4, 3, 5])               // E (#1), D (#2), F (#3)
    }

    // MARK: - 4. Playback advancement consumes the first pending item while retaining the remaining chain

    func test4_playbackAdvancementConsumesFirstPendingRetainingRemaining() {
        let displayOrder = [0, 4, 3, 5, 1, 2] // A, E, D, F, B, C
        let currentDisplayIndex = 1           // advanced to E (setIdx 4)
        var pending: [Int] = [4, 3, 5]

        PlayNextChainPolicy.onPlaybackStarted(
            currentSetIndex: 4,
            displayOrder: displayOrder,
            currentDisplayIndex: currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertEqual(pending, [3, 5]) // E consumed; D (#1) and F (#2) remain
        XCTAssertEqual(displayOrder[currentDisplayIndex + 1], 3) // D is immediately next
        XCTAssertEqual(displayOrder[currentDisplayIndex + 2], 5) // F is after D
    }

    // MARK: - 5. A new selection after advancement appends after remaining pending entries

    func test5_newSelectionAfterAdvancementAppendsAfterRemainingPendingEntries() {
        var displayOrder = [0, 4, 3, 5, 1, 2] // A, E, D, F, B, C
        var currentDisplayIndex = 1           // playing E (setIdx 4)
        var pending: [Int] = [3, 5]           // remaining: D (#1), F (#2)

        // User selects C (at displayIndex 5, setIdx 2) while E is playing
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 5,             // C
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(displayOrder, [0, 4, 3, 5, 2, 1]) // A, E, D, F, C, B
        XCTAssertEqual(currentDisplayIndex, 1)           // still playing E
        XCTAssertEqual(pending, [3, 5, 2])               // D (#1), F (#2), C (#3)
    }

    // MARK: - 6. Selecting an already pending item does not duplicate or reorder it

    func test6_selectingAlreadyPendingItemDoesNotDuplicateOrReorder() {
        var displayOrder = [0, 4, 3, 1, 2, 5] // A, E, D, B, C, F
        var currentDisplayIndex = 0           // playing A
        var pending: [Int] = [4, 3]           // E (#1), D (#2)

        // User selects D again (displayIndex 2, setIdx 3)
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 2,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertFalse(changed) // safe no-op
        XCTAssertEqual(displayOrder, [0, 4, 3, 1, 2, 5]) // unchanged
        XCTAssertEqual(pending, [4, 3])                  // unchanged
    }

    // MARK: - 7. Selecting current item remains invalid/no-op

    func test7_selectingCurrentItemRemainsInvalidNoOp() {
        var displayOrder = [0, 1, 2, 3]
        var currentDisplayIndex = 1 // playing B (setIdx 1)
        var pending: [Int] = []

        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 1, // B itself
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertFalse(changed)
        XCTAssertEqual(displayOrder, [0, 1, 2, 3])
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - 8. Selecting from before current calculates indexes correctly

    func test8_selectingFromBeforeCurrentCalculatesIndexesCorrectly() {
        var displayOrder = [0, 1, 4, 2, 3] // X(0), A(1, playing), E(4, pending), B(2), C(3)
        var currentDisplayIndex = 1        // playing A
        var pending: [Int] = [4]           // E is pending #1

        // Select X (at displayIndex 0, before current)
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 0,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        // X moves after E: [A(1), E(4), X(0), B(2), C(3)]
        XCTAssertEqual(displayOrder, [1, 4, 0, 2, 3])
        XCTAssertEqual(currentDisplayIndex, 0) // A is now at index 0
        XCTAssertEqual(displayOrder[currentDisplayIndex], 1) // still A playing
        XCTAssertEqual(pending, [4, 0])        // E (#1), X (#2)
    }

    // MARK: - 9. Selecting from after current calculates indexes correctly

    func test9_selectingFromAfterCurrentCalculatesIndexesCorrectly() {
        var displayOrder = [0, 1, 2, 3, 4] // A(0), B(1), C(2), D(3), E(4)
        var currentDisplayIndex = 0        // playing A
        var pending: [Int] = []

        // Select D (displayIndex 3)
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 3,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(displayOrder, [0, 3, 1, 2, 4]) // A, D, B, C, E
        XCTAssertEqual(currentDisplayIndex, 0)
        XCTAssertEqual(pending, [3])
    }

    // MARK: - 10. Filtered result appends to the correct canonical pending chain

    func test10_filteredResultAppendsToCorrectCanonicalPendingChain() {
        // Full queue: [alpha(0), beta(1), gamma(2), delta(3), beta-extra(4)]
        var displayOrder = [0, 1, 2, 3, 4]
        var currentDisplayIndex = 1 // playing beta
        var pending: [Int] = []

        // User searches for "beta". Visible items: beta (row 0 -> canonical 1), beta-extra (row 1 -> canonical 4).
        // User triggers Play Next on beta-extra (canonical 4):
        let changed1 = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 4,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )
        XCTAssertTrue(changed1)
        XCTAssertEqual(displayOrder, [0, 1, 4, 2, 3])
        XCTAssertEqual(pending, [4])

        // User clears or changes search to "delta" (visible -> canonical 3, now at displayIndex 4).
        // User triggers Play Next on delta (canonical 3, at displayIndex 4):
        let changed2 = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 4,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )
        XCTAssertTrue(changed2)
        XCTAssertEqual(displayOrder, [0, 1, 4, 3, 2])
        XCTAssertEqual(pending, [4, 3]) // beta-extra (#1), delta (#2)
    }

    // MARK: - 11. Removing a pending item does not leave invalid pending state

    func test11_removingPendingItemDoesNotLeaveInvalidPendingState() {
        var displayOrder = [0, 4, 3, 5, 1, 2] // A, E, D, F, B, C
        var pending: [Int] = [4, 3, 5]        // E (#1), D (#2), F (#3)

        // User deletes D (displayIndex 2, setIdx 3)
        let removedSetIdx = displayOrder[2]
        displayOrder.remove(at: 2)
        // Remap displayOrder for indices > 3
        displayOrder = displayOrder.map { $0 > removedSetIdx ? $0 - 1 : $0 }

        PlayNextChainPolicy.onQueueItemRemoved(
            removedSetIndex: removedSetIdx,
            pendingSetIndices: &pending
        )

        // D is removed, F (was 5) remapped to 4, E (was 4) remapped to 3
        XCTAssertEqual(pending, [3, 4]) // E (now setIdx 3), F (now setIdx 4)
        XCTAssertEqual(displayOrder, [0, 3, 4, 1, 2]) // A, E, F, B, C
    }

    // MARK: - 12. Clearing/replacing the queue clears stale pending state

    func test12_clearingOrReplacingQueueClearsStalePendingState() {
        var pending: [Int] = [4, 3, 5]
        pending.removeAll()
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - 13. Queue count and membership remain unchanged by Play Next reordering

    func test13_queueCountAndMembershipRemainUnchangedByPlayNextReordering() {
        let initialOrder = [0, 1, 2, 3, 4, 5]
        var displayOrder = initialOrder
        var currentDisplayIndex = 2 // playing C
        var pending: [Int] = []

        _ = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 5,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )
        _ = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 0,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertEqual(displayOrder.count, initialOrder.count)
        XCTAssertEqual(Set(displayOrder), Set(initialOrder))
    }

    // MARK: - 14. Current playback identity remains unchanged

    func test14_currentPlaybackIdentityRemainsUnchanged() {
        var displayOrder = [0, 1, 2, 3, 4]
        var currentDisplayIndex = 2 // playing C (setIdx 2)
        let originalPlayingSetIdx = displayOrder[currentDisplayIndex]
        var pending: [Int] = []

        _ = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 0,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertEqual(displayOrder[currentDisplayIndex], originalPlayingSetIdx)
    }

    // MARK: - Additional Practical Tests

    func testPractical_chainOfFourOrMore() {
        var displayOrder = [0, 1, 2, 3, 4, 5, 6] // A, B, C, D, E, F, G
        var currentDisplayIndex = 0              // A
        var pending: [Int] = []

        // Play Next: E, then D, then F, then C
        _ = PlayNextChainPolicy.applyPlayNext(targetDisplayIndex: 4, displayOrder: &displayOrder, currentDisplayIndex: &currentDisplayIndex, pendingSetIndices: &pending)
        _ = PlayNextChainPolicy.applyPlayNext(targetDisplayIndex: 4, displayOrder: &displayOrder, currentDisplayIndex: &currentDisplayIndex, pendingSetIndices: &pending)
        _ = PlayNextChainPolicy.applyPlayNext(targetDisplayIndex: 5, displayOrder: &displayOrder, currentDisplayIndex: &currentDisplayIndex, pendingSetIndices: &pending)
        _ = PlayNextChainPolicy.applyPlayNext(targetDisplayIndex: 5, displayOrder: &displayOrder, currentDisplayIndex: &currentDisplayIndex, pendingSetIndices: &pending)

        // Expected: A, E, D, F, C, B, G
        XCTAssertEqual(displayOrder, [0, 4, 3, 5, 2, 1, 6])
        XCTAssertEqual(pending, [4, 3, 5, 2])
    }

    func testPractical_duplicateEntriesDistinguishedBySetIndex() {
        // Two entries referencing identical content but at different set indices (e.g. 1 and 3)
        var displayOrder = [0, 1, 2, 3, 4] // A, song, C, song, D
        var currentDisplayIndex = 0
        var pending: [Int] = []

        // Add first song (setIdx 1)
        _ = PlayNextChainPolicy.applyPlayNext(targetDisplayIndex: 1, displayOrder: &displayOrder, currentDisplayIndex: &currentDisplayIndex, pendingSetIndices: &pending)
        // Add second song (setIdx 3, currently at displayIndex 3)
        _ = PlayNextChainPolicy.applyPlayNext(targetDisplayIndex: 3, displayOrder: &displayOrder, currentDisplayIndex: &currentDisplayIndex, pendingSetIndices: &pending)

        XCTAssertEqual(displayOrder, [0, 1, 3, 2, 4])
        XCTAssertEqual(pending, [1, 3])
    }

    func testPractical_ordinaryImmediateNextItemAppendedWithoutDisruption() {
        var displayOrder = [0, 1, 2, 3] // A, B, C, D
        var currentDisplayIndex = 0
        var pending: [Int] = []

        // B is already immediately next (displayIndex 1)
        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 1,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(displayOrder, [0, 1, 2, 3]) // queue order undisturbed
        XCTAssertEqual(pending, [1])               // B is now pending #1

        // Now select D (displayIndex 3)
        let changed2 = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: 3,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pending
        )

        XCTAssertTrue(changed2)
        XCTAssertEqual(displayOrder, [0, 1, 3, 2]) // D placed after B!
        XCTAssertEqual(pending, [1, 3])
    }
}
