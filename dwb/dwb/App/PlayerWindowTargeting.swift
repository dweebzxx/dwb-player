import Foundation

/// Which player window a Dock click and the Settings window act on. The inputs are plain
/// snapshots of each player window, so the rules are testable without AppKit or VLCKit.
enum PlayerWindowTargeting {

    struct WindowSnapshot<ID: Equatable>: Equatable {
        let id: ID
        /// Visible and not minimized.
        let isOnScreen: Bool
        let isMinimized: Bool
        /// Order stamp of the last time this window became key; 0 if it never did.
        let lastKeyStamp: UInt64
        /// Order stamp of the last time this window was minimized; nil while it is not.
        let minimizeStamp: UInt64?
    }

    enum ReopenChoice<ID: Equatable>: Equatable {
        case bringForward(ID)
        case restoreMinimized(ID)
        case openNewWindow
    }

    /// Dock click: the most recently active on-screen window, else the most recently
    /// minimized window, else a new window. Closed windows are not in `windows`.
    static func reopenChoice<ID>(windows: [WindowSnapshot<ID>]) -> ReopenChoice<ID> {
        if let active = mostRecentlyKeyOnScreen(windows) {
            return .bringForward(active)
        }
        let minimized = windows.enumerated().filter { $0.element.isMinimized }
        if let latest = minimized.max(by: {
            ($0.element.minimizeStamp ?? 0, $0.offset) < ($1.element.minimizeStamp ?? 0, $1.offset)
        }) {
            return .restoreMinimized(latest.element.id)
        }
        return .openNewWindow
    }

    /// Settings target: the on-screen player window that most recently became key.
    /// Settings itself is never in `windows`, so it becoming key changes nothing.
    static func settingsTarget<ID>(windows: [WindowSnapshot<ID>]) -> ID? {
        mostRecentlyKeyOnScreen(windows)
    }

    /// Ties (such as two windows that never became key) go to the later, newer window.
    private static func mostRecentlyKeyOnScreen<ID>(_ windows: [WindowSnapshot<ID>]) -> ID? {
        windows.enumerated()
            .filter { $0.element.isOnScreen }
            .max(by: { ($0.element.lastKeyStamp, $0.offset) < ($1.element.lastKeyStamp, $1.offset) })?
            .element.id
    }

    // MARK: - Settings helper text

    static let noTargetHelperText = "No player window is open."
    /// Longest window name shown in the helper text before it is shortened in the middle.
    static let maxHelperNameLength = 48

    static func settingsHelperText(targetTitle: String?) -> String {
        guard let title = targetTitle else { return noTargetHelperText }
        return "Applies to \u{201C}\(middleTruncated(title, maxLength: maxHelperNameLength))\u{201D}."
    }

    /// The Playback speed row's text: the speed applies to video only, then the target.
    static func speedHelperText(targetTitle: String?) -> String {
        "Affects video only. " + settingsHelperText(targetTitle: targetTitle)
    }

    static func middleTruncated(_ text: String, maxLength: Int) -> String {
        guard maxLength > 1, text.count > maxLength else { return text }
        let kept = maxLength - 1
        return String(text.prefix((kept + 1) / 2)) + "\u{2026}" + String(text.suffix(kept / 2))
    }
}
