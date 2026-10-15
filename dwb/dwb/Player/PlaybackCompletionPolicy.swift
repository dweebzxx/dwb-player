import Foundation

enum PlaybackCompletionAction: String {
    case repeatCurrent
    case playNext
    case endlessShuffleNext
    case stopLastItem
    case ignoredUserStop
}

/// Failure advancement deliberately differs from normal completion: a media error
/// never repeats the failed item, even when Repeat One is active. At the end of
/// an Endless Shuffle cycle, a one-item queue also stops rather than retrying it.
enum PlaybackFailureAdvanceAction: Equatable {
    case skipToNextDistinctItem
    case stopAtEnd
}

/// The queue item and media-start session that emitted a failure signal. This
/// value lets equivalent VLC and handshake callbacks share one decision while
/// keeping later playback attempts for the same URL distinct.
struct PlaybackFailureAttempt: Equatable {
    let mediaURL: URL
    let sessionID: Int
}

enum PlaybackFailureEventDisposition: Equatable {
    case ignoreStaleOrUserStop
    case ignoreDuplicate
    case handle(PlaybackFailureAdvanceAction)
}

struct PlaybackFailureAdvancePolicy {
    let currentDisplayIndex: Int
    let displayOrderCount: Int
    let isEndlessShuffleOn: Bool

    var action: PlaybackFailureAdvanceAction {
        guard currentDisplayIndex >= 0,
              currentDisplayIndex < displayOrderCount,
              displayOrderCount > 1 else {
            return .stopAtEnd
        }
        if currentDisplayIndex < displayOrderCount - 1 {
            return .skipToNextDistinctItem
        }
        return isEndlessShuffleOn ? .skipToNextDistinctItem : .stopAtEnd
    }

    /// A delayed callback can only affect its original, still-current attempt.
    static func disposition(
        failedAttempt: PlaybackFailureAttempt,
        currentURL: URL?,
        currentSessionID: Int,
        isUserStop: Bool,
        naturalEOFDetected: Bool,
        activeFailureAttempt: PlaybackFailureAttempt?,
        action: PlaybackFailureAdvanceAction
    ) -> PlaybackFailureEventDisposition {
        guard !isUserStop,
              !naturalEOFDetected,
              failedAttempt.sessionID == currentSessionID,
              currentURL?.standardizedFileURL.path == failedAttempt.mediaURL.standardizedFileURL.path else {
            return .ignoreStaleOrUserStop
        }
        guard activeFailureAttempt != failedAttempt else {
            return .ignoreDuplicate
        }
        return .handle(action)
    }
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

/// Stall clock for the mid-playback stall watchdog: VLC keeps reporting "playing"
/// but time and position have not moved. Samples are fed only while the player
/// reports playing, so the clock must be told when playback pauses; otherwise the
/// first sample after a resume would be measured against the last frame before
/// the pause.
struct MidPlaybackStallClock: Equatable {
    private var lastTimeMs = -1
    private var lastPosition: Float = -1
    private var lastAdvanceMT: TimeInterval = 0

    /// Forgets the baseline so the next sample starts a fresh clock.
    mutating func reset() {
        lastTimeMs = -1
        lastPosition = -1
        lastAdvanceMT = 0
    }

    /// The player stopped reporting playing (a pause). The next playing sample
    /// starts a new clock instead of continuing the one from before the pause.
    mutating func playbackPaused() {
        reset()
    }

    /// Records one sample taken while playing. Returns how long time and position
    /// have been unchanged once that reaches `toleranceSeconds`, otherwise nil.
    mutating func stalledSeconds(timeMs: Int,
                                 position: Float,
                                 nowMT: TimeInterval,
                                 toleranceSeconds: TimeInterval) -> TimeInterval? {
        let advanced = lastTimeMs < 0
            || timeMs != lastTimeMs
            || (position.isFinite && lastPosition.isFinite && position != lastPosition)

        if advanced {
            lastPosition = position
            lastTimeMs = timeMs
            lastAdvanceMT = nowMT
            return nil
        }

        guard lastAdvanceMT > 0 else {
            lastAdvanceMT = nowMT
            return nil
        }

        let stalledFor = nowMT - lastAdvanceMT
        return stalledFor >= toleranceSeconds ? stalledFor : nil
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
