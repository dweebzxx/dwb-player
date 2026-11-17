import AppKit

/// Pure presentation rules for the Queue Page, taken from `tokens-and-specs.md`
/// section 10 ("Queue panel (active look)"). No views, no UserDefaults. Geometry lives in
/// `QueuePanelLayout.swift`; every number comes from `DWBMetrics`.

enum QueuePanelMetrics {
    static let headerHeight = DWBMetrics.queueHeaderHeight

    /// The resize grab zone reaches this far to each side of the shared edge (8 pt in all).
    static let resizeGrabZoneHalfWidth: CGFloat = DWBMetrics.queueDividerHitWidth / 2

    /// 10 pt caps captions elsewhere in the app (Settings group captions) track at +4%.
    /// The Queue Page's own section labels do not track (§10.3).
    static let sectionLabelKern: CGFloat = 0.4

    static let panelMinimumWidth = DWBMetrics.queuePanelMinWidth
}

/// Windowed Queue Page width. Pure arithmetic; the player window owns the custom fraction.
/// The player's own formula (§10.1): max(260, 45% of the content width), at least 200 when dragged.
enum QueuePanelWidthPolicy {
    /// The default width, which is also the widest a drag can make the panel.
    static func maximumWidth(contentWidth: CGFloat) -> CGFloat {
        DWBMetrics.queuePanelMaxWidth(contentWidth: contentWidth, isPlayer: true)
    }

    static func clampedWidth(_ proposed: CGFloat, contentWidth: CGFloat) -> CGFloat {
        min(max(proposed, DWBMetrics.queuePanelMinWidth), maximumWidth(contentWidth: contentWidth))
    }

    /// The panel width for a content width and an optional custom fraction of it.
    static func width(contentWidth: CGFloat, customFraction: CGFloat?) -> CGFloat {
        guard let customFraction else { return maximumWidth(contentWidth: contentWidth) }
        return clampedWidth(contentWidth * customFraction, contentWidth: contentWidth)
    }

    /// The fraction to store for a dragged edge at `edgeX` (the panel's left edge, from the
    /// content view's left side), or nil when the clamped width is within the snap tolerance of the maximum.
    static func customFraction(forEdgeX edgeX: CGFloat, contentWidth: CGFloat) -> CGFloat? {
        guard contentWidth > 0 else { return nil }
        let width = clampedWidth(contentWidth - edgeX, contentWidth: contentWidth)
        if width >= maximumWidth(contentWidth: contentWidth) - DWBMetrics.queuePanelSnapTolerance { return nil }
        return width / contentWidth
    }

    /// The fraction after a keyboard nudge of the divider: `delta` points wider (positive) or
    /// narrower from `currentWidth`, through the same clamp and snap as a drag.
    static func customFraction(afterResizingBy delta: CGFloat, currentWidth: CGFloat, contentWidth: CGFloat) -> CGFloat? {
        customFraction(forEdgeX: contentWidth - (currentWidth + delta), contentWidth: contentWidth)
    }
}

/// How one row looks, from the states it can be in. Two shapes (the flat row and the playing
/// card) share one set of states; selection wins over hover, and the playing card keeps its fill.
struct QueueRowAppearance: Equatable {
    enum Fill: Equatable { case none, accentTintStrong, overlaySelected, overlayHover }
    /// `quiet` = 0.5 pt Border (playing card at rest); `borderStrongHairline` = 0.5 pt BorderStrong
    /// (playing card on hover); `borderStrong` = 1 pt BorderStrong (selected).
    enum Edge: Equatable {
        case none, quiet, borderStrongHairline, borderStrong

        var lineWidth: CGFloat {
            switch self {
            case .none: return 0
            case .quiet, .borderStrongHairline: return DWBMetrics.queuePlayingEdge
            case .borderStrong: return 1
            }
        }
    }
    enum LeadingGlyph: Equatable { case none, playing, failed }

    let fill: Fill
    let edge: Edge
    let showsCurrentBar: Bool
    /// The 0.5 pt gridLine under a flat row. Never on the playing card, a selected row, or the row
    /// right above a selected one, so nothing crosses a selected edge.
    let showsSeparator: Bool
    let leadingGlyph: LeadingGlyph
    let showsBookmark: Bool
    let metadataIsError: Bool
    let filenameIsDimmed: Bool
    let filenameWeight: NSFont.Weight

    static func make(isCurrent: Bool,
                     isSelected: Bool,
                     isHovering: Bool,
                     isFailed: Bool,
                     isBookmarked: Bool,
                     isNextRowSelected: Bool = false) -> QueueRowAppearance {
        let fill: Fill = isCurrent ? .accentTintStrong
            : isSelected ? .overlaySelected
            : isHovering ? .overlayHover
            : .none
        let edge: Edge
        if isSelected {
            edge = .borderStrong
        } else if isCurrent {
            edge = isHovering ? .borderStrongHairline : .quiet
        } else {
            edge = .none
        }
        let glyph: LeadingGlyph = isCurrent ? .playing : (isFailed ? .failed : .none)
        return QueueRowAppearance(fill: fill,
                                  edge: edge,
                                  showsCurrentBar: isCurrent,
                                  showsSeparator: !isCurrent && !isSelected && !isNextRowSelected,
                                  leadingGlyph: glyph,
                                  showsBookmark: isBookmarked,
                                  metadataIsError: isFailed,
                                  filenameIsDimmed: isFailed,
                                  filenameWeight: isCurrent ? .semibold : .medium)
    }
}

/// Section rows are either a sentence-case label or a one-line note ("No previous").
enum QueueSectionLabelStyle: Equatable {
    case label
    case note

    /// The projection names its sections in caps ("NOW PLAYING"); anything else is a note.
    static func style(forTitle title: String) -> QueueSectionLabelStyle {
        title == title.uppercased() ? .label : .note
    }

    /// What the row shows: "Previous", "Now playing", "Up next"; a note is shown as it is.
    static func displayText(forTitle title: String) -> String {
        guard style(forTitle: title) == .label else { return title }
        let lowered = title.lowercased()
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
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

/// One marker section (`N` or `M`) in the footer's actions row.
struct QueueMarkerState: Equatable {
    enum Kind: Equatable { case primary, secondary }
    /// State is a mark, never a fill: a solid dot when every target has the prefix, a ring when only
    /// some do, nothing otherwise.
    enum Mark: Equatable { case none, applied, mixed }

    let kind: Kind
    /// The normalized prefix, which is also what pressing the section applies.
    let prefix: String
    let label: String
    let isBlank: Bool
    let isApplied: Bool
    let isMixed: Bool
    let isEnabled: Bool

    var mark: Mark { isApplied ? .applied : (isMixed ? .mixed : .none) }

    /// The key that does the same as the section. Used only in tooltips; nothing draws it.
    var keyTag: String { kind == .primary ? "N" : "M" }

    private var kindName: String { kind == .primary ? "primary" : "secondary" }
    private var otherKindName: String { kind == .primary ? "secondary" : "primary" }

    /// The label: the first 8 characters of the normalized prefix, plus "…" when it is
    /// longer, or "—" when blank.
    static func label(forPrefix prefix: String) -> String {
        let t = PrefixNormalization.normalized(prefix)
        if t.isEmpty { return "—" }
        return t.count <= 8 ? t : String(t.prefix(8)) + "…"
    }

    /// "Applied" when it has a prefix and every targeted file already starts with it.
    static func isApplied(prefix: String, targetNames: [String]) -> Bool {
        let t = PrefixNormalization.normalized(prefix)
        guard !t.isEmpty, !targetNames.isEmpty else { return false }
        return targetNames.allSatisfy { $0.hasPrefix(t) }
    }

    /// "Mixed" when it has a prefix and some, but not all, targeted files start with it.
    static func isMixed(prefix: String, targetNames: [String]) -> Bool {
        let t = PrefixNormalization.normalized(prefix)
        guard !t.isEmpty, !targetNames.isEmpty else { return false }
        let matching = targetNames.filter { $0.hasPrefix(t) }.count
        return matching > 0 && matching < targetNames.count
    }

    /// A section is clickable only with a non-blank prefix and at least one item in the queue.
    static func isEnabled(prefix: String, queueHasItems: Bool) -> Bool {
        queueHasItems && !PrefixNormalization.normalized(prefix).isEmpty
    }

    /// The secondary section is not offered when it equals a non-empty primary prefix.
    static func secondaryIsShown(primary: String, secondary: String) -> Bool {
        let p = PrefixNormalization.normalized(primary)
        let s = PrefixNormalization.normalized(secondary)
        return s.isEmpty || s != p
    }

    /// `targetNames` are the selected files, or the playing file when nothing is selected. With
    /// nothing targeted the section is disabled.
    static func make(kind: Kind, prefix: String, targetNames: [String], queueHasItems: Bool) -> QueueMarkerState {
        let t = PrefixNormalization.normalized(prefix)
        return QueueMarkerState(kind: kind,
                                prefix: t,
                                label: label(forPrefix: prefix),
                                isBlank: t.isEmpty,
                                isApplied: isApplied(prefix: prefix, targetNames: targetNames),
                                isMixed: isMixed(prefix: prefix, targetNames: targetNames),
                                isEnabled: isEnabled(prefix: prefix, queueHasItems: queueHasItems && !targetNames.isEmpty))
    }

    var tooltip: String {
        if isBlank { return "No \(kindName) prefix set. Set one in Settings > Queue & Files." }
        return "\(kindName.capitalized) prefix “\(prefix)”: add it to the selected file, press again to remove it, or replace the \(otherKindName) prefix. Shortcut: \(keyTag)"
    }

    var accessibilityLabel: String {
        if isBlank { return "\(kindName.capitalized) prefix not set" }
        return "Apply \(kindName) prefix \(prefix) to selected file"
    }

    /// "applied", "mixed" (only some selected files have it) or "not applied"; a blank section has no value.
    var accessibilityValue: String? {
        if isBlank { return nil }
        switch mark {
        case .applied: return "applied"
        case .mixed: return "mixed, some selected files have it"
        case .none: return "not applied"
        }
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
            && QueueMarkerState.secondaryIsShown(primary: primary, secondary: secondary)
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

/// One snapshot drives rail compression, utility selection, and the rendered overflow.
/// Width is the media rail's bounds, including the space left by Queue Page.
struct RailOverflowModel: Equatable {
    enum Action: Equatable { case customPrefix, customPrefixSecondary, shuffle, replay, bookmark, settings }
    enum Utility: Equatable { case hidden, settings, more }
    struct Item: Equatable {
        let action: Action
        let title: String
        let isOn: Bool
        let isEnabled: Bool
    }
    struct Input {
        var width: CGFloat
        var primary = ""
        var secondary = ""
        var showPrefixes = true
        var showShuffle = true
        var showRepeat = true
        var showBookmark = true
        var showVolume = true
        var canRename = false
        var canShuffle = false
        var shuffleOn = false
        var repeatOn = false
        var hasItem = false
        var bookmarked = false
    }

    let primaryHidden: Bool
    let secondaryHidden: Bool
    let shuffleHidden: Bool
    let repeatHidden: Bool
    let bookmarkHidden: Bool
    let volumeHidden: Bool
    let skipHidden: Bool
    let previousNextHidden: Bool
    let timeHidden: Bool
    let utility: Utility
    /// Empty for direct Settings or suppressed utility; Settings is last otherwise.
    let items: [Item]

    init(_ input: Input) {
        primaryHidden = !RailPrefixButtons.showsPrimary(primary: input.primary, prefixButtonsEnabled: input.showPrefixes) || input.width < 500
        secondaryHidden = !RailPrefixButtons.showsSecondary(primary: input.primary, secondary: input.secondary, prefixButtonsEnabled: input.showPrefixes) || input.width < 540
        shuffleHidden = !input.showShuffle || input.width < 430
        repeatHidden = !input.showRepeat || input.width < 390
        bookmarkHidden = !input.showBookmark || input.width < 560
        volumeHidden = !input.showVolume || input.width < 360
        skipHidden = input.width < 360
        previousNextHidden = input.width < 280
        timeHidden = input.width < 640
        var actions: [Item] = []
        if RailPrefixButtons.showsInMoreMenu(.primary, primary: input.primary, secondary: input.secondary,
                                            prefixButtonsEnabled: input.showPrefixes, buttonIsHidden: primaryHidden) {
            actions.append(Item(action: .customPrefix, title: RailPrefixButtons.label(forPrefix: input.primary), isOn: false, isEnabled: input.canRename))
        }
        if RailPrefixButtons.showsInMoreMenu(.secondary, primary: input.primary, secondary: input.secondary,
                                            prefixButtonsEnabled: input.showPrefixes, buttonIsHidden: secondaryHidden) {
            actions.append(Item(action: .customPrefixSecondary, title: RailPrefixButtons.label(forPrefix: input.secondary), isOn: false, isEnabled: input.canRename))
        }
        // Unlike prefixes, these actions remain eligible when their preference is off.
        if shuffleHidden { actions.append(Item(action: .shuffle, title: "Shuffle", isOn: input.shuffleOn, isEnabled: input.canShuffle)) }
        if repeatHidden { actions.append(Item(action: .replay, title: "Repeat one", isOn: input.repeatOn, isEnabled: true)) }
        if bookmarkHidden { actions.append(Item(action: .bookmark, title: "Bookmark", isOn: input.bookmarked, isEnabled: input.hasItem)) }
        utility = input.width < 330 ? .hidden : actions.isEmpty ? .settings : .more
        items = utility == .more ? actions + [Item(action: .settings, title: "Settings", isOn: false, isEnabled: true)] : []
    }
}

/// Routing for the prefix and rename shortcuts. Which key runs each command comes from the
/// command table (`ShortcutCommands.swift`); this maps the command to the action.
enum PrefixKeyRouting {
    enum Action: Equatable { case primaryPrefix, secondaryPrefix, rename }

    /// The action of a prefix or rename command, never while a text field is being edited.
    static func action(for command: ShortcutCommandID?, isEditingText: Bool) -> Action? {
        guard !isEditingText, let command else { return nil }
        switch command {
        case .togglePrimaryPrefix:   return .primaryPrefix
        case .toggleSecondaryPrefix: return .secondaryPrefix
        case .renameFile:            return .rename
        default:                     return nil
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

/// The two filtered empty states (§10.6): a neutral 44 pt circle with a glyph, the title and one
/// button. (An empty queue keeps its own state with the faded app icon.)
enum QueueFilteredEmptyState: Equatable {
    case noMatches
    case noBookmarks

    static let circleDiameter = DWBMetrics.queueEmptyCircle
    static let glyphSize = DWBMetrics.queueEmptyGlyph

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
        case .noBookmarks: return "bookmark"
        }
    }
}
