import Foundation
import XCTest

final class PlaybackCompletionPolicyTests: XCTestCase {

    func testExplicitPauseSuppressesPausedNearEOFCompletionWithoutChangingQueuePolicy() {
        XCTAssertTrue(ExplicitPlayPauseCompletionPolicy.suppressesPausedNearEOFCompletion(for: .pause))
        XCTAssertEqual(
            PlaybackCompletionPolicy(
                isRepeatOne: false,
                currentDisplayIndex: 0,
                displayOrderCount: 2,
                isEndlessShuffleOn: false,
                queueIsEmpty: false
            ).action,
            .playNext
        )
    }

    func testExplicitResumeSuppressesDelayedPausedNearEOFCompletionAndCancelsOnlySyntheticCompletion() {
        XCTAssertTrue(ExplicitPlayPauseCompletionPolicy.suppressesPausedNearEOFCompletion(for: .play))
        XCTAssertTrue(
            ExplicitPlayPauseCompletionPolicy.shouldCancelPendingPausedNearEOFCompletion(
                for: .play,
                naturalEOFDetected: false,
                hasPendingPausedNearEOFCompletion: true
            )
        )
        XCTAssertFalse(
            ExplicitPlayPauseCompletionPolicy.shouldCancelPendingPausedNearEOFCompletion(
                for: .play,
                naturalEOFDetected: true,
                hasPendingPausedNearEOFCompletion: true
            )
        )
    }

    func testNonExplicitPausedNearEOFAndNaturalEOFRemainCompletionEligible() {
        XCTAssertFalse(ExplicitPlayPauseCompletionPolicy.suppressesPausedNearEOFCompletion(for: nil))
        XCTAssertFalse(
            ExplicitPlayPauseCompletionPolicy.shouldCancelPendingPausedNearEOFCompletion(
                for: .pause,
                naturalEOFDetected: false,
                hasPendingPausedNearEOFCompletion: true
            )
        )
    }

    func testRepeatOneReturnsRepeatCurrent() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 2,
            displayOrderCount: 5,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testRepeatOneTakesPriorityOverEndlessShuffle() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isEndlessShuffleOn: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testRepeatOneTakesPriorityWhenMidQueue() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 0,
            displayOrderCount: 3,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testMidQueueReturnsPlayNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 1,
            displayOrderCount: 5,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testFirstOfTwoItemsReturnsPlayNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 2,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testLastItemNoEndlessReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testSingleItemQueueNoModifiersReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testEndlessShuffleWithItemsReturnsEndlessShuffleNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isEndlessShuffleOn: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .endlessShuffleNext)
    }

    func testEndlessShuffleEmptyQueueReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isEndlessShuffleOn: true,
            queueIsEmpty: true
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testEndlessShuffleMidQueueStillAdvancesNormally() {
        // Endless shuffle only fires when at the last item; mid-queue uses playNext.
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 2,
            displayOrderCount: 5,
            isEndlessShuffleOn: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testPlaybackFailureSkipsMidQueueWithoutUsingRepeatOnePolicy() {
        let action = PlaybackFailureAdvancePolicy(
            currentDisplayIndex: 1,
            displayOrderCount: 4,
            isEndlessShuffleOn: false
        ).action
        XCTAssertEqual(action, .skipToNextDistinctItem)
    }

    func testPlaybackFailureStopsAtOrdinaryQueueEnd() {
        let action = PlaybackFailureAdvancePolicy(
            currentDisplayIndex: 3,
            displayOrderCount: 4,
            isEndlessShuffleOn: false
        ).action
        XCTAssertEqual(action, .stopAtEnd)
    }

    func testPlaybackFailureSkipsAtEndOfMultiItemEndlessShuffle() {
        let action = PlaybackFailureAdvancePolicy(
            currentDisplayIndex: 2,
            displayOrderCount: 3,
            isEndlessShuffleOn: true
        ).action
        XCTAssertEqual(action, .skipToNextDistinctItem)
    }

    func testPlaybackFailureNeverRetriesSingleItemEndlessShuffle() {
        let action = PlaybackFailureAdvancePolicy(
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isEndlessShuffleOn: true
        ).action
        XCTAssertEqual(action, .stopAtEnd)
    }

    func testCurrentFailureWithSuccessorIsHandledOnceAndConsecutiveSessionsRemainEligible() {
        let first = PlaybackFailureAttempt(mediaURL: URL(fileURLWithPath: "/queue/B.mp4"), sessionID: 10)
        let action = PlaybackFailureAdvancePolicy(
            currentDisplayIndex: 1,
            displayOrderCount: 4,
            isEndlessShuffleOn: false
        ).action

        XCTAssertEqual(
            PlaybackFailureAdvancePolicy.disposition(
                failedAttempt: first,
                currentURL: first.mediaURL,
                currentSessionID: 10,
                isUserStop: false,
                naturalEOFDetected: false,
                activeFailureAttempt: nil,
                action: action
            ),
            .handle(.skipToNextDistinctItem)
        )

        let second = PlaybackFailureAttempt(mediaURL: URL(fileURLWithPath: "/queue/C.mp4"), sessionID: 11)
        XCTAssertEqual(
            PlaybackFailureAdvancePolicy.disposition(
                failedAttempt: second,
                currentURL: second.mediaURL,
                currentSessionID: 11,
                isUserStop: false,
                naturalEOFDetected: false,
                activeFailureAttempt: nil,
                action: action
            ),
            .handle(.skipToNextDistinctItem)
        )
    }

    func testRepeatedFailureCallbackForCurrentAttemptDoesNotAdvanceTwice() {
        let attempt = PlaybackFailureAttempt(mediaURL: URL(fileURLWithPath: "/queue/B.mp4"), sessionID: 10)
        XCTAssertEqual(
            PlaybackFailureAdvancePolicy.disposition(
                failedAttempt: attempt,
                currentURL: attempt.mediaURL,
                currentSessionID: 10,
                isUserStop: false,
                naturalEOFDetected: false,
                activeFailureAttempt: attempt,
                action: .skipToNextDistinctItem
            ),
            .ignoreDuplicate
        )
    }

    func testStaleFailureAfterNavigationCannotSkipNewCurrentItem() {
        let stale = PlaybackFailureAttempt(mediaURL: URL(fileURLWithPath: "/queue/B.mp4"), sessionID: 10)
        XCTAssertEqual(
            PlaybackFailureAdvancePolicy.disposition(
                failedAttempt: stale,
                currentURL: URL(fileURLWithPath: "/queue/C.mp4"),
                currentSessionID: 11,
                isUserStop: false,
                naturalEOFDetected: false,
                activeFailureAttempt: nil,
                action: .skipToNextDistinctItem
            ),
            .ignoreStaleOrUserStop
        )
    }

    func testStopAndNormalEOFAreNotTreatedAsFailures() {
        let attempt = PlaybackFailureAttempt(mediaURL: URL(fileURLWithPath: "/queue/B.mp4"), sessionID: 10)
        XCTAssertEqual(
            PlaybackFailureAdvancePolicy.disposition(
                failedAttempt: attempt,
                currentURL: attempt.mediaURL,
                currentSessionID: 10,
                isUserStop: true,
                naturalEOFDetected: false,
                activeFailureAttempt: nil,
                action: .skipToNextDistinctItem
            ),
            .ignoreStaleOrUserStop
        )
        XCTAssertEqual(
            PlaybackFailureAdvancePolicy.disposition(
                failedAttempt: attempt,
                currentURL: attempt.mediaURL,
                currentSessionID: 10,
                isUserStop: false,
                naturalEOFDetected: true,
                activeFailureAttempt: nil,
                action: .skipToNextDistinctItem
            ),
            .ignoreStaleOrUserStop
        )
    }

    // MARK: - Mid-playback stall clock

    private let stallTolerance: TimeInterval = 4.0

    func testStallClockPausedForSixtySecondsThenResumedDoesNotStallOnFirstTick() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 12_000, position: 0.25, nowMT: 100.00, toleranceSeconds: stallTolerance))
        // The tick that sees the pause while the player still reports playing.
        XCTAssertNil(clock.stalledSeconds(timeMs: 12_040, position: 0.2501, nowMT: 100.25, toleranceSeconds: stallTolerance))

        clock.playbackPaused()

        // Resumed 60 s later; VLC has not produced a new frame yet, so time is unchanged.
        XCTAssertNil(clock.stalledSeconds(timeMs: 12_040, position: 0.2501, nowMT: 160.25, toleranceSeconds: stallTolerance))
    }

    func testStallClockPlayingWithTimeUnchangedForToleranceStalls() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 5_000, position: 0.5, nowMT: 10.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 5_000, position: 0.5, nowMT: 10.25, toleranceSeconds: stallTolerance))
        let stalled = clock.stalledSeconds(timeMs: 5_000, position: 0.5, nowMT: 14.0, toleranceSeconds: stallTolerance)
        XCTAssertNotNil(stalled)
        XCTAssertEqual(stalled ?? 0, 4.0, accuracy: 0.001)
        XCTAssertNotNil(clock.stalledSeconds(timeMs: 5_000, position: 0.5, nowMT: 20.0, toleranceSeconds: stallTolerance))
    }

    func testStallClockPlayingWithTimeUnchangedBelowToleranceDoesNotStall() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 5_000, position: 0.5, nowMT: 10.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 5_000, position: 0.5, nowMT: 13.75, toleranceSeconds: stallTolerance))
    }

    func testStallClockStallAfterResumeIsStillDetected() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 8_000, position: 0.4, nowMT: 50.0, toleranceSeconds: stallTolerance))
        clock.playbackPaused()

        // Resumed after 60 s, plays for a moment, then freezes.
        XCTAssertNil(clock.stalledSeconds(timeMs: 8_000, position: 0.4, nowMT: 110.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 8_250, position: 0.4003, nowMT: 110.25, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 8_250, position: 0.4003, nowMT: 114.0, toleranceSeconds: stallTolerance))
        let stalled = clock.stalledSeconds(timeMs: 8_250, position: 0.4003, nowMT: 114.25, toleranceSeconds: stallTolerance)
        XCTAssertNotNil(stalled)
        XCTAssertEqual(stalled ?? 0, 4.0, accuracy: 0.001)
    }

    func testStallClockNoMovementForToleranceAfterResumeStalls() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 8_000, position: 0.4, nowMT: 50.0, toleranceSeconds: stallTolerance))
        clock.playbackPaused()

        XCTAssertNil(clock.stalledSeconds(timeMs: 8_000, position: 0.4, nowMT: 110.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 8_000, position: 0.4, nowMT: 113.75, toleranceSeconds: stallTolerance))
        XCTAssertNotNil(clock.stalledSeconds(timeMs: 8_000, position: 0.4, nowMT: 114.0, toleranceSeconds: stallTolerance))
    }

    func testStallClockAdvancingTimeResetsTheClock() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 1_000, position: 0.1, nowMT: 10.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 1_000, position: 0.1, nowMT: 13.5, toleranceSeconds: stallTolerance))
        // Movement just before the tolerance restarts the count from this sample.
        XCTAssertNil(clock.stalledSeconds(timeMs: 1_250, position: 0.1003, nowMT: 13.75, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 1_250, position: 0.1003, nowMT: 17.5, toleranceSeconds: stallTolerance))
        XCTAssertNotNil(clock.stalledSeconds(timeMs: 1_250, position: 0.1003, nowMT: 17.75, toleranceSeconds: stallTolerance))
    }

    func testStallClockPositionAloneAdvancingResetsTheClock() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 2_000, position: 0.2, nowMT: 10.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 2_000, position: 0.2005, nowMT: 20.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 2_000, position: 0.2005, nowMT: 23.75, toleranceSeconds: stallTolerance))
    }

    func testStallClockResetStartsAFreshClock() {
        var clock = MidPlaybackStallClock()
        XCTAssertNil(clock.stalledSeconds(timeMs: 3_000, position: 0.3, nowMT: 10.0, toleranceSeconds: stallTolerance))
        clock.reset()
        XCTAssertNil(clock.stalledSeconds(timeMs: 3_000, position: 0.3, nowMT: 90.0, toleranceSeconds: stallTolerance))
        XCTAssertNil(clock.stalledSeconds(timeMs: 3_000, position: 0.3, nowMT: 93.75, toleranceSeconds: stallTolerance))
        XCTAssertNotNil(clock.stalledSeconds(timeMs: 3_000, position: 0.3, nowMT: 94.0, toleranceSeconds: stallTolerance))
    }
}
