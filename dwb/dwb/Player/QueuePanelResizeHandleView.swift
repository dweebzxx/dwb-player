import AppKit

/// 8 pt grab zone centered on the edge the video area shares with the Queue Page. A sibling of
/// `queuePage` in the content view, directly above it. At rest it draws nothing and the panel's own
/// 1 pt edge stays the only visible line; on hover, drag or keyboard focus a 2 pt `accentText` line
/// at 0.7 opacity fades in (§10.1).
///
/// It handles its own mouse events and never calls `super`, so a press here never reaches
/// the video surface (no fullscreen double-click), the queue table (no row selection or
/// reorder), or the window background (no window move in Complete Video Window mode).
///
/// For the keyboard and VoiceOver it is a splitter: Left widens the panel and Right narrows it by
/// 10 pt, Home resets. All three go through the same clamp and reset the drag uses.
final class QueuePanelResizeHandleView: NSView {
    /// Called on every drag event with the proposed edge x, in the superview's coordinates.
    var onDrag: ((CGFloat) -> Void)?
    /// Called once when a drag that moved the edge ends.
    var onDragEnd: (() -> Void)?
    /// Called on a double-click, and for Home.
    var onReset: (() -> Void)?
    /// Called for a keyboard resize: positive widens the panel, negative narrows it.
    var onNudge: ((CGFloat) -> Void)?
    /// The panel's current width, for VoiceOver's value. Read when asked.
    var currentWidthProvider: (() -> CGFloat)?

    private var isTracking = false
    private var didDrag = false
    private var isHovering = false
    private var isDragging = false
    private var hasKeyboardFocus = false
    /// Pointer offset from the edge at mouse-down, so the edge does not jump to the pointer.
    private var grabOffset: CGFloat = 0
    private var trackingAreaReference: NSTrackingArea?
    private let indicatorLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        indicatorLayer.opacity = 0
        layer?.addSublayer(indicatorLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Queue width")
        setAccessibilityHelp("Drag to resize; double-click to reset.")
        setAccessibilityIdentifier("queue.divider")
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { refreshIndicator(animated: false) }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func layout() {
        super.layout()
        // 2 pt wide, centered on the shared edge, the full height.
        let width = DWBMetrics.queueDividerLine
        indicatorLayer.frame = NSRect(x: floor(bounds.midX - width / 2), y: 0, width: width, height: bounds.height)
    }

    // MARK: Indicator

    private func refreshIndicator(animated: Bool) {
        let visible = isHovering || isDragging || hasKeyboardFocus
        indicatorLayer.backgroundColor = PlayerTheme.current.accentText.cgColor
        let target = visible ? Float(DWBMetrics.queueDividerLineAlpha) : 0
        let duration = animated ? DWBAppearance.shared.duration(DWBMotion.hover) : 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        if duration == 0 { CATransaction.setDisableActions(true) }
        indicatorLayer.opacity = target
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refreshIndicator(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshIndicator(animated: true)
    }

    override func viewDidHide() {
        super.viewDidHide()
        isHovering = false
        isDragging = false
        refreshIndicator(animated: false)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            isTracking = false
            didDrag = false
            onReset?()
            return
        }
        guard let container = superview else { return }
        let point = container.convert(event.locationInWindow, from: nil)
        grabOffset = point.x - frame.midX
        isTracking = true
        didDrag = false
        isDragging = true
        refreshIndicator(animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTracking, let container = superview else { return }
        let point = container.convert(event.locationInWindow, from: nil)
        didDrag = true
        NSCursor.resizeLeftRight.set()
        onDrag?(point.x - grabOffset)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTracking else { return }
        isTracking = false
        isDragging = false
        refreshIndicator(animated: true)
        if didDrag {
            didDrag = false
            onDragEnd?()
        }
    }

    // MARK: Keyboard and accessibility

    override func becomeFirstResponder() -> Bool {
        hasKeyboardFocus = true
        refreshIndicator(animated: true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        hasKeyboardFocus = false
        refreshIndicator(animated: true)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let step = DWBMetrics.queueDividerKeyStep
        switch event.keyCode {
        case 123: onNudge?(step)      // ← widens
        case 124: onNudge?(-step)     // → narrows
        case 115: onReset?()          // Home
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityValue() -> Any? {
        guard let width = currentWidthProvider?() else { return nil }
        return "\(Int(width.rounded())) points"
    }

    override func accessibilityPerformIncrement() -> Bool {
        onNudge?(DWBMetrics.queueDividerKeyStep)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        onNudge?(-DWBMetrics.queueDividerKeyStep)
        return true
    }
}
