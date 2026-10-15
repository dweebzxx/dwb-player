import AppKit

/// Pure presentation rules for the parts of the player window that sit over the
/// video. Everything here is free of view state so it can be unit tested.

enum OverlayBacking {
    /// Increase Contrast replaces every translucent backing with an opaque one.
    static func resolved(_ color: NSColor, increaseContrast: Bool) -> NSColor {
        increaseContrast ? color.withAlphaComponent(1) : color
    }
}

// MARK: - Volume HUD

enum VolumeHUDModel {
    static let height: CGFloat = 56
    static let sidePadding: CGFloat = 22
    static let gap: CGFloat = 18
    static let iconSize: CGFloat = 18
    static let segmentSize: CGFloat = 11
    static let segmentRadius: CGFloat = 2.5
    static let segmentGap: CGFloat = 4
    static let groupGap: CGFloat = 12
    static let unlitAlpha: CGFloat = 0.24
    static let valueFontSize: CGFloat = 20
    static let valueWidth: CGFloat = 62
    static let normalSegmentCount = 7
    static let boostSegmentCount = 4
    static let heatStartVolume: Int32 = 150
    static let heatSpan: Int32 = 50

    static var segmentCount: Int { normalSegmentCount + boostSegmentCount }

    static var normalGroupWidth: CGFloat { groupWidth(count: normalSegmentCount) }
    static var boostGroupWidth: CGFloat { groupWidth(count: boostSegmentCount) }
    static var meterWidth: CGFloat { normalGroupWidth + groupGap + boostGroupWidth }

    static var preferredWidth: CGFloat {
        sidePadding + iconSize + gap + meterWidth + gap + valueWidth + sidePadding
    }

    private static func groupWidth(count: Int) -> CGFloat {
        CGFloat(count) * segmentSize + CGFloat(max(0, count - 1)) * segmentGap
    }

    /// 0 up to 150%, then rising linearly to 1 at 200%.
    static func heatFraction(volume: Int32) -> CGFloat {
        let clamped = VolumePolicy.clamped(volume)
        guard clamped > heatStartVolume else { return 0 }
        return min(1, CGFloat(clamped - heatStartVolume) / CGFloat(heatSpan))
    }

    static func isLit(segment index: Int, volume: Int32) -> Bool {
        index < VolumePolicy.filledSegmentCount(
            for: volume,
            normalSegmentCount: normalSegmentCount,
            extendedSegmentCount: boostSegmentCount
        )
    }

    /// The fully lit color of a segment: marker primary for the 0–100% group,
    /// marker secondary for the boost group, blended toward error red from 150%.
    static func litColor(segment index: Int, volume: Int32, theme: DWBTheme) -> NSColor {
        let base = index < normalSegmentCount ? theme.markerPrimary : theme.markerSecondary
        let heat = heatFraction(volume: volume)
        guard heat > 0 else { return base }
        return base.blended(withFraction: heat, of: DWBColor.errorFill) ?? base
    }

    /// X offset of a segment's left edge from the left edge of the meter.
    static func segmentMinX(_ index: Int) -> CGFloat {
        if index < normalSegmentCount {
            return CGFloat(index) * (segmentSize + segmentGap)
        }
        return normalGroupWidth + groupGap
            + CGFloat(index - normalSegmentCount) * (segmentSize + segmentGap)
    }

    /// Converts a pointer X (from the meter's left edge) to the uniform
    /// 0...1 fraction `VolumePolicy.volume(forMeterFraction:)` expects, so the
    /// two groups and the gap between them map onto the 100% boundary.
    static func meterFraction(forX x: CGFloat) -> CGFloat {
        let total = CGFloat(segmentCount)
        let normalBoundary = CGFloat(normalSegmentCount) / total
        if x <= normalGroupWidth {
            return max(0, x) / normalGroupWidth * normalBoundary
        }
        let boostStart = normalGroupWidth + groupGap
        if x < boostStart { return normalBoundary }
        let boostFraction = min(1, (x - boostStart) / boostGroupWidth)
        return normalBoundary + boostFraction * (1 - normalBoundary)
    }
}

// MARK: - Audio sync HUD

enum AudioSyncHUDModel {
    static let height: CGFloat = 44
    static let hold: TimeInterval = DWBMotion.syncHold
    static let captionKern: CGFloat = 0.4
}

// MARK: - HUD stack

/// The volume HUD, with the audio sync HUD directly above it, sits above the
/// undo toast so the three never overlap. The status HUD takes the volume HUD's slot.
enum HUDStackMetrics {
    /// Distance from the top of the rail to the bottom of the volume HUD and the status HUD:
    /// `DWBMetrics.hudBottomOffset` above the stage bottom, which is the toast's 24 pt
    /// offset plus its 40 pt height above the 68 pt rail.
    static let bottomOffsetAboveRail: CGFloat = DWBMetrics.hudBottomOffset - DWBMetrics.railHeight
    static let gap: CGFloat = 8
}

// MARK: - Status HUD

/// What the non-modal status HUD says (`tokens-and-specs.md` 9.4). Pure so the copy, the
/// symbols and the hold times can be tested.
struct StatusHUDContent: Equatable {
    enum Tone: Equatable { case neutral, caution }

    let symbol: String
    let title: String
    let detail: String?
    let tone: Tone
    let hold: TimeInterval

    /// Fit / Fill / Stretch: the mode name, with its shortcut as the detail.
    static func scale(_ mode: ScaleMode) -> StatusHUDContent {
        switch mode {
        case .fit:
            return StatusHUDContent(symbol: "rectangle.arrowtriangle.2.inward", title: "Fit",
                                    detail: "\u{2318}1", tone: .neutral, hold: DWBMotion.scaleHUDHold)
        case .fill:
            return StatusHUDContent(symbol: "rectangle.arrowtriangle.2.outward", title: "Fill",
                                    detail: "\u{2318}2", tone: .neutral, hold: DWBMotion.scaleHUDHold)
        case .stretch:
            return StatusHUDContent(symbol: "arrow.left.and.right", title: "Stretch",
                                    detail: "\u{2318}3", tone: .neutral, hold: DWBMotion.scaleHUDHold)
        }
    }

    static func windowLimit(maxWindows: Int) -> StatusHUDContent {
        StatusHUDContent(symbol: "macwindow", title: "Window limit reached",
                         detail: "dwb player supports up to \(maxWindows) player windows.",
                         tone: .caution, hold: DWBMotion.windowLimitHold)
    }

    /// What VoiceOver speaks: the title, then the detail.
    var spokenText: String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title). \(detail)"
    }
}

enum StatusHUDMetrics {
    static let minHeight: CGFloat = DWBMetrics.statusHUDMinHeight
    static let maxWidth: CGFloat = 420
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let leadingPadding: CGFloat = 14
    static let trailingPadding: CGFloat = 18
    static let iconSize: CGFloat = 16
    static let iconGap: CGFloat = 10
    static let lineGap: CGFloat = 1
    static let titleFontSize: CGFloat = 13
    static let detailFontSize: CGFloat = 11

    /// At least `minHeight`; grows when the two text lines plus padding need more.
    static func height(titleHeight: CGFloat, detailHeight: CGFloat) -> CGFloat {
        let lines = titleHeight + (detailHeight > 0 ? lineGap + detailHeight : 0)
        return max(minHeight, topPadding + lines + bottomPadding)
    }
}

// MARK: - Title overlay

enum TitleOverlayMetrics {
    static let compactWidthThreshold: CGFloat = 560
    static let maximumWidth: CGFloat = 800
    static let horizontalPadding: CGFloat = 18
    static let topInset: CGFloat = 20

    static func isCompact(videoWidth: CGFloat) -> Bool { videoWidth < compactWidthThreshold }
    static func height(videoWidth: CGFloat) -> CGFloat { isCompact(videoWidth: videoWidth) ? 38 : 42 }
    static func fontSize(videoWidth: CGFloat) -> CGFloat { isCompact(videoWidth: videoWidth) ? 17 : 20 }

    static func width(textWidth: CGFloat, videoWidth: CGFloat) -> CGFloat {
        let limit = max(0, min(videoWidth - 32, maximumWidth))
        return min(limit, ceil(textWidth) + horizontalPadding * 2)
    }
}

// MARK: - Failure message

enum FailureMessageMetrics {
    static let height: CGFloat = 40
    static let horizontalPadding: CGFloat = 14
    static let iconSize: CGFloat = 16
    static let iconGap: CGFloat = 10
    /// Distance from the top of the video area, which keeps the message just
    /// below the title overlay (20 + 42 + 14).
    static let topInset: CGFloat = 76
    static let hold: TimeInterval = DWBMotion.failureHold

    static let message = "Could not play"

    static func text(filename: String) -> String {
        "\(message) \u{201c}\(filename)\u{201d}"
    }
}

// MARK: - Undo toast

enum UndoToastMetrics {
    static let height: CGFloat = 40
    static let leadingPadding: CGFloat = 14
    static let trailingPadding: CGFloat = 6
    static let gap: CGFloat = 10
    static let iconSize: CGFloat = 15
    static let buttonHeight: CGFloat = 28
    static let buttonRadius: CGFloat = 6
    static let buttonHorizontalPadding: CGFloat = 10
    static let hold: TimeInterval = 3.0
    /// Distance from the bottom of the video area to the bottom of the toast
    /// (the 68 pt rail plus 24 pt).
    static let bottomInset: CGFloat = DWBMetrics.railHeight + 24

    /// A toast is shown for any prefix change: the one-file form names the file, the batch
    /// form (two or more) gives only the count.
    static func shouldShow(forRenamedFileCount count: Int) -> Bool { count >= 1 }

    static func isBatch(renamedFileCount count: Int) -> Bool { count > 1 }

    /// Caption before the count or filename: "Prefix changed: <name>" / "Prefix changed on <N files>".
    static func caption(renamedFileCount count: Int) -> String {
        isBatch(renamedFileCount: count) ? "Prefix changed on" : "Prefix changed:"
    }

    /// The semibold count: "N files". Never lists names.
    static func batchCountText(_ count: Int) -> String { "\(count) files" }

    static func spokenText(renamedFileCount count: Int, filename: String?) -> String {
        if isBatch(renamedFileCount: count) {
            return "Prefix changed on \(count) files. Undo with Command Z."
        }
        return "Prefix changed on \(filename ?? ""). Undo with Command Z."
    }
}

/// Finds the marker prefix a filename starts with, preferring the longer prefix
/// so a shorter one never highlights part of a longer one.
enum MarkerPrefixHighlight {
    enum Kind: Equatable { case primary, secondary }

    struct Match: Equatable {
        let kind: Kind
        let utf16Length: Int
    }

    static func match(in name: String, primary: String, secondary: String) -> Match? {
        let candidates: [(kind: Kind, prefix: String)] = [
            (.primary, PrefixNormalization.normalized(primary)),
            (.secondary, PrefixNormalization.normalized(secondary))
        ]
        .filter { !$0.prefix.isEmpty }
        .sorted { $0.prefix.count > $1.prefix.count }
        guard let found = candidates.first(where: { name.hasPrefix($0.prefix) }) else { return nil }
        return Match(kind: found.kind, utf16Length: (found.prefix as NSString).length)
    }
}

// MARK: - Drop zone

enum DropZoneCopy {
    static let subtitle = "Release to add to the top of the queue."
    static let inset: CGFloat = 12
    static let radius: CGFloat = 12
    static let dashPattern: [NSNumber] = [6, 4]

    static func title(fileCount: Int, folderCount: Int) -> String {
        let total = fileCount + folderCount
        if folderCount > 0 {
            return "Add \(total) item\(total == 1 ? "" : "s") to the queue"
        }
        return "Add \(fileCount) file\(fileCount == 1 ? "" : "s") to the queue"
    }
}

// MARK: - Scrubber

enum ScrubberStyle {
    static let trackHeight = DWBMetrics.scrubberTrack
    static let rangeHeight = DWBMetrics.scrubberRange
    static let tickWidth: CGFloat = 1.5
    static let tickHeight: CGFloat = 8
    static let increaseContrastTrackAlpha: CGFloat = 0.40
    static let increaseContrastTickAlpha: CGFloat = 0.85

    static func trackColor(increaseContrast: Bool) -> NSColor {
        increaseContrast
            ? DWBColor.track.withAlphaComponent(increaseContrastTrackAlpha)
            : DWBColor.track
    }

    static func tickColor(increaseContrast: Bool) -> NSColor {
        increaseContrast
            ? DWBColor.tick.withAlphaComponent(increaseContrastTickAlpha)
            : DWBColor.tick
    }

    /// 6 pt at rest, 8 pt while hovered or dragged; fixed at 6 pt under Reduce Motion.
    static func knobDiameter(emphasized: Bool, reduceMotion: Bool) -> CGFloat {
        emphasized && !reduceMotion ? DWBMetrics.knobEmphasized : DWBMetrics.knob
    }
}

// MARK: - Rail

enum RailMetrics {
    static let horizontalPadding: CGFloat = 16
    static let hairlineHeight: CGFloat = 1
    static let scrubberHeight: CGFloat = 14
    static let scrubberTopPadding: CGFloat = 2
    static let buttonRowHeight: CGFloat = 40
    static let buttonRowBottomPadding: CGFloat = 10
    static let timeLabelFontSize: CGFloat = 10.5

    /// Y of the scrubber frame's bottom edge, measured from the rail's bottom.
    static var scrubberMinY: CGFloat {
        DWBMetrics.railHeight - hairlineHeight - scrubberTopPadding - scrubberHeight
    }

    /// Y of the vertical center of the button row, measured from the rail's bottom.
    static var buttonRowCenterY: CGFloat { buttonRowBottomPadding + buttonRowHeight / 2 }
}
