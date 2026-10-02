import Cocoa

/// Transient HUD shown when this player window's audio sync offset changes.
///
/// Compensates for Bluetooth-headphone audio latency (and similar fixed
/// output-device delay) by letting the user nudge audio playback earlier or
/// later relative to video, by ear, in small increments. Modeled on
/// VolumeBarView's transient-HUD behavior but without drag interaction —
/// the value is only changed via PlayerWindowController's adjust/reset
/// methods (menu items and keyboard shortcuts).
final class AudioDelayBarView: NSView {

    static let preferredSize = NSSize(width: Metrics.preferredWidth, height: 48)

    private enum Metrics {
        static let cornerRadius: CGFloat = 10
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

    private var hideTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 0.94).cgColor
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        configureClockImageView()
        addSubview(clockImageView)
        addSubview(captionLabel)
        addSubview(valueLabel)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Audio Sync")
        updatePresentation(milliseconds: 0)
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        let iconHeight: CGFloat = 16
        clockImageView.frame = NSRect(
            x: Metrics.iconX,
            y: (bounds.height - iconHeight) / 2,
            width: Metrics.iconWidth,
            height: iconHeight
        )
        captionLabel.frame = NSRect(
            x: Metrics.labelX,
            y: bounds.height / 2,
            width: Metrics.valueWidth,
            height: bounds.height / 2 - 2
        )
        valueLabel.frame = NSRect(
            x: Metrics.labelX,
            y: 4,
            width: Metrics.valueWidth,
            height: bounds.height / 2 - 2
        )
    }

    /// Shows the HUD for `milliseconds`, fading in if hidden and rescheduling auto-hide.
    /// Positive means audio plays later (delayed further); negative means audio plays
    /// sooner (advanced) — matches VLCMediaPlayer.currentAudioPlaybackDelay's sign.
    func show(milliseconds: Int32) {
        updatePresentation(milliseconds: milliseconds)

        if isHidden || alphaValue < 0.05 {
            isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self.animator().alphaValue = 1.0
            }
        }
        scheduleHide()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    private static func makeCaptionLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "AUDIO SYNC")
        label.font = Metrics.captionFont
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.drawsBackground = false
        label.isBordered = false
        return label
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0 ms")
        label.font = Metrics.valueFont
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        label.drawsBackground = false
        label.isBordered = false
        return label
    }

    private func configureClockImageView() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        clockImageView.image = NSImage(systemSymbolName: "waveform.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        clockImageView.imageScaling = .scaleProportionallyUpOrDown
        clockImageView.contentTintColor = NSColor.white.withAlphaComponent(0.94)
    }

    private func updatePresentation(milliseconds: Int32) {
        let sign = milliseconds > 0 ? "+" : ""
        valueLabel.stringValue = "\(sign)\(milliseconds) ms"
        setAccessibilityValue("\(sign)\(milliseconds) milliseconds")
        needsDisplay = true
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                self.animator().alphaValue = 0
            } completionHandler: {
                self.isHidden = true
                self.alphaValue = 0
            }
        }
    }
}
