import Foundation

// MARK: - Debug level

enum DebugLevel: Int, Comparable {
    case info = 0, warning, error

    static func < (lhs: DebugLevel, rhs: DebugLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log entry

struct DebugLogEntry {
    let date: Date
    let level: DebugLevel
    let category: String
    let message: String
}

// MARK: - Buffer

/// In-memory storage rules for the Debug Console. Pure value type, no UI.
///
/// While recording everything (console on), every entry goes to the main buffer.
/// While recording important lines only (console off), warnings and errors go to the
/// main buffer, and info lines wait in a short context list. A warning or error first
/// moves that context list into the main buffer, in time order, so a line is never
/// stored twice and the history leading up to it is kept.
struct DebugLogBuffer {

    static let mainLimit = 1000
    // Slack so we trim in bulk (O(1) amortized) instead of removing one element per overflow log.
    static let mainSlack = 256
    static let contextLimit = 400
    /// Very frequent layout diagnostics: info lines in this category are never kept as context.
    static let contextExcludedCategory = "queue-geometry"

    private var storage: [DebugLogEntry] = []
    private(set) var context: [DebugLogEntry] = []
    private(set) var isRecordingAll: Bool

    init(recordingAll: Bool = false) {
        isRecordingAll = recordingAll
    }

    /// The main buffer, oldest first, at most `mainLimit` entries.
    var entries: [DebugLogEntry] {
        storage.count > Self.mainLimit ? Array(storage.suffix(Self.mainLimit)) : storage
    }

    mutating func append(_ entry: DebugLogEntry) {
        if isRecordingAll || entry.level >= .warning {
            storage.append(contentsOf: context)
            context.removeAll()
            storage.append(entry)
            trimIfOverSlack()
            return
        }
        guard entry.category != Self.contextExcludedCategory else { return }
        context.append(entry)
        if context.count > Self.contextLimit {
            context.removeFirst(context.count - Self.contextLimit)
        }
    }

    /// Switching to "everything" moves the context list into the main buffer first.
    /// Switching back clears nothing.
    mutating func setRecordingAll(_ recordingAll: Bool) {
        if recordingAll {
            storage.append(contentsOf: context)
            context.removeAll()
            trimIfOverSlack()
        }
        isRecordingAll = recordingAll
    }

    /// Trims the main buffer to exactly `mainLimit`.
    mutating func trimToLimit() {
        if storage.count > Self.mainLimit {
            storage.removeFirst(storage.count - Self.mainLimit)
        }
    }

    mutating func clear() {
        storage.removeAll()
        context.removeAll()
    }

    private mutating func trimIfOverSlack() {
        if storage.count > Self.mainLimit + Self.mainSlack {
            trimToLimit()
        }
    }
}
