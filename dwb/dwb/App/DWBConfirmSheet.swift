import AppKit

/// The design system's destructive confirmation (`components/feedback/ConfirmDialog.jsx`),
/// shown as a sheet: 380 pt wide, radius 10, `surfaceElevated`. Cancel is the default and
/// focused button; the destructive button is `errorText` solid with a `textOnFill` label.
/// Used for the destructive confirmations in Settings > Advanced.
enum DWBConfirmSheetMetrics {
    static let width: CGFloat = 380
    static let padding: CGFloat = 20
    static let radius: CGFloat = DWBMetrics.radiusCard
    static let iconSize: CGFloat = 18
}

private final class DWBConfirmPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class DWBConfirmSheet {
    private static var active: DWBConfirmSheet?

    private let panel: DWBConfirmPanel
    private let cancelButton: DWBButton
    private let confirmButton: DWBButton
    private let onConfirm: () -> Void
    private weak var parent: NSWindow?
    private var didFinish = false

    /// Presents the confirmation as a sheet on `window`. With no window it runs modally.
    static func present(on window: NSWindow?,
                        title: String,
                        message: String,
                        confirmTitle: String,
                        cancelTitle: String = "Cancel",
                        onConfirm: @escaping () -> Void) {
        let sheet = DWBConfirmSheet(title: title, message: message,
                                    confirmTitle: confirmTitle, cancelTitle: cancelTitle,
                                    onConfirm: onConfirm)
        active = sheet
        sheet.show(on: window)
    }

    private init(title: String, message: String, confirmTitle: String, cancelTitle: String,
                 onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
        cancelButton = DWBButton(title: cancelTitle, variant: .neutral)
        confirmButton = DWBButton(title: confirmTitle, variant: .destructive)

        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = DWBConfirmSheetMetrics.radius
        content.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        content.layer?.borderWidth = 1
        content.layer?.borderColor = DWBAppearance.shared.border.cgColor
        content.layer?.masksToBounds = true

        let warning = NSImageView()
        let configuration = NSImage.SymbolConfiguration(pointSize: DWBConfirmSheetMetrics.iconSize, weight: .regular)
        warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?
            .withSymbolConfiguration(configuration)
        warning.contentTintColor = DWBColor.errorText
        warning.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.textColor = DWBColor.textPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2

        let titleRow = NSStackView(views: [warning, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 11.5)
        messageLabel.textColor = DWBAppearance.shared.textSecondary
        messageLabel.preferredMaxLayoutWidth = DWBConfirmSheetMetrics.width - DWBConfirmSheetMetrics.padding * 2

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let buttonRow = NSStackView(views: [spacer, cancelButton, confirmButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [titleRow, messageLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        let pad = DWBConfirmSheetMetrics.padding
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: DWBConfirmSheetMetrics.width),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: DWBConfirmSheetMetrics.width, height: ceil(content.fittingSize.height))

        panel = DWBConfirmPanel(contentRect: NSRect(origin: .zero, size: size),
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

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.keyEquivalent = "\r"
        cancelButton.setAccessibilityIdentifier("confirm.cancel")
        confirmButton.target = self
        confirmButton.action = #selector(confirmTapped)
        confirmButton.setAccessibilityIdentifier("confirm.destructive")
        panel.initialFirstResponder = cancelButton
        panel.onCancel = { [weak self] in self?.finish(confirmed: false) }
    }

    private func show(on window: NSWindow?) {
        parent = window
        if let window {
            window.beginSheet(panel) { [weak self] _ in self?.sheetEnded() }
            panel.makeFirstResponder(cancelButton)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(cancelButton)
            NSApp.runModal(for: panel)
        }
    }

    @objc private func cancelTapped() { finish(confirmed: false) }
    @objc private func confirmTapped() { finish(confirmed: true) }

    private var pendingConfirmation = false

    private func finish(confirmed: Bool) {
        guard !didFinish else { return }
        didFinish = true
        pendingConfirmation = confirmed
        if let parent {
            parent.endSheet(panel)
        } else {
            NSApp.stopModal()
            panel.orderOut(nil)
            sheetEnded()
        }
    }

    private func sheetEnded() {
        panel.orderOut(nil)
        let confirmed = pendingConfirmation
        Self.active = nil
        if confirmed { onConfirm() }
    }
}
