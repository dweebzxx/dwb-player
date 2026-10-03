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
             description: "How files play, and which media types the queue accepts."),
        Page(name: "Controls",
             identifier: "controls",
             description: "How the playback bar behaves and which buttons it shows, plus the player window."),
        Page(name: "Queue & Files",
             identifier: "queueFiles",
             description: "One-click prefix rename, the primary and secondary prefixes, and how the Queue Page opens."),
        Page(name: "Shortcuts",
             identifier: "shortcuts",
             description: "Every keyboard shortcut, grouped by task. Hover a row to see its keys. This page is read-only."),
        Page(name: "Advanced",
             identifier: "advanced",
             description: "The debug console, clearing bookmarks, and restoring default settings."),
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
