import Foundation

/// Copy and bundle-backed values for the Advanced and About Settings pages.
/// Kept free of AppKit and VLCKit so the displayed values can be tested directly.
enum SettingsAdvancedAboutContent {
    enum Advanced {
        static let sectionTitles = ["Diagnostics", "Bookmarks", "Reset"]
        static let cancel = "Cancel"
        static let debugConsole = "Show debug console"
        static let autoplayLogging = "Detailed autoplay logging"
        static let autoplayHelp = "Records additional autoplay diagnostics in debug builds only."
        static let clearBookmarks = "Clear All Bookmarks…"
        static let clearBookmarksHelp = "Clears this app's bookmarks without deleting media files. This cannot be undone."
        static let clearBookmarksTitle = "Clear all bookmarks for dwb player?"
        static let clearBookmarksMessage = "This removes all bookmarks saved by this app. Media files are not deleted. This cannot be undone."
        static let clearBookmarksConfirm = "Clear All Bookmarks"
        static let restoreDefaults = "Restore Default Settings…"
        static let restoreDefaultsHelp = "Restores this app's settings and keyboard shortcuts. Media files, queues, and bookmarks are not deleted."
        static let restoreDefaultsTitle = "Restore default settings for dwb player?"
        static let restoreDefaultsMessage = "This resets this app's settings and customized keyboard shortcuts. Media files, queues, and bookmarks are not deleted."
        static let restoreDefaultsConfirm = "Restore Defaults"
    }

    enum About {
        struct Fact: Equatable {
            let label: String
            let value: String
        }

        static let description = "Play and review local videos, images, and GIFs."
        static let displayedBuild = "--"
        static let githubTitle = "View on GitHub"
        static let issuesTitle = "Report an Issue"

        static func versionLine(version: String, build: String) -> String {
            "Version \(version) · Build \(build)"
        }

        static func facts(info: [String: Any], vlcBackendVersion: String) -> [Fact] {
            let minimumSystem = info["LSMinimumSystemVersion"] as? String
            return [
                Fact(label: "License", value: "MIT License"),
                Fact(label: "Requires", value: minimumSystem.map { "macOS \($0) or later" } ?? "Unavailable"),
                Fact(label: "Interface", value: "AppKit"),
                Fact(label: "Playback framework", value: "VLCKit"),
                Fact(label: "VLC backend", value: vlcBackendVersion)
            ]
        }
    }
}
