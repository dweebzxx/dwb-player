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

    // MARK: Player formula and snap tolerance (§10.1)

    func testPlayerWidthUsesThePlayerBranchNotTheSkimGridOne() {
        // Skim and grid would give 280...360 (31%); the player gives max(260, 45%).
        XCTAssertEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 1000), 450, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 1000),
                       DWBMetrics.queuePanelMaxWidth(contentWidth: 1000, isPlayer: true), accuracy: accuracy)
        XCTAssertNotEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 1000),
                          DWBMetrics.queuePanelMaxWidth(contentWidth: 1000, isPlayer: false))
        XCTAssertEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 400), 260, accuracy: accuracy)
    }

    func testSnapToleranceIsHalfAPoint() throws {
        XCTAssertEqual(DWBMetrics.queuePanelSnapTolerance, 0.5)
        // 449.6 pt is within 0.5 of the 450 maximum: the custom width clears.
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 1000 - 449.6, contentWidth: 1000))
        // 449.4 pt is not.
        XCTAssertNotNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 1000 - 449.4, contentWidth: 1000))
    }

    func testHalfOfASmallMaximumStillClampsToTheMinimum() {
        // A 400 pt window has a 260 pt maximum; half of that is below 200 only when clamped.
        XCTAssertEqual(QueuePanelWidthPolicy.clampedWidth(130, contentWidth: 400), 200, accuracy: accuracy)
    }

    // MARK: Keyboard resize uses the drag's clamp and snap

    func testKeyboardWidenAndNarrowMoveByTenPoints() throws {
        let narrower = try XCTUnwrap(QueuePanelWidthPolicy.customFraction(afterResizingBy: -10, currentWidth: 300, contentWidth: 1000))
        XCTAssertEqual(narrower * 1000, 290, accuracy: accuracy)
        let wider = try XCTUnwrap(QueuePanelWidthPolicy.customFraction(afterResizingBy: 10, currentWidth: 300, contentWidth: 1000))
        XCTAssertEqual(wider * 1000, 310, accuracy: accuracy)
    }

    func testKeyboardNarrowingStopsAtTheMinimum() throws {
        let fraction = try XCTUnwrap(QueuePanelWidthPolicy.customFraction(afterResizingBy: -10, currentWidth: 205, contentWidth: 1000))
        XCTAssertEqual(fraction * 1000, 200, accuracy: accuracy)
        let stuck = try XCTUnwrap(QueuePanelWidthPolicy.customFraction(afterResizingBy: -10, currentWidth: 200, contentWidth: 1000))
        XCTAssertEqual(stuck * 1000, 200, accuracy: accuracy)
    }

    func testKeyboardWideningToTheMaximumClearsTheCustomWidth() {
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(afterResizingBy: 10, currentWidth: 445, contentWidth: 1000))
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(afterResizingBy: 10, currentWidth: 450, contentWidth: 1000))
    }
}
