import Foundation

enum SettingsDefaultsRegistry {
    enum Keys {
        static let persistedVolume = "lastEffectiveVolume"
        static let skipDurationSeconds = "skipDurationSeconds"
        static let autoHideTitlebar = "autoHideTitlebar"
        static let completeVideoWindowMode = "completeVideoWindowMode"
        static let imageDurationSeconds = "imageDurationSeconds"
        static let gifLoopCount = "gifLoopCount"
        static let acceptVideoMedia = "acceptVideoMedia"
        static let acceptImageMedia = "acceptImageMedia"
        static let acceptGIFMedia = "acceptGIFMedia"
        static let showTitleOverlay = "showTitleOverlay"
        static let videoPageDButtonEnabled = "videoPageDButtonEnabled"
        static let customPrefixValue = "customPrefixValue"
        static let customPrefixSecondaryValue = "customPrefixValue2"
        static let debugConsoleEnabled = "debugConsoleEnabled"
        static let verboseAutoplayTrace = "verboseAutoplayTrace"
        static let chromeAutohideThreshold = "chromeAutohideThreshold"
        static let chromeReducedMotion = "chromeReducedMotion"
        static let queuePanelOpenAtLaunch = "queuePanelOpenAtLaunch"
        static let advanceAfterPrefix = "advanceAfterPrefix"
        static let bottomRailShowXButton = "bottomRailShowXButton"
        static let bottomRailShowShuffleButton = "bottomRailShowShuffleButton"
        static let bottomRailShowReplayButton = "bottomRailShowReplayButton"
        static let bottomRailShowVolumeButton = "bottomRailShowVolumeButton"
        static let bottomRailShowBookmarkButton = "bottomRailShowBookmarkButton"
        /// Manual audio/video sync offset in milliseconds, applied to
        /// VLCMediaPlayer.currentAudioPlaybackDelay. Compensates for fixed
        /// output-device latency (e.g. Bluetooth headphones). Positive delays
        /// audio further; negative advances it. Persisted as a default so a
        /// user tunes it once per output device rather than every session.
        static let audioSyncDelayMilliseconds = "audioSyncDelayMilliseconds"

    }

    enum Defaults {
        static let skipDurationSeconds = 10
        static let imageDurationSeconds = 3
        static let gifLoopCount = 1
        static let chromeAutohideThreshold = 3.0
        static let playerWindowOpacityMin = 0.35
        static let playerWindowOpacityMax = 1.0
        /// Every new player window starts at 100% opacity; window opacity is not stored.
        static let playerWindowOpacity = 1.0
        static let audioSyncDelayMilliseconds: Int32 = 0
        static let audioSyncDelayStepMilliseconds: Int32 = 50
        static let audioSyncDelayRangeMilliseconds: ClosedRange<Int32> = -3000...3000
    }

    static func defaultValues(reduceMotionDefault: Bool) -> [String: Any] {
        let defaults: [String: Any] = [
            Keys.skipDurationSeconds: Defaults.skipDurationSeconds,
            Keys.imageDurationSeconds: Defaults.imageDurationSeconds,
            Keys.gifLoopCount: Defaults.gifLoopCount,
            Keys.acceptVideoMedia: true,
            Keys.acceptImageMedia: true,
            Keys.acceptGIFMedia: true,
            Keys.autoHideTitlebar: false,
            Keys.completeVideoWindowMode: false,
            Keys.showTitleOverlay: true,
            Keys.videoPageDButtonEnabled: false,
            Keys.customPrefixValue: "",
            Keys.customPrefixSecondaryValue: "",
            Keys.debugConsoleEnabled: false,
            Keys.verboseAutoplayTrace: false,
            Keys.chromeAutohideThreshold: Defaults.chromeAutohideThreshold,
            Keys.chromeReducedMotion: reduceMotionDefault,
            Keys.queuePanelOpenAtLaunch: false,
            Keys.advanceAfterPrefix: false,
            Keys.bottomRailShowXButton: true,
            Keys.bottomRailShowShuffleButton: true,
            Keys.bottomRailShowReplayButton: true,
            Keys.bottomRailShowVolumeButton: true,
            Keys.bottomRailShowBookmarkButton: true,
            Keys.audioSyncDelayMilliseconds: Defaults.audioSyncDelayMilliseconds,
        ]

        return defaults
    }

    /// "Restore Default Settings…": every preference returns to its default, and the
    /// shortcut overrides are removed with them.
    static func restoreAll(in defaults: UserDefaults = .standard, reduceMotionDefault: Bool) {
        for (key, value) in defaultValues(reduceMotionDefault: reduceMotionDefault) {
            defaults.set(value, forKey: key)
        }
        ShortcutOverrideStore(defaults: defaults).clear()
    }

    static func register(defaults: UserDefaults = .standard, reduceMotionDefault: Bool) {
        defaults.register(defaults: defaultValues(reduceMotionDefault: reduceMotionDefault))
    }
}
