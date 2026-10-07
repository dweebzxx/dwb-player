import AppKit

/// Pure presentation rules for the Queue Page, taken from `tokens-and-specs.md`
/// section 5 ("Queue panel" and "File markers"). No views, no UserDefaults.

enum QueuePanelMetrics {
    static let headerHeight = DWBMetrics.queueHeaderHeight
    static let searchPillHeight: CGFloat = 28
    static let headerButton: CGFloat = 26

    static let rowHeight = DWBMetrics.queueRowHeight
    static let rowInset = DWBMetrics.queueRowInset
    /// A table row holds the 56 pt pill plus the 4 pt inset above and below it.
    static var tableRowHeight: CGFloat { rowHeight + rowInset * 2 }
    static let sectionRowHeight: CGFloat = 28
    static let listLeadingInset: CGFloat = 12
    static let listTrailingInset: CGFloat = 8

    static let currentBarWidth: CGFloat = 3
    static let currentBarLeading: CGFloat = 4
    static let currentBarVerticalInset: CGFloat = 10
    static let currentBarRadius: CGFloat = 2
    static let playGlyphSize: CGFloat = 11
    static let failedGlyphSize: CGFloat = 12
    static let bookmarkGlyphSize: CGFloat = 12
    static let glyphSlotWidth: CGFloat = 14
    static let rowLeadingPadding: CGFloat = 12
    static let rowTrailingPadding: CGFloat = 10
    static let rowContentGap: CGFloat = 8
    static let titleMetaGap: CGFloat = 3
    /// Gap between the filename and the Play Next tag that follows it.
    static let titleTagGap: CGFloat = 6

    static let sectionLabelKern: CGFloat = 0.4          // +4% of 10 pt

    static let footerPillHeight: CGFloat = 26
    static let markerGroupHeight: CGFloat = 28
    static let markerChipHeight: CGFloat = 22
    static let markerGroupPadding: CGFloat = 3
    static let footerHorizontalPadding: CGFloat = 12
    static let footerRowGap: CGFloat = 8
    static let footerTopPadding: CGFloat = 8
    /// 4 pt below the marker row plus 4 pt above the action row, as in `QueueFooter.jsx`.
    static let footerRowSpacing: CGFloat = 8
    static let footerBottomPadding: CGFloat = 10
    static let compactIconPillWidth: CGFloat = 28
    static let compactIconsBelowWidth: CGFloat = 390

    /// Height of the footer, border excluded.
    static func footerHeight(showsMarkerRow: Bool) -> CGFloat {
        let actionRow = footerPillHeight + footerBottomPadding
        guard showsMarkerRow else { return footerTopPadding + actionRow }
        return footerTopPadding + markerGroupHeight + footerRowSpacing + actionRow
    }

    /// The rounded row shape inside a full-width table row. `visibleWidth` is the part of
    /// the row the clip view actually shows; a legacy scroller can make the table row wider
    /// than that, and the 8 pt trailing inset has to land inside the visible part.
    static func pillRect(inRowBounds bounds: NSRect, visibleWidth: CGFloat? = nil) -> NSRect {
        let shown = min(bounds.width, (visibleWidth ?? bounds.width) > 0 ? (visibleWidth ?? bounds.width) : bounds.width)
        return NSRect(x: bounds.minX + listLeadingInset,
                      y: bounds.minY + rowInset,
                      width: max(0, shown - listLeadingInset - listTrailingInset),
                      height: max(0, bounds.height - rowInset * 2))
    }
}

/// How one row looks, from the states it can be in (six states share one anatomy).
struct QueueRowAppearance: Equatable {
    enum Fill: Equatable { case none, accentTint, overlaySelected, overlayHover }
    enum Edge: Equatable { case gridLine, accentFill, borderStrong }
    enum LeadingGlyph: Equatable { case none, playing, failed }

    let fill: Fill
    let edge: Edge
    let showsCurrentBar: Bool
    let leadingGlyph: LeadingGlyph
    let showsBookmark: Bool
    let metadataIsError: Bool
    let filenameIsDimmed: Bool
    let filenameWeight: NSFont.Weight

    static func make(isCurrent: Bool,
                     isSelected: Bool,
                     isHovering: Bool,
                     isFailed: Bool,
                     isBookmarked: Bool) -> QueueRowAppearance {
        let fill: Fill = isCurrent ? .accentTint
            : isSelected ? .overlaySelected
            : isHovering ? .overlayHover
            : .none
        let edge: Edge = isSelected ? .borderStrong
            : isCurrent ? .accentFill
            : .gridLine
        let glyph: LeadingGlyph = isCurrent ? .playing : (isFailed ? .failed : .none)
        return QueueRowAppearance(fill: fill,
                                  edge: edge,
                                  showsCurrentBar: isCurrent,
                                  leadingGlyph: glyph,
                                  showsBookmark: isBookmarked,
                                  metadataIsError: isFailed,
                                  filenameIsDimmed: isFailed,
                                  filenameWeight: isCurrent ? .semibold : .medium)
    }
}

/// Section rows are either a caps label or a one-line note ("No previous").
enum QueueSectionLabelStyle: Equatable {
    case capsLabel
    case emptyNote

    static func style(forTitle title: String) -> QueueSectionLabelStyle {
        title == title.uppercased() ? .capsLabel : .emptyNote
    }
}

/// One marker chip (`N` or `M`) in the footer group.
struct QueueMarkerChipState: Equatable {
    enum Kind: Equatable { case primary, secondary }

    let kind: Kind
    let label: String
    let isBlank: Bool
    let isApplied: Bool
    let isEnabled: Bool

    var keyTag: String { kind == .primary ? "N" : "M" }

    static func trimmed(_ prefix: String) -> String {
        prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The existing prefix-button label: the trimmed prefix up to 8 characters, or "—" when blank.
    static func label(forPrefix prefix: String) -> String {
        let t = trimmed(prefix)
        if t.isEmpty { return "—" }
        return t.count <= 8 ? t : String(t.prefix(8)) + "…"
    }

    /// A chip reads "applied" when it has a prefix and every targeted file already starts with it.
    static func isApplied(prefix: String, targetNames: [String]) -> Bool {
        let t = trimmed(prefix)
        guard !t.isEmpty, !targetNames.isEmpty else { return false }
        return targetNames.allSatisfy { $0.hasPrefix(t) }
    }

    static func make(kind: Kind, prefix: String, targetNames: [String]) -> QueueMarkerChipState {
        let blank = trimmed(prefix).isEmpty
        return QueueMarkerChipState(kind: kind,
                                    label: label(forPrefix: prefix),
                                    isBlank: blank,
                                    isApplied: isApplied(prefix: prefix, targetNames: targetNames),
                                    isEnabled: !blank)
    }
}

/// Which footer variant fits the width. Compact icons keep the old 390 pt rule; the
/// chip group shortens Undo to its glyph first, then hands the prefix actions to the
/// More menu when even that does not fit.
struct QueueFooterLayoutPlan: Equatable {
    var usesCompactIcons: Bool
    var usesCompactUndo: Bool
    var usesPrefixOverflow: Bool

    static func make(width: CGFloat,
                     hasPrefixActions: Bool,
                     removeButtonWidth: CGFloat,
                     fullGroupWidth: CGFloat,
                     compactUndoGroupWidth: CGFloat) -> QueueFooterLayoutPlan {
        let compactIcons = width < QueuePanelMetrics.compactIconsBelowWidth
        let available = width
            - QueuePanelMetrics.footerHorizontalPadding * 2
            - removeButtonWidth
            - QueuePanelMetrics.footerRowGap
        if fullGroupWidth <= available {
            return QueueFooterLayoutPlan(usesCompactIcons: compactIcons, usesCompactUndo: false, usesPrefixOverflow: false)
        }
        if compactUndoGroupWidth <= available {
            return QueueFooterLayoutPlan(usesCompactIcons: compactIcons, usesCompactUndo: true, usesPrefixOverflow: false)
        }
        return QueueFooterLayoutPlan(usesCompactIcons: compactIcons, usesCompactUndo: true, usesPrefixOverflow: hasPrefixActions)
    }
}

// MARK: - Queue interactions (`tokens-and-specs.md` 9.7)

/// The search highlight: the first case- and accent-insensitive match of the query in a
/// filename, the same comparison the search filter uses.
enum QueueSearchHighlight {
    static func firstMatch(in name: String, query: String) -> NSRange? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              let range = name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        return NSRange(range, in: name)
    }
}

/// The two filtered empty states: a neutral 44 pt circle with a glyph, the title and one
/// button. (An empty queue keeps its own state with the app icon.)
enum QueueFilteredEmptyState: Equatable {
    case noMatches
    case noBookmarks

    static let circleDiameter: CGFloat = 44
    static let glyphSize: CGFloat = 18

    /// A search query always reads as "no matching files"; only a bookmark filter on its own
    /// reads as "no bookmarked media".
    static func make(query: String, bookmarkFilterEnabled: Bool) -> QueueFilteredEmptyState {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return bookmarkFilterEnabled && !hasQuery ? .noBookmarks : .noMatches
    }

    var title: String {
        switch self {
        case .noMatches: return "No matching files"
        case .noBookmarks: return "No bookmarked media"
        }
    }

    var actionTitle: String {
        switch self {
        case .noMatches: return "Clear Search"
        case .noBookmarks: return "Show All Media"
        }
    }

    var symbolName: String {
        switch self {
        case .noMatches: return "magnifyingglass"
        case .noBookmarks: return "bookmark.slash"
        }
    }
}

/// The drop line shown between rows while drag-reordering in Manual sort: a 2 pt line in
/// the row gap with an 8 pt ring at its leading edge, inset 4 pt from the row edges.
enum QueueDropIndicatorMetrics {
    static let sideInset: CGFloat = 4
    static let lineHeight = DWBMetrics.dropLine
    static let ringDiameter = DWBMetrics.dropRing
    static let ringBorder: CGFloat = 2
    /// The dragged row stays in the list at this alpha.
    static let draggedRowAlpha: CGFloat = 0.4

    /// Ring and line inside a view `width` wide and one ring tall. The line starts under the
    /// ring (1 pt in from its far edge) and runs to the trailing edge.
    static func geometry(width: CGFloat) -> (ring: NSRect, line: NSRect) {
        let ring = NSRect(x: 0, y: 0, width: ringDiameter, height: ringDiameter)
        let lineX = ringDiameter - 1
        let line = NSRect(x: lineX,
                          y: (ringDiameter - lineHeight) / 2,
                          width: max(0, width - lineX),
                          height: lineHeight)
        return (ring, line)
    }
}
