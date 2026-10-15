import Cocoa
import VLCKitSPM

extension Notification.Name {
    /// Posted when playback control chrome settings change.
    static let transportVisibilityChanged     = Notification.Name("dwb.transportVisibilityChanged")
    /// Posted when the shared skip-duration preference changes.
    static let skipDurationChanged            = Notification.Name("dwb.skipDurationChanged")
    /// Posted when the titlebar auto-hide setting changes.
    static let autoHideTitlebarChanged        = Notification.Name("dwb.autoHideTitlebarChanged")
    /// Posted when windowed Complete Video Mode changes.
    static let completeVideoWindowModeChanged = Notification.Name("dwb.completeVideoWindowModeChanged")
    /// Posted when the image slideshow display duration changes.
    static let imageDurationChanged           = Notification.Name("dwb.imageDurationChanged")
    /// Posted when the GIF playback loop-count setting changes.
    static let gifLoopCountChanged            = Notification.Name("dwb.gifLoopCountChanged")
    /// Posted when accepted media type settings change.
    static let acceptedMediaTypesChanged      = Notification.Name("dwb.acceptedMediaTypesChanged")
    /// Posted when the title overlay on playback start setting changes.
    static let titleOverlaySettingChanged     = Notification.Name("dwb.titleOverlaySettingChanged")
    /// Posted when the stored custom prefix value changes.
    static let customPrefixValueChanged                    = Notification.Name("dwb.customPrefixValueChanged")
    /// Posted when the debug console enable setting changes.
    static let debugConsoleSettingChanged     = Notification.Name("dwb.debugConsoleSettingChanged")
    /// Posted when one player window's playback speed changes.
    static let playbackSpeedChanged           = Notification.Name("dwb.playbackSpeedChanged")
    /// Posted when one player window's effective volume or mute changes, from any route.
    static let windowVolumeChanged            = Notification.Name("dwb.windowVolumeChanged")
    /// Posted when any of the playback-bar button visibility toggles (x_,
    /// Shuffle, Replay, Volume, Bookmark) change. BottomRailView observes
    /// this and re-applies button visibility / rebuilds the More menu.
    static let bottomRailButtonVisibilityChanged = Notification.Name("dwb.bottomRailButtonVisibilityChanged")
    /// Posted by a player window when it becomes key, is minimized or restored, closes,
    /// or changes its title. Settings re-picks its target window on it.
    static let playerWindowTargetingChanged = Notification.Name("dwb.playerWindowTargetingChanged")
}

/// Singleton settings panel. Open via dwb > Settings… (Cmd+,).
/// Sidebar pages: Playback, Controls, Queue & Files, Shortcuts (General); Advanced, About (System).
/// Window 820 × 550 pt, 188 pt sidebar on solid canvas, one shared page header
/// (title, description, hairline). Layout values come from `DWBMetrics`.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    static let shared = SettingsWindowController()

    // MARK: - UserDefaults keys

    static let persistedVolumeKey       = SettingsDefaultsRegistry.Keys.persistedVolume
    /// Manual audio/video sync offset, persisted so it survives across windows and
    /// launches (a Bluetooth headset's latency is roughly constant per device).
    static let audioSyncDelayKey                  = SettingsDefaultsRegistry.Keys.audioSyncDelayMilliseconds
    static let audioSyncDelayStepMilliseconds     = SettingsDefaultsRegistry.Defaults.audioSyncDelayStepMilliseconds
    static let audioSyncDelayRangeMilliseconds    = SettingsDefaultsRegistry.Defaults.audioSyncDelayRangeMilliseconds
    static let skipDurationKey          = SettingsDefaultsRegistry.Keys.skipDurationSeconds
    static let defaultSkipDurationSeconds = SettingsDefaultsRegistry.Defaults.skipDurationSeconds
    /// Titlebar auto-hide in windowed mode. Default: false.
    static let autoHideTitlebarKey      = SettingsDefaultsRegistry.Keys.autoHideTitlebar
    /// Hide the titlebar chrome in windowed mode so video reaches the top edge. Default: false.
    static let completeVideoWindowModeKey = SettingsDefaultsRegistry.Keys.completeVideoWindowMode
    /// Image slideshow display duration in seconds. Default: 3.
    static let imageDurationKey         = SettingsDefaultsRegistry.Keys.imageDurationSeconds
    static let defaultImageDurationSeconds = SettingsDefaultsRegistry.Defaults.imageDurationSeconds
    /// GIF playback loop count before queue advance. Default: 1.
    static let gifLoopCountKey          = SettingsDefaultsRegistry.Keys.gifLoopCount
    static let defaultGIFLoopCount      = SettingsDefaultsRegistry.Defaults.gifLoopCount
    /// Accepted media types for open/drop intake. Defaults: all true.
    static let acceptVideoKey           = SettingsDefaultsRegistry.Keys.acceptVideoMedia
    static let acceptImagesKey          = SettingsDefaultsRegistry.Keys.acceptImageMedia
    static let acceptGIFKey             = SettingsDefaultsRegistry.Keys.acceptGIFMedia
    /// Show title overlay when video or image playback starts. Default: true.
    static let showTitleOverlayKey      = SettingsDefaultsRegistry.Keys.showTitleOverlay
    /// Stored custom prefix string for one-click rename, kept exactly as typed. Default: "".
    static let customPrefixValueKey     = SettingsDefaultsRegistry.Keys.customPrefixValue
    /// Stored secondary custom prefix string for one-click rename. Default: "".
    static let customPrefixSecondaryValueKey = SettingsDefaultsRegistry.Keys.customPrefixSecondaryValue
    /// Show in-app debug console. Default: false.
    static let debugConsoleKey          = SettingsDefaultsRegistry.Keys.debugConsoleEnabled
    /// Verbose per-tick watchdog trace in Xcode console. Debug builds only. Default: false.
    static let verboseAutoplayTraceKey  = SettingsDefaultsRegistry.Keys.verboseAutoplayTrace
    /// Shared quiet-rail chrome idle threshold. Default: 3.0 seconds.
    static let chromeAutohideThresholdKey = SettingsDefaultsRegistry.Keys.chromeAutohideThreshold
    /// Reduce quiet-rail chrome animation. Default mirrors the system reduce-motion setting at launch.
    static let chromeReducedMotionKey   = SettingsDefaultsRegistry.Keys.chromeReducedMotion
    /// Open the Queue Page when a player window launches. Default: false.
    static let queuePanelOpenAtLaunchKey = SettingsDefaultsRegistry.Keys.queuePanelOpenAtLaunch
    /// Playback-bar button visibility toggles. All default ON to preserve the
    /// current unified-rail look; the user can hide individual buttons from
    /// Settings → Controls → Playback bar buttons.
    static let bottomRailShowXKey         = SettingsDefaultsRegistry.Keys.bottomRailShowXButton
    static let bottomRailShowShuffleKey   = SettingsDefaultsRegistry.Keys.bottomRailShowShuffleButton
    static let bottomRailShowReplayKey    = SettingsDefaultsRegistry.Keys.bottomRailShowReplayButton
    static let bottomRailShowVolumeKey    = SettingsDefaultsRegistry.Keys.bottomRailShowVolumeButton
    static let bottomRailShowBookmarkKey  = SettingsDefaultsRegistry.Keys.bottomRailShowBookmarkButton
    /// Window opacity is per window and never stored. New windows start at 100%.
    static let playerWindowOpacityMin: CGFloat = CGFloat(SettingsDefaultsRegistry.Defaults.playerWindowOpacityMin)
    static let playerWindowOpacityMax: CGFloat = CGFloat(SettingsDefaultsRegistry.Defaults.playerWindowOpacityMax)
    static let defaultPlayerWindowOpacityValue: CGFloat = CGFloat(SettingsDefaultsRegistry.Defaults.playerWindowOpacity)
    static let githubURLString = "https://github.com/dweebzxx/dwb-player"
    static let githubIssuesURLString = "https://github.com/dweebzxx/dwb-player/issues"

    // MARK: - Static helpers

    static func clampedPlayerWindowOpacity(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultPlayerWindowOpacityValue }
        return min(playerWindowOpacityMax, max(playerWindowOpacityMin, value))
    }
    static func playerWindowOpacityPercent(_ opacity: CGFloat) -> Int {
        Int((clampedPlayerWindowOpacity(opacity) * 100.0).rounded())
    }
    static func vlcBackendVersionText() -> String {
        let version = VLCLibrary.shared().version.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "Unavailable" : version
    }
    static func isVerboseAutoplayTraceEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: verboseAutoplayTraceKey)
    }
    static func isAutoHideTitlebarEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: autoHideTitlebarKey)
    }
    static func isCompleteVideoWindowModeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: completeVideoWindowModeKey)
    }
    static func isShowTitleOverlayEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: showTitleOverlayKey)
    }
    /// The prefixes as typed, for the Settings fields. Everything else uses the trimmed values.
    static func storedCustomPrefixValue() -> String {
        UserDefaults.standard.string(forKey: customPrefixValueKey) ?? ""
    }
    static func storedCustomPrefixSecondaryValue() -> String {
        UserDefaults.standard.string(forKey: customPrefixSecondaryValueKey) ?? ""
    }
    /// The primary prefix, normalized (`PrefixNormalization`). The chip label, the N key,
    /// the chip, the rail button, the highlight and the filename all use this one value.
    static func customPrefixValue() -> String {
        PrefixNormalization.normalized(storedCustomPrefixValue())
    }
    static func customPrefixSecondaryValue() -> String {
        PrefixNormalization.normalized(storedCustomPrefixSecondaryValue())
    }
    static func isDebugConsoleEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: debugConsoleKey)
    }
    static func isBottomRailShowXEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: bottomRailShowXKey)
    }
    static func isBottomRailShowShuffleEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: bottomRailShowShuffleKey)
    }
    static func isBottomRailShowReplayEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: bottomRailShowReplayKey)
    }
    static func isBottomRailShowVolumeEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: bottomRailShowVolumeKey)
    }
    static func isBottomRailShowBookmarkEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: bottomRailShowBookmarkKey)
    }
    static func acceptsVideoMedia() -> Bool {
        UserDefaults.standard.bool(forKey: acceptVideoKey)
    }
    static func acceptsImageMedia() -> Bool {
        UserDefaults.standard.bool(forKey: acceptImagesKey)
    }
    static func acceptsGIFMedia() -> Bool {
        UserDefaults.standard.bool(forKey: acceptGIFKey)
    }
    static func acceptedMediaKinds() -> Set<MediaFileSupport.MediaKind> {
        var kinds = Set<MediaFileSupport.MediaKind>()
        if acceptsVideoMedia() { kinds.insert(.video) }
        if acceptsImageMedia() { kinds.insert(.image) }
        if acceptsGIFMedia() { kinds.insert(.gif) }
        return kinds
    }

    struct SkipDurationOption  { let seconds: Int;    let title: String }
    struct ImageDurationOption { let seconds: Double; let title: String }
    struct GIFLoopCountOption  { let loops:   Int;    let title: String }

    static let skipDurationOptions: [SkipDurationOption] = [
        .init(seconds: 10,  title: "10 seconds"),
        .init(seconds: 30,  title: "30 seconds"),
        .init(seconds: 60,  title: "60 seconds"),
        .init(seconds: 180, title: "3 minutes"),
    ]
    static let imageDurationOptions: [ImageDurationOption] = [
        .init(seconds: 0.5,  title: "0.5 seconds"),
        .init(seconds: 0.75, title: "0.75 seconds"),
        .init(seconds: 1,    title: "1 second"),
        .init(seconds: 2,    title: "2 seconds"),
        .init(seconds: 3,    title: "3 seconds"),
        .init(seconds: 5,    title: "5 seconds"),
        .init(seconds: 10,   title: "10 seconds"),
    ]
    static let gifLoopCountOptions: [GIFLoopCountOption] = [
        .init(loops: 1,  title: "1 loop"),
        .init(loops: 3,  title: "3 loops"),
        .init(loops: 5,  title: "5 loops"),
        .init(loops: 10, title: "10 loops"),
    ]
    static let chromeThresholdOptions: [(seconds: Double, title: String)] = [
        (1.0, "1 second"),
        (1.5, "1.5 seconds"),
        (2.0, "2 seconds"),
        (3.0, "3 seconds"),
        (5.0, "5 seconds"),
        (8.0, "8 seconds"),
    ]

    static func chromeThresholdTag(for seconds: Double) -> Int {
        Int((seconds * 10).rounded())
    }

    static func imageDurationTag(for seconds: Double) -> Int {
        Int((seconds * 100).rounded())
    }
    static func imageDurationSeconds(forTag tag: Int) -> Double {
        Double(tag) / 100.0
    }
    static func validatedImageDurationSeconds(_ value: Double) -> Double {
        let tag = imageDurationTag(for: value)
        return imageDurationOptions.first(where: { imageDurationTag(for: $0.seconds) == tag })?.seconds
            ?? Double(defaultImageDurationSeconds)
    }
    static func currentImageDurationSeconds() -> Double {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: imageDurationKey)
            .map { _ in defaults.double(forKey: imageDurationKey) }
            ?? Double(defaultImageDurationSeconds)
        let v = validatedImageDurationSeconds(stored)
        if v != stored { defaults.set(v, forKey: imageDurationKey) }
        return v
    }
    static func validatedGIFLoopCount(_ value: Int) -> Int {
        gifLoopCountOptions.contains(where: { $0.loops == value }) ? value : defaultGIFLoopCount
    }
    static func currentGIFLoopCount() -> Int {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: gifLoopCountKey)
            .map { _ in defaults.integer(forKey: gifLoopCountKey) }
            ?? defaultGIFLoopCount
        let v = validatedGIFLoopCount(stored)
        if v != stored { defaults.set(v, forKey: gifLoopCountKey) }
        return v
    }
    private static func settingsDefaultValues() -> [String: Any] {
        SettingsDefaultsRegistry.defaultValues(
            reduceMotionDefault: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }
    static func registerDefaults() {
        SettingsDefaultsRegistry.register(
            reduceMotionDefault: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }
    static func restoreSettingsDefaults() {
        let defaults = UserDefaults.standard
        for (key, value) in settingsDefaultValues() {
            defaults.set(value, forKey: key)
        }
        NotificationCenter.default.post(name: .transportVisibilityChanged, object: nil)
        NotificationCenter.default.post(name: .skipDurationChanged, object: nil)
        NotificationCenter.default.post(name: .autoHideTitlebarChanged, object: nil)
        NotificationCenter.default.post(name: .completeVideoWindowModeChanged, object: nil)
        NotificationCenter.default.post(name: .imageDurationChanged, object: nil)
        NotificationCenter.default.post(name: .gifLoopCountChanged, object: nil)
        NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: nil)
        NotificationCenter.default.post(name: .titleOverlaySettingChanged, object: nil)
        NotificationCenter.default.post(name: .customPrefixValueChanged, object: nil)
        NotificationCenter.default.post(name: .debugConsoleSettingChanged, object: nil)
        NotificationCenter.default.post(name: .bottomRailButtonVisibilityChanged, object: nil)
    }
    static func validatedSkipDurationSeconds(_ value: Int) -> Int {
        skipDurationOptions.contains(where: { $0.seconds == value }) ? value : defaultSkipDurationSeconds
    }
    static func currentSkipDurationSeconds() -> Int {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: skipDurationKey)
            .map { _ in defaults.integer(forKey: skipDurationKey) }
            ?? defaultSkipDurationSeconds
        let v = validatedSkipDurationSeconds(stored)
        if v != stored { defaults.set(v, forKey: skipDurationKey) }
        return v
    }
    static func setSkipDuration(_ seconds: Int) {
        let v = validatedSkipDurationSeconds(seconds)
        UserDefaults.standard.set(v, forKey: skipDurationKey)
        NotificationCenter.default.post(name: .skipDurationChanged, object: nil)
    }
    static func skipDurationTitle(seconds: Int) -> String {
        skipDurationOptions.first(where: { $0.seconds == validatedSkipDurationSeconds(seconds) })?.title
            ?? "\(defaultSkipDurationSeconds) seconds"
    }
    static func skipActionTitle(isForward: Bool, seconds: Int) -> String {
        "\(isForward ? "Forward" : "Rewind") \(skipDurationTitle(seconds: seconds))"
    }
    // MARK: - UI controls

    // Playback section
    private let skipDurationPopup           = DWBPopUpButton()
    private let playbackSpeedPopup          = DWBPopUpButton()
    private let showTitleOverlayCheckbox    = NSButton()
    private let imageDurationPopup          = DWBPopUpButton()
    private let gifLoopCountPopup           = DWBPopUpButton()
    private let acceptVideoCheckbox         = NSButton()
    private let acceptImagesCheckbox        = NSButton()
    private let acceptGIFCheckbox           = NSButton()

    // Controls section
    private let bottomRailShowXCheckbox        = NSButton()
    private let bottomRailShowShuffleCheckbox  = NSButton()
    private let bottomRailShowReplayCheckbox   = NSButton()
    private let bottomRailShowVolumeCheckbox   = NSButton()
    private let bottomRailShowBookmarkCheckbox = NSButton()
    private let chromeAutohideThresholdPopup = DWBPopUpButton()
    private let chromeReducedMotionCheckbox  = NSButton()
    private let autoHideTitlebarCheckbox     = NSButton()
    private let completeVideoWindowModeCheckbox = NSButton()
    private let windowOpacitySlider       = NSSlider()
    private let windowOpacityPercentLabel = NSTextField(labelWithString: "100%")
    private let windowOpacityResetButton  = DWBButton(title: "Default", variant: .neutral, size: .small)
    private let windowVolumeSlider        = NSSlider()
    private let windowVolumePercentLabel  = NSTextField(labelWithString: "100%")
    private let windowVolumeResetButton   = DWBButton(title: "Default", variant: .neutral, size: .small)

    // Helper text naming the target player window (opacity, playback speed, and volume).
    private let playbackSpeedTargetLabel  = NSTextField(wrappingLabelWithString: PlayerWindowTargeting.noTargetHelperText)
    private let windowVolumeTargetLabel   = NSTextField(wrappingLabelWithString: PlayerWindowTargeting.noTargetHelperText)
    private let windowOpacityTargetLabel  = NSTextField(wrappingLabelWithString: PlayerWindowTargeting.noTargetHelperText)
    /// The player window currently showing the Settings target outline.
    private weak var outlinedPlayerWindowController: PlayerWindowController?

    // Queue & Files section
    private let customPrefixValueTextField             = DWBTextField()
    private let customPrefixSecondaryValueTextField    = DWBTextField()
    private let queuePanelOpenAtLaunchCheckbox = NSButton()

    // Advanced section
    private let debugConsoleCheckbox          = NSButton()
    private let verboseAutoplayTraceCheckbox  = NSButton()
    private let restoreDefaultsButton         = DWBButton(title: "Restore All Settings to Default", variant: .secondary)
    private let clearBookmarksButton          = DWBButton(title: "Clear All Bookmarks…", variant: .destructivePlain)

    // MARK: - Sidebar / detail state

    private var sidebarButtons: [SettingsSidebarItemButton] = []
    private let detailContainer = NSView()
    private var sectionViews:   [NSView] = []
    private var sectionNames: [String] { SettingsPages.all.map(\.name) }
    /// Closures that re-apply colors that depend on Increase Contrast (secondary and
    /// tertiary text, borders). Run on every `.dwbAppearanceDidChange`.
    private var contrastRefreshers: [() -> Void] = []

    // MARK: - Init

    private init() {
        let win = NSPanel(
            contentRect: NSRect(origin: .zero, size: DWBMetrics.settingsSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.minSize = DWBMetrics.settingsMinSize
        win.standardWindowButton(.closeButton)?.isHidden = false
        win.standardWindowButton(.closeButton)?.isEnabled = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = false
        win.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        win.standardWindowButton(.zoomButton)?.isHidden = false
        win.standardWindowButton(.zoomButton)?.isEnabled = false
        // Suite dark-theme consistency: pin the settings window to dark Aqua so its
        // chrome and controls match dwb skim's settings window on any system theme.
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = DWBColor.surface
        super.init(window: win)
        buildUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: win
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackSpeedDidChange(_:)),
            name: .playbackSpeedChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVolumeDidChange(_:)),
            name: .windowVolumeChanged,
            object: nil
        )
        // Keep Settings above player windows while the app is active, but do not use
        // a global floating level that would place it above other applications' windows.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anyWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        // The target and its outline follow player windows and Settings' own visibility.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerWindowTargetingDidChange(_:)),
            name: .playerWindowTargetingChanged,
            object: nil
        )
        for name in [NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowVisibilityDidChange(_:)),
                name: name,
                object: win
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: win
        )
        for name in [NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification,
                     NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowVisibilityDidChange(_:)),
                name: name,
                object: nil
            )
        }
        DWBAppearance.observe(self, selector: #selector(appearanceDidChange))
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func appearanceDidChange() {
        contrastRefreshers.forEach { $0() }
        sidebarButtons.forEach { $0.refreshAppearance() }
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // Sidebar: 188 pt on solid canvas, grouped under General and System, items 32 pt
        // tall with radius 6 (design system Settings window).
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = DWBColor.canvas.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 14
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        for group in SettingsPages.groups {
            let groupStack = NSStackView()
            groupStack.orientation = .vertical
            groupStack.alignment = .leading
            groupStack.spacing = 2
            groupStack.translatesAutoresizingMaskIntoConstraints = false

            let caption = NSTextField(labelWithString: "")
            caption.translatesAutoresizingMaskIntoConstraints = false
            caption.drawsBackground = false
            caption.isEditable = false
            caption.isBordered = false
            caption.setAccessibilityElement(false)
            let applyCaption = {
                caption.attributedStringValue = NSAttributedString(string: group.label.uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: DWBAppearance.shared.textTertiary,
                    .kern: QueuePanelMetrics.sectionLabelKern
                ])
            }
            applyCaption()
            contrastRefreshers.append(applyCaption)
            let captionRow = NSView()
            captionRow.translatesAutoresizingMaskIntoConstraints = false
            captionRow.addSubview(caption)
            NSLayoutConstraint.activate([
                caption.leadingAnchor.constraint(equalTo: captionRow.leadingAnchor, constant: 12),
                caption.trailingAnchor.constraint(equalTo: captionRow.trailingAnchor),
                caption.topAnchor.constraint(equalTo: captionRow.topAnchor),
                caption.bottomAnchor.constraint(equalTo: captionRow.bottomAnchor, constant: -4)
            ])
            groupStack.addArrangedSubview(captionRow)
            captionRow.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true

            for index in group.pageIndices {
                let page = SettingsPages.all[index]
                let btn = SettingsSidebarItemButton(title: page.name,
                                                    sectionIndex: index,
                                                    accessibilityIdentifier: "settings.sidebar.\(page.identifier)",
                                                    target: self,
                                                    action: #selector(sidebarButtonClicked(_:)))
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.heightAnchor.constraint(equalToConstant: DWBMetrics.sidebarRow).isActive = true
                btn.onNavigate = { [weak self] offset in self?.navigateSidebar(from: index, offset: offset) }
                groupStack.addArrangedSubview(btn)
                btn.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true
                sidebarButtons.append(btn)
            }
            sidebarStack.addArrangedSubview(groupStack)
            groupStack.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
        }
        sidebarButtons.sort { $0.sectionIndex < $1.sectionIndex }

        // Vertical separator
        let sepLine = SettingsSeparatorLine()
        sepLine.translatesAutoresizingMaskIntoConstraints = false

        // Detail container
        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(sidebar)
        cv.addSubview(sepLine)
        cv.addSubview(detailContainer)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: cv.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: DWBMetrics.sidebarWidth),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 20),

            sepLine.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sepLine.topAnchor.constraint(equalTo: cv.topAnchor),
            sepLine.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            sepLine.widthAnchor.constraint(equalToConstant: 1),

            detailContainer.leadingAnchor.constraint(equalTo: sepLine.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: cv.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        // Build section views; add all to container, show only the selected one
        sectionViews = [
            buildPlaybackSection(),
            buildControlsSection(),
            buildQueueFilesSection(),
            buildShortcutsSection(),
            buildAdvancedSection(),
            buildAboutSection(),
        ]
        for (i, sv) in sectionViews.enumerated() {
            sv.translatesAutoresizingMaskIntoConstraints = false
            detailContainer.addSubview(sv)
            NSLayoutConstraint.activate([
                sv.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
                sv.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
                sv.topAnchor.constraint(equalTo: detailContainer.topAnchor),
                sv.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            ])
            sv.isHidden = (i != 0)
        }

        selectSection(0)
        syncUIFromDefaults()
    }

    // MARK: - Sidebar selection

    private func selectSection(_ index: Int) {
        guard index >= 0, index < sectionViews.count else { return }
        for (i, sv) in sectionViews.enumerated() {
            sv.isHidden = (i != index)
        }
        for btn in sidebarButtons {
            btn.isSelected = (btn.sectionIndex == index)
        }
    }

    @objc private func sidebarButtonClicked(_ sender: SettingsSidebarItemButton) {
        selectSection(sender.sectionIndex)
    }

    /// Up and Down arrows move the sidebar selection across both groups.
    private func navigateSidebar(from index: Int, offset: Int) {
        guard let target = SettingsPages.neighbor(of: index, offset: offset),
              let button = sidebarButtons.first(where: { $0.sectionIndex == target }) else { return }
        window?.makeFirstResponder(button)
        selectSection(target)
    }

    // MARK: - Section: Playback

    private func buildPlaybackSection() -> NSView {
        configure(showTitleOverlayCheckbox, title: "Show title overlay on playback start", state: Self.isShowTitleOverlayEnabled())
        showTitleOverlayCheckbox.setAccessibilityIdentifier("settings.playback.showTitleOverlay")

        skipDurationPopup.target = self
        skipDurationPopup.action = #selector(skipDurationPopupChanged(_:))
        for opt in Self.skipDurationOptions {
            skipDurationPopup.addItem(withTitle: opt.title)
            skipDurationPopup.lastItem?.tag = opt.seconds
        }
        skipDurationPopup.setAccessibilityIdentifier("settings.playback.skipDuration")

        playbackSpeedPopup.target = self
        playbackSpeedPopup.action = #selector(playbackSpeedPopupChanged(_:))
        for opt in PlaybackSpeedOption.all {
            playbackSpeedPopup.addItem(withTitle: opt.title)
            playbackSpeedPopup.lastItem?.tag = opt.tag
        }
        playbackSpeedPopup.setAccessibilityIdentifier("settings.playback.speed")

        imageDurationPopup.target = self
        imageDurationPopup.action = #selector(imageDurationPopupChanged(_:))
        for opt in Self.imageDurationOptions {
            imageDurationPopup.addItem(withTitle: opt.title)
            imageDurationPopup.lastItem?.tag = Self.imageDurationTag(for: opt.seconds)
        }
        imageDurationPopup.setAccessibilityIdentifier("settings.playback.imageDuration")

        gifLoopCountPopup.target = self
        gifLoopCountPopup.action = #selector(gifLoopCountPopupChanged(_:))
        for opt in Self.gifLoopCountOptions {
            gifLoopCountPopup.addItem(withTitle: opt.title)
            gifLoopCountPopup.lastItem?.tag = opt.loops
        }
        gifLoopCountPopup.setAccessibilityIdentifier("settings.playback.gifLoopCount")

        // Window volume uses the Window opacity row's controls, widths, and spacing.
        windowVolumeSlider.minValue = Double(VolumePolicy.minimumVolume)
        windowVolumeSlider.maxValue = Double(VolumePolicy.maximumVolume)
        windowVolumeSlider.target = self
        windowVolumeSlider.action = #selector(windowVolumeSliderChanged(_:))
        windowVolumeSlider.translatesAutoresizingMaskIntoConstraints = false
        windowVolumeSlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        windowVolumeSlider.setAccessibilityIdentifier("settings.playback.windowVolume")

        windowVolumePercentLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        windowVolumePercentLabel.alignment = .right
        windowVolumePercentLabel.translatesAutoresizingMaskIntoConstraints = false
        windowVolumePercentLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let applyVolumePercentColor: () -> Void = { [weak self] in
            self?.windowVolumePercentLabel.textColor = DWBAppearance.shared.textSecondary
        }
        applyVolumePercentColor()
        contrastRefreshers.append(applyVolumePercentColor)

        windowVolumeResetButton.target = self
        windowVolumeResetButton.action = #selector(resetWindowVolume(_:))
        windowVolumeResetButton.setAccessibilityIdentifier("settings.playback.resetWindowVolume")

        let volumeStack = NSStackView(views: [windowVolumeSlider, windowVolumePercentLabel, windowVolumeResetButton])
        volumeStack.orientation = .horizontal
        volumeStack.alignment = .centerY
        volumeStack.spacing = 10

        let section1 = buildSection(title: "Playback behavior", rows: [
            buildRow(label: "Skip duration", control: skipDurationPopup),
            buildRow(label: "Playback speed", control: playbackSpeedPopup, helperLabel: playbackSpeedTargetLabel),
            buildRow(label: "Window volume", control: volumeStack, helperLabel: windowVolumeTargetLabel),
            buildRow(label: nil, control: showTitleOverlayCheckbox)
        ])

        let section2 = buildSection(title: "Images & animated GIFs", rows: [
            buildRow(label: "Image slideshow duration", control: imageDurationPopup),
            buildRow(label: "GIF loops before advancing", control: gifLoopCountPopup)
        ])

        configure(acceptVideoCheckbox, title: "Video", state: Self.acceptsVideoMedia())
        configure(acceptImagesCheckbox, title: "Images", state: Self.acceptsImageMedia())
        configure(acceptGIFCheckbox, title: "GIF", state: Self.acceptsGIFMedia())
        acceptVideoCheckbox.setAccessibilityIdentifier("settings.playback.acceptVideo")
        acceptImagesCheckbox.setAccessibilityIdentifier("settings.playback.acceptImages")
        acceptGIFCheckbox.setAccessibilityIdentifier("settings.playback.acceptGIF")

        let section3 = buildSection(title: "Accept", rows: [
            buildRow(label: nil, control: acceptVideoCheckbox),
            buildRow(label: nil, control: acceptImagesCheckbox),
            buildRow(label: nil, control: acceptGIFCheckbox)
        ])

        return buildPage(index: 0, sections: [section1, section2, section3])
    }

    // MARK: - Section: Controls

    private func buildControlsSection() -> NSView {
        configure(chromeReducedMotionCheckbox, title: "Reduce motion", state: UserDefaults.standard.bool(forKey: Self.chromeReducedMotionKey))
        configure(autoHideTitlebarCheckbox, title: "Auto-hide titlebar", state: Self.isAutoHideTitlebarEnabled())
        configure(completeVideoWindowModeCheckbox, title: "Hide window chrome for edge-to-edge video", state: Self.isCompleteVideoWindowModeEnabled())
        chromeReducedMotionCheckbox.setAccessibilityIdentifier("settings.controls.reduceMotion")
        autoHideTitlebarCheckbox.setAccessibilityIdentifier("settings.controls.autoHideTitlebar")
        completeVideoWindowModeCheckbox.setAccessibilityIdentifier("settings.controls.edgeToEdgeVideo")

        chromeAutohideThresholdPopup.target = self
        chromeAutohideThresholdPopup.action = #selector(chromeThresholdPopupChanged(_:))
        for opt in Self.chromeThresholdOptions {
            chromeAutohideThresholdPopup.addItem(withTitle: opt.title)
            chromeAutohideThresholdPopup.lastItem?.tag = Self.chromeThresholdTag(for: opt.seconds)
        }
        chromeAutohideThresholdPopup.setAccessibilityIdentifier("settings.controls.autoHideDelay")

        windowOpacitySlider.minValue = Double(Self.playerWindowOpacityMin * 100.0)
        windowOpacitySlider.maxValue = Double(Self.playerWindowOpacityMax * 100.0)
        windowOpacitySlider.target = self
        windowOpacitySlider.action = #selector(windowOpacitySliderChanged(_:))
        windowOpacitySlider.translatesAutoresizingMaskIntoConstraints = false
        windowOpacitySlider.widthAnchor.constraint(equalToConstant: 190).isActive = true
        windowOpacitySlider.setAccessibilityIdentifier("settings.controls.windowOpacity")

        windowOpacityPercentLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        windowOpacityPercentLabel.alignment = .right
        windowOpacityPercentLabel.translatesAutoresizingMaskIntoConstraints = false
        windowOpacityPercentLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let applyPercentColor: () -> Void = { [weak self] in
            self?.windowOpacityPercentLabel.textColor = DWBAppearance.shared.textSecondary
        }
        applyPercentColor()
        contrastRefreshers.append(applyPercentColor)

        windowOpacityResetButton.target = self
        windowOpacityResetButton.action = #selector(resetWindowOpacity(_:))
        windowOpacityResetButton.setAccessibilityIdentifier("settings.controls.resetWindowOpacity")

        let opacityStack = NSStackView(views: [windowOpacitySlider, windowOpacityPercentLabel, windowOpacityResetButton])
        opacityStack.orientation = .horizontal
        opacityStack.alignment = .centerY
        opacityStack.spacing = 10

        // Short visible labels under the section title; the full phrase stays the VoiceOver label.
        configure(bottomRailShowXCheckbox,        title: "Prefix buttons", state: Self.isBottomRailShowXEnabled())
        configure(bottomRailShowShuffleCheckbox,  title: "Shuffle",        state: Self.isBottomRailShowShuffleEnabled())
        configure(bottomRailShowReplayCheckbox,   title: "Replay",         state: Self.isBottomRailShowReplayEnabled())
        configure(bottomRailShowVolumeCheckbox,   title: "Volume",         state: Self.isBottomRailShowVolumeEnabled())
        configure(bottomRailShowBookmarkCheckbox, title: "Bookmark",       state: Self.isBottomRailShowBookmarkEnabled())
        bottomRailShowXCheckbox.setAccessibilityLabel("Show prefix buttons in playback bar")
        bottomRailShowShuffleCheckbox.setAccessibilityLabel("Show Shuffle button in playback bar")
        bottomRailShowReplayCheckbox.setAccessibilityLabel("Show Replay button in playback bar")
        bottomRailShowVolumeCheckbox.setAccessibilityLabel("Show Volume button in playback bar")
        bottomRailShowBookmarkCheckbox.setAccessibilityLabel("Show Bookmark button in playback bar")
        bottomRailShowXCheckbox.setAccessibilityIdentifier("settings.controls.showPrefixButtons")
        bottomRailShowShuffleCheckbox.setAccessibilityIdentifier("settings.controls.showShuffle")
        bottomRailShowReplayCheckbox.setAccessibilityIdentifier("settings.controls.showRepeat")
        bottomRailShowVolumeCheckbox.setAccessibilityIdentifier("settings.controls.showVolume")
        bottomRailShowBookmarkCheckbox.setAccessibilityIdentifier("settings.controls.showBookmark")

        let section1 = buildSection(title: "Playback bar behavior", rows: [
            buildRow(label: "Auto-hide delay", control: chromeAutohideThresholdPopup),
            buildRow(label: nil, control: chromeReducedMotionCheckbox)
        ])

        // Design system 9.5: rail buttons as a 2-column checkbox grid.
        let railButtonsGrid = NSGridView(views: [
            [bottomRailShowXCheckbox, NSGridCell.emptyContentView],
            [bottomRailShowShuffleCheckbox, bottomRailShowReplayCheckbox],
            [bottomRailShowVolumeCheckbox, bottomRailShowBookmarkCheckbox]
        ])
        railButtonsGrid.rowSpacing = DWBMetrics.rowGap
        railButtonsGrid.columnSpacing = DWBMetrics.columnGap
        railButtonsGrid.xPlacement = .leading
        railButtonsGrid.rowAlignment = .firstBaseline
        railButtonsGrid.translatesAutoresizingMaskIntoConstraints = false

        let section1b = buildSection(title: "Playback bar buttons", rows: [
            buildRow(label: nil, control: railButtonsGrid)
        ])

        let section4 = buildSection(title: "Window chrome", rows: [
            buildRow(label: nil, control: autoHideTitlebarCheckbox),
            buildRow(label: nil, control: completeVideoWindowModeCheckbox),
            buildRow(label: "Window opacity", control: opacityStack, helperLabel: windowOpacityTargetLabel)
        ])

        return buildPage(index: 1, sections: [section1, section1b, section4])
    }

    // MARK: - Section: Queue & Files

    private func buildQueueFilesSection() -> NSView {
        configure(queuePanelOpenAtLaunchCheckbox, title: "Open Queue Page with new player windows", state: UserDefaults.standard.bool(forKey: Self.queuePanelOpenAtLaunchKey))
        queuePanelOpenAtLaunchCheckbox.setAccessibilityIdentifier("settings.queue.openAtLaunch")

        customPrefixValueTextField.usesMonospacedFont = true
        customPrefixValueTextField.placeholderString = "e.g. x_"
        customPrefixValueTextField.stringValue = Self.storedCustomPrefixValue()
        customPrefixValueTextField.delegate = self
        customPrefixValueTextField.toolTip = "Primary prefix added to the start of the filename. The N key, the queue's primary prefix chip and the rail's prefix button use it. The \"/\" character is not allowed."
        customPrefixValueTextField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        customPrefixValueTextField.setAccessibilityIdentifier("settings.queue.primaryPrefix")

        customPrefixSecondaryValueTextField.usesMonospacedFont = true
        customPrefixSecondaryValueTextField.placeholderString = "e.g. fav_"
        customPrefixSecondaryValueTextField.stringValue = Self.storedCustomPrefixSecondaryValue()
        customPrefixSecondaryValueTextField.delegate = self
        customPrefixSecondaryValueTextField.toolTip = "Secondary prefix. The M key, the queue's secondary prefix chip and the rail's second prefix button use it. Leave empty to use one prefix only. The \"/\" character is not allowed."
        customPrefixSecondaryValueTextField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        customPrefixSecondaryValueTextField.setAccessibilityIdentifier("settings.queue.secondaryPrefix")

        let section1 = buildSection(title: "Queue page rename", rows: [
            buildRow(label: "Primary prefix", control: customPrefixValueTextField,
                     helperText: "N, the queue's primary prefix chip and the rail's prefix button apply this prefix. Format: prefix + filename stem + extension. Each prefix ends in exactly one underscore: keep, keep_ and keep__ all give keep_.",
                     swatch: PlayerTheme.current.markerPrimary),
            buildRow(label: "Secondary prefix", control: customPrefixSecondaryValueTextField,
                     helperText: "M, the queue's secondary prefix chip and the rail's second prefix button apply this prefix. Leave empty to use one prefix only.",
                     swatch: PlayerTheme.current.markerSecondary)
        ])

        let section3 = buildSection(title: "Queue behavior", rows: [
            buildRow(label: nil, control: queuePanelOpenAtLaunchCheckbox)
        ])

        return buildPage(index: 2, sections: [section1, section3])
    }

    // MARK: - Section: Advanced

    private func buildAdvancedSection() -> NSView {
        configure(debugConsoleCheckbox, title: "Show debug console", state: Self.isDebugConsoleEnabled())
        configure(verboseAutoplayTraceCheckbox, title: "Verbose autoplay trace (debug builds only)", state: Self.isVerboseAutoplayTraceEnabled())
        debugConsoleCheckbox.setAccessibilityIdentifier("settings.advanced.debugConsole")
        verboseAutoplayTraceCheckbox.setAccessibilityIdentifier("settings.advanced.verboseAutoplay")
        restoreDefaultsButton.target = self
        restoreDefaultsButton.action = #selector(restoreAllSettingsToDefault(_:))
        restoreDefaultsButton.setAccessibilityIdentifier("settings.advanced.restoreDefaults")

        clearBookmarksButton.target = self
        clearBookmarksButton.action = #selector(clearAllBookmarks(_:))
        clearBookmarksButton.setAccessibilityIdentifier("settings.advanced.clearBookmarks")

        let section1 = buildSection(title: "Diagnostics", rows: [
            buildRow(label: nil, control: debugConsoleCheckbox),
            buildRow(label: nil, control: verboseAutoplayTraceCheckbox)
        ])

        let section2 = buildSection(title: "Bookmarks", rows: [
            buildRow(label: nil, control: clearBookmarksButton,
                     helperText: "Bookmarks are stored locally on this device and may include full file paths of bookmarked media. Clearing is permanent and cannot be undone.")
        ])

        let section3 = buildSection(title: "Reset", rows: [
            buildRow(label: nil, control: restoreDefaultsButton,
                     helperText: "Restores dwb player preferences. Media files, queues, and bookmarks are not deleted.")
        ])

        return buildPage(index: 4, sections: [section1, section2, section3])
    }

    // MARK: - Section: About

    private func buildAboutSection() -> NSView {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = info?["CFBundleVersion"]            as? String ?? "—"

        // No page header: About carries its own identity block (design system 9.5).
        let about = AboutPageView(
            version: version,
            build: build,
            description: "Local media playback for macOS",
            facts: [
                ("License", "MIT License"),
                ("System", "macOS 13 or later"),
                ("Interface", "AppKit"),
                ("Playback", "VLCKit \(Self.vlcBackendVersionText())")
            ],
            links: [
                AboutPageView.Link(title: "View on GitHub", identifier: "settings.about.github") { [weak self] in
                    self?.openGitHubRepository(NSNull())
                },
                AboutPageView.Link(title: "Report an Issue", identifier: "settings.about.issues") { [weak self] in
                    self?.openGitHubIssues(NSNull())
                }
            ],
            copyright: "© dwb"
        )
        return buildPage(index: 5, sections: [about], showsHeader: false)
    }

    // MARK: - Section: Shortcuts

    private func buildShortcutsSection() -> NSView {
        let shortcuts = ShortcutsPageView()
        let section = NSStackView(views: [shortcuts])
        section.orientation = .vertical
        section.alignment = .leading
        section.translatesAutoresizingMaskIntoConstraints = false
        shortcuts.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return buildPage(index: 3, sections: [section])
    }

    // MARK: - Layout helpers

    private func configure(_ btn: NSButton, title: String, state: Bool) {
        // Standard AppKit checkbox, tinted by the AccentColor asset; only the label
        // is styled so it reads on the dark page.
        btn.setButtonType(.switch)
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: DWBColor.textPrimary
        ])
        btn.target = self
        btn.action = #selector(checkboxToggled(_:))
        btn.state  = state ? .on : .off
        btn.contentTintColor = nil
        btn.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Flat settings section with an accent header and no card chrome.
    private func buildSection(title: String?, rows: [NSView]) -> NSView {
        var views = rows
        if let title {
            let header = NSTextField(labelWithString: title)
            header.font = .systemFont(ofSize: 11, weight: .semibold)
            header.textColor = PlayerTheme.current.accentText
            header.translatesAutoresizingMaskIntoConstraints = false
            header.setAccessibilityRole(.staticText)
            views.insert(header, at: 0)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DWBMetrics.rowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// `helperLabel` passes in a helper label the controller updates later; it is styled
    /// the same as one built from `helperText`.
    private func buildRow(label: String?,
                          control: NSView,
                          helperText: String? = nil,
                          helperLabel: NSTextField? = nil,
                          swatch: NSColor? = nil) -> NSView {
        let controlColumn = NSStackView()
        controlColumn.orientation = .vertical
        controlColumn.alignment = .leading
        controlColumn.spacing = 5
        controlColumn.translatesAutoresizingMaskIntoConstraints = false
        controlColumn.addArrangedSubview(control)

        if let note = helperLabel ?? helperText.map({ NSTextField(wrappingLabelWithString: $0) }) {
            note.font = .systemFont(ofSize: 11)
            note.textColor = DWBAppearance.shared.textTertiary
            note.isEditable = false
            note.isSelectable = false
            note.isBordered = false
            note.drawsBackground = false
            note.preferredMaxLayoutWidth = 390
            note.translatesAutoresizingMaskIntoConstraints = false
            note.widthAnchor.constraint(lessThanOrEqualToConstant: 390).isActive = true
            contrastRefreshers.append { note.textColor = DWBAppearance.shared.textTertiary }
            controlColumn.addArrangedSubview(note)
        }

        guard let labelText = label else { return controlColumn }

        // Labels wrap inside the 156 pt column rather than truncating.
        let lbl = NSTextField(wrappingLabelWithString: labelText)
        lbl.font = .systemFont(ofSize: 13)
        lbl.textColor = DWBColor.textPrimary
        lbl.isEditable = false
        lbl.isSelectable = false
        lbl.isBordered = false
        lbl.drawsBackground = false
        lbl.maximumNumberOfLines = 2
        lbl.preferredMaxLayoutWidth = DWBMetrics.labelColumn
        lbl.translatesAutoresizingMaskIntoConstraints = false

        // The label column is 156 pt wide and starts level with the first control row
        // (4 pt top padding on a 24 pt control row).
        let labelColumn = NSView()
        labelColumn.translatesAutoresizingMaskIntoConstraints = false
        labelColumn.addSubview(lbl)
        var constraints: [NSLayoutConstraint] = [
            labelColumn.widthAnchor.constraint(equalToConstant: DWBMetrics.labelColumn),
            labelColumn.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            lbl.topAnchor.constraint(equalTo: labelColumn.topAnchor, constant: 4),
            lbl.bottomAnchor.constraint(lessThanOrEqualTo: labelColumn.bottomAnchor)
        ]
        if let swatch {
            let dot = SettingsSwatchView(color: swatch)
            labelColumn.addSubview(dot)
            constraints += [
                dot.leadingAnchor.constraint(equalTo: labelColumn.leadingAnchor),
                dot.centerYAnchor.constraint(equalTo: lbl.firstBaselineAnchor, constant: -4.5),
                dot.widthAnchor.constraint(equalToConstant: DWBMetrics.prefixSwatch),
                dot.heightAnchor.constraint(equalToConstant: DWBMetrics.prefixSwatch),
                lbl.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6)
            ]
        } else {
            constraints.append(lbl.leadingAnchor.constraint(equalTo: labelColumn.leadingAnchor))
        }
        constraints.append(lbl.trailingAnchor.constraint(lessThanOrEqualTo: labelColumn.trailingAnchor))
        NSLayoutConstraint.activate(constraints)

        let row = NSStackView(views: [labelColumn, controlColumn])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = DWBMetrics.columnGap
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// One Settings page: the shared header (20 pt title, one-line description, hairline)
    /// above flat sections, inside a scroll view with the design system's page insets.
    /// About passes `showsHeader: false`; it carries no page header (9.5).
    private func buildPage(index: Int, sections: [NSView], showsHeader: Bool = true) -> NSView {
        let page = SettingsPages.all[index]

        let headerBlock: NSView? = showsHeader ? makeSettingsPageHeader(for: page) : nil

        let stack = NSStackView(views: (headerBlock.map { [$0] } ?? []) + sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DWBMetrics.sectionGap
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DWBColor.surface
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = SettingsFlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        // Page insets from `DWBMetrics.insets`. The 54 pt top inset is measured from the
        // window's top edge, so the standard title bar supplies the first 30 pt.
        let insets = DWBMetrics.insets
        let topInset = max(0, insets.top - 30)
        let trailing = stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -insets.right)
        trailing.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: topInset),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: insets.left),
            trailing,
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: DWBMetrics.contentMax),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -insets.bottom)
        ])
        headerBlock?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for section in sections {
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        scrollView.documentView = documentView
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        container.setAccessibilityLabel("\(page.name) settings")

        return container
    }

    /// The shared page header: 20 pt title, one-line description and a hairline.
    private func makeSettingsPageHeader(for page: SettingsPages.Page) -> NSView {
        let title = NSTextField(labelWithString: page.name)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = DWBColor.textPrimary
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setAccessibilityRole(.staticText)
        title.setAccessibilityIdentifier("settings.page.\(page.identifier).title")

        let description = NSTextField(wrappingLabelWithString: page.description)
        description.font = .systemFont(ofSize: 11.5)
        description.textColor = DWBAppearance.shared.textSecondary
        description.isSelectable = false
        description.preferredMaxLayoutWidth = DWBMetrics.contentMax
        description.translatesAutoresizingMaskIntoConstraints = false
        description.setAccessibilityIdentifier("settings.page.\(page.identifier).description")
        contrastRefreshers.append { description.textColor = DWBAppearance.shared.textSecondary }

        let hairline = SettingsHairlineView()
        hairline.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [title, description])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        let headerBlock = NSView()
        headerBlock.translatesAutoresizingMaskIntoConstraints = false
        headerBlock.addSubview(header)
        headerBlock.addSubview(hairline)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: headerBlock.topAnchor),
            header.leadingAnchor.constraint(equalTo: headerBlock.leadingAnchor),
            header.trailingAnchor.constraint(lessThanOrEqualTo: headerBlock.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            hairline.leadingAnchor.constraint(equalTo: headerBlock.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: headerBlock.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            hairline.bottomAnchor.constraint(equalTo: headerBlock.bottomAnchor)
        ])

        return headerBlock
    }

    // MARK: - Actions

    @objc private func checkboxToggled(_ sender: NSButton) {
        let enabled = sender.state == .on

        if sender === autoHideTitlebarCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.autoHideTitlebarKey)
            NotificationCenter.default.post(name: .autoHideTitlebarChanged, object: nil)
            DebugConsoleController.log("settings", "autoHideTitlebar=\(enabled)")
            return
        }
        if sender === completeVideoWindowModeCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.completeVideoWindowModeKey)
            NotificationCenter.default.post(name: .completeVideoWindowModeChanged, object: nil)
            DebugConsoleController.log("settings", "completeVideoWindowMode=\(enabled)")
            return
        }
        if sender === showTitleOverlayCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.showTitleOverlayKey)
            NotificationCenter.default.post(name: .titleOverlaySettingChanged, object: nil)
            DebugConsoleController.log("settings", "showTitleOverlay=\(enabled)")
            return
        }
        if sender === acceptVideoCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.acceptVideoKey)
            NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: nil)
            DebugConsoleController.log("settings", "acceptVideo=\(enabled)")
            return
        }
        if sender === acceptImagesCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.acceptImagesKey)
            NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: nil)
            DebugConsoleController.log("settings", "acceptImages=\(enabled)")
            return
        }
        if sender === acceptGIFCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.acceptGIFKey)
            NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: nil)
            DebugConsoleController.log("settings", "acceptGIF=\(enabled)")
            return
        }
        if sender === debugConsoleCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.debugConsoleKey)
            NotificationCenter.default.post(name: .debugConsoleSettingChanged, object: nil)
            return
        }
        if sender === verboseAutoplayTraceCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.verboseAutoplayTraceKey)
            return
        }
        if sender === chromeReducedMotionCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.chromeReducedMotionKey)
            NotificationCenter.default.post(name: .transportVisibilityChanged, object: nil)
            DebugConsoleController.log("settings", "chromeReducedMotion=\(enabled)")
            return
        }
        if sender === queuePanelOpenAtLaunchCheckbox {
            UserDefaults.standard.set(enabled, forKey: Self.queuePanelOpenAtLaunchKey)
            DebugConsoleController.log("settings", "queuePanelOpenAtLaunch=\(enabled)")
            return
        }
        let bottomRailKey: String?
        switch sender {
        case bottomRailShowXCheckbox:        bottomRailKey = Self.bottomRailShowXKey
        case bottomRailShowShuffleCheckbox:  bottomRailKey = Self.bottomRailShowShuffleKey
        case bottomRailShowReplayCheckbox:   bottomRailKey = Self.bottomRailShowReplayKey
        case bottomRailShowVolumeCheckbox:   bottomRailKey = Self.bottomRailShowVolumeKey
        case bottomRailShowBookmarkCheckbox: bottomRailKey = Self.bottomRailShowBookmarkKey
        default: bottomRailKey = nil
        }
        if let key = bottomRailKey {
            UserDefaults.standard.set(enabled, forKey: key)
            NotificationCenter.default.post(name: .bottomRailButtonVisibilityChanged, object: nil)
            DebugConsoleController.log("settings", "\(key)=\(enabled)")
            return
        }
    }

    @objc private func skipDurationPopupChanged(_ sender: NSPopUpButton) {
        let selected = Self.validatedSkipDurationSeconds(sender.selectedTag())
        UserDefaults.standard.set(selected, forKey: Self.skipDurationKey)
        NotificationCenter.default.post(name: .skipDurationChanged, object: nil)
        DebugConsoleController.log("settings", "skipDuration=\(selected)s")
        syncUIFromDefaults()
    }

    @objc private func imageDurationPopupChanged(_ sender: NSPopUpButton) {
        let selected = Self.validatedImageDurationSeconds(Self.imageDurationSeconds(forTag: sender.selectedTag()))
        UserDefaults.standard.set(selected, forKey: Self.imageDurationKey)
        NotificationCenter.default.post(name: .imageDurationChanged, object: nil)
        DebugConsoleController.log("settings", "imageDuration=\(selected)s")
        syncUIFromDefaults()
    }

    @objc private func gifLoopCountPopupChanged(_ sender: NSPopUpButton) {
        let selected = Self.validatedGIFLoopCount(sender.selectedTag())
        UserDefaults.standard.set(selected, forKey: Self.gifLoopCountKey)
        NotificationCenter.default.post(name: .gifLoopCountChanged, object: nil)
        DebugConsoleController.log("settings", "gifLoopCount=\(selected)")
        syncUIFromDefaults()
    }

    @objc private func playbackSpeedPopupChanged(_ sender: NSPopUpButton) {
        guard let option = PlaybackSpeedOption.option(forTag: sender.selectedTag()) else { return }
        targetPlayerWindowController()?.setPlaybackSpeed(option.rate, source: "settings")
        syncPlaybackSpeedControlsFromTarget()
    }

    @objc private func chromeThresholdPopupChanged(_ sender: NSPopUpButton) {
        let seconds = Double(sender.selectedTag()) / 10.0
        UserDefaults.standard.set(seconds, forKey: Self.chromeAutohideThresholdKey)
        NotificationCenter.default.post(name: .transportVisibilityChanged, object: nil)
        DebugConsoleController.log("settings", "chromeAutohideThreshold=\(seconds)s")
        syncUIFromDefaults()
    }

    /// Opacity is window-only: the slider and reset change the target window and store nothing.
    @objc private func windowOpacitySliderChanged(_ sender: NSSlider) {
        setTargetWindowOpacity(CGFloat(sender.doubleValue / 100.0))
    }

    @objc private func resetWindowOpacity(_ sender: NSButton) {
        setTargetWindowOpacity(Self.defaultPlayerWindowOpacityValue)
    }

    private func setTargetWindowOpacity(_ value: CGFloat) {
        guard let target = targetPlayerWindowController() else {
            syncTargetControls()
            return
        }
        let opacity = Self.clampedPlayerWindowOpacity(value)
        target.setWindowOpacityFromSettings(opacity)
        updateWindowOpacityControls(opacity)
        DebugConsoleController.log("settings", "windowOpacity: window=\(target.debugIdentity) value=\(Self.playerWindowOpacityPercent(opacity))%")
    }

    /// Volume is window-only like opacity; the window stores it as the new-window default (D-010).
    @objc private func windowVolumeSliderChanged(_ sender: NSSlider) {
        setTargetWindowVolume(VolumePolicy.volume(forSliderValue: sender.doubleValue))
    }

    @objc private func resetWindowVolume(_ sender: NSButton) {
        setTargetWindowVolume(VolumePolicy.normalVolume)
    }

    private func setTargetWindowVolume(_ value: Int32) {
        guard let target = targetPlayerWindowController() else {
            syncTargetControls()
            return
        }
        let volume = VolumePolicy.clamped(value)
        target.setVolumeFromSettings(volume)
        updateWindowVolumeControls(target.currentEffectiveVolume)
        DebugConsoleController.log("settings", "windowVolume: window=\(target.debugIdentity) value=\(volume)%")
    }

    @objc private func restoreAllSettingsToDefault(_ sender: Any) {
        DWBConfirmSheet.present(
            on: window,
            title: "Restore all settings to default?",
            message: "This resets dwb player preferences. It does not delete media files, queues, or bookmarks.",
            confirmTitle: "Restore Defaults"
        ) { [weak self] in
            self?.performRestoreSettingsDefaults()
        }
    }

    private func performRestoreSettingsDefaults() {
        Self.restoreSettingsDefaults()
        syncUIFromDefaults()
        DebugConsoleController.log("settings", "restoreDefaults")
    }

    @objc private func clearAllBookmarks(_ sender: Any) {
        DWBConfirmSheet.present(
            on: window,
            title: "Clear all bookmarks?",
            message: "Bookmarks are stored locally and can include full file paths. This cannot be undone.",
            confirmTitle: "Clear Bookmarks"
        ) {
            BookmarkStore.shared.clearAll()
            DebugConsoleController.log("settings", "clearAllBookmarks")
        }
    }

    @objc private func openGitHubRepository(_ sender: Any) {
        guard let url = URL(string: Self.githubURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openGitHubIssues(_ sender: Any) {
        guard let url = URL(string: Self.githubIssuesURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func settingsWindowDidBecomeKey(_ notification: Notification) {
        syncTargetControls()
    }

    @objc private func playerWindowTargetingDidChange(_ notification: Notification) {
        syncTargetControls()
    }

    @objc private func settingsWindowVisibilityDidChange(_ notification: Notification) {
        syncTargetControls()
    }

    @objc private func settingsWindowWillClose(_ notification: Notification) {
        syncTargetControls(settingsClosing: true)
    }

    @objc private func playbackSpeedDidChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        syncPlaybackSpeedControlsFromTarget()
    }

    @objc private func windowVolumeDidChange(_ notification: Notification) {
        guard window?.isVisible == true,
              let target = targetPlayerWindowController(),
              notification.object as AnyObject? === target else { return }
        updateWindowVolumeControls(target.currentEffectiveVolume)
    }

    @objc private func anyWindowDidBecomeKey(_ notification: Notification) {
        guard let becameKeyWin = notification.object as? NSWindow,
              becameKeyWin !== window,
              window?.isVisible == true,
              becameKeyWin.windowController is PlayerWindowController else { return }
        window?.order(.above, relativeTo: becameKeyWin.windowNumber)
        syncTargetControls()
    }

    @objc private func appDidBecomeActive(_ notification: Notification) {
        orderAbovePlayerWindows()
        syncTargetControls()
    }

    private func orderAbovePlayerWindows() {
        guard let settingsWin = window, settingsWin.isVisible else { return }
        guard let frontmostPlayerWin = NSApp.orderedWindows.first(where: {
            $0 !== settingsWin && ($0.windowController is PlayerWindowController)
        }) else { return }
        settingsWin.order(.above, relativeTo: frontmostPlayerWin.windowNumber)
    }

    // MARK: - Sync

    private func syncUIFromDefaults() {
        customPrefixValueTextField.stringValue          = Self.storedCustomPrefixValue()
        customPrefixSecondaryValueTextField.stringValue = Self.storedCustomPrefixSecondaryValue()
        autoHideTitlebarCheckbox.state         = Self.isAutoHideTitlebarEnabled()      ? .on : .off
        completeVideoWindowModeCheckbox.state  = Self.isCompleteVideoWindowModeEnabled() ? .on : .off
        showTitleOverlayCheckbox.state         = Self.isShowTitleOverlayEnabled()      ? .on : .off
        acceptVideoCheckbox.state              = Self.acceptsVideoMedia()             ? .on : .off
        acceptImagesCheckbox.state             = Self.acceptsImageMedia()             ? .on : .off
        acceptGIFCheckbox.state                = Self.acceptsGIFMedia()               ? .on : .off
        debugConsoleCheckbox.state             = Self.isDebugConsoleEnabled()          ? .on : .off
        verboseAutoplayTraceCheckbox.state     = Self.isVerboseAutoplayTraceEnabled()  ? .on : .off
        chromeReducedMotionCheckbox.state      = UserDefaults.standard.bool(forKey: Self.chromeReducedMotionKey)     ? .on : .off
        queuePanelOpenAtLaunchCheckbox.state   = UserDefaults.standard.bool(forKey: Self.queuePanelOpenAtLaunchKey) ? .on : .off
        bottomRailShowXCheckbox.state          = Self.isBottomRailShowXEnabled()        ? .on : .off
        bottomRailShowShuffleCheckbox.state    = Self.isBottomRailShowShuffleEnabled()  ? .on : .off
        bottomRailShowReplayCheckbox.state     = Self.isBottomRailShowReplayEnabled()   ? .on : .off
        bottomRailShowVolumeCheckbox.state     = Self.isBottomRailShowVolumeEnabled()   ? .on : .off
        bottomRailShowBookmarkCheckbox.state   = Self.isBottomRailShowBookmarkEnabled() ? .on : .off

        skipDurationPopup.selectItem(withTag: Self.currentSkipDurationSeconds())
        syncPlaybackSpeedControlsFromTarget()
        imageDurationPopup.selectItem(withTag: Self.imageDurationTag(for: Self.currentImageDurationSeconds()))
        gifLoopCountPopup.selectItem(withTag: Self.currentGIFLoopCount())

        let rawThreshold = UserDefaults.standard.double(forKey: Self.chromeAutohideThresholdKey)
        let threshold    = rawThreshold > 0 ? rawThreshold : 3.0
        let tag          = Self.chromeThresholdTag(for: threshold)
        chromeAutohideThresholdPopup.selectItem(withTag: tag)
        if chromeAutohideThresholdPopup.selectedItem == nil {
            chromeAutohideThresholdPopup.selectItem(withTag: Self.chromeThresholdTag(for: 3.0))
        }
        syncTargetControls()
    }

    /// Re-reads the target player window into the opacity and volume sliders and readouts,
    /// the speed popup, the helper labels, the enabled states, and the target outline.
    private func syncTargetControls(settingsClosing: Bool = false) {
        let target = targetPlayerWindowController()
        updateWindowOpacityControls(target?.currentWindowOpacity ?? Self.defaultPlayerWindowOpacityValue)
        updateWindowVolumeControls(target?.currentEffectiveVolume ?? PlayerWindowController.defaultPersistedVolume())
        syncPlaybackSpeedControlsFromTarget()

        let helperText = PlayerWindowTargeting.settingsHelperText(targetTitle: target?.window?.title)
        playbackSpeedTargetLabel.stringValue = helperText
        windowOpacityTargetLabel.stringValue = helperText
        windowVolumeTargetLabel.stringValue = helperText
        let hasTarget = target != nil
        windowOpacitySlider.isEnabled = hasTarget
        windowOpacityResetButton.isEnabled = hasTarget
        windowVolumeSlider.isEnabled = hasTarget
        windowVolumeResetButton.isEnabled = hasTarget
        playbackSpeedPopup.isEnabled = hasTarget

        updateTargetOutline(target: isOnScreenForOutline(settingsClosing: settingsClosing) ? target : nil)
    }

    /// Settings shows the outline only while it is visible, not minimized, and not hidden
    /// with the app (the panel hides when the app deactivates).
    private func isOnScreenForOutline(settingsClosing: Bool) -> Bool {
        guard !settingsClosing, let settingsWin = window,
              settingsWin.isVisible, !settingsWin.isMiniaturized, !NSApp.isHidden else { return false }
        return NSApp.isActive || !settingsWin.hidesOnDeactivate
    }

    private func updateTargetOutline(target: PlayerWindowController?) {
        if outlinedPlayerWindowController !== target {
            outlinedPlayerWindowController?.setSettingsTargetOutlineVisible(false)
            outlinedPlayerWindowController = target
        }
        target?.setSettingsTargetOutlineVisible(true)
    }

    private func syncPlaybackSpeedControlsFromTarget() {
        let rate = targetPlayerWindowController()?.currentPlaybackSpeed
            ?? PlaybackSpeedOption.normalRate
        let option = PlaybackSpeedOption.validated(rate)
        playbackSpeedPopup.selectItem(withTag: option.tag)
    }

    private func updateWindowOpacityControls(_ opacity: CGFloat) {
        let clamped = Self.clampedPlayerWindowOpacity(opacity)
        windowOpacitySlider.doubleValue = Double(clamped * 100.0)
        windowOpacityPercentLabel.stringValue = "\(Self.playerWindowOpacityPercent(clamped))%"
    }

    private func updateWindowVolumeControls(_ volume: Int32) {
        let clamped = VolumePolicy.clamped(volume)
        windowVolumeSlider.doubleValue = Double(clamped)
        windowVolumePercentLabel.stringValue = VolumePolicy.percentText(clamped)
    }

    /// The on-screen player window that most recently became key (`PlayerWindowTargeting`).
    private func targetPlayerWindowController() -> PlayerWindowController? {
        guard let controllers = (NSApp.delegate as? AppDelegate)?.windowControllers else { return nil }
        let targetID = PlayerWindowTargeting.settingsTarget(windows: controllers.map { $0.targetingSnapshot() })
        return controllers.first { ObjectIdentifier($0) == targetID }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === customPrefixValueTextField {
            let prefix = field.stringValue
            guard !prefix.contains("/"), !prefix.contains("\0") else { return }
            UserDefaults.standard.set(prefix, forKey: Self.customPrefixValueKey)
            NotificationCenter.default.post(name: .customPrefixValueChanged, object: nil)
            DebugConsoleController.log("settings", "customPrefixValue='\(prefix)'")
        } else if field === customPrefixSecondaryValueTextField {
            let prefix = field.stringValue
            guard !prefix.contains("/"), !prefix.contains("\0") else { return }
            UserDefaults.standard.set(prefix, forKey: Self.customPrefixSecondaryValueKey)
            NotificationCenter.default.post(name: .customPrefixValueChanged, object: nil)
            DebugConsoleController.log("settings", "customPrefixSecondaryValue='\(prefix)'")
        }
    }

    // MARK: - Open

    func openSettings() {
        syncUIFromDefaults()
        if !(window?.isVisible ?? false) {
            window?.center()
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        orderAbovePlayerWindows()
        syncTargetControls()
    }

    func openAcceptSettings() {
        selectSection(0)
        openSettings()
    }
}

// MARK: - Settings sidebar item
// 32 pt row, radius 6. Selected: `accentTintStrong` fill, 1 pt `accentFill` ring, semibold
// text. Focus: 2 pt ring (3 pt in `accentText` under Increase Contrast).

private final class SettingsSidebarItemButton: NSButton {
    let sectionIndex: Int
    private let itemTitle: String
    private var isHovering = false
    private var isPressing = false
    private var trackingAreaReference: NSTrackingArea?
    /// Called with -1 (Up Arrow) or +1 (Down Arrow); the controller moves the selection.
    var onNavigate: ((Int) -> Void)?

    var isSelected: Bool = false {
        didSet {
            setAccessibilityValue(isSelected ? "selected" : "not selected")
            updateAppearance()
        }
    }

    init(title: String,
         sectionIndex: Int,
         accessibilityIdentifier: String,
         target: AnyObject?,
         action: Selector) {
        self.sectionIndex = sectionIndex
        self.itemTitle = title
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.radiusControl
        layer?.borderWidth = 1
        setAccessibilityLabel(title)
        setAccessibilityHelp("Show \(title) settings")
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityValue("not selected")
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool {
        isEnabled && !isHidden
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        updateAppearance()
        super.mouseDown(with: event)
        isPressing = false
        updateAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateAppearance()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateAppearance()
        return resigned
    }

    override var isEnabled: Bool {
        didSet {
            setAccessibilityEnabled(isEnabled)
            updateAppearance()
        }
    }

    /// Up/Down arrows switch pages across both sidebar groups.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onNavigate?(-1)  // Up Arrow
        case 125: onNavigate?(1)   // Down Arrow
        default:  super.keyDown(with: event)
        }
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 12
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let appearance = DWBAppearance.shared
        let focused = window?.firstResponder === self
        let font: NSFont
        if isSelected {
            layer?.backgroundColor = PlayerTheme.current.accentTintStrong.cgColor
            font = .systemFont(ofSize: 13, weight: .semibold)
        } else {
            layer?.backgroundColor = (isPressing ? DWBColor.overlayPressed : isHovering ? DWBColor.overlayHover : NSColor.clear).cgColor
            font = .systemFont(ofSize: 13, weight: .regular)
        }

        let borderColor: NSColor
        if focused {
            borderColor = appearance.focusRingColor
        } else if isSelected {
            borderColor = PlayerTheme.current.accentFill
        } else {
            borderColor = .clear
        }
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = focused ? appearance.focusRingWidth : 1
        alphaValue = isEnabled ? 1.0 : DWBMetrics.disabledAlpha

        attributedTitle = NSAttributedString(string: itemTitle, attributes: [
            .paragraphStyle: paragraphStyle,
            .foregroundColor: DWBColor.textPrimary,
            .font: font,
        ])
    }
}

// MARK: - Appearance-aware separators and small views

private final class SettingsSeparatorLine: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = DWBAppearance.shared.border.cgColor
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }
}

/// The 1 pt `gridLine` rule under a page header.
private final class SettingsHairlineView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = DWBColor.gridLine.cgColor
    }
}

/// The 8 pt marker-color dot beside the prefix row labels.
private final class SettingsSwatchView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.prefixSwatch / 2
        layer?.backgroundColor = color.cgColor
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}
