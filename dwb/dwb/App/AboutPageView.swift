import AppKit

/// The About page (`tokens-and-specs.md` 9.5, `components/settings/AboutPage.jsx`): no page
/// header; a 96 pt icon, then a column 24 pt to its right with the name, version, description,
/// a rule, the facts and the link pills. The copyright sits at the bottom right.
final class AboutPageView: NSView {
    struct Link {
        let title: String
        let identifier: String
        let open: () -> Void
    }

    static let columnGap: CGFloat = 24
    /// The description and the rule are at most 420 pt wide.
    static let columnMaxWidth: CGFloat = 420
    static let minHeight: CGFloat = 380
    static let factKeyColumn: CGFloat = 110

    private var refreshers: [() -> Void] = []
    private let links: [Link]

    init(version: String,
         build: String,
         description: String,
         facts: [(String, String)],
         links: [Link],
         copyright: String?) {
        self.links = links
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        func makeLabel(_ text: String,
                       size: CGFloat,
                       color: @escaping () -> NSColor) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: size)
            label.textColor = color()
            label.isSelectable = false
            label.translatesAutoresizingMaskIntoConstraints = false
            refreshers.append { label.textColor = color() }
            return label
        }

        let iconView = NSImageView()
        iconView.image = NSImage(named: NSImage.applicationIconName)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityElement(false)

        // "dwb" in the primary text color, the app word in accentText; 26 pt semibold.
        let nameLabel = NSTextField(labelWithString: "")
        nameLabel.isSelectable = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        let nameFont = NSFont.systemFont(ofSize: DWBMetrics.aboutTitle, weight: .semibold)
        let name = NSMutableAttributedString(string: "dwb", attributes: [
            .font: nameFont, .foregroundColor: DWBColor.textPrimary
        ])
        name.append(NSAttributedString(string: " player", attributes: [
            .font: nameFont, .foregroundColor: PlayerTheme.current.accentText
        ]))
        nameLabel.attributedStringValue = name
        nameLabel.setAccessibilityLabel("dwb player")

        let versionLabel = makeLabel("Version \(version) \u{2022} Build \(build)", size: 13,
                                     color: { DWBAppearance.shared.textSecondary })
        versionLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = DWBColor.textPrimary
        descriptionLabel.isSelectable = false
        descriptionLabel.preferredMaxLayoutWidth = Self.columnMaxWidth
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        let rule = AboutRuleView()
        rule.translatesAutoresizingMaskIntoConstraints = false

        let factRows: [[NSView]] = facts.map { key, value in
            let keyLabel = makeLabel(key, size: 12.5, color: { DWBAppearance.shared.textTertiary })
            let valueLabel = makeLabel(value, size: 12.5, color: { DWBColor.textPrimary })
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
            valueLabel.lineBreakMode = .byTruncatingMiddle
            valueLabel.toolTip = value
            return [keyLabel, valueLabel]
        }
        let factsGrid = NSGridView(views: factRows)
        factsGrid.translatesAutoresizingMaskIntoConstraints = false
        factsGrid.rowSpacing = 7
        factsGrid.columnSpacing = 12
        factsGrid.rowAlignment = .firstBaseline
        if factsGrid.numberOfColumns == 2 {
            factsGrid.column(at: 0).width = Self.factKeyColumn
            factsGrid.column(at: 0).xPlacement = .leading
            factsGrid.column(at: 1).xPlacement = .leading
        }

        let pills: [AboutLinkPill] = links.enumerated().map { index, link in
            let pill = AboutLinkPill(title: link.title)
            pill.target = self
            pill.action = #selector(linkTapped(_:))
            pill.tag = index
            pill.setAccessibilityIdentifier(link.identifier)
            return pill
        }
        let linkRow = NSStackView(views: pills)
        linkRow.orientation = .horizontal
        linkRow.spacing = 8
        linkRow.translatesAutoresizingMaskIntoConstraints = false

        // Flex gap 6 plus the kit's margins: description +4, rule 12 / 10, links +14.
        var arranged: [NSView] = [nameLabel, versionLabel, descriptionLabel, rule]
        if !factRows.isEmpty { arranged.append(factsGrid) }
        if !pills.isEmpty { arranged.append(linkRow) }
        let column = NSStackView(views: arranged)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.setCustomSpacing(10, after: versionLabel)
        column.setCustomSpacing(18, after: descriptionLabel)
        column.setCustomSpacing(16, after: rule)
        if !factRows.isEmpty { column.setCustomSpacing(20, after: factsGrid) }
        column.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(column)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: DWBMetrics.aboutIcon),
            iconView.heightAnchor.constraint(equalToConstant: DWBMetrics.aboutIcon),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            column.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Self.columnGap),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            rule.heightAnchor.constraint(equalToConstant: 1),
            rule.widthAnchor.constraint(equalToConstant: Self.columnMaxWidth),

            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minHeight)
        ])

        if let copyright {
            let copyrightLabel = makeLabel(copyright, size: 10.5, color: { DWBAppearance.shared.textTertiary })
            addSubview(copyrightLabel)
            NSLayoutConstraint.activate([
                copyrightLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                copyrightLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        setAccessibilityLabel("About dwb player")
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() {
        refreshers.forEach { $0() }
    }

    @objc private func linkTapped(_ sender: NSControl) {
        guard links.indices.contains(sender.tag) else { return }
        links[sender.tag].open()
    }
}

/// The 1 pt `border` rule under the description (`borderStrong` under Increase Contrast).
private final class AboutRuleView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyColor()
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { applyColor() }

    private func applyColor() {
        layer?.backgroundColor = DWBAppearance.shared.border.cgColor
    }
}

/// An About link: a 24 pt pill with a 1 pt `border` edge on `overlaySelected`, the title in
/// `accentText` (11.5 pt semibold) and `arrow.up.right.square` (10 pt) after it. Radius 12.
private final class AboutLinkPill: NSControl {
    private let title: String
    private var isPressed = false
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    private static let height: CGFloat = 24
    private static let horizontalPadding: CGFloat = 10
    private static let iconGap: CGFloat = 5
    private static let iconSize: CGFloat = 10
    private static var labelFont: NSFont { .systemFont(ofSize: 11.5, weight: .semibold) }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
        setAccessibilityLabel(title)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        let text = ceil((title as NSString).size(withAttributes: [.font: Self.labelFont]).width)
        return NSSize(width: Self.horizontalPadding * 2 + text + Self.iconGap + Self.iconSize, height: Self.height)
    }

    override func accessibilityPerformPress() -> Bool {
        sendAction(action, to: target)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = DWBAppearance.shared
        let theme = PlayerTheme.current
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DWBMetrics.radiusPill, yRadius: DWBMetrics.radiusPill)
        DWBColor.overlaySelected.setFill()
        path.fill()
        if isPressed || isHovering {
            (isPressed ? DWBColor.overlayPressed : DWBColor.overlayHover).setFill()
            path.fill()
        }
        let focused = window?.firstResponder === self
        (focused ? appearance.focusRingColor : appearance.border).setStroke()
        path.lineWidth = focused ? appearance.focusRingWidth : 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: theme.accentText]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textOrigin = NSPoint(x: Self.horizontalPadding, y: floor((bounds.height - textSize.height) / 2))
        (title as NSString).draw(at: textOrigin, withAttributes: attributes)

        let configuration = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .semibold)
        if let icon = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?.tinted(with: theme.accentText) {
            let size = icon.size
            icon.draw(in: NSRect(x: textOrigin.x + ceil(textSize.width) + Self.iconGap,
                                 y: floor((bounds.height - size.height) / 2),
                                 width: size.width, height: size.height))
        }
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

    override func mouseEntered(with event: NSEvent) { isHovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovering = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Space and Return follow the link.
        if event.keyCode == 49 || event.keyCode == 36 {
            sendAction(action, to: target)
        } else {
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
}
