import Cocoa
import VLCKitSPM

final class BottomRailView: NSView {
    weak var player: VLCMediaPlayer?
    weak var controller: PlayerWindowController?

    var scrubDidBegin: (() -> Void)?
    var scrubDidEnd: (() -> Void)?

    private let veil = NSView()
    private let hairline = NSView()
    private let queueButton = RailButton()
    private let dPrefixButton = RailButton()
    private let secondaryPrefixButton = RailButton()
    private let rewindButton = RailButton()
    private let prevButton = RailButton()
    private let playPauseButton = RailButton()
    private let nextButton = RailButton()
    private let forwardButton = RailButton()
    private let volumeButton = RailButton()
    private let shuffleButton = RailButton()
    private let repeatButton = RailButton()
    private let bookmarkButton = RailButton()
    private let moreButton = RailButton()
    private let settingsButton = RailButton()
    private let fullscreenButton = RailButton()
    private let elapsedLabel = NSTextField(labelWithString: "-:--")
    private let remainingLabel = NSTextField(labelWithString: "-:--")
    private let scrubber = ScrubberSlider()

    private var preMuteVolume: Int32 = 100
    private var isScrubbing = false
    private var isFullscreenStyle = false
    private var pendingSeekPosition: Float?
    private var pendingSeekDate: Date?
    private let pendingSeekTimeout: TimeInterval = 1.5

    var isImageMode: Bool = false
    var isGIFMode: Bool = false
    var imageModeElapsed: Double = 0
    var imageModeDuration: Double = 3
    var imageModeIsPlaying: Bool = true

    private var cachedPlayPauseSymbol: String?
    private var cachedVolumeSymbol: String?
    private var cachedRepeatSymbol: String?
    private var cachedElapsedText: String?
    private var cachedRemainingText: String?
    private var cachedScrubberValue = -1.0
    private var accessibilityVisible = true
    private var railTrackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isMoreMenuOpen = false

    var interactionStateDidChange: (() -> Void)?

    var hasActiveInteraction: Bool {
        isPointerInside || isMoreMenuOpen || containsFirstResponder
    }

    private var containsFirstResponder: Bool {
        guard var view = window?.firstResponder as? NSView else { return false }
        while true {
            if view === self { return true }
            guard let parent = view.superview else { return false }
            view = parent
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupViews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBottomRailButtonVisibilityChanged),
            name: .bottomRailButtonVisibilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCustomPrefixValueChanged),
            name: .customPrefixValueChanged,
            object: nil
        )
        PlayerAccessibilityEnvironment.observeChanges(self, selector: #selector(accessibilityOptionsChanged))
    }

    required init?(coder: NSCoder) {
        fatalError("programmatic only")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        PlayerAccessibilityEnvironment.stopObserving(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let railTrackingArea {
            removeTrackingArea(railTrackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        railTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        interactionStateDidChange?()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        interactionStateDidChange?()
    }

    @objc private func accessibilityOptionsChanged() {
        applyRailChrome()
        applyTimeLabelColor()
        scrubber.needsDisplay = true
    }

    /// Rail backing and top hairline; the backing becomes opaque under Increase Contrast.
    private func applyRailChrome() {
        let increased = PlayerAccessibilityEnvironment.increaseContrast
        veil.layer?.backgroundColor = OverlayBacking.resolved(DWBColor.backingChrome, increaseContrast: increased).cgColor
        hairline.layer?.backgroundColor = (increased ? DWBColor.borderStrong : DWBColor.hairline).cgColor
    }

    private func applyTimeLabelColor() {
        let color = PlayerAccessibilityEnvironment.increaseContrast ? DWBColor.textPrimary : DWBColor.textSecondary
        elapsedLabel.textColor = color
        remainingLabel.textColor = color
    }

    @objc private func handleBottomRailButtonVisibilityChanged() {
        applyVisibilitySettings()
    }

    @objc private func handleCustomPrefixValueChanged() {
        updatePrefixButtonLabels()
        applyVisibilitySettings()
    }

    fileprivate static func trimmedPrefix(_ prefix: String) -> String {
        prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func railPrefixLabel(_ prefix: String) -> String {
        let trimmed = trimmedPrefix(prefix)
        guard let first = trimmed.first else { return "" }
        return "\(first)_"
    }

    private static func hasConfiguredPrefix(_ prefix: String) -> Bool {
        !trimmedPrefix(prefix).isEmpty
    }

    private static func hasDistinctSecondaryPrefix(primary: String, secondary: String) -> Bool {
        let primaryTrimmed = trimmedPrefix(primary)
        let secondaryTrimmed = trimmedPrefix(secondary)
        return !secondaryTrimmed.isEmpty && secondaryTrimmed != primaryTrimmed
    }

    private func updatePrefixButtonLabels() {
        dPrefixButton.title = BottomRailView.railPrefixLabel(SettingsWindowController.customPrefixValue())
        secondaryPrefixButton.title = BottomRailView.railPrefixLabel(SettingsWindowController.customPrefixSecondaryValue())
    }

    func applyVisibilitySettings() {
        updatePrefixButtonLabels()
        let primary = SettingsWindowController.customPrefixValue()
        let secondary = SettingsWindowController.customPrefixSecondaryValue()
        let showPrefixButtons = SettingsWindowController.isBottomRailShowXEnabled()
        dPrefixButton.isHidden         = !showPrefixButtons || !BottomRailView.hasConfiguredPrefix(primary)
        secondaryPrefixButton.isHidden = !showPrefixButtons || !BottomRailView.hasDistinctSecondaryPrefix(primary: primary, secondary: secondary)
        shuffleButton.isHidden         = !SettingsWindowController.isBottomRailShowShuffleEnabled()
        repeatButton.isHidden          = !SettingsWindowController.isBottomRailShowReplayEnabled()
        volumeButton.isHidden          = !SettingsWindowController.isBottomRailShowVolumeEnabled()
        bookmarkButton.isHidden        = !SettingsWindowController.isBottomRailShowBookmarkEnabled()
        // NSMenu dismisses automatically on visibility or settings changes via system dismiss.
        applySkipDurationSettings()
        invalidateCachedDisplayState()
        syncAccessibilityExposure()
        needsLayout = true
    }

    func setAccessibilityVisible(_ visible: Bool) {
        accessibilityVisible = visible
        syncAccessibilityExposure()
        window?.recalculateKeyViewLoop()
    }

    func applySkipDurationSettings() {
        let seconds = SettingsWindowController.currentSkipDurationSeconds()
        let rewindTitle = SettingsWindowController.skipActionTitle(isForward: false, seconds: seconds)
        let forwardTitle = SettingsWindowController.skipActionTitle(isForward: true, seconds: seconds)
        rewindButton.configureSymbol(skipSymbolName(isForward: false, seconds: seconds),
                                     accessibilityLabel: rewindTitle,
                                     help: rewindTitle,
                                     fallbackNames: ["gobackward"])
        forwardButton.configureSymbol(skipSymbolName(isForward: true, seconds: seconds),
                                      accessibilityLabel: forwardTitle,
                                      help: forwardTitle,
                                      fallbackNames: ["goforward"])
    }

    func setFullscreenStyle(_ fullscreen: Bool) {
        guard isFullscreenStyle != fullscreen else { return }
        isFullscreenStyle = fullscreen
        fullscreenButton.configureSymbol(fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                         accessibilityLabel: "Toggle Fullscreen",
                                         help: "Toggle Fullscreen")
        needsLayout = true
    }

    func invalidateCachedDisplayState() {
        cachedPlayPauseSymbol = nil
        cachedVolumeSymbol = nil
        cachedRepeatSymbol = nil
        cachedElapsedText = nil
        cachedRemainingText = nil
        cachedScrubberValue = -1
    }

    func notifySeek(to position: Float) {
        pendingSeekPosition = position
        pendingSeekDate = Date()
    }

    func update() {
        if isImageMode {
            updateForImageMode()
            return
        }

        guard let player else {
            setPlaybackButtonsEnabled(false)
            scrubber.isEnabled = false
            updateBookmarkButtonState()
            return
        }

        let hasMedia = player.media != nil
        let playSymbol = player.isPlaying ? "pause.fill" : "play.fill"
        if playSymbol != cachedPlayPauseSymbol {
            cachedPlayPauseSymbol = playSymbol
            playPauseButton.configureSymbol(playSymbol,
                                            primary: true,
                                            accessibilityLabel: player.isPlaying ? "Pause" : "Play",
                                            help: "Play / Pause (Space)")
        }
        playPauseButton.setAccessibilityValue(player.isPlaying ? "playing" : "paused")
        scrubber.isEnabled = hasMedia
        scrubber.setAccessibilityLabel("Playback position")
        scrubber.setAccessibilityHelp("Adjust the current playback time")

        updateScrubberFromPlayer(player)

        let elapsed = player.time.stringValue
        let remaining = player.remainingTime?.stringValue ?? "-:--"
        let timeText = controller?.isShowingProvisionalDuration == true
            ? "\(elapsed)  \(MediaFileSupport.durationLoadingText)"
            : "\(elapsed)  \(remaining)"
        setLabel(elapsedLabel, cached: &cachedElapsedText, text: timeText)
        elapsedLabel.setAccessibilityValue(timeText)
        scrubber.setAccessibilityValueDescription("\(timeText), \(Int((scrubber.doubleValue * 100).rounded())) percent")
        // remainingLabel is always hidden; combined time is shown in elapsedLabel

        if let audio = player.audio {
            let volumeSymbol = audio.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
            if volumeSymbol != cachedVolumeSymbol {
                cachedVolumeSymbol = volumeSymbol
                volumeButton.configureSymbol(volumeSymbol,
                                             accessibilityLabel: "Mute or Unmute",
                                             help: "Mute / Unmute")
            }
            volumeButton.setAccessibilityValue(audio.volume == 0 ? "muted" : "unmuted")
            // Above 100% the button takes the caution color (a level warning).
            volumeButton.railStyle = audio.volume > VolumePolicy.normalVolume ? .warning : .normal
        }

        rewindButton.isEnabled = hasMedia
        forwardButton.isEnabled = hasMedia
        playPauseButton.isEnabled = hasMedia
        volumeButton.isEnabled = hasMedia
        prevButton.isEnabled = hasMedia && (controller?.hasPrevious ?? false)
        nextButton.isEnabled = hasMedia && (controller?.hasNext ?? false)

        queueButton.isEnabled = controller != nil
        queueButton.isToggled = controller?.isQueuePageOpen ?? false
        queueButton.setAccessibilityValue(queueButton.isToggled ? "Queue Page open" : "Queue Page closed")

        updateShuffleButtonState()

        repeatButton.isEnabled = hasMedia
        let repeatActive = controller?.isRepeatOne ?? false
        repeatButton.isToggled = repeatActive
        repeatButton.setAccessibilityValue(repeatActive ? "Repeat One on" : "Repeat One off")
        let repeatSymbol = repeatActive ? "repeat.1" : "repeat"
        if repeatSymbol != cachedRepeatSymbol {
            cachedRepeatSymbol = repeatSymbol
            repeatButton.configureSymbol(repeatSymbol,
                                         accessibilityLabel: "Repeat Current File",
                                         help: "Repeat current file")
        }

        updatePrefixButtons()
        updateBookmarkButtonState()
    }

    private func updateBookmarkButtonState() {
        let hasItem = controller?.currentMediaURL != nil
        bookmarkButton.isEnabled = hasItem
        let isBookmarked = controller?.isCurrentItemBookmarked ?? false
        bookmarkButton.isToggled = isBookmarked
        let symbol = isBookmarked ? "bookmark.fill" : "bookmark"
        let label = isBookmarked ? "Remove Bookmark" : "Bookmark"
        bookmarkButton.configureSymbol(symbol,
                                       accessibilityLabel: label,
                                       help: "Bookmark (B)")
        bookmarkButton.setAccessibilityValue(isBookmarked ? "bookmarked" : "not bookmarked")
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let railH = DWBMetrics.railHeight
        let sidePad = RailMetrics.horizontalPadding
        let buttonSize = DWBMetrics.railButton
        let playSize = DWBMetrics.railButtonPrimary
        let gap: CGFloat = w < 520 ? 6 : 8

        // Buttons are centered in the 40 pt row beneath the scrubber.
        let rowCenterY = RailMetrics.buttonRowCenterY
        let rowY: CGFloat = rowCenterY - buttonSize / 2
        let playY: CGFloat = rowCenterY - playSize / 2

        veil.frame = NSRect(x: 0, y: 0, width: w, height: railH)
        veil.layer?.cornerRadius = 0
        veil.layer?.maskedCorners = []
        applyRailChrome()
        hairline.frame = NSRect(x: 0, y: railH - RailMetrics.hairlineHeight, width: w, height: RailMetrics.hairlineHeight)

        // The scrubber sits inside the rail's horizontal padding, below the hairline.
        scrubber.frame = NSRect(x: sidePad,
                                y: RailMetrics.scrubberMinY,
                                width: max(0, w - sidePad * 2),
                                height: RailMetrics.scrubberHeight)

        applyResponsiveVisibility(width: w)

        // Left cluster: Queue, primary prefix, secondary prefix, Bookmark
        var leftX = sidePad
        for button in [queueButton, dPrefixButton, secondaryPrefixButton, bookmarkButton] where !button.isHidden {
            place(button, x: leftX, y: rowY, size: buttonSize)
            leftX += buttonSize + gap
        }

        // Pre-calculate right cluster left boundary so center group can be
        // clamped against it before either cluster is placed.
        let rightClusterOrder: [RailButton] = [fullscreenButton, moreButton, volumeButton, repeatButton, shuffleButton]
        let rightClusterCount = CGFloat(rightClusterOrder.filter { !$0.isHidden }.count)
        let rightClusterLeft: CGFloat = rightClusterCount == 0
            ? w - sidePad
            : w - sidePad - rightClusterCount * buttonSize - (rightClusterCount - 1) * gap

        let center: [(RailButton, CGFloat)] = [
            (rewindButton, buttonSize),
            (prevButton, buttonSize),
            (playPauseButton, playSize),
            (nextButton, buttonSize),
            (forwardButton, buttonSize)
        ].filter { !$0.0.isHidden }
        let centerWidth = center.reduce(CGFloat(0)) { $0 + $1.1 } + CGFloat(center.count - 1) * gap
        let maxCenterLeft = rightClusterLeft - centerWidth - gap
        let centerGroupLeft = min(maxCenterLeft, max(leftX + gap, (w - centerWidth) / 2))
        var centerX = centerGroupLeft
        for (button, size) in center {
            place(button, x: centerX, y: size == playSize ? playY : rowY, size: size)
            centerX += size + gap
        }

        // Right cluster: Fullscreen, More, Volume, Replay, Shuffle (laid out right-to-left)
        var rightX = w - sidePad - buttonSize
        for button in [fullscreenButton, moreButton, volumeButton, repeatButton, shuffleButton] where !button.isHidden {
            place(button, x: rightX, y: rowY, size: buttonSize)
            rightX -= buttonSize + gap
        }

        // Time label follows the left cluster, in the button row. It is shown only
        // when it fits between the left cluster and the transport group.
        let timeLabelH: CGFloat = 14
        let timeLabelX = leftX
        let timeLabelRoom = centerGroupLeft - gap - timeLabelX
        let minimumTimeLabelWidth: CGFloat = 96
        if !elapsedLabel.isHidden && timeLabelRoom < minimumTimeLabelWidth {
            elapsedLabel.isHidden = true
        }
        elapsedLabel.frame = NSRect(x: timeLabelX,
                                    y: (rowCenterY - timeLabelH / 2).rounded(),
                                    width: max(0, min(130, timeLabelRoom)),
                                    height: timeLabelH)
        remainingLabel.frame = .zero   // combined time shown in elapsedLabel
        syncAccessibilityExposure()
    }

    private func applyResponsiveVisibility(width: CGFloat) {
        // Settings act as the authoritative "show this button" gate; width is an
        // additional compression rule when the window is narrow.
        let primary = SettingsWindowController.customPrefixValue()
        let secondary = SettingsWindowController.customPrefixSecondaryValue()
        let showPrefixButtons = SettingsWindowController.isBottomRailShowXEnabled()
        dPrefixButton.isHidden = !showPrefixButtons
            || !BottomRailView.hasConfiguredPrefix(primary)
            || width < 500
        secondaryPrefixButton.isHidden = !showPrefixButtons
            || !BottomRailView.hasDistinctSecondaryPrefix(primary: primary, secondary: secondary)
            || width < 540
        elapsedLabel.isHidden    = width < 640
        remainingLabel.isHidden  = true   // combined time shown in elapsedLabel; always hidden
        shuffleButton.isHidden   = !SettingsWindowController.isBottomRailShowShuffleEnabled()  || width < 430
        repeatButton.isHidden    = !SettingsWindowController.isBottomRailShowReplayEnabled()   || width < 390
        volumeButton.isHidden    = !SettingsWindowController.isBottomRailShowVolumeEnabled()   || width < 360
        bookmarkButton.isHidden  = !SettingsWindowController.isBottomRailShowBookmarkEnabled() || width < 560
        // Preserve the centered transport hierarchy without overlap when an open
        // Queue Page leaves the media surface extremely narrow. Keyboard commands
        // remain available; controls return automatically as width is restored.
        rewindButton.isHidden = width < 360
        forwardButton.isHidden = width < 360
        prevButton.isHidden = width < 280
        nextButton.isHidden = width < 280
        moreButton.isHidden = width < 330
        settingsButton.isHidden = true // Settings remains available in the More menu.
    }

    private func setupViews() {
        veil.wantsLayer = true
        addSubview(veil)
        hairline.wantsLayer = true
        addSubview(hairline)

        configure(queueButton, symbol: "square.split.2x1", label: "Toggle Queue Page", help: "Toggle Queue Page", identifier: "player.rail.queue", action: #selector(queueTapped), style: .utility)
        updatePrefixButtonLabels()
        configure(dPrefixButton, symbol: nil, label: "Apply Primary Custom Prefix", help: "Rename: apply primary custom prefix (N)", identifier: "player.rail.primaryPrefix", action: #selector(dPrefixTapped), style: .prefixPrimary, title: dPrefixButton.title)
        configure(secondaryPrefixButton, symbol: nil, label: "Apply Secondary Custom Prefix", help: "Rename: apply secondary custom prefix (M)", identifier: "player.rail.secondaryPrefix", action: #selector(secondaryPrefixTapped), style: .prefixSecondary, title: secondaryPrefixButton.title)
        configure(rewindButton, symbol: "gobackward.10", label: "Rewind", help: "Rewind", identifier: "player.rail.rewind", action: #selector(rewindTapped))
        configure(prevButton, symbol: "backward.end.fill", label: "Previous File", help: "Previous file (Z)", identifier: "player.rail.previous", action: #selector(prevTapped))
        configure(playPauseButton, symbol: "play.fill", label: "Play or Pause", help: "Play / Pause (Space)", identifier: "player.rail.playPause", action: #selector(playPauseTapped), style: .emphasized, primary: true)
        configure(nextButton, symbol: "forward.end.fill", label: "Next File", help: "Next file (X)", identifier: "player.rail.next", action: #selector(nextTapped))
        configure(forwardButton, symbol: "goforward.10", label: "Skip Forward", help: "Skip Forward", identifier: "player.rail.forward", action: #selector(forwardTapped))
        configure(volumeButton, symbol: "speaker.wave.2.fill", label: "Mute or Unmute", help: "Mute / Unmute", identifier: "player.rail.volume", action: #selector(volumeTapped))
        configure(shuffleButton, symbol: "shuffle", label: "Shuffle", help: "Shuffle", identifier: "player.rail.shuffle", action: #selector(shuffleTapped))
        configure(repeatButton, symbol: "repeat", label: "Repeat Current File", help: "Repeat current file", identifier: "player.rail.repeatOne", action: #selector(repeatTapped))
        configure(bookmarkButton, symbol: "bookmark", label: "Bookmark", help: "Bookmark (B)", identifier: "player.rail.bookmark", action: #selector(bookmarkTapped), style: .bookmark)
        configure(moreButton, symbol: "ellipsis", label: "More Actions", help: "More actions overflow menu", identifier: "player.rail.more", action: #selector(moreTapped))
        configure(settingsButton, symbol: "gearshape", label: "Settings", help: "Settings (⌘,)", identifier: "player.rail.settings", action: #selector(settingsTapped))
        configure(fullscreenButton, symbol: "arrow.up.left.and.arrow.down.right", label: "Toggle Fullscreen", help: "Toggle Fullscreen", identifier: "player.rail.fullscreen", action: #selector(fullscreenTapped))

        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: RailMetrics.timeLabelFontSize, weight: .medium)
            label.drawsBackground = false
            label.alignment = .left
            addSubview(label)
        }
        applyTimeLabelColor()
        elapsedLabel.setAccessibilityLabel("Playback time")
        elapsedLabel.setAccessibilityIdentifier("player.rail.time")

        // The slider frame is the full hit area; the cell draws the track centered in it.
        scrubber.cell = RailScrubberCell()
        scrubber.minValue = 0
        scrubber.maxValue = 1
        scrubber.doubleValue = 0
        scrubber.isContinuous = true
        scrubber.target = self
        scrubber.action = #selector(scrubberMoved(_:))
        scrubber.setAccessibilityLabel("Playback position")
        scrubber.setAccessibilityHelp("Adjust the current playback time")
        scrubber.setAccessibilityIdentifier("player.rail.scrubber")
        scrubber.scrubDidBegin = { [weak self] in
            guard let self else { return }
            self.pendingSeekPosition = nil
            self.pendingSeekDate = nil
            self.isScrubbing = true
            self.scrubDidBegin?()
            if !self.isImageMode {
                self.controller?.notifyUserSeek(source: "rail-scrub-begin")
            }
        }
        scrubber.scrubDidEnd = { [weak self] in
            guard let self else { return }
            self.isScrubbing = false
            defer { self.scrubDidEnd?() }
            guard !self.isImageMode else { return }
            let raw = Float(self.scrubber.doubleValue)
            let pos = self.controller?.clampedUserSeekPosition(raw, source: "rail-scrub-end")
                ?? max(0, min(0.985, raw))
            self.scrubber.doubleValue = Double(pos)
            self.controller?.notifyUserSeek(targetPosition: pos, source: "rail-scrub-end")
            self.player?.position = pos
            self.notifySeek(to: pos)
        }
        addSubview(scrubber)

        let railButtons = [
            queueButton, dPrefixButton, secondaryPrefixButton, rewindButton, prevButton,
            playPauseButton, nextButton, forwardButton, volumeButton, shuffleButton,
            repeatButton, bookmarkButton, moreButton, settingsButton, fullscreenButton
        ]
        for button in railButtons {
            button.interactionStateDidChange = { [weak self] in
                self?.interactionStateDidChange?()
            }
        }

        applyVisibilitySettings()
    }

    private func configure(_ button: RailButton,
                           symbol: String?,
                           label: String,
                           help: String,
                           identifier: String,
                           action: Selector,
                           style: RailButton.Style = .normal,
                           title: String = "",
                           primary: Bool = false) {
        button.railStyle = style
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
        button.title = title
        if let symbol {
            button.configureSymbol(symbol, primary: primary, accessibilityLabel: label, help: help)
        } else {
            button.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            button.setAccessibilityLabel(label)
            button.setAccessibilityHelp(help)
            button.toolTip = help
        }
        addSubview(button)
    }

    private func syncAccessibilityExposure() {
        let controls: [NSView] = [
            queueButton, dPrefixButton, secondaryPrefixButton, rewindButton, prevButton,
            playPauseButton, nextButton, forwardButton, volumeButton, shuffleButton,
            repeatButton, bookmarkButton, moreButton, settingsButton, fullscreenButton,
            elapsedLabel, scrubber
        ]
        for control in controls {
            control.setAccessibilityElement(accessibilityVisible && !control.isHidden)
        }
    }

    private func place(_ button: RailButton, x: CGFloat, y: CGFloat, size: CGFloat) {
        button.frame = NSRect(x: x, y: y, width: size, height: size)
        button.layer?.cornerRadius = size / 2
    }

    private func updateScrubberFromPlayer(_ player: VLCMediaPlayer) {
        guard !isScrubbing else { return }
        var targetPos: Double?
        if let pending = pendingSeekPosition {
            let current = player.position
            let elapsed = pendingSeekDate.map { Date().timeIntervalSince($0) } ?? pendingSeekTimeout
            if abs(current - pending) < 0.01 || elapsed > pendingSeekTimeout {
                pendingSeekPosition = nil
                pendingSeekDate = nil
                let pos = Double(current)
                if pos.isFinite { targetPos = max(0, min(1, pos)) }
            } else {
                targetPos = Double(pending)
            }
        } else {
            let pos = Double(player.position)
            if pos.isFinite { targetPos = max(0, min(1, pos)) }
        }
        if let targetPos, abs(targetPos - cachedScrubberValue) > 0.001 {
            cachedScrubberValue = targetPos
            scrubber.doubleValue = targetPos
        }
    }

    private func updateForImageMode() {
        let mediaKind = isGIFMode ? "animated GIF" : "image"
        let playSymbol = imageModeIsPlaying ? "pause.fill" : "play.fill"
        if playSymbol != cachedPlayPauseSymbol {
            cachedPlayPauseSymbol = playSymbol
            playPauseButton.configureSymbol(playSymbol,
                                            primary: true,
                                            accessibilityLabel: imageModeIsPlaying ? "Pause \(mediaKind)" : "Resume \(mediaKind)",
                                            help: "Play / Pause (Space)")
        }
        playPauseButton.setAccessibilityValue(imageModeIsPlaying ? "playing" : "paused")
        if !isScrubbing {
            let pos = imageModeDuration > 0 ? min(1.0, imageModeElapsed / imageModeDuration) : 0
            if abs(pos - cachedScrubberValue) > 0.001 {
                cachedScrubberValue = pos
                scrubber.doubleValue = pos
            }
        }
        setLabel(elapsedLabel, cached: &cachedElapsedText,
                 text: "\(formatImageTime(imageModeElapsed))  \(formatImageTime(imageModeDuration))")
        elapsedLabel.setAccessibilityValue(elapsedLabel.stringValue)
        scrubber.isEnabled = false
        scrubber.setAccessibilityLabel(isGIFMode ? "Animated GIF progress" : "Image slideshow progress")
        scrubber.setAccessibilityHelp("Displays progress; image and GIF progress cannot be scrubbed")
        scrubber.setAccessibilityValueDescription(
            "\(elapsedLabel.stringValue), \(Int((scrubber.doubleValue * 100).rounded())) percent"
        )
        // remainingLabel is always hidden; combined time is shown in elapsedLabel
        rewindButton.isEnabled = false
        forwardButton.isEnabled = false
        volumeButton.isEnabled = false
        playPauseButton.isEnabled = true
        prevButton.isEnabled = controller?.hasPrevious ?? false
        nextButton.isEnabled = controller?.hasNext ?? false
        queueButton.isEnabled = controller != nil
        queueButton.isToggled = controller?.isQueuePageOpen ?? false
        queueButton.setAccessibilityValue(queueButton.isToggled ? "Queue Page open" : "Queue Page closed")
        updateShuffleButtonState()
        repeatButton.isEnabled = true
        let repeatActive = controller?.isRepeatOne ?? false
        repeatButton.isToggled = repeatActive
        repeatButton.setAccessibilityValue(repeatButton.isToggled ? "Repeat One on" : "Repeat One off")
        let repeatSymbol = repeatActive ? "repeat.1" : "repeat"
        if repeatSymbol != cachedRepeatSymbol {
            cachedRepeatSymbol = repeatSymbol
            repeatButton.configureSymbol(repeatSymbol,
                                         accessibilityLabel: "Repeat Current File",
                                         help: "Repeat current file")
        }
        updatePrefixButtons()
        updateBookmarkButtonState()
    }

    private func updateShuffleButtonState() {
        let shuffleEnabled = (controller?.playbackSet.count ?? 0) > 1
        let shuffleOn = controller?.isShuffleOn ?? false
        let endlessOn = controller?.isEndlessShuffleOn ?? false
        shuffleButton.isEnabled = shuffleEnabled
        shuffleButton.isToggled = shuffleOn || endlessOn
        let help: String
        let label: String
        let symbol: String
        if endlessOn {
            help   = "Endless Shuffle on — click to turn off"
            label  = "Endless Shuffle"
            symbol = "arrow.triangle.2.circlepath"
        } else if shuffleOn {
            help   = "Shuffle on — click for Endless Shuffle"
            label  = "Shuffle"
            symbol = "shuffle"
        } else {
            help   = "Shuffle"
            label  = "Shuffle"
            symbol = "shuffle"
        }
        if shuffleButton.toolTip != help {
            shuffleButton.configureSymbol(symbol, accessibilityLabel: label, help: help)
        }
        let state = endlessOn ? "Endless Shuffle on" : shuffleOn ? "Shuffle on" : "Shuffle off"
        shuffleButton.setAccessibilityValue(state)
    }

    private func updatePrefixButtons() {
        let enabled = controller?.canRenameCurrentMedia == true
        dPrefixButton.isEnabled = enabled
        secondaryPrefixButton.isEnabled = enabled
    }

    private func setPlaybackButtonsEnabled(_ enabled: Bool) {
        [rewindButton, prevButton, playPauseButton, nextButton, forwardButton,
         volumeButton, shuffleButton, repeatButton, queueButton,
         dPrefixButton, secondaryPrefixButton].forEach { $0.isEnabled = enabled }
        queueButton.isEnabled = controller != nil
    }

    private func setLabel(_ label: NSTextField, cached: inout String?, text: String) {
        guard cached != text else { return }
        cached = text
        label.stringValue = text
    }

    private func skipSymbolName(isForward: Bool, seconds: Int) -> String {
        switch seconds {
        case 10:
            return isForward ? "goforward.10" : "gobackward.10"
        case 30:
            return isForward ? "goforward.30" : "gobackward.30"
        case 60:
            return isForward ? "goforward.60" : "gobackward.60"
        default:
            return isForward ? "goforward" : "gobackward"
        }
    }

    private func formatImageTime(_ seconds: Double) -> String {
        MediaFileSupport.formatShortDuration(max(0, seconds))
    }

    @objc private func queueTapped() { controller?.toggleQueuePage() }
    @objc private func dPrefixTapped() { controller?.performCustomPrefixRenameCurrentItem() }
    @objc private func secondaryPrefixTapped() { controller?.performSecondaryCustomPrefixRenameCurrentItem(source: "bottomRail-secondary") }
    @objc private func playPauseTapped() { controller?.togglePlayPause() }
    @objc private func prevTapped() { controller?.playPrevious() }
    @objc private func nextTapped() { controller?.playNext() }
    @objc private func rewindTapped() { controller?.skipBackward10() }
    @objc private func forwardTapped() { controller?.skipForward10() }
    @objc private func shuffleTapped() { controller?.toggleShuffle() }
    @objc private func repeatTapped() { controller?.toggleRepeat() }
    @objc private func bookmarkTapped() { controller?.toggleBookmark() }
    @objc private func settingsTapped() { SettingsWindowController.shared.openSettings() }
    @objc private func fullscreenTapped() { window?.toggleFullScreen(nil) }

    @objc private func moreTapped() {
        let shuffleEnabled = (controller?.playbackSet.count ?? 0) > 1
        let shuffleOn = (controller?.isShuffleOn ?? false) || (controller?.isEndlessShuffleOn ?? false)
        let renameEnabled = controller?.canRenameCurrentMedia == true
        let hasItem = controller?.currentMediaURL != nil
        let isBookmarked = controller?.isCurrentItemBookmarked ?? false
        let isRepeat = controller?.isRepeatOne ?? false

        let primary = SettingsWindowController.customPrefixValue()
        let secondary = SettingsWindowController.customPrefixSecondaryValue()
        let showPrefixButtons = SettingsWindowController.isBottomRailShowXEnabled()
        let hasPrimary = BottomRailView.hasConfiguredPrefix(primary)
        let hasDistinctSecondary = BottomRailView.hasDistinctSecondaryPrefix(primary: primary, secondary: secondary)

        // Use NSMenu so overflow actions are natively accessible to VoiceOver and
        // keyboard-only users. NSMenuItem exposes role, label, state, and activation
        // through AppKit's built-in accessibility and keyboard navigation automatically.
        // Show each action when its dedicated rail button is hidden (Settings off or
        // narrow-width responsive hiding). Visible rail buttons are not duplicated.
        let menu = NSMenu(title: "More Actions")
        menu.autoenablesItems = false

        func addItem(title: String, action: MoreMenuAction, isOn: Bool, isEnabled: Bool) {
            let item = NSMenuItem(title: title, action: #selector(handleMoreMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.state = isOn ? .on : .off
            item.isEnabled = isEnabled
            item.representedObject = action
            menu.addItem(item)
        }

        if hasPrimary && (dPrefixButton.isHidden || !showPrefixButtons) {
            addItem(title: BottomRailView.railPrefixLabel(primary), action: .customPrefix, isOn: false, isEnabled: renameEnabled)
        }
        if hasDistinctSecondary && (secondaryPrefixButton.isHidden || !showPrefixButtons) {
            addItem(title: BottomRailView.railPrefixLabel(secondary), action: .customPrefixSecondary, isOn: false, isEnabled: renameEnabled)
        }
        if shuffleButton.isHidden {
            addItem(title: "Shuffle",   action: .shuffle,   isOn: shuffleOn,    isEnabled: shuffleEnabled)
        }
        if repeatButton.isHidden {
            addItem(title: "Replay",    action: .replay,    isOn: isRepeat,     isEnabled: true)
        }
        if bookmarkButton.isHidden {
            addItem(title: "Bookmark",  action: .bookmark,  isOn: isBookmarked, isEnabled: hasItem)
        }
        // Settings is always last so it stays reachable even when every dedicated button is visible.
        addItem(title: "Settings", action: .settings, isOn: false, isEnabled: true)

        // Anchor above the more button; AppKit adjusts for screen edges automatically.
        isMoreMenuOpen = true
        interactionStateDidChange?()
        menu.popUp(positioning: nil,
                   at: NSPoint(x: moreButton.frame.minX, y: moreButton.frame.maxY),
                   in: self)
        isMoreMenuOpen = false
        interactionStateDidChange?()
    }

    @objc private func handleMoreMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MoreMenuAction else { return }
        switch action {
        case .customPrefix:          controller?.performCustomPrefixRenameCurrentItem()
        case .customPrefixSecondary: controller?.performSecondaryCustomPrefixRenameCurrentItem(source: "bottomRail-more")
        case .shuffle:               controller?.toggleShuffle()
        case .replay:                controller?.toggleRepeat()
        case .bookmark:              controller?.toggleBookmark()
        case .settings:              SettingsWindowController.shared.openSettings()
        }
    }


    @objc private func scrubberMoved(_ sender: NSSlider) {
        guard !isImageMode else { return }
        let raw = Float(sender.doubleValue)
        let pos = controller?.clampedUserSeekPosition(raw, source: "rail-scrubber-move")
            ?? max(0, min(0.985, raw))
        if abs(Double(pos) - sender.doubleValue) > 0.0005 {
            sender.doubleValue = Double(pos)
        }
        player?.position = pos
        notifySeek(to: pos)
    }

    @objc private func volumeTapped() {
        controller?.toggleMuteFromTransport()
        cachedVolumeSymbol = nil
        update()
    }
}

// MARK: - More menu

fileprivate enum MoreMenuAction {
    case customPrefix, customPrefixSecondary, shuffle, replay, bookmark, settings
}

// MARK: - Rail scrubber cell

/// Draws the design system's scrubber: a 2 pt track vertically centered in the
/// 14 pt slider frame, an optional 4 pt preview range, optional 1.5 × 8 pt
/// segment ticks, the 2 pt played portion, and a 6 pt knob that grows to 8 pt
/// on hover or drag (it does not grow under Reduce Motion). NSSliderCell still
/// owns click and drag tracking over the full frame, and the knob stays
/// centered on AppKit's knob position (`ScrubberTrackGeometry`, P115).
fileprivate final class RailScrubberCell: NSSliderCell {

    private var scrubber: ScrubberSlider? { controlView as? ScrubberSlider }

    override func drawKnob(_ knobRect: NSRect) {
        let fullRect = controlView?.bounds ?? knobRect
        let trackRect = centeredRect(in: fullRect, height: ScrubberStyle.trackHeight)
        let diameter = ScrubberStyle.knobDiameter(
            emphasized: scrubber?.isEmphasized ?? false,
            reduceMotion: PlayerAccessibilityEnvironment.reduceMotion
        )
        let visibleKnob = ScrubberTrackGeometry.visibleKnobRect(
            trackRect: trackRect,
            knobRect: knobRect,
            diameter: diameter
        )

        DWBColor.textPrimary.setFill()
        NSBezierPath(ovalIn: visibleKnob).fill()
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        // Use the control view's full bounds to avoid any system inset on the bar.
        let fullRect = controlView?.bounds ?? rect
        let increasedContrast = PlayerAccessibilityEnvironment.increaseContrast
        let barRect = centeredRect(in: fullRect, height: ScrubberStyle.trackHeight)

        ScrubberStyle.trackColor(increaseContrast: increasedContrast).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()

        if let range = scrubber?.previewRange {
            let lower = CGFloat(max(0, min(1, range.lowerBound)))
            let upper = CGFloat(max(0, min(1, range.upperBound)))
            let previewRect = centeredRect(in: fullRect, height: ScrubberStyle.rangeHeight)
            let rangeRect = NSRect(x: previewRect.minX + lower * previewRect.width,
                                   y: previewRect.minY,
                                   width: max(0, (upper - lower) * previewRect.width),
                                   height: previewRect.height)
            PlayerTheme.current.accentFill.setFill()
            NSBezierPath(roundedRect: rangeRect, xRadius: 2, yRadius: 2).fill()
        }

        if let ticks = scrubber?.tickPositions, !ticks.isEmpty {
            ScrubberStyle.tickColor(increaseContrast: increasedContrast).setFill()
            let tickBand = centeredRect(in: fullRect, height: ScrubberStyle.tickHeight)
            for position in ticks {
                let x = fullRect.minX + CGFloat(max(0, min(1, position))) * fullRect.width
                NSRect(x: x - ScrubberStyle.tickWidth / 2,
                       y: tickBand.minY,
                       width: ScrubberStyle.tickWidth,
                       height: tickBand.height).fill()
            }
        }

        if maxValue > minValue {
            // AppKit maps track clicks to the knob's travel range, which
            // is inset from the visible bar by half the knob width. Use that
            // exact knob center for the visual endpoint so the click target,
            // value, and rendered progress position share one geometry.
            let filled = ScrubberTrackGeometry.progressFillRect(
                trackRect: barRect,
                knobRect: knobRect(flipped: flipped)
            )
            PlayerTheme.current.accentText.setFill()
            NSBezierPath(roundedRect: filled, xRadius: 1, yRadius: 1).fill()
        }
    }

    private func centeredRect(in fullRect: NSRect, height: CGFloat) -> NSRect {
        NSRect(x: fullRect.minX, y: fullRect.midY - height / 2, width: fullRect.width, height: height)
    }
}
