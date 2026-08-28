import Foundation

enum PlaybackCompletionAction: String {
    case repeatCurrent
    case playNext
    case endlessShuffleNext
    case stopLastItem
    case ignoredUserStop
}

/// Captures the target state of a direct Play/Pause command while VLCKit is
/// delivering its asynchronous state notification. A direct user command must
/// win over the paused-near-EOF fallback, which is reserved for a real
/// completion transition that happens to surface as `.paused`.
enum ExplicitPlayPauseTarget: Equatable {
    case play
    case pause
}

/// Keeps direct play/pause intent separate from genuine completion signals.
/// This is deliberately independent of position thresholds: those thresholds
/// remain only for the pre-existing paused-near-EOF fallback.
enum ExplicitPlayPauseCompletionPolicy {
    static func suppressesPausedNearEOFCompletion(
        for target: ExplicitPlayPauseTarget?
    ) -> Bool {
        target != nil
    }

    static func shouldCancelPendingPausedNearEOFCompletion(
        for target: ExplicitPlayPauseTarget,
        naturalEOFDetected: Bool,
        hasPendingPausedNearEOFCompletion: Bool
    ) -> Bool {
        target == .play
            && !naturalEOFDetected
            && hasPendingPausedNearEOFCompletion
    }
}

struct PlaybackCompletionPolicy {
    let isRepeatOne: Bool
    let currentDisplayIndex: Int
    let displayOrderCount: Int
    let isEndlessShuffleOn: Bool
    let queueIsEmpty: Bool

    var action: PlaybackCompletionAction {
        if isRepeatOne { return .repeatCurrent }
        if currentDisplayIndex < displayOrderCount - 1 { return .playNext }
        if isEndlessShuffleOn && !queueIsEmpty { return .endlessShuffleNext }
        return .stopLastItem
    }
}
