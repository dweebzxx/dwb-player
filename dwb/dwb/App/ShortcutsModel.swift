import Foundation

/// The data behind Settings > Shortcuts: every shortcut player has, grouped by task,
/// plus the search filter and the keyboard-map layout. Pure values, no views.
///
/// Titles and key text are the app's existing copy, regrouped. Only shortcuts that
/// exist in player are listed.

enum ShortcutTone: Equatable {
    case accent
    case markerPrimary
    case markerSecondary
}

struct ShortcutEntry: Equatable {
    let action: String
    /// One entry per key cap shown on the row (for example `["←", "⌥←"]`).
    let keys: [String]
    var tone: ShortcutTone = .accent

    init(_ action: String, _ keys: String, tone: ShortcutTone = .accent) {
        self.action = action
        self.keys = keys.components(separatedBy: " / ")
        self.tone = tone
    }

    /// Keys of this entry that sit on the keyboard map (unmodified keys only).
    var mapKeys: [String] {
        keys.filter { ShortcutKeyboardLayout.allKeys.contains($0) }
    }
}

struct ShortcutGroup: Equatable {
    let title: String
    /// Set on the one group that only exists in player ("dwb player only").
    let appLabel: String?
    let items: [ShortcutEntry]

    init(_ title: String, appLabel: String? = nil, items: [ShortcutEntry]) {
        self.title = title
        self.appLabel = appLabel
        self.items = items
    }
}

enum ShortcutKeyboardLayout {
    /// Letter and punctuation rows, as in the design system's `ShortcutsPage`.
    static let rows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", "."]
    ]
    static let space = "Space"
    static let arrows = ["←", "↑", "↓", "→"]

    /// Key sizes in points: 26 × 24, with a 150 pt space bar.
    static let keyWidth: CGFloat = 26
    static let keyHeight: CGFloat = 24
    static let spaceWidth: CGFloat = 150

    static var allKeys: Set<String> {
        Set(rows.flatMap { $0 } + [space] + arrows)
    }

    /// Left indent of each letter row, in points (12 pt per row).
    static func rowIndent(_ index: Int) -> CGFloat { CGFloat(index) * 12 }
}

enum ShortcutsCatalog {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup("Playback", items: [
            ShortcutEntry("Play / Pause", "Space"),
            ShortcutEntry("Rewind by skip duration", "← / ⌥←"),
            ShortcutEntry("Forward by skip duration", "→ / ⌥→"),
            ShortcutEntry("Volume Up", "↑ / ⌘↑"),
            ShortcutEntry("Volume Down", "↓ / ⌘↓"),
            ShortcutEntry("Shuffle", "⌥⌘S"),
            ShortcutEntry("Endless Shuffle", "⌥⌘E"),
            ShortcutEntry("Repeat One", "⌥⌘R")
        ]),
        ShortcutGroup("Navigation", items: [
            ShortcutEntry("Previous Item", ","),
            ShortcutEntry("Next Item", ".")
        ]),
        ShortcutGroup("File markers", items: [
            ShortcutEntry("Primary prefix (add / remove / replace)", "N", tone: .markerPrimary),
            ShortcutEntry("Secondary prefix (add / remove / replace)", "M", tone: .markerSecondary),
            ShortcutEntry("Rename current file…", "R"),
            ShortcutEntry("Undo last prefix change", "⌘Z")
        ]),
        ShortcutGroup("Queue & window", items: [
            ShortcutEntry("Open File", "⌘O"),
            ShortcutEntry("New Window", "⌘N"),
            ShortcutEntry("Four Window Grid", "⌘4"),
            ShortcutEntry("Fit", "⌘1"),
            ShortcutEntry("Fill", "⌘2"),
            ShortcutEntry("Stretch", "⌘3"),
            ShortcutEntry("Minimize", "⌘M"),
            ShortcutEntry("Reveal in Finder", "⇧⌘R"),
            ShortcutEntry("Clear Queue", "⇧⌘⌫"),
            ShortcutEntry("Remove selected queue rows", "Delete / Forward Delete"),
            ShortcutEntry("Open Settings", "⌘,"),
            ShortcutEntry("Move Settings sidebar selection", "↑ / ↓"),
            ShortcutEntry("Quit dwb player", "⌘Q")
        ]),
        ShortcutGroup("Skip & audio sync", appLabel: "dwb player", items: [
            ShortcutEntry("10 seconds", "1"),
            ShortcutEntry("30 seconds", "3"),
            ShortcutEntry("60 seconds", "6"),
            ShortcutEntry("3 minutes", "9"),
            ShortcutEntry("Bookmark Current Item", "B"),
            ShortcutEntry("Advance Audio (Play Sooner)", "[ / ⌘["),
            ShortcutEntry("Delay Audio (Play Later)", "] / ⌘]"),
            ShortcutEntry("Reset Audio Sync", "\\ / ⌘\\")
        ])
    ]
}

enum ShortcutsSearch {
    /// Keeps the rows whose action name or key text contains the query, ignoring case,
    /// and drops groups left empty. An empty query keeps everything.
    static func filter(_ groups: [ShortcutGroup], query: String) -> [ShortcutGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            let items = group.items.filter { matches($0, needle: needle) }
            return items.isEmpty ? nil : ShortcutGroup(group.title, appLabel: group.appLabel, items: items)
        }
    }

    static func matches(_ entry: ShortcutEntry, needle: String) -> Bool {
        let haystack = ([entry.action] + entry.keys).joined(separator: " ").lowercased()
        return haystack.contains(needle)
    }
}

/// Which keyboard-map keys have a shortcut, and the tone each takes.
enum ShortcutKeyMap {
    static func tones(for groups: [ShortcutGroup]) -> [String: ShortcutTone] {
        var result: [String: ShortcutTone] = [:]
        for entry in groups.flatMap(\.items) {
            for key in entry.mapKeys {
                // A marker tone is never replaced by the plain accent tone.
                if result[key] == nil || entry.tone != .accent {
                    result[key] = entry.tone
                }
            }
        }
        return result
    }
}
