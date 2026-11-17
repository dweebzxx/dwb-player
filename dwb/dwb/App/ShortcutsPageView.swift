import AppKit

// Settings > Shortcuts, from the design system's `ShortcutsPage`: a keyboard map, a search
// field with Restore Defaults…, and rows grouped by task. The rows come from the command table
// (`ShortcutCommands.swift`) and the filter lives in `ShortcutsModel.swift`; this file draws
// them and opens the editor sheet (`ShortcutEditorSheet.swift`) for an editable key.

private func shortcutToneColor(_ tone: ShortcutTone) -> NSColor {
    switch tone {
    case .accent:          return PlayerTheme.current.accentFill
    case .markerPrimary:   return PlayerTheme.current.markerPrimary
    case .markerSecondary: return PlayerTheme.current.markerSecondary
    }
}

// MARK: - Keyboard map

/// A decorative map of the keyboard: 26 × 24 pt keys, a space bar and the arrow keys.
/// Keys with a shortcut are bordered; hovering a row lights its keys with a solid fill.
final class ShortcutKeyboardMapView: NSView {
    static let keyWidth = ShortcutKeyboardLayout.keyWidth
    static let keyHeight = ShortcutKeyboardLayout.keyHeight
    static let spaceWidth = ShortcutKeyboardLayout.spaceWidth
    private static let keyGap: CGFloat = 4
    private static let padding: CGFloat = 12

    var tones: [String: ShortcutTone] = [:] { didSet { needsDisplay = true } }
    var hotKeys: Set<String> = [] { didSet { needsDisplay = true } }
    var hotTone: ShortcutTone = .accent { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Decorative: the same information is in the rows below.
        setAccessibilityElement(false)
        translatesAutoresizingMaskIntoConstraints = false
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    override var intrinsicContentSize: NSSize {
        let letterRows = ShortcutKeyboardLayout.rows
        var widestLetterRow: CGFloat = 0
        for (index, row) in letterRows.enumerated() {
            let count = CGFloat(row.count)
            let rowWidth: CGFloat = ShortcutKeyboardLayout.rowIndent(index)
                + count * Self.keyWidth
                + (count - 1) * Self.keyGap
            widestLetterRow = max(widestLetterRow, rowWidth)
        }
        let arrowsWidth: CGFloat = 4 * Self.keyWidth + 3 * Self.keyGap
        let bottomRowWidth: CGFloat = bottomRowIndent + Self.spaceWidth + 20 + arrowsWidth
        let rowCount = CGFloat(letterRows.count + 1)
        let height: CGFloat = rowCount * Self.keyHeight + (rowCount - 1) * Self.keyGap + Self.padding * 2
        return NSSize(width: max(widestLetterRow, bottomRowWidth) + Self.padding * 2, height: height)
    }

    private var bottomRowIndent: CGFloat { 66 }

    override func draw(_ dirtyRect: NSRect) {
        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: DWBMetrics.radiusCard, yRadius: DWBMetrics.radiusCard)
        DWBColor.canvas.setFill()
        panel.fill()
        DWBAppearance.shared.border.setStroke()
        panel.lineWidth = 1
        panel.stroke()

        var y = Self.padding
        for (index, row) in ShortcutKeyboardLayout.rows.enumerated() {
            var x = Self.padding + ShortcutKeyboardLayout.rowIndent(index)
            for key in row {
                drawKey(key, in: NSRect(x: x, y: y, width: Self.keyWidth, height: Self.keyHeight))
                x += Self.keyWidth + Self.keyGap
            }
            y += Self.keyHeight + Self.keyGap
        }
        var x = Self.padding + bottomRowIndent
        drawKey(ShortcutKeyboardLayout.space, in: NSRect(x: x, y: y, width: Self.spaceWidth, height: Self.keyHeight))
        x += Self.spaceWidth + 20
        for key in ShortcutKeyboardLayout.arrows {
            drawKey(key, in: NSRect(x: x, y: y, width: Self.keyWidth, height: Self.keyHeight))
            x += Self.keyWidth + Self.keyGap
        }
    }

    private func drawKey(_ key: String, in rect: NSRect) {
        let tone = tones[key]
        let isHot = hotKeys.contains(key)
        let isMarker = tone == .markerPrimary || tone == .markerSecondary
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusKey, yRadius: DWBMetrics.radiusKey)
        let textColor: NSColor
        if let tone {
            let toneColor = shortcutToneColor(tone)
            if isHot {
                (isMarker ? toneColor : PlayerTheme.current.accentSolid).setFill()
                textColor = DWBColor.textOnFill
            } else {
                DWBColor.overlaySelected.setFill()
                textColor = isMarker ? toneColor : DWBColor.textPrimary
            }
            path.fill()
            toneColor.setStroke()
        } else {
            DWBColor.gridLine.setStroke()
            textColor = DWBColor.textDisabled
        }
        path.lineWidth = 1
        path.stroke()

        let label = key == ShortcutKeyboardLayout.space ? "" : key
        guard !label.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: textColor
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                 withAttributes: attributes)
    }
}

// MARK: - Key cap

/// A key as a cap. With `onPress` it is a button that opens the editor: it takes keyboard
/// focus, answers Return and Space, and draws a focus ring. Without it, it only shows the key.
final class ShortcutKeyCapView: NSView {
    enum Style { case key, add, unassigned }

    private let text: String
    private let tone: ShortcutTone
    private let style: Style
    var onPress: (() -> Void)?
    /// Called when focus enters or leaves the cap, so the row can light its keys.
    var onFocusChange: ((Bool) -> Void)?
    private var isHovering = false { didSet { needsDisplay = true } }
    private var isFocused = false { didSet { needsDisplay = true } }
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }

    init(text: String, tone: ShortcutTone, style: Style = .key) {
        self.text = text
        self.tone = tone
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    private static let wordFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    private var font: NSFont { style == .unassigned ? Self.wordFont : Self.font }

    override var intrinsicContentSize: NSSize {
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return NSSize(width: max(22, width + 12), height: 20)
    }

    /// Makes the cap a button with an accessibility label and help.
    func makeInteractive(label: String, help: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityHelp(help)
    }

    override var acceptsFirstResponder: Bool { onPress != nil }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            isFocused = true
            scrollToVisible(bounds.insetBy(dx: -8, dy: -8))
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        onFocusChange?(false)
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if onPress != nil, event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 {
            onPress?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard onPress != nil else { super.mouseDown(with: event); return }
        window?.makeFirstResponder(self)
    }

    override func mouseUp(with event: NSEvent) {
        guard onPress != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseUp(with: event)
            return
        }
        onPress?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        guard onPress != nil else { return }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = DWBAppearance.shared
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusKey, yRadius: DWBMetrics.radiusKey)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        if isHovering && onPress != nil {
            DWBColor.overlayHover.setFill()
            path.fill()
        }
        let edge: NSColor
        let label: NSColor
        switch style {
        case .key:
            edge = tone == .accent ? DWBColor.borderStrong : shortcutToneColor(tone)
            label = tone == .accent ? DWBColor.textPrimary : shortcutToneColor(tone)
        case .add:
            edge = appearance.border
            label = DWBColor.textSecondary
        case .unassigned:
            edge = DWBColor.borderStrong
            label = appearance.textTertiary
            path.setLineDash([3, 2], count: 2, phase: 0)
        }
        edge.setStroke()
        path.lineWidth = 1
        path.stroke()
        if isFocused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -1, dy: -1),
                                    xRadius: DWBMetrics.radiusKey + 1, yRadius: DWBMetrics.radiusKey + 1)
            appearance.focusRingColor.setStroke()
            ring.lineWidth = appearance.focusRingWidth
            ring.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: label]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                                withAttributes: attributes)
    }
}

// MARK: - Row

final class ShortcutRowView: NSView {
    let entry: ShortcutEntry
    /// Called with the entry while the pointer is on the row or focus is in it, and with nil
    /// when neither is.
    var onHighlightChanged: ((ShortcutEntry?) -> Void)?
    /// Called to open the editor: the index of the key to replace, or nil to add a key.
    var onEdit: ((ShortcutEntry, Int?) -> Void)?

    private var isHovering = false { didSet { needsDisplay = true } }
    private var isFocused = false { didSet { needsDisplay = true } }
    private var trackingAreaReference: NSTrackingArea?
    private let actionLabel = NSTextField(wrappingLabelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var focusTargets: [ShortcutKeyCapView] = []

    override var isFlipped: Bool { true }

    init(entry: ShortcutEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        actionLabel.stringValue = entry.action
        actionLabel.font = .systemFont(ofSize: 13)
        actionLabel.textColor = DWBColor.textPrimary
        actionLabel.maximumNumberOfLines = 0
        actionLabel.lineBreakMode = .byWordWrapping
        actionLabel.setAccessibilityElement(false)

        noteLabel.stringValue = entry.note ?? ""
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = DWBAppearance.shared.textTertiary
        noteLabel.maximumNumberOfLines = 0
        noteLabel.lineBreakMode = .byWordWrapping
        noteLabel.isHidden = entry.note == nil
        noteLabel.setAccessibilityElement(false)

        let texts = NSStackView(views: [actionLabel, noteLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        texts.translatesAutoresizingMaskIntoConstraints = false
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        texts.setHuggingPriority(.defaultLow, for: .horizontal)

        let caps = NSStackView(views: makeCaps())
        caps.orientation = .horizontal
        caps.spacing = 4
        caps.translatesAutoresizingMaskIntoConstraints = false
        caps.setContentHuggingPriority(.required, for: .horizontal)
        caps.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(texts)
        addSubview(caps)
        // The caps keep their natural width, so the text column gets the rest of the row.
        let capsWidth = caps.widthAnchor.constraint(equalToConstant: ceil(caps.fittingSize.width))
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            texts.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            texts.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            texts.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            capsWidth,
            caps.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            caps.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The text column takes all the width the key caps leave, so the labels wrap there.
            texts.trailingAnchor.constraint(equalTo: caps.leadingAnchor, constant: -12)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(entry.action)
        setAccessibilityValue(entry.keys.isEmpty ? "Unassigned" : entry.keys.map(\.spokenText).joined(separator: ", "))
        var help = [entry.note].compactMap { $0 }
        if !entry.isEditable { help.append("This shortcut cannot be changed.") }
        setAccessibilityHelp(help.isEmpty ? nil : help.joined(separator: " "))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// One cap per key. An editable row can add a key; with no key it shows Unassigned.
    private func makeCaps() -> [NSView] {
        guard entry.isEditable else {
            return entry.keys.map { ShortcutKeyCapView(text: $0.text, tone: entry.tone) }
        }
        var views: [NSView] = []
        if entry.keys.isEmpty {
            let cap = ShortcutKeyCapView(text: "Unassigned", tone: entry.tone, style: .unassigned)
            cap.makeInteractive(label: "Unassigned, \(entry.action)",
                                help: "Assign a shortcut to \(entry.action)") { [weak self] in
                guard let self else { return }
                self.onEdit?(self.entry, nil)
            }
            register(cap)
            views.append(cap)
        } else {
            for (index, key) in entry.keys.enumerated() {
                let cap = ShortcutKeyCapView(text: key.text, tone: entry.tone)
                cap.makeInteractive(label: "\(key.spokenText), \(entry.action)",
                                    help: "Edit the \(key.text) shortcut for \(entry.action)") { [weak self] in
                    guard let self else { return }
                    self.onEdit?(self.entry, index)
                }
                register(cap)
                views.append(cap)
            }
            let add = ShortcutKeyCapView(text: "+", tone: entry.tone, style: .add)
            add.makeInteractive(label: "Add shortcut for \(entry.action)",
                                help: "Add another shortcut for \(entry.action)") { [weak self] in
                guard let self else { return }
                self.onEdit?(self.entry, nil)
            }
            register(add)
            views.append(add)
        }
        return views
    }

    private func register(_ cap: ShortcutKeyCapView) {
        focusTargets.append(cap)
        cap.onFocusChange = { [weak self] focused in
            guard let self else { return }
            self.onHighlightChanged?(focused ? self.entry : (self.isHovering ? self.entry : nil))
        }
    }

    // A reference row has no cap to focus, so the row itself takes focus and lights its keys.
    override var acceptsFirstResponder: Bool { !entry.isEditable }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            isFocused = true
            scrollToVisible(bounds)
            onHighlightChanged?(entry)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        onHighlightChanged?(isHovering ? entry : nil)
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            DWBColor.overlayHover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl).fill()
        }
        if isFocused {
            let appearance = DWBAppearance.shared
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                    xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl)
            appearance.focusRingColor.setStroke()
            ring.lineWidth = appearance.focusRingWidth
            ring.stroke()
        }
        DWBColor.gridLine.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
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

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHighlightChanged?(entry)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHighlightChanged?(isFocused || focusTargets.contains { window?.firstResponder === $0 } ? entry : nil)
    }
}

// MARK: - Toolbar

/// The search pill and Restore Defaults… on one line. When the page is too narrow for both,
/// the button wraps below the field.
private final class ShortcutsToolbarView: NSView {
    private let pill: NSView
    private let button: NSView
    private static let gap: CGFloat = 12
    private static let wrappedGap: CGFloat = 8
    private static let pillMinimum: CGFloat = 220
    private static let rowHeight: CGFloat = 28

    private var wideConstraints: [NSLayoutConstraint] = []
    private var wrappedConstraints: [NSLayoutConstraint] = []
    private var isWrapped = false

    override var isFlipped: Bool { true }

    init(pill: NSView, button: NSView) {
        self.pill = pill
        self.button = button
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        addSubview(button)
        let fit = heightAnchor.constraint(equalToConstant: Self.rowHeight)
        wideConstraints = [
            button.leadingAnchor.constraint(equalTo: pill.trailingAnchor, constant: Self.gap),
            button.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ]
        wrappedConstraints = [
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: Self.wrappedGap)
        ]
        rowConstraint = fit
        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: leadingAnchor),
            pill.topAnchor.constraint(equalTo: topAnchor),
            pill.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            fit
        ] + wideConstraints)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var rowConstraint: NSLayoutConstraint!

    override func layout() {
        let buttonWidth = button.intrinsicContentSize.width
        let wraps = bounds.width > 0 && bounds.width < Self.pillMinimum + Self.gap + buttonWidth
        if wraps != isWrapped {
            isWrapped = wraps
            NSLayoutConstraint.deactivate(wraps ? wideConstraints : wrappedConstraints)
            NSLayoutConstraint.activate(wraps ? wrappedConstraints : wideConstraints)
            rowConstraint.constant = wraps ? Self.rowHeight * 2 + Self.wrappedGap : Self.rowHeight
        }
        super.layout()
    }
}

// MARK: - Page

final class ShortcutsPageView: NSView, NSTextFieldDelegate {
    private let registry: ShortcutRegistry
    private var groups: [ShortcutGroup] = []
    private let mapView = ShortcutKeyboardMapView(frame: .zero)
    private let searchPill = NSView()
    private let searchField = NSTextField()
    private let restoreButton = DWBButton(title: "Restore Defaults\u{2026}", variant: .secondary)
    private let scopeLabel = NSTextField(labelWithString: "Changes apply only to dwb player.")
    private let emptyLabel = NSTextField(labelWithString: "No matching shortcuts.")
    private let groupsStack = NSStackView()
    private let rootStack = NSStackView()
    private var isSearchFocused = false
    private var hoveredEntry: ShortcutEntry?
    private var rowsByCommand: [ShortcutCommandID: ShortcutRowView] = [:]

    override var isFlipped: Bool { true }

    init(registry: ShortcutRegistry = .shared) {
        self.registry = registry
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildSearchPill()

        restoreButton.target = self
        restoreButton.action = #selector(restoreDefaultsTapped)
        restoreButton.setAccessibilityLabel("Restore Defaults")
        restoreButton.setAccessibilityHelp("Restores the default keyboard shortcuts for dwb player")
        restoreButton.setAccessibilityIdentifier("settings.shortcuts.restoreDefaults")
        let toolbar = ShortcutsToolbarView(pill: searchPill, button: restoreButton)

        scopeLabel.font = .systemFont(ofSize: 11)
        scopeLabel.textColor = DWBAppearance.shared.textTertiary
        scopeLabel.setAccessibilityIdentifier("settings.shortcuts.scope")

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = DWBAppearance.shared.textSecondary
        emptyLabel.setAccessibilityIdentifier("settings.shortcuts.empty")
        emptyLabel.isHidden = true

        groupsStack.orientation = .vertical
        groupsStack.alignment = .leading
        groupsStack.spacing = 18
        groupsStack.translatesAutoresizingMaskIntoConstraints = false

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(mapView)
        rootStack.addArrangedSubview(toolbar)
        rootStack.addArrangedSubview(scopeLabel)
        rootStack.setCustomSpacing(8, after: toolbar)
        rootStack.addArrangedSubview(emptyLabel)
        rootStack.addArrangedSubview(groupsStack)
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor),
            groupsStack.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            groupsStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor)
        ])
        reload()
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsDidChange),
                                               name: ShortcutRegistry.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        DWBAppearance.stopObserving(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appearanceChanged() {
        applySearchChrome()
        scopeLabel.textColor = DWBAppearance.shared.textTertiary
        emptyLabel.textColor = DWBAppearance.shared.textSecondary
        reload()
    }

    /// A shortcut changed: the rows, the map and the context text follow it at once.
    @objc private func shortcutsDidChange() {
        reload()
    }

    /// The text currently in the search field. Exposed for tests and automation.
    var query: String {
        get { searchField.stringValue }
        set {
            searchField.stringValue = newValue
            reload()
        }
    }

    private func buildSearchPill() {
        searchPill.wantsLayer = true
        searchPill.translatesAutoresizingMaskIntoConstraints = false
        searchPill.layer?.cornerRadius = DWBMetrics.radiusPill

        let icon = NSImageView()
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        icon.contentTintColor = DWBAppearance.shared.textTertiary
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityElement(false)
        icon.identifier = NSUserInterfaceItemIdentifier("shortcuts.search.icon")

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 12)
        searchField.textColor = DWBColor.textPrimary
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.usesSingleLineMode = true
        searchField.setAccessibilityLabel("Search shortcuts")
        searchField.setAccessibilityIdentifier("settings.shortcuts.search")

        searchPill.addSubview(icon)
        searchPill.addSubview(searchField)
        let width = searchPill.widthAnchor.constraint(equalToConstant: 320)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            searchPill.heightAnchor.constraint(equalToConstant: 28),
            searchPill.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            width,
            icon.leadingAnchor.constraint(equalTo: searchPill.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: searchPill.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: searchPill.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchPill.centerYAnchor)
        ])
        applySearchChrome()
    }

    private func applySearchChrome() {
        let appearance = DWBAppearance.shared
        searchPill.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        searchPill.layer?.borderColor = (isSearchFocused ? appearance.focusRingColor : appearance.border).cgColor
        searchPill.layer?.borderWidth = isSearchFocused ? appearance.focusRingWidth : 1
        searchField.placeholderAttributedString = NSAttributedString(string: "Search shortcuts", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: appearance.textTertiary
        ])
        searchPill.subviews.compactMap { $0 as? NSImageView }.forEach { $0.contentTintColor = appearance.textTertiary }
    }

    /// Rebuilds the grouped rows from the active keys and the current query.
    private func reload() {
        // Keep keyboard focus on the row the user just edited.
        let focusedCommand = rowsByCommand.first { _, row in
            row.focusTargets.contains { window?.firstResponder === $0 } || window?.firstResponder === row
        }?.key

        groups = ShortcutsCatalog.groups(bindings: registry.bindings)
        mapView.tones = ShortcutKeyMap.tones(for: groups)
        let visible = ShortcutsSearch.filter(groups, query: searchField.stringValue)
        groupsStack.arrangedSubviews.forEach { view in
            groupsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowsByCommand = [:]
        hoveredEntry = nil
        mapView.hotKeys = []
        emptyLabel.isHidden = !visible.isEmpty
        for group in visible {
            let groupView = makeGroupView(group)
            groupsStack.addArrangedSubview(groupView)
            // Rows span the whole content column, not just the widest row.
            groupView.widthAnchor.constraint(equalTo: groupsStack.widthAnchor).isActive = true
        }
        // The rows are new views: rebuild the Tab order, then put focus back on the edited row.
        window?.recalculateKeyViewLoop()
        if let focusedCommand, let row = rowsByCommand[focusedCommand] {
            window?.makeFirstResponder(row.focusTargets.first ?? row)
        }
    }

    private func makeGroupView(_ group: ShortcutGroup) -> NSView {
        let title = NSTextField(labelWithString: group.title)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = PlayerTheme.current.accentText
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setAccessibilityElement(false)

        let header = NSStackView(views: [title])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        if let appLabel = group.appLabel {
            let app = NSTextField(labelWithString: "\(appLabel) only")
            app.font = .systemFont(ofSize: 10, weight: .medium)
            app.textColor = DWBAppearance.shared.textTertiary
            app.setAccessibilityElement(false)
            header.addArrangedSubview(app)
        }

        let rows = group.items.map { entry -> ShortcutRowView in
            let row = ShortcutRowView(entry: entry)
            row.onHighlightChanged = { [weak self] highlighted in self?.rowHighlightChanged(highlighted) }
            row.onEdit = { [weak self] entry, index in self?.edit(entry, keyIndex: index) }
            rowsByCommand[entry.id] = row
            return row
        }
        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setCustomSpacing(6, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for row in rows {
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        stack.setAccessibilityLabel(group.appLabel.map { "\(group.title), \($0) only" } ?? group.title)
        return stack
    }

    private func rowHighlightChanged(_ entry: ShortcutEntry?) {
        hoveredEntry = entry
        guard let entry else {
            mapView.hotKeys = []
            return
        }
        mapView.hotTone = entry.tone
        mapView.hotKeys = Set(entry.mapKeys)
    }

    private func edit(_ entry: ShortcutEntry, keyIndex: Int?) {
        guard let window else { return }
        ShortcutEditorSheet.present(on: window, command: entry.id, keyIndex: keyIndex, registry: registry)
    }

    @objc private func restoreDefaultsTapped(_ sender: Any) {
        DWBConfirmSheet.present(
            on: window,
            title: "Restore default shortcuts for dwb player?",
            message: "This resets the keyboard shortcuts for dwb player, including rows the search hides. It does not change other settings.",
            confirmTitle: "Restore Defaults"
        ) { [registry] in
            registry.restoreDefaults()
        }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidBeginEditing(_ obj: Notification) {
        isSearchFocused = true
        applySearchChrome()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        isSearchFocused = false
        applySearchChrome()
    }

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }
}
