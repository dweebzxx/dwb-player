import AppKit
import XCTest

final class QueuePanelModelsTests: XCTestCase {

    // MARK: Row states

    private func look(current: Bool = false, selected: Bool = false, hover: Bool = false,
                      failed: Bool = false, bookmarked: Bool = false) -> QueueRowAppearance {
        QueueRowAppearance.make(isCurrent: current, isSelected: selected, isHovering: hover,
                                isFailed: failed, isBookmarked: bookmarked)
    }

    func testDefaultRowHasNoFillAndAGridLineEdge() {
        let row = look()
        XCTAssertEqual(row.fill, .none)
        XCTAssertEqual(row.edge, .gridLine)
        XCTAssertFalse(row.showsCurrentBar)
        XCTAssertEqual(row.leadingGlyph, .none)
        XCTAssertEqual(row.filenameWeight, .medium)
    }

    func testCurrentRowUsesAccentTintEdgeBarAndPlayGlyph() {
        let row = look(current: true)
        XCTAssertEqual(row.fill, .accentTint)
        XCTAssertEqual(row.edge, .accentFill)
        XCTAssertTrue(row.showsCurrentBar)
        XCTAssertEqual(row.leadingGlyph, .playing)
        XCTAssertEqual(row.filenameWeight, .semibold)
    }

    func testSelectedRowUsesOverlaySelectedAndBorderStrong() {
        let row = look(selected: true)
        XCTAssertEqual(row.fill, .overlaySelected)
        XCTAssertEqual(row.edge, .borderStrong)
    }

    func testHoverRowUsesOverlayHover() {
        XCTAssertEqual(look(hover: true).fill, .overlayHover)
    }

    func testSelectionWinsOverHover() {
        XCTAssertEqual(look(selected: true, hover: true).fill, .overlaySelected)
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

    // MARK: Geometry

    func testRowMetricsMatchTheDesignSystem() {
        XCTAssertEqual(QueuePanelMetrics.rowHeight, 56)
        XCTAssertEqual(QueuePanelMetrics.rowInset, 4)
        XCTAssertEqual(QueuePanelMetrics.tableRowHeight, 64)
        XCTAssertEqual(QueuePanelMetrics.headerHeight, 52)
        XCTAssertEqual(QueuePanelMetrics.searchPillHeight, 28)
    }

    func testPillRectIsFiftySixPointsTallInsideTheTableRow() {
        let rect = QueuePanelMetrics.pillRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 64))
        XCTAssertEqual(rect.height, 56)
        XCTAssertEqual(rect.minY, 4)
        XCTAssertEqual(rect.minX, 12)
        XCTAssertEqual(rect.maxX, 392)
    }

    func testFooterSpacingMatchesTheSharedFooterSpec() {
        XCTAssertEqual(QueuePanelMetrics.footerHorizontalPadding, 12)
        XCTAssertEqual(QueuePanelMetrics.footerTopPadding, 8)
        XCTAssertEqual(QueuePanelMetrics.footerBottomPadding, 10)
        XCTAssertEqual(QueuePanelMetrics.footerRowSpacing, 6)
        XCTAssertEqual(QueuePanelMetrics.footerRowGap, 8)
        XCTAssertEqual(QueuePanelMetrics.markerGroupHeight, 28)
        XCTAssertEqual(QueuePanelMetrics.markerChipHeight, 22)
    }

    func testGroupOutlineAndEveryHighlightShareThePillRadiusToken() {
        XCTAssertEqual(QueuePanelMetrics.markerGroupCornerRadius, DWBMetrics.radiusPill)
        XCTAssertEqual(QueuePanelMetrics.markerHighlightCornerRadius, QueuePanelMetrics.markerGroupCornerRadius)
        XCTAssertEqual(QueuePanelMetrics.markerHighlightCornerRadius, 12)
    }

    func testFooterHeightFollowsThePlan() {
        let beside = QueueFooterLayoutPlan(usesCompactIcons: false, usesCompactUndo: false, groupWraps: false, totalOnOwnRow: false)
        let ownTotal = QueueFooterLayoutPlan(usesCompactIcons: false, usesCompactUndo: false, groupWraps: false, totalOnOwnRow: true)
        let wrapped = QueueFooterLayoutPlan(usesCompactIcons: true, usesCompactUndo: true, groupWraps: true, totalOnOwnRow: false)
        let wrappedOwnTotal = QueueFooterLayoutPlan(usesCompactIcons: true, usesCompactUndo: true, groupWraps: true, totalOnOwnRow: true)
        // 8 top + 28 marker row + 6 + 26 action row + 10 bottom
        XCTAssertEqual(QueuePanelMetrics.footerHeight(plan: beside), 78)
        XCTAssertEqual(QueuePanelMetrics.footerHeight(plan: ownTotal), 78 + 6 + QueuePanelMetrics.footerTotalRowHeight)
        // Remove row (26) + 6 + group row (28) instead of one 28 pt row.
        XCTAssertEqual(QueuePanelMetrics.footerHeight(plan: wrapped), 78 + 26 + 6)
        XCTAssertEqual(QueuePanelMetrics.footerHeight(plan: wrappedOwnTotal),
                       78 + 26 + 6 + 6 + QueuePanelMetrics.footerTotalRowHeight)
    }

    func testSectionLabelTracksFourPercentOfTenPoints() {
        XCTAssertEqual(QueuePanelMetrics.sectionLabelKern, 0.4, accuracy: 0.0001)
    }

    func testSectionStyleSeparatesCapsLabelsFromEmptyNotes() {
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "PREVIOUS"), .capsLabel)
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "NOW PLAYING"), .capsLabel)
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "UP NEXT"), .capsLabel)
        XCTAssertEqual(QueueSectionLabelStyle.style(forTitle: "No previous"), .emptyNote)
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
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: ""), "—")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "   "), "—")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "\n "), "—")
    }

    func testChipLabelShowsTheNormalizedPrefixUpToEightCharacters() {
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "keep_"), "keep_")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "keep"), "keep_")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "  keep_  "), "keep_")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "\nkeep_\n"), "keep_")
        // Normalized length 8: no ellipsis.
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "abcdefg_"), "abcdefg_")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "abcdefg"), "abcdefg_")
        // Normalized length 9: first eight characters and an ellipsis.
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "abcdefgh"), "abcdefgh…")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "abcdefgh_"), "abcdefgh…")
    }

    func testChipIsDisabledWhenBlankOrWhenTheQueueIsEmpty() {
        XCTAssertFalse(QueueMarkerChipState.isEnabled(prefix: "", queueHasItems: true))
        XCTAssertFalse(QueueMarkerChipState.isEnabled(prefix: "   ", queueHasItems: true))
        XCTAssertFalse(QueueMarkerChipState.isEnabled(prefix: "keep_", queueHasItems: false))
        XCTAssertTrue(QueueMarkerChipState.isEnabled(prefix: "keep_", queueHasItems: true))
        XCTAssertTrue(QueueMarkerChipState.isEnabled(prefix: "keep", queueHasItems: true))
    }

    func testSecondaryChipIsHiddenOnlyWhenItEqualsANonBlankPrimary() {
        XCTAssertFalse(QueueMarkerChipState.secondaryIsShown(primary: "keep_", secondary: "keep_"))
        XCTAssertFalse(QueueMarkerChipState.secondaryIsShown(primary: "keep", secondary: " keep__ "))
        XCTAssertTrue(QueueMarkerChipState.secondaryIsShown(primary: "keep_", secondary: "del_"))
        // Blank secondary stays shown (disabled, "—").
        XCTAssertTrue(QueueMarkerChipState.secondaryIsShown(primary: "keep_", secondary: ""))
        XCTAssertTrue(QueueMarkerChipState.secondaryIsShown(primary: "", secondary: ""))
        XCTAssertTrue(QueueMarkerChipState.secondaryIsShown(primary: "", secondary: "del_"))
        let blank = QueueMarkerChipState.make(kind: .secondary, prefix: "", targetNames: ["a.mp4"], queueHasItems: true)
        XCTAssertEqual(blank.label, "—")
        XCTAssertFalse(blank.isEnabled)
    }

    func testBlankPrefixShowsDashAndIsDisabled() {
        let chip = QueueMarkerChipState.make(kind: .primary, prefix: "   ", targetNames: ["keep_a.mp4"], queueHasItems: true)
        XCTAssertEqual(chip.label, "—")
        XCTAssertTrue(chip.isBlank)
        XCTAssertFalse(chip.isEnabled)
        XCTAssertFalse(chip.isApplied)
    }

    func testChipCopyForTooltipsAndAccessibility() {
        let primary = QueueMarkerChipState.make(kind: .primary, prefix: "keep", targetNames: ["a.mp4"], queueHasItems: true)
        XCTAssertEqual(primary.tooltip, "Primary prefix “keep_”: add it to the selected file, press again to remove it, or replace the secondary prefix. Shortcut: N")
        XCTAssertEqual(primary.accessibilityLabel, "Apply primary prefix keep_ to selected file")
        XCTAssertEqual(primary.accessibilityValue, "not applied")
        let applied = QueueMarkerChipState.make(kind: .secondary, prefix: "del_", targetNames: ["del_a.mp4"], queueHasItems: true)
        XCTAssertEqual(applied.tooltip, "Secondary prefix “del_”: add it to the selected file, press again to remove it, or replace the primary prefix. Shortcut: M")
        XCTAssertEqual(applied.accessibilityLabel, "Apply secondary prefix del_ to selected file")
        XCTAssertEqual(applied.accessibilityValue, "applied")
        let blankPrimary = QueueMarkerChipState.make(kind: .primary, prefix: "", targetNames: [], queueHasItems: true)
        XCTAssertEqual(blankPrimary.tooltip, "No primary prefix set. Set one in Settings > Queue & Files.")
        XCTAssertEqual(blankPrimary.accessibilityLabel, "Primary prefix not set")
        XCTAssertNil(blankPrimary.accessibilityValue)
        let blankSecondary = QueueMarkerChipState.make(kind: .secondary, prefix: " ", targetNames: [], queueHasItems: true)
        XCTAssertEqual(blankSecondary.tooltip, "No secondary prefix set. Set one in Settings > Queue & Files.")
        XCTAssertEqual(blankSecondary.accessibilityLabel, "Secondary prefix not set")
    }

    func testChipIsAppliedOnlyWhenEveryTargetStartsWithThePrefix() {
        XCTAssertTrue(QueueMarkerChipState.isApplied(prefix: "keep_", targetNames: ["keep_a.mp4", "keep_b.mp4"]))
        XCTAssertTrue(QueueMarkerChipState.isApplied(prefix: "keep", targetNames: ["keep_a.mp4"]))
        XCTAssertFalse(QueueMarkerChipState.isApplied(prefix: "keep_", targetNames: ["keep_a.mp4", "b.mp4"]))
        XCTAssertFalse(QueueMarkerChipState.isApplied(prefix: "keep_", targetNames: []))
        XCTAssertFalse(QueueMarkerChipState.isApplied(prefix: "", targetNames: ["a.mp4"]))
    }

    // MARK: Footer responsiveness

    private func plan(width: CGFloat,
                      full: CGFloat = 200,
                      compact: CGFloat = 150,
                      rescan: CGFloat = 70,
                      total: CGFloat = 150,
                      clear: CGFloat = 90) -> QueueFooterLayoutPlan {
        QueueFooterLayoutPlan.make(width: width, removeButtonWidth: 26, fullGroupWidth: full,
                                   compactUndoGroupWidth: compact, rescanWidth: rescan,
                                   totalWidth: total, clearWidth: clear)
    }

    func testFullGroupSitsBesideRemoveWhenItFits() {
        // Full group needs 200 + 26 + 8 gap + 24 padding = 258.
        let p = plan(width: 258)
        XCTAssertFalse(p.usesCompactUndo)
        XCTAssertFalse(p.groupWraps)
    }

    func testUndoShrinksToItsGlyphBeforeAnythingWraps() {
        let p = plan(width: 257)
        XCTAssertTrue(p.usesCompactUndo)
        XCTAssertFalse(p.groupWraps)
        // Compact group needs 150 + 26 + 8 + 24 = 208.
        XCTAssertFalse(plan(width: 208).groupWraps)
        XCTAssertTrue(plan(width: 208).usesCompactUndo)
    }

    func testGroupWrapsToItsOwnRowWithFullUndoWhenThatRowFits() {
        let p = plan(width: 207)
        XCTAssertTrue(p.groupWraps)
        // The row holds 207 - 24 = 183 pt, which fits the compact group but not the full one.
        XCTAssertTrue(p.usesCompactUndo)
        let roomy = plan(width: 207, full: 180, compact: 150)
        XCTAssertTrue(roomy.groupWraps)
        XCTAssertFalse(roomy.usesCompactUndo)
        // Full group exactly fills the wrapped row: still full Undo.
        XCTAssertFalse(plan(width: 207, full: 183, compact: 170).usesCompactUndo)
        XCTAssertTrue(plan(width: 207, full: 184, compact: 170).usesCompactUndo)
    }

    func testNothingEverMovesIntoAMenu() {
        let p = plan(width: 120)
        XCTAssertTrue(p.groupWraps)
        XCTAssertTrue(p.usesCompactUndo)
    }

    func testTotalLabelTakesItsOwnRowWhenItDoesNotFitInline() {
        // 70 + 150 + 1 + 90 + 3 gaps of 8 = 335, plus 24 padding = 359.
        XCTAssertFalse(plan(width: 359).totalOnOwnRow)
        XCTAssertTrue(plan(width: 358).totalOnOwnRow)
    }

    func testCompactIconsKeepTheOldThreeHundredNinetyRule() {
        XCTAssertTrue(QueueFooterLayoutPlan.usesCompactIcons(width: 389))
        XCTAssertFalse(QueueFooterLayoutPlan.usesCompactIcons(width: 390))
        XCTAssertTrue(plan(width: 389).usesCompactIcons)
        XCTAssertFalse(plan(width: 390).usesCompactIcons)
    }

    // MARK: Total label

    func testTotalTextCountsItems() {
        XCTAssertEqual(QueueFooterText.total(duration: "00:00:00", itemCount: 0, visibleCount: 0, isFiltered: false),
                       "Total: 00:00:00 | 0 items")
        XCTAssertEqual(QueueFooterText.total(duration: "00:03:20", itemCount: 1, visibleCount: 1, isFiltered: false),
                       "Total: 00:03:20 | 1 item")
        XCTAssertEqual(QueueFooterText.total(duration: "01:02:03", itemCount: 12, visibleCount: 12, isFiltered: false),
                       "Total: 01:02:03 | 12 items")
    }

    func testTotalTextShowsVisibleOverTotalWhileFiltering() {
        XCTAssertEqual(QueueFooterText.total(duration: "01:02:03", itemCount: 12, visibleCount: 3, isFiltered: true),
                       "Total: 01:02:03 | 3/12 shown")
        XCTAssertEqual(QueueFooterText.total(duration: "00:00:00", itemCount: 12, visibleCount: 0, isFiltered: true),
                       "Total: 00:00:00 | 0/12 shown")
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

    func testEveryPrefixKeyReturnsNilWithModifiersOrWhileEditingText() {
        for key in ["n", "m", "r"] {
            XCTAssertNotNil(PrefixKeyRouting.action(forCharacters: key, hasModifiers: false, isEditingText: false))
            XCTAssertNil(PrefixKeyRouting.action(forCharacters: key, hasModifiers: true, isEditingText: false))
            XCTAssertNil(PrefixKeyRouting.action(forCharacters: key, hasModifiers: false, isEditingText: true))
        }
    }

    func testPlainNMAndRMapToTheirActions() {
        XCTAssertEqual(PrefixKeyRouting.action(forCharacters: "n", hasModifiers: false, isEditingText: false), .primaryPrefix)
        XCTAssertEqual(PrefixKeyRouting.action(forCharacters: "m", hasModifiers: false, isEditingText: false), .secondaryPrefix)
        XCTAssertEqual(PrefixKeyRouting.action(forCharacters: "r", hasModifiers: false, isEditingText: false), .rename)
        XCTAssertNil(PrefixKeyRouting.action(forCharacters: "b", hasModifiers: false, isEditingText: false))
        XCTAssertNil(PrefixKeyRouting.action(forCharacters: nil, hasModifiers: false, isEditingText: false))
    }

    func testPrefixKeysNeverFireWithModifiersOrWhileEditingText() {
        XCTAssertNil(PrefixKeyRouting.action(forCharacters: "n", hasModifiers: true, isEditingText: false))
        XCTAssertNil(PrefixKeyRouting.action(forCharacters: "r", hasModifiers: false, isEditingText: true))
    }

    func testRenameKeyUsesTheSelectedRowOnlyWhenExactlyOneIsSelected() {
        XCTAssertEqual(PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: [4]), 4)
        XCTAssertNil(PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: []))
        XCTAssertNil(PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: [1, 2]))
    }
}
