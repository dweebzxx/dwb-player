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

    func testFooterHeightIsTwoRowsWithMarkersAndOneRowWithout() {
        XCTAssertEqual(QueuePanelMetrics.footerHeight(showsMarkerRow: true), 80)
        XCTAssertEqual(QueuePanelMetrics.footerHeight(showsMarkerRow: false), 44)
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

    // MARK: Marker chips

    func testChipLabelTrimsAndCapsAtEightCharacters() {
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "keep_"), "keep_")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "  keep_  "), "keep_")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "abcdefgh"), "abcdefgh")
        XCTAssertEqual(QueueMarkerChipState.label(forPrefix: "abcdefghi"), "abcdefgh…")
    }

    func testBlankPrefixShowsDashAndIsDisabled() {
        let chip = QueueMarkerChipState.make(kind: .primary, prefix: "   ", targetNames: ["keep_a.mp4"])
        XCTAssertEqual(chip.label, "—")
        XCTAssertTrue(chip.isBlank)
        XCTAssertFalse(chip.isEnabled)
        XCTAssertFalse(chip.isApplied)
    }

    func testChipKeyTagIsNForPrimaryAndMForSecondary() {
        XCTAssertEqual(QueueMarkerChipState.make(kind: .primary, prefix: "a_", targetNames: []).keyTag, "N")
        XCTAssertEqual(QueueMarkerChipState.make(kind: .secondary, prefix: "b_", targetNames: []).keyTag, "M")
    }

    func testChipIsAppliedOnlyWhenEveryTargetStartsWithThePrefix() {
        XCTAssertTrue(QueueMarkerChipState.isApplied(prefix: "keep_", targetNames: ["keep_a.mp4", "keep_b.mp4"]))
        XCTAssertFalse(QueueMarkerChipState.isApplied(prefix: "keep_", targetNames: ["keep_a.mp4", "b.mp4"]))
        XCTAssertFalse(QueueMarkerChipState.isApplied(prefix: "keep_", targetNames: []))
        XCTAssertFalse(QueueMarkerChipState.isApplied(prefix: "", targetNames: ["a.mp4"]))
    }

    // MARK: Footer responsiveness

    func testFullGroupShowsWhenItFits() {
        let plan = QueueFooterLayoutPlan.make(width: 480, hasPrefixActions: true, removeButtonWidth: 26,
                                              fullGroupWidth: 280, compactUndoGroupWidth: 220)
        XCTAssertFalse(plan.usesCompactUndo)
        XCTAssertFalse(plan.usesPrefixOverflow)
        XCTAssertFalse(plan.usesCompactIcons)
    }

    func testUndoShrinksToItsGlyphBeforeAnythingMoves() {
        let plan = QueueFooterLayoutPlan.make(width: 330, hasPrefixActions: true, removeButtonWidth: 26,
                                              fullGroupWidth: 280, compactUndoGroupWidth: 220)
        XCTAssertTrue(plan.usesCompactUndo)
        XCTAssertFalse(plan.usesPrefixOverflow)
    }

    func testPrefixActionsMoveToMoreWhenEvenTheCompactGroupDoesNotFit() {
        let plan = QueueFooterLayoutPlan.make(width: 260, hasPrefixActions: true, removeButtonWidth: 26,
                                              fullGroupWidth: 280, compactUndoGroupWidth: 220)
        XCTAssertTrue(plan.usesCompactUndo)
        XCTAssertTrue(plan.usesPrefixOverflow)
        XCTAssertTrue(plan.usesCompactIcons)
    }

    func testNoOverflowWithoutPrefixActions() {
        let plan = QueueFooterLayoutPlan.make(width: 260, hasPrefixActions: false, removeButtonWidth: 26,
                                              fullGroupWidth: 280, compactUndoGroupWidth: 220)
        XCTAssertFalse(plan.usesPrefixOverflow)
    }

    func testCompactIconsKeepTheOldThreeHundredNinetyRule() {
        XCTAssertTrue(QueueFooterLayoutPlan.make(width: 389, hasPrefixActions: false, removeButtonWidth: 26,
                                                 fullGroupWidth: 10, compactUndoGroupWidth: 10).usesCompactIcons)
        XCTAssertFalse(QueueFooterLayoutPlan.make(width: 390, hasPrefixActions: false, removeButtonWidth: 26,
                                                  fullGroupWidth: 10, compactUndoGroupWidth: 10).usesCompactIcons)
    }
}

final class DWBContrastTests: XCTestCase {
    func testBorderBecomesBorderStrong() {
        XCTAssertEqual(DWBContrast.border(false), DWBColor.border)
        XCTAssertEqual(DWBContrast.border(true), DWBColor.borderStrong)
    }

    func testSecondaryAndTertiaryTextStepUp() {
        XCTAssertEqual(DWBContrast.textSecondary(false), DWBColor.textSecondary)
        XCTAssertEqual(DWBContrast.textSecondary(true), DWBColor.textPrimary)
        XCTAssertEqual(DWBContrast.textTertiary(false), DWBColor.textTertiary)
        XCTAssertEqual(DWBContrast.textTertiary(true), DWBColor.textSecondary)
    }

    func testAccentTintGoesFromEighteenToTwentyEightPercent() {
        XCTAssertEqual(DWBContrast.accentTintAlpha(false), 0.18, accuracy: 0.0001)
        XCTAssertEqual(DWBContrast.accentTintAlpha(true), 0.28, accuracy: 0.0001)
        XCTAssertEqual(DWBContrast.accentTint(.player, true).alphaComponent, 0.28, accuracy: 0.0001)
    }

    func testTranslucentBackingsBecomeOpaque() {
        XCTAssertEqual(DWBContrast.opaque(DWBColor.backingHUD, true).alphaComponent, 1, accuracy: 0.0001)
        XCTAssertEqual(DWBContrast.opaque(DWBColor.backingHUD, false).alphaComponent, 0.92, accuracy: 0.0001)
    }

    func testFocusRingIsThreePointsInAccentTextUnderIncreaseContrast() {
        XCTAssertEqual(DWBContrast.focusRingWidth(true), 3)
        XCTAssertEqual(DWBContrast.focusRingWidth(false), 2)
        XCTAssertEqual(DWBContrast.focusRingColor(.player, true), DWBTheme.player.accentText)
        XCTAssertEqual(DWBContrast.focusRingColor(.player, false), DWBTheme.player.accentFill)
    }

    func testReduceMotionMakesFadesInstant() {
        XCTAssertEqual(DWBMotion.duration(0.18, reduceMotion: true), 0)
        XCTAssertEqual(DWBMotion.duration(0.18, reduceMotion: false), 0.18)
    }
}

final class QueueInteractionModelsTests: XCTestCase {

    // MARK: Search highlight

    func testHighlightIsTheFirstCaseInsensitiveMatch() {
        let range = QueueSearchHighlight.firstMatch(in: "Banana band.mp4", query: "an")
        XCTAssertEqual(range, NSRange(location: 1, length: 2))
        XCTAssertEqual(QueueSearchHighlight.firstMatch(in: "Banana band.mp4", query: "BAN"),
                       NSRange(location: 0, length: 3))
    }

    func testHighlightIgnoresAccentsLikeTheFilter() {
        let range = QueueSearchHighlight.firstMatch(in: "Café noir.mp4", query: "cafe")
        XCTAssertEqual(range, NSRange(location: 0, length: 4))
    }

    func testHighlightTrimsTheQueryAndNeedsAMatch() {
        XCTAssertEqual(QueueSearchHighlight.firstMatch(in: "clip.mp4", query: "  lip "), NSRange(location: 1, length: 3))
        XCTAssertNil(QueueSearchHighlight.firstMatch(in: "clip.mp4", query: "zzz"))
        XCTAssertNil(QueueSearchHighlight.firstMatch(in: "clip.mp4", query: ""))
        XCTAssertNil(QueueSearchHighlight.firstMatch(in: "clip.mp4", query: "   "))
    }

    func testHighlightRangeIsInUTF16UnitsForAttributedStrings() {
        let range = QueueSearchHighlight.firstMatch(in: "😀 clip.mp4", query: "clip")
        XCTAssertEqual(range, NSRange(location: 3, length: 4))
    }

    // MARK: Filtered empty states

    func testSearchQueryReadsAsNoMatchingFiles() {
        let state = QueueFilteredEmptyState.make(query: "zzz", bookmarkFilterEnabled: false)
        XCTAssertEqual(state, .noMatches)
        XCTAssertEqual(state.title, "No matching files")
        XCTAssertEqual(state.actionTitle, "Clear Search")
        XCTAssertEqual(state.symbolName, "magnifyingglass")
    }

    func testBookmarkFilterAloneReadsAsNoBookmarkedMedia() {
        let state = QueueFilteredEmptyState.make(query: "", bookmarkFilterEnabled: true)
        XCTAssertEqual(state, .noBookmarks)
        XCTAssertEqual(state.title, "No bookmarked media")
        XCTAssertEqual(state.actionTitle, "Show All Media")
        XCTAssertEqual(state.symbolName, "bookmark.slash")
    }

    func testSearchWinsWhenBothFiltersAreOn() {
        XCTAssertEqual(QueueFilteredEmptyState.make(query: "zzz", bookmarkFilterEnabled: true), .noMatches)
        XCTAssertEqual(QueueFilteredEmptyState.make(query: "   ", bookmarkFilterEnabled: true), .noBookmarks)
    }

    func testFilteredEmptyStateUsesA44PointCircleAndA18PointGlyph() {
        XCTAssertEqual(QueueFilteredEmptyState.circleDiameter, 44)
        XCTAssertEqual(QueueFilteredEmptyState.glyphSize, 18)
    }

    // MARK: Drop line

    func testDropLineIsATwoPointLineWithAnEightPointRingAtItsLeadingEnd() {
        XCTAssertEqual(QueueDropIndicatorMetrics.lineHeight, 2)
        XCTAssertEqual(QueueDropIndicatorMetrics.ringDiameter, 8)
        XCTAssertEqual(QueueDropIndicatorMetrics.ringBorder, 2)
        XCTAssertEqual(QueueDropIndicatorMetrics.sideInset, 4)
        XCTAssertEqual(QueueDropIndicatorMetrics.draggedRowAlpha, 0.4)

        let geometry = QueueDropIndicatorMetrics.geometry(width: 200)
        XCTAssertEqual(geometry.ring, NSRect(x: 0, y: 0, width: 8, height: 8))
        XCTAssertEqual(geometry.line.height, 2)
        // Vertically centered on the ring, so the line sits in the middle of the row gap.
        XCTAssertEqual(geometry.line.midY, geometry.ring.midY)
        // The line starts 1 pt inside the ring and ends at the trailing edge.
        XCTAssertEqual(geometry.line.minX, 7)
        XCTAssertEqual(geometry.line.maxX, 200)
    }

    func testDropLineNeverGoesNegativeInANarrowView() {
        XCTAssertEqual(QueueDropIndicatorMetrics.geometry(width: 3).line.width, 0)
    }

    // MARK: Play Next tag

    func testPlayNextTagMetricsMatchTheSpec() {
        XCTAssertEqual(DWBMetrics.playNextTag, 16)
        XCTAssertEqual(QueuePanelMetrics.titleTagGap, 6)
    }
}
