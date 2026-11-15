import AppKit

// Pure geometry and text rules for the active Queue Page look (`tokens-and-specs.md` §10).
// No views, no UserDefaults, no VLCKit: the Queue Page view only places what these return.
// Every value comes from `DWBMetrics`' "Queue panel (active look)" block.

// MARK: - Panel

enum QueuePanelLayout {
    /// The 1 pt border on the panel's leading edge. Header, list and footer lay out inside the rest.
    static let edgeWidth: CGFloat = 1

    /// Compact forms (header and footer) apply below `queueCompactBelow`, measured on the whole panel.
    static func isCompact(panelWidth: CGFloat) -> Bool {
        panelWidth < DWBMetrics.queueCompactBelow
    }

    static func contentWidth(panelWidth: CGFloat) -> CGFloat {
        max(0, panelWidth - edgeWidth)
    }
}

// MARK: - Header (§10.2)

/// One 52 pt row at every width: search field, sort, bookmark filter, close. Frames are in the
/// header view's coordinates (origin bottom-left, width = panel width minus the leading edge).
struct QueueHeaderLayout: Equatable {
    let isCompact: Bool
    let search: NSRect
    let sort: NSRect
    let bookmark: NSRect
    let close: NSRect

    /// Padding and gap around the sort label inside the expanded sort button: 4 + label + 6 + chevron 10 + 4.
    static let sortButtonChrome: CGFloat = 4 + 6 + 10 + 4
    static let sortChevronSize: CGFloat = 10
    /// The compact sort button keeps 2 pt between itself and the search field (the study's `margin-left`).
    static let compactSortMargin: CGFloat = 2
    /// The header's own 1 pt bottom rule sits inside its 52 pt.
    static let bottomRule: CGFloat = 1

    static func make(panelWidth: CGFloat, sortLabelWidth: CGFloat) -> QueueHeaderLayout {
        let compact = QueuePanelLayout.isCompact(panelWidth: panelWidth)
        let width = QueuePanelLayout.contentWidth(panelWidth: panelWidth)
        let inset = compact ? DWBMetrics.queueHeaderInsetCompact : DWBMetrics.queueHeaderInset
        let gap = compact ? 0 : DWBMetrics.queueHeaderGap
        let iconWidth = DWBMetrics.queueHeaderButtonCompactWidth
        let buttonHeight = DWBMetrics.queueHeaderButton
        let rowHeight = DWBMetrics.queueHeaderHeight - bottomRule
        let y = bottomRule + floor((rowHeight - buttonHeight) / 2)

        let close = NSRect(x: width - inset - iconWidth, y: y, width: iconWidth, height: buttonHeight)
        let bookmark = NSRect(x: close.minX - gap - iconWidth, y: y, width: iconWidth, height: buttonHeight)
        let sortWidth = compact
            ? iconWidth
            : min(DWBMetrics.queueSortLabelMaxWidth, ceil(sortLabelWidth) + sortButtonChrome)
        let sort = NSRect(x: bookmark.minX - gap - sortWidth, y: y, width: sortWidth, height: buttonHeight)
        let searchRight = sort.minX - (compact ? compactSortMargin : gap)
        let search = NSRect(x: inset,
                            y: bottomRule + floor((rowHeight - DWBMetrics.queueSearchHeight) / 2),
                            width: max(0, searchRight - inset),
                            height: DWBMetrics.queueSearchHeight)
        return QueueHeaderLayout(isCompact: compact, search: search, sort: sort, bookmark: bookmark, close: close)
    }

    /// Width available to the sort label inside the expanded sort button.
    static func sortLabelMaxWidth() -> CGFloat {
        DWBMetrics.queueSortLabelMaxWidth - sortButtonChrome
    }
}

// MARK: - Footer (§10.5)

/// Two rows at every width, 78 pt in all: the actions row (39 including its 1 pt bottom rule)
/// above the status row (38), under a 1 pt top rule. Frames are in the footer view's coordinates
/// (origin bottom-left, width = panel width minus the leading edge).
struct QueueFooterLayout: Equatable {
    let isCompact: Bool
    let size: NSSize
    let topRule: NSRect
    let actionRule: NSRect
    /// Remove, primary prefix, secondary prefix, Undo: four equal sections.
    let actionCells: [NSRect]
    /// 0.5 × 18 dividers on the leading edge of cells 2…4.
    let actionDividers: [NSRect]
    let rescan: NSRect
    let total: NSRect
    let clear: NSRect
    let totalDividers: [NSRect]

    /// The total shortens until it fits the center cell width minus this.
    var totalFitWidth: CGFloat { max(0, total.width - DWBMetrics.queueTotalFitInset) }

    static func make(panelWidth: CGFloat) -> QueueFooterLayout {
        let compact = QueuePanelLayout.isCompact(panelWidth: panelWidth)
        let width = QueuePanelLayout.contentWidth(panelWidth: panelWidth)
        let height = DWBMetrics.queueFooterHeight
        let statusHeight = DWBMetrics.queueStatusRowHeight
        let actionHeight = DWBMetrics.queueActionRowHeight
        let ruleHeight: CGFloat = 1

        let topRule = NSRect(x: 0, y: height - ruleHeight, width: width, height: ruleHeight)
        let actionRule = NSRect(x: 0, y: statusHeight, width: width, height: ruleHeight)
        // Content of the actions row sits between its bottom rule and the footer's top rule.
        let cellY = statusHeight + ruleHeight
        let cellHeight = actionHeight - ruleHeight
        var cells: [NSRect] = []
        var dividers: [NSRect] = []
        for index in 0..<4 {
            let minX = floor(width * CGFloat(index) / 4)
            let maxX = index == 3 ? width : floor(width * CGFloat(index + 1) / 4)
            cells.append(NSRect(x: minX, y: cellY, width: maxX - minX, height: cellHeight))
            if index > 0 {
                dividers.append(NSRect(x: minX,
                                       y: cellY + cellHeight - DWBMetrics.queueCellDividerTop - DWBMetrics.queueCellDivider.height,
                                       width: DWBMetrics.queueCellDivider.width,
                                       height: DWBMetrics.queueCellDivider.height))
            }
        }

        let columns = compact ? DWBMetrics.queueStatusColumnsCompact : DWBMetrics.queueStatusColumns
        let leading = min(columns.leading, width)
        let trailing = min(columns.trailing, max(0, width - leading))
        let rescan = NSRect(x: 0, y: 0, width: leading, height: statusHeight)
        let total = NSRect(x: leading, y: 0, width: max(0, width - leading - trailing), height: statusHeight)
        let clear = NSRect(x: width - trailing, y: 0, width: trailing, height: statusHeight)
        let dividerY = floor((statusHeight - DWBMetrics.queueCellDivider.height) / 2)
        let totalDividers = [
            NSRect(x: total.minX, y: dividerY, width: DWBMetrics.queueCellDivider.width, height: DWBMetrics.queueCellDivider.height),
            NSRect(x: total.maxX - DWBMetrics.queueCellDivider.width, y: dividerY,
                   width: DWBMetrics.queueCellDivider.width, height: DWBMetrics.queueCellDivider.height)
        ]
        return QueueFooterLayout(isCompact: compact, size: NSSize(width: width, height: height),
                                 topRule: topRule, actionRule: actionRule,
                                 actionCells: cells, actionDividers: dividers,
                                 rescan: rescan, total: total, clear: clear, totalDividers: totalDividers)
    }
}

/// Geometry inside one footer section. Rects are in the section's own top-left-origin bounds.
enum QueueFooterCellGeometry {
    static func labelPadding(isCompact: Bool) -> CGFloat { isCompact ? 4 : 7 }

    /// The 4 pt applied / mixed mark, 7 pt from the top and right edges.
    static func markRect(inBounds bounds: NSRect) -> NSRect {
        let size = DWBMetrics.queueMarkerStateMark
        let inset = DWBMetrics.queueMarkerStateInset
        return NSRect(x: bounds.maxX - inset - size, y: bounds.minY + inset, width: size, height: size)
    }

    /// A label of `textWidth` × `textHeight`, centered, never wider than the section minus its padding.
    static func labelRect(inBounds bounds: NSRect, textWidth: CGFloat, textHeight: CGFloat, isCompact: Bool) -> NSRect {
        let padding = labelPadding(isCompact: isCompact)
        let width = min(ceil(textWidth), max(0, bounds.width - padding * 2))
        return NSRect(x: bounds.minX + floor((bounds.width - width) / 2),
                      y: bounds.minY + floor((bounds.height - textHeight) / 2),
                      width: width, height: textHeight)
    }

    /// An icon, a gap and a label as one group, centered in the section.
    static func iconLabelRects(inBounds bounds: NSRect, iconSize: CGFloat, labelWidth: CGFloat,
                               labelHeight: CGFloat, gap: CGFloat = 6, isCompact: Bool) -> (icon: NSRect, label: NSRect) {
        let padding = labelPadding(isCompact: isCompact)
        let maxLabel = max(0, bounds.width - padding * 2 - iconSize - gap)
        let label = min(ceil(labelWidth), maxLabel)
        let group = iconSize + gap + label
        let x = bounds.minX + floor((bounds.width - group) / 2)
        let icon = NSRect(x: x, y: bounds.minY + floor((bounds.height - iconSize) / 2), width: iconSize, height: iconSize)
        let text = NSRect(x: icon.maxX + gap, y: bounds.minY + floor((bounds.height - labelHeight) / 2),
                          width: label, height: labelHeight)
        return (icon, text)
    }
}

// MARK: - Total (§10.5)

/// The status row's total: the longest of three readings that fits the center cell, never a second line.
enum QueueFooterTotal {
    static let separator = " · "
    /// Inset on each side of the total's text inside its cell (half of `queueTotalFitInset`).
    static let textInset: CGFloat = DWBMetrics.queueTotalFitInset / 2
    /// What the queue shows when no duration is known (the same text as `MediaFileSupport.durationUnknownText`).
    static let unknownDurationText = "--:--"

    static func itemCountText(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// "280 items", "1 item", or "12 of 280 items" while a search or filter is active.
    static func countText(itemCount: Int, visibleCount: Int, isFiltered: Bool) -> String {
        isFiltered ? "\(visibleCount) of \(itemCountText(itemCount))" : itemCountText(itemCount)
    }

    /// "111:32:18" → "111h 32m"; "00:42:10" → "42m". A trailing " +" (some durations unknown)
    /// survives. nil when the text is not a clock duration (`--:--` stays as it is).
    static func hoursMinutes(fromDuration text: String) -> String? {
        var body = text
        var plus = false
        if body.hasSuffix(" +") {
            plus = true
            body.removeLast(2)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let hours = Int(parts[0]), let minutes = Int(parts[1]), Int(parts[2]) != nil,
              hours >= 0, minutes >= 0 else { return nil }
        let reading = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return plus ? reading + " +" : reading
    }

    /// Longest first: duration and count, duration alone, then hours and minutes.
    static func candidates(durationText: String, itemCount: Int, visibleCount: Int, isFiltered: Bool) -> [String] {
        var result = [durationText + separator + countText(itemCount: itemCount, visibleCount: visibleCount, isFiltered: isFiltered),
                      durationText]
        if let short = hoursMinutes(fromDuration: durationText), !result.contains(short) {
            result.append(short)
        }
        return result
    }

    /// The first candidate that fits `availableWidth`; the shortest when none does (the label then
    /// clips its tail rather than wrapping).
    static func fitted(_ candidates: [String], availableWidth: CGFloat, measure: (String) -> CGFloat) -> String {
        candidates.first(where: { measure($0) <= availableWidth }) ?? candidates.last ?? ""
    }

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

    static func measuredWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The unshortened total, for the tooltip and VoiceOver. Says so when durations are partial or unknown.
    static func accessibilityText(durationText: String, itemCount: Int, visibleCount: Int, isFiltered: Bool) -> String {
        var text = durationText + separator + countText(itemCount: itemCount, visibleCount: visibleCount, isFiltered: isFiltered)
        if durationText == unknownDurationText {
            text += ", duration unknown"
        } else if durationText.hasSuffix("+") {
            text += ", some durations unknown"
        }
        return text
    }
}

// MARK: - Rows (§10.4)

/// Row geometry in a flipped (top-left origin) table row. The row view and the cell both lay
/// out from these rects, so the card, its bar and its text agree.
enum QueueRowGeometry {
    static func tableRowHeight(isCurrent: Bool) -> CGFloat {
        isCurrent ? DWBMetrics.queuePlayingRowHeight : DWBMetrics.queueFlatRowHeight
    }

    static func shapeHeight(isCurrent: Bool) -> CGFloat {
        isCurrent ? DWBMetrics.queuePlayingCardHeight : DWBMetrics.queueFlatRowHeight
    }

    static func cornerRadius(isCurrent: Bool) -> CGFloat {
        isCurrent ? DWBMetrics.queuePlayingCardRadius : DWBMetrics.queueFlatRowRadius
    }

    /// The flat row, or the 48 pt card with its 4 pt gap below. `visibleWidth` is the part of the
    /// row the clip view shows (a legacy scroller can make the table row wider than that).
    static func shapeRect(inRowBounds bounds: NSRect, isCurrent: Bool, visibleWidth: CGFloat? = nil) -> NSRect {
        let shown = min(bounds.width, (visibleWidth ?? bounds.width) > 0 ? (visibleWidth ?? bounds.width) : bounds.width)
        let side = DWBMetrics.queueListSidePadding
        return NSRect(x: bounds.minX + side,
                      y: bounds.minY,
                      width: max(0, shown - side * 2 - DWBMetrics.queueRowTrailingMargin),
                      height: shapeHeight(isCurrent: isCurrent))
    }

    /// The 0.5 pt separator under a flat row, inset 5 left and 7 right.
    static func separatorRect(forShape shape: NSRect) -> NSRect {
        NSRect(x: shape.minX + DWBMetrics.queueRowSeparatorInsetLeading,
               y: shape.maxY - DWBMetrics.queueRowSeparator,
               width: max(0, shape.width - DWBMetrics.queueRowSeparatorInsetLeading - DWBMetrics.queueRowSeparatorInsetTrailing),
               height: DWBMetrics.queueRowSeparator)
    }

    /// The 3 pt bar: flush left, the card's full height. The row view clips it to the card's rounded boundary.
    static func barRect(forCard card: NSRect) -> NSRect {
        NSRect(x: card.minX, y: card.minY, width: DWBMetrics.queuePlayingBar, height: card.height)
    }

    /// Where the 0.5 pt (or 1 pt) edge strokes: inside the shape, so nothing paints past it.
    static func edgeRect(forShape shape: NSRect, lineWidth: CGFloat) -> NSRect {
        shape.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
    }

    static let metadataLine: CGFloat = 16

    struct Content: Equatable {
        let glyph: NSRect?
        let name: NSRect
        let tag: NSRect?
        let bookmark: NSRect?
        let meta: NSRect
    }

    static let bookmarkGlyphWidth: CGFloat = 10
    static let bookmarkGlyphHeight: CGFloat = 12

    static func textInset(isCurrent: Bool, isFailed: Bool) -> CGFloat {
        if isCurrent { return DWBMetrics.queuePlayingTextInset }
        return isFailed ? DWBMetrics.queueRowTextInsetFailed : DWBMetrics.queueRowTextInset
    }

    /// Name line (18) over metadata line (16), centered in the shape. The tag and bookmark follow the
    /// name after a 6 pt gap, and their room is taken from the name before it is measured.
    static func content(inShape shape: NSRect,
                        isCurrent: Bool,
                        isFailed: Bool,
                        nameNaturalWidth: CGFloat,
                        tagWidth: CGFloat?,
                        showsBookmark: Bool) -> Content {
        let gap = DWBMetrics.queueRowNameGap
        let x = shape.minX + textInset(isCurrent: isCurrent, isFailed: isFailed)
        let right = shape.maxX - DWBMetrics.queueRowTextTrailing
        let textWidth = max(0, right - x)
        let blockHeight = DWBMetrics.queueRowNameLine + metadataLine
        let top = shape.minY + floor((shape.height - blockHeight) / 2)

        var reserved: CGFloat = 0
        if let tagWidth { reserved += gap + tagWidth }
        if showsBookmark { reserved += gap + bookmarkGlyphWidth }
        let nameWidth = min(ceil(nameNaturalWidth), max(0, textWidth - reserved))
        let name = NSRect(x: x, y: top, width: nameWidth, height: DWBMetrics.queueRowNameLine)

        var cursor = name.maxX
        var tag: NSRect?
        if let tagWidth {
            cursor += gap
            tag = NSRect(x: cursor, y: top + floor((DWBMetrics.queueRowNameLine - DWBMetrics.playNextTag) / 2),
                         width: tagWidth, height: DWBMetrics.playNextTag)
            cursor += tagWidth
        }
        var bookmark: NSRect?
        if showsBookmark {
            cursor += gap
            bookmark = NSRect(x: cursor, y: top + floor((DWBMetrics.queueRowNameLine - bookmarkGlyphHeight) / 2),
                              width: bookmarkGlyphWidth, height: bookmarkGlyphHeight)
        }
        let meta = NSRect(x: x, y: top + DWBMetrics.queueRowNameLine, width: textWidth, height: metadataLine)

        var glyph: NSRect?
        if isCurrent {
            let height = DWBMetrics.queuePlayingGlyph + 2
            glyph = NSRect(x: shape.minX + DWBMetrics.queuePlayingGlyphLeading,
                           y: shape.minY + floor((shape.height - height) / 2),
                           width: DWBMetrics.queuePlayingGlyph, height: height)
        } else if isFailed {
            glyph = NSRect(x: shape.minX + 9, y: shape.minY + floor((shape.height - 12) / 2), width: 12, height: 12)
        }
        return Content(glyph: glyph, name: name, tag: tag, bookmark: bookmark, meta: meta)
    }
}

// MARK: - Middle truncation (§10.4)

enum QueueNameTruncation {
    /// Characters kept after the ellipsis for `kept` characters in all: min(9, kept / 2).
    static func tailCount(forKept kept: Int) -> Int {
        min(DWBMetrics.queueNameTailMax, kept / 2)
    }

    /// Drops one character at a time, keeping `tailCount` after the ellipsis, until `fits`.
    static func truncated(_ name: String, fits: (String) -> Bool) -> String {
        if fits(name) { return name }
        let characters = Array(name)
        var kept = characters.count - 1
        while kept > 0 {
            let tail = tailCount(forKept: kept)
            let head = kept - tail
            let candidate = String(characters[..<head]) + "…" + String(characters[(characters.count - tail)...])
            if fits(candidate) { return candidate }
            kept -= 1
        }
        return "…"
    }

    /// The same rule on an attributed name: prefix color, weight and every other attribute stay on the
    /// characters that are kept. The ellipsis takes the attributes of the first character after it.
    static func truncated(_ text: NSAttributedString, toFit width: CGFloat) -> NSAttributedString {
        guard width > 0, ceil(text.size().width) > width else { return text }
        let string = text.string
        let characters = Array(string)
        func utf16Range(_ range: Range<Int>) -> NSRange {
            let lower = string.index(string.startIndex, offsetBy: range.lowerBound)
            let upper = string.index(string.startIndex, offsetBy: range.upperBound)
            return NSRange(lower..<upper, in: string)
        }
        func build(head: Int, tail: Int) -> NSAttributedString {
            let result = NSMutableAttributedString()
            if head > 0 { result.append(text.attributedSubstring(from: utf16Range(0..<head))) }
            let tailStart = characters.count - tail
            let anchor = tail > 0 ? tailStart : max(0, head - 1)
            let anchorLocation = utf16Range(0..<anchor).length
            let attributes = text.length > 0
                ? text.attributes(at: min(anchorLocation, text.length - 1), effectiveRange: nil) : [:]
            result.append(NSAttributedString(string: "…", attributes: attributes))
            if tail > 0 { result.append(text.attributedSubstring(from: utf16Range(tailStart..<characters.count))) }
            return result
        }
        var kept = characters.count - 1
        while kept > 0 {
            let tail = tailCount(forKept: kept)
            let candidate = build(head: kept - tail, tail: tail)
            if ceil(candidate.size().width) <= width { return candidate }
            kept -= 1
        }
        return build(head: 0, tail: 0)
    }
}
