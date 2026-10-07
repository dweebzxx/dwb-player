import Foundation
import XCTest

final class PlayerCommandValidationTests: XCTestCase {
    private func state(
        hasWindow: Bool = true,
        queueCount: Int = 2,
        hasCurrent: Bool = true,
        canRename: Bool = true,
        shuffle: Bool = false,
        endless: Bool = false,
        repeatOne: Bool = false,
        speedTag: Int = 100
    ) -> PlayerCommandState {
        .init(
            hasPlayerWindow: hasWindow,
            queueCount: queueCount,
            hasCurrentMedia: hasCurrent,
            canRenameCurrentMedia: canRename,
            shuffleEnabled: shuffle,
            endlessShuffleEnabled: endless,
            repeatOneEnabled: repeatOne,
            selectedPlaybackSpeedTag: speedTag
        )
    }

    func testVolumePolicyClampsToTwoHundredPercent() {
        XCTAssertEqual(VolumePolicy.clamped(-1), 0)
        XCTAssertEqual(VolumePolicy.clamped(0), 0)
        XCTAssertEqual(VolumePolicy.clamped(100), 100)
        XCTAssertEqual(VolumePolicy.clamped(150), 150)
        XCTAssertEqual(VolumePolicy.clamped(200), 200)
        XCTAssertEqual(VolumePolicy.clamped(201), 200)
    }

    func testVolumeSegmentsPreserveNormalAndExtendedGainBoundary() {
        XCTAssertEqual(VolumePolicy.filledSegmentCount(for: 0, normalSegmentCount: 7, extendedSegmentCount: 4), 0)
        XCTAssertEqual(VolumePolicy.filledSegmentCount(for: 100, normalSegmentCount: 7, extendedSegmentCount: 4), 7)
        XCTAssertEqual(VolumePolicy.filledSegmentCount(for: 101, normalSegmentCount: 7, extendedSegmentCount: 4), 8)
        XCTAssertEqual(VolumePolicy.filledSegmentCount(for: 150, normalSegmentCount: 7, extendedSegmentCount: 4), 9)
        XCTAssertEqual(VolumePolicy.filledSegmentCount(for: 200, normalSegmentCount: 7, extendedSegmentCount: 4), 11)
        XCTAssertEqual(VolumePolicy.filledSegmentCount(for: 250, normalSegmentCount: 7, extendedSegmentCount: 4), 11)
    }

    func testVolumeMeterInputUsesNormalAndExtendedSegmentRanges() {
        let normalBoundary = CGFloat(7) / CGFloat(11)
        XCTAssertEqual(VolumePolicy.volume(forMeterFraction: -0.1, normalSegmentCount: 7, extendedSegmentCount: 4), 0)
        XCTAssertEqual(VolumePolicy.volume(forMeterFraction: normalBoundary, normalSegmentCount: 7, extendedSegmentCount: 4), 100)
        XCTAssertEqual(VolumePolicy.volume(forMeterFraction: (normalBoundary + 1) / 2, normalSegmentCount: 7, extendedSegmentCount: 4), 150)
        XCTAssertEqual(VolumePolicy.volume(forMeterFraction: 1, normalSegmentCount: 7, extendedSegmentCount: 4), 200)
        XCTAssertEqual(VolumePolicy.volume(forMeterFraction: 1.1, normalSegmentCount: 7, extendedSegmentCount: 4), 200)
    }

    func testFileAndQueueCommandsFollowCurrentWindowState() {
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 10, state: state(hasCurrent: false))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 11, state: state(canRename: false))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 12, state: state(hasCurrent: false))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 13, state: state(queueCount: 0))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 13, state: state(queueCount: 1))?.isEnabled, true)
    }

    func testShuffleEndlessAndRepeatExposeEnabledAndCheckedState() {
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 20, state: state(queueCount: 1))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 20, state: state(shuffle: true))?.isOn, true)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 21, state: state(queueCount: 0))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 21, state: state(endless: true))?.isOn, true)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 22, state: state(hasCurrent: false))?.isEnabled, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 22, state: state(repeatOne: true))?.isOn, true)
    }

    func testPlaybackSpeedSelectionUsesPerWindowSpeedTag() {
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 1125, state: state(speedTag: 125))?.isOn, true)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 1100, state: state(speedTag: 125))?.isOn, false)
        XCTAssertEqual(PlayerCommandValidation.result(forTag: 1125, state: state(hasWindow: false, speedTag: 125))?.isEnabled, false)
    }

    func testScrubberProgressAndVisibleKnobUseNativeTravelAtEndpointsAndInteriorPoints() {
        let track = CGRect(x: 0, y: 0, width: 200, height: 3)
        let knobWidth: CGFloat = 20

        let samples: [(position: CGFloat, expectedCenter: CGFloat)] = [
            (0, 10), (0.25, 55), (0.5, 100), (0.75, 145), (1, 190)
        ]
        for (position, expectedCenter) in samples {
            let knob = CGRect(x: expectedCenter - knobWidth / 2, y: -8, width: knobWidth, height: 16)
            let fill = ScrubberTrackGeometry.progressFillRect(trackRect: track, knobRect: knob)
            XCTAssertEqual(fill.maxX, expectedCenter, accuracy: 0.001, "position \(position)")

            let visibleKnob = ScrubberTrackGeometry.visibleKnobRect(trackRect: track, knobRect: knob)
            XCTAssertEqual(visibleKnob.midX, expectedCenter, accuracy: 0.001, "position \(position)")
            XCTAssertEqual(visibleKnob.midY, track.midY, accuracy: 0.001, "position \(position)")
            XCTAssertEqual(visibleKnob.width, 8, accuracy: 0.001)
            XCTAssertEqual(visibleKnob.height, 8, accuracy: 0.001)
        }
    }

    func testScrubberProgressClampsToTrackAndTracksWidthChanges() {
        let narrowTrack = CGRect(x: 0, y: 0, width: 100, height: 3)
        let wideTrack = CGRect(x: 0, y: 0, width: 400, height: 3)

        XCTAssertEqual(
            ScrubberTrackGeometry.progressFillRect(
                trackRect: narrowTrack,
                knobRect: CGRect(x: -20, y: 0, width: 20, height: 16)
            ).maxX,
            narrowTrack.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScrubberTrackGeometry.progressFillRect(
                trackRect: narrowTrack,
                knobRect: CGRect(x: 100, y: 0, width: 20, height: 16)
            ).maxX,
            narrowTrack.maxX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScrubberTrackGeometry.progressFillRect(
                trackRect: wideTrack,
                knobRect: CGRect(x: 190, y: 0, width: 20, height: 16)
            ).maxX,
            200,
            accuracy: 0.001
        )
    }

    func testFolderDropFromOffSelectsShuffle() {
        XCTAssertEqual(FolderDropShufflePolicy.resultingMode(
            currentMode: .off,
            isDragDrop: true,
            containsFolder: true,
            addedPlayableMedia: true
        ), .shuffle)
    }

    func testFolderDropFromEndlessSelectsShuffle() {
        XCTAssertEqual(FolderDropShufflePolicy.resultingMode(
            currentMode: .endless,
            isDragDrop: true,
            containsFolder: true,
            addedPlayableMedia: true
        ), .shuffle)
    }

    func testFolderDropWhileShuffleRemainsShuffle() {
        XCTAssertEqual(FolderDropShufflePolicy.resultingMode(
            currentMode: .shuffle,
            isDragDrop: true,
            containsFolder: true,
            addedPlayableMedia: true
        ), .shuffle)
    }

    func testFolderDropShufflePolicyLeavesFileOnlyEmptyAndNonDropIntakeUnchanged() {
        XCTAssertEqual(FolderDropShufflePolicy.resultingMode(
            currentMode: .endless,
            isDragDrop: true,
            containsFolder: false,
            addedPlayableMedia: true
        ), .endless)
        XCTAssertEqual(FolderDropShufflePolicy.resultingMode(
            currentMode: .off,
            isDragDrop: true,
            containsFolder: true,
            addedPlayableMedia: false
        ), .off)
        XCTAssertEqual(FolderDropShufflePolicy.resultingMode(
            currentMode: .endless,
            isDragDrop: false,
            containsFolder: true,
            addedPlayableMedia: true
        ), .endless)
    }

    func testFolderDropRandomStartUsesNewMediaForEmptyQueueAndCombinedQueueOtherwise() {
        XCTAssertEqual(
            FolderDropShuffleStartPolicy.scope(
                isDragDrop: true,
                containsFolder: true,
                addedPlayableMedia: true,
                queueWasEmpty: true
            ),
            .newlyAddedMedia
        )
        XCTAssertEqual(
            FolderDropShuffleStartPolicy.scope(
                isDragDrop: true,
                containsFolder: true,
                addedPlayableMedia: true,
                queueWasEmpty: false
            ),
            .combinedQueue
        )
        XCTAssertEqual(
            FolderDropShuffleStartPolicy.scope(
                isDragDrop: true,
                containsFolder: false,
                addedPlayableMedia: true,
                queueWasEmpty: false
            ),
            .none
        )
    }
}
