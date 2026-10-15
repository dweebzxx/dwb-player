import Foundation
import CoreGraphics

/// Shared numeric contract for the existing per-window volume system.
enum VolumePolicy {
    static let minimumVolume: Int32 = 0
    static let normalVolume: Int32 = 100
    static let maximumVolume: Int32 = 200

    static func clamped(_ volume: Int) -> Int32 {
        Int32(max(Int(minimumVolume), min(Int(maximumVolume), volume)))
    }

    static func clamped(_ volume: Int32) -> Int32 {
        clamped(Int(volume))
    }

    /// Maps normal volume across the normal-color segments and software gain
    /// across the extended-color segments without changing the 100% boundary.
    static func filledSegmentCount(for volume: Int32,
                                   normalSegmentCount: Int,
                                   extendedSegmentCount: Int) -> Int {
        guard normalSegmentCount > 0, extendedSegmentCount > 0 else { return 0 }

        let clampedVolume = clamped(volume)
        if clampedVolume == minimumVolume { return 0 }
        if clampedVolume <= normalVolume {
            let fraction = Double(clampedVolume) / Double(normalVolume)
            return min(normalSegmentCount, Int((fraction * Double(normalSegmentCount)).rounded(.up)))
        }

        let extendedRange = maximumVolume - normalVolume
        let extendedFraction = Double(clampedVolume - normalVolume) / Double(extendedRange)
        let filledExtended = Int((extendedFraction * Double(extendedSegmentCount)).rounded(.up))
        return normalSegmentCount + min(extendedSegmentCount, filledExtended)
    }

    /// Converts horizontal HUD input through the same normal/extended segment
    /// boundary used for drawing.
    static func volume(forMeterFraction fraction: CGFloat,
                       normalSegmentCount: Int,
                       extendedSegmentCount: Int) -> Int32 {
        let segmentCount = normalSegmentCount + extendedSegmentCount
        guard normalSegmentCount > 0, extendedSegmentCount > 0, segmentCount > 0 else {
            return minimumVolume
        }

        let clampedFraction = min(1, max(0, fraction))
        let normalBoundary = CGFloat(normalSegmentCount) / CGFloat(segmentCount)
        if clampedFraction <= normalBoundary {
            let normalFraction = clampedFraction / normalBoundary
            return clamped(Int((normalFraction * CGFloat(normalVolume)).rounded()))
        }

        let extendedFraction = (clampedFraction - normalBoundary) / (1 - normalBoundary)
        let volume = CGFloat(normalVolume)
            + extendedFraction * CGFloat(maximumVolume - normalVolume)
        return clamped(Int(volume.rounded()))
    }

    /// The volume a window plays at: 0 while muted, otherwise its stored volume.
    static func effectiveVolume(stored: Int32, muted: Bool) -> Int32 {
        muted ? minimumVolume : clamped(stored)
    }

    /// Converts the Settings slider position to a whole-percent window volume.
    static func volume(forSliderValue value: Double) -> Int32 {
        guard value.isFinite else { return minimumVolume }
        return clamped(Int(min(Double(maximumVolume) + 1, max(Double(minimumVolume) - 1, value)).rounded()))
    }

    /// Settings readout text, for example "150%".
    static func percentText(_ volume: Int32) -> String {
        "\(clamped(volume))%"
    }
}

/// Decides whether a window must write its own volume back to VLC (P137).
///
/// VLC keeps volume state that every player in the process shares, so a new audio
/// output can start at another window's value. The window's cache cannot see that;
/// only VLC's actual value can. A write is needed only when VLC reports a usable
/// value that differs from what this window intends.
enum AudioReassertPolicy {
    /// The volume to write, or nil when no write is needed.
    /// - Parameters:
    ///   - actual: VLC's `audio.volume`. nil or negative means no audio output yet.
    ///   - intended: 0 when the window is muted, otherwise its clamped volume.
    static func valueToWrite(actual: Int32?, intended: Int32) -> Int32? {
        guard let actual, actual >= VolumePolicy.minimumVolume else { return nil }
        return actual == intended ? nil : intended
    }
}

/// Shared geometry for the visual progress point of a scrubber.
///
/// NSSliderCell still owns click and drag tracking, including the inset range
/// through which its knob travels. Drawing must therefore terminate at
/// that knob's center rather than derive a second position from the wider bar.
enum ScrubberTrackGeometry {
    static let visibleKnobDiameter: CGFloat = 8

    static func progressFillRect(trackRect: CGRect, knobRect: CGRect) -> CGRect {
        guard !trackRect.isEmpty else { return .zero }

        let progressX = min(trackRect.maxX, max(trackRect.minX, knobRect.midX))
        return CGRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(0, progressX - trackRect.minX),
            height: trackRect.height
        )
    }

    /// Keeps the compact visual thumb centered on the exact horizontal center
    /// AppKit uses for its tracked knob, while matching the custom rail's
    /// vertical center.
    static func visibleKnobRect(trackRect: CGRect,
                                knobRect: CGRect,
                                diameter: CGFloat = visibleKnobDiameter) -> CGRect {
        guard !trackRect.isEmpty else { return .zero }

        return CGRect(
            x: knobRect.midX - diameter / 2,
            y: trackRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
    }
}

enum FolderDropShuffleMode: Equatable {
    case off
    case shuffle
    case endless
}

enum FolderDropShuffleStartScope: Equatable {
    case none
    case newlyAddedMedia
    case combinedQueue
}

/// Identifies the deliberately narrow case in which a successful drag/drop
/// folder intake must choose the existing Shuffle playback mode.
enum FolderDropShufflePolicy {
    static func resultingMode(currentMode: FolderDropShuffleMode,
                              isDragDrop: Bool,
                              containsFolder: Bool,
                              addedPlayableMedia: Bool) -> FolderDropShuffleMode {
        guard isDragDrop, containsFolder, addedPlayableMedia else { return currentMode }
        return .shuffle
    }
}

/// Keeps random-start selection limited to successful folder drag/drop intake.
enum FolderDropShuffleStartPolicy {
    static func scope(isDragDrop: Bool,
                      containsFolder: Bool,
                      addedPlayableMedia: Bool,
                      queueWasEmpty: Bool) -> FolderDropShuffleStartScope {
        guard isDragDrop, containsFolder, addedPlayableMedia else { return .none }
        return queueWasEmpty ? .newlyAddedMedia : .combinedQueue
    }
}

struct PlayerCommandState: Equatable {
    var hasPlayerWindow: Bool
    var queueCount: Int
    var hasCurrentMedia: Bool
    var canRenameCurrentMedia: Bool
    var shuffleEnabled: Bool
    var endlessShuffleEnabled: Bool
    var repeatOneEnabled: Bool
    var selectedPlaybackSpeedTag: Int
}

struct PlayerCommandValidationResult: Equatable {
    let isEnabled: Bool
    let isOn: Bool?
}

enum PlayerCommandValidation {
    static func result(forTag tag: Int, state: PlayerCommandState) -> PlayerCommandValidationResult? {
        switch tag {
        case 10: // Reveal in Finder
            return .init(isEnabled: state.hasCurrentMedia, isOn: nil)
        case 11: // Rename
            return .init(isEnabled: state.canRenameCurrentMedia, isOn: nil)
        case 12: // Remove Current
            return .init(isEnabled: state.hasCurrentMedia, isOn: nil)
        case 13: // Clear Queue
            return .init(isEnabled: state.queueCount > 0, isOn: nil)
        case 20: // Shuffle
            return .init(isEnabled: state.queueCount > 1, isOn: state.shuffleEnabled)
        case 21: // Endless Shuffle
            return .init(isEnabled: state.queueCount > 0, isOn: state.endlessShuffleEnabled)
        case 22: // Repeat One
            return .init(isEnabled: state.hasCurrentMedia, isOn: state.repeatOneEnabled)
        case 1000...1999: // Playback speed items
            return .init(
                isEnabled: state.hasPlayerWindow,
                isOn: tag - 1000 == state.selectedPlaybackSpeedTag
            )
        default:
            return nil
        }
    }
}
