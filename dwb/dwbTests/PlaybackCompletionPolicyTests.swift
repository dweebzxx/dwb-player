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
}
