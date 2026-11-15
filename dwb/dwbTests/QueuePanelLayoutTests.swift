import AppKit
import XCTest

/// Geometry and text rules for the active Queue Page look (`tokens-and-specs.md` §10). These are
/// pure or view-level checks of frames and measured text; none of them is a rendered-appearance
/// check, which stays a manual review.
final class QueuePanelLayoutTests: XCTestCase {

    private let widths: [CGFloat] = [200, 270, 389, 390, 540]
    private let accuracy: CGFloat = 0.0001

    // MARK: - Ported metrics (§10.8)

    func testActiveMetricsMatchTheDesignSystem() {
        XCTAssertEqual(DWBMetrics.queueFlatRowHeight, 44)
        XCTAssertEqual(DWBMetrics.queuePlayingRowHeight, 52)
        XCTAssertEqual(DWBMetrics.queuePlayingCardHeight, 48)
        XCTAssertEqual(DWBMetrics.queuePlayingCardGap, 4)
        XCTAssertEqual(DWBMetrics.queueHeaderHeight, 52)
        XCTAssertEqual(DWBMetrics.queueSectionHeight, 28)
        XCTAssertEqual(DWBMetrics.queueFooterHeight, 78)
        XCTAssertEqual(DWBMetrics.queueActionRowHeight, 39)
        XCTAssertEqual(DWBMetrics.queueStatusRowHeight, 38)
        XCTAssertEqual(DWBMetrics.queuePanelMinWidth, 200)
        XCTAssertEqual(DWBMetrics.queueCompactBelow, 390)
        XCTAssertEqual(DWBMetrics.queueCellHoverAlpha, 0.035, accuracy: accuracy)
        XCTAssertEqual(DWBMetrics.queueCellPressedAlpha, 0.075, accuracy: accuracy)
        XCTAssertEqual(DWBMetrics.queueFooterDisabledAlpha, 0.4, accuracy: accuracy)
        XCTAssertEqual(DWBMetrics.queueEmptyIcon, 96)
        XCTAssertEqual(DWBMetrics.queueEmptyIconAlpha, 0.32, accuracy: accuracy)
        XCTAssertEqual(DWBMetrics.queueEmptyIconSaturation, 0.6, accuracy: accuracy)
        XCTAssertEqual(DWBMetrics.queueEmptyDetailMaxWidth, 320)
        XCTAssertEqual(DWBMetrics.queueEmptyPill, 26)
        XCTAssertEqual(DWBMetrics.queueEmptyCircle, 44)
        XCTAssertEqual(DWBMetrics.queueEmptyGap, 13)
        XCTAssertEqual(DWBMetrics.queueEmptyPadding, 15)
        // The classic metrics stay declared for the UI kits, but the active look does not use them.
        XCTAssertEqual(DWBMetrics.queueRowHeight, 56)
        XCTAssertEqual(DWBMetrics.queueRowInset, 4)
        XCTAssertNotEqual(DWBMetrics.queueFlatRowHeight, DWBMetrics.queueRowHeight)
    }

    func testCompactSwitchesBetween389And390() {
        XCTAssertTrue(QueuePanelLayout.isCompact(panelWidth: 389))
        XCTAssertFalse(QueuePanelLayout.isCompact(panelWidth: 390))
        XCTAssertTrue(QueuePanelLayout.isCompact(panelWidth: 200))
        XCTAssertFalse(QueuePanelLayout.isCompact(panelWidth: 540))
    }

    // MARK: - Header: one 52 pt row at every width

    private func sortLabelWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .regular)]).width)
    }

    func testHeaderIsOneRowWithEveryActionAtEveryWidth() {
        let bounds = NSRect(x: 0, y: 0, width: 0, height: DWBMetrics.queueHeaderHeight)
        for width in widths {
            let header = QueueHeaderLayout.make(panelWidth: width, sortLabelWidth: sortLabelWidth("Manual"))
            let content = bounds.insetBy(dx: 0, dy: 0)
            let frames = [header.search, header.sort, header.bookmark, header.close]
            for frame in frames {
                XCTAssertGreaterThan(frame.width, 0, "width \(width)")
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "width \(width)")
                XCTAssertLessThanOrEqual(frame.maxX, QueuePanelLayout.contentWidth(panelWidth: width), "width \(width)")
                // One row: every frame sits in the same 51 pt band above the 1 pt rule.
                XCTAssertGreaterThanOrEqual(frame.minY, QueueHeaderLayout.bottomRule)
                XCTAssertLessThanOrEqual(frame.maxY, content.height)
                XCTAssertEqual(frame.height, 28, "width \(width)")
            }
            XCTAssertEqual(header.search.minY, header.sort.minY, "same row at \(width)")
            // Left to right: search, sort, bookmark filter, close; none overlap.
            XCTAssertLessThanOrEqual(header.search.maxX, header.sort.minX, "width \(width)")
            XCTAssertLessThanOrEqual(header.sort.maxX, header.bookmark.minX, "width \(width)")
            XCTAssertLessThanOrEqual(header.bookmark.maxX, header.close.minX, "width \(width)")
        }
    }

    func testHeaderKeepsAUsableSearchFieldAt200() {
        let header = QueueHeaderLayout.make(panelWidth: 200, sortLabelWidth: sortLabelWidth("Manual"))
        XCTAssertTrue(header.isCompact)
        XCTAssertGreaterThanOrEqual(header.search.width, 100)
        // Compact: a 24 wide sort icon button that is still there.
        XCTAssertEqual(header.sort.width, 24)
        XCTAssertEqual(header.bookmark.width, 24)
        XCTAssertEqual(header.close.width, 24)
        // 7 pt insets, no gap; the search field keeps 2 pt from the sort button.
        XCTAssertEqual(header.search.minX, 7)
        XCTAssertEqual(header.search.maxX, header.sort.minX - 2, accuracy: accuracy)
        XCTAssertEqual(header.close.maxX, QueuePanelLayout.contentWidth(panelWidth: 200) - 7, accuracy: accuracy)
    }

    func testSortStaysAnIconBelow390AndShowsItsLabelFrom390() {
        let label = sortLabelWidth("Manual")
        let compact = QueueHeaderLayout.make(panelWidth: 389, sortLabelWidth: label)
        let expanded = QueueHeaderLayout.make(panelWidth: 390, sortLabelWidth: label)
        XCTAssertEqual(compact.sort.width, 24)
        XCTAssertEqual(expanded.sort.width, label + QueueHeaderLayout.sortButtonChrome, accuracy: accuracy)
        XCTAssertGreaterThan(expanded.sort.width, 24)
        // 12 pt insets and 4 pt gaps once expanded.
        XCTAssertEqual(expanded.search.minX, 12)
        XCTAssertEqual(expanded.search.maxX, expanded.sort.minX - 4, accuracy: accuracy)
        XCTAssertEqual(expanded.sort.maxX, expanded.bookmark.minX - 4, accuracy: accuracy)
        XCTAssertEqual(expanded.close.maxX, QueuePanelLayout.contentWidth(panelWidth: 390) - 12, accuracy: accuracy)
    }

    func testSortLabelIsCappedAt120WithTailTruncationRoom() {
        let long = sortLabelWidth("Duration Long-Short")
        let header = QueueHeaderLayout.make(panelWidth: 540, sortLabelWidth: long)
        XCTAssertLessThanOrEqual(header.sort.width, 120)
        XCTAssertEqual(QueueHeaderLayout.sortLabelMaxWidth(), 96)
        let huge = QueueHeaderLayout.make(panelWidth: 540, sortLabelWidth: 400)
        XCTAssertEqual(huge.sort.width, 120)
    }

    // MARK: - Footer: exactly two rows, 78 pt, at every width

    func testFooterIsSeventyEightPointsInTwoRowsAtEveryWidth() {
        for width in widths {
            let footer = QueueFooterLayout.make(panelWidth: width)
            let contentWidth = QueuePanelLayout.contentWidth(panelWidth: width)
            XCTAssertEqual(footer.size.height, 78, "width \(width)")
            XCTAssertEqual(footer.size.width, contentWidth, "width \(width)")
            // 1 top rule + 39 actions row (its own 1 pt rule included) + 38 status row.
            XCTAssertEqual(footer.topRule, NSRect(x: 0, y: 77, width: contentWidth, height: 1))
            XCTAssertEqual(footer.actionRule, NSRect(x: 0, y: 38, width: contentWidth, height: 1))
            XCTAssertEqual(footer.topRule.height + DWBMetrics.queueActionRowHeight + DWBMetrics.queueStatusRowHeight, 78, "width \(width)")

            XCTAssertEqual(footer.actionCells.count, 4)
            XCTAssertEqual(footer.actionDividers.count, 3)
            for cell in footer.actionCells {
                XCTAssertEqual(cell.minY, 39, "width \(width)")
                XCTAssertEqual(cell.height, 38, "width \(width)")
                XCTAssertGreaterThan(cell.width, 0, "width \(width)")
            }
            // Four equal sections that tile the row (within a point of rounding).
            XCTAssertEqual(footer.actionCells.first?.minX, 0)
            XCTAssertEqual(footer.actionCells.last?.maxX, contentWidth)
            for index in 0..<3 {
                XCTAssertEqual(footer.actionCells[index].maxX, footer.actionCells[index + 1].minX, "width \(width)")
            }
            let widthsOfCells = footer.actionCells.map(\.width)
            XCTAssertLessThanOrEqual((widthsOfCells.max() ?? 0) - (widthsOfCells.min() ?? 0), 1, "width \(width)")
            XCTAssertEqual(footer.actionCells.last?.maxY, 77)
        }
    }

    func testFooterDividersAreHairlinesOnTheLeadingEdgeOfCellsTwoToFour() {
        for width in widths {
            let footer = QueueFooterLayout.make(panelWidth: width)
            for (index, divider) in footer.actionDividers.enumerated() {
                let cell = footer.actionCells[index + 1]
                XCTAssertEqual(divider.width, 0.5)
                XCTAssertEqual(divider.height, 18)
                XCTAssertEqual(divider.minX, cell.minX)
                // 10 from the top of the cell's content.
                XCTAssertEqual(cell.maxY - divider.maxY, 10, accuracy: accuracy)
            }
        }
    }

    func testStatusRowColumnsAre100FlexibleAnd110ThenCompact34FlexibleAnd34() {
        for width in widths {
            let footer = QueueFooterLayout.make(panelWidth: width)
            let contentWidth = QueuePanelLayout.contentWidth(panelWidth: width)
            let compact = width < 390
            XCTAssertEqual(footer.rescan.width, compact ? 34 : 100, "width \(width)")
            XCTAssertEqual(footer.clear.width, compact ? 34 : 110, "width \(width)")
            XCTAssertEqual(footer.rescan.minX, 0)
            XCTAssertEqual(footer.rescan.maxX, footer.total.minX, accuracy: accuracy)
            XCTAssertEqual(footer.total.maxX, footer.clear.minX, accuracy: accuracy)
            XCTAssertEqual(footer.clear.maxX, contentWidth, accuracy: accuracy)
            XCTAssertGreaterThan(footer.total.width, 0)
            for frame in [footer.rescan, footer.total, footer.clear] {
                XCTAssertEqual(frame.minY, 0)
                XCTAssertEqual(frame.height, 38)
            }
            XCTAssertEqual(footer.totalFitWidth, footer.total.width - 16, accuracy: accuracy)
            XCTAssertEqual(footer.totalDividers.count, 2)
            XCTAssertEqual(footer.totalDividers[0].minX, footer.total.minX)
            XCTAssertEqual(footer.totalDividers[1].maxX, footer.total.maxX)
            for divider in footer.totalDividers {
                XCTAssertEqual(divider.width, 0.5)
                XCTAssertEqual(divider.height, 18)
                XCTAssertEqual(divider.midY, 19, accuracy: accuracy)
            }
        }
    }

    func testFooterFramesNeverOverlapNeverGoNegativeAndStayInside() {
        for width in widths {
            let footer = QueueFooterLayout.make(panelWidth: width)
            let bounds = NSRect(origin: .zero, size: footer.size)
            let buttons = footer.actionCells + [footer.rescan, footer.total, footer.clear]
            for frame in buttons + [footer.topRule, footer.actionRule] + footer.actionDividers + footer.totalDividers {
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "width \(width)")
                XCTAssertGreaterThanOrEqual(frame.minY, 0, "width \(width)")
                XCTAssertGreaterThanOrEqual(frame.width, 0, "width \(width)")
                XCTAssertGreaterThanOrEqual(frame.height, 0, "width \(width)")
                XCTAssertTrue(bounds.contains(frame), "width \(width): \(frame)")
            }
            for i in 0..<buttons.count {
                for j in (i + 1)..<buttons.count {
                    XCTAssertTrue(buttons[i].intersection(buttons[j]).isEmpty, "width \(width): \(buttons[i]) vs \(buttons[j])")
                }
            }
            // Two rows only: the action cells sit entirely above the status row and its rule.
            XCTAssertGreaterThanOrEqual(footer.actionCells.map(\.minY).min() ?? 0, footer.actionRule.maxY)
            XCTAssertLessThanOrEqual([footer.rescan, footer.total, footer.clear].map(\.maxY).max() ?? 0, footer.actionRule.minY)
        }
    }

    func testFooterHeightIsTheSameWhateverTheContent() {
        // The plan takes only the width: there is no state that adds a row or a wrapped group.
        for width in [120, 199, 200, 260, 1200] as [CGFloat] {
            XCTAssertEqual(QueueFooterLayout.make(panelWidth: width).size.height, 78)
        }
    }

    // MARK: - Footer sections: full-section targets, centered content, marks

    private func footerContainer(panelWidth: CGFloat) -> (NSView, QueueFooterLayout) {
        let footer = QueueFooterLayout.make(panelWidth: panelWidth)
        let container = NSView(frame: NSRect(origin: .zero, size: footer.size))
        return (container, footer)
    }

    func testEverySectionIsOneButtonThatFillsItsWholeCell() {
        for width in widths {
            let (container, footer) = footerContainer(panelWidth: width)
            var buttons: [QueueFooterCellButton] = []
            for frame in footer.actionCells + [footer.rescan, footer.clear] {
                let button = QueueFooterCellButton(frame: frame)
                container.addSubview(button)
                buttons.append(button)
            }
            // The 0.5 pt dividers are drawn on top and must not take the pointer.
            for divider in footer.actionDividers + footer.totalDividers {
                let rule = QueueRuleView(kind: .divider)
                rule.frame = divider
                container.addSubview(rule)
            }
            for button in buttons {
                let frame = button.frame
                // Corners and edges of the section (inset 0.25 so each point is inside only this cell).
                let probes = [NSPoint(x: frame.minX + 0.25, y: frame.minY + 0.25),
                              NSPoint(x: frame.maxX - 0.25, y: frame.minY + 0.25),
                              NSPoint(x: frame.minX + 0.25, y: frame.maxY - 0.25),
                              NSPoint(x: frame.maxX - 0.25, y: frame.maxY - 0.25),
                              NSPoint(x: frame.midX, y: frame.midY)]
                for point in probes {
                    XCTAssertTrue(container.hitTest(point) === button, "width \(width): \(point) in \(frame)")
                }
            }
        }
    }

    func testRescanAndClearContentIsCenteredInTheirOwnColumns() {
        for width in [270, 540] as [CGFloat] {
            let footer = QueueFooterLayout.make(panelWidth: width)
            for (frame, symbol, text) in [(footer.rescan, "arrow.clockwise", "Rescan"),
                                          (footer.clear, "trash", "Clear queue")] {
                let button = QueueFooterCellButton(frame: NSRect(origin: .zero, size: frame.size))
                button.symbolName = symbol
                button.labelText = text
                button.labelFont = .systemFont(ofSize: 10.5)
                let rects = button.contentRects()
                let icon = try! XCTUnwrap(rects.icon)
                let label = try! XCTUnwrap(rects.label)
                // The icon-and-label group is centered in its own column, not pushed to the panel edge.
                let group = icon.union(label)
                XCTAssertEqual(group.midX, button.bounds.midX, accuracy: 1)
                XCTAssertEqual(icon.midY, button.bounds.midY, accuracy: 1)
                XCTAssertTrue(button.bounds.contains(group))
            }
        }
    }

    func testCompactStatusCellsCenterTheirIconAlone() {
        let footer = QueueFooterLayout.make(panelWidth: 200)
        let button = QueueFooterCellButton(frame: NSRect(origin: .zero, size: footer.rescan.size))
        button.symbolName = "arrow.clockwise"
        button.labelText = "Rescan"
        button.showsLabel = false
        let rects = button.contentRects()
        XCTAssertNil(rects.label)
        XCTAssertEqual(rects.icon?.midX ?? 0, button.bounds.midX, accuracy: accuracy)
        XCTAssertEqual(rects.icon?.midY ?? 0, button.bounds.midY, accuracy: accuracy)
    }

    func testMarkerMarkIsFourPointsAtSevenFromTheTopRightAndNeverOverlapsAPrefixLabel() {
        for width in widths {
            let footer = QueueFooterLayout.make(panelWidth: width)
            for cellFrame in footer.actionCells {
                let bounds = NSRect(origin: .zero, size: cellFrame.size)
                let mark = QueueFooterCellGeometry.markRect(inBounds: bounds)
                XCTAssertEqual(mark.size, NSSize(width: 4, height: 4))
                XCTAssertEqual(bounds.maxX - mark.maxX, 7, accuracy: accuracy)
                XCTAssertEqual(mark.minY, 7, accuracy: accuracy)
                // Longest prefix label the section can show: eight characters and an ellipsis.
                let longest = QueueMarkerState.label(forPrefix: "abcdefghij")
                let button = QueueFooterCellButton(frame: bounds)
                button.labelFont = QueueFooterCellButton.markerFont
                button.labelText = longest
                button.isCompact = width < 390
                button.mark = .applied
                let rects = button.contentRects()
                let label = try! XCTUnwrap(rects.label)
                let padding = QueueFooterCellGeometry.labelPadding(isCompact: width < 390)
                XCTAssertGreaterThanOrEqual(label.minX, padding - accuracy, "width \(width)")
                XCTAssertLessThanOrEqual(label.maxX, bounds.width - padding + accuracy, "width \(width)")
                XCTAssertTrue(label.intersection(mark).isEmpty, "width \(width): label \(label) vs mark \(mark)")
                // And it stays clear of the divider on the cell's leading edge.
                XCTAssertGreaterThan(label.minX, DWBMetrics.queueCellDivider.width)
            }
        }
    }

    func testLabelIsCenteredWhenItFitsAndTailTruncatedWithinItsCellWhenItDoesNot() {
        let bounds = NSRect(x: 0, y: 0, width: 49, height: 38)
        let button = QueueFooterCellButton(frame: bounds)
        button.labelFont = QueueFooterCellButton.markerFont
        button.isCompact = true
        button.labelText = "k_"
        let short = try! XCTUnwrap(button.contentRects().label)
        XCTAssertEqual(short.midX, bounds.midX, accuracy: 1)
        XCTAssertEqual(short.midY, bounds.midY, accuracy: 1)
        button.labelText = "abcdefgh…"
        let long = try! XCTUnwrap(button.contentRects().label)
        XCTAssertEqual(long.width, bounds.width - 8, accuracy: accuracy)
    }

    func testHoverPressAndDisabledChangeNothingButTheOverlay() {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 38)
        let button = QueueFooterCellButton(frame: frame)
        button.symbolName = "arrow.clockwise"
        button.labelText = "Rescan"
        button.labelFont = .systemFont(ofSize: 10.5)
        let before = button.contentRects()

        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
        button.mouseEntered(with: try! XCTUnwrap(entered))
        XCTAssertTrue(button.isHovering)
        let after = button.contentRects()
        XCTAssertEqual(before.icon, after.icon)
        XCTAssertEqual(before.label, after.label)
        XCTAssertEqual(button.frame, frame)
        // No transform: the button is not layer-backed and draws everything itself.
        XCTAssertNil(button.layer)
        XCTAssertTrue(button.isFlipped)

        // Overlays are textPrimary at the footer's own alphas, pressed above hover, none at rest.
        XCTAssertNil(QueueControlButton.cellOverlay(hovering: false, pressing: false))
        XCTAssertEqual(QueueControlButton.cellOverlay(hovering: true, pressing: false)?.alphaComponent ?? 0, 0.035, accuracy: 0.0001)
        XCTAssertEqual(QueueControlButton.cellOverlay(hovering: true, pressing: true)?.alphaComponent ?? 0, 0.075, accuracy: 0.0001)

        // Disabled: 0.4 opacity, and a disabled button neither highlights nor stays hovered.
        button.isEnabled = false
        XCTAssertEqual(button.alphaValue, 0.4, accuracy: accuracy)
        XCTAssertFalse(button.isHovering)
        button.mouseEntered(with: try! XCTUnwrap(entered))
        XCTAssertFalse(button.isHovering)
        XCTAssertEqual(button.contentRects().icon, before.icon)
    }

    func testMarkIsDrawnOnlyForAppliedAndMixed() {
        let button = QueueFooterCellButton(frame: NSRect(x: 0, y: 0, width: 80, height: 38))
        button.labelFont = QueueFooterCellButton.markerFont
        button.labelText = "keep_"
        XCTAssertNil(button.contentRects().mark)
        button.mark = .applied
        XCTAssertNotNil(button.contentRects().mark)
        button.mark = .mixed
        XCTAssertNotNil(button.contentRects().mark)
        XCTAssertEqual(button.contentRects().mark, QueueFooterCellGeometry.markRect(inBounds: button.bounds))
    }

    // MARK: - Total (§10.5)

    func testItemCountsAreSingularPluralAndFiltered() {
        XCTAssertEqual(QueueFooterTotal.countText(itemCount: 0, visibleCount: 0, isFiltered: false), "0 items")
        XCTAssertEqual(QueueFooterTotal.countText(itemCount: 1, visibleCount: 1, isFiltered: false), "1 item")
        XCTAssertEqual(QueueFooterTotal.countText(itemCount: 280, visibleCount: 280, isFiltered: false), "280 items")
        XCTAssertEqual(QueueFooterTotal.countText(itemCount: 280, visibleCount: 12, isFiltered: true), "12 of 280 items")
        XCTAssertEqual(QueueFooterTotal.countText(itemCount: 1, visibleCount: 1, isFiltered: true), "1 of 1 item")
        XCTAssertEqual(QueueFooterTotal.countText(itemCount: 12, visibleCount: 0, isFiltered: true), "0 of 12 items")
    }

    func testCandidatesRunFromDurationAndCountToHoursAndMinutes() {
        XCTAssertEqual(QueueFooterTotal.candidates(durationText: "111:32:18", itemCount: 280, visibleCount: 280, isFiltered: false),
                       ["111:32:18 · 280 items", "111:32:18", "111h 32m"])
        XCTAssertEqual(QueueFooterTotal.candidates(durationText: "00:42:10", itemCount: 1, visibleCount: 1, isFiltered: false),
                       ["00:42:10 · 1 item", "00:42:10", "42m"])
        XCTAssertEqual(QueueFooterTotal.candidates(durationText: "01:02:03", itemCount: 280, visibleCount: 12, isFiltered: true),
                       ["01:02:03 · 12 of 280 items", "01:02:03", "1h 2m"])
        XCTAssertEqual(QueueFooterTotal.candidates(durationText: "00:00:00", itemCount: 0, visibleCount: 0, isFiltered: false),
                       ["00:00:00 · 0 items", "00:00:00", "0m"])
    }

    func testAPartialTotalKeepsItsPlusWhenShortened() {
        let candidates = QueueFooterTotal.candidates(durationText: "01:02:03 +", itemCount: 12, visibleCount: 12, isFiltered: false)
        XCTAssertEqual(candidates, ["01:02:03 + · 12 items", "01:02:03 +", "1h 2m +"])
        XCTAssertEqual(QueueFooterTotal.hoursMinutes(fromDuration: "111:32:18 +"), "111h 32m +")
        XCTAssertEqual(QueueFooterTotal.hoursMinutes(fromDuration: "00:05:00 +"), "5m +")
    }

    func testAnAllUnknownTotalStaysDashesAndIsNeverReadAsZero() {
        let candidates = QueueFooterTotal.candidates(durationText: "--:--", itemCount: 12, visibleCount: 12, isFiltered: false)
        XCTAssertEqual(candidates, ["--:-- · 12 items", "--:--"])
        XCTAssertNil(QueueFooterTotal.hoursMinutes(fromDuration: "--:--"))
        XCTAssertFalse(candidates.contains { $0.contains("0m") || $0.contains("00:00") })
    }

    func testFullTotalForAccessibilityKeepsTheUncertainty() {
        XCTAssertEqual(QueueFooterTotal.accessibilityText(durationText: "01:02:03", itemCount: 12, visibleCount: 12, isFiltered: false),
                       "01:02:03 · 12 items")
        XCTAssertEqual(QueueFooterTotal.accessibilityText(durationText: "01:02:03 +", itemCount: 12, visibleCount: 3, isFiltered: true),
                       "01:02:03 + · 3 of 12 items, some durations unknown")
        XCTAssertEqual(QueueFooterTotal.accessibilityText(durationText: "--:--", itemCount: 12, visibleCount: 12, isFiltered: false),
                       "--:-- · 12 items, duration unknown")
    }

    func testFittedPicksTheLongestCandidateThatFitsAndTheShortestWhenNoneDoes() {
        let measure: (String) -> CGFloat = { CGFloat($0.count) }
        let candidates = ["111:32:18 · 280 items", "111:32:18", "111h 32m"]
        XCTAssertEqual(QueueFooterTotal.fitted(candidates, availableWidth: 21, measure: measure), "111:32:18 · 280 items")
        XCTAssertEqual(QueueFooterTotal.fitted(candidates, availableWidth: 20, measure: measure), "111:32:18")
        XCTAssertEqual(QueueFooterTotal.fitted(candidates, availableWidth: 9, measure: measure), "111:32:18")
        XCTAssertEqual(QueueFooterTotal.fitted(candidates, availableWidth: 8, measure: measure), "111h 32m")
        XCTAssertEqual(QueueFooterTotal.fitted(candidates, availableWidth: 1, measure: measure), "111h 32m")
    }

    func testTotalIsChosenAgainstTheActualNativeWidthOfEachCenterCell() {
        let cases: [(String, Int, Int, Bool)] = [
            ("01:02:03", 12, 12, false),
            ("111:32:18", 280, 280, false),
            ("111:32:18 +", 280, 12, true),
            ("--:--", 5, 5, false),
            ("9999:59:59", 99_999, 99_999, false)
        ]
        for width in widths {
            let footer = QueueFooterLayout.make(panelWidth: width)
            for (duration, count, visible, filtered) in cases {
                let candidates = QueueFooterTotal.candidates(durationText: duration, itemCount: count,
                                                             visibleCount: visible, isFiltered: filtered)
                let chosen = QueueFooterTotal.fitted(candidates, availableWidth: footer.totalFitWidth,
                                                     measure: QueueFooterTotal.measuredWidth)
                let index = try! XCTUnwrap(candidates.firstIndex(of: chosen))
                // It fits, or it is the shortest reading; every longer reading did not fit.
                if index < candidates.count - 1 {
                    XCTAssertLessThanOrEqual(QueueFooterTotal.measuredWidth(chosen), footer.totalFitWidth, "\(width) \(duration)")
                }
                for longer in candidates[..<index] {
                    XCTAssertGreaterThan(QueueFooterTotal.measuredWidth(longer), footer.totalFitWidth, "\(width) \(duration)")
                }
                print("QUEUE-TOTAL panel=\(width) fit=\(footer.totalFitWidth) \"\(duration)\" \(count) items -> \"\(chosen)\" (\(QueueFooterTotal.measuredWidth(chosen)) pt)")
            }
        }
    }

    func testTheNarrowestPanelStillShowsAReadableTotalWithoutAnotherRow() {
        let footer = QueueFooterLayout.make(panelWidth: 200)
        let chosen = QueueFooterTotal.fitted(
            QueueFooterTotal.candidates(durationText: "111:32:18", itemCount: 280, visibleCount: 280, isFiltered: false),
            availableWidth: footer.totalFitWidth, measure: QueueFooterTotal.measuredWidth)
        XCTAssertEqual(chosen, "111:32:18")
        XCTAssertEqual(QueueFooterLayout.make(panelWidth: 200).size.height, 78)
    }

    // MARK: - Rows (§10.4)

    func testFlatRowsAre44AndThePlayingRowIs52WithA48PointCardAndA4PointGap() {
        XCTAssertEqual(QueueRowGeometry.tableRowHeight(isCurrent: false), 44)
        XCTAssertEqual(QueueRowGeometry.tableRowHeight(isCurrent: true), 52)
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 52)
        let card = QueueRowGeometry.shapeRect(inRowBounds: bounds, isCurrent: true)
        XCTAssertEqual(card.height, 48)
        XCTAssertEqual(bounds.maxY - card.maxY, 4, "the 4 pt gap below the card")
        let flat = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44), isCurrent: false)
        XCTAssertEqual(flat.height, 44)
        XCTAssertEqual(QueueRowGeometry.cornerRadius(isCurrent: true), 7)
        XCTAssertEqual(QueueRowGeometry.cornerRadius(isCurrent: false), 6)
    }

    func testMovingTheCurrentItemSwapsWhichRowsAre52And44() {
        func heights(rowCount: Int, current: Int) -> [CGFloat] {
            (0..<rowCount).map { QueueRowGeometry.tableRowHeight(isCurrent: $0 == current) }
        }
        let before = heights(rowCount: 6, current: 2)
        let after = heights(rowCount: 6, current: 4)
        XCTAssertEqual(before, [44, 44, 52, 44, 44, 44])
        XCTAssertEqual(after, [44, 44, 44, 44, 52, 44])
        // The former current row is flat again and the new one is a card: no stale geometry either way.
        XCTAssertEqual(before[2], 52); XCTAssertEqual(after[2], 44)
        XCTAssertEqual(before[4], 44); XCTAssertEqual(after[4], 52)
        XCTAssertEqual(before.reduce(0, +), after.reduce(0, +))
    }

    func testRowShapeHasSixPointSidePaddingAndAFourPointTrailingMargin() {
        let shape = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44), isCurrent: false)
        XCTAssertEqual(shape.minX, 6)
        XCTAssertEqual(400 - shape.maxX, 10)
        XCTAssertEqual(shape.minY, 0)
        // A legacy scroller makes the table row wider than what the clip shows: the margin follows the clip.
        let clipped = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44),
                                                 isCurrent: false, visibleWidth: 385)
        XCTAssertEqual(385 - clipped.maxX, 10)
    }

    func testPlayingBarIsFlushLeftAndTheCardsFullHeightAndTheEdgeStrokesStayInside() {
        let bounds = NSRect(x: 0, y: 0, width: 333, height: 52)
        let card = QueueRowGeometry.shapeRect(inRowBounds: bounds, isCurrent: true)
        let bar = QueueRowGeometry.barRect(forCard: card)
        XCTAssertEqual(bar.minX, card.minX)
        XCTAssertEqual(bar.minY, card.minY)
        XCTAssertEqual(bar.height, card.height)
        XCTAssertEqual(bar.width, 3)
        XCTAssertTrue(card.contains(bar))
        for lineWidth in [0.5, 1] as [CGFloat] {
            let edge = QueueRowGeometry.edgeRect(forShape: card, lineWidth: lineWidth)
            // The stroke's outer boundary is the shape's own: nothing paints past the card.
            XCTAssertEqual(edge.minX - lineWidth / 2, card.minX, accuracy: accuracy)
            XCTAssertEqual(edge.maxY + lineWidth / 2, card.maxY, accuracy: accuracy)
        }
    }

    func testRowEdgesLandOnWholeDevicePixelsAtOneAndTwoTimes() {
        for width in [201, 333, 540] as [CGFloat] {
            for isCurrent in [false, true] {
                let bounds = NSRect(x: 0, y: 0, width: width, height: QueueRowGeometry.tableRowHeight(isCurrent: isCurrent))
                let shape = QueueRowGeometry.shapeRect(inRowBounds: bounds, isCurrent: isCurrent)
                for scale in [1, 2] as [CGFloat] {
                    for edge in [shape.minX, shape.maxX, shape.minY, shape.maxY] {
                        XCTAssertEqual((edge * scale).truncatingRemainder(dividingBy: 1), 0, accuracy: accuracy,
                                       "width \(width) current \(isCurrent) scale \(scale)")
                    }
                }
            }
        }
    }

    func testSeparatorIsTheRowsLastHalfPointAndNeverCrossesIntoANeighbor() {
        let shape = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44), isCurrent: false)
        let separator = QueueRowGeometry.separatorRect(forShape: shape)
        XCTAssertEqual(separator.height, 0.5)
        XCTAssertEqual(separator.maxY, shape.maxY)
        XCTAssertEqual(separator.minX, shape.minX + 5)
        XCTAssertEqual(shape.maxX - separator.maxX, 7)
        XCTAssertTrue(shape.contains(separator))
    }

    func testTextAndAccessoriesStayInsideTheCardWithRoomForDescenders() {
        let nameFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let metaFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        // The native line heights fit the 18 and 16 pt lines the geometry gives them.
        XCTAssertLessThanOrEqual(ceil(nameFont.ascender - nameFont.descender + nameFont.leading), DWBMetrics.queueRowNameLine)
        XCTAssertLessThanOrEqual(ceil(metaFont.ascender - metaFont.descender + metaFont.leading), QueueRowGeometry.metadataLine)

        for width in [200, 270, 540] as [CGFloat] {
            for (isCurrent, isFailed) in [(false, false), (false, true), (true, false), (true, true)] {
                let bounds = NSRect(x: 0, y: 0, width: width - 1, height: QueueRowGeometry.tableRowHeight(isCurrent: isCurrent))
                let shape = QueueRowGeometry.shapeRect(inRowBounds: bounds, isCurrent: isCurrent)
                let content = QueueRowGeometry.content(inShape: shape, isCurrent: isCurrent, isFailed: isFailed,
                                                       nameNaturalWidth: 900, tagWidth: 30, showsBookmark: true)
                for frame in [content.name, content.meta, content.tag, content.bookmark, content.glyph].compactMap({ $0 }) {
                    XCTAssertTrue(shape.contains(frame), "\(frame) outside \(shape) at \(width) current \(isCurrent)")
                    XCTAssertGreaterThanOrEqual(frame.width, 0)
                    XCTAssertGreaterThanOrEqual(frame.height, 0)
                }
                // Both lines sit at least 4 pt from the card's top and bottom: descenders are not clipped.
                XCTAssertGreaterThanOrEqual(content.name.minY - shape.minY, 4)
                XCTAssertGreaterThanOrEqual(shape.maxY - content.meta.maxY, 4)
                XCTAssertEqual(content.meta.minY, content.name.maxY)
            }
        }
    }

    func testTextInsetsFollowTheRowKind() {
        let shape = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44), isCurrent: false)
        let flat = QueueRowGeometry.content(inShape: shape, isCurrent: false, isFailed: false, nameNaturalWidth: 50, tagWidth: nil, showsBookmark: false)
        let failed = QueueRowGeometry.content(inShape: shape, isCurrent: false, isFailed: true, nameNaturalWidth: 50, tagWidth: nil, showsBookmark: false)
        let card = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 52), isCurrent: true)
        let playing = QueueRowGeometry.content(inShape: card, isCurrent: true, isFailed: false, nameNaturalWidth: 50, tagWidth: nil, showsBookmark: false)
        XCTAssertEqual(flat.name.minX - shape.minX, 5)
        XCTAssertNil(flat.glyph)
        XCTAssertEqual(failed.name.minX - shape.minX, 27)
        XCTAssertEqual(failed.glyph?.minX, shape.minX + 9)
        XCTAssertEqual(playing.name.minX - card.minX, 37)
        XCTAssertEqual(playing.glyph?.minX, card.minX + 14)
        XCTAssertEqual(playing.glyph?.width, 13)
        XCTAssertLessThanOrEqual(failed.glyph?.maxX ?? 0, failed.name.minX)
        XCTAssertLessThanOrEqual(playing.glyph?.maxX ?? 0, playing.name.minX)
        // A playing row that is also failed shows the playing glyph and its own inset.
        let both = QueueRowGeometry.content(inShape: card, isCurrent: true, isFailed: true, nameNaturalWidth: 50, tagWidth: nil, showsBookmark: false)
        XCTAssertEqual(both.name.minX - card.minX, 37)
        XCTAssertEqual(both.glyph?.minX, card.minX + 14)
    }

    func testTagAndBookmarkTakeTheirRoomBeforeTheNameIsMeasured() {
        let shape = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44), isCurrent: false)
        let textRight = shape.maxX - 10
        // A long name: it shortens so the tag and bookmark end exactly at the text edge.
        let long = QueueRowGeometry.content(inShape: shape, isCurrent: false, isFailed: false,
                                            nameNaturalWidth: 900, tagWidth: 30, showsBookmark: true)
        let tag = try! XCTUnwrap(long.tag)
        let bookmark = try! XCTUnwrap(long.bookmark)
        XCTAssertEqual(tag.minX, long.name.maxX + 6, accuracy: accuracy)
        XCTAssertEqual(bookmark.minX, tag.maxX + 6, accuracy: accuracy)
        XCTAssertEqual(bookmark.maxX, textRight, accuracy: accuracy)
        XCTAssertGreaterThan(long.name.width, 0)
        // A short name: they follow it directly.
        let short = QueueRowGeometry.content(inShape: shape, isCurrent: false, isFailed: false,
                                             nameNaturalWidth: 80, tagWidth: 30, showsBookmark: true)
        XCTAssertEqual(short.name.width, 80)
        XCTAssertEqual(short.tag?.minX ?? 0, short.name.maxX + 6, accuracy: accuracy)
        // Neither accessory: the name takes the whole line.
        let plain = QueueRowGeometry.content(inShape: shape, isCurrent: false, isFailed: false,
                                             nameNaturalWidth: 900, tagWidth: nil, showsBookmark: false)
        XCTAssertEqual(plain.name.maxX, textRight, accuracy: accuracy)
        XCTAssertNil(plain.tag)
        XCTAssertNil(plain.bookmark)
    }

    // MARK: - Middle truncation (§10.4)

    func testMiddleTruncationFollowsTheDesignSystemExample() {
        let name = "Long summer evening in the mountains.mp4"
        // Fits while 36 characters or fewer: 35 kept plus the ellipsis.
        let result = QueueNameTruncation.truncated(name, fits: { $0.count <= 36 })
        XCTAssertEqual(result, "Long summer evening in the…tains.mp4")
    }

    func testMiddleTruncationKeepsAtMostNineCharactersAfterTheEllipsisAndHalfWhenShort() {
        let name = String(repeating: "a", count: 30) + ".mp4"
        let wide = QueueNameTruncation.truncated(name, fits: { $0.count <= 21 })
        XCTAssertEqual(wide.components(separatedBy: "…").last?.count, 9)
        let narrow = QueueNameTruncation.truncated(name, fits: { $0.count <= 7 })
        // 6 kept: 3 after the ellipsis.
        XCTAssertEqual(narrow.components(separatedBy: "…").last?.count, 3)
        XCTAssertEqual(narrow.count, 7)
        XCTAssertEqual(QueueNameTruncation.truncated(name, fits: { _ in false }), "…")
        XCTAssertEqual(QueueNameTruncation.truncated("short.mp4", fits: { _ in true }), "short.mp4")
    }

    func testAttributedMiddleTruncationKeepsPrefixColorAndWeightAndTheFullNameIsUntouched() {
        let name = "keep_a very long holiday recording from last summer.mp4"
        let attributed = QueueNameStyle.attributedName(name, fontSize: 12.5, weight: .medium,
                                                       color: DWBColor.textPrimary,
                                                       primaryPrefix: "keep_", secondaryPrefix: "del_", query: "")
        let width: CGFloat = 150
        let truncated = QueueNameTruncation.truncated(attributed, toFit: width)
        XCTAssertTrue(truncated.string.contains("…"))
        XCTAssertLessThan(truncated.string.count, name.count)
        XCTAssertLessThanOrEqual(ceil(truncated.size().width), width)
        XCTAssertTrue(truncated.string.hasPrefix("keep_"))
        XCTAssertTrue(truncated.string.hasSuffix(".mp4"))
        // The marker prefix keeps its marker color and bold weight on the kept characters.
        let head = truncated.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(head[.foregroundColor] as? NSColor, PlayerTheme.current.markerPrimary)
        XCTAssertEqual((head[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold), true)
        // The tail is the ordinary name color.
        let tail = truncated.attributes(at: truncated.length - 1, effectiveRange: nil)
        XCTAssertEqual(tail[.foregroundColor] as? NSColor, DWBColor.textPrimary)
        // Truncating for display never changes the source string (the item identity and tooltip).
        XCTAssertEqual(attributed.string, name)
    }

    func testNothingIsTruncatedWhenTheNameFitsOrThereIsNoWidth() {
        let attributed = NSAttributedString(string: "tiny.mp4", attributes: [.font: NSFont.systemFont(ofSize: 12.5)])
        XCTAssertEqual(QueueNameTruncation.truncated(attributed, toFit: 500).string, "tiny.mp4")
        XCTAssertEqual(QueueNameTruncation.truncated(attributed, toFit: 0).string, "tiny.mp4")
    }

    func testNameLabelTruncatesInTheMiddleAtRestAndKeepsTheWholeNameWhileSearching() {
        let name = "Long summer evening in the mountains with friends.mp4"
        let attributed = QueueNameStyle.attributedName(name, fontSize: 12.5, weight: .medium, color: DWBColor.textPrimary,
                                                       primaryPrefix: "", secondaryPrefix: "", query: "evening")
        let label = QueueNameLabel(frame: NSRect(x: 0, y: 0, width: 140, height: 18))
        label.attributedText = attributed

        label.truncation = .middle
        let rest = label.displayedText(forWidth: 140)
        XCTAssertTrue(rest.string.contains("…"))

        // Searching: end-clip. The attributed match is still on the same characters of the full name.
        label.truncation = .tail
        let searching = label.displayedText(forWidth: 140)
        XCTAssertEqual(searching.string, name)
        let range = try! XCTUnwrap(QueueSearchHighlight.firstMatch(in: name, query: "evening"))
        let match = searching.attributes(at: range.location, effectiveRange: nil)
        XCTAssertEqual(match[.backgroundColor] as? NSColor, PlayerTheme.current.accentTintStrong)
        XCTAssertNotNil(match[.underlineStyle])
        XCTAssertEqual(label.attributedText.string, name)
    }

    // MARK: - Drop line (§10.4)

    func testDropLineIsAStraightTwoPointLineWithoutARing() {
        XCTAssertEqual(QueueDropIndicatorMetrics.lineHeight, 2)
        XCTAssertEqual(QueueDropIndicatorMetrics.draggedRowAlpha, 0.4, accuracy: accuracy)
        let shape = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: 400, height: 44), isCurrent: false)
        let frame = QueueDropIndicatorMetrics.frame(onBoundaryY: 88, spanning: shape)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.midY, 88, accuracy: accuracy)
        XCTAssertEqual(frame.minX, shape.minX)
        XCTAssertEqual(frame.width, shape.width)
        XCTAssertEqual(QueueDropIndicatorMetrics.lineRect(width: 120), NSRect(x: 0, y: 0, width: 120, height: 2))
    }

    // MARK: - Filtered empty states (§10.6)

    func testFilteredEmptyStatesUseTheGlyphCircleAndNeverTheAppIcon() {
        XCTAssertEqual(QueueFilteredEmptyState.circleDiameter, 44)
        XCTAssertEqual(QueueFilteredEmptyState.glyphSize, 18)
        let noMatches = QueueFilteredEmptyState.make(query: "xyz", bookmarkFilterEnabled: false)
        XCTAssertEqual(noMatches.symbolName, "magnifyingglass")
        XCTAssertEqual(noMatches.title, "No matching files")
        XCTAssertEqual(noMatches.actionTitle, "Clear Search")
        let noBookmarks = QueueFilteredEmptyState.make(query: "", bookmarkFilterEnabled: true)
        XCTAssertEqual(noBookmarks.symbolName, "bookmark")
        XCTAssertEqual(noBookmarks.title, "No bookmarked media")
        XCTAssertEqual(noBookmarks.actionTitle, "Show All Media")
        // A query with the bookmark filter on still reads as a search with no results.
        XCTAssertEqual(QueueFilteredEmptyState.make(query: "xyz", bookmarkFilterEnabled: true), .noMatches)
    }
}
