import Cocoa

/// Transient HUD shown when this player window's audio sync offset changes.
///
/// Compensates for Bluetooth-headphone audio latency (and similar fixed
/// output-device delay) by letting the user nudge audio playback earlier or
/// later relative to video, by ear, in small increments. Modeled on
/// VolumeBarView's transient-HUD behavior but without drag interaction —
/// the value is only changed via PlayerWindowController's adjust/reset
/// methods (menu items and keyboard shortcuts).
final class AudioDelayBarView: OverlayPanelView {

    static var preferredSize: NSSize { NSSize(width: Metrics.preferredWidth, height: AudioSyncHUDModel.height) }

    private enum Metrics {
        static let iconX: CGFloat = 16
        static let iconWidth: CGFloat = 18
        static let labelX: CGFloat = 46
        static let labelTrailingInset: CGFloat = 16
        static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        static let captionFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        // Widest plausible value: "-3000 ms" (see PlayerWindowController's clamp range).
        static let valueWidth = ceil(
            ("-3000 ms" as NSString)
                .size(withAttributes: [.font: valueFont]).width
        ) + 4
        static var preferredWidth: CGFloat {
            labelX + valueWidth + labelTrailingInset
        }
    }

    private let clockImageView = NSImageView()
    private let captionLabel = AudioDelayBarView.makeCaptionLabel()
    private let valueLabel = AudioDelayBarView.makeValueLabel()

    override init(frame: NSRect) {
        super.init(frame: frame)
        fadeDuration = DWBMotion.fade

        configureClockImageView()
        addSubview(clockImageView)
        addSubview(captionLabel)
        addSubview(valueLabel)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Audio Sync")
        updatePresentation(milliseconds: 0)
        applyCaptionColor()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func contrastDidChange() {
        applyCaptionColor()
    }

    override func layout() {
        super.layout()

        let iconHeight: CGFloat = 16
        clockImageView.frame = NSRect(
            x: Metrics.iconX,
            y: ((bounds.height - iconHeight) / 2).rounded(),
            width: Metrics.iconWidth,
            height: iconHeight
        )
        captionLabel.frame = NSRect(
            x: Metrics.labelX,
            y: bounds.height - 6 - 13,
            width: Metrics.valueWidth,
            height: 13
        )
        valueLabel.frame = NSRect(
            x: Metrics.labelX,
            y: 6,
            width: Metrics.valueWidth,
            height: 20
        )
    }

    /// Shows the HUD for `milliseconds`, fading in if hidden and rescheduling auto-hide.
    /// Positive means audio plays later (delayed further); negative means audio plays
    /// sooner (advanced) — matches VLCMediaPlayer.currentAudioPlaybackDelay's sign.
    func show(milliseconds: Int32) {
        updatePresentation(milliseconds: milliseconds)
        present(hold: AudioSyncHUDModel.hold)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    private static func makeCaptionLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.drawsBackground = false
        label.isBordered = false
        return label
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0 ms")
        label.font = Metrics.valueFont
        label.textColor = DWBColor.textPrimary
        label.drawsBackground = false
        label.isBordered = false
        return label
    }

    private func applyCaptionColor() {
        captionLabel.attributedStringValue = NSAttributedString(string: "AUDIO SYNC", attributes: [
            .font: Metrics.captionFont,
            .foregroundColor: increaseContrast ? DWBColor.textPrimary : DWBColor.textSecondary,
            .kern: AudioSyncHUDModel.captionKern
        ])
    }

    private func configureClockImageView() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        clockImageView.image = NSImage(systemSymbolName: "waveform.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        clockImageView.imageScaling = .scaleProportionallyUpOrDown
        clockImageView.contentTintColor = DWBColor.textPrimary
    }

    private func updatePresentation(milliseconds: Int32) {
        let sign = milliseconds > 0 ? "+" : ""
        valueLabel.stringValue = "\(sign)\(milliseconds) ms"
        setAccessibilityValue("\(sign)\(milliseconds) milliseconds")
        needsDisplay = true
    }
}
