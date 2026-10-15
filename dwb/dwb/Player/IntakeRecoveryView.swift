import Cocoa

final class IntakeRecoveryView: NSView {
    var actionHandler: ((MediaIntakeRecoveryAction) -> Void)?
    var dismissHandler: (() -> Void)?
    var layoutDidChange: (() -> Void)?

    private let statusImageView = NSImageView()
    private let progressIndicator = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton()
    private var actionButtons: [NSButton] = []
    private var actions: [MediaIntakeRecoveryAction] = []
    private var presentation: MediaIntakeRecoveryPresentation?

    private enum Metrics {
        static let paddingTop: CGFloat = 16
        static let paddingRight: CGFloat = 16
        static let paddingBottom: CGFloat = 16
        static let paddingLeft: CGFloat = 18
        static let statusIconSize: CGFloat = 22
        static let iconTextGap: CGFloat = 10
        static let titleHeight: CGFloat = 18
        static let messageHeight: CGFloat = 30
        static let titleMessageGap: CGFloat = 4
        static let buttonHeight: CGFloat = 24
        static let buttonGap: CGFloat = 6
        static let closeSize: CGFloat = 24
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        PlayerAccessibilityEnvironment.observeChanges(self, selector: #selector(accessibilityOptionsChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit {
        PlayerAccessibilityEnvironment.stopObserving(self)
    }

    @objc private func accessibilityOptionsChanged() {
        applyContrastColors()
        // Action buttons carry contrast-dependent borders and text; rebuild them in place.
        if let presentation, !actionButtons.isEmpty {
            rebuildActionButtons(for: presentation.actions)
            needsLayout = true
        }
    }

    /// Increase Contrast lifts the secondary text roles one step.
    private func applyContrastColors() {
        let increased = PlayerAccessibilityEnvironment.increaseContrast
        messageLabel.textColor = increased ? DWBColor.textPrimary : DWBColor.textSecondary
        detailsLabel.textColor = increased ? DWBColor.textSecondary : DWBColor.textTertiary
    }

    func present(_ presentation: MediaIntakeRecoveryPresentation) {
        // A count update to the card already on screen changes only its text, so the
        // buttons (and keyboard focus on them) survive repeated progress updates.
        if !isHidden, let current = self.presentation,
           current.title == presentation.title,
           current.actions == presentation.actions,
           current.style == presentation.style {
            self.presentation = presentation
            messageLabel.stringValue = presentation.message
            setAccessibilityValue(presentation.message)
            return
        }
        self.presentation = presentation
        titleLabel.stringValue = presentation.title
        messageLabel.stringValue = presentation.message
        detailsLabel.stringValue = presentation.details
        detailsLabel.isHidden = true
        applyPresentationStyle(presentation)
        rebuildActionButtons(for: presentation.actions)
        dismissButton.isHidden = !presentation.allowsDismissal
        dismissButton.setAccessibilityElement(presentation.allowsDismissal)
        setAccessibilityLabel(presentation.title)
        setAccessibilityValue(presentation.message)
        setAccessibilityElement(true)
        isHidden = false
        needsLayout = true
        layoutDidChange?()
        window?.recalculateKeyViewLoop()
    }

    func dismiss() {
        isHidden = true
        setAccessibilityElement(false)
        actionButtons.forEach { $0.setAccessibilityElement(false) }
        dismissButton.setAccessibilityElement(false)
        window?.recalculateKeyViewLoop()
    }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        let compact = width < 380
        let actionCount = presentation?.actions.count ?? 0
        let actionBlockHeight: CGFloat
        if actionCount == 0 {
            actionBlockHeight = 0
        } else if compact {
            actionBlockHeight = CGFloat(actionCount) * Metrics.buttonHeight
                + CGFloat(max(0, actionCount - 1)) * Metrics.buttonGap
        } else {
            actionBlockHeight = Metrics.buttonHeight
        }
        let detailsHeight: CGFloat = detailsLabel.isHidden ? 0 : 42
        let actionGap: CGFloat = actionCount == 0 ? 0 : 12
        return Metrics.paddingTop + Metrics.titleHeight + Metrics.titleMessageGap + Metrics.messageHeight
            + actionGap + actionBlockHeight + detailsHeight + Metrics.paddingBottom
    }

    override func layout() {
        super.layout()
        let top = bounds.height - Metrics.paddingTop
        dismissButton.frame = NSRect(x: bounds.width - Metrics.paddingRight - Metrics.closeSize,
                                     y: top - Metrics.closeSize,
                                     width: Metrics.closeSize,
                                     height: Metrics.closeSize)
        statusImageView.frame = NSRect(x: Metrics.paddingLeft,
                                       y: top - Metrics.statusIconSize,
                                       width: Metrics.statusIconSize,
                                       height: Metrics.statusIconSize)
        progressIndicator.frame = statusImageView.frame.insetBy(dx: 3, dy: 3)
        let textLeading = Metrics.paddingLeft + Metrics.statusIconSize + Metrics.iconTextGap
        titleLabel.frame = NSRect(x: textLeading,
                                  y: top - Metrics.titleHeight,
                                  width: max(0, dismissButton.frame.minX - textLeading - 8),
                                  height: Metrics.titleHeight)
        messageLabel.frame = NSRect(x: textLeading,
                                    y: top - Metrics.titleHeight - Metrics.titleMessageGap - Metrics.messageHeight,
                                    width: max(0, bounds.width - textLeading - Metrics.paddingRight),
                                    height: Metrics.messageHeight)

        let buttonHeight = Metrics.buttonHeight
        let compact = bounds.width < 380
        let buttonBlockHeight: CGFloat
        if compact {
            buttonBlockHeight = actionButtons.isEmpty
                ? 0
                : CGFloat(actionButtons.count) * buttonHeight + CGFloat(max(0, actionButtons.count - 1)) * Metrics.buttonGap
            for (index, button) in actionButtons.enumerated() {
                let y = Metrics.paddingBottom + CGFloat(actionButtons.count - index - 1) * (buttonHeight + Metrics.buttonGap)
                button.frame = NSRect(x: textLeading,
                                      y: y,
                                      width: max(0, bounds.width - textLeading - Metrics.paddingRight),
                                      height: buttonHeight)
            }
        } else {
            buttonBlockHeight = actionButtons.isEmpty ? 0 : buttonHeight
            var x = textLeading
            for button in actionButtons {
                let width = max(78, ceil(button.intrinsicContentSize.width) + 20)
                button.frame = NSRect(x: x, y: Metrics.paddingBottom, width: width, height: buttonHeight)
                x += width + 8
            }
        }

        detailsLabel.frame = detailsLabel.isHidden
            ? .zero
            : NSRect(x: textLeading,
                     y: Metrics.paddingBottom + buttonBlockHeight + 8,
                     width: max(0, bounds.width - textLeading - Metrics.paddingRight),
                     height: 34)
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.radiusCard
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = DWBColor.cautionFill.cgColor
        layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("player.intakeRecovery")
        isHidden = true
        setAccessibilityElement(false)

        statusImageView.imageScaling = .scaleProportionallyDown
        statusImageView.setAccessibilityElement(false)
        addSubview(statusImageView)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.setAccessibilityElement(false)
        progressIndicator.isHidden = true
        addSubview(progressIndicator)

        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = DWBColor.textPrimary
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)

        messageLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        messageLabel.maximumNumberOfLines = 2
        messageLabel.setAccessibilityElement(false)
        addSubview(messageLabel)

        detailsLabel.font = .systemFont(ofSize: 10.5)
        detailsLabel.maximumNumberOfLines = 2
        detailsLabel.setAccessibilityElement(false)
        addSubview(detailsLabel)

        applyContrastColors()

        dismissButton.isBordered = false
        dismissButton.bezelStyle = .regularSquare
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        dismissButton.toolTip = "Dismiss intake message"
        dismissButton.setAccessibilityLabel("Dismiss")
        dismissButton.setAccessibilityHelp("Dismiss this media intake message")
        dismissButton.setAccessibilityIdentifier("player.intakeRecovery.dismiss")
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)
        addSubview(dismissButton)
    }

    private func rebuildActionButtons(for actions: [MediaIntakeRecoveryAction]) {
        actionButtons.forEach { $0.removeFromSuperview() }
        self.actions = actions
        actionButtons = actions.enumerated().map { index, action in
            let button = NSButton(title: action.title, target: self, action: #selector(actionTapped(_:)))
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.tag = index
            button.toolTip = action.title
            button.setAccessibilityLabel(action.title)
            button.setAccessibilityHelp(accessibilityHelp(for: action))
            button.setAccessibilityIdentifier("player.intakeRecovery.\(action.rawValue)")
            button.setAccessibilityElement(true)
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.layer?.borderWidth = 1
            if index == 0 && action != .cancelIntake {
                button.isBordered = false
                button.layer?.backgroundColor = PlayerTheme.current.accentFill.cgColor
                button.layer?.borderColor = PlayerTheme.current.accentFill.cgColor
                button.contentTintColor = DWBColor.textOnFill
                button.font = .systemFont(ofSize: 11, weight: .semibold)
            } else if action == .showDetails {
                button.isBordered = false
                button.layer?.backgroundColor = NSColor.clear.cgColor
                button.layer?.borderColor = NSColor.clear.cgColor
                button.contentTintColor = DWBAppearance.shared.textSecondary
            } else {
                button.isBordered = false
                button.layer?.backgroundColor = DWBColor.overlayHover.cgColor
                button.layer?.borderColor = DWBAppearance.shared.border.cgColor
                button.contentTintColor = DWBColor.textPrimary
            }
            addSubview(button)
            return button
        }
        dismissButton.setAccessibilityElement(presentation?.allowsDismissal == true)
    }

    private func applyPresentationStyle(_ presentation: MediaIntakeRecoveryPresentation) {
        let symbolName: String
        let foreground: NSColor
        let border: NSColor
        switch presentation.style {
        case .progress:
            symbolName = "magnifyingglass"
            foreground = PlayerTheme.current.accentText
            border = PlayerTheme.current.accentFill
        case .warning:
            symbolName = "exclamationmark.triangle.fill"
            foreground = DWBColor.cautionText
            border = DWBColor.cautionFill
        case .error:
            symbolName = "xmark.octagon.fill"
            foreground = DWBColor.errorText
            border = DWBColor.errorFill
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        statusImageView.image = image?.withSymbolConfiguration(configuration) ?? image
        statusImageView.contentTintColor = foreground
        layer?.borderColor = border.cgColor
        progressIndicator.isHidden = presentation.style != .progress
        statusImageView.isHidden = presentation.style == .progress
        if presentation.style == .progress {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func accessibilityHelp(for action: MediaIntakeRecoveryAction) -> String {
        switch action {
        case .addMedia: return "Choose local files or folders to add"
        case .openAcceptSettings: return "Open the Accept media type settings"
        case .retryRescan: return "Retry scanning the source folder"
        case .revealSource: return "Reveal the source folder in Finder"
        case .locateSource: return "Choose the source folder again"
        case .showDetails: return "Show diagnostic details for this failure"
        case .cancelIntake: return "Stop loading the dropped media"
        }
    }

    @objc private func dismissTapped() {
        dismissHandler?()
    }

    @objc private func actionTapped(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        let action = actions[sender.tag]
        if action == .showDetails {
            detailsLabel.isHidden.toggle()
            sender.title = detailsLabel.isHidden ? "Show Details" : "Hide Details"
            sender.setAccessibilityLabel(sender.title)
            setAccessibilityValue(detailsLabel.isHidden
                ? presentation?.message
                : [presentation?.message, presentation?.details].compactMap { $0 }.joined(separator: " "))
            needsLayout = true
            layoutDidChange?()
            return
        }
        actionHandler?(action)
    }
}
