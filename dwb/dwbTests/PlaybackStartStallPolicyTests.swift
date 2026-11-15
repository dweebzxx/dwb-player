import XCTest

final class PlaybackStartStallPolicyTests: XCTestCase {

    // MARK: - Single start (R2b)

    private func warns(startedAt: TimeInterval = 100,
                       now: TimeInterval,
                       playingSeen: Bool = false,
                       watched: Int = 7,
                       current: Int = 7,
                       volume: VolumeKind = .local,
                       alreadyWarned: Bool = false) -> Bool {
        PlaybackStartStallPolicy.shouldWarnStalledStart(startedAt: startedAt,
                                                        now: now,
                                                        playingSeen: playingSeen,
                                                        watchedSession: watched,
                                                        currentSession: current,
                                                        volume: volume,
                                                        alreadyWarned: alreadyWarned)
    }

    func testStallValuesAreFiveSecondsAndThree() {
        XCTAssertEqual(PlaybackStartStallPolicy.stallSeconds, 5.0)
        XCTAssertEqual(PlaybackStartStallPolicy.streakThreshold, 3)
    }

    func testNoWarningBeforeFiveSeconds() {
        XCTAssertFalse(warns(now: 100))
        XCTAssertFalse(warns(now: 104.99))
    }

    func testWarnsAtAndAfterFiveSecondsWithoutPlaying() {
        XCTAssertTrue(warns(now: 105))
        XCTAssertTrue(warns(now: 130))
    }

    func testNoWarningWhenPlayingWasSeen() {
        XCTAssertFalse(warns(now: 110, playingSeen: true))
    }

    func testNoWarningForADifferentSession() {
        XCTAssertFalse(warns(now: 110, watched: 7, current: 8))
    }

    func testNoSecondWarningForTheSameSession() {
        XCTAssertFalse(warns(now: 110, alreadyWarned: true))
    }

    func testNonLocalVolumeNeverWarnsOnThisPath() {
        XCTAssertFalse(warns(now: 105, volume: .nonLocal))
        XCTAssertFalse(warns(now: 500, volume: .nonLocal))
    }

    // MARK: - Streak (R2c)

    func testTwoFailedStartsDoNotWarn() {
        var streak = PlaybackStartStallPolicy.Streak()
        XCTAssertFalse(streak.startFailed())
        XCTAssertFalse(streak.startFailed())
        XCTAssertEqual(streak.count, 2)
    }

    func testThirdFailedStartWarnsAndFourthDoesNot() {
        var streak = PlaybackStartStallPolicy.Streak()
        _ = streak.startFailed()
        _ = streak.startFailed()
        XCTAssertTrue(streak.startFailed())
        XCTAssertFalse(streak.startFailed())
        XCTAssertFalse(streak.startFailed())
    }

    func testPlayingResetsTheCountAndThreeMoreFailuresWarnAgain() {
        var streak = PlaybackStartStallPolicy.Streak()
        _ = streak.startFailed()
        _ = streak.startFailed()
        XCTAssertTrue(streak.startFailed())

        streak.playingSeen()
        XCTAssertEqual(streak.count, 0)

        XCTAssertFalse(streak.startFailed())
        XCTAssertFalse(streak.startFailed())
        XCTAssertTrue(streak.startFailed())
    }

    // MARK: - Watch: one session counts once (R2c)

    private final class Harness {
        var session = 0
        var state = 0
        var clock: TimeInterval = 1000
        var lines: [String] = []
        lazy var watch = PlaybackStartStallWatch(currentSession: { [unowned self] in self.session },
                                                 lastSeenStateRaw: { [unowned self] in self.state },
                                                 now: { [unowned self] in self.clock },
                                                 emitWarning: { [unowned self] in self.lines.append($0) })

        func start(_ file: String, volume: VolumeKind = .local) {
            session += 1
            watch.videoStarted(windowID: "player-1", session: session, file: file, volume: volume)
        }
    }

    func testSessionThatTimedOutAndWasReplacedCountsOnce() {
        let h = Harness()
        h.start("a.mp4")
        h.clock += 5
        h.watch.stallTimerFired(session: h.session)            // start-stalled; counts a.mp4 (1)
        XCTAssertEqual(h.lines.count, 1)
        XCTAssertTrue(h.lines[0].hasPrefix("start-stalled: window=player-1 file=a.mp4 session=1 state=0 secondsSinceStart=5.0"))

        h.start("b.mp4")                                       // replaces a.mp4: must not count it again
        h.start("c.mp4")                                       // ends b.mp4 (2)
        XCTAssertEqual(h.lines.count, 1)
        h.start("d.mp4")                                       // ends c.mp4 (3) -> streak
        XCTAssertEqual(h.lines.count, 2)
        XCTAssertEqual(h.lines[1], "start-stalled-streak: window=player-1 count=3 lastFile=c.mp4 lastSession=3 state=0")
    }

    func testStreakWarnsOnceThenPlayingResetsIt() {
        let h = Harness()
        for name in ["a", "b", "c", "d", "e"] { h.start(name) }   // a, b, c, d end without playing
        XCTAssertEqual(h.lines.filter { $0.hasPrefix("start-stalled-streak") }.count, 1)

        h.watch.playingSeen(session: h.session)                    // e plays: streak over
        h.start("f")                                               // ends e (played): not counted
        h.start("g")
        h.start("h")
        XCTAssertEqual(h.lines.filter { $0.hasPrefix("start-stalled-streak") }.count, 1)
        h.start("i")                                               // f, g, h failed -> second streak warning
        XCTAssertEqual(h.lines.filter { $0.hasPrefix("start-stalled-streak") }.count, 2)
    }

    func testPlayingBeforeTheTimerSuppressesTheWarning() {
        let h = Harness()
        h.start("a.mp4")
        h.watch.playingSeen(session: h.session)
        h.clock += 6
        h.watch.stallTimerFired(session: h.session)
        XCTAssertTrue(h.lines.isEmpty)
    }

    func testTimerForAReplacedSessionDoesNothing() {
        let h = Harness()
        h.start("a.mp4")
        let old = h.session
        h.start("b.mp4")
        h.clock += 6
        h.watch.stallTimerFired(session: old)
        XCTAssertTrue(h.lines.isEmpty)
    }

    func testNonLocalStartWritesNoStallLineButCountsInTheStreak() {
        let h = Harness()
        h.start("a.mkv", volume: .nonLocal)
        h.clock += 60
        h.watch.stallTimerFired(session: h.session)
        XCTAssertTrue(h.lines.isEmpty)

        h.start("b.mkv", volume: .nonLocal)
        h.start("c.mkv", volume: .nonLocal)
        h.watch.windowClosed()                                     // ends c: third failure
        XCTAssertEqual(h.lines.count, 1)
        XCTAssertTrue(h.lines[0].hasPrefix("start-stalled-streak: window=player-1 count=3 lastFile=c.mkv"))
    }

    func testImageStartEndsTheVideoSessionAndCountsIt() {
        let h = Harness()
        h.start("a.mp4")
        h.start("b.mp4")
        h.start("c.mp4")
        h.session += 1
        h.watch.nonVideoSessionStarted()                           // ends c: third failure
        XCTAssertEqual(h.lines.count, 1)
        XCTAssertTrue(h.lines[0].hasPrefix("start-stalled-streak: window=player-1 count=3 lastFile=c.mp4"))
    }
}
