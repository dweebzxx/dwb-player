import Cocoa

/// Reads the two accessibility switches the design system asks every part to honor.
/// A thin face over `DWBAppearance`, the one shared place that watches them.
enum PlayerAccessibilityEnvironment {
    static var increaseContrast: Bool {
        DWBAppearance.shared.increaseContrast
    }

    /// The app's own "Reduce motion" setting, which defaults to the system value.
    static var reduceMotion: Bool {
        DWBAppearance.shared.reduceMotion
    }

    static func observeChanges(_ observer: Any, selector: Selector) {
        DWBAppearance.observe(observer, selector: selector)
    }

    static func stopObserving(_ observer: Any) {
        DWBAppearance.stopObserving(observer)
    }
}

/// Base for a rounded panel that floats over the video: a token backing, an
/// optional 1 pt edge, the HUD shadow, Increase Contrast handling, and an
/// optional show / hold / fade-out lifecycle that honors Reduce Motion.
class OverlayPanelView: NSView {
    var backingColor: NSColor = DWBColor.backingHUD { didSet { applyChrome() } }
    var edgeColor: NSColor? = DWBColor.hairline { didSet { applyChrome() } }
    /// Edge used under Increase Contrast; nil keeps `edgeColor`.
    var increaseContrastEdgeColor: NSColor? = DWBColor.borderStrong { didSet { applyChrome() } }
    var showsShadow = true { didSet { applyChrome() } }
    var panelCornerRadius: CGFloat = DWBMetrics.radiusCard { didSet { applyChrome() } }
    var passesMouseThrough = true
    var fadeDuration: TimeInterval = DWBMotion.fade

    /// Subclasses return true to keep the panel up while the user is interacting with it.
    var defersHide: Bool { false }

    private var hideTimer: Timer?
    private var presentationGeneration = 0

    var increaseContrast: Bool { PlayerAccessibilityEnvironment.increaseContrast }
    var reduceMotion: Bool { PlayerAccessibilityEnvironment.reduceMotion }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        alphaValue = 0
        isHidden = true
        PlayerAccessibilityEnvironment.observeChanges(self, selector: #selector(accessibilityOptionsChanged))
        applyChrome()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit {
        hideTimer?.invalidate()
        PlayerAccessibilityEnvironment.stopObserving(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesMouseThrough ? nil : super.hitTest(point)
    }

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    /// Backing color for the current contrast setting. Overridden where the
    /// translucent fill is a tint rather than a backing.
    func resolvedBackingColor() -> NSColor {
        OverlayBacking.resolved(backingColor, increaseContrast: increaseContrast)
    }

    /// Called after the chrome is reapplied for an Increase Contrast change.
    func contrastDidChange() {}

    func applyChrome() {
        guard let layer else { return }
        layer.backgroundColor = resolvedBackingColor().cgColor
        layer.cornerRadius = panelCornerRadius
        layer.masksToBounds = false
        let edge = increaseContrast ? (increaseContrastEdgeColor ?? edgeColor) : edgeColor
        layer.borderWidth = edge == nil ? 0 : 1
        layer.borderColor = edge?.cgColor
        if showsShadow {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.45
            layer.shadowOffset = CGSize(width: 0, height: -8)
            layer.shadowRadius = 12
        } else {
            layer.shadowOpacity = 0
        }
        updateShadowPath()
    }

    private func updateShadowPath() {
        guard showsShadow, bounds.width > 0, bounds.height > 0 else {
            layer?.shadowPath = nil
            return
        }
        layer?.shadowPath = CGPath(roundedRect: bounds,
                                   cornerWidth: panelCornerRadius,
                                   cornerHeight: panelCornerRadius,
                                   transform: nil)
    }

    @objc private func accessibilityOptionsChanged() {
        applyChrome()
        contrastDidChange()
        needsDisplay = true
        needsLayout = true
    }

    // MARK: Lifecycle

    /// Shows the panel. With a `hold`, it fades out after that long; with nil it stays until dismissed.
    func present(hold: TimeInterval?) {
        presentationGeneration += 1
        let generation = presentationGeneration
        isHidden = false
        fade(to: 1, generation: generation)
        if let hold {
            scheduleHide(after: hold, generation: generation)
        } else {
            hideTimer?.invalidate()
        }
    }

    /// Restarts the hold from now without changing visibility (used after a drag).
    func rescheduleHide(after hold: TimeInterval) {
        scheduleHide(after: hold, generation: presentationGeneration)
    }

    func cancelPendingHide() {
        hideTimer?.invalidate()
    }

    func dismiss() {
        presentationGeneration += 1
        let generation = presentationGeneration
        hideTimer?.invalidate()
        guard !isHidden else { return }
        fade(to: 0, generation: generation) { [weak self] in self?.isHidden = true }
    }

    private func scheduleHide(after hold: TimeInterval, generation: Int) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
            guard let self, self.presentationGeneration == generation, !self.defersHide else { return }
            self.fade(to: 0, generation: generation) { [weak self] in self?.isHidden = true }
        }
    }

    private func fade(to alpha: CGFloat, generation: Int, completion: (() -> Void)? = nil) {
        let duration = DWBMotion.duration(fadeDuration, reduceMotion: reduceMotion)
        if duration == 0 {
            layer?.removeAllAnimations()
            alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            self.animator().alphaValue = alpha
        }, completionHandler: { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            completion?()
        })
    }
}

// MARK: - Layout helpers

private func verticallyCentered(_ x: CGFloat, width: CGFloat, height: CGFloat, in bounds: NSRect) -> NSRect {
    NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, width), height: height)
}

private func symbolImage(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    return image?.withSymbolConfiguration(configuration) ?? image
}

private func makeLabel() -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.drawsBackground = false
    label.isBordered = false
    label.isSelectable = false
    label.lineBreakMode = .byTruncatingTail
    label.cell?.usesSingleLineMode = true
    return label
}

// MARK: - Title overlay

final class TitleOverlayView: OverlayPanelView {
    private let label = makeLabel()
    private var videoWidth: CGFloat = 800

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backingColor = DWBColor.backingTitle
        edgeColor = nil
        increaseContrastEdgeColor = nil
        showsShadow = false
        fadeDuration = DWBMotion.rail
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        setAccessibilityIdentifier("player.titleOverlay")
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func configure(title: String, videoWidth: CGFloat) {
        self.videoWidth = videoWidth
        label.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: TitleOverlayMetrics.fontSize(videoWidth: videoWidth), weight: .semibold),
            .foregroundColor: DWBColor.textPrimary
        ])
        setAccessibilityLabel(title)
        needsLayout = true
    }

    var preferredHeight: CGFloat { TitleOverlayMetrics.height(videoWidth: videoWidth) }

    var preferredWidth: CGFloat {
        TitleOverlayMetrics.width(textWidth: label.attributedStringValue.size().width, videoWidth: videoWidth)
    }

    override func layout() {
        super.layout()
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = verticallyCentered(TitleOverlayMetrics.horizontalPadding,
                                         width: bounds.width - TitleOverlayMetrics.horizontalPadding * 2,
                                         height: height,
                                         in: bounds)
    }
}

// MARK: - Failure message

final class FailureMessageView: OverlayPanelView {
    private let iconView = NSImageView()
    private let label = makeLabel()
    private var textWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        edgeColor = DWBColor.errorFill
        increaseContrastEdgeColor = nil
        fadeDuration = DWBMotion.fade
        iconView.image = symbolImage("xmark.octagon.fill", pointSize: FailureMessageMetrics.iconSize)
        iconView.contentTintColor = DWBColor.errorText
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
        addSubview(label)
        setAccessibilityIdentifier("player.failureMessage")
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    /// Shows "Could not play “<filename>”" with an optional suffix, held for 3 s.
    func present(filename: String, suffix: String? = nil) {
        let semibold = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let medium = NSFont.systemFont(ofSize: 13, weight: .medium)
        let text = NSMutableAttributedString(
            string: "\(FailureMessageMetrics.message) \u{201c}",
            attributes: [.font: semibold, .foregroundColor: DWBColor.textPrimary]
        )
        text.append(NSAttributedString(string: filename, attributes: [.font: medium, .foregroundColor: DWBColor.textPrimary]))
        text.append(NSAttributedString(string: "\u{201d}", attributes: [.font: semibold, .foregroundColor: DWBColor.textPrimary]))
        if let suffix, !suffix.isEmpty {
            text.append(NSAttributedString(string: " \u{2014} \(suffix)",
                                           attributes: [.font: medium, .foregroundColor: DWBAppearance.shared.textSecondary]))
        }
        label.attributedStringValue = text
        textWidth = ceil(text.size().width)
        let spoken = FailureMessageMetrics.text(filename: filename) + (suffix.map { " \u{2014} \($0)" } ?? "")
        setAccessibilityLabel(spoken)
        needsLayout = true
        present(hold: FailureMessageMetrics.hold)
        NSAccessibility.post(element: self,
                             notification: .announcementRequested,
                             userInfo: [.announcement: spoken,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let natural = FailureMessageMetrics.horizontalPadding * 2
            + FailureMessageMetrics.iconSize + FailureMessageMetrics.iconGap + textWidth + 2
        return min(max(0, maxWidth), natural)
    }

    override func layout() {
        super.layout()
        let padding = FailureMessageMetrics.horizontalPadding
        let icon = FailureMessageMetrics.iconSize
        iconView.frame = verticallyCentered(padding, width: icon, height: icon, in: bounds)
        let labelX = padding + icon + FailureMessageMetrics.iconGap
        label.frame = verticallyCentered(labelX,
                                         width: bounds.width - labelX - padding,
                                         height: ceil(label.intrinsicContentSize.height),
                                         in: bounds)
    }
}

// MARK: - Undo toast

private final class UndoToastButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
}

final class UndoToastView: OverlayPanelView {
    private let iconView = NSImageView()
    private let captionLabel = makeLabel()
    private let nameLabel = makeLabel()
    private let undoButton = UndoToastButton()
    private var captionWidth: CGFloat = 0
    private var nameWidth: CGFloat = 0
    private var buttonWidth: CGFloat = 0
    private var lastFilename: String?
    /// 1 shows the filename; 2 or more shows "N files".
    private var renamedCount = 1

    /// Runs the same undo as Command-Z.
    var onUndo: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        passesMouseThrough = false
        fadeDuration = DWBMotion.fade

        iconView.image = symbolImage("checkmark.circle.fill", pointSize: UndoToastMetrics.iconSize)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
        addSubview(captionLabel)
        addSubview(nameLabel)

        undoButton.isBordered = false
        undoButton.bezelStyle = .regularSquare
        undoButton.focusRingType = .none
        undoButton.wantsLayer = true
        undoButton.layer?.cornerRadius = UndoToastMetrics.buttonRadius
        undoButton.layer?.backgroundColor = DWBColor.overlaySelected.cgColor
        undoButton.target = self
        undoButton.action = #selector(undoTapped)
        undoButton.setAccessibilityLabel("Undo")
        undoButton.setAccessibilityHelp("Undo the last marker rename, every file in it (\u{2318}Z)")
        undoButton.setAccessibilityIdentifier("player.undoToast.undo")
        addSubview(undoButton)

        setAccessibilityIdentifier("player.undoToast")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func contrastDidChange() {
        applyColors()
        updateSubject()
    }

    private var theme: DWBTheme { PlayerTheme.current }

    private func applyColors() {
        let secondary = increaseContrast ? DWBColor.textPrimary : DWBColor.textSecondary
        iconView.contentTintColor = secondary
        captionLabel.attributedStringValue = NSAttributedString(string: UndoToastMetrics.caption(renamedFileCount: renamedCount), attributes: [
            .font: NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: secondary
        ])
        // `fittingSize` includes the cell's 2 pt text inset on each side; the attributed
        // string's own width does not, and the caption would clip.
        captionWidth = ceil(captionLabel.fittingSize.width)

        let title = NSMutableAttributedString(string: "Undo", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: theme.accentText,
            .kern: 0
        ])
        undoButton.attributedTitle = title
        buttonWidth = ceil(title.size().width) + UndoToastMetrics.buttonHorizontalPadding * 2
    }

    /// The text after the caption: the filename for one file, "N files" for a batch.
    private func updateSubject() {
        if UndoToastMetrics.isBatch(renamedFileCount: renamedCount) {
            updateBatchCount(renamedCount)
        } else if let lastFilename {
            updateName(lastFilename)
        }
    }

    /// Semibold count with tabular digits; no filenames.
    private func updateBatchCount(_ count: Int) {
        let text = NSAttributedString(string: UndoToastMetrics.batchCountText(count), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: DWBColor.textPrimary
        ])
        nameLabel.attributedStringValue = text
        nameWidth = ceil(nameLabel.fittingSize.width)
        needsLayout = true
    }

    private func updateName(_ filename: String) {
        let match = MarkerPrefixHighlight.match(
            in: filename,
            primary: SettingsWindowController.customPrefixValue(),
            secondary: SettingsWindowController.customPrefixSecondaryValue()
        )
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: DWBColor.textPrimary
        ]
        let text = NSMutableAttributedString(string: filename, attributes: base)
        if let match {
            text.addAttributes([
                .font: NSFont.systemFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: match.kind == .primary ? theme.markerPrimary : theme.markerSecondary
            ], range: NSRange(location: 0, length: match.utf16Length))
        }
        nameLabel.attributedStringValue = text
        nameWidth = ceil(nameLabel.fittingSize.width)
        needsLayout = true
    }

    /// Shows the toast for a single-file prefix change. A new call replaces the
    /// current toast and restarts the hold.
    func present(renamedTo filename: String) {
        lastFilename = filename
        renamedCount = 1
        applyColors()
        updateName(filename)
        announceAndPresent(UndoToastMetrics.spokenText(renamedFileCount: 1, filename: filename))
    }

    /// Shows the batch form for a successful multi-file prefix change: "Prefix changed on N files".
    /// Same replacement, hold and VoiceOver rules as the one-file toast.
    func present(renamedFileCount count: Int) {
        lastFilename = nil
        renamedCount = count
        applyColors()
        updateBatchCount(count)
        announceAndPresent(UndoToastMetrics.spokenText(renamedFileCount: count, filename: nil))
    }

    private func announceAndPresent(_ spoken: String) {
        setAccessibilityLabel(spoken)
        present(hold: UndoToastMetrics.hold)
        NSAccessibility.post(element: self,
                             notification: .announcementRequested,
                             userInfo: [.announcement: spoken,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let gap = UndoToastMetrics.gap
        let natural = UndoToastMetrics.leadingPadding + UndoToastMetrics.iconSize + gap
            + captionWidth + gap + nameWidth + gap + buttonWidth + UndoToastMetrics.trailingPadding
        return min(max(0, maxWidth), natural)
    }

    override func layout() {
        super.layout()
        let gap = UndoToastMetrics.gap
        let icon = UndoToastMetrics.iconSize
        iconView.frame = verticallyCentered(UndoToastMetrics.leadingPadding, width: icon, height: icon, in: bounds)

        let buttonX = bounds.width - UndoToastMetrics.trailingPadding - buttonWidth
        undoButton.frame = verticallyCentered(buttonX, width: buttonWidth, height: UndoToastMetrics.buttonHeight, in: bounds)

        let captionX = UndoToastMetrics.leadingPadding + icon + gap
        let labelHeight = ceil(captionLabel.intrinsicContentSize.height)
        captionLabel.frame = verticallyCentered(captionX, width: captionWidth, height: labelHeight, in: bounds)

        let nameX = captionX + captionWidth + gap
        nameLabel.frame = verticallyCentered(nameX,
                                             width: min(nameWidth, buttonX - gap - nameX),
                                             height: ceil(nameLabel.intrinsicContentSize.height),
                                             in: bounds)
    }

    @objc private func undoTapped() {
        onUndo?()
    }
}

// MARK: - Status HUD

/// Non-modal status HUD (`tokens-and-specs.md` 9.4): an icon, a title and an optional detail
/// line. It sits in the volume HUD's slot and replaces it; the window controller keeps the
/// two from showing together. Never takes the pointer.
final class StatusHUDView: OverlayPanelView {
    private let iconView = NSImageView()
    private let titleLabel = makeLabel()
    private let detailLabel = makeLabel()
    private var content: StatusHUDContent?
    private var textWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fadeDuration = DWBMotion.fade
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        setAccessibilityIdentifier("player.statusHUD")
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func contrastDidChange() {
        applyContent()
    }

    /// Shows `content`; a new call replaces the current one and restarts its hold.
    func present(content: StatusHUDContent) {
        self.content = content
        applyContent()
        present(hold: content.hold)
        NSAccessibility.post(element: self,
                             notification: .announcementRequested,
                             userInfo: [.announcement: content.spokenText,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func applyContent() {
        guard let content else { return }
        iconView.image = symbolImage(content.symbol, pointSize: StatusHUDMetrics.iconSize, weight: .regular)
        iconView.contentTintColor = content.tone == .caution ? DWBColor.cautionText : DWBColor.textPrimary

        titleLabel.attributedStringValue = NSAttributedString(string: content.title, attributes: [
            .font: NSFont.systemFont(ofSize: StatusHUDMetrics.titleFontSize, weight: .semibold),
            .foregroundColor: DWBColor.textPrimary
        ])
        detailLabel.attributedStringValue = NSAttributedString(string: content.detail ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: StatusHUDMetrics.detailFontSize),
            .foregroundColor: DWBAppearance.shared.textSecondary
        ])
        detailLabel.isHidden = content.detail?.isEmpty ?? true
        textWidth = ceil(max(titleLabel.fittingSize.width,
                             detailLabel.isHidden ? 0 : detailLabel.fittingSize.width))
        setAccessibilityLabel(content.spokenText)
        needsLayout = true
    }

    private var titleHeight: CGFloat { ceil(titleLabel.intrinsicContentSize.height) }
    private var detailHeight: CGFloat { detailLabel.isHidden ? 0 : ceil(detailLabel.intrinsicContentSize.height) }

    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let natural = StatusHUDMetrics.leadingPadding + StatusHUDMetrics.iconSize + StatusHUDMetrics.iconGap
            + textWidth + StatusHUDMetrics.trailingPadding
        let width = min(max(0, maxWidth), StatusHUDMetrics.maxWidth, natural)
        return NSSize(width: width,
                      height: StatusHUDMetrics.height(titleHeight: titleHeight, detailHeight: detailHeight))
    }

    override func layout() {
        super.layout()
        let icon = StatusHUDMetrics.iconSize
        iconView.frame = verticallyCentered(StatusHUDMetrics.leadingPadding, width: icon, height: icon, in: bounds)

        let textX = StatusHUDMetrics.leadingPadding + icon + StatusHUDMetrics.iconGap
        let textW = max(0, bounds.width - textX - StatusHUDMetrics.trailingPadding)
        let block = titleHeight + (detailHeight > 0 ? StatusHUDMetrics.lineGap + detailHeight : 0)
        var y = ((bounds.height - block) / 2).rounded()
        if detailHeight > 0 {
            detailLabel.frame = NSRect(x: textX, y: y, width: textW, height: detailHeight)
            y += detailHeight + StatusHUDMetrics.lineGap
        }
        titleLabel.frame = NSRect(x: textX, y: y, width: textW, height: titleHeight)
    }
}

// MARK: - Drop zone

private final class DashedBorderView: NSView {
    override func makeBackingLayer() -> CALayer { CAShapeLayer() }

    private var shape: CAShapeLayer? { layer as? CAShapeLayer }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shape?.fillColor = nil
        shape?.lineWidth = 2
        shape?.lineDashPattern = DropZoneCopy.dashPattern
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    func setStroke(_ color: NSColor) {
        shape?.strokeColor = color.cgColor
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        shape?.path = CGPath(roundedRect: rect,
                             cornerWidth: DropZoneCopy.radius - 1,
                             cornerHeight: DropZoneCopy.radius - 1,
                             transform: nil)
    }
}

/// Valid-state drop zone shown over the video or image area during a drag.
final class DropZoneOverlayView: OverlayPanelView {
    private let border = DashedBorderView()
    private let card = NSView()
    private let iconView = NSImageView()
    private let titleLabel = makeLabel()
    private let subtitleLabel = makeLabel()
    private var cardSize = NSSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        edgeColor = nil
        increaseContrastEdgeColor = nil
        showsShadow = false
        panelCornerRadius = DropZoneCopy.radius
        fadeDuration = DWBMotion.fade

        addSubview(border)

        card.wantsLayer = true
        card.layer?.cornerRadius = DWBMetrics.radiusCard
        addSubview(card)

        iconView.image = symbolImage("plus", pointSize: 24)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        card.addSubview(iconView)

        titleLabel.alignment = .center
        subtitleLabel.alignment = .center
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        setAccessibilityIdentifier("player.dropZone")
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var theme: DWBTheme { PlayerTheme.current }

    override func resolvedBackingColor() -> NSColor {
        increaseContrast ? theme.accentTintStrong : theme.accentTint
    }

    override func contrastDidChange() {
        applyColors()
    }

    private func applyColors() {
        border.setStroke(theme.accentText)
        card.layer?.backgroundColor = OverlayBacking.resolved(DWBColor.backingHUD, increaseContrast: increaseContrast).cgColor
        iconView.contentTintColor = theme.accentText
    }

    func present(fileCount: Int, folderCount: Int) {
        let title = DropZoneCopy.title(fileCount: fileCount, folderCount: folderCount)
        titleLabel.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: DWBColor.textPrimary
        ])
        subtitleLabel.attributedStringValue = NSAttributedString(string: DropZoneCopy.subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: increaseContrast ? DWBColor.textPrimary : DWBColor.textSecondary
        ])
        setAccessibilityLabel("\(title). \(DropZoneCopy.subtitle)")
        needsLayout = true
        present(hold: nil)
    }

    override func layout() {
        super.layout()
        border.frame = bounds

        let titleWidth = ceil(titleLabel.attributedStringValue.size().width)
        let subtitleWidth = ceil(subtitleLabel.attributedStringValue.size().width)
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        let subtitleHeight = ceil(subtitleLabel.intrinsicContentSize.height)
        let iconHeight: CGFloat = 24
        let contentWidth = max(titleWidth, subtitleWidth, iconHeight)
        let width = min(bounds.width * 0.8, contentWidth + 44)
        let height = 16 + iconHeight + 8 + titleHeight + 8 + subtitleHeight + 16
        cardSize = NSSize(width: width, height: height)
        card.frame = NSRect(x: ((bounds.width - width) / 2).rounded(),
                            y: ((bounds.height - height) / 2).rounded(),
                            width: width, height: height)

        var y = height - 16 - iconHeight
        iconView.frame = NSRect(x: (width - iconHeight) / 2, y: y, width: iconHeight, height: iconHeight)
        y -= 8 + titleHeight
        titleLabel.frame = NSRect(x: 22, y: y, width: width - 44, height: titleHeight)
        y -= 8 + subtitleHeight
        subtitleLabel.frame = NSRect(x: 22, y: y, width: width - 44, height: subtitleHeight)
    }
}

// MARK: - Settings target outline

/// Outline on the content edge of the player window that Settings controls (P136).
/// Same rule as a focused pane: 2 pt in the accent fill, 3 pt in accent text under
/// Increase Contrast. Draw-only: it takes no mouse events and does not affect layout.
final class SettingsTargetOutlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        isHidden = true
        setAccessibilityElement(false)
        applyAppearance()
        DWBAppearance.observe(self, selector: #selector(appearanceDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func appearanceDidChange() {
        applyAppearance()
    }

    private func applyAppearance() {
        layer?.borderColor = DWBAppearance.shared.focusRingColor.cgColor
        layer?.borderWidth = DWBAppearance.shared.focusRingWidth
    }
}
