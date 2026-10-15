import Foundation

/// Which failure is being judged.
enum PlaybackStartFailureSource: String {
    case handshakeNoPlaying = "handshake-no-playing"
    case handshakeNoProgress = "handshake-no-progress"
    case midPlaybackStall = "mid-playback-stall"
}

enum PlaybackStartDecision: Equatable {
    /// Keep waiting; do not touch the player.
    case wait
    /// Build one fresh player and wait again.
    case rebuild
    /// The item failed: mark it failed and move to the next one (local files).
    case failAndSkip
    /// The item failed: mark it failed and stay on it (non-local files).
    case failAndStop
}

/// How long a start or a stall is given, and what happens when it runs out. A file on a
/// non-local volume gets one long window and, if it still fails, playback stops on it instead of
/// re-opening the next files on the same volume. Local files keep the existing timings and skip.
enum PlaybackStartWindowPolicy {
    /// How long a non-local file may take to reach its first `.playing` state with media time
    /// greater than 0, and how long its time may stand still mid-playback. Also the wait after the
    /// one-time player rebuild.
    static let nonLocalStartWindowSeconds: TimeInterval = 20
    /// Local mid-playback stall tolerance (unchanged).
    static let localStallToleranceSeconds: TimeInterval = 4

    static func stallToleranceSeconds(for volume: VolumeKind) -> TimeInterval {
        volume == .nonLocal ? nonLocalStartWindowSeconds : localStallToleranceSeconds
    }

    /// What a failed item does once its failure is confirmed.
    static func failureDecision(volume: VolumeKind) -> PlaybackStartDecision {
        volume == .nonLocal ? .failAndStop : .failAndSkip
    }

    /// - Parameters:
    ///   - elapsedSeconds: for a handshake, time since `play()` or since the rebuild; for a stall,
    ///     how long time and position have stood still.
    ///   - progressSeen: `.playing` with media time greater than 0 has been seen. Nothing to decide.
    ///   - recoveryAvailable: the one-time player rebuild has not been used and the transition allows it.
    ///   - localAttemptsExhausted: for local files only, the handshake's retry counters have run out
    ///     (the existing 0.35 s check, 2 `play()` retries); local files do not use elapsed time to start.
    static func decide(volume: VolumeKind,
                       source: PlaybackStartFailureSource,
                       elapsedSeconds: TimeInterval,
                       progressSeen: Bool,
                       recoveryAvailable: Bool,
                       localAttemptsExhausted: Bool = false) -> PlaybackStartDecision {
        guard !progressSeen else { return .wait }

        switch (volume, source) {
        case (_, .midPlaybackStall):
            return elapsedSeconds >= stallToleranceSeconds(for: volume)
                ? failureDecision(volume: volume) : .wait
        case (.nonLocal, _):
            guard elapsedSeconds >= nonLocalStartWindowSeconds else { return .wait }
            return recoveryAvailable ? .rebuild : failureDecision(volume: .nonLocal)
        case (.local, _):
            guard localAttemptsExhausted else { return .wait }
            return recoveryAvailable ? .rebuild : failureDecision(volume: .local)
        }
    }
}
