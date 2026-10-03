import Cocoa

/// Compact keyboard-shortcut tag rendered beside a control (e.g. "N" next to the
/// custom prefix rename buttons). Decorative only: it never intercepts clicks and is hidden
/// from accessibility — the shortcut is announced through the control's own
/// help/tooltip text instead. Dark-theme styling matches the rail/footer chrome.
final class ShortcutKeyBadge: NSTextField {
    static let badgeWidth: CGFloat  = 15
    static let badgeHeight: CGFloat = 13

    init(key: String) {
        super.init(frame: .zero)
        stringValue = key
        isEditable = false
        isSelectable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        alignment = .center
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        font = .monospacedSystemFont(ofSize: 8, weight: .semibold)
        textColor = DWBAppearance.shared.textSecondary
        wantsLayer = true
        layer?.backgroundColor = DWBColor.canvas.cgColor
        layer?.borderColor = DWBColor.borderStrong.cgColor
        layer?.borderWidth = 1.0
        layer?.cornerRadius = DWBMetrics.radiusTag
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Source-over composite of two colors, used where a hover or pressed overlay
/// sits on top of a toggled tint.
private func composite(_ top: NSColor, over bottom: NSColor) -> NSColor {
    guard let t = top.usingColorSpace(.sRGB), let b = bottom.usingColorSpace(.sRGB) else { return top }
    let alpha = t.alphaComponent + b.alphaComponent * (1 - t.alphaComponent)
    guard alpha > 0 else { return .clear }
    func channel(_ tc: CGFloat, _ bc: CGFloat) -> CGFloat {
        (tc * t.alphaComponent + bc * b.alphaComponent * (1 - t.alphaComponent)) / alpha
    }
    return NSColor(srgbRed: channel(t.redComponent, b.redComponent),
                   green: channel(t.greenComponent, b.greenComponent),
                   blue: channel(t.blueComponent, b.blueComponent),
                   alpha: alpha)
}

final class RailButton: NSButton {
    enum Style: Equatable {
        case normal
        case emphasized
        case utility
        case prefixPrimary
        case prefixSecondary
        case bookmark
        case warning
    }

    var railStyle: Style = .normal {
        didSet {
            guard railStyle != oldValue else { return }
            updateAppearance()
        }
    }

    var isToggled: Bool = false {
        didSet {
            setAccessibilityValue(isToggled ? "on" : "off")
            updateAppearance()
        }
    }

    var interactionStateDidChange: (() -> Void)?

    private var isHovering = false
    private var isPressing = false
    private var tracking: NSTrackingArea?
    private let focusRingLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("programmatic only")
    }

    deinit {
        PlayerAccessibilityEnvironment.stopObserving(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
        interactionStateDidChange?()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
        interactionStateDidChange?()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPressing = true
        updateAppearance()
        interactionStateDidChange?()
        super.mouseDown(with: event)
        isPressing = false
        updateAppearance()
        interactionStateDidChange?()
    }

    override var isEnabled: Bool {
        didSet {
            setAccessibilityEnabled(isEnabled)
            updateAppearance()
        }
    }

    override var title: String {
        didSet { updateAppearance() }
    }

    override var acceptsFirstResponder: Bool {
        isEnabled && !isHidden && alphaValue > 0.05
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateAppearance()
        interactionStateDidChange?()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateAppearance()
        interactionStateDidChange?()
        return resigned
    }

    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }

    override func drawFocusRingMask() {
        NSBezierPath(ovalIn: focusRingMaskBounds).fill()
    }

    override func layout() {
        super.layout()
        updateFocusRingPath()
    }

    func configureSymbol(_ symbolName: String,
                         pointSize: CGFloat,
                         accessibilityLabel: String,
                         help: String,
                         fallbackNames: [String] = []) {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        for candidate in [symbolName] + fallbackNames {
            if let image = NSImage(systemSymbolName: candidate,
                                   accessibilityDescription: accessibilityLabel) {
                self.image = image.withSymbolConfiguration(cfg) ?? image
                break
            }
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityHelp(help)
        toolTip = help
    }

    private func configure() {
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.borderWidth = 0
        focusRingLayer.fillColor = nil
        focusRingLayer.isHidden = true
        layer?.addSublayer(focusRingLayer)
        contentTintColor = DWBColor.textPrimary
        PlayerAccessibilityEnvironment.observeChanges(self, selector: #selector(accessibilityOptionsChanged))
        updateAppearance()
    }

    @objc private func accessibilityOptionsChanged() {
        updateAppearance()
    }

    /// Glyph and title color for the current style when the button is not toggled.
    private var restTint: NSColor {
        switch railStyle {
        case .normal, .emphasized, .utility: return DWBColor.textPrimary
        case .prefixPrimary: return PlayerTheme.current.markerPrimary
        case .prefixSecondary: return PlayerTheme.current.markerSecondary
        case .bookmark: return PlayerTheme.current.accentText
        case .warning: return DWBColor.cautionText
        }
    }

    /// Glyph color when toggled. Styled buttons keep their own tone; a plain
    /// button takes the accent.
    private var toggledTint: NSColor {
        switch railStyle {
        case .normal, .emphasized, .utility: return PlayerTheme.current.accentText
        default: return restTint
        }
    }

    /// Ring and tint base for the toggled state.
    private var toggledFill: NSColor {
        switch railStyle {
        case .prefixPrimary: return DWBColor.orangeFillDark
        case .prefixSecondary: return DWBColor.tealFillDark
        case .warning: return DWBColor.cautionFill
        default: return PlayerTheme.current.accentFill
        }
    }

    private func updateAppearance() {
        alphaValue = isEnabled ? 1.0 : DWBMetrics.disabledAlpha

        let increasedContrast = PlayerAccessibilityEnvironment.increaseContrast
        let keyboardFocused = window?.firstResponder === self && isEnabled
        let interactive = isEnabled
        let toggled = isToggled && isEnabled

        var fill = NSColor.clear
        var ring: NSColor?

        if toggled {
            fill = toggledFill.withAlphaComponent(0.28)
            ring = toggledFill
            if isPressing && interactive {
                fill = composite(DWBColor.overlayPressed, over: fill)
            } else if isHovering && interactive {
                fill = composite(DWBColor.overlayHover, over: fill)
            }
        } else {
            if railStyle == .emphasized {
                fill = DWBColor.overlaySelected
                if isPressing && interactive {
                    fill = composite(DWBColor.overlayPressed, over: fill)
                } else if isHovering && interactive {
                    fill = DWBColor.overlayPressed
                }
            } else if isPressing && interactive {
                fill = DWBColor.overlayPressed
            } else if isHovering && interactive {
                fill = DWBColor.overlayHover
            }
            if increasedContrast {
                ring = DWBColor.borderStrong
            }
        }

        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = ring?.cgColor
        layer?.borderWidth = ring == nil ? 0 : 1

        let tint = toggled ? toggledTint : restTint
        contentTintColor = tint
        applyTitleTint(tint)

        focusRingLayer.isHidden = !keyboardFocused
        focusRingLayer.strokeColor = PlayerTheme.current.focusRing(increaseContrast: increasedContrast).cgColor
        focusRingLayer.lineWidth = increasedContrast ? DWBMetrics.focusWidthIC : DWBMetrics.focusWidth
        updateFocusRingPath()
    }

    /// A ring of `focusWidth` whose inner edge sits 2 pt outside the button.
    private func updateFocusRingPath() {
        let width = focusRingLayer.lineWidth
        let outset = 2 + width / 2
        focusRingLayer.frame = bounds
        focusRingLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: -outset, dy: -outset), transform: nil)
    }

    private func applyTitleTint(_ tint: NSColor) {
        guard image == nil else { return }
        let currentTitle = title
        guard !currentTitle.isEmpty else {
            attributedTitle = NSAttributedString(string: "")
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: tint
        ]
        attributedTitle = NSAttributedString(string: currentTitle, attributes: attributes)
    }
}
