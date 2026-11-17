import AppKit

// The Edit shortcut sheet (`tokens-and-specs.md` 9.3: the same chrome as the rename sheet) and
// its key recorder. The sheet only collects a key and shows whether it can be used; the rules
// live in `ShortcutBindings.validate` and the keys are saved through `ShortcutRegistry`.

// MARK: - Copy

enum ShortcutEditorCopy {
    static let title = "Edit shortcut"
    static let appName = "dwb player"
    static let recorderLabel = "Press a key or key combination"
    static let remove = "Remove"
    static let cancel = "Cancel"
    static let save = "Save"
    static let invalid = "This key combination can't be used for this action."

    static func conflict(with action: String) -> String {
        "Already assigned to \u{2018}\(action)\u{2019} in this context."
    }
}

// MARK: - Recorder

/// A 24 pt field that captures the next key press, with its modifiers, and shows it in key cap
/// notation. It follows the rename sheet's field: `surfaceSunken`, a 1 pt `borderStrong` edge
/// (`errorText` when the key cannot be used) and a 2 pt focus ring while it has focus.
final class ShortcutRecorderView: NSView {
    enum State: Equatable {
        /// Nothing pressed yet.
        case empty
        case key(ShortcutKey)
        /// A press the dispatch cannot match: a modifier alone, a function key, and so on.
        case unsupported
    }

    private(set) var state: State = .empty
    var onChange: ((State) -> Void)?
    /// The key being replaced, shown until the first press.
    var currentKeyText: String? { didSet { refresh() } }
    var hasError = false { didSet { restyle() } }

    private let label = NSTextField(labelWithString: "")
    private let ringLayer = CALayer()
    private var isFocused = false { didSet { restyle() } }
    private var lastModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = false
        ringLayer.cornerRadius = 7
        layer?.addSublayer(ringLayer)
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none

        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel(ShortcutEditorCopy.recorderLabel)
        setAccessibilityIdentifier("shortcutEditor.recorder")
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { restyle() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DWBMetrics.sheetFieldHeight)
    }

    /// The recorded key as text, or the current key before the first press.
    private var displayText: String {
        switch state {
        case .key(let key):  return key.text
        case .unsupported:   return ""
        case .empty:         return currentKeyText ?? ""
        }
    }

    private func refresh() {
        let appearance = DWBAppearance.shared
        label.stringValue = displayText
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        if case .key = state {
            label.textColor = DWBColor.textPrimary
        } else {
            label.textColor = appearance.textTertiary
        }
        setAccessibilityValue(accessibilityText)
        restyle()
        needsLayout = true
    }

    private var accessibilityText: String {
        switch state {
        case .key(let key):  return key.spokenText
        case .unsupported:   return "unsupported key"
        case .empty:         return currentKeyText.flatMap { ShortcutKey(text: $0)?.spokenText } ?? "no key"
        }
    }

    private func restyle() {
        let appearance = DWBAppearance.shared
        layer?.backgroundColor = DWBColor.surfaceSunken.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (hasError ? DWBColor.errorText : DWBColor.borderStrong).cgColor
        ringLayer.isHidden = !isFocused
        ringLayer.borderWidth = appearance.focusRingWidth
        ringLayer.borderColor = (hasError ? DWBColor.errorFill : appearance.focusRingColor).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let outset = ringLayer.borderWidth
        ringLayer.frame = bounds.insetBy(dx: -outset, dy: -outset)
        ringLayer.cornerRadius = 5 + outset
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: 8, y: floor((bounds.height - height) / 2),
                             width: max(0, bounds.width - 16), height: height)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { isFocused = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    /// Takes a key press as the new key. Return, Enter, Escape and Tab are not recordable:
    /// they stay with the sheet's buttons and the focus loop. Returns whether the press was taken.
    func record(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.keyCode {
        case 36, 76, 53: return false   // Return, Enter, Escape
        case 48:         return false   // Tab
        default:         break
        }
        set(ShortcutKey(event: event).map(State.key) ?? .unsupported)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if record(event) { return }
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                window?.selectKeyView(preceding: self)
            } else {
                window?.selectKeyView(following: self)
            }
            return
        }
        super.keyDown(with: event)
    }

    /// A modifier pressed on its own is a key combination that cannot be used.
    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if lastModifiers.isEmpty && !flags.isEmpty { set(.unsupported) }
        lastModifiers = flags
        super.flagsChanged(with: event)
    }

    private func set(_ newState: State) {
        state = newState
        refresh()
        NSAccessibility.post(element: self, notification: .valueChanged)
        onChange?(newState)
    }
}

// MARK: - Validation row

/// Inline message under the recorder: an 11 pt `errorText` line led by `exclamationmark.circle`.
/// It holds two lines so a long action name wraps without resizing the sheet.
private final class ShortcutValidationRow: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    static let height: CGFloat = 30

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = DWBColor.errorText
        icon.setAccessibilityElement(false)
        icon.isHidden = true
        label.font = .systemFont(ofSize: 11)
        label.textColor = DWBColor.errorText
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.setAccessibilityIdentifier("shortcutEditor.validation")
        addSubview(icon)
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var isFlipped: Bool { true }

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
        let textX: CGFloat = 11 + 5
        icon.frame = NSRect(x: 0, y: 1, width: 11, height: 11)
        label.preferredMaxLayoutWidth = max(0, bounds.width - textX)
        label.frame = NSRect(x: textX, y: 0, width: max(0, bounds.width - textX), height: bounds.height)
    }
}

// MARK: - Sheet

final class ShortcutEditorSheet: NSObject {
    private let host: DWBSheetHost
    private let recorder = ShortcutRecorderView()
    private let validationRow = ShortcutValidationRow()
    private let removeButton = DWBButton(title: ShortcutEditorCopy.remove, variant: .neutral)
    private let cancelButton = DWBButton(title: ShortcutEditorCopy.cancel, variant: .neutral)
    private let saveButton = DWBButton(title: ShortcutEditorCopy.save, variant: .primary)

    private let registry: ShortcutRegistry
    private let commandID: ShortcutCommandID
    /// Which key of the command is being replaced, or nil when a key is being added.
    private let keyIndex: Int?
    private var recorded: ShortcutKey?

    /// Shows the sheet on `window` for one key of `commandID`: the key at `keyIndex`, or a
    /// new key when `keyIndex` is nil.
    static func present(on window: NSWindow,
                        command commandID: ShortcutCommandID,
                        keyIndex: Int?,
                        registry: ShortcutRegistry = .shared) {
        let sheet = ShortcutEditorSheet(command: commandID, keyIndex: keyIndex, registry: registry)
        sheet.show(on: window)
    }

    private init(command commandID: ShortcutCommandID, keyIndex: Int?, registry: ShortcutRegistry) {
        self.registry = registry
        self.commandID = commandID
        self.keyIndex = keyIndex
        let command = registry.bindings.command(commandID)

        let contentWidth = DWBMetrics.renameSheetWidth - sheetPadding.left - sheetPadding.right
        let content = SheetChromeView()
        let titleLabel = sheetTitleLabel(ShortcutEditorCopy.title)
        let appLabel = sheetCaptionLabel(width: contentWidth)
        appLabel.stringValue = ShortcutEditorCopy.appName
        let actionLabel = NSTextField(wrappingLabelWithString: command.name)
        actionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        actionLabel.textColor = DWBColor.textPrimary
        actionLabel.maximumNumberOfLines = 2
        actionLabel.preferredMaxLayoutWidth = contentWidth
        actionLabel.setAccessibilityElement(false)
        let recorderLabel = NSTextField(labelWithString: ShortcutEditorCopy.recorderLabel)
        recorderLabel.font = .systemFont(ofSize: 11.5)
        recorderLabel.textColor = DWBAppearance.shared.textSecondary
        recorderLabel.setAccessibilityElement(false)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let buttons = NSStackView(views: [removeButton, spacer, cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [titleLabel, appLabel, actionLabel, recorderLabel, recorder,
                                        validationRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: actionLabel)
        stack.setCustomSpacing(4, after: recorderLabel)
        stack.setCustomSpacing(10, after: validationRow)
        pin(stack, in: content)
        NSLayoutConstraint.activate([
            appLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.heightAnchor.constraint(equalToConstant: DWBMetrics.sheetFieldHeight),
            validationRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        host = DWBSheetHost(content: content, width: DWBMetrics.renameSheetWidth,
                            title: ShortcutEditorCopy.title)
        super.init()

        if let keyIndex, registry.bindings.activeKeys(for: commandID).indices.contains(keyIndex) {
            recorder.currentKeyText = registry.bindings.activeKeys(for: commandID)[keyIndex].text
        }
        recorder.onChange = { [weak self] state in self?.recorderChanged(state) }
        removeButton.isEnabled = keyIndex != nil
        removeButton.setAccessibilityLabel("Remove \(command.name) shortcut")
        removeButton.setAccessibilityIdentifier("shortcutEditor.remove")
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("shortcutEditor.cancel")
        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false
        saveButton.setAccessibilityIdentifier("shortcutEditor.save")
        saveButton.setAccessibilityHelp("Choose a key first")

        host.panel.keyEquivalentHook = { [weak self] event in self?.claim(event) ?? false }
    }

    private func show(on window: NSWindow) {
        // The sheet object stays alive until the sheet ends: the host holds this closure.
        host.present(on: window, focus: recorder) { [self] _ in _ = self }
    }

    // MARK: Keys

    /// While the sheet is open no menu item and no player command sees a key press. The
    /// recorder takes it when it has focus; with focus on a button, a key that carries ⌘, ⌃
    /// or ⌥ is swallowed so it cannot reach the menus.
    private func claim(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if host.panel.firstResponder === recorder { return recorder.record(event) }
        if [36, 76, 53].contains(event.keyCode) { return false }
        return !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    private func recorderChanged(_ state: ShortcutRecorderView.State) {
        var message: String?
        var canSave = false
        recorded = nil
        switch state {
        case .empty:
            break
        case .unsupported:
            message = ShortcutEditorCopy.invalid
        case .key(let key):
            switch registry.bindings.validate(key, for: commandID, replacing: keyIndex) {
            case .ok:
                recorded = key
                canSave = true
            case .invalid:
                message = ShortcutEditorCopy.invalid
            case .conflict(let other):
                message = ShortcutEditorCopy.conflict(with: registry.bindings.command(other).name)
            }
        }
        validationRow.message = message
        recorder.hasError = message != nil
        saveButton.isEnabled = canSave
        saveButton.setAccessibilityHelp(canSave ? nil : "Choose a key first")
    }

    // MARK: Actions

    @objc private func cancelTapped() { host.finish(confirmed: false) }

    @objc private func saveTapped() {
        guard let recorded else { return }
        let keys = registry.bindings.keys(for: commandID, replacing: keyIndex, with: recorded)
        host.finish(confirmed: true)
        registry.setKeys(keys, for: commandID)
    }

    @objc private func removeTapped() {
        guard keyIndex != nil else { return }
        let keys = registry.bindings.keys(for: commandID, replacing: keyIndex, with: nil)
        host.finish(confirmed: true)
        registry.setKeys(keys, for: commandID)
    }
}
