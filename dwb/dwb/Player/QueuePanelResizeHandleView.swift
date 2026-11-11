import AppKit

/// Invisible 8 pt grab zone centered on the edge the video area shares with the Queue Page.
/// A sibling of `queuePage` in the content view, directly above it. It draws nothing; the
/// panel's own 1 pt divider stays the only visible edge.
///
/// It handles its own mouse events and never calls `super`, so a press here never reaches
/// the video surface (no fullscreen double-click), the queue table (no row selection or
/// reorder), or the window background (no window move in Complete Video Window mode).
final class QueuePanelResizeHandleView: NSView {
    /// Called on every drag event with the proposed edge x, in the superview's coordinates.
    var onDrag: ((CGFloat) -> Void)?
    /// Called once when a drag that moved the edge ends.
    var onDragEnd: (() -> Void)?
    /// Called on a double-click.
    var onReset: (() -> Void)?

    private var isTracking = false
    private var didDrag = false
    /// Pointer offset from the edge at mouse-down, so the edge does not jump to the pointer.
    private var grabOffset: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

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
        if didDrag {
            didDrag = false
            onDragEnd?()
        }
    }
}
