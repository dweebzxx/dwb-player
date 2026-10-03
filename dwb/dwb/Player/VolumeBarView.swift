import Cocoa

/// Interactive segmented-volume HUD shown transiently when this player window's
/// volume changes. It preserves click/drag adjustment and the 0–200
/// software-gain range while presenting the design system's 11-segment meter.
final class VolumeBarView: OverlayPanelView {

    static var preferredSize: NSSize {
        NSSize(width: VolumeHUDModel.preferredWidth, height: VolumeHUDModel.height)
    }

    private let speakerImageView = NSImageView()
    private let valueLabel = VolumeBarView.makeValueLabel()

    private(set) var currentVolume: Int32 = 100
    private var isDragging = false

    /// Called when the user adjusts volume by clicking or dragging the meter.
    var onVolumeChanged: ((Int32) -> Void)?

    override var defersHide: Bool { isDragging }

    override init(frame: NSRect) {
        super.init(frame: frame)
        passesMouseThrough = false
        fadeDuration = DWBMotion.fade

        speakerImageView.imageScaling = .scaleProportionallyUpOrDown
        speakerImageView.contentTintColor = .white
        addSubview(speakerImageView)
        addSubview(valueLabel)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Volume")
        setAccessibilityHelp("Click or drag the level meter to adjust volume")
        updatePresentation()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        let icon = VolumeHUDModel.iconSize
        speakerImageView.frame = NSRect(
            x: VolumeHUDModel.sidePadding,
            y: ((bounds.height - icon) / 2).rounded(),
            width: icon,
            height: icon
        )
        let valueHeight: CGFloat = 26
        valueLabel.frame = NSRect(
            x: bounds.width - VolumeHUDModel.sidePadding - VolumeHUDModel.valueWidth,
            y: ((bounds.height - valueHeight) / 2).rounded(),
            width: VolumeHUDModel.valueWidth,
            height: valueHeight
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let meter = meterRect
        for index in 0..<VolumeHUDModel.segmentCount {
            let rect = NSRect(
                x: meter.minX + VolumeHUDModel.segmentMinX(index),
                y: meter.minY,
                width: VolumeHUDModel.segmentSize,
                height: VolumeHUDModel.segmentSize
            )
            let lit = VolumeHUDModel.litColor(segment: index, volume: currentVolume, theme: PlayerTheme.current)
            let color = VolumeHUDModel.isLit(segment: index, volume: currentVolume)
                ? lit
                : lit.withAlphaComponent(VolumeHUDModel.unlitAlpha)
            color.setFill()
            NSBezierPath(roundedRect: rect,
                         xRadius: VolumeHUDModel.segmentRadius,
                         yRadius: VolumeHUDModel.segmentRadius).fill()
        }
    }

    /// Shows the HUD for `volume`, fading in if hidden and rescheduling auto-hide.
    /// Safe during drag: the HUD remains visible until mouse up.
    func show(volume: Int32) {
        currentVolume = clampedVolume(volume)
        updatePresentation()

        guard !isDragging else { return }
        present(hold: DWBMotion.volumeHold)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        cancelPendingHide()
        present(hold: nil)
        applyMouseVolume(event)
    }

    override func mouseDragged(with event: NSEvent) {
        applyMouseVolume(event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        rescheduleHide(after: DWBMotion.volumeHold)
    }

    private var meterRect: NSRect {
        NSRect(
            x: VolumeHUDModel.sidePadding + VolumeHUDModel.iconSize + VolumeHUDModel.gap,
            y: ((bounds.height - VolumeHUDModel.segmentSize) / 2).rounded(),
            width: VolumeHUDModel.meterWidth,
            height: VolumeHUDModel.segmentSize
        )
    }

    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "100%")
        label.font = .monospacedDigitSystemFont(ofSize: VolumeHUDModel.valueFontSize, weight: .bold)
        label.textColor = .white
        label.drawsBackground = false
        label.isBordered = false
        label.alignment = .right
        return label
    }

    private func updatePresentation() {
        let configuration = NSImage.SymbolConfiguration(pointSize: VolumeHUDModel.iconSize, weight: .semibold)
        let symbolName = currentVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        speakerImageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        valueLabel.stringValue = "\(currentVolume)%"
        setAccessibilityValue("\(currentVolume)%")
        needsDisplay = true
    }

    private func clampedVolume(_ volume: Int32) -> Int32 {
        VolumePolicy.clamped(volume)
    }

    private func applyMouseVolume(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let fraction = VolumeHUDModel.meterFraction(forX: point.x - meterRect.minX)
        let volume = VolumePolicy.volume(
            forMeterFraction: fraction,
            normalSegmentCount: VolumeHUDModel.normalSegmentCount,
            extendedSegmentCount: VolumeHUDModel.boostSegmentCount
        )
        currentVolume = volume
        updatePresentation()
        onVolumeChanged?(volume)
    }
}
