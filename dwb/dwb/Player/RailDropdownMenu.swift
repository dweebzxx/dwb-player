import AppKit

/// The rail-only DropdownMenu. The DS permits an NSPanel for pop-ups.
/// A panel keeps keyboard input available with custom-drawn rows (NSMenu item
/// views do not receive keyboard events). No generic Popover chrome is used.
final class RailDropdownMenu: NSObject, NSWindowDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        var cancel: (() -> Void)?
        override func cancelOperation(_ sender: Any?) { cancel?() }
        override func accessibilityPerformCancel() -> Bool { cancel?(); return true }
    }

    // DropdownMenu.jsx: 220 wide, inset 5, r8; rows 24 high, r5.
    private enum Metrics {
        static let width: CGFloat = 220
        static let inset: CGFloat = 5
        static let rowHeight: CGFloat = 24
        static let radius: CGFloat = 8
        static let shadowMargin: CGFloat = 32
    }

    private let items: [RailOverflowModel.Item]
    private let panel = Panel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    private let surface = NSView()
    private var rows: [Row] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private weak var parent: NSWindow?
    private weak var previousResponder: NSResponder?
    private var isOpen = false
    var didChoose: ((RailOverflowModel.Action) -> Void)?
    var didClose: (() -> Void)?

    init(items: [RailOverflowModel.Item]) {
        self.items = items
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .popUpMenu
        panel.animationBehavior = .none // No motion, including Reduce Motion.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.cancel = { [weak self] in self?.dismiss() }
        panel.setAccessibilityLabel("More Actions")
        let height = Metrics.inset * 2 + CGFloat(items.count) * Metrics.rowHeight
        let margin = Metrics.shadowMargin
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.width + margin * 2, height: height + margin * 2))
        root.setAccessibilityElement(false)
        panel.contentView = root
        panel.setContentSize(root.frame.size)
        surface.frame = NSRect(x: margin, y: margin, width: Metrics.width, height: height)
        surface.wantsLayer = true
        surface.layer?.cornerRadius = Metrics.radius
        surface.layer?.masksToBounds = false
        surface.layer?.shadowPath = CGPath(roundedRect: surface.bounds, cornerWidth: Metrics.radius, cornerHeight: Metrics.radius, transform: nil)
        surface.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        surface.layer?.borderWidth = 1
        surface.layer?.borderColor = (PlayerAccessibilityEnvironment.increaseContrast ? DWBColor.borderStrong : DWBColor.border).cgColor
        surface.layer?.shadowColor = NSColor.black.cgColor
        surface.layer?.shadowOpacity = 0.5
        surface.layer?.shadowOffset = CGSize(width: 0, height: -12)
        surface.layer?.shadowRadius = 16 // CSS shadow blur 32, as with the existing HUD shadow.
        surface.setAccessibilityElement(true)
        surface.setAccessibilityRole(.menu)
        surface.setAccessibilityLabel("More Actions")
        root.addSubview(surface)
        for (index, item) in items.enumerated() {
            let row = Row(item: item)
            row.frame = NSRect(x: Metrics.inset, y: height - Metrics.inset - CGFloat(index + 1) * Metrics.rowHeight,
                               width: Metrics.width - 2 * Metrics.inset, height: Metrics.rowHeight)
            row.tag = index
            row.target = self
            row.action = #selector(chosen(_:))
            row.didHover = { [weak self, weak row] in
                guard let self, let row, row.isEnabled else { return }
                self.panel.makeFirstResponder(row)
            }
            surface.addSubview(row)
            rows.append(row)
        }
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        panel.orderOut(nil)
    }

    func show(above anchor: NSView) {
        guard let owner = anchor.window, let screen = owner.screen else { didClose?(); return }
        parent = owner
        previousResponder = owner.firstResponder
        let anchorRect = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        let size = surface.frame.size
        // DS menu offset 4, edge-aligned, above the bottom rail; clamp to the screen.
        let x = min(max(anchorRect.minX, visible.minX), visible.maxX - size.width)
        let y = min(max(anchorRect.maxY + 4, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x - Metrics.shadowMargin, y: y - Metrics.shadowMargin))
        isOpen = true
        owner.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(rows.first(where: \.isEnabled))
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak anchor] event in
            guard let self, self.isOpen else { return event }
            if event.type == .keyDown, event.window === self.panel {
                switch event.keyCode {
                case 125: self.moveSelection(by: 1); return nil
                case 126: self.moveSelection(by: -1); return nil
                case 36, 76, 49:
                    if let row = self.panel.firstResponder as? Row { self.chosen(row) }
                    return nil
                case 53: self.dismiss(); return nil
                case 48: self.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1); return nil
                default: break
                }
            } else if event.type != .keyDown {
                if let anchor, event.window === anchor.window,
                   anchor.convert(anchor.bounds, to: nil).contains(event.locationInWindow) {
                    self.dismiss()
                    return nil // A second anchor click closes without reopening.
                }
                if event.window !== self.panel || !self.surface.frame.contains(event.locationInWindow) {
                    self.dismiss(restoreFocus: false)
                }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismiss(restoreFocus: false)
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in self?.dismiss() })
        }
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: owner, queue: .main) { [weak self] _ in self?.dismiss(restoreFocus: false) })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss(restoreFocus: false) })
    }

    func dismiss(restoreFocus: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        let wasKey = panel.isKeyWindow
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if restoreFocus, wasKey, let parent, parent.isVisible {
            parent.makeKey()
            parent.makeFirstResponder(previousResponder)
        }
        didClose?()
    }

    func windowDidResignKey(_ notification: Notification) { dismiss(restoreFocus: false) }

    private func moveSelection(by delta: Int) {
        let enabled = rows.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        let current = enabled.firstIndex(where: { $0 === panel.firstResponder }) ?? (delta > 0 ? -1 : 0)
        panel.makeFirstResponder(enabled[(current + delta + enabled.count) % enabled.count])
    }

    @objc private func chosen(_ sender: Row) {
        guard isOpen, sender.isEnabled else { return }
        let action = items[sender.tag].action
        dismiss()
        didChoose?(action)
    }

    /// NSButton retains native mouse tracking and accessibility Press dispatch.
    /// Its semantic menu-item state is separate from the custom visual checkmark.
    private final class Row: NSButton {
        private let item: RailOverflowModel.Item
        private var tracking: NSTrackingArea?
        var didHover: (() -> Void)?
        init(item: RailOverflowModel.Item) {
            self.item = item
            super.init(frame: .zero)
            title = item.title
            isEnabled = item.isEnabled
            state = item.isOn ? .on : .off
            isBordered = false
            focusRingType = .none
            setAccessibilityRole(.menuItem)
            setAccessibilityLabel(item.title)
            setAccessibilityValue(item.isOn ? "on" : "off")
            setAccessibilityEnabled(item.isEnabled)
        }
        required init?(coder: NSCoder) { fatalError("programmatic only") }
        override var acceptsFirstResponder: Bool { isEnabled }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            superview?.subviews.forEach { $0.needsDisplay = true }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            needsDisplay = true
            return result
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
            tracking = area
            addTrackingArea(area)
        }
        override func mouseEntered(with event: NSEvent) { didHover?() }
        override func draw(_ dirtyRect: NSRect) {
            let selected = isEnabled && window?.firstResponder === self
            if selected {
                PlayerTheme.current.accentTintStrong.setFill()
                let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
                path.fill()
                PlayerTheme.current.accentFill.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            let color = isEnabled ? DWBColor.textPrimary : DWBColor.textDisabled
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color]
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            var textAttributes = attributes
            textAttributes[.paragraphStyle] = paragraph
            let height = (item.title as NSString).size(withAttributes: attributes).height
            (item.title as NSString).draw(in: NSRect(x: 26, y: (bounds.height - height) / 2, width: bounds.width - 26 - 8, height: height), withAttributes: textAttributes)
            if item.isOn, let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
                let tinted = NSImage(size: image.size)
                tinted.lockFocus()
                PlayerTheme.current.accentText.setFill()
                NSRect(origin: .zero, size: image.size).fill()
                image.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
                tinted.unlockFocus()
                tinted.draw(in: NSRect(x: 6 + (14 - image.size.width) / 2, y: (bounds.height - image.size.height) / 2, width: image.size.width, height: image.size.height))
            }
        }
    }
}
