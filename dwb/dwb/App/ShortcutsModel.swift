import Foundation

/// The data behind Settings > Shortcuts: the rows of the command table (`ShortcutCommands.swift`)
/// grouped by task, plus the search filter and the keyboard-map layout. Pure values, no views.

enum ShortcutTone: Equatable {
    case accent
    case markerPrimary
    case markerSecondary
}

/// One row on the page: a command with the keys that run it now.
struct ShortcutEntry: Equatable {
    let id: ShortcutCommandID
    let action: String
    /// The keys in assignment order, one key cap each.
    let keys: [ShortcutKey]
    /// Context text shown next to the action.
    let note: String?
    let isEditable: Bool
    var tone: ShortcutTone = .accent

    init(command: ShortcutCommand, keys: [ShortcutKey]) {
        self.id = command.id
        self.action = command.name
        self.keys = keys
        self.note = command.note
        self.isEditable = command.isEditable
        self.tone = command.tone
    }

    var keyTexts: [String] { keys.map(\.text) }

    /// Keys of this entry that sit on the keyboard map (unmodified keys only).
    var mapKeys: [String] { keys.compactMap(\.mapLabel) }
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
    /// The rows of Settings > Shortcuts, grouped by task, from the command table and the
    /// active keys. Groups with no command are left out.
    static func groups(bindings: ShortcutBindings = ShortcutRegistry.shared.bindings) -> [ShortcutGroup] {
        ShortcutGroupID.allCases.compactMap { group in
            let items = bindings.commands.filter { $0.group == group }.map {
                ShortcutEntry(command: $0, keys: bindings.activeKeys(for: $0.id))
            }
            return items.isEmpty ? nil : ShortcutGroup(group.title, appLabel: group.appLabel, items: items)
        }
    }

    /// The one place that answers "which keys run this action now": the key texts of the
    /// command table's active keys, in assignment order.
    static func currentKeys(for id: ShortcutCommandID,
                            in bindings: ShortcutBindings = ShortcutRegistry.shared.bindings) -> [String] {
        bindings.activeKeyTexts(for: id)
    }
}

enum ShortcutsSearch {
    /// Keeps the rows that match the query, ignoring case, and drops groups left empty. A
    /// group whose title matches keeps all its rows. An empty query keeps everything.
    static func filter(_ groups: [ShortcutGroup], query: String) -> [ShortcutGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.title.lowercased().contains(needle) { return group }
            let items = group.items.filter { matches($0, needle: needle) }
            return items.isEmpty ? nil : ShortcutGroup(group.title, appLabel: group.appLabel, items: items)
        }
    }

    /// A row matches on its action name, its keys (the symbols, such as `⌘`, and the spoken
    /// words, such as "command"), and its context text.
    static func matches(_ entry: ShortcutEntry, needle: String) -> Bool {
        var parts = [entry.action]
        parts += entry.keys.map(\.text)
        parts += entry.keys.map(\.spokenText)
        if let note = entry.note { parts.append(note) }
        return parts.joined(separator: " ").lowercased().contains(needle)
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

/// The shortcut line under a prefix field in Settings > Queue & Files.
enum PrefixShortcutText {
    /// One key: `Shortcut: N`. Several: `Shortcuts: N, H`, in assignment order. None:
    /// `Shortcut: Unassigned`.
    static func text(keys: [String]) -> String {
        switch keys.count {
        case 0:  return "Shortcut: Unassigned"
        case 1:  return "Shortcut: \(keys[0])"
        default: return "Shortcuts: " + keys.joined(separator: ", ")
        }
    }

    static func primary(in bindings: ShortcutBindings = ShortcutRegistry.shared.bindings) -> String {
        text(keys: ShortcutsCatalog.currentKeys(for: .togglePrimaryPrefix, in: bindings))
    }

    static func secondary(in bindings: ShortcutBindings = ShortcutRegistry.shared.bindings) -> String {
        text(keys: ShortcutsCatalog.currentKeys(for: .toggleSecondaryPrefix, in: bindings))
    }
}

/// Tooltips and help text that name a shortcut: `Bookmark (B)`. They read the active key of
/// the command, so a changed shortcut shows in them.
enum ShortcutHint {
    /// `title` with the first active key of `id` in parentheses; just `title` when the
    /// command has no key.
    static func title(_ title: String, for id: ShortcutCommandID,
                      in bindings: ShortcutBindings = ShortcutRegistry.shared.bindings) -> String {
        guard let key = bindings.primaryKeyText(for: id) else { return title }
        return "\(title) (\(key))"
    }
}
