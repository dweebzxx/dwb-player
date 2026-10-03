import AppKit

// Settings > Shortcuts, rebuilt from the design system's `ShortcutsPage`: a keyboard map,
// a search field, and rows grouped by task. The data and the filter live in
// `ShortcutsModel.swift`; this file only draws them.

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

final class ShortcutKeyCapView: NSView {
    private let text: String
    private let tone: ShortcutTone

    override var isFlipped: Bool { true }

    init(text: String, tone: ShortcutTone) {
        self.text = text
        self.tone = tone
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

    override var intrinsicContentSize: NSSize {
        let width = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width)
        return NSSize(width: max(22, width + 12), height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusKey, yRadius: DWBMetrics.radiusKey)
        DWBColor.surfaceElevated.setFill()
        path.fill()
        (tone == .accent ? DWBColor.borderStrong : shortcutToneColor(tone)).setStroke()
        path.lineWidth = 1
        path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: tone == .accent ? DWBColor.textPrimary : shortcutToneColor(tone)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                                withAttributes: attributes)
    }
}

// MARK: - Row

final class ShortcutRowView: NSView {
    let entry: ShortcutEntry
    var onHoverChanged: ((ShortcutEntry?) -> Void)?
    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool { true }

    init(entry: ShortcutEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let action = NSTextField(labelWithString: entry.action)
        action.font = .systemFont(ofSize: 13)
        action.textColor = DWBColor.textPrimary
        action.lineBreakMode = .byTruncatingTail
        action.translatesAutoresizingMaskIntoConstraints = false
        action.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let caps = NSStackView(views: entry.keys.map { ShortcutKeyCapView(text: $0, tone: entry.tone) })
        caps.orientation = .horizontal
        caps.spacing = 4
        caps.translatesAutoresizingMaskIntoConstraints = false
        caps.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(action)
        addSubview(caps)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            action.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            action.centerYAnchor.constraint(equalTo: centerYAnchor),
            caps.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            caps.centerYAnchor.constraint(equalTo: centerYAnchor),
            action.trailingAnchor.constraint(lessThanOrEqualTo: caps.leadingAnchor, constant: -12)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(entry.action)
        setAccessibilityValue(entry.keys.joined(separator: ", "))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isHovering {
            DWBColor.overlayHover.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: DWBMetrics.radiusControl, yRadius: DWBMetrics.radiusControl).fill()
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
        onHoverChanged?(entry)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChanged?(nil)
    }
}

// MARK: - Page

final class ShortcutsPageView: NSView, NSTextFieldDelegate {
    private let groups: [ShortcutGroup]
    private let mapView = ShortcutKeyboardMapView(frame: .zero)
    private let searchPill = NSView()
    private let searchField = NSTextField()
    private let groupsStack = NSStackView()
    private let rootStack = NSStackView()
    private var isSearchFocused = false

    override var isFlipped: Bool { true }

    init(groups: [ShortcutGroup] = ShortcutsCatalog.groups) {
        self.groups = groups
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        mapView.tones = ShortcutKeyMap.tones(for: groups)
        buildSearchPill()

        groupsStack.orientation = .vertical
        groupsStack.alignment = .leading
        groupsStack.spacing = 18
        groupsStack.translatesAutoresizingMaskIntoConstraints = false

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(mapView)
        rootStack.addArrangedSubview(searchPill)
        rootStack.addArrangedSubview(groupsStack)
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            groupsStack.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor),
            groupsStack.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor)
        ])
        reload()
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() {
        applySearchChrome()
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

    /// Rebuilds the grouped rows from the current query.
    private func reload() {
        let visible = ShortcutsSearch.filter(groups, query: searchField.stringValue)
        groupsStack.arrangedSubviews.forEach { view in
            groupsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        mapView.hotKeys = []
        for group in visible {
            let groupView = makeGroupView(group)
            groupsStack.addArrangedSubview(groupView)
            // Rows span the whole content column, not just the widest row.
            groupView.widthAnchor.constraint(equalTo: groupsStack.widthAnchor).isActive = true
        }
    }

    private func makeGroupView(_ group: ShortcutGroup) -> NSView {
        let title = NSTextField(labelWithString: group.title)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = PlayerTheme.current.accentText
        title.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [title])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        if let appLabel = group.appLabel {
            let app = NSTextField(labelWithString: "\(appLabel) only")
            app.font = .systemFont(ofSize: 10, weight: .medium)
            app.textColor = DWBAppearance.shared.textTertiary
            header.addArrangedSubview(app)
        }

        let rows = group.items.map { entry -> ShortcutRowView in
            let row = ShortcutRowView(entry: entry)
            row.onHoverChanged = { [weak self] hovered in self?.rowHoverChanged(hovered) }
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
        stack.setAccessibilityLabel(group.title)
        return stack
    }

    private func rowHoverChanged(_ entry: ShortcutEntry?) {
        guard let entry else {
            mapView.hotKeys = []
            return
        }
        mapView.hotTone = entry.tone
        mapView.hotKeys = Set(entry.mapKeys)
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
