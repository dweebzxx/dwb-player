import AppKit

// The design system's two rename sheets (`tokens-and-specs.md` 9.3,
// `components/feedback/RenameSheet.jsx`, `BatchRenameSheet.jsx`). Each is a borderless panel
// shown with `beginSheet` under the title bar, with the stage dimmed by black at 45%.
// What gets renamed, and how a failure is reported, stays with `PlayerWindowController`.

// MARK: - Shared host

private final class DWBSheetPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// `surfaceElevated` with a 1 pt `border` on the left, bottom and right and a radius of 10
/// on the bottom corners only: the top edge meets the title bar.
private final class SheetChromeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = DWBMetrics.radiusCard
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        outline.line(to: NSPoint(x: rect.minX, y: rect.minY + r))
        outline.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                          startAngle: 180, endAngle: 270)
        outline.line(to: NSPoint(x: rect.maxX - r, y: rect.minY))
        outline.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                          startAngle: 270, endAngle: 360)
        outline.line(to: NSPoint(x: rect.maxX, y: rect.maxY))

        let body = outline.copy() as! NSBezierPath
        body.close()
        DWBColor.surfaceElevated.setFill()
        body.fill()
        DWBAppearance.shared.border.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}

/// Black at 45% over the stage while a sheet is up.
private final class StageDimView: NSView {
    static let alpha: CGFloat = 0.45

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.alpha).cgColor
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    /// The sheet is modal for the window; clicks on the dimmed stage do nothing.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
}

private final class DWBSheetHost {
    private static var active: [DWBSheetHost] = []

    let panel: DWBSheetPanel
    private weak var parent: NSWindow?
    private var dimView: StageDimView?
    private var didFinish = false
    private var confirmedResult = false
    private var completion: ((Bool) -> Void)?

    /// `content` carries a stack pinned to its edges, so `fittingSize.height` is the sheet
    /// height (the same sizing as `DWBConfirmSheet`).
    fileprivate init(content: SheetChromeView, width: CGFloat, title: String) {
        content.widthAnchor.constraint(equalToConstant: width).isActive = true
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: ceil(content.fittingSize.height))

        panel = DWBSheetPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        panel.contentView = content
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityRole(.sheet)
        panel.setAccessibilityLabel(title)
        panel.onCancel = { [weak self] in self?.finish(confirmed: false) }
    }

    /// Shows the sheet on `window` and calls `completion(true)` after a confirmation,
    /// `completion(false)` after a cancel.
    func present(on window: NSWindow, focus: NSResponder?, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        parent = window
        Self.active.append(self)

        if let stage = window.contentView {
            let dim = StageDimView(frame: stage.bounds)
            stage.addSubview(dim)
            dimView = dim
            let fade = DWBAppearance.shared.duration(DWBMotion.fade)
            if fade > 0 {
                dim.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = fade
                    dim.animator().alphaValue = 1
                }
            }
        }
        window.beginSheet(panel) { [weak self] _ in self?.sheetEnded() }
        if let focus { panel.makeFirstResponder(focus) }
    }

    func finish(confirmed: Bool) {
        guard !didFinish else { return }
        didFinish = true
        confirmedResult = confirmed
        if let parent {
            parent.endSheet(panel)
        } else {
            sheetEnded()
        }
    }

    private func sheetEnded() {
        panel.orderOut(nil)
        dimView?.removeFromSuperview()
        dimView = nil
        Self.active.removeAll { $0 === self }
        let done = completion
        completion = nil
        done?(confirmedResult)
    }
}

// MARK: - Labels

private func sheetTitleLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 13.5, weight: .semibold)
    label.textColor = DWBColor.textPrimary
    label.lineBreakMode = .byTruncatingTail
    label.setAccessibilityElement(false)
    return label
}

private func sheetCaptionLabel(width: CGFloat) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: "")
    label.font = .systemFont(ofSize: 11.5)
    label.textColor = DWBAppearance.shared.textSecondary
    label.lineBreakMode = .byCharWrapping
    label.maximumNumberOfLines = 3
    label.preferredMaxLayoutWidth = width
    label.setAccessibilityElement(false)
    return label
}

private let sheetPadding = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)

private func pin(_ stack: NSStackView, in content: NSView) {
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: content.topAnchor, constant: sheetPadding.top),
        stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: sheetPadding.left),
        stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -sheetPadding.right),
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -sheetPadding.bottom)
    ])
}

private func buttonRow(_ cancel: DWBButton, _ confirm: DWBButton) -> NSStackView {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    let row = NSStackView(views: [spacer, cancel, confirm])
    row.orientation = .horizontal
    row.spacing = 8
    return row
}

// MARK: - Rename (single)

/// A 24 pt field row: the editable stem on `surfaceSunken`, then the protected extension
/// token. A 1 pt edge (`borderStrong`, or `errorText` for an invalid name) and a 2 pt ring
/// while editing (`errorFill` when invalid).
private final class FocusReportingTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            (currentEditor() as? NSTextView)?.insertionPointColor = DWBColor.textPrimary
            onFocusChange?(true)
        }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}

private final class RenameFieldView: NSView {
    let textField = FocusReportingTextField()
    private let ringLayer = CALayer()
    private let token = NSView()
    private let divider = NSView()
    private let lock = NSImageView()
    private let extensionLabel = NSTextField(labelWithString: "")
    private let hasExtension: Bool

    var isFocused = false { didSet { restyle() } }
    var hasError = false { didSet { restyle() } }

    init(stem: String, extensionText: String) {
        hasExtension = !extensionText.isEmpty
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = false
        ringLayer.cornerRadius = 7
        ringLayer.borderWidth = DWBMetrics.focusWidth
        layer?.addSublayer(ringLayer)

        textField.stringValue = stem
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 12)
        textField.textColor = DWBColor.textPrimary
        textField.lineBreakMode = .byClipping
        textField.cell?.isScrollable = true
        textField.cell?.usesSingleLineMode = true
        textField.setAccessibilityLabel("File name")
        textField.setAccessibilityIdentifier("renameSheet.name")
        textField.onFocusChange = { [weak self] focused in self?.isFocused = focused }
        addSubview(textField)

        if hasExtension {
            token.wantsLayer = true
            token.layer?.cornerRadius = 4
            token.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            token.layer?.masksToBounds = true
            token.toolTip = "The extension is protected"
            token.setAccessibilityLabel("Extension \(extensionText), protected")
            divider.wantsLayer = true
            token.addSubview(divider)
            lock.imageScaling = .scaleProportionallyDown
            lock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .regular))
            lock.setAccessibilityElement(false)
            token.addSubview(lock)
            extensionLabel.stringValue = extensionText
            extensionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            token.addSubview(extensionLabel)
            addSubview(token)
        }
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { restyle() }

    private func restyle() {
        let appearance = DWBAppearance.shared
        layer?.backgroundColor = DWBColor.surfaceSunken.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (hasError ? DWBColor.errorText : DWBColor.borderStrong).cgColor
        ringLayer.isHidden = !isFocused
        ringLayer.borderWidth = appearance.focusRingWidth
        ringLayer.borderColor = (hasError ? DWBColor.errorFill : appearance.focusRingColor).cgColor
        token.layer?.backgroundColor = DWBColor.surface.cgColor
        divider.layer?.backgroundColor = appearance.border.cgColor
        lock.contentTintColor = DWBColor.textDisabled
        extensionLabel.textColor = appearance.textTertiary
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let ringOutset = ringLayer.borderWidth
        ringLayer.frame = bounds.insetBy(dx: -ringOutset, dy: -ringOutset)
        ringLayer.cornerRadius = 5 + ringOutset

        var textRight = bounds.width - 7
        if hasExtension {
            let labelSize = extensionLabel.intrinsicContentSize
            let width = 8 + 8 + 4 + ceil(labelSize.width) + 8
            token.frame = NSRect(x: bounds.width - 1 - width, y: 1, width: width, height: bounds.height - 2)
            divider.frame = NSRect(x: 0, y: 0, width: 1, height: token.bounds.height)
            lock.frame = NSRect(x: 8, y: floor((token.bounds.height - 8) / 2), width: 8, height: 8)
            extensionLabel.frame = NSRect(x: 8 + 8 + 4,
                                          y: floor((token.bounds.height - ceil(labelSize.height)) / 2),
                                          width: ceil(labelSize.width), height: ceil(labelSize.height))
            textRight = token.frame.minX
        }
        let textHeight = ceil(textField.intrinsicContentSize.height)
        textField.frame = NSRect(x: 7, y: floor((bounds.height - textHeight) / 2),
                                 width: max(0, textRight - 7), height: textHeight)
    }
}

/// Inline validation: an 11 pt `errorText` line led by `exclamationmark.circle`. The row
/// keeps its 15 pt height when empty so the sheet does not jump.
private final class RenameValidationRow: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    static let height: CGFloat = 15

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = DWBColor.errorText
        icon.setAccessibilityElement(false)
        label.font = .systemFont(ofSize: 11)
        label.textColor = DWBColor.errorText
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityIdentifier("renameSheet.validation")
        addSubview(icon)
        addSubview(label)
        icon.isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    var message: String? {
        didSet {
            guard message != oldValue else { return }
            label.stringValue = message ?? ""
            icon.isHidden = message == nil
            needsLayout = true
            if let message {
                NSAccessibility.post(element: label,
                                     notification: .announcementRequested,
                                     userInfo: [.announcement: message,
                                                .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
    }

    override func layout() {
        super.layout()
        let labelHeight = ceil(label.intrinsicContentSize.height)
        let textX: CGFloat = message == nil ? 0 : 11 + 5
        icon.frame = NSRect(x: 0, y: floor((bounds.height - 11) / 2), width: 11, height: 11)
        label.frame = NSRect(x: textX, y: floor((bounds.height - labelHeight) / 2),
                             width: max(0, bounds.width - textX), height: labelHeight)
    }
}

final class DWBRenameSheet: NSObject, NSTextFieldDelegate {
    private let host: DWBSheetHost
    private let fieldView: RenameFieldView
    private let validationRow: RenameValidationRow
    private let cancelButton: DWBButton
    private let renameButton: DWBButton
    private let originalStem: String
    private let fileExtension: String
    private let nameExists: (String) -> Bool
    private let onRename: (String) -> Void
    private var evaluation: RenameValidation.Result

    /// Shows the rename sheet on `window`. `nameExists` answers whether a file with the given
    /// full name is already in the folder; `onRename` receives the new full file name.
    static func present(on window: NSWindow,
                        filename: String,
                        stem: String,
                        fileExtension: String,
                        nameExists: @escaping (String) -> Bool,
                        onRename: @escaping (String) -> Void) {
        let sheet = DWBRenameSheet(filename: filename, stem: stem, fileExtension: fileExtension,
                                   nameExists: nameExists, onRename: onRename)
        sheet.show(on: window)
    }

    private init(filename: String, stem: String, fileExtension: String,
                 nameExists: @escaping (String) -> Bool, onRename: @escaping (String) -> Void) {
        let fieldView = RenameFieldView(stem: stem, extensionText: fileExtension.isEmpty ? "" : ".\(fileExtension)")
        let validationRow = RenameValidationRow()
        let cancelButton = DWBButton(title: RenameSheetCopy.cancelTitle, variant: .neutral)
        let renameButton = DWBButton(title: RenameSheetCopy.singleConfirmTitle, variant: .primary)
        self.originalStem = stem
        self.fileExtension = fileExtension
        self.nameExists = nameExists
        self.onRename = onRename
        self.fieldView = fieldView
        self.validationRow = validationRow
        self.cancelButton = cancelButton
        self.renameButton = renameButton
        evaluation = RenameValidation.evaluate(stem: stem, originalStem: stem,
                                               fileExtension: fileExtension, nameExists: nameExists)

        let contentWidth = DWBMetrics.renameSheetWidth - sheetPadding.left - sheetPadding.right
        let content = SheetChromeView()
        let titleLabel = sheetTitleLabel(RenameSheetCopy.singleTitle)
        let caption = sheetCaptionLabel(width: contentWidth)
        caption.stringValue = RenameSheetCopy.singleCaption(filename: filename)
        let buttons = buttonRow(cancelButton, renameButton)

        let stack = NSStackView(views: [titleLabel, caption, fieldView, validationRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: caption)      // 6 + 8 above the field
        stack.setCustomSpacing(10, after: validationRow) // 6 + 4 above the buttons
        pin(stack, in: content)
        fieldView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            caption.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fieldView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fieldView.heightAnchor.constraint(equalToConstant: DWBMetrics.sheetFieldHeight),
            validationRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        host = DWBSheetHost(content: content, width: DWBMetrics.renameSheetWidth,
                            title: RenameSheetCopy.singleTitle)
        super.init()

        fieldView.textField.delegate = self
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("renameSheet.cancel")
        renameButton.target = self
        renameButton.action = #selector(renameTapped)
        renameButton.keyEquivalent = "\r"
        renameButton.setAccessibilityIdentifier("renameSheet.rename")
        apply(evaluation)
    }

    private func show(on window: NSWindow) {
        // The sheet object stays alive until the sheet ends: the host holds this closure.
        host.present(on: window, focus: fieldView.textField) { [self] _ in _ = self }
        // The stem, not the extension, is selected for typing over. The field is already first
        // responder, so select through its editor rather than asking for focus a second time.
        fieldView.textField.currentEditor()?.selectAll(nil)
    }

    private func apply(_ result: RenameValidation.Result) {
        evaluation = result
        let issue = result.visibleIssue
        validationRow.message = issue.map(RenameValidation.message(for:))
        fieldView.hasError = issue != nil
        renameButton.isEnabled = result.canSubmit
    }

    private func recompute() {
        apply(RenameValidation.evaluate(stem: fieldView.textField.stringValue,
                                        originalStem: originalStem,
                                        fileExtension: fileExtension,
                                        nameExists: nameExists))
    }

    // MARK: Actions

    @objc private func cancelTapped() { host.finish(confirmed: false) }

    @objc private func renameTapped() { submit() }

    private func submit() {
        guard evaluation.canSubmit else { return }
        let name = evaluation.fullName
        // The rename runs after the sheet has closed, so its own failure sheet can open.
        host.finish(confirmed: true)
        DispatchQueue.main.async { [onRename] in onRename(name) }
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { recompute() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            host.finish(confirmed: false)
            return true
        default:
            return false
        }
    }
}

// MARK: - Batch rename

private final class BatchRenameRowView: NSView {
    static let verticalPadding: CGFloat = 3

    init(old: String, new: String, primaryPrefix: String, secondaryPrefix: String, theme: DWBTheme) {
        super.init(frame: .zero)
        let appearance = DWBAppearance.shared
        let font = NSFont.systemFont(ofSize: 11.5)

        let oldLabel = NSTextField(labelWithString: old)
        oldLabel.font = font
        oldLabel.textColor = appearance.textTertiary
        oldLabel.lineBreakMode = .byTruncatingTail
        oldLabel.setAccessibilityElement(false)

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .regular))
        chevron.imageScaling = .scaleProportionallyDown
        chevron.contentTintColor = DWBColor.textDisabled
        chevron.setAccessibilityElement(false)

        let newLabel = NSTextField(labelWithString: "")
        newLabel.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: new, attributes: [
            .font: font, .foregroundColor: DWBColor.textPrimary
        ])
        if let match = MarkerPrefixHighlight.match(in: new, primary: primaryPrefix, secondary: secondaryPrefix) {
            text.addAttributes([
                .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: match.kind == .primary ? theme.markerPrimary : theme.markerSecondary
            ], range: NSRange(location: 0, length: match.utf16Length))
        }
        newLabel.attributedStringValue = text
        newLabel.setAccessibilityElement(false)

        for view in [oldLabel, chevron, newLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(view)
        }
        let rowHeight = ceil(font.boundingRectForFont.height) + Self.verticalPadding * 2
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: rowHeight),
            oldLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            oldLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: oldLabel.trailingAnchor, constant: 8),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            newLabel.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            newLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            newLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            oldLabel.widthAnchor.constraint(equalTo: newLabel.widthAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel("\(old) will become \(new)")
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }
}

/// Sunken well, 1 pt `border`, radius 6, holding the "old › new" rows.
private final class BatchRenameWellView: NSView {
    init(preview: BatchRenamePreview.Preview, primaryPrefix: String, secondaryPrefix: String, theme: DWBTheme) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = DWBMetrics.radiusControl
        layer?.borderWidth = 1
        restyle()

        var views: [NSView] = preview.rows.map {
            BatchRenameRowView(old: $0.old, new: $0.new, primaryPrefix: primaryPrefix,
                               secondaryPrefix: secondaryPrefix, theme: theme)
        }
        if let more = preview.moreText {
            let label = NSTextField(labelWithString: more)
            label.font = .systemFont(ofSize: 11)
            label.textColor = DWBAppearance.shared.textTertiary
            label.translatesAutoresizingMaskIntoConstraints = false
            let holder = NSView()
            holder.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 10),
                label.topAnchor.constraint(equalTo: holder.topAnchor, constant: 3),
                label.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -1),
                label.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor, constant: -10)
            ])
            holder.setAccessibilityElement(true)
            holder.setAccessibilityLabel(more)
            views.append(holder)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1)
        ])
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { restyle() }

    private func restyle() {
        layer?.backgroundColor = DWBColor.surfaceSunken.cgColor
        layer?.borderColor = DWBAppearance.shared.border.cgColor
    }
}

final class DWBBatchRenameSheet: NSObject {
    private let host: DWBSheetHost
    private let cancelButton: DWBButton
    private let confirmButton: DWBButton
    private let onConfirm: () -> Void

    /// Confirms a multi-file marker rename before anything on disk changes. `prefix` is the
    /// marker being applied or removed; `isPrimary` picks its marker color.
    static func present(on window: NSWindow,
                        prefix: String,
                        isPrimary: Bool,
                        primaryPrefix: String,
                        secondaryPrefix: String,
                        renames: [(old: String, new: String)],
                        onConfirm: @escaping () -> Void) {
        let sheet = DWBBatchRenameSheet(prefix: prefix, isPrimary: isPrimary,
                                        primaryPrefix: primaryPrefix, secondaryPrefix: secondaryPrefix,
                                        renames: renames, onConfirm: onConfirm)
        sheet.show(on: window)
    }

    private init(prefix: String, isPrimary: Bool, primaryPrefix: String, secondaryPrefix: String,
                 renames: [(old: String, new: String)], onConfirm: @escaping () -> Void) {
        let count = renames.count
        let cancelButton = DWBButton(title: RenameSheetCopy.cancelTitle, variant: .neutral)
        let confirmButton = DWBButton(title: RenameSheetCopy.batchConfirmTitle(count: count), variant: .primary)
        self.onConfirm = onConfirm
        self.cancelButton = cancelButton
        self.confirmButton = confirmButton

        let theme = PlayerTheme.current
        let contentWidth = DWBMetrics.batchSheetWidth - sheetPadding.left - sheetPadding.right
        let content = SheetChromeView()
        let title = RenameSheetCopy.batchTitle(count: count)
        let titleLabel = sheetTitleLabel(title)

        let removing = BatchRenamePreview.isRemoving(oldNames: renames.map(\.old), prefix: prefix)
        let parts = BatchRenamePreview.captionParts(count: count, removing: removing)
        let caption = sheetCaptionLabel(width: contentWidth)
        let captionFont = NSFont.systemFont(ofSize: 11.5)
        let captionColor = DWBAppearance.shared.textSecondary
        let text = NSMutableAttributedString(string: parts.lead,
                                             attributes: [.font: captionFont, .foregroundColor: captionColor])
        text.append(NSAttributedString(string: prefix, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: isPrimary ? theme.markerPrimary : theme.markerSecondary
        ]))
        text.append(NSAttributedString(string: parts.trail,
                                       attributes: [.font: captionFont, .foregroundColor: captionColor]))
        caption.attributedStringValue = text

        let well = BatchRenameWellView(preview: BatchRenamePreview.make(renames: renames),
                                       primaryPrefix: primaryPrefix, secondaryPrefix: secondaryPrefix, theme: theme)
        let buttons = buttonRow(cancelButton, confirmButton)

        let stack = NSStackView(views: [titleLabel, caption, well, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: caption)  // 6 + 8 above the well
        stack.setCustomSpacing(16, after: well)     // 6 + 10 above the buttons
        pin(stack, in: content)
        well.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            caption.widthAnchor.constraint(equalTo: stack.widthAnchor),
            well.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        host = DWBSheetHost(content: content, width: DWBMetrics.batchSheetWidth, title: title)
        super.init()

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("batchRenameSheet.cancel")
        confirmButton.target = self
        confirmButton.action = #selector(confirmTapped)
        confirmButton.keyEquivalent = "\r"
        confirmButton.setAccessibilityIdentifier("batchRenameSheet.confirm")
    }

    private func show(on window: NSWindow) {
        // The host holds this closure, which keeps the sheet object alive until it ends.
        host.present(on: window, focus: confirmButton) { [self] confirmed in
            // The renames run after the sheet has closed, so a failure sheet can open.
            if confirmed { DispatchQueue.main.async { self.onConfirm() } }
        }
    }

    @objc private func cancelTapped() { host.finish(confirmed: false) }
    @objc private func confirmTapped() { host.finish(confirmed: true) }
}
