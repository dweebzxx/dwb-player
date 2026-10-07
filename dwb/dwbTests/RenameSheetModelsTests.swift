import XCTest

final class RenameSheetModelsTests: XCTestCase {

    // MARK: Single rename validation

    private func evaluate(_ stem: String,
                          original: String = "clip",
                          ext: String = "mp4",
                          existing: Set<String> = []) -> RenameValidation.Result {
        RenameValidation.evaluate(stem: stem, originalStem: original, fileExtension: ext,
                                  nameExists: { existing.contains($0) })
    }

    func testUnchangedNameIsValidButCannotBeSubmitted() {
        let result = evaluate("clip")
        XCTAssertTrue(result.isUnchanged)
        XCTAssertNil(result.issue)
        XCTAssertNil(result.visibleIssue)
        XCTAssertFalse(result.canSubmit)
    }

    func testChangedValidNameCanBeSubmittedWithTheProtectedExtension() {
        let result = evaluate("  keep_clip  ")
        XCTAssertEqual(result.stem, "keep_clip")
        XCTAssertEqual(result.fullName, "keep_clip.mp4")
        XCTAssertNil(result.issue)
        XCTAssertTrue(result.canSubmit)
    }

    func testEmptyNameIsInvalidAndShowsTheMessage() {
        for blank in ["", "   ", "\n"] {
            let result = evaluate(blank)
            XCTAssertEqual(result.issue, .empty)
            XCTAssertEqual(result.visibleIssue, .empty)
            XCTAssertFalse(result.canSubmit)
        }
        XCTAssertEqual(RenameValidation.message(for: .empty), "Enter a name.")
    }

    func testSlashAndColonAreForbidden() {
        for bad in ["a/b", "a:b", "/", ":", "keep_/clip"] {
            let result = evaluate(bad)
            XCTAssertEqual(result.issue, .forbiddenCharacter, bad)
            XCTAssertFalse(result.canSubmit, bad)
        }
        XCTAssertEqual(RenameValidation.message(for: .forbiddenCharacter),
                       "Names can\u{2019}t contain \u{201C}/\u{201D} or \u{201C}:\u{201D}.")
    }

    func testAnExistingNameIsInvalidAndNamesTheFile() {
        let result = evaluate("other", existing: ["other.mp4"])
        XCTAssertEqual(result.issue, .nameExists("other.mp4"))
        XCTAssertFalse(result.canSubmit)
        XCTAssertEqual(RenameValidation.message(for: .nameExists("other.mp4")),
                       "\u{201C}other.mp4\u{201D} already exists in this folder.")
    }

    func testTheOriginalNameIsNotReportedAsExisting() {
        // The file itself is in the folder; leaving the name alone is "unchanged", not a clash.
        let result = evaluate("clip", existing: ["clip.mp4"])
        XCTAssertNil(result.issue)
        XCTAssertTrue(result.isUnchanged)
    }

    func testTheExtensionIsPartOfTheExistenceCheck() {
        XCTAssertNil(evaluate("other", existing: ["other.mkv"]).issue)
        XCTAssertEqual(evaluate("other", existing: ["other.mp4"]).issue, .nameExists("other.mp4"))
    }

    func testFileWithoutAnExtensionUsesTheBareStem() {
        let result = RenameValidation.evaluate(stem: "notes2", originalStem: "notes", fileExtension: "",
                                               nameExists: { $0 == "taken" })
        XCTAssertEqual(result.fullName, "notes2")
        XCTAssertTrue(result.canSubmit)
        let clash = RenameValidation.evaluate(stem: "taken", originalStem: "notes", fileExtension: "",
                                              nameExists: { $0 == "taken" })
        XCTAssertEqual(clash.issue, .nameExists("taken"))
    }

    // MARK: Copy

    func testSingleRenameCopyKeepsTheExistingCaption() {
        XCTAssertEqual(RenameSheetCopy.singleTitle, "Rename File")
        XCTAssertEqual(RenameSheetCopy.singleCaption(filename: "clip.mp4"), "New name for \"clip.mp4\":")
        XCTAssertEqual(RenameSheetCopy.singleConfirmTitle, "Rename")
        XCTAssertEqual(RenameSheetCopy.cancelTitle, "Cancel")
    }

    func testBatchRenameCopyStatesTheCount() {
        XCTAssertEqual(RenameSheetCopy.batchTitle(count: 5), "Rename 5 Files?")
        XCTAssertEqual(RenameSheetCopy.batchConfirmTitle(count: 5), "Rename 5 Files")
    }

    // MARK: Batch preview

    func testPreviewListsUpToFourRowsAndCountsTheRest() {
        let renames = (1...7).map { (old: "a\($0).mp4", new: "keep_a\($0).mp4") }
        let preview = BatchRenamePreview.make(renames: renames)
        XCTAssertEqual(preview.rows.count, 4)
        XCTAssertEqual(preview.rows[0], BatchRenamePreview.Row(old: "a1.mp4", new: "keep_a1.mp4"))
        XCTAssertEqual(preview.rows[3].old, "a4.mp4")
        XCTAssertEqual(preview.moreCount, 3)
        XCTAssertEqual(preview.moreText, "and 3 more")
    }

    func testPreviewWithFourOrFewerRowsHasNoMoreLine() {
        let renames = (1...4).map { (old: "a\($0).mp4", new: "keep_a\($0).mp4") }
        let preview = BatchRenamePreview.make(renames: renames)
        XCTAssertEqual(preview.rows.count, 4)
        XCTAssertEqual(preview.moreCount, 0)
        XCTAssertNil(preview.moreText)
        XCTAssertEqual(BatchRenamePreview.make(renames: [(old: "x", new: "y")]).rows.count, 1)
        XCTAssertTrue(BatchRenamePreview.make(renames: []).rows.isEmpty)
    }

    func testPreviewRowTextReadsOldChevronNew() {
        let row = BatchRenamePreview.Row(old: "a.mp4", new: "keep_a.mp4")
        XCTAssertEqual(row.text, "a.mp4 \u{203A} keep_a.mp4")
    }

    func testPreviewKeepsRenameOrderAndHonorsACustomLimit() {
        let renames = [(old: "b", new: "1"), (old: "a", new: "2"), (old: "c", new: "3")]
        let preview = BatchRenamePreview.make(renames: renames, maxRows: 2)
        XCTAssertEqual(preview.rows.map(\.old), ["b", "a"])
        XCTAssertEqual(preview.moreText, "and 1 more")
    }

    func testRemovingWhenEveryFileAlreadyCarriesThePrefix() {
        XCTAssertTrue(BatchRenamePreview.isRemoving(oldNames: ["keep_a", "keep_b"], prefix: "keep_"))
        XCTAssertFalse(BatchRenamePreview.isRemoving(oldNames: ["keep_a", "b"], prefix: "keep_"))
        XCTAssertFalse(BatchRenamePreview.isRemoving(oldNames: [], prefix: "keep_"))
        XCTAssertFalse(BatchRenamePreview.isRemoving(oldNames: ["a"], prefix: ""))
    }

    func testBatchCaptionNamesTheCountAndPointsAtUndo() {
        let applying = BatchRenamePreview.captionParts(count: 3, removing: false)
        XCTAssertEqual(applying.lead, "Applying the ")
        XCTAssertEqual(applying.trail, " prefix renames 3 files on disk. \u{2318}Z undoes the whole batch.")
        XCTAssertEqual(BatchRenamePreview.captionParts(count: 3, removing: true).lead, "Removing the ")
    }
}
