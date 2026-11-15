import AppKit

// Row parts for the Queue Page (`tokens-and-specs.md` 9.7 and 10.4): the filename with its
// marker prefix and search match, the Play Next tag, and the drop line.

// MARK: - Filename

enum QueueNameStyle {
    /// The filename as a row draws it: the marker prefix bold in its marker color, then the
    /// first search match bold on `accentTintStrong` with a 1 pt `accentText` underline. The
    /// match is never color alone.
    static func attributedName(_ name: String,
                               fontSize: CGFloat,
                               weight: NSFont.Weight,
                               color: NSColor,
                               primaryPrefix: String,
                               secondaryPrefix: String,
                               query: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let result = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])

        let theme = PlayerTheme.current
        let candidates: [(prefix: String, color: NSColor)] = [
            (primaryPrefix.trimmingCharacters(in: .whitespacesAndNewlines), theme.markerPrimary),
            (secondaryPrefix.trimmingCharacters(in: .whitespacesAndNewlines), theme.markerSecondary)
        ]
        .filter { !$0.prefix.isEmpty }
        .sorted { $0.prefix.count > $1.prefix.count } // the longer prefix wins
        if let match = candidates.first(where: { name.hasPrefix($0.prefix) }) {
            result.addAttributes([
                .foregroundColor: match.color,
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold)
            ], range: NSRange(location: 0, length: (match.prefix as NSString).length))
        }

        if let range = QueueSearchHighlight.firstMatch(in: name, query: query) {
            result.addAttributes([
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .backgroundColor: theme.accentTintStrong,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: theme.accentText
            ], range: range)
        }
        return result
    }
}

/// Draws attribute backgrounds as radius-2 rounded rectangles (the search highlight).
private final class RoundedHighlightLayoutManager: NSLayoutManager {
    static let cornerRadius: CGFloat = 2

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        color.setFill()
        for index in 0..<rectCount {
            NSBezierPath(roundedRect: rectArray[index],
                         xRadius: Self.cornerRadius,
                         yRadius: Self.cornerRadius).fill()
        }
    }
}

/// A one-line filename that paints the search highlight with a rounded background, which an
/// `NSTextField` cannot do. At rest it truncates in the middle by measurement (§10.4); while a
/// search is active it clips at the end so the highlighted match stays visible.
final class QueueNameLabel: NSView {
    enum Truncation { case middle, tail }

    private let storage = NSTextStorage()
    private let layoutManager = RoundedHighlightLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
    private var cachedDisplay: (width: CGFloat, truncation: Truncation, text: NSAttributedString)?

    var attributedText = NSAttributedString() {
        didSet {
            cachedDisplay = nil
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var truncation: Truncation = .middle {
        didSet {
            guard truncation != oldValue else { return }
            cachedDisplay = nil
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 1
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cachedDisplay = nil
    }

    /// The width the name needs when nothing is truncated.
    var naturalWidth: CGFloat { ceil(attributedText.size().width) }

    var lineHeight: CGFloat { ceil(attributedText.size().height) }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: lineHeight) }

    /// What is drawn at `width`: the whole name, a measured middle truncation, or (tail mode) the
    /// whole name for the layout manager to clip.
    func displayedText(forWidth width: CGFloat) -> NSAttributedString {
        if let cachedDisplay, cachedDisplay.width == width, cachedDisplay.truncation == truncation {
            return cachedDisplay.text
        }
        let text: NSAttributedString
        switch truncation {
        case .middle: text = QueueNameTruncation.truncated(attributedText, toFit: width)
        case .tail: text = attributedText
        }
        cachedDisplay = (width, truncation, text)
        return text
    }

    /// Clicks go to the row, as they do for an `NSTextField` label.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, attributedText.length > 0 else { return }
        let shown = NSMutableAttributedString(attributedString: displayedText(forWidth: bounds.width))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = truncation == .tail ? .byTruncatingTail : .byClipping
        shown.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: shown.length))
        storage.setAttributedString(shown)
        container.lineBreakMode = paragraph.lineBreakMode
        container.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        let glyphRange = layoutManager.glyphRange(for: container)
        let used = layoutManager.usedRect(for: container)
        let origin = NSPoint(x: 0, y: floor((bounds.height - used.height) / 2))
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

// MARK: - Play Next tag

/// 16 pt tall, radius 4, 1 pt `accentFill` edge on `accentTint`: a list-start glyph and the
/// position (9.5 pt bold, tabular). Placed after the name (same tag in the active look); hidden
/// on the current row.
final class QueuePlayNextTagView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let glyph = NSImageView()

    private static let leadingPadding: CGFloat = 4
    private static let glyphSize: CGFloat = 9
    private static let glyphGap: CGFloat = 3
    private static let trailingPadding: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        label.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        label.setAccessibilityElement(false)
        addSubview(label)
        glyph.imageScaling = .scaleProportionallyDown
        glyph.setAccessibilityElement(false)
        addSubview(glyph)
        toolTip = "Play Next"
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    var preferredWidth: CGFloat {
        let text = ceil((label.stringValue as NSString).size(withAttributes: [.font: label.font as Any]).width)
        return ceil(Self.leadingPadding + Self.glyphSize + Self.glyphGap + text + Self.trailingPadding)
    }

    func configure(position: Int) {
        let theme = PlayerTheme.current
        label.stringValue = "\(position)"
        label.textColor = theme.accentText
        layer?.backgroundColor = DWBAppearance.shared.accentTint.cgColor
        layer?.borderColor = theme.accentFill.cgColor
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.glyphSize, weight: .bold)
        let image = NSImage(systemSymbolName: "text.line.first.and.arrowtriangle.forward", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        glyph.image = image?.withSymbolConfiguration(configuration) ?? image
        glyph.contentTintColor = theme.accentText
        setAccessibilityLabel("Play next, position \(position)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: Self.leadingPadding, y: floor((bounds.height - Self.glyphSize) / 2),
                             width: Self.glyphSize, height: Self.glyphSize)
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: Self.leadingPadding + Self.glyphSize + Self.glyphGap,
                             y: floor((bounds.height - size.height) / 2),
                             width: ceil(size.width), height: ceil(size.height))
    }
}

// MARK: - Drop line

/// The drop line shown between rows while drag-reordering in Manual sort: a straight 2 pt
/// `accentText` line on the row's top or bottom edge, no ring (§10.4). The dragged row stays
/// in the list at 0.4 alpha.
enum QueueDropIndicatorMetrics {
    static let lineHeight = DWBMetrics.dropLine
    static let draggedRowAlpha = DWBMetrics.queueRowDragAlpha

    /// The line inside a view `width` wide and one line tall.
    static func lineRect(width: CGFloat) -> NSRect {
        NSRect(x: 0, y: 0, width: max(0, width), height: lineHeight)
    }

    /// The line's frame on the boundary `boundaryY` between two rows, spanning the row shape
    /// `shape` (centered on the boundary).
    static func frame(onBoundaryY boundaryY: CGFloat, spanning shape: NSRect) -> NSRect {
        NSRect(x: shape.minX, y: boundaryY - lineHeight / 2, width: shape.width, height: lineHeight)
    }
}

/// The drop line: a 2 pt `accentText` line. Lets the pointer through.
final class QueueDropIndicatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        setAccessibilityElement(false)
        DWBAppearance.observe(self, selector: #selector(appearanceChanged))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    deinit { DWBAppearance.stopObserving(self) }

    @objc private func appearanceChanged() { needsDisplay = true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        PlayerTheme.current.accentText.setFill()
        QueueDropIndicatorMetrics.lineRect(width: bounds.width).fill()
    }
}
