import Foundation

/// A completed marker rename, retained only long enough to reverse it once.
struct MarkerRenameUndoEntry: Equatable {
    let originalURL: URL
    let renamedURL: URL
}

struct MarkerRenameUndoStep: Equatable {
    let entries: [MarkerRenameUndoEntry]

    init?(entries: [MarkerRenameUndoEntry]) {
        guard !entries.isEmpty else { return nil }
        self.entries = entries
    }
}

enum MarkerRenameUndoFailure: Error, Equatable {
    case missingSource(filename: String)
    case destinationCollision(filename: String)
}

/// A validated inverse move. Its source is the marker-renamed file and its
/// destination is the original filename.
struct PlannedMarkerRenameUndo: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

enum MarkerRenameUndoPlan {
    static func build(
        for step: MarkerRenameUndoStep,
        fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Result<[PlannedMarkerRenameUndo], MarkerRenameUndoFailure> {
        var plan: [PlannedMarkerRenameUndo] = []

        for entry in step.entries {
            guard fileExistsAtPath(entry.renamedURL.path) else {
                return .failure(.missingSource(filename: entry.renamedURL.lastPathComponent))
            }
            guard !fileExistsAtPath(entry.originalURL.path) else {
                return .failure(.destinationCollision(filename: entry.originalURL.lastPathComponent))
            }
            plan.append(
                PlannedMarkerRenameUndo(
                    sourceURL: entry.renamedURL,
                    destinationURL: entry.originalURL
                )
            )
        }

        return .success(plan)
    }
}

/// Per-window one-step marker-rename undo state.
struct MarkerRenameUndoState {
    private(set) var step: MarkerRenameUndoStep?

    var canUndo: Bool { step != nil }

    mutating func record(entries: [MarkerRenameUndoEntry]) {
        guard let step = MarkerRenameUndoStep(entries: entries) else { return }
        self.step = step
    }

    mutating func clear() {
        step = nil
    }
}
