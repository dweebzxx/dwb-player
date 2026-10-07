import AppKit
import XCTest

final class DWBThemeTests: XCTestCase {
    func testPlayerThemeUsesApprovedRoles() {
        XCTAssertEqual(DWBTheme.player.markerPrimary, DWBColor.orangeOnDark)
        XCTAssertEqual(DWBTheme.player.markerSecondary, DWBColor.tealOnDark)
        XCTAssertEqual(DWBTheme.player.accentText, DWBColor.periOnDark)
    }

    func testTextAndFillContrastMeetDesignSystemThresholds() {
        let textStops = [DWBColor.tealOnDark, DWBColor.periOnDark, DWBColor.orangeOnDark, DWBColor.successText, DWBColor.cautionText, DWBColor.errorText]
        for text in textStops {
            for surface in [DWBColor.canvas, DWBColor.surface, DWBColor.surfaceElevated] {
                XCTAssertGreaterThanOrEqual(contrastRatio(text, surface), 4.5)
            }
        }
        for fill in [DWBColor.tealFillDark, DWBColor.periFillDark, DWBColor.orangeFillDark] {
            XCTAssertGreaterThanOrEqual(contrastRatio(fill, DWBColor.surface), 3.0)
        }
    }

    func testRailIconScaleFollowsTheOpticalSizes() {
        // 9.1: utility 11, volume and More 12, skip and step 13, primary 17.
        XCTAssertEqual(DWBRailIcon.size(for: "square.split.2x1"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "shuffle"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "repeat.1"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "bookmark.fill"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "pip.enter"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "pip.exit"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "arrow.up.left.and.arrow.down.right"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "arrow.down.right.and.arrow.up.left"), 11)
        XCTAssertEqual(DWBRailIcon.size(for: "speaker.wave.2.fill"), 12)
        XCTAssertEqual(DWBRailIcon.size(for: "speaker.slash.fill"), 12)
        XCTAssertEqual(DWBRailIcon.size(for: "ellipsis"), 12)
        XCTAssertEqual(DWBRailIcon.size(for: "gobackward.10"), 13)
        XCTAssertEqual(DWBRailIcon.size(for: "goforward"), 13)
        XCTAssertEqual(DWBRailIcon.size(for: "backward.end.fill"), 13)
        XCTAssertEqual(DWBRailIcon.size(for: "forward.end.fill"), 13)
        XCTAssertEqual(DWBRailIcon.size(for: "play.fill", primary: true), 17)
        XCTAssertEqual(DWBRailIcon.size(for: "pause.fill", primary: true), 17)
    }

    func testHandoffMetricsAndHoldTimes() {
        XCTAssertEqual(DWBMetrics.queueRowDense, 32)
        XCTAssertEqual(DWBMetrics.renameSheetWidth, 400)
        XCTAssertEqual(DWBMetrics.batchSheetWidth, 420)
        XCTAssertEqual(DWBMotion.scaleHUDHold, 1.25)
        XCTAssertEqual(DWBMotion.windowLimitHold, 2.5)
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            XCTFail("Expected an sRGB color")
            return 0
        }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
}
