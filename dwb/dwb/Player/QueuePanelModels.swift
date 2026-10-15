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
    /// One pill radius for the group outline and every highlight inside it: the applied chip
    /// fill and edge, the chip hover fill and Undo's hover fill.
    static let markerGroupCornerRadius: CGFloat = DWBMetrics.radiusPill
    static let markerHighlightCornerRadius: CGFloat = markerGroupCornerRadius
    static let footerHorizontalPadding: CGFloat = 12
    /// Gap between items in one footer row.
    static let footerRowGap: CGFloat = 8
    static let footerTopPadding: CGFloat = 8
    /// Gap between footer rows.
    static let footerRowSpacing: CGFloat = 6
    static let footerBottomPadding: CGFloat = 10
    static let footerRemoveButtonSize: CGFloat = 26
    /// The total label's own row, used when it does not fit beside Rescan and Clear Queue.
    static let footerTotalRowHeight: CGFloat = 16
    static let footerDividerWidth: CGFloat = 1
    static let compactIconPillWidth: CGFloat = 28
    static let compactIconsBelowWidth: CGFloat = 390

    /// Height of the footer, border excluded: the Remove row (with the marker group beside it,
    /// or the group on its own row below), an optional total-label row, and the Rescan row.
    static func footerHeight(plan: QueueFooterLayoutPlan) -> CGFloat {
        var height = footerTopPadding
        if plan.groupWraps {
            height += footerRemoveButtonSize + footerRowSpacing + markerGroupHeight
        } else {
            height += markerGroupHeight
        }
        if plan.totalOnOwnRow { height += footerRowSpacing + footerTotalRowHeight }
        height += footerRowSpacing + footerPillHeight + footerBottomPadding
        return height
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

/// The one rule for a stored prefix, shared by the Settings accessors and every reader.
enum PrefixNormalization {
    /// Trim whitespace and newlines; an empty result is blank (""). Otherwise remove every
    /// trailing "_" and add exactly one: "keep", "keep_" and "keep__" all give "keep_".
    static func normalized(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var body = Substring(trimmed)
        while body.last == "_" { body = body.dropLast() }
        return String(body) + "_"
    }
}

/// One marker chip (`N` or `M`) in the footer group.
struct QueueMarkerChipState: Equatable {
    enum Kind: Equatable { case primary, secondary }

    let kind: Kind
    /// The normalized prefix, which is also what pressing the chip applies.
    let prefix: String
    let label: String
    let isBlank: Bool
    let isApplied: Bool
    let isEnabled: Bool

    /// The key that does the same as the chip. Used only in tooltips; nothing draws it.
    var keyTag: String { kind == .primary ? "N" : "M" }

    private var kindName: String { kind == .primary ? "primary" : "secondary" }
    private var otherKindName: String { kind == .primary ? "secondary" : "primary" }

    /// The chip label: the first 8 characters of the normalized prefix, plus "…" when it is
    /// longer, or "—" when blank.
    static func label(forPrefix prefix: String) -> String {
        let t = PrefixNormalization.normalized(prefix)
        if t.isEmpty { return "—" }
        return t.count <= 8 ? t : String(t.prefix(8)) + "…"
    }

    /// A chip reads "applied" when it has a prefix and every targeted file already starts with it.
    static func isApplied(prefix: String, targetNames: [String]) -> Bool {
        let t = PrefixNormalization.normalized(prefix)
        guard !t.isEmpty, !targetNames.isEmpty else { return false }
        return targetNames.allSatisfy { $0.hasPrefix(t) }
    }

    /// A chip is clickable only with a non-blank prefix and at least one item in the queue.
    static func isEnabled(prefix: String, queueHasItems: Bool) -> Bool {
        queueHasItems && !PrefixNormalization.normalized(prefix).isEmpty
    }

    /// The secondary chip is not offered when it equals a non-empty primary prefix.
    static func secondaryIsShown(primary: String, secondary: String) -> Bool {
        let p = PrefixNormalization.normalized(primary)
        let s = PrefixNormalization.normalized(secondary)
        return s.isEmpty || s != p
    }

    static func make(kind: Kind, prefix: String, targetNames: [String], queueHasItems: Bool) -> QueueMarkerChipState {
        let t = PrefixNormalization.normalized(prefix)
        return QueueMarkerChipState(kind: kind,
                                    prefix: t,
                                    label: label(forPrefix: prefix),
                                    isBlank: t.isEmpty,
                                    isApplied: isApplied(prefix: prefix, targetNames: targetNames),
                                    isEnabled: isEnabled(prefix: prefix, queueHasItems: queueHasItems))
    }

    var tooltip: String {
        if isBlank { return "No \(kindName) prefix set. Set one in Settings > Queue & Files." }
        return "\(kindName.capitalized) prefix “\(prefix)”: add it to the selected file, press again to remove it, or replace the \(otherKindName) prefix. Shortcut: \(keyTag)"
    }

    var accessibilityLabel: String {
        if isBlank { return "\(kindName.capitalized) prefix not set" }
        return "Apply \(kindName) prefix \(prefix) to selected file"
    }

    /// "applied" or "not applied"; a blank chip has no value.
    var accessibilityValue: String? {
        isBlank ? nil : (isApplied ? "applied" : "not applied")
    }
}

/// Which footer variant fits the width. The marker group sits beside Remove with full
/// Undo, then with glyph-only Undo, then wraps to its own row (full Undo if it fits that
/// row, else glyph-only). Nothing moves into a menu. The total label takes its own row
/// when it does not fit between Rescan and Clear Queue.
struct QueueFooterLayoutPlan: Equatable {
    var usesCompactIcons: Bool
    var usesCompactUndo: Bool
    var groupWraps: Bool
    var totalOnOwnRow: Bool

    static func usesCompactIcons(width: CGFloat) -> Bool {
        width < QueuePanelMetrics.compactIconsBelowWidth
    }

    /// All widths are in points. `rescanWidth` and `clearWidth` are the widths at the
    /// compact-icon setting that `usesCompactIcons(width:)` gives for `width`.
    static func make(width: CGFloat,
                     removeButtonWidth: CGFloat,
                     fullGroupWidth: CGFloat,
                     compactUndoGroupWidth: CGFloat,
                     rescanWidth: CGFloat,
                     totalWidth: CGFloat,
                     clearWidth: CGFloat) -> QueueFooterLayoutPlan {
        let gap = QueuePanelMetrics.footerRowGap
        let rowWidth = width - QueuePanelMetrics.footerHorizontalPadding * 2
        let besideRemove = rowWidth - removeButtonWidth - gap

        var compactUndo = false
        var wraps = false
        if fullGroupWidth <= besideRemove {
            compactUndo = false
        } else if compactUndoGroupWidth <= besideRemove {
            compactUndo = true
        } else {
            wraps = true
            compactUndo = fullGroupWidth > rowWidth
        }

        // Rescan, total, divider, Clear Queue: three gaps between four items.
        let inlineTotalRow = rescanWidth + totalWidth + QueuePanelMetrics.footerDividerWidth + clearWidth + gap * 3
        return QueueFooterLayoutPlan(usesCompactIcons: usesCompactIcons(width: width),
                                     usesCompactUndo: compactUndo,
                                     groupWraps: wraps,
                                     totalOnOwnRow: inlineTotalRow > rowWidth)
    }
}

/// The footer's single total label.
enum QueueFooterText {
    static func itemCountText(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// `Total: <duration> | <N> items`, or `Total: <duration> | <v>/<N> shown` while a
    /// search or filter is active.
    static func total(duration: String, itemCount: Int, visibleCount: Int, isFiltered: Bool) -> String {
        if isFiltered {
            return "Total: \(duration) | \(visibleCount)/\(itemCount) shown"
        }
        return "Total: \(duration) | \(itemCountText(itemCount))"
    }
}

/// The playback rail's primary and secondary prefix buttons.
enum RailPrefixButtons {
    /// The first character of the normalized prefix plus "_", or "" when blank.
    static func label(forPrefix prefix: String) -> String {
        let t = PrefixNormalization.normalized(prefix)
        guard let first = t.first else { return "" }
        return "\(first)_"
    }

    static func showsPrimary(primary: String, prefixButtonsEnabled: Bool) -> Bool {
        prefixButtonsEnabled && !PrefixNormalization.normalized(primary).isEmpty
    }

    static func showsSecondary(primary: String, secondary: String, prefixButtonsEnabled: Bool) -> Bool {
        prefixButtonsEnabled
            && !PrefixNormalization.normalized(secondary).isEmpty
            && QueueMarkerChipState.secondaryIsShown(primary: primary, secondary: secondary)
    }

    enum Slot { case primary, secondary }

    /// The More menu lists a prefix action only when the "Prefix buttons" setting is on and
    /// that rail button is hidden for lack of width. With the setting off the menu has none.
    static func showsInMoreMenu(_ slot: Slot,
                                primary: String,
                                secondary: String,
                                prefixButtonsEnabled: Bool,
                                buttonIsHidden: Bool) -> Bool {
        guard buttonIsHidden else { return false }
        switch slot {
        case .primary:   return showsPrimary(primary: primary, prefixButtonsEnabled: prefixButtonsEnabled)
        case .secondary: return showsSecondary(primary: primary, secondary: secondary, prefixButtonsEnabled: prefixButtonsEnabled)
        }
    }
}

/// Plain-key routing for the prefix and rename shortcuts.
enum PrefixKeyRouting {
    enum Action: Equatable { case primaryPrefix, secondaryPrefix, rename }

    /// `N`, `M` and `R` with no modifier, never while a text field is being edited.
    static func action(forCharacters characters: String?,
                       hasModifiers: Bool,
                       isEditingText: Bool) -> Action? {
        guard !hasModifiers, !isEditingText, let characters else { return nil }
        switch characters.lowercased() {
        case "n": return .primaryPrefix
        case "m": return .secondaryPrefix
        case "r": return .rename
        default:  return nil
        }
    }

    /// `R` renames the one selected row. With none or several selected it returns nil and the
    /// caller renames the current file.
    static func selectedRenameRow(selectedDisplayIndices: [Int]) -> Int? {
        selectedDisplayIndices.count == 1 ? selectedDisplayIndices[0] : nil
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
