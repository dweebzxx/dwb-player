import Foundation
import XCTest

final class MarkerRenameUndoPlanTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/marker-undo/\(name)")
    }

    private func step(_ entries: [MarkerRenameUndoEntry]) -> MarkerRenameUndoStep {
        guard let step = MarkerRenameUndoStep(entries: entries) else {
            XCTFail("Expected a non-empty undo step")
            fatalError("Expected a non-empty undo step")
        }
        return step
    }

    func testBuildsSingleFileInversePlan() {
        let original = url("clip.mov")
        let renamed = url("keep_clip.mov")
        let existing = Set([renamed.path])

        let result = MarkerRenameUndoPlan.build(for: step([
            .init(originalURL: original, renamedURL: renamed)
        ])) { existing.contains($0) }

        XCTAssertEqual(result, .success([
            .init(sourceURL: renamed, destinationURL: original)
        ]))
    }

    func testMultiFilePreflightIsAllOrNothing() {
        let first = MarkerRenameUndoEntry(originalURL: url("one.mov"), renamedURL: url("keep_one.mov"))
        let second = MarkerRenameUndoEntry(originalURL: url("two.mov"), renamedURL: url("keep_two.mov"))
        let existing = Set([first.renamedURL.path])

        let result = MarkerRenameUndoPlan.build(for: step([first, second])) { existing.contains($0) }

        XCTAssertEqual(result, .failure(.missingSource(filename: "keep_two.mov")))
    }

    func testRefusesUndoWhenRenamedSourceIsMissing() {
        let entry = MarkerRenameUndoEntry(originalURL: url("clip.mov"), renamedURL: url("keep_clip.mov"))

        let result = MarkerRenameUndoPlan.build(for: step([entry])) { _ in false }

        XCTAssertEqual(result, .failure(.missingSource(filename: "keep_clip.mov")))
    }

    func testRefusesUndoWhenOriginalDestinationIsOccupied() {
        let entry = MarkerRenameUndoEntry(originalURL: url("clip.mov"), renamedURL: url("keep_clip.mov"))
        let existing = Set([entry.originalURL.path, entry.renamedURL.path])

        let result = MarkerRenameUndoPlan.build(for: step([entry])) { existing.contains($0) }

        XCTAssertEqual(result, .failure(.destinationCollision(filename: "clip.mov")))
    }

    func testNoOpDoesNotCreateOrReplaceUndoStep() {
        var state = MarkerRenameUndoState()
        let entry = MarkerRenameUndoEntry(originalURL: url("clip.mov"), renamedURL: url("keep_clip.mov"))
        state.record(entries: [entry])
        state.record(entries: [])

        XCTAssertEqual(state.step?.entries, [entry])
    }

    func testNewMarkerRenameReplacesPreviousUndoStep() {
        var state = MarkerRenameUndoState()
        let first = MarkerRenameUndoEntry(originalURL: url("one.mov"), renamedURL: url("keep_one.mov"))
        let second = MarkerRenameUndoEntry(originalURL: url("two.mov"), renamedURL: url("keep_two.mov"))

        state.record(entries: [first])
        state.record(entries: [second])

        XCTAssertEqual(state.step?.entries, [second])
    }
}
