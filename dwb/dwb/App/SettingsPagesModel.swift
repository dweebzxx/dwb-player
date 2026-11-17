import Foundation

/// The six Settings pages, their sidebar grouping, and each page's one-line description.
/// Page names and order are unchanged; the grouping and descriptions come from the
/// design system's Settings window (`KIT_GROUPS`, `KIT_DESC`) and the "Contains" column
/// of the Windows SOT page table.
enum SettingsPages {
    struct Page: Equatable {
        let name: String
        let identifier: String
        let description: String
    }

    struct Group: Equatable {
        let label: String
        /// Indices into `SettingsPages.all`, in sidebar order.
        let pageIndices: [Int]
    }

    static let all: [Page] = [
        Page(name: "Playback",
             identifier: "playback",
             description: "Video playback, image timing, and GIF loops."),
        Page(name: "Appearance & Controls",
             identifier: "controls",
             description: "Customize playback controls and window appearance."),
        Page(name: "Queue & Files",
             identifier: "queueFiles",
             description: "Choose accepted media, queue behavior, and filename prefixes."),
        Page(name: "Shortcuts",
             identifier: "shortcuts",
             description: "Find and customize keyboard shortcuts for this app."),
        Page(name: "Advanced",
             identifier: "advanced",
             description: "Diagnostics, bookmarks, and default settings."),
        Page(name: "About",
             identifier: "about",
             description: "Version, build, license, and project links.")
    ]

    static let groups: [Group] = [
        Group(label: "General", pageIndices: [0, 1, 2, 3]),
        Group(label: "System", pageIndices: [4, 5])
    ]

    /// Page indices in the order the sidebar shows them (arrow-key order).
    static var sidebarOrder: [Int] { groups.flatMap(\.pageIndices) }

    /// The page reached by moving `offset` rows from `index` in the sidebar, or nil at an end.
    static func neighbor(of index: Int, offset: Int) -> Int? {
        let order = sidebarOrder
        guard let position = order.firstIndex(of: index) else { return nil }
        let target = position + offset
        return order.indices.contains(target) ? order[target] : nil
    }
}

// MARK: - Playback page: number fields over fixed choices

/// The choices behind a Settings number field (image duration, GIF loops). The field is
/// editable, but only the listed choices are ever stored: a typed value snaps to the nearest
/// choice (the smaller one on a tie) and the stepper moves one choice at a time.
/// Pure values, no AppKit.
enum SettingsNumericChoices {
    /// Reads what the user typed. Returns nil when it is not a plain number, so the caller
    /// restores the stored value. A comma counts as the decimal point when there is no dot.
    static func parse(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("."), trimmed.filter({ $0 == "," }).count == 1 {
            trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        }
        var body = Substring(trimmed)
        if let first = body.first, first == "-" || first == "+" { body = body.dropFirst() }
        guard !body.isEmpty,
              body.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              body.filter({ $0 == "." }).count <= 1,
              let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    /// The choice nearest to `value`. A value below the first choice gives the first, above
    /// the last gives the last, and an exact tie gives the smaller choice.
    static func nearest(to value: Double, in choices: [Double]) -> Double? {
        var best: Double?
        for choice in choices.sorted() {
            guard let current = best else { best = choice; continue }
            if abs(choice - value) < abs(current - value) { best = choice }
        }
        return best
    }

    /// The choice one step from `value` (`direction` > 0 up, < 0 down), staying at the end.
    static func stepped(from value: Double, direction: Int, in choices: [Double]) -> Double? {
        let sorted = choices.sorted()
        guard let current = nearest(to: value, in: sorted),
              let index = sorted.firstIndex(of: current) else { return nil }
        let target = direction > 0 ? min(index + 1, sorted.count - 1) : direction < 0 ? max(index - 1, 0) : index
        return sorted[target]
    }

    /// The text shown in the field: `0.5`, `0.75`, `1`, `10`.
    static func displayText(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

// MARK: - Appearance & Controls page: dependent row

/// Hide title bar and Automatically hide title bar. While Hide title bar is on, the
/// automatic option is disabled but keeps its saved value; turning Hide title bar off
/// enables it again with that value. Pure values, no AppKit.
enum SettingsTitlebarDependency {
    struct RowState: Equatable {
        /// Whether the checkbox accepts clicks.
        let isEnabled: Bool
        /// The checkbox state shown: always the saved value.
        let isChecked: Bool
    }

    static func autoHideRowState(hideTitlebar: Bool, autoHideTitlebar: Bool) -> RowState {
        RowState(isEnabled: !hideTitlebar, isChecked: autoHideTitlebar)
    }

    static func autoHideMenuState(hideTitlebar: Bool, autoHideTitlebar: Bool) -> RowState {
        autoHideRowState(hideTitlebar: hideTitlebar, autoHideTitlebar: autoHideTitlebar)
    }
}

// MARK: - Playback page: speed popup titles

/// Titles of the Playback speed popup in Settings (`0.25×`, `1.00× (Normal)`). The Playback
/// Speed menu keeps its own titles (`0.25x`, `1.00x Normal`).
enum SettingsPlaybackSpeedTitle {
    static func title(rate: Float, isNormal: Bool) -> String {
        let base = String(format: "%.2f\u{00D7}", rate)
        return isNormal ? base + " (Normal)" : base
    }
}
