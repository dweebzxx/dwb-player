import XCTest

final class PlaybackStartWindowPolicyTests: XCTestCase {

    private func decide(_ volume: VolumeKind,
                        _ source: PlaybackStartFailureSource,
                        elapsed: TimeInterval,
                        progressSeen: Bool = false,
                        recovery: Bool = true,
                        localExhausted: Bool = false) -> PlaybackStartDecision {
        PlaybackStartWindowPolicy.decide(volume: volume,
                                         source: source,
                                         elapsedSeconds: elapsed,
                                         progressSeen: progressSeen,
                                         recoveryAvailable: recovery,
                                         localAttemptsExhausted: localExhausted)
    }

    func testNamedWindowIsTwentySecondsAndLocalStallIsUnchanged() {
        XCTAssertEqual(PlaybackStartWindowPolicy.nonLocalStartWindowSeconds, 20)
        XCTAssertEqual(PlaybackStartWindowPolicy.stallToleranceSeconds(for: .nonLocal), 20)
        XCTAssertEqual(PlaybackStartWindowPolicy.stallToleranceSeconds(for: .local), 4)
    }

    func testFailureSourcesUseTheLoggedNames() {
        XCTAssertEqual(PlaybackStartFailureSource.handshakeNoPlaying.rawValue, "handshake-no-playing")
        XCTAssertEqual(PlaybackStartFailureSource.handshakeNoProgress.rawValue, "handshake-no-progress")
        XCTAssertEqual(PlaybackStartFailureSource.midPlaybackStall.rawValue, "mid-playback-stall")
        XCTAssertNil(PlaybackStartFailureSource(rawValue: "vlc-error"))
        XCTAssertNil(PlaybackStartFailureSource(rawValue: "paused-before-eof"))
    }

    func testNonLocalStartWaitsTheFullWindowThenRebuildsOnce() {
        for source in [PlaybackStartFailureSource.handshakeNoPlaying, .handshakeNoProgress] {
            XCTAssertEqual(decide(.nonLocal, source, elapsed: 0), .wait)
            XCTAssertEqual(decide(.nonLocal, source, elapsed: 19.9), .wait)
            XCTAssertEqual(decide(.nonLocal, source, elapsed: 20), .rebuild)
            XCTAssertEqual(decide(.nonLocal, source, elapsed: 20, recovery: false), .failAndStop)
            XCTAssertEqual(decide(.nonLocal, source, elapsed: 19.9, recovery: false), .wait)
        }
    }

    func testNonLocalStartNeverSkips() {
        for source in [PlaybackStartFailureSource.handshakeNoPlaying, .handshakeNoProgress, .midPlaybackStall] {
            for elapsed in [0.0, 5, 20, 40, 400] {
                for recovery in [true, false] {
                    XCTAssertNotEqual(decide(.nonLocal, source, elapsed: elapsed, recovery: recovery), .failAndSkip)
                }
            }
        }
    }

    func testNonLocalStallWaitsTwentySecondsThenStops() {
        XCTAssertEqual(decide(.nonLocal, .midPlaybackStall, elapsed: 4.2), .wait)
        XCTAssertEqual(decide(.nonLocal, .midPlaybackStall, elapsed: 19.9), .wait)
        XCTAssertEqual(decide(.nonLocal, .midPlaybackStall, elapsed: 20), .failAndStop)
    }

    func testLocalStallKeepsFourSecondsAndSkips() {
        XCTAssertEqual(decide(.local, .midPlaybackStall, elapsed: 3.9), .wait)
        XCTAssertEqual(decide(.local, .midPlaybackStall, elapsed: 4), .failAndSkip)
        XCTAssertEqual(decide(.local, .midPlaybackStall, elapsed: 4.2, recovery: true), .failAndSkip)
    }

    func testLocalStartFollowsTheExistingRetryCountersNotElapsedTime() {
        for source in [PlaybackStartFailureSource.handshakeNoPlaying, .handshakeNoProgress] {
            XCTAssertEqual(decide(.local, source, elapsed: 500), .wait)
            XCTAssertEqual(decide(.local, source, elapsed: 0.3, localExhausted: true), .rebuild)
            XCTAssertEqual(decide(.local, source, elapsed: 0.3, recovery: false, localExhausted: true), .failAndSkip)
        }
    }

    func testProgressSeenAlwaysWaits() {
        for volume in [VolumeKind.local, .nonLocal] {
            for source in [PlaybackStartFailureSource.handshakeNoPlaying, .handshakeNoProgress, .midPlaybackStall] {
                XCTAssertEqual(decide(volume, source, elapsed: 500, progressSeen: true, localExhausted: true), .wait)
            }
        }
    }

    func testFailureDecisionSkipsLocalAndStopsNonLocal() {
        XCTAssertEqual(PlaybackStartWindowPolicy.failureDecision(volume: .local), .failAndSkip)
        XCTAssertEqual(PlaybackStartWindowPolicy.failureDecision(volume: .nonLocal), .failAndStop)
    }
}
