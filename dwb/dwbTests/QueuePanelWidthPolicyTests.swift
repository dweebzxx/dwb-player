import XCTest

final class QueuePanelWidthPolicyTests: XCTestCase {

    private let accuracy: CGFloat = 0.0001

    // MARK: Default width (no custom fraction)

    func testDefaultWidthFollowsTodaysRule() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 480, customFraction: nil), 260, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 577, customFraction: nil), 260, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: nil), 450, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 2000, customFraction: nil), 900, accuracy: accuracy)
    }

    // MARK: Clamping

    func testCustomFractionBelowMinimumClampsTo200() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: 0.05), 200, accuracy: accuracy)
    }

    func testCustomFractionAboveMaximumClampsToMaximum() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: 0.9), 450, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 480, customFraction: 0.9), 260, accuracy: accuracy)
    }

    // MARK: Proportion across window resizes

    func testFractionIsKeptAcrossResize() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: 0.30), 300, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 2000, customFraction: 0.30), 600, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 600, customFraction: 0.30), 200, accuracy: accuracy)
    }

    // MARK: Drag position → stored fraction

    func testDragEndingAtMaximumClearsCustomWidth() {
        // Edge at 550 in a 1000 pt window is a 450 pt panel, the maximum.
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 550, contentWidth: 1000))
    }

    func testDragPastMaximumClearsCustomWidth() {
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 100, contentWidth: 1000))
    }

    func testDragPastMinimumStoresFractionFor200() throws {
        let fraction = try XCTUnwrap(QueuePanelWidthPolicy.customFraction(forEdgeX: 950, contentWidth: 1000))
        XCTAssertEqual(fraction, 0.2, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: fraction), 200, accuracy: accuracy)
    }

    func testDragInsideLimitsStoresItsFraction() throws {
        let fraction = try XCTUnwrap(QueuePanelWidthPolicy.customFraction(forEdgeX: 700, contentWidth: 1000))
        XCTAssertEqual(fraction, 0.3, accuracy: accuracy)
    }

    // MARK: Header title (narrow panel)

    func testHeaderTitleHidesBelowTodaysMinimumWidth() {
        XCTAssertTrue(QueuePanelWidthPolicy.showsHeaderTitle(panelWidth: 260))
        XCTAssertTrue(QueuePanelWidthPolicy.showsHeaderTitle(panelWidth: 450))
        XCTAssertFalse(QueuePanelWidthPolicy.showsHeaderTitle(panelWidth: 259))
        XCTAssertFalse(QueuePanelWidthPolicy.showsHeaderTitle(panelWidth: 200))
    }
}
