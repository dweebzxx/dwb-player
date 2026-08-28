import Cocoa

/// Interactive segmented-volume HUD shown transiently when this player window's
/// volume changes. It preserves click/drag adjustment and the 0–200
/// software-gain range while presenting a compact horizontal meter.
final class VolumeBarView: NSView {

    static let preferredSize = NSSize(width: Metrics.preferredWidth, height: 48)

    private enum Metrics {
        static let cornerRadius: CGFloat = 10
        static let iconX: CGFloat = 16
        static let iconWidth: CGFloat = 18
        static let meterX: CGFloat = 49
        static let segmentWidth: CGFloat = 6
        static let segmentGap: CGFloat = 3
        static let segmentHeight: CGFloat = 8
        static let normalSegmentCount = 7
        static let extendedSegmentCount = 4
        static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        static let valueLeadingGap: CGFloat = 10
        static let valueTrailingInset: CGFloat = 12
        static let valueWidth = ceil(
            ("\(VolumePolicy.maximumVolume)%" as NSString)
                .size(withAttributes: [.font: valueFont]).width
        ) + 4

        static var segmentCount: Int { normalSegmentCount + extendedSegmentCount }
        static var meterWidth: CGFloat {
            CGFloat(segmentCount) * segmentWidth + CGFloat(segmentCount - 1) * segmentGap
        }
        static var preferredWidth: CGFloat {
            meterX + meterWidth + valueLeadingGap + valueWidth + valueTrailingInset
        }
    }

    private let speakerImageView = NSImageView()
    private let valueLabel = VolumeBarView.makeValueLabel()

    private(set) var currentVolume: Int32 = 100
    private var isDragging = false
    private var hideTimer: Timer?

    /// Called when the user adjusts volume by clicking or dragging the meter.
    var onVolumeChanged: ((Int32) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 0.94).cgColor
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        configureSpeakerImageView()
        addSubview(speakerImageView)
        addSubview(valueLabel)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Volume")
        setAccessibilityHelp("Click or drag the level meter to adjust volume")
        updatePresentation()
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        let iconHeight: CGFloat = 18
        speakerImageView.frame = NSRect(
            x: Metrics.iconX,
            y: (bounds.height - iconHeight) / 2,
            width: Metrics.iconWidth,
            height: iconHeight
        )
        valueLabel.frame = NSRect(
            x: bounds.width - Metrics.valueWidth - Metrics.valueTrailingInset,
            y: (bounds.height - 20) / 2,
            width: Metrics.valueWidth,
            height: 20
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let meter = meterRect
        let filledSegments = filledSegmentCount(for: currentVolume)
        for index in 0..<Metrics.segmentCount {
            let rect = NSRect(
                x: meter.minX + CGFloat(index) * (Metrics.segmentWidth + Metrics.segmentGap),
                y: meter.minY,
                width: Metrics.segmentWidth,
                height: Metrics.segmentHeight
            )
            let color: NSColor
            if index >= filledSegments {
                color = NSColor.white.withAlphaComponent(0.16)
            } else if index < Metrics.normalSegmentCount {
                color = PlayerBrandColors.periwinkleLight.withAlphaComponent(0.82)
            } else {
                color = PlayerBrandColors.darkOchreLight.withAlphaComponent(0.86)
            }
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    /// Shows the HUD for `volume`, fading in if hidden and rescheduling auto-hide.
    /// Safe during drag: the HUD remains visible until mouse up.
    func show(volume: Int32) {
        currentVolume = clampedVolume(volume)
        updatePresentation()

        guard !isDragging else { return }
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

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        hideTimer?.invalidate()
        isHidden = false
        alphaValue = 1.0
        applyMouseVolume(event)
    }

    override func mouseDragged(with event: NSEvent) {
        applyMouseVolume(event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        scheduleHide()
    }

    private var meterRect: NSRect {
        NSRect(
            x: Metrics.meterX,
            y: (bounds.height - Metrics.segmentHeight) / 2,
            width: Metrics.meterWidth,
            height: Metrics.segmentHeight
        )
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "100%")
        label.font = Metrics.valueFont
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        label.drawsBackground = false
        label.isBordered = false
        label.alignment = .right
        return label
    }

    private func configureSpeakerImageView() {
        speakerImageView.imageScaling = .scaleProportionallyUpOrDown
        speakerImageView.contentTintColor = NSColor.white.withAlphaComponent(0.94)
    }

    private func updatePresentation() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let symbolName = currentVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        speakerImageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        valueLabel.stringValue = "\(currentVolume)%"
        setAccessibilityValue("\(currentVolume)%")
        needsDisplay = true
    }

    private func filledSegmentCount(for volume: Int32) -> Int {
        VolumePolicy.filledSegmentCount(
            for: volume,
            normalSegmentCount: Metrics.normalSegmentCount,
            extendedSegmentCount: Metrics.extendedSegmentCount
        )
    }

    private func clampedVolume(_ volume: Int32) -> Int32 {
        VolumePolicy.clamped(volume)
    }

    private func applyMouseVolume(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let fraction = (point.x - meterRect.minX) / meterRect.width
        let volume = VolumePolicy.volume(
            forMeterFraction: fraction,
            normalSegmentCount: Metrics.normalSegmentCount,
            extendedSegmentCount: Metrics.extendedSegmentCount
        )
        currentVolume = volume
        updatePresentation()
        onVolumeChanged?(volume)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            guard let self, !self.isDragging else { return }
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
