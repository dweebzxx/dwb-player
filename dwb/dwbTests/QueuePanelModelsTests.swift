import AppKit
import XCTest

final class QueuePanelModelsTests: XCTestCase {

    // MARK: Row states

    private func look(current: Bool = false, selected: Bool = false, hover: Bool = false,
                      failed: Bool = false, bookmarked: Bool = false,
                      nextSelected: Bool = false) -> QueueRowAppearance {
        QueueRowAppearance.make(isCurrent: current, isSelected: selected, isHovering: hover,
                                isFailed: failed, isBookmarked: bookmarked, isNextRowSelected: nextSelected)
    }

    func testFlatRowAtRestHasNoFillNoEdgeAndASeparator() {
        let row = look()
        XCTAssertEqual(row.fill, .none)
        XCTAssertEqual(row.edge, .none)
        XCTAssertTrue(row.showsSeparator)
        XCTAssertFalse(row.showsCurrentBar)
        XCTAssertEqual(row.leadingGlyph, .none)
        XCTAssertEqual(row.filenameWeight, .medium)
    }

    func testPlayingCardUsesUniformAccentTintStrongAQuietEdgeAndTheBar() {
        let row = look(current: true)
        XCTAssertEqual(row.fill, .accentTintStrong)
        XCTAssertEqual(row.edge, .quiet)
        XCTAssertEqual(row.edge.lineWidth, 0.5)
        XCTAssertTrue(row.showsCurrentBar)
        XCTAssertFalse(row.showsSeparator)
        XCTAssertEqual(row.leadingGlyph, .playing)
        XCTAssertEqual(row.filenameWeight, .semibold)
    }

    func testPlayingCardEdgeBecomesBorderStrongOnHoverAndOneWholePointWhenSelected() {
        XCTAssertEqual(look(current: true, hover: true).edge, .borderStrongHairline)
        XCTAssertEqual(look(current: true, hover: true).edge.lineWidth, 0.5)
        let selected = look(current: true, selected: true, hover: true)
        XCTAssertEqual(selected.edge, .borderStrong)
        XCTAssertEqual(selected.edge.lineWidth, 1)
        // The card keeps its fill; selection adds the edge, it does not swap the fill.
        XCTAssertEqual(selected.fill, .accentTintStrong)
    }

    func testSelectedFlatRowUsesOverlaySelectedAndAOnePointBorderStrongEdge() {
        let row = look(selected: true)
        XCTAssertEqual(row.fill, .overlaySelected)
        XCTAssertEqual(row.edge, .borderStrong)
        XCTAssertEqual(row.edge.lineWidth, 1)
    }

    func testHoverRowUsesOverlayHoverAndNoEdge() {
        XCTAssertEqual(look(hover: true).fill, .overlayHover)
        XCTAssertEqual(look(hover: true).edge, .none)
    }

    func testSelectionWinsOverHover() {
        XCTAssertEqual(look(selected: true, hover: true).fill, .overlaySelected)
    }

    func testSeparatorIsHiddenOnASelectedRowAndAboveOneAndOnThePlayingCard() {
        XCTAssertTrue(look().showsSeparator)
        XCTAssertFalse(look(selected: true).showsSeparator)
        XCTAssertFalse(look(selected: true, hover: true).showsSeparator)
        XCTAssertFalse(look(nextSelected: true).showsSeparator)
        XCTAssertFalse(look(current: true).showsSeparator)
        // Hover alone does not hide it.
        XCTAssertTrue(look(hover: true).showsSeparator)
    }

    func testFailedRowShowsWarningGlyphAndErrorMetadata() {
        let row = look(failed: true)
        XCTAssertEqual(row.leadingGlyph, .failed)
        XCTAssertTrue(row.metadataIsError)
        XCTAssertTrue(row.filenameIsDimmed)
    }

    func testCurrentGlyphWinsOverFailedGlyphButMetadataStaysError() {
        let row = look(current: true, failed: true)
        XCTAssertEqual(row.leadingGlyph, .playing)
        XCTAssertTrue(row.metadataIsError)
    }

    func testBookmarkedRowShowsBookmarkGlyph() {
        XCTAssertTrue(look(bookmarked: true).showsBookmark)
        XCTAssertFalse(look().showsBookmark)
    }

    // MARK: Sections and header metrics

    func testHeaderIsFiftyTwoPointsAndTheSectionKernBelongsToSettingsCaptions() {
        XCTAssertEqual(QueuePanelMetrics.headerHeight, 52)
        XCTAssertEqual(QueuePanelMetrics.sectionLabelKern, 0.4, accuracy: 0.0001)
    }

    func testSectionStyleSeparatesLabelsFromNotes() {
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "PREVIOUS"), .label)
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "NOW PLAYING"), .label)
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "UP NEXT"), .label)
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "No previous"), .note)
    }

    func testSectionLabelsAreShownInSentenceCaseAndNotesAreUntouched() {
        XCTAssertEqual(QueueSectionLabelStyle.displayText(forTitle: "PREVIOUS"), "Previous")
        XCTAssertEqual(QueueSectionLabelStyle.displayText(forTitle: "NOW PLAYING"), "Now playing")
        XCTAssertEqual(QueueSectionLabelStyle.displayText(forTitle: "UP NEXT"), "Up next")
        XCTAssertEqual(QueueSectionLabelStyle.displayText(forTitle: "No previous"), "No previous")
    }

    // MARK: Prefix normalization

    func testNormalizedPrefixRule() {
        XCTAssertEqual(PrefixNormalization.normalized(""), "")
        XCTAssertEqual(PrefixNormalization.normalized("   "), "")
        XCTAssertEqual(PrefixNormalization.normalized("\n\t "), "")
        XCTAssertEqual(PrefixNormalization.normalized("keep"), "keep_")
        XCTAssertEqual(PrefixNormalization.normalized("keep_"), "keep_")
        XCTAssertEqual(PrefixNormalization.normalized("keep__"), "keep_")
        XCTAssertEqual(PrefixNormalization.normalized(" keep "), "keep_")
        XCTAssertEqual(PrefixNormalization.normalized("_"), "_")
        XCTAssertEqual(PrefixNormalization.normalized("__"), "_")
        XCTAssertEqual(PrefixNormalization.normalized("😀fun"), "😀fun_")
        XCTAssertEqual(PrefixNormalization.normalized("日本"), "日本_")
        XCTAssertEqual(PrefixNormalization.normalized("日本_"), "日本_")
    }

    func testNormalizedPrefixIsIdempotent() {
        for raw in ["", "  ", "keep", "keep_", "keep__", " keep ", "_", "__", "😀", "日本__"] {
            let once = PrefixNormalization.normalized(raw)
            XCTAssertEqual(PrefixNormalization.normalized(once), once, "raw: \(raw)")
        }
    }

    // MARK: Marker chips

    func testChipLabelShowsDashWhenBlank() {
        XCTAssertEqual(QueueMarkerState.label(forPrefix: ""), "—")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "   "), "—")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "\n "), "—")
    }

    func testChipLabelShowsTheNormalizedPrefixUpToEightCharacters() {
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "keep_"), "keep_")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "keep"), "keep_")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "  keep_  "), "keep_")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "\nkeep_\n"), "keep_")
        // Normalized length 8: no ellipsis.
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "abcdefg_"), "abcdefg_")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "abcdefg"), "abcdefg_")
        // Normalized length 9: first eight characters and an ellipsis.
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "abcdefgh"), "abcdefgh…")
        XCTAssertEqual(QueueMarkerState.label(forPrefix: "abcdefgh_"), "abcdefgh…")
    }

    func testChipIsDisabledWhenBlankOrWhenTheQueueIsEmpty() {
        XCTAssertFalse(QueueMarkerState.isEnabled(prefix: "", queueHasItems: true))
        XCTAssertFalse(QueueMarkerState.isEnabled(prefix: "   ", queueHasItems: true))
        XCTAssertFalse(QueueMarkerState.isEnabled(prefix: "keep_", queueHasItems: false))
        XCTAssertTrue(QueueMarkerState.isEnabled(prefix: "keep_", queueHasItems: true))
        XCTAssertTrue(QueueMarkerState.isEnabled(prefix: "keep", queueHasItems: true))
    }

    func testSecondaryChipIsHiddenOnlyWhenItEqualsANonBlankPrimary() {
        XCTAssertFalse(QueueMarkerState.secondaryIsShown(primary: "keep_", secondary: "keep_"))
        XCTAssertFalse(QueueMarkerState.secondaryIsShown(primary: "keep", secondary: " keep__ "))
        XCTAssertTrue(QueueMarkerState.secondaryIsShown(primary: "keep_", secondary: "del_"))
        // Blank secondary stays shown (disabled, "—").
        XCTAssertTrue(QueueMarkerState.secondaryIsShown(primary: "keep_", secondary: ""))
        XCTAssertTrue(QueueMarkerState.secondaryIsShown(primary: "", secondary: ""))
        XCTAssertTrue(QueueMarkerState.secondaryIsShown(primary: "", secondary: "del_"))
        let blank = QueueMarkerState.make(kind: .secondary, prefix: "", targetNames: ["a.mp4"], queueHasItems: true)
        XCTAssertEqual(blank.label, "—")
        XCTAssertFalse(blank.isEnabled)
    }

    func testBlankPrefixShowsDashAndIsDisabled() {
        let chip = QueueMarkerState.make(kind: .primary, prefix: "   ", targetNames: ["keep_a.mp4"], queueHasItems: true)
        XCTAssertEqual(chip.label, "—")
        XCTAssertTrue(chip.isBlank)
        XCTAssertFalse(chip.isEnabled)
        XCTAssertFalse(chip.isApplied)
    }

    func testChipCopyForTooltipsAndAccessibility() {
        let primary = QueueMarkerState.make(kind: .primary, prefix: "keep", targetNames: ["a.mp4"], queueHasItems: true)
        XCTAssertEqual(primary.tooltip, "Primary prefix “keep_”: add it to the selected file, press again to remove it, or replace the secondary prefix. Shortcut: N")
        XCTAssertEqual(primary.accessibilityLabel, "Apply primary prefix keep_ to selected file")
        XCTAssertEqual(primary.accessibilityValue, "not applied")
        let applied = QueueMarkerState.make(kind: .secondary, prefix: "del_", targetNames: ["del_a.mp4"], queueHasItems: true)
        XCTAssertEqual(applied.tooltip, "Secondary prefix “del_”: add it to the selected file, press again to remove it, or replace the primary prefix. Shortcut: M")
        XCTAssertEqual(applied.accessibilityLabel, "Apply secondary prefix del_ to selected file")
        XCTAssertEqual(applied.accessibilityValue, "applied")
        let blankPrimary = QueueMarkerState.make(kind: .primary, prefix: "", targetNames: [], queueHasItems: true)
        XCTAssertEqual(blankPrimary.tooltip, "No primary prefix set. Set one in Settings > Queue & Files.")
        XCTAssertEqual(blankPrimary.accessibilityLabel, "Primary prefix not set")
        XCTAssertNil(blankPrimary.accessibilityValue)
        let blankSecondary = QueueMarkerState.make(kind: .secondary, prefix: " ", targetNames: [], queueHasItems: true)
        XCTAssertEqual(blankSecondary.tooltip, "No secondary prefix set. Set one in Settings > Queue & Files.")
        XCTAssertEqual(blankSecondary.accessibilityLabel, "Secondary prefix not set")
    }

    func testChipIsAppliedOnlyWhenEveryTargetStartsWithThePrefix() {
        XCTAssertTrue(QueueMarkerState.isApplied(prefix: "keep_", targetNames: ["keep_a.mp4", "keep_b.mp4"]))
        XCTAssertTrue(QueueMarkerState.isApplied(prefix: "keep", targetNames: ["keep_a.mp4"]))
        XCTAssertFalse(QueueMarkerState.isApplied(prefix: "keep_", targetNames: ["keep_a.mp4", "b.mp4"]))
        XCTAssertFalse(QueueMarkerState.isApplied(prefix: "keep_", targetNames: []))
        XCTAssertFalse(QueueMarkerState.isApplied(prefix: "", targetNames: ["a.mp4"]))
    }

    // MARK: Applied, mixed and none (§10.5)

    private func state(_ prefix: String, _ names: [String], hasItems: Bool = true) -> QueueMarkerState {
        QueueMarkerState.make(kind: .primary, prefix: prefix, targetNames: names, queueHasItems: hasItems)
    }

    func testMarkIsAppliedWhenEveryTargetHasThePrefix() {
        let s = state("keep_", ["keep_a.mp4", "keep_b.mp4"])
        XCTAssertEqual(s.mark, .applied)
        XCTAssertTrue(s.isApplied)
        XCTAssertFalse(s.isMixed)
        XCTAssertEqual(s.accessibilityValue, "applied")
    }

    func testMarkIsMixedWhenOnlySomeTargetsHaveThePrefix() {
        let s = state("keep_", ["keep_a.mp4", "b.mp4", "c.mp4"])
        XCTAssertEqual(s.mark, .mixed)
        XCTAssertFalse(s.isApplied)
        XCTAssertTrue(s.isMixed)
        XCTAssertEqual(s.accessibilityValue, "mixed, some selected files have it")
    }

    func testMarkIsNoneWhenNoTargetHasThePrefix() {
        let s = state("keep_", ["a.mp4", "b.mp4"])
        XCTAssertEqual(s.mark, .none)
        XCTAssertEqual(s.accessibilityValue, "not applied")
    }

    func testBlankPrefixHasNoMarkAndNoAccessibilityValue() {
        let s = state("  ", ["keep_a.mp4"])
        XCTAssertEqual(s.mark, .none)
        XCTAssertNil(s.accessibilityValue)
        XCTAssertFalse(s.isEnabled)
    }

    func testNothingTargetedDisablesTheSectionAndShowsNoMark() {
        let s = state("keep_", [])
        XCTAssertEqual(s.mark, .none)
        XCTAssertFalse(s.isEnabled)
        // An empty queue disables it too, even with a stale target list.
        XCTAssertFalse(state("keep_", ["keep_a.mp4"], hasItems: false).isEnabled)
        XCTAssertTrue(state("keep_", ["a.mp4"]).isEnabled)
    }

    func testMixedUsesTheNormalizedPrefix() {
        XCTAssertTrue(QueueMarkerState.isMixed(prefix: "keep", targetNames: ["keep_a.mp4", "x.mp4"]))
        XCTAssertFalse(QueueMarkerState.isMixed(prefix: "keep", targetNames: ["keep_a.mp4"]))
        XCTAssertFalse(QueueMarkerState.isMixed(prefix: "", targetNames: ["keep_a.mp4", "x.mp4"]))
        XCTAssertFalse(QueueMarkerState.isMixed(prefix: "keep", targetNames: []))
    }

    // MARK: Rail prefix buttons

    func testRailLabelIsTheFirstCharacterOfTheNormalizedPrefixPlusUnderscore() {
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: "keep_"), "k_")
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: "keep"), "k_")
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: "  Delete_"), "D_")
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: "😀fun"), "😀_")
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: "日本"), "日_")
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: ""), "")
        XCTAssertEqual(RailPrefixButtons.label(forPrefix: "   "), "")
    }

    func testRailButtonsHideForBlankDuplicateOrWhenTheSettingIsOff() {
        XCTAssertTrue(RailPrefixButtons.showsPrimary(primary: "keep_", prefixButtonsEnabled: true))
        XCTAssertFalse(RailPrefixButtons.showsPrimary(primary: "  ", prefixButtonsEnabled: true))
        XCTAssertFalse(RailPrefixButtons.showsPrimary(primary: "keep_", prefixButtonsEnabled: false))
        XCTAssertTrue(RailPrefixButtons.showsSecondary(primary: "keep_", secondary: "del_", prefixButtonsEnabled: true))
        XCTAssertFalse(RailPrefixButtons.showsSecondary(primary: "keep_", secondary: "", prefixButtonsEnabled: true))
        XCTAssertFalse(RailPrefixButtons.showsSecondary(primary: "keep_", secondary: "keep", prefixButtonsEnabled: true))
        XCTAssertFalse(RailPrefixButtons.showsSecondary(primary: "keep_", secondary: "del_", prefixButtonsEnabled: false))
    }

    func testMoreMenuListsAPrefixOnlyWhenTheSettingIsOnAndTheRailButtonIsHidden() {
        func shows(_ slot: RailPrefixButtons.Slot, primary: String = "keep_", secondary: String = "del_",
                   enabled: Bool, hidden: Bool) -> Bool {
            RailPrefixButtons.showsInMoreMenu(slot, primary: primary, secondary: secondary,
                                              prefixButtonsEnabled: enabled, buttonIsHidden: hidden)
        }
        for slot in [RailPrefixButtons.Slot.primary, .secondary] {
            XCTAssertTrue(shows(slot, enabled: true, hidden: true))
            XCTAssertFalse(shows(slot, enabled: true, hidden: false))
            XCTAssertFalse(shows(slot, enabled: false, hidden: true))
            XCTAssertFalse(shows(slot, enabled: false, hidden: false))
        }
    }

    func testMoreMenuOmitsABlankPrimaryAndASecondaryThatMatchesTheFirst() {
        XCTAssertFalse(RailPrefixButtons.showsInMoreMenu(.primary, primary: "  ", secondary: "del_",
                                                         prefixButtonsEnabled: true, buttonIsHidden: true))
        XCTAssertFalse(RailPrefixButtons.showsInMoreMenu(.secondary, primary: "keep_", secondary: "keep",
                                                         prefixButtonsEnabled: true, buttonIsHidden: true))
        XCTAssertFalse(RailPrefixButtons.showsInMoreMenu(.secondary, primary: "keep_", secondary: "",
                                                         prefixButtonsEnabled: true, buttonIsHidden: true))
    }

    // MARK: Prefix keys

    func testEveryPrefixCommandReturnsNilWhileEditingText() {
        for command in [ShortcutCommandID.togglePrimaryPrefix, .toggleSecondaryPrefix, .renameFile] {
            XCTAssertNotNil(PrefixKeyRouting.action(for: command, isEditingText: false))
            XCTAssertNil(PrefixKeyRouting.action(for: command, isEditingText: true))
        }
    }

    func testPrefixAndRenameCommandsMapToTheirActions() {
        XCTAssertEqual(PrefixKeyRouting.action(for: .togglePrimaryPrefix, isEditingText: false), .primaryPrefix)
        XCTAssertEqual(PrefixKeyRouting.action(for: .toggleSecondaryPrefix, isEditingText: false), .secondaryPrefix)
        XCTAssertEqual(PrefixKeyRouting.action(for: .renameFile, isEditingText: false), .rename)
        XCTAssertNil(PrefixKeyRouting.action(for: .toggleBookmark, isEditingText: false))
        XCTAssertNil(PrefixKeyRouting.action(for: nil, isEditingText: false))
    }

    func testThePlainDefaultKeysReachThePrefixCommandsAndModifiedKeysDoNot() {
        let bindings = ShortcutBindings()
        for surface in [ShortcutSurface.video, .image, .queueTable] {
            XCTAssertEqual(bindings.pageCommand(for: .character("n"), surface: surface), .togglePrimaryPrefix)
            XCTAssertEqual(bindings.pageCommand(for: .character("m"), surface: surface), .toggleSecondaryPrefix)
            XCTAssertEqual(bindings.pageCommand(for: .character("r"), surface: surface), .renameFile)
            XCTAssertNil(bindings.pageCommand(for: .character("n", .command), surface: surface))
            XCTAssertNil(bindings.pageCommand(for: .character("r", .shift), surface: surface))
        }
    }

    func testRenameKeyUsesTheSelectedRowOnlyWhenExactlyOneIsSelected() {
        XCTAssertEqual(PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: [4]), 4)
        XCTAssertNil(PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: []))
        XCTAssertNil(PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: [1, 2]))
    }
}
