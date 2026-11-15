import AppKit

// Native controls for the Queue Page's active look (`tokens-and-specs.md` §10). Each control draws
// itself: no bezel, no cell drawing, no layer animation and no transform, so a press never moves
// anything. Geometry comes from `QueuePanelLayout.swift`; values from `DWBMetrics`.

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

/// SF Symbols drawn in one flat color (palette rendering), so a control can draw them with
/// `NSImage.draw` over its own fill without tinting the fill.
enum QueueSymbol {
    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let size = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let palette = NSImage.SymbolConfiguration(paletteColors: [color, color, color])
        return base.withSymbolConfiguration(size.applying(palette))
    }

    /// Draws `image` centered in `rect`.
    static func draw(_ image: NSImage?, centeredIn rect: NSRect) {
        guard let image else { return }
        let size = image.size
        let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                            width: size.width, height: size.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

// MARK: - Rules

/// A hairline: a gridLine rule or a 0.5 pt divider. Lets the pointer through.
final class QueueRuleView: NSView {
    enum Kind { case rule, divider }

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(false)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = DWBAppearance.shared
        switch kind {
        case .rule: (appearance.increaseContrast ? appearance.border : DWBColor.gridLine).setFill()
        case .divider: appearance.border.setFill()
        }
        bounds.fill()
    }
}

// MARK: - Button base

private final class QueueButtonCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {}
}

/// Hover, press and keyboard-focus state for a self-drawn button. The press follows the pointer
/// while it is down and the action runs on release inside; nothing but the fill changes.
class QueueControlButton: NSButton {
    private(set) var isHovering = false
    private(set) var isPressing = false
    private(set) var showsKeyboardFocus = false
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled && super.acceptsFirstResponder }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = QueueButtonCell(textCell: "")
        setButtonType(.momentaryPushIn)
        isBordered = false
        title = ""
        focusRingType = .none
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovering = false
                isPressing = false
            }
            alphaValue = isEnabled ? 1 : DWBMetrics.queueFooterDisabledAlpha
            needsDisplay = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovering = false
        isPressing = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        isPressing = true
        needsDisplay = true
        var inside = true
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if isPressing != inside {
                isPressing = inside
                needsDisplay = true
                displayIfNeeded()
            }
            if next.type == .leftMouseUp { break }
        }
        isPressing = false
        isHovering = inside
        needsDisplay = true
        if inside { sendAction(action, to: target) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            // A ring for the keyboard only: a press with the pointer never draws one.
            let type = NSApp.currentEvent?.type
            showsKeyboardFocus = type != .leftMouseDown && type != .rightMouseDown
            needsDisplay = true
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        showsKeyboardFocus = false
        needsDisplay = true
        return resigned
    }

    /// The focus ring (2 pt accent fill; Increase Contrast: 3 pt accent text), drawn inside `rect`.
    func drawFocusRing(in rect: NSRect, radius: CGFloat) {
        guard showsKeyboardFocus else { return }
        let appearance = DWBAppearance.shared
        let width = appearance.focusRingWidth
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), xRadius: radius, yRadius: radius)
        path.lineWidth = width
        appearance.focusRingColor.setStroke()
        path.stroke()
    }

    static func cellOverlay(hovering: Bool, pressing: Bool) -> NSColor? {
        if pressing { return DWBColor.textPrimary.withAlphaComponent(DWBMetrics.queueCellPressedAlpha) }
        if hovering { return DWBColor.textPrimary.withAlphaComponent(DWBMetrics.queueCellHoverAlpha) }
        return nil
    }
}

// MARK: - Header buttons (§10.2)

/// Sort, bookmark filter, close and the search clear button: 28 tall, r5, no fill at rest,
/// textPrimary. A toggled button (bookmark filter on) is accentTint with an accentText glyph.
final class QueueHeaderButton: QueueControlButton {
    var symbolName: String? { didSet { needsDisplay = true } }
    var symbolPointSize: CGFloat = 15 { didSet { needsDisplay = true } }
    var symbolWeight: NSFont.Weight = .regular { didSet { needsDisplay = true } }
    /// The expanded sort button's label, drawn before the chevron. nil for an icon-only button.
    var label: String? { didSet { needsDisplay = true } }
    var isToggledOn = false { didSet { needsDisplay = true } }
    /// A fill under the button (the search clear button covers the text behind it).
    var backdrop: NSColor? { didSet { needsDisplay = true } }
    var glyphColor: NSColor? { didSet { needsDisplay = true } }

    static let labelFont = NSFont.systemFont(ofSize: 10.5, weight: .regular)

    static func labelWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: labelFont]).width)
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = DWBAppearance.shared
        let radius = DWBMetrics.queueHeaderButtonRadius
        let shape = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        if let backdrop { backdrop.setFill(); shape.fill() }
        if isToggledOn { appearance.accentTint.setFill(); shape.fill() }
        if isEnabled {
            if isPressing { DWBColor.overlayPressed.setFill(); shape.fill() }
            else if isHovering { DWBColor.overlayHover.setFill(); shape.fill() }
        }
        let color = glyphColor ?? (isToggledOn ? PlayerTheme.current.accentText : DWBColor.textPrimary)

        if let label {
            // 4 + label + 6 + chevron 10 + 4
            let chevronRect = NSRect(x: bounds.maxX - 4 - QueueHeaderLayout.sortChevronSize, y: 0,
                                     width: QueueHeaderLayout.sortChevronSize, height: bounds.height)
            QueueSymbol.draw(QueueSymbol.image("chevron.down", pointSize: QueueHeaderLayout.sortChevronSize,
                                               weight: .medium, color: color), centeredIn: chevronRect)
            let textRect = NSRect(x: 4, y: 0, width: max(0, chevronRect.minX - 6 - 4), height: bounds.height)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: color,
                                                             .paragraphStyle: paragraph]
            let height = ceil(Self.labelFont.ascender - Self.labelFont.descender)
            (label as NSString).draw(in: NSRect(x: textRect.minX, y: floor((bounds.height - height) / 2),
                                                width: textRect.width, height: height), withAttributes: attributes)
        } else if let symbolName {
            QueueSymbol.draw(QueueSymbol.image(symbolName, pointSize: symbolPointSize, weight: symbolWeight, color: color),
                             centeredIn: bounds)
        }
        drawFocusRing(in: bounds, radius: radius)
    }
}

// MARK: - Search field (§10.2)

/// An `NSSearchField` with no system search or cancel glyph: the Queue Page draws its own magnifier
/// and clear button. Reports focus so the container can draw the focus edge and ring.
final class QueueSearchField: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }
}

final class QueueSearchFieldCell: NSSearchFieldCell {
    override init(textCell string: String) {
        super.init(textCell: string)
        // NSCell.init(textCell:) creates a non-editable label cell; restore editability.
        isEditable = true
        usesSingleLineMode = true
        isScrollable = true
        lineBreakMode = .byClipping
    }

    required init(coder: NSCoder) { fatalError() }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect { .zero }
    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect { .zero }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        return NSRect(x: rect.minX, y: rect.minY + floor((rect.height - textHeight) / 2),
                      width: rect.width, height: textHeight)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { searchTextRect(forBounds: rect) }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
}

/// The 28 pt, r6 search field: surfaceElevated, no border; focused it gets a 1 pt accentFill edge and
/// a 1 pt accentFill outer ring (3 pt in all under Increase Contrast, in accentText). The view is
/// `outset` larger than the field on every side so the outer ring has room.
final class QueueSearchFieldView: NSView {
    static let outset: CGFloat = 2
    private static let magnifierInset: CGFloat = 7
    private static let magnifierSize: CGFloat = 12
    private static let textGap: CGFloat = 6
    private static let textHeight: CGFloat = 20

    let searchField = QueueSearchField()
    let clearButton = QueueHeaderButton(frame: .zero)

    private(set) var isFocused = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        searchField.cell = QueueSearchFieldCell(textCell: "")
        searchField.isEditable = true
        searchField.font = .systemFont(ofSize: 11)
        searchField.textColor = DWBColor.textPrimary
        searchField.backgroundColor = .clear
        searchField.drawsBackground = false
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.onFocusChange = { [weak self] focused in self?.isFocused = focused }
        addSubview(searchField)

        clearButton.symbolName = "xmark"
        clearButton.symbolPointSize = 10
        clearButton.symbolWeight = .medium
        clearButton.backdrop = DWBColor.surfaceElevated
        clearButton.isHidden = true
        addSubview(clearButton)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() {
        clearButton.glyphColor = DWBAppearance.shared.textSecondary
        needsDisplay = true
    }

    /// The field proper (28 tall), inside the outset.
    var fieldRect: NSRect { bounds.insetBy(dx: Self.outset, dy: Self.outset) }

    func setFocused(_ focused: Bool) { isFocused = focused }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if fieldRect.contains(convert(event.locationInWindow, from: nil)) {
            window?.makeFirstResponder(searchField)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func layout() {
        super.layout()
        let field = fieldRect
        let clearWidth: CGFloat = 20, clearHeight: CGFloat = 22
        let textX = field.minX + Self.magnifierInset + Self.magnifierSize + Self.textGap
        let textRight = clearButton.isHidden ? field.maxX - 4 : field.maxX - 2 - clearWidth
        searchField.frame = NSRect(x: textX, y: field.midY - Self.textHeight / 2,
                                   width: max(0, textRight - textX), height: Self.textHeight)
        clearButton.frame = NSRect(x: field.maxX - 2 - clearWidth, y: field.midY - clearHeight / 2,
                                   width: clearWidth, height: clearHeight)
        clearButton.glyphColor = DWBAppearance.shared.textSecondary
    }

    override func draw(_ dirtyRect: NSRect) {
        let field = fieldRect
        let radius = DWBMetrics.queueSearchRadius
        DWBColor.surfaceElevated.setFill()
        NSBezierPath(roundedRect: field, xRadius: radius, yRadius: radius).fill()

        let magnifier = NSRect(x: field.minX + Self.magnifierInset, y: field.minY,
                               width: Self.magnifierSize, height: field.height)
        let image = QueueSymbol.image("magnifyingglass", pointSize: Self.magnifierSize, weight: .regular,
                                      color: DWBAppearance.shared.textTertiary)
        QueueSymbol.draw(image, centeredIn: magnifier)

        guard isFocused else { return }
        let appearance = DWBAppearance.shared
        let line = appearance.increaseContrast ? DWBMetrics.focusWidthIC / 2 : DWBMetrics.focusWidth / 2
        appearance.focusRingColor.setStroke()
        let edge = NSBezierPath(roundedRect: field.insetBy(dx: line / 2, dy: line / 2),
                                xRadius: radius - line / 2, yRadius: radius - line / 2)
        edge.lineWidth = line
        edge.stroke()
        let ring = NSBezierPath(roundedRect: field.insetBy(dx: -line / 2, dy: -line / 2),
                                xRadius: radius + line / 2, yRadius: radius + line / 2)
        ring.lineWidth = line
        ring.stroke()
    }
}

// MARK: - Footer sections (§10.5)

/// One footer section. The whole section is the button; its icon or label is centered and never
/// moves. Hover and press are textPrimary overlays over the full section; state is a mark in the
/// top-right corner, never a fill, outline or underline.
final class QueueFooterCellButton: QueueControlButton {
    var symbolName: String? { didSet { needsDisplay = true } }
    var symbolColor: NSColor = DWBColor.textPrimary { didSet { needsDisplay = true } }
    var labelText = "" { didSet { needsDisplay = true } }
    var labelFont: NSFont = .systemFont(ofSize: 10.5, weight: .regular) { didSet { needsDisplay = true } }
    var labelColor: NSColor = DWBColor.textPrimary { didSet { needsDisplay = true } }
    /// False for the compact status cells, which show only the icon.
    var showsLabel = true { didSet { needsDisplay = true } }
    var mark: QueueMarkerState.Mark = .none { didSet { needsDisplay = true } }
    var isCompact = false { didSet { needsDisplay = true } }

    /// The marker label font: 11 medium, tabular digits.
    static let markerFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    var textHeight: CGFloat { ceil(labelFont.ascender - labelFont.descender) }

    /// Where the label and the state mark land in this section, for the draw and for tests.
    func contentRects() -> (icon: NSRect?, label: NSRect?, mark: NSRect?) {
        let labelWidth = (labelText as NSString).size(withAttributes: [.font: labelFont]).width
        var icon: NSRect?
        var label: NSRect?
        let hasLabel = showsLabel && !labelText.isEmpty
        if symbolName != nil, hasLabel {
            let rects = QueueFooterCellGeometry.iconLabelRects(inBounds: bounds, iconSize: DWBMetrics.queueCellIcon,
                                                               labelWidth: labelWidth, labelHeight: textHeight,
                                                               isCompact: isCompact)
            icon = rects.icon
            label = rects.label
        } else if symbolName != nil {
            let size = DWBMetrics.queueCellIcon
            icon = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        } else if hasLabel {
            label = QueueFooterCellGeometry.labelRect(inBounds: bounds, textWidth: labelWidth,
                                                      textHeight: textHeight, isCompact: isCompact)
        }
        let markRect = mark == .none ? nil : QueueFooterCellGeometry.markRect(inBounds: bounds)
        return (icon, label, markRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, let overlay = Self.cellOverlay(hovering: isHovering, pressing: isPressing) {
            overlay.setFill()
            bounds.fill()
        }
        let rects = contentRects()
        if let icon = rects.icon, let symbolName {
            QueueSymbol.draw(QueueSymbol.image(symbolName, pointSize: DWBMetrics.queueCellIcon, weight: .regular,
                                               color: symbolColor), centeredIn: icon)
        }
        if let label = rects.label {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = .center
            (labelText as NSString).draw(in: label, withAttributes: [.font: labelFont, .foregroundColor: labelColor,
                                                                      .paragraphStyle: paragraph])
        }
        if let markRect = rects.mark {
            labelColor.setFill()
            labelColor.setStroke()
            switch mark {
            case .applied:
                NSBezierPath(ovalIn: markRect).fill()
            case .mixed:
                let ring = NSBezierPath(ovalIn: markRect.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            case .none:
                break
            }
        }
        drawFocusRing(in: bounds.insetBy(dx: 3, dy: 3), radius: 0)
    }
}

// MARK: - Empty-state buttons (§10.6)

/// "Add Media" (an outlined accent pill) and the filtered states' one button.
final class QueueEmptyActionButton: QueueControlButton {
    enum Style { case outlinePill, filteredAction }

    private let style: Style

    var labelText = "" { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private var labelFont: NSFont {
        switch style {
        case .outlinePill: return .systemFont(ofSize: 12, weight: .semibold)
        case .filteredAction: return .systemFont(ofSize: 11, weight: .regular)
        }
    }

    private var cornerRadius: CGFloat {
        style == .outlinePill ? DWBMetrics.radiusPill : DWBMetrics.queueEmptyButtonRadius
    }

    private var textColor: NSColor {
        style == .outlinePill ? PlayerTheme.current.accentText : DWBColor.textPrimary
    }

    /// The pill is 26 tall; the filtered button is its text line plus 7 above and below.
    func preferredSize() -> NSSize {
        let textWidth = ceil((labelText as NSString).size(withAttributes: [.font: labelFont]).width)
        switch style {
        case .outlinePill:
            return NSSize(width: max(96, textWidth + 24), height: DWBMetrics.queueEmptyPill)
        case .filteredAction:
            return NSSize(width: textWidth + 24, height: ceil(labelFont.ascender - labelFont.descender) + 14)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = DWBAppearance.shared
        let edgeColor = style == .outlinePill ? DWBColor.borderStrong : appearance.border
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5)
        if style == .filteredAction {
            DWBColor.surfaceElevated.setFill()
            path.fill()
        }
        if isEnabled {
            if isPressing { DWBColor.overlayPressed.setFill(); path.fill() }
            else if isHovering { DWBColor.overlayHover.setFill(); path.fill() }
        }
        edgeColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let height = ceil(labelFont.ascender - labelFont.descender)
        (labelText as NSString).draw(in: NSRect(x: 8, y: floor((bounds.height - height) / 2),
                                                width: max(0, bounds.width - 16), height: height),
                                     withAttributes: [.font: labelFont, .foregroundColor: textColor,
                                                      .paragraphStyle: paragraph])
        drawFocusRing(in: bounds, radius: cornerRadius)
    }
}
