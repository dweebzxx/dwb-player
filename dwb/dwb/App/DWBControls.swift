import AppKit

// Custom-drawn controls for Settings, the confirm sheet and the Debug Console, built from
// `tokens-and-specs.md` section 5. Each reads its colors from `DWBColor` and the shared
// `DWBAppearance`, so Increase Contrast updates them live.

// MARK: - Push button

/// Layer-drawn push button: 28 pt tall (24 small), radius 6, one fill and one 1 pt edge.
final class DWBButton: NSButton {
    enum Variant {
        case primary, secondary, neutral, plain, destructive, destructivePlain
    }

    enum Size {
        case regular, small
        var height: CGFloat { self == .small ? 24 : 28 }
        var horizontalPadding: CGFloat { self == .small ? 10 : 14 }
        var fontSize: CGFloat { self == .small ? 11 : 13 }
    }

    var variant: Variant { didSet { restyle() } }
    let size: Size
    private var isHovering = false
    private var isPressing = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String, variant: Variant = .secondary, size: Size = .regular) {
        self.variant = variant
        self.size = size
        super.init(frame: .zero)
        self.title = title
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.radiusControl
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { restyle() }

    override var title: String {
        didSet { restyle() }
    }

    override var isEnabled: Bool {
        didSet { restyle() }
    }

    override var intrinsicContentSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: variant)]
        let width = ceil((title as NSString).size(withAttributes: attributes).width) + size.horizontalPadding * 2
        return NSSize(width: max(width, 40), height: size.height)
    }

    private func font(for variant: Variant) -> NSFont {
        let emphasized = variant == .primary || variant == .destructive
        return .systemFont(ofSize: size.fontSize, weight: emphasized ? .semibold : .medium)
    }

    private struct Colors {
        var fill: NSColor
        var label: NSColor
        var edge: NSColor
    }

    private func colors() -> Colors {
        let theme = PlayerTheme.current
        let appearance = DWBAppearance.shared
        let clear = NSColor.clear
        switch variant {
        case .primary:
            return Colors(fill: theme.accentSolid, label: DWBColor.textOnFill, edge: theme.accentSolid)
        case .secondary:
            return Colors(fill: clear, label: theme.accentText, edge: DWBColor.borderStrong)
        case .neutral:
            return Colors(fill: DWBColor.overlaySelected, label: DWBColor.textPrimary, edge: appearance.border)
        case .plain:
            return Colors(fill: clear, label: theme.accentText, edge: clear)
        case .destructive:
            return Colors(fill: DWBColor.errorText, label: DWBColor.textOnFill, edge: DWBColor.errorText)
        case .destructivePlain:
            return Colors(fill: clear, label: DWBColor.errorText, edge: clear)
        }
    }

    func restyle() {
        let c = colors()
        var fill = c.fill
        if isEnabled && (isPressing || isHovering) {
            switch variant {
            case .primary, .destructive:
                // Solid fills brighten on hover and darken while pressed.
                fill = (isPressing ? c.fill.blended(withFraction: 0.12, of: .black)
                                   : c.fill.blended(withFraction: 0.08, of: .white)) ?? c.fill
            case .neutral:
                fill = DWBColor.overlayPressed
            case .secondary, .plain, .destructivePlain:
                fill = isPressing ? DWBColor.overlayPressed : DWBColor.overlayHover
            }
        }
        layer?.backgroundColor = fill.cgColor
        let focused = window?.firstResponder === self
        if focused {
            layer?.borderColor = DWBAppearance.shared.focusRingColor.cgColor
            layer?.borderWidth = DWBAppearance.shared.focusRingWidth
        } else {
            layer?.borderColor = c.edge.cgColor
            layer?.borderWidth = c.edge.alphaComponent > 0 ? 1 : 0
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font(for: variant),
            .foregroundColor: c.label,
            .paragraphStyle: Self.centered
        ])
        alphaValue = isEnabled ? 1.0 : DWBMetrics.disabledAlpha
        invalidateIntrinsicContentSize()
    }

    private static let centered: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byClipping
        return p
    }()

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; restyle() }
    override func mouseExited(with event: NSEvent) { isHovering = false; restyle() }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressing = true
        restyle()
        super.mouseDown(with: event)
        isPressing = false
        restyle()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        restyle()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        restyle()
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restyle()
    }
}

// MARK: - Pop-up button

/// Pop-up drawn as a 24 pt, radius 6 `surfaceElevated` pill with a 1 pt border and a
/// chevron glyph. The menu itself is the system menu.
final class DWBPopUpButton: NSPopUpButton {
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    private let fixedWidth: CGFloat

    init(width: CGFloat = 200) {
        fixedWidth = width
        super.init(frame: .zero, pullsDown: false)
        cell = DWBPopUpButtonCell(textCell: "", pullsDown: false)
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        widthAnchor.constraint(equalToConstant: width).isActive = true
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    var isHoveringControl: Bool { isHovering }

    override var intrinsicContentSize: NSSize { NSSize(width: fixedWidth, height: 24) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovering = false; needsDisplay = true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        needsDisplay = true
        return resigned
    }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : DWBMetrics.disabledAlpha }
    }
}

private final class DWBPopUpButtonCell: NSPopUpButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let appearance = DWBAppearance.shared
        let popUp = controlView as? DWBPopUpButton
        let focused = controlView.window?.firstResponder === controlView
        let rect = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        if popUp?.isHoveringControl == true {
            DWBColor.overlayHover.setFill()
            path.fill()
        }
        let edge = focused ? appearance.focusRingColor : appearance.border
        edge.setStroke()
        path.lineWidth = focused ? appearance.focusRingWidth : 1
        path.stroke()

        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let chevron = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronConfig)?.tinted(with: appearance.textSecondary) {
            let size = chevron.size
            chevron.draw(in: NSRect(x: cellFrame.maxX - 6 - size.width,
                                    y: cellFrame.midY - size.height / 2,
                                    width: size.width, height: size.height))
        }

        let title = selectedItem?.title ?? ""
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: DWBColor.textPrimary,
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil(NSFont.systemFont(ofSize: 13).boundingRectForFont.height)
        let textRect = NSRect(x: cellFrame.minX + 10,
                              y: cellFrame.midY - textHeight / 2,
                              width: max(0, cellFrame.width - 10 - 6 - 11 - 6),
                              height: textHeight)
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {}
}

// MARK: - Text field

/// Text or number field: `surfaceSunken`, 1 pt `borderStrong` edge, radius 5, 22 pt tall.
final class DWBTextField: NSTextField {
    var usesMonospacedFont = false {
        didSet { font = usesMonospacedFont ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = DWBTextFieldCell(textCell: "")
        isEditable = true
        isSelectable = true
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 12)
        textColor = DWBColor.textPrimary
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
        applyChrome()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { applyChrome() }

    private var isEditing: Bool { currentEditor() != nil }

    func applyChrome() {
        layer?.backgroundColor = DWBColor.surfaceSunken.cgColor
        let appearance = DWBAppearance.shared
        layer?.borderColor = (isEditing ? appearance.focusRingColor : DWBColor.borderStrong).cgColor
        layer?.borderWidth = isEditing ? appearance.focusRingWidth : 1
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = DWBColor.textPrimary
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        applyChrome()
        return accepted
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        applyChrome()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        applyChrome()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
    }
}

private final class DWBTextFieldCell: NSTextFieldCell {
    private let horizontalInset: CGFloat = 7

    override init(textCell string: String) {
        super.init(textCell: string)
        isEditable = true
        isScrollable = true
        usesSingleLineMode = true
        lineBreakMode = .byClipping
    }

    required init(coder: NSCoder) { fatalError() }

    private func insetRect(_ rect: NSRect) -> NSRect {
        let textFont = font ?? .systemFont(ofSize: 12)
        let textHeight = ceil(textFont.boundingRectForFont.height)
        return NSRect(x: rect.minX + horizontalInset,
                      y: rect.minY + floor((rect.height - textHeight) / 2),
                      width: max(0, rect.width - horizontalInset * 2),
                      height: textHeight)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { insetRect(rect) }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: insetRect(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: insetRect(rect), in: controlView, editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }
}

// MARK: - Segmented control

/// Custom-drawn segmented control: selected segment is `accentSolid` with a `textOnFill`
/// label, because the system's white-on-accent label fails 4.5:1.
final class DWBSegmentedControl: NSControl {
    var segments: [String] = [] {
        didSet { needsDisplay = true; invalidateIntrinsicContentSize() }
    }
    var selectedSegment = 0 {
        didSet { needsDisplay = true }
    }
    private var hoveredSegment: Int?
    private var trackingAreaReference: NSTrackingArea?
    private let segmentHeight: CGFloat = 20

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.radioGroup)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    private func segmentWidth(_ index: Int) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        return ceil((segments[index] as NSString).size(withAttributes: [.font: font]).width) + 18
    }

    override var intrinsicContentSize: NSSize {
        let inner = segments.indices.reduce(CGFloat(0)) { $0 + segmentWidth($1) } + CGFloat(max(0, segments.count - 1)) * 2
        return NSSize(width: inner + 6, height: segmentHeight + 6)
    }

    private func segmentRect(_ index: Int) -> NSRect {
        var x: CGFloat = 3
        for i in 0..<index { x += segmentWidth(i) + 2 }
        return NSRect(x: x, y: 3, width: segmentWidth(index), height: segmentHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        DWBColor.surfaceElevated.setFill()
        outer.fill()
        DWBAppearance.shared.border.setStroke()
        outer.lineWidth = 1
        outer.stroke()
        for index in segments.indices {
            let rect = segmentRect(index)
            let selected = index == selectedSegment
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            if selected {
                PlayerTheme.current.accentSolid.setFill()
                path.fill()
            } else if hoveredSegment == index {
                DWBColor.overlayHover.setFill()
                path.fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular),
                .foregroundColor: selected ? DWBColor.textOnFill : DWBColor.textPrimary
            ]
            let size = (segments[index] as NSString).size(withAttributes: attributes)
            (segments[index] as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2,
                                                           y: rect.midY - size.height / 2),
                                               withAttributes: attributes)
        }
        if window?.firstResponder === self {
            let appearance = DWBAppearance.shared
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8)
            appearance.focusRingColor.setStroke()
            ring.lineWidth = appearance.focusRingWidth
            ring.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    private func segment(at point: NSPoint) -> Int? {
        segments.indices.first { segmentRect($0).insetBy(dx: -1, dy: -3).contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let hit = segment(at: convert(event.locationInWindow, from: nil))
        if hit != hoveredSegment { hoveredSegment = hit; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hoveredSegment = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let hit = segment(at: convert(event.locationInWindow, from: nil)) else { return }
        selectedSegment = hit
        sendAction(action, to: target)
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123 where selectedSegment > 0:
            selectedSegment -= 1
            sendAction(action, to: target)
        case 124 where selectedSegment < segments.count - 1:
            selectedSegment += 1
            sendAction(action, to: target)
        default:
            super.keyDown(with: event)
        }
    }
}
