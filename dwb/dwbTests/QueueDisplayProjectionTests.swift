import Cocoa
import Foundation
import XCTest

final class QueueDisplayProjectionTests: XCTestCase {

    // Minimal stand-in for queue items — no AppKit dependency required.
    private struct Item {
        let displayName: String
        let path: String
    }

    private func makeItems(_ names: [(String, String)]) -> [Item] {
        names.map { Item(displayName: $0.0, path: $0.1) }
    }

    private func filteredPairs(
        from items: [Item],
        query: String,
        bookmarkedPaths: Set<String> = [],
        bookmarkFilterEnabled: Bool = false
    ) -> [(Int, Item)] {
        QueueDisplayProjection.filteredPairs(
            from: items,
            displayName: \.displayName,
            urlPath: \.path,
            query: query,
            bookmarkedPaths: bookmarkedPaths,
            bookmarkFilterEnabled: bookmarkFilterEnabled
        )
    }

    // MARK: - filteredPairs — search

    func testEmptyQueryReturnsAll() {
        let items = makeItems([("alpha.mp4", "/a"), ("beta.mp4", "/b"), ("gamma.mp4", "/c")])
        let pairs = filteredPairs(from: items, query: "")
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs.map(\.0), [0, 1, 2])
    }

    func testQueryFiltersToMatchingItems() {
        let items = makeItems([("alpha.mp4", "/a"), ("beta.mp4", "/b"), ("alphabet.mov", "/c")])
        let pairs = filteredPairs(from: items, query: "alpha")
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 0) // alpha.mp4 at display index 0
        XCTAssertEqual(pairs[1].0, 2) // alphabet.mov at display index 2
    }

    func testQueryIsCaseInsensitive() {
        let items = makeItems([("MOVIE.mp4", "/a"), ("movie.mp4", "/b"), ("other.mp4", "/c")])
        let pairs = filteredPairs(from: items, query: "movie")
        XCTAssertEqual(pairs.count, 2)
    }

    func testQueryMatchesNone() {
        let items = makeItems([("alpha.mp4", "/a"), ("beta.mp4", "/b")])
        let pairs = filteredPairs(from: items, query: "zzz")
        XCTAssertTrue(pairs.isEmpty)
    }

    func testQueryOnEmptyItemsReturnsEmpty() {
        let pairs = filteredPairs(from: [], query: "anything")
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - filteredPairs — bookmark filter

    func testBookmarkFilterDisabledReturnsAll() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b")])
        let pairs = filteredPairs(from: items, query: "", bookmarkedPaths: ["/a"], bookmarkFilterEnabled: false)
        XCTAssertEqual(pairs.count, 2)
    }

    func testBookmarkFilterEnabledReturnsOnlyBookmarked() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b"), ("c.mp4", "/c")])
        let pairs = filteredPairs(from: items, query: "", bookmarkedPaths: ["/b", "/c"], bookmarkFilterEnabled: true)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 1)
        XCTAssertEqual(pairs[1].0, 2)
    }

    func testBookmarkFilterEnabledWithNoBookmarksReturnsEmpty() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b")])
        let pairs = filteredPairs(from: items, query: "", bookmarkedPaths: [], bookmarkFilterEnabled: true)
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - filteredPairs — combined search + bookmark filter

    func testCombinedSearchAndBookmarkFilter() {
        let items = makeItems([
            ("alpha.mp4", "/a"),
            ("alpha_bookmarked.mp4", "/b"),
            ("beta.mp4", "/c"),
        ])
        let pairs = filteredPairs(
            from: items,
            query: "alpha",
            bookmarkedPaths: ["/b"],
            bookmarkFilterEnabled: true
        )
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0, 1)
        XCTAssertEqual(pairs[0].1.displayName, "alpha_bookmarked.mp4")
    }

    // MARK: - filteredPairs — display index stability

    func testDisplayIndicesReflectOriginalPosition() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b"), ("c.mp4", "/c"), ("d.mp4", "/d")])
        let pairs = filteredPairs(from: items, query: "b")
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0, 1) // "b.mp4" is at original index 1
    }

    // MARK: - allowsManualReorder

    func testAllowsReorderWhenManualSortAndNoFilters() {
        XCTAssertTrue(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "", bookmarkFilterEnabled: false
        ))
    }

    func testDisallowsReorderWhenNotManualSort() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: false, query: "", bookmarkFilterEnabled: false
        ))
    }

    func testDisallowsReorderWhenQueryActive() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "foo", bookmarkFilterEnabled: false
        ))
    }

    func testDisallowsReorderWhenBookmarkFilterActive() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "", bookmarkFilterEnabled: true
        ))
    }

    func testDisallowsReorderWhenBothFiltersActive() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "foo", bookmarkFilterEnabled: true
        ))
    }

    // MARK: - sectioned rows and command mapping

    func testVisibleRowsMapToUnderlyingDisplayIndices() {
        let rows = QueueDisplayProjection.sectionedRows(
            displayIndices: [0, 1, 2, 3],
            currentDisplayIndex: 2,
            filterActive: false
        )
        XCTAssertEqual(rows, [
            .section("PREVIOUS"), .item(displayIndex: 0), .item(displayIndex: 1),
            .section("NOW PLAYING"), .item(displayIndex: 2),
            .section("UP NEXT"), .item(displayIndex: 3),
        ])
        XCTAssertEqual(
            QueueDisplayProjection.displayIndices(forVisibleRows: IndexSet([1, 4, 6]), in: rows),
            [0, 2, 3]
        )
    }

    func testSearchAndBookmarkFilteringRetainOriginalDisplayIndicesForDeletion() {
        let items = makeItems([
            ("alpha.mp4", "/a"),
            ("beta.mp4", "/b"),
            ("alpha-bookmarked.mp4", "/c"),
            ("delta.mp4", "/d"),
        ])
        let pairs = filteredPairs(
            from: items,
            query: "alpha",
            bookmarkedPaths: ["/c"],
            bookmarkFilterEnabled: true
        )
        let rows = QueueDisplayProjection.sectionedRows(
            displayIndices: pairs.map(\.0),
            currentDisplayIndex: 1,
            filterActive: true
        )
        XCTAssertEqual(rows, [.section("UP NEXT"), .item(displayIndex: 2)])
        XCTAssertEqual(QueueDisplayProjection.displayIndices(forVisibleRows: IndexSet(integer: 1), in: rows), [2])
    }

    func testDeleteAndForwardDeleteUseAllSelectedVisibleRowsDescending() {
        XCTAssertTrue(QueueDisplayProjection.isDeletionKeyCode(51), "Backspace must route to queue deletion")
        XCTAssertTrue(QueueDisplayProjection.isDeletionKeyCode(117), "Forward Delete must route to queue deletion")
        XCTAssertFalse(QueueDisplayProjection.isDeletionKeyCode(36), "Return must not route to queue deletion")

        let rows: [QueueDisplayProjection.Row] = [
            .section("UP NEXT"),
            .item(displayIndex: 1),
            .item(displayIndex: 4),
            .item(displayIndex: 7),
        ]
        let mapped = QueueDisplayProjection.displayIndices(forVisibleRows: IndexSet([1, 2, 3]), in: rows)
        let plan = QueueDisplayProjection.deletionPlan(
            itemCount: 8,
            currentDisplayIndex: 0,
            requestedDisplayIndices: mapped
        )
        XCTAssertEqual(plan.descendingDisplayIndices, [7, 4, 1])
    }

    func testNearestValidRowSelectionSkipsSectionRowsAfterReload() {
        let rows: [QueueDisplayProjection.Row] = [
            .section("PREVIOUS"),
            .item(displayIndex: 0),
            .section("NOW PLAYING"),
            .item(displayIndex: 1),
        ]
        XCTAssertEqual(QueueDisplayProjection.nearestSelectableRow(anchor: 2, in: rows), 3)
        XCTAssertEqual(QueueDisplayProjection.nearestSelectableRow(anchor: 8, in: rows), 3)
    }

    func testCurrentItemDeletionAdvancesToNearestEstablishedSuccessor() {
        let middle = QueueDisplayProjection.deletionPlan(
            itemCount: 5,
            currentDisplayIndex: 2,
            requestedDisplayIndices: [2]
        )
        XCTAssertTrue(middle.removesCurrentItem)
        XCTAssertEqual(middle.resultingCurrentDisplayIndex, 2)

        let last = QueueDisplayProjection.deletionPlan(
            itemCount: 5,
            currentDisplayIndex: 4,
            requestedDisplayIndices: [4]
        )
        XCTAssertEqual(last.resultingCurrentDisplayIndex, 3)
    }

    func testContextActionMappingUsesTheClickedVisibleRow() {
        let rows: [QueueDisplayProjection.Row] = [
            .section("UP NEXT"),
            .item(displayIndex: 5),
            .item(displayIndex: 9),
        ]
        XCTAssertEqual(rows[2].displayIndex, 9)
        XCTAssertNil(rows[0].displayIndex)
    }

}
