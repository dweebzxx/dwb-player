import AppKit

extension NSColor {
    /// This color, treated as an overlay (such as `overlayHover`), laid over `base`.
    func dwbComposited(over base: NSColor) -> NSColor {
        guard base.alphaComponent > 0.001 else { return self }
        let flat = withAlphaComponent(1)
        return base.blended(withFraction: alphaComponent, of: flat) ?? self
    }
}

/// Layer-drawn button base for the Queue Page chrome: one fill, one 1 pt edge, hover and
/// pressed overlays, a focus ring that follows Increase Contrast, and the 32% disabled
/// treatment. Subclasses set `fillColor`, `edgeColor` and the label in `restyle()`.
class QueueChromeButton: NSButton {
    var fillColor: NSColor = .clear { didSet { updateAppearance() } }
    var edgeColor: NSColor = .clear { didSet { updateAppearance() } }
    var cornerRadius: CGFloat = DWBMetrics.radiusControl { didSet { needsLayout = true } }

    private(set) var isHovering = false
    private(set) var isPressing = false
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        isBordered = false
        title = ""
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() {
        restyle()
        updateAppearance()
    }

    /// Recompute colors and the label from the current appearance.
    func restyle() {}

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(cornerRadius, bounds.height / 2)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
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
        guard isEnabled else { return }
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restyle()
        updateAppearance()
    }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { isHovering = false }
            restyle()
            updateAppearance()
        }
    }

    func updateAppearance() {
        var fill = fillColor
        if isEnabled {
            if isPressing {
                fill = DWBColor.overlayPressed.dwbComposited(over: fillColor)
            } else if isHovering {
                fill = DWBColor.overlayHover.dwbComposited(over: fillColor)
            }
        }
        layer?.backgroundColor = fill.cgColor
        let focused = window?.firstResponder === self
        if focused {
            layer?.borderColor = DWBAppearance.shared.focusRingColor.cgColor
            layer?.borderWidth = DWBAppearance.shared.focusRingWidth
        } else {
            layer?.borderColor = edgeColor.cgColor
            layer?.borderWidth = edgeColor.alphaComponent > 0 ? 1 : 0
        }
        alphaValue = isEnabled ? 1.0 : DWBMetrics.disabledAlpha
    }
}

// MARK: - Pill (Rescan, Clear Queue, empty-state action)

final class QueuePillButton: QueueChromeButton {
    enum Style { case standard, outlineAccent }

    private let style: Style
    private let labelColorProvider: () -> NSColor
    private var symbol: NSImage?
    var labelText = "" { didSet { restyle() } }
    var isIconOnly = false { didSet { restyle(); invalidateIntrinsicContentSize() } }

    init(style: Style = .standard, labelColor: @escaping () -> NSColor) {
        self.style = style
        self.labelColorProvider = labelColor
        super.init(frame: .zero)
        cornerRadius = DWBMetrics.radiusPill
    }

    required init?(coder: NSCoder) { fatalError() }

    func setIconSymbol(_ name: String, description: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        symbol = image?.withSymbolConfiguration(configuration) ?? image
        restyle()
    }

    override func restyle() {
        let appearance = DWBAppearance.shared
        switch style {
        case .standard:
            fillColor = DWBColor.surfaceElevated
            edgeColor = appearance.border
        case .outlineAccent:
            fillColor = .clear
            edgeColor = DWBColor.borderStrong
        }
        let color = labelColorProvider()
        if isIconOnly, let symbol {
            title = ""
            image = symbol
            imagePosition = .imageOnly
            contentTintColor = color
        } else {
            image = nil
            imagePosition = .noImage
            let weight: NSFont.Weight = style == .outlineAccent ? .semibold : .regular
            let size: CGFloat = style == .outlineAccent ? 12 : 11.5
            attributedTitle = NSAttributedString(string: labelText, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: Self.centeredParagraph
            ])
        }
    }

    private static let centeredParagraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byClipping
        return p
    }()

    /// Width for the full label (12 pt padding each side).
    func preferredWidth() -> CGFloat {
        if isIconOnly { return QueuePanelMetrics.compactIconPillWidth }
        let size: CGFloat = style == .outlineAccent ? 12 : 11.5
        let weight: NSFont.Weight = style == .outlineAccent ? .semibold : .regular
        let textWidth = (labelText as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        return ceil(textWidth) + 24
    }
}

// MARK: - Marker chip (N / M)

final class QueueMarkerChipButton: QueueChromeButton {
    let kind: QueueMarkerChipState.Kind
    private(set) var chipState: QueueMarkerChipState

    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
    private static let tagFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)

    init(kind: QueueMarkerChipState.Kind) {
        self.kind = kind
        self.chipState = QueueMarkerChipState(kind: kind, label: "—", isBlank: true, isApplied: false, isEnabled: false)
        super.init(frame: .zero)
        cornerRadius = DWBMetrics.radiusControl
    }

    required init?(coder: NSCoder) { fatalError() }

    private var markerColor: NSColor {
        kind == .primary ? PlayerTheme.current.markerPrimary : PlayerTheme.current.markerSecondary
    }

    func apply(_ state: QueueMarkerChipState) {
        chipState = state
        isEnabled = state.isEnabled
        setAccessibilityValue(state.isApplied ? "applied" : (state.isBlank ? "no prefix set" : "not applied"))
        restyle()
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    override func restyle() {
        if chipState.isApplied && chipState.isEnabled {
            let alpha = DWBAppearance.shared.increaseContrast ? 0.28 : 0.18
            fillColor = markerColor.withAlphaComponent(alpha)
            edgeColor = markerColor
        } else {
            fillColor = .clear
            edgeColor = .clear
        }
        needsDisplay = true
    }

    private var labelColor: NSColor {
        chipState.isBlank || !chipState.isEnabled ? DWBColor.textDisabled : markerColor
    }

    private var tagTextSize: NSSize {
        (chipState.keyTag as NSString).size(withAttributes: [.font: Self.tagFont])
    }

    private var tagWidth: CGFloat { ceil(tagTextSize.width) + 8 }
    private var labelWidth: CGFloat {
        ceil((chipState.label as NSString).size(withAttributes: [.font: Self.labelFont]).width)
    }

    func preferredWidth() -> CGFloat {
        8 + labelWidth + 6 + tagWidth + 8
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth(), height: QueuePanelMetrics.markerChipHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: labelColor]
        let labelSize = (chipState.label as NSString).size(withAttributes: labelAttributes)
        let labelOrigin = NSPoint(x: 8, y: floor((bounds.height - labelSize.height) / 2))
        (chipState.label as NSString).draw(at: labelOrigin, withAttributes: labelAttributes)

        let tagHeight: CGFloat = 14
        let tagRect = NSRect(x: labelOrigin.x + ceil(labelSize.width) + 6,
                             y: floor((bounds.height - tagHeight) / 2),
                             width: tagWidth,
                             height: tagHeight)
        let tagEdge = chipState.isEnabled ? DWBAppearance.shared.border : DWBAppearance.shared.border.withAlphaComponent(0.6)
        let path = NSBezierPath(roundedRect: tagRect.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusTag, yRadius: DWBMetrics.radiusTag)
        path.lineWidth = 1
        tagEdge.setStroke()
        path.stroke()
        let tagAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.tagFont,
            .foregroundColor: chipState.isEnabled ? DWBAppearance.shared.textTertiary : DWBColor.textDisabled
        ]
        let tagTextOrigin = NSPoint(x: tagRect.minX + (tagRect.width - tagTextSize.width) / 2,
                                    y: tagRect.minY + (tagRect.height - tagTextSize.height) / 2)
        (chipState.keyTag as NSString).draw(at: tagTextOrigin, withAttributes: tagAttributes)
    }
}

// MARK: - Undo button

final class QueueUndoButton: QueueChromeButton {
    var isCompact = false { didSet { restyle(); invalidateIntrinsicContentSize() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cornerRadius = DWBMetrics.radiusControl
        setAccessibilityLabel("Undo last marker rename, Command-Z")
        setAccessibilityHelp("Restores the filenames changed by the most recent marker rename in this window")
        setAccessibilityIdentifier("queue.footer.undoMarkerRename")
        toolTip = "Undo Marker Rename (⌘Z)"
    }

    required init?(coder: NSCoder) { fatalError() }

    private var contentColor: NSColor {
        isEnabled ? DWBColor.textPrimary : DWBColor.textDisabled
    }

    override func restyle() {
        fillColor = .clear
        edgeColor = .clear
        let color = contentColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let glyph = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")?
            .withSymbolConfiguration(configuration)
        if isCompact {
            title = ""
            image = glyph
            imagePosition = .imageOnly
            contentTintColor = color
            return
        }
        image = nil
        imagePosition = .noImage
        let text = NSMutableAttributedString()
        if let glyph {
            let attachment = NSTextAttachment()
            attachment.image = glyph.tinted(with: color)
            attachment.bounds = NSRect(x: 0, y: -2, width: glyph.size.width, height: glyph.size.height)
            text.append(NSAttributedString(attachment: attachment))
        }
        text.append(NSAttributedString(string: " Undo", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: color
        ]))
        text.append(NSAttributedString(string: " ⌘Z", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: isEnabled ? DWBAppearance.shared.textTertiary : DWBColor.textDisabled
        ]))
        attributedTitle = text
    }

    func preferredWidth() -> CGFloat {
        isCompact ? 28 : 8 + 12 + 5 + 30 + 5 + 18 + 8
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth(), height: QueuePanelMetrics.markerChipHeight)
    }
}

extension NSImage {
    /// A copy of a template image filled with `color`, for use inside attributed strings.
    func tinted(with color: NSColor) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}

// MARK: - Marker chip group

/// The footer's marker group: primary chip, secondary chip, a divider, and Undo.
final class QueueMarkerChipGroupView: NSView {
    let primaryChip = QueueMarkerChipButton(kind: .primary)
    let secondaryChip = QueueMarkerChipButton(kind: .secondary)
    let undoButton = QueueUndoButton()
    private let divider = NSView()

    private(set) var showsPrimary = false
    private(set) var showsSecondary = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.radiusPill
        layer?.borderWidth = 1
        setAccessibilityRole(.group)
        setAccessibilityLabel("File markers")
        divider.wantsLayer = true
        addSubview(primaryChip)
        addSubview(secondaryChip)
        addSubview(divider)
        addSubview(undoButton)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { restyle() }

    private func restyle() {
        layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        layer?.borderColor = DWBAppearance.shared.border.cgColor
        divider.layer?.backgroundColor = DWBAppearance.shared.border.cgColor
    }

    func apply(primary: QueueMarkerChipState?,
               secondary: QueueMarkerChipState?,
               undoEnabled: Bool,
               compactUndo: Bool) {
        showsPrimary = primary != nil
        showsSecondary = secondary != nil
        primaryChip.isHidden = primary == nil
        secondaryChip.isHidden = secondary == nil
        primaryChip.setAccessibilityElement(primary != nil)
        secondaryChip.setAccessibilityElement(secondary != nil)
        if let primary { primaryChip.apply(primary) }
        if let secondary { secondaryChip.apply(secondary) }
        undoButton.isCompact = compactUndo
        undoButton.isEnabled = undoEnabled
        undoButton.restyle()
        needsLayout = true
    }

    private static let chipGap: CGFloat = 2
    private static let dividerWidth: CGFloat = 1
    private static let dividerMargin: CGFloat = 3

    func preferredWidth(compactUndo: Bool) -> CGFloat {
        let wasCompact = undoButton.isCompact
        undoButton.isCompact = compactUndo
        defer { undoButton.isCompact = wasCompact }
        var width = QueuePanelMetrics.markerGroupPadding * 2
        if showsPrimary { width += primaryChip.preferredWidth() + Self.chipGap }
        if showsSecondary { width += secondaryChip.preferredWidth() + Self.chipGap }
        if showsPrimary || showsSecondary {
            width += Self.dividerMargin * 2 + Self.dividerWidth
        }
        width += undoButton.preferredWidth()
        return width
    }

    override func layout() {
        super.layout()
        let chipH = QueuePanelMetrics.markerChipHeight
        let y = floor((bounds.height - chipH) / 2)
        var x = QueuePanelMetrics.markerGroupPadding
        if showsPrimary {
            let w = primaryChip.preferredWidth()
            primaryChip.frame = NSRect(x: x, y: y, width: w, height: chipH)
            x += w + Self.chipGap
        }
        if showsSecondary {
            let w = secondaryChip.preferredWidth()
            secondaryChip.frame = NSRect(x: x, y: y, width: w, height: chipH)
            x += w + Self.chipGap
        }
        if showsPrimary || showsSecondary {
            x += Self.dividerMargin - Self.chipGap
            divider.isHidden = false
            divider.frame = NSRect(x: x, y: floor((bounds.height - 14) / 2), width: Self.dividerWidth, height: 14)
            x += Self.dividerWidth + Self.dividerMargin
        } else {
            divider.isHidden = true
        }
        undoButton.frame = NSRect(x: x, y: y, width: undoButton.preferredWidth(), height: chipH)
    }
}
