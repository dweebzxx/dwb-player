import Foundation

/// Pure rules and copy for the two rename sheets (`tokens-and-specs.md` 9.3). No view state,
/// so the validation and the "old › new" list can be unit tested. Validation only stops a
/// rename that `renameFile(at:to:)` would reject; it never changes what that method does.

// MARK: - Copy

enum RenameSheetCopy {
    static let singleTitle = "Rename File"
    static let cancelTitle = "Cancel"
    static let singleConfirmTitle = "Rename"

    /// The caption the single rename dialog already used.
    static func singleCaption(filename: String) -> String {
        "New name for \"\(filename)\":"
    }

    static func batchTitle(count: Int) -> String { "Rename \(count) Files?" }
    static func batchConfirmTitle(count: Int) -> String { "Rename \(count) Files" }
}

// MARK: - Single rename validation

enum RenameValidation {
    enum Issue: Equatable {
        case empty
        /// The stem contains `/` or `:`.
        case forbiddenCharacter
        /// A different file already has the resulting name.
        case nameExists(String)
    }

    struct Result: Equatable {
        /// The stem with surrounding whitespace removed.
        let stem: String
        /// The complete file name the rename would use: stem plus the protected extension.
        let fullName: String
        /// The stem is the original stem, so there is nothing to rename.
        let isUnchanged: Bool
        let issue: Issue?

        /// What the inline message shows. An untouched name raises no message.
        var visibleIssue: Issue? { isUnchanged ? nil : issue }

        /// Rename is enabled only for a changed, valid name.
        var canSubmit: Bool { !isUnchanged && issue == nil }
    }

    static let forbiddenCharacters = CharacterSet(charactersIn: "/:")

    /// `fileExtension` has no leading dot. `nameExists` answers whether a file with the given
    /// full name is already in the folder.
    static func evaluate(stem rawStem: String,
                         originalStem: String,
                         fileExtension: String,
                         nameExists: (String) -> Bool) -> Result {
        let stem = rawStem.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = Self.fullName(stem: stem, fileExtension: fileExtension)
        let unchanged = stem == originalStem

        let issue: Issue?
        if stem.isEmpty {
            issue = .empty
        } else if rawStem.rangeOfCharacter(from: forbiddenCharacters) != nil {
            issue = .forbiddenCharacter
        } else if !unchanged && nameExists(fullName) {
            issue = .nameExists(fullName)
        } else {
            issue = nil
        }
        return Result(stem: stem, fullName: fullName, isUnchanged: unchanged, issue: issue)
    }

    static func fullName(stem: String, fileExtension: String) -> String {
        fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    /// The text of the inline message.
    static func message(for issue: Issue) -> String {
        switch issue {
        case .empty:
            return "Enter a name."
        case .forbiddenCharacter:
            return "Names can\u{2019}t contain \u{201C}/\u{201D} or \u{201C}:\u{201D}."
        case .nameExists(let name):
            return "\u{201C}\(name)\u{201D} already exists in this folder."
        }
    }
}

// MARK: - Batch rename preview

enum BatchRenamePreview {
    struct Row: Equatable {
        let old: String
        let new: String

        /// "old › new"
        var text: String { "\(old) \u{203A} \(new)" }
    }

    struct Preview: Equatable {
        let rows: [Row]
        /// Renames beyond the visible rows.
        let moreCount: Int

        /// "and N more", or nil when every rename is listed.
        var moreText: String? { moreCount > 0 ? "and \(moreCount) more" : nil }
    }

    static let maxRows = 4

    static func make(renames: [(old: String, new: String)], maxRows: Int = BatchRenamePreview.maxRows) -> Preview {
        let rows = renames.prefix(max(0, maxRows)).map { Row(old: $0.old, new: $0.new) }
        return Preview(rows: Array(rows), moreCount: max(0, renames.count - rows.count))
    }

    /// True when every file already carries `prefix`, so the batch removes it.
    static func isRemoving(oldNames: [String], prefix: String) -> Bool {
        !oldNames.isEmpty && !prefix.isEmpty && oldNames.allSatisfy { $0.hasPrefix(prefix) }
    }

    /// The caption split around the prefix, which the sheet draws in monospaced semibold
    /// marker color: "Applying the " + prefix + " prefix renames N files on disk. …".
    static func captionParts(count: Int, removing: Bool) -> (lead: String, trail: String) {
        ("\(removing ? "Removing" : "Applying") the ",
         " prefix renames \(count) files on disk. \u{2318}Z undoes the whole batch.")
    }
}
