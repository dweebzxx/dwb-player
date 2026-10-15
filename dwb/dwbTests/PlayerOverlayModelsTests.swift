import AppKit
import XCTest

final class PlayerOverlayModelsTests: XCTestCase {

    // MARK: Volume HUD

    func testHeatFractionIsZeroUpToOneFiftyThenRisesToOneAtTwoHundred() {
        XCTAssertEqual(VolumeHUDModel.heatFraction(volume: 0), 0)
        XCTAssertEqual(VolumeHUDModel.heatFraction(volume: 100), 0)
        XCTAssertEqual(VolumeHUDModel.heatFraction(volume: 150), 0)
        XCTAssertEqual(VolumeHUDModel.heatFraction(volume: 175), 0.5, accuracy: 0.0001)
        XCTAssertEqual(VolumeHUDModel.heatFraction(volume: 200), 1, accuracy: 0.0001)
        XCTAssertEqual(VolumeHUDModel.heatFraction(volume: 250), 1, accuracy: 0.0001)
    }

    func testSegmentFillMatchesSevenNormalAndFourBoostSegments() {
        func lit(_ volume: Int32) -> Int {
            (0..<VolumeHUDModel.segmentCount).filter { VolumeHUDModel.isLit(segment: $0, volume: volume) }.count
        }
        XCTAssertEqual(VolumeHUDModel.segmentCount, 11)
        XCTAssertEqual(lit(0), 0)
        XCTAssertEqual(lit(100), 7)
        XCTAssertEqual(lit(125), 8)
        XCTAssertEqual(lit(150), 9)
        XCTAssertEqual(lit(175), 10)
        XCTAssertEqual(lit(200), 11)
        // Lit segments are always a prefix of the meter.
        XCTAssertTrue(VolumeHUDModel.isLit(segment: 6, volume: 100))
        XCTAssertFalse(VolumeHUDModel.isLit(segment: 7, volume: 100))
    }

    func testSegmentColorsUseMarkerRolesAndBlendTowardErrorFromOneFifty() {
        let theme = DWBTheme.player
        XCTAssertEqual(VolumeHUDModel.litColor(segment: 0, volume: 100, theme: theme), theme.markerPrimary)
        XCTAssertEqual(VolumeHUDModel.litColor(segment: 6, volume: 150, theme: theme), theme.markerPrimary)
        XCTAssertEqual(VolumeHUDModel.litColor(segment: 7, volume: 125, theme: theme), theme.markerSecondary)
        XCTAssertEqual(VolumeHUDModel.litColor(segment: 10, volume: 150, theme: theme), theme.markerSecondary)

        // At 200% every segment is the error fill; at 175% it is halfway there.
        for index in 0..<VolumeHUDModel.segmentCount {
            assertColor(VolumeHUDModel.litColor(segment: index, volume: 200, theme: theme), equals: DWBColor.errorFill)
        }
        let half = VolumeHUDModel.litColor(segment: 0, volume: 175, theme: theme)
        let expected = theme.markerPrimary.blended(withFraction: 0.5, of: DWBColor.errorFill)!
        assertColor(half, equals: expected)
    }

    func testMeterGeometryHasTwoGroupsAndAGap() {
        XCTAssertEqual(VolumeHUDModel.normalGroupWidth, 7 * 11 + 6 * 4)
        XCTAssertEqual(VolumeHUDModel.boostGroupWidth, 4 * 11 + 3 * 4)
        XCTAssertEqual(VolumeHUDModel.meterWidth, VolumeHUDModel.normalGroupWidth + 12 + VolumeHUDModel.boostGroupWidth)
        XCTAssertEqual(VolumeHUDModel.segmentMinX(0), 0)
        XCTAssertEqual(VolumeHUDModel.segmentMinX(6), 6 * 15)
        XCTAssertEqual(VolumeHUDModel.segmentMinX(7), VolumeHUDModel.normalGroupWidth + 12)
        XCTAssertEqual(VolumeHUDModel.segmentMinX(10), VolumeHUDModel.normalGroupWidth + 12 + 3 * 15)
    }

    func testPointerPositionsMapAcrossTheGroupGapToVolumes() {
        func volume(atX x: CGFloat) -> Int32 {
            VolumePolicy.volume(forMeterFraction: VolumeHUDModel.meterFraction(forX: x),
                                normalSegmentCount: VolumeHUDModel.normalSegmentCount,
                                extendedSegmentCount: VolumeHUDModel.boostSegmentCount)
        }
        XCTAssertEqual(volume(atX: -20), 0)
        XCTAssertEqual(volume(atX: 0), 0)
        XCTAssertEqual(volume(atX: VolumeHUDModel.normalGroupWidth), 100)
        // Anywhere in the gap holds the 100% boundary.
        XCTAssertEqual(volume(atX: VolumeHUDModel.normalGroupWidth + 6), 100)
        XCTAssertEqual(volume(atX: VolumeHUDModel.normalGroupWidth + 12), 100)
        XCTAssertEqual(volume(atX: VolumeHUDModel.meterWidth), 200)
        XCTAssertEqual(volume(atX: VolumeHUDModel.meterWidth + 40), 200)
        let boostMiddle = VolumeHUDModel.normalGroupWidth + 12 + VolumeHUDModel.boostGroupWidth / 2
        XCTAssertEqual(volume(atX: boostMiddle), 150)
    }

    // MARK: Backings and contrast

    func testIncreaseContrastMakesEveryBackingOpaque() {
        for backing in [DWBColor.backingChrome, DWBColor.backingHUD, DWBColor.backingTitle] {
            XCTAssertLessThan(backing.alphaComponent, 1)
            XCTAssertEqual(OverlayBacking.resolved(backing, increaseContrast: true).alphaComponent, 1)
            XCTAssertEqual(OverlayBacking.resolved(backing, increaseContrast: false), backing)
        }
    }

    func testScrubberTrackAndTickAlphaStrengthenUnderIncreaseContrast() {
        XCTAssertEqual(ScrubberStyle.trackColor(increaseContrast: false).alphaComponent, 0.18, accuracy: 0.0001)
        XCTAssertEqual(ScrubberStyle.trackColor(increaseContrast: true).alphaComponent, 0.40, accuracy: 0.0001)
        XCTAssertEqual(ScrubberStyle.tickColor(increaseContrast: false).alphaComponent, 0.55, accuracy: 0.0001)
        XCTAssertEqual(ScrubberStyle.tickColor(increaseContrast: true).alphaComponent, 0.85, accuracy: 0.0001)
    }

    func testKnobGrowsOnlyWhenEmphasizedAndMotionIsAllowed() {
        XCTAssertEqual(ScrubberStyle.knobDiameter(emphasized: false, reduceMotion: false), 6)
        XCTAssertEqual(ScrubberStyle.knobDiameter(emphasized: true, reduceMotion: false), 8)
        XCTAssertEqual(ScrubberStyle.knobDiameter(emphasized: true, reduceMotion: true), 6)
        XCTAssertEqual(ScrubberStyle.knobDiameter(emphasized: false, reduceMotion: true), 6)
    }

    func testKnobStaysCenteredOnAppKitKnobPositionAtEitherSize() {
        let track = CGRect(x: 0, y: 6, width: 400, height: 2)
        let appKitKnob = CGRect(x: 90, y: 0, width: 21, height: 14)
        for diameter in [CGFloat(6), 8] {
            let knob = ScrubberTrackGeometry.visibleKnobRect(trackRect: track, knobRect: appKitKnob, diameter: diameter)
            XCTAssertEqual(knob.midX, appKitKnob.midX, accuracy: 0.0001)
            XCTAssertEqual(knob.midY, track.midY, accuracy: 0.0001)
            XCTAssertEqual(knob.width, diameter)
        }
        // The default diameter is unchanged from P115.
        let defaulted = ScrubberTrackGeometry.visibleKnobRect(trackRect: track, knobRect: appKitKnob)
        XCTAssertEqual(defaulted.width, ScrubberTrackGeometry.visibleKnobDiameter)
    }

    // MARK: Rail

    func testRailLayoutFitsSixtyEightPoints() {
        XCTAssertEqual(DWBMetrics.railHeight, 68)
        XCTAssertEqual(RailMetrics.scrubberMinY, 51)
        XCTAssertEqual(RailMetrics.scrubberMinY + RailMetrics.scrubberHeight + RailMetrics.scrubberTopPadding + RailMetrics.hairlineHeight,
                       DWBMetrics.railHeight)
        // The 36 pt play button fits inside the 40 pt row beneath the scrubber.
        let top = RailMetrics.buttonRowCenterY + DWBMetrics.railButtonPrimary / 2
        let bottom = RailMetrics.buttonRowCenterY - DWBMetrics.railButtonPrimary / 2
        XCTAssertLessThan(top, RailMetrics.scrubberMinY)
        XCTAssertGreaterThanOrEqual(bottom, 0)
    }

    // MARK: Title overlay

    func testTitleOverlayMetricsSwitchToCompactBelowFiveSixty() {
        XCTAssertEqual(TitleOverlayMetrics.height(videoWidth: 560), 42)
        XCTAssertEqual(TitleOverlayMetrics.fontSize(videoWidth: 560), 20)
        XCTAssertEqual(TitleOverlayMetrics.height(videoWidth: 559), 38)
        XCTAssertEqual(TitleOverlayMetrics.fontSize(videoWidth: 559), 17)
    }

    func testTitleOverlayWidthAddsPaddingAndCapsAtEightHundred() {
        XCTAssertEqual(TitleOverlayMetrics.width(textWidth: 200, videoWidth: 1000), 236)
        XCTAssertEqual(TitleOverlayMetrics.width(textWidth: 5000, videoWidth: 2000), 800)
        XCTAssertEqual(TitleOverlayMetrics.width(textWidth: 5000, videoWidth: 500), 468)
    }

    // MARK: Failure message and toast

    func testFailureMessageKeepsExistingWordingAndHoldsThreeSeconds() {
        XCTAssertEqual(FailureMessageMetrics.text(filename: "a.mp4"), "Could not play \u{201c}a.mp4\u{201d}")
        XCTAssertEqual(FailureMessageMetrics.hold, 3.0)
        XCTAssertEqual(FailureMessageMetrics.height, 40)
    }

    func testUndoToastShowsForAnyPrefixChangeAndIsBatchFromTwoFiles() {
        XCTAssertFalse(UndoToastMetrics.shouldShow(forRenamedFileCount: 0))
        XCTAssertTrue(UndoToastMetrics.shouldShow(forRenamedFileCount: 1))
        XCTAssertTrue(UndoToastMetrics.shouldShow(forRenamedFileCount: 2))
        XCTAssertFalse(UndoToastMetrics.isBatch(renamedFileCount: 1))
        XCTAssertTrue(UndoToastMetrics.isBatch(renamedFileCount: 2))
        XCTAssertEqual(UndoToastMetrics.hold, 3.0)
    }

    func testUndoToastBatchCopyNeverListsNames() {
        XCTAssertEqual(UndoToastMetrics.caption(renamedFileCount: 1), "Prefix changed:")
        XCTAssertEqual(UndoToastMetrics.caption(renamedFileCount: 3), "Prefix changed on")
        XCTAssertEqual(UndoToastMetrics.batchCountText(3), "3 files")
        XCTAssertEqual(UndoToastMetrics.spokenText(renamedFileCount: 3, filename: "keep_a.mp4"),
                       "Prefix changed on 3 files. Undo with Command Z.")
        XCTAssertEqual(UndoToastMetrics.spokenText(renamedFileCount: 1, filename: "keep_a.mp4"),
                       "Prefix changed on keep_a.mp4. Undo with Command Z.")
    }

    func testHUDStackClearsTheUndoToast() {
        let toastTop = UndoToastMetrics.bottomInset - DWBMetrics.railHeight + UndoToastMetrics.height
        XCTAssertGreaterThanOrEqual(HUDStackMetrics.bottomOffsetAboveRail, toastTop)
    }

    func testHUDSlotIsTheDesignSystemOffsetAboveTheStageBottom() {
        XCTAssertEqual(DWBMetrics.hudBottomOffset, 132)
        XCTAssertEqual(DWBMetrics.railHeight + HUDStackMetrics.bottomOffsetAboveRail, DWBMetrics.hudBottomOffset)
    }

    // MARK: Status HUD

    func testScaleStatusHUDNamesTheModeAndItsShortcut() {
        let fit = StatusHUDContent.scale(.fit)
        XCTAssertEqual(fit.symbol, "rectangle.arrowtriangle.2.inward")
        XCTAssertEqual(fit.title, "Fit")
        XCTAssertEqual(fit.detail, "\u{2318}1")
        let fill = StatusHUDContent.scale(.fill)
        XCTAssertEqual(fill.symbol, "rectangle.arrowtriangle.2.outward")
        XCTAssertEqual(fill.title, "Fill")
        XCTAssertEqual(fill.detail, "\u{2318}2")
        let stretch = StatusHUDContent.scale(.stretch)
        XCTAssertEqual(stretch.symbol, "arrow.left.and.right")
        XCTAssertEqual(stretch.title, "Stretch")
        XCTAssertEqual(stretch.detail, "\u{2318}3")
        for content in [fit, fill, stretch] {
            XCTAssertEqual(content.tone, .neutral)
            XCTAssertEqual(content.hold, 1.25)
        }
    }

    func testWindowLimitStatusHUDUsesTheRealLimitAndHoldsTwoAndAHalfSeconds() {
        let content = StatusHUDContent.windowLimit(maxWindows: 5)
        XCTAssertEqual(content.symbol, "macwindow")
        XCTAssertEqual(content.title, "Window limit reached")
        XCTAssertEqual(content.detail, "dwb player supports up to 5 player windows.")
        XCTAssertEqual(content.tone, .caution)
        XCTAssertEqual(content.hold, 2.5)
        XCTAssertEqual(StatusHUDContent.windowLimit(maxWindows: 7).detail, "dwb player supports up to 7 player windows.")
        XCTAssertEqual(content.spokenText, "Window limit reached. dwb player supports up to 5 player windows.")
    }

    func testStatusHUDHeightHasAFloorOfFortyFourAndGrowsWithTwoLines() {
        XCTAssertEqual(StatusHUDMetrics.minHeight, 44)
        XCTAssertEqual(StatusHUDMetrics.height(titleHeight: 16, detailHeight: 0), 44)
        XCTAssertEqual(StatusHUDMetrics.height(titleHeight: 16, detailHeight: 14), 8 + 16 + 1 + 14 + 8)
        XCTAssertEqual(StatusHUDMetrics.height(titleHeight: 40, detailHeight: 40), 8 + 40 + 1 + 40 + 8)
        XCTAssertEqual(StatusHUDMetrics.iconSize, 16)
        XCTAssertEqual(StatusHUDMetrics.leadingPadding, 14)
        XCTAssertEqual(StatusHUDMetrics.trailingPadding, 18)
    }

    func testMarkerPrefixHighlightPrefersTheLongerPrefix() {
        let match = MarkerPrefixHighlight.match(in: "keep_clip.mp4", primary: "keep_", secondary: "k")
        XCTAssertEqual(match, MarkerPrefixHighlight.Match(kind: .primary, utf16Length: 5))
        let secondary = MarkerPrefixHighlight.match(in: "del_clip.mp4", primary: "keep_", secondary: " del_ ")
        XCTAssertEqual(secondary, MarkerPrefixHighlight.Match(kind: .secondary, utf16Length: 4))
        XCTAssertNil(MarkerPrefixHighlight.match(in: "clip.mp4", primary: "keep_", secondary: "del_"))
        XCTAssertNil(MarkerPrefixHighlight.match(in: "clip.mp4", primary: "", secondary: ""))
    }

    func testMarkerPrefixHighlightReadsTheNormalizedPrefixAndKeepsTheLongerOne() {
        // "keep" normalizes to "keep_"; "keep_x" to "keep_x_", which is longer and wins.
        XCTAssertEqual(MarkerPrefixHighlight.match(in: "keep_clip.mp4", primary: "keep", secondary: ""),
                       MarkerPrefixHighlight.Match(kind: .primary, utf16Length: 5))
        XCTAssertEqual(MarkerPrefixHighlight.match(in: "keep_x_clip.mp4", primary: "keep_", secondary: "keep_x"),
                       MarkerPrefixHighlight.Match(kind: .secondary, utf16Length: 7))
    }

    // MARK: Drop zone

    func testDropZoneCopyMatchesPlayerQueueBehavior() {
        XCTAssertEqual(DropZoneCopy.title(fileCount: 1, folderCount: 0), "Add 1 file to the queue")
        XCTAssertEqual(DropZoneCopy.title(fileCount: 3, folderCount: 0), "Add 3 files to the queue")
        XCTAssertEqual(DropZoneCopy.title(fileCount: 2, folderCount: 1), "Add 3 items to the queue")
        XCTAssertEqual(DropZoneCopy.title(fileCount: 0, folderCount: 1), "Add 1 item to the queue")
        // Player inserts dropped files at the top of the queue.
        XCTAssertEqual(DropZoneCopy.subtitle, "Release to add to the top of the queue.")
        XCTAssertEqual(DropZoneCopy.dashPattern, [6, 4])
    }

    // MARK: Helpers

    private func assertColor(_ actual: NSColor, equals expected: NSColor,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let a = actual.usingColorSpace(.sRGB), let e = expected.usingColorSpace(.sRGB) else {
            return XCTFail("Colors are not convertible to sRGB", file: file, line: line)
        }
        XCTAssertEqual(a.redComponent, e.redComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(a.greenComponent, e.greenComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(a.blueComponent, e.blueComponent, accuracy: 0.002, file: file, line: line)
    }
}
