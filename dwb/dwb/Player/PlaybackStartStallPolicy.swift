import Foundation

/// P146: pure decisions for the "a start never reached `.playing`" console warnings.
/// No AppKit, no VLCKit. The window feeds it values it already holds.
enum PlaybackStartStallPolicy {
    /// A local video start that has not seen `.playing` this long after its `videoStart` line warns once.
    static let stallSeconds: TimeInterval = 5.0
    /// Consecutive video starts that ended without `.playing` before the streak warning.
    static let streakThreshold = 3

    /// Single start: warn exactly once, for the watched session only, for a local file only.
    /// A non-local file (P142) has its own long window and its own console lines, so it never warns here.
    static func shouldWarnStalledStart(startedAt: TimeInterval,
                                       now: TimeInterval,
                                       playingSeen: Bool,
                                       watchedSession: Int,
                                       currentSession: Int,
                                       volume: VolumeKind,
                                       alreadyWarned: Bool) -> Bool {
        guard volume == .local,
              !playingSeen,
              !alreadyWarned,
              watchedSession == currentSession else { return false }
        return now - startedAt >= stallSeconds
    }

    /// Consecutive failed video starts. Each session is reported to it once.
    struct Streak: Equatable {
        private(set) var count = 0
        private(set) var warned = false

        /// A video start's session ended (or timed out) without `.playing`.
        /// Returns true when the streak warning is due now: once, until `playingSeen()` resets it.
        mutating func startFailed() -> Bool {
            count += 1
            guard count >= PlaybackStartStallPolicy.streakThreshold, !warned else { return false }
            warned = true
            return true
        }

        /// `.playing` arrived: the streak is over.
        mutating func playingSeen() {
            count = 0
            warned = false
        }
    }
}

/// P146: one per window. Writes console warnings only; it never touches the player and never
/// changes playback. It reads only the values below, which the window supplies. The one timer is
/// a single non-repeating, cancellable work item on the main queue. Main thread only.
final class PlaybackStartStallWatch {
    private struct Watched {
        let windowID: String
        let session: Int
        let file: String
        let startedAt: TimeInterval
        let volume: VolumeKind
        var playingSeen = false
        var warned = false
        var counted = false
    }

    private var watched: Watched?
    private var streak = PlaybackStartStallPolicy.Streak()
    private var workItem: DispatchWorkItem?

    private let currentSession: () -> Int
    private let lastSeenStateRaw: () -> Int
    private let now: () -> TimeInterval
    private let emitWarning: (String) -> Void

    init(currentSession: @escaping () -> Int,
         lastSeenStateRaw: @escaping () -> Int,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         emitWarning: @escaping (String) -> Void) {
        self.currentSession = currentSession
        self.lastSeenStateRaw = lastSeenStateRaw
        self.now = now
        self.emitWarning = emitWarning
    }

    /// A video start was logged. Ends the previous session's watch, then watches this one.
    /// A local file gets the 5 s timer; a non-local file gets none.
    func videoStarted(windowID: String, session: Int, file: String, volume: VolumeKind) {
        endWatched()
        watched = Watched(windowID: windowID, session: session, file: file,
                          startedAt: now(), volume: volume)
        guard volume == .local else { return }
        let item = DispatchWorkItem { [weak self] in self?.stallTimerFired(session: session) }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + PlaybackStartStallPolicy.stallSeconds, execute: item)
    }

    /// An image or GIF start replaced the session.
    func nonVideoSessionStarted() {
        endWatched()
    }

    /// `.playing` arrived for `session`: cancel the timer and end the streak.
    func playingSeen(session: Int) {
        guard var current = watched, current.session == session else { return }
        current.playingSeen = true
        watched = current
        cancelTimer()
        streak.playingSeen()
    }

    /// The window closed: cancel the timer and settle the open session.
    func windowClosed() {
        endWatched()
    }

    // MARK: - Private

    private func cancelTimer() {
        workItem?.cancel()
        workItem = nil
    }

    /// The timer's body. Internal so unit tests can drive it with an injected clock.
    func stallTimerFired(session: Int) {
        workItem = nil
        guard var current = watched, current.session == session else { return }
        let nowValue = now()
        guard PlaybackStartStallPolicy.shouldWarnStalledStart(startedAt: current.startedAt,
                                                              now: nowValue,
                                                              playingSeen: current.playingSeen,
                                                              watchedSession: current.session,
                                                              currentSession: currentSession(),
                                                              volume: current.volume,
                                                              alreadyWarned: current.warned) else { return }
        current.warned = true
        emitWarning("start-stalled: window=\(current.windowID) file=\(current.file) session=\(current.session) state=\(lastSeenStateRaw()) secondsSinceStart=\(String(format: "%.1f", nowValue - current.startedAt))")
        countFailure(&current)
        watched = current
    }

    /// The watched session ended (replaced, or the window closed). Counts it once if it never played.
    private func endWatched() {
        cancelTimer()
        guard var ended = watched else { return }
        watched = nil
        if !ended.playingSeen { countFailure(&ended) }
    }

    private func countFailure(_ item: inout Watched) {
        guard !item.counted else { return }
        item.counted = true
        if streak.startFailed() {
            emitWarning("start-stalled-streak: window=\(item.windowID) count=\(streak.count) lastFile=\(item.file) lastSession=\(item.session) state=\(lastSeenStateRaw())")
        }
    }
}
