import Foundation
import XCTest

/// Tests for MediaFileSupport.calculatePrefixTransition — the shared prefix
/// toggle/swap logic introduced in P120. These are pure name-calculation tests;
/// no filesystem access occurs.
final class PrefixTransitionTests: XCTestCase {

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    private func result(file: String, primary: String, secondary: String, invokedPrimary: Bool) -> String? {
        MediaFileSupport.calculatePrefixTransition(
            originalURL: url(file),
            primary: primary,
            secondary: secondary,
            invokedPrimary: invokedPrimary
        )
    }

    // MARK: - State 1: Neither prefix → invoke Primary → add Primary

    func testNoPrefixInvokePrimaryAddsPrefix() {
        let r = result(file: "video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: true)
        XCTAssertEqual(r, "keep_video.mp4")
    }

    func testNoPrefixInvokePrimaryPreservesExtension() {
        let r = result(file: "movie.MOV", primary: "k_", secondary: "o_", invokedPrimary: true)
        XCTAssertEqual(r, "k_movie.MOV")
    }

    func testNoPrefixInvokePrimaryNoExtension() {
        let r = result(file: "song", primary: "keep_", secondary: "other_", invokedPrimary: true)
        XCTAssertEqual(r, "keep_song")
    }

    // MARK: - State 2: Neither prefix → invoke Secondary → add Secondary

    func testNoPrefixInvokeSecondaryAddsPrefix() {
        let r = result(file: "video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: false)
        XCTAssertEqual(r, "other_video.mp4")
    }

    func testNoPrefixInvokeSecondaryPreservesExtension() {
        let r = result(file: "clip.avi", primary: "k_", secondary: "s_", invokedPrimary: false)
        XCTAssertEqual(r, "s_clip.avi")
    }

    // MARK: - State 3: Primary present → invoke Primary → remove Primary

    func testPrimaryPresentInvokePrimaryRemovesPrefix() {
        let r = result(file: "keep_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: true)
        XCTAssertEqual(r, "video.mp4")
    }

    func testPrimaryPresentInvokePrimaryPreservesRemainder() {
        let r = result(file: "k_some_clip.mov", primary: "k_", secondary: "s_", invokedPrimary: true)
        XCTAssertEqual(r, "some_clip.mov")
    }

    // MARK: - State 4: Secondary present → invoke Secondary → remove Secondary

    func testSecondaryPresentInvokeSecondaryRemovesPrefix() {
        let r = result(file: "other_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: false)
        XCTAssertEqual(r, "video.mp4")
    }

    func testSecondaryPresentInvokeSecondaryNoExtension() {
        let r = result(file: "s_clip", primary: "k_", secondary: "s_", invokedPrimary: false)
        XCTAssertEqual(r, "clip")
    }

    // MARK: - State 5: Primary present → invoke Secondary → replace Primary with Secondary

    func testPrimaryPresentInvokeSecondaryReplacesPrimary() {
        let r = result(file: "keep_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: false)
        XCTAssertEqual(r, "other_video.mp4")
    }

    func testPrimaryPresentInvokeSecondaryPreservesExtension() {
        let r = result(file: "k_clip.mov", primary: "k_", secondary: "s_", invokedPrimary: false)
        XCTAssertEqual(r, "s_clip.mov")
    }

    // MARK: - State 6: Secondary present → invoke Primary → replace Secondary with Primary

    func testSecondaryPresentInvokePrimaryReplacesSecondary() {
        let r = result(file: "other_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: true)
        XCTAssertEqual(r, "keep_video.mp4")
    }

    func testSecondaryPresentInvokePrimaryPreservesExtension() {
        let r = result(file: "s_clip.mov", primary: "k_", secondary: "s_", invokedPrimary: true)
        XCTAssertEqual(r, "k_clip.mov")
    }

    // MARK: - No stacking

    func testNoStackingPrimaryOnPrimary() {
        // Same prefix invoked twice: toggled off, not doubled.
        let r = result(file: "keep_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: true)
        // Should be "video.mp4", not "keep_keep_video.mp4"
        XCTAssertEqual(r, "video.mp4")
        XCTAssertFalse((r ?? "").contains("keep_keep_"))
    }

    func testNoStackingSecondaryOnPrimary() {
        // Primary active, secondary invoked — replace, not stack.
        let r = result(file: "keep_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: false)
        XCTAssertEqual(r, "other_video.mp4")
        XCTAssertFalse((r ?? "").contains("other_keep_"))
        XCTAssertFalse((r ?? "").contains("keep_other_"))
    }

    func testNoStackingPrimaryOnSecondary() {
        // Secondary active, primary invoked — replace, not stack.
        let r = result(file: "other_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: true)
        XCTAssertEqual(r, "keep_video.mp4")
        XCTAssertFalse((r ?? "").contains("keep_other_"))
        XCTAssertFalse((r ?? "").contains("other_keep_"))
    }

    // MARK: - Repeated toggle sequences

    func testRepeatedPrimaryToggle() {
        // none → primary → none → primary
        let file1 = "video.mp4"
        let withPrimary = result(file: file1, primary: "keep_", secondary: "other_", invokedPrimary: true) ?? ""
        XCTAssertEqual(withPrimary, "keep_video.mp4")

        let backToNone = result(file: withPrimary, primary: "keep_", secondary: "other_", invokedPrimary: true) ?? ""
        XCTAssertEqual(backToNone, "video.mp4")

        let withPrimaryAgain = result(file: backToNone, primary: "keep_", secondary: "other_", invokedPrimary: true) ?? ""
        XCTAssertEqual(withPrimaryAgain, "keep_video.mp4")
    }

    func testAlternatingPrimarySecondarySwaps() {
        // primary → secondary → primary → secondary
        let p = "keep_"; let s = "other_"
        var name = "keep_video.mp4"
        name = result(file: name, primary: p, secondary: s, invokedPrimary: false) ?? name
        XCTAssertEqual(name, "other_video.mp4")
        name = result(file: name, primary: p, secondary: s, invokedPrimary: true) ?? name
        XCTAssertEqual(name, "keep_video.mp4")
        name = result(file: name, primary: p, secondary: s, invokedPrimary: false) ?? name
        XCTAssertEqual(name, "other_video.mp4")
        // Only one configured prefix appears at any point.
        XCTAssertFalse(name.contains("keep_other_"))
        XCTAssertFalse(name.contains("other_keep_"))
    }

    // MARK: - Unrelated leading text

    func testUnrelatedLeadingTextIsNotModified() {
        // File begins with something that does not match either prefix.
        let r = result(file: "notes_about_video.mp4", primary: "keep_", secondary: "other_", invokedPrimary: true)
        XCTAssertEqual(r, "keep_notes_about_video.mp4")
    }

    func testEmptyPrimaryReturnsNil() {
        let r = result(file: "video.mp4", primary: "", secondary: "other_", invokedPrimary: true)
        XCTAssertNil(r)
    }

    func testEmptySecondaryReturnsNil() {
        let r = result(file: "video.mp4", primary: "keep_", secondary: "", invokedPrimary: false)
        XCTAssertNil(r)
    }

    func testIdentityResultReturnsNil() {
        // The transition produces no change — should return nil (no-op signal).
        // Edge case: both prefixes empty with already-bare name.
        let r = MediaFileSupport.calculatePrefixTransition(
            originalURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            primary: "", secondary: "", invokedPrimary: true
        )
        XCTAssertNil(r)
    }
}
