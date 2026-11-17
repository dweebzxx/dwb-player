import XCTest

final class PlayerWindowTargetingTests: XCTestCase {

    private typealias Snapshot = PlayerWindowTargeting.WindowSnapshot<String>

    private func onScreen(_ id: String, key: UInt64) -> Snapshot {
        Snapshot(id: id, isOnScreen: true, isMinimized: false, lastKeyStamp: key, minimizeStamp: nil)
    }

    private func minimized(_ id: String, key: UInt64, minimizedAt stamp: UInt64) -> Snapshot {
        Snapshot(id: id, isOnScreen: false, isMinimized: true, lastKeyStamp: key, minimizeStamp: stamp)
    }

    // MARK: - Dock reopen

    func testReopenWithNoWindowsOpensNewWindow() {
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: [Snapshot]()), .openNewWindow)
    }

    func testReopenWithOneMinimizedWindowRestoresIt() {
        let windows = [minimized("A", key: 1, minimizedAt: 2)]
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: windows), .restoreMinimized("A"))
    }

    func testReopenWithThreeMinimizedWindowsRestoresMostRecentlyMinimized() {
        // Minimized in the order A, B, C; key order is deliberately different.
        let windows = [
            minimized("A", key: 6, minimizedAt: 7),
            minimized("B", key: 5, minimizedAt: 8),
            minimized("C", key: 4, minimizedAt: 9)
        ]
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: windows), .restoreMinimized("C"))
    }

    func testReopenWithVisibleAndMinimizedWindowBringsVisibleForward() {
        let windows = [
            onScreen("A", key: 1),
            minimized("B", key: 2, minimizedAt: 3)
        ]
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: windows), .bringForward("A"))
    }

    func testReopenBringsMostRecentlyActiveVisibleWindowForward() {
        let windows = [onScreen("A", key: 5), onScreen("B", key: 3), onScreen("C", key: 4)]
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: windows), .bringForward("A"))
    }

    func testReopenIgnoresMinimizedWindowThatWasThenClosed() {
        // A closed window leaves AppDelegate's list, so it is absent from the snapshots.
        let before = [minimized("A", key: 1, minimizedAt: 3), minimized("B", key: 2, minimizedAt: 4)]
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: before), .restoreMinimized("B"))
        let afterClosingB = before.filter { $0.id != "B" }
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: afterClosingB), .restoreMinimized("A"))
        XCTAssertEqual(PlayerWindowTargeting.reopenChoice(windows: afterClosingB.filter { $0.id != "A" }),
                       .openNewWindow)
    }

    // MARK: - Settings target

    func testSettingsBecomingKeyDoesNotChangeTarget() {
        // Settings is never a player window snapshot, and its becoming key stamps nothing.
        let windows = [onScreen("A", key: 1), onScreen("B", key: 2)]
        XCTAssertEqual(PlayerWindowTargeting.settingsTarget(windows: windows), "B")
        XCTAssertEqual(PlayerWindowTargeting.settingsTarget(windows: windows), "B")
    }

    func testSettingsTargetMovesToNextMostRecentVisibleWindowWhenTargetCloses() {
        let windows = [onScreen("A", key: 2), onScreen("B", key: 1), onScreen("C", key: 3)]
        XCTAssertEqual(PlayerWindowTargeting.settingsTarget(windows: windows), "C")
        let afterClosingC = windows.filter { $0.id != "C" }
        XCTAssertEqual(PlayerWindowTargeting.settingsTarget(windows: afterClosingC), "A")
    }

    func testSettingsTargetSkipsMinimizedWindow() {
        let windows = [onScreen("A", key: 1), minimized("B", key: 2, minimizedAt: 3)]
        XCTAssertEqual(PlayerWindowTargeting.settingsTarget(windows: windows), "A")
    }

    func testSettingsHasNoTargetWhenAllWindowsAreMinimizedOrClosed() {
        let windows = [minimized("A", key: 1, minimizedAt: 2), minimized("B", key: 3, minimizedAt: 4)]
        XCTAssertNil(PlayerWindowTargeting.settingsTarget(windows: windows))
        XCTAssertNil(PlayerWindowTargeting.settingsTarget(windows: [Snapshot]()))
    }

    // MARK: - Helper text

    func testHelperTextNamesMedia() {
        XCTAssertEqual(PlayerWindowTargeting.settingsHelperText(targetTitle: "holiday.mp4"),
                       "Applies to \u{201C}holiday.mp4\u{201D}.")
    }

    func testHelperTextWithNoMediaUsesDefaultWindowTitle() {
        XCTAssertEqual(PlayerWindowTargeting.settingsHelperText(targetTitle: "dwb player"),
                       "Applies to \u{201C}dwb player\u{201D}.")
    }

    func testHelperTextWithNoTarget() {
        XCTAssertEqual(PlayerWindowTargeting.settingsHelperText(targetTitle: nil), "No player window is open.")
    }

    func testHelperTextTruncatesLongNameInTheMiddle() {
        let name = "A-very-long-media-file-name-that-keeps-going-and-going-until-the-end.mkv"
        let text = PlayerWindowTargeting.settingsHelperText(targetTitle: name)
        let shown = PlayerWindowTargeting.middleTruncated(name, maxLength: PlayerWindowTargeting.maxHelperNameLength)

        XCTAssertEqual(text, "Applies to \u{201C}\(shown)\u{201D}.")
        XCTAssertEqual(shown.count, PlayerWindowTargeting.maxHelperNameLength)
        XCTAssertTrue(shown.hasPrefix("A-very-long-media-file-"))
        XCTAssertTrue(shown.hasSuffix("-the-end.mkv"))
        XCTAssertTrue(shown.contains("\u{2026}"))
    }

    // MARK: - Playback speed helper text

    func testSpeedHelperTextSaysVideoOnlyThenNamesTheWindow() {
        XCTAssertEqual(PlayerWindowTargeting.speedHelperText(targetTitle: "Holiday.mov"),
                       "Affects video only. Applies to \u{201C}Holiday.mov\u{201D}.")
    }

    func testSpeedHelperTextWithNoWindowSaysSo() {
        XCTAssertEqual(PlayerWindowTargeting.speedHelperText(targetTitle: nil),
                       "Affects video only. No player window is open.")
    }
}
