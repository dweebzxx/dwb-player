import Foundation
import XCTest

/// Tests for the pure parts of "Advance after prefix" (P145): the transition kind
/// (`MediaFileSupport.prefixTransitionKind`) and the advance decision
/// (`PrefixAdvancePolicy.decide`). No filesystem, AppKit or VLCKit access.
final class PrefixAdvanceTests: XCTestCase {

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    private func kind(file: String, primary: String, secondary: String, invokedPrimary: Bool) -> PrefixTransitionKind? {
        MediaFileSupport.prefixTransitionKind(
            originalURL: url(file),
            primary: primary,
            secondary: secondary,
            invokedPrimary: invokedPrimary
        )
    }

    // MARK: - Registered default

    func testAdvanceAfterPrefixIsRegisteredOffByDefault() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)

        XCTAssertEqual(SettingsDefaultsRegistry.Keys.advanceAfterPrefix, "advanceAfterPrefix")
        XCTAssertEqual(defaults[SettingsDefaultsRegistry.Keys.advanceAfterPrefix] as? Bool, false)
    }

    // MARK: - Transition kind: the six cells

    func testKindNeitherPrefixPrimaryIsAdded() {
        XCTAssertEqual(kind(file: "A.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: true), .added)
    }

    func testKindNeitherPrefixSecondaryIsAdded() {
        XCTAssertEqual(kind(file: "A.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: false), .added)
    }

    func testKindPrimaryPresentPrimaryIsRemoved() {
        XCTAssertEqual(kind(file: "keep_A.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: true), .removed)
    }

    func testKindPrimaryPresentSecondaryIsReplaced() {
        XCTAssertEqual(kind(file: "keep_A.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: false), .replaced)
    }

    func testKindSecondaryPresentPrimaryIsReplaced() {
        XCTAssertEqual(kind(file: "fav_A.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: true), .replaced)
    }

    func testKindSecondaryPresentSecondaryIsRemoved() {
        XCTAssertEqual(kind(file: "fav_A.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: false), .removed)
    }

    // MARK: - Transition kind: no change, empty prefixes

    func testKindEmptyInvokedPrefixIsNil() {
        XCTAssertNil(kind(file: "A.mp4", primary: "", secondary: "fav_", invokedPrimary: true))
        XCTAssertNil(kind(file: "A.mp4", primary: "keep_", secondary: "", invokedPrimary: false))
    }

    func testKindEmptyOtherPrefixNeverMatchesTheName() {
        // The secondary is empty: only the invoked primary can be added or removed.
        XCTAssertEqual(kind(file: "A.mp4", primary: "keep_", secondary: "", invokedPrimary: true), .added)
        XCTAssertEqual(kind(file: "keep_A.mp4", primary: "keep_", secondary: "", invokedPrimary: true), .removed)
    }

    func testKindEqualPrefixesRemoveTheInvokedOne() {
        // Both prefixes are the same string: the invoked one is found first, so it is a removal
        // and the name always changes.
        let transition = MediaFileSupport.calculatePrefixTransition(
            originalURL: url("x_A.mp4"), primary: "x_", secondary: "x_", invokedPrimary: false)
        XCTAssertEqual(transition, "A.mp4")
        XCTAssertEqual(kind(file: "x_A.mp4", primary: "x_", secondary: "x_", invokedPrimary: false), .removed)
    }

    func testKindIgnoresPrefixTextThatIsNotAtTheStartOfTheStem() {
        XCTAssertEqual(kind(file: "A_keep_.mp4", primary: "keep_", secondary: "fav_", invokedPrimary: true), .added)
    }

    func testKindWorksWithoutAnExtension() {
        XCTAssertEqual(kind(file: "keep_song", primary: "keep_", secondary: "fav_", invokedPrimary: false), .replaced)
    }

    // MARK: - Transition kind: one prefix begins with the other

    func testKindOverlappingPrefixesFollowTheTransitionBranchOrder() {
        // primary "keep_" is the start of secondary "keep_fav_". `calculatePrefixTransition`
        // tests the invoked prefix first, then the other one; the kind must do the same.
        let primary = "keep_", secondary = "keep_fav_"

        // Invoked prefix is the longer one: it wins where it matches, else the shorter is replaced.
        XCTAssertEqual(kind(file: "keep_fav_A.mp4", primary: primary, secondary: secondary, invokedPrimary: false), .removed)
        XCTAssertEqual(kind(file: "keep_A.mp4", primary: primary, secondary: secondary, invokedPrimary: false), .replaced)
        XCTAssertEqual(kind(file: "A.mp4", primary: primary, secondary: secondary, invokedPrimary: false), .added)

        // Invoked prefix is the shorter one: "keep_fav_A" also starts with "keep_", and the
        // invoked prefix is tested first, so it is a removal.
        XCTAssertEqual(kind(file: "keep_fav_A.mp4", primary: primary, secondary: secondary, invokedPrimary: true), .removed)
        XCTAssertEqual(kind(file: "keep_A.mp4", primary: primary, secondary: secondary, invokedPrimary: true), .removed)
    }

    // MARK: - Kind and transition cannot disagree

    func testKindAgreesWithCalculatePrefixTransitionForEveryCombination() {
        let configs: [(String, String)] = [
            ("keep_", "fav_"), ("keep_", ""), ("", "fav_"), ("", ""),
            ("keep_", "keep_fav_"), ("keep_fav_", "keep_"), ("x_", "x_")
        ]
        let files = ["A.mp4", "keep_A.mp4", "fav_A.mp4", "keep_fav_A.mp4", "x_A.mp4", "noext", "keep_noext", "A_keep_.mov"]

        for (primary, secondary) in configs {
            for file in files {
                for invokedPrimary in [true, false] {
                    let newName = MediaFileSupport.calculatePrefixTransition(
                        originalURL: url(file), primary: primary, secondary: secondary, invokedPrimary: invokedPrimary)
                    let k = kind(file: file, primary: primary, secondary: secondary, invokedPrimary: invokedPrimary)
                    let label = "file=\(file) primary=\(primary) secondary=\(secondary) invokedPrimary=\(invokedPrimary)"

                    XCTAssertEqual(newName == nil, k == nil, label)
                    guard let newName = newName, let k = k else { continue }

                    let invoked = invokedPrimary ? primary : secondary
                    switch k {
                    case .added:
                        XCTAssertTrue(newName.hasPrefix(invoked), label)
                        XCTAssertEqual(newName.count, file.count + invoked.count, label)
                    case .removed:
                        XCTAssertTrue(file.hasPrefix(invoked), label)
                        XCTAssertEqual(newName.count, file.count - invoked.count, label)
                    case .replaced:
                        XCTAssertTrue(newName.hasPrefix(invoked), label)
                        XCTAssertFalse(file.hasPrefix(invoked), label)
                    }
                }
            }
        }
    }

    // MARK: - Advance decision

    private func decide(
        setting: Bool = true,
        origin: PrefixPressOrigin = .playerControl,
        targets: [Int] = [2],
        current: Int = 2,
        kind: PrefixTransitionKind = .added,
        renamed: Bool = true,
        hasNext: Bool = true
    ) -> PrefixAdvanceDecision {
        PrefixAdvancePolicy.decide(
            settingEnabled: setting,
            origin: origin,
            targetDisplayIndices: targets,
            currentDisplayIndex: current,
            kind: kind,
            renameSucceeded: renamed,
            hasNextItem: hasNext
        )
    }

    func testDecisionSettingOffNeverAdvancesAndNeverLogs() {
        for kind in [PrefixTransitionKind.added, .replaced, .removed] {
            XCTAssertEqual(decide(setting: false, kind: kind), .settingOff)
        }
        XCTAssertEqual(decide(setting: false, origin: .queuePage, targets: [0, 1]), .settingOff)
        XCTAssertEqual(decide(setting: false, renamed: false, hasNext: false), .settingOff)
    }

    func testDecisionAddedOnCurrentItemFromPlayerControlAdvances() {
        XCTAssertEqual(decide(kind: .added), .advance)
    }

    func testDecisionReplacedOnCurrentItemFromPlayerControlAdvances() {
        XCTAssertEqual(decide(kind: .replaced), .advance)
    }

    func testDecisionRemovedStays() {
        XCTAssertEqual(decide(kind: .removed), .skip(.removed))
    }

    func testDecisionQueuePageOriginNeverAdvances() {
        for kind in [PrefixTransitionKind.added, .replaced, .removed] {
            XCTAssertEqual(decide(origin: .queuePage, targets: [2], current: 2, kind: kind), .skip(.queueTarget))
        }
    }

    func testDecisionOtherRowFromPlayerControlDoesNotAdvance() {
        // Queue Page open, a row other than the playing one is selected, rail button pressed.
        XCTAssertEqual(decide(targets: [4], current: 2, kind: .added), .skip(.queueTarget))
    }

    func testDecisionSeveralRowsDoNotAdvanceEvenWhenTheyIncludeTheCurrentItem() {
        XCTAssertEqual(decide(targets: [2, 3], current: 2, kind: .added), .skip(.queueTarget))
        XCTAssertEqual(decide(targets: [1, 2, 3], current: 2, kind: .replaced), .skip(.queueTarget))
    }

    func testDecisionNoTargetsDoNotAdvance() {
        XCTAssertEqual(decide(targets: [], current: 2), .skip(.queueTarget))
    }

    func testDecisionFirstRowCurrentItemAdvances() {
        XCTAssertEqual(decide(targets: [0], current: 0, kind: .added), .advance)
    }

    func testDecisionFailedRenameDoesNotAdvance() {
        XCTAssertEqual(decide(kind: .added, renamed: false), .skip(.renameFailed))
        XCTAssertEqual(decide(kind: .replaced, renamed: false), .skip(.renameFailed))
    }

    func testDecisionLastItemWithNothingAfterItStays() {
        XCTAssertEqual(decide(kind: .added, hasNext: false), .skip(.noNextItem))
        XCTAssertEqual(decide(kind: .replaced, hasNext: false), .skip(.noNextItem))
    }

    func testDecisionRemovalOnLastItemReportsRemoval() {
        XCTAssertEqual(decide(kind: .removed, hasNext: false), .skip(.removed))
    }

    func testDecisionSkipReasonsLogAsTheirRawValues() {
        XCTAssertEqual(PrefixAdvanceSkipReason.removed.rawValue, "removed")
        XCTAssertEqual(PrefixAdvanceSkipReason.queueTarget.rawValue, "queueTarget")
        XCTAssertEqual(PrefixAdvanceSkipReason.noNextItem.rawValue, "noNextItem")
        XCTAssertEqual(PrefixAdvanceSkipReason.renameFailed.rawValue, "renameFailed")
    }
}
