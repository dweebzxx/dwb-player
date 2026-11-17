import XCTest

final class RailOverflowModelTests: XCTestCase {
    private func input(width: CGFloat = 800) -> RailOverflowModel.Input {
        var input = RailOverflowModel.Input(width: width)
        input.primary = "keep_"
        input.secondary = "later_"
        input.canRename = true
        input.canShuffle = true
        input.hasItem = true
        return input
    }

    func testNoOverflowSelectsDirectSettingsAndHasNoMenu() {
        let model = RailOverflowModel(input())
        XCTAssertEqual(model.utility, .settings)
        XCTAssertTrue(model.items.isEmpty)
    }

    func testOneOverflowActionSelectsMoreWithSettingsLast() {
        let model = RailOverflowModel(input(width: 559))
        XCTAssertEqual(model.utility, .more)
        XCTAssertEqual(model.items.map(\.action), [.bookmark, .settings])
        XCTAssertFalse(model.primaryHidden)
        XCTAssertFalse(model.secondaryHidden)
    }

    func testMultipleActionsPreserveOrderLabelsChecksAndEnablement() {
        var value = input(width: 389)
        value.shuffleOn = true
        value.repeatOn = true
        value.bookmarked = true
        let model = RailOverflowModel(value)
        XCTAssertEqual(model.items.map(\.action), [.customPrefix, .customPrefixSecondary, .shuffle, .replay, .bookmark, .settings])
        XCTAssertEqual(model.items.map(\.title), ["k_", "l_", "Shuffle", "Repeat one", "Bookmark", "Settings"])
        XCTAssertEqual(model.items.map(\.isOn), [false, false, true, true, true, false])
        XCTAssertTrue(model.items.allSatisfy(\.isEnabled))
    }

    func testDisabledEligibleActionsStillSelectMore() {
        var value = input(width: 499)
        value.canRename = false
        value.hasItem = false
        let model = RailOverflowModel(value)
        XCTAssertEqual(model.utility, .more)
        XCTAssertEqual(model.items.map(\.action), [.customPrefix, .customPrefixSecondary, .bookmark, .settings])
        XCTAssertEqual(model.items.map(\.isEnabled), [false, false, false, true])
        value.width = 389
        value.canShuffle = false
        XCTAssertEqual(RailOverflowModel(value).items.first(where: { $0.action == .shuffle })?.isEnabled, false)
        // Repeat remains enabled in overflow even without playable media.
        XCTAssertEqual(RailOverflowModel(value).items.first(where: { $0.action == .replay })?.isEnabled, true)
    }

    func testPreferenceDisabledPrefixesAreAbsentFromOverflow() {
        var value = input(width: 499)
        value.showPrefixes = false
        let model = RailOverflowModel(value)
        XCTAssertTrue(model.primaryHidden)
        XCTAssertTrue(model.secondaryHidden)
        XCTAssertEqual(model.items.map(\.action), [.bookmark, .settings])
        value.width = 800
        XCTAssertEqual(RailOverflowModel(value).utility, .settings)
    }

    func testBlankAndEqualPrefixesPreserveExistingEligibility() {
        var value = input(width: 499)
        value.primary = "  "
        value.secondary = ""
        XCTAssertEqual(RailOverflowModel(value).items.map(\.action), [.bookmark, .settings])
        value.primary = "keep_"
        value.secondary = "keep"
        XCTAssertEqual(RailOverflowModel(value).items.map(\.action), [.customPrefix, .bookmark, .settings])
        value.primary = ""
        value.secondary = "later_"
        XCTAssertEqual(RailOverflowModel(value).items.map(\.action), [.customPrefixSecondary, .bookmark, .settings])
    }

    func testNonPrefixPreferencesKeepHiddenButtonOverflowRules() {
        var value = input()
        value.showShuffle = false
        value.showRepeat = false
        value.showBookmark = false
        value.showVolume = false
        let model = RailOverflowModel(value)
        XCTAssertEqual(model.utility, .more)
        XCTAssertEqual(model.items.map(\.action), [.shuffle, .replay, .bookmark, .settings])
    }

    func testThresholdsImmediatelyBelowAndAtRetainCompression() {
        let cases: [(CGFloat, KeyPath<RailOverflowModel, Bool>)] = [
            (280, \.previousNextHidden), (360, \.skipHidden), (360, \.volumeHidden),
            (390, \.repeatHidden), (430, \.shuffleHidden), (500, \.primaryHidden),
            (540, \.secondaryHidden), (560, \.bookmarkHidden), (640, \.timeHidden)
        ]
        for (threshold, key) in cases {
            XCTAssertTrue(RailOverflowModel(input(width: threshold - 0.01))[keyPath: key], "below \(threshold)")
            XCTAssertFalse(RailOverflowModel(input(width: threshold))[keyPath: key], "at \(threshold)")
        }
    }

    func testSuppressionBelow330AndRestoration() {
        let hidden = RailOverflowModel(input(width: 329.99))
        XCTAssertEqual(hidden.utility, .hidden)
        XCTAssertTrue(hidden.items.isEmpty)
        XCTAssertEqual(RailOverflowModel(input(width: 330)).utility, .more)
        XCTAssertEqual(RailOverflowModel(input()).utility, .settings)
    }

    func testVisibleActionsAreNotDuplicatedAcrossThresholds() {
        for width: CGFloat in [330, 389.99, 390, 429.99, 430, 499.99, 500, 539.99, 540, 559.99, 560, 800] {
            let model = RailOverflowModel(input(width: width))
            let actions = model.items.map(\.action)
            XCTAssertEqual(actions.contains(.customPrefix), model.primaryHidden)
            XCTAssertEqual(actions.contains(.customPrefixSecondary), model.secondaryHidden)
            XCTAssertEqual(actions.contains(.shuffle), model.shuffleHidden)
            XCTAssertEqual(actions.contains(.replay), model.repeatHidden)
            XCTAssertEqual(actions.contains(.bookmark), model.bookmarkHidden)
            if model.utility == .more { XCTAssertEqual(actions.last, .settings) }
        }
    }
}
