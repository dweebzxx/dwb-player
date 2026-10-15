import XCTest

final class DebugLogBufferTests: XCTestCase {

    private func entry(_ message: String,
                       level: DebugLevel = .info,
                       category: String = "test") -> DebugLogEntry {
        DebugLogEntry(date: Date(), level: level, category: category, message: message)
    }

    private func messages(_ entries: [DebugLogEntry]) -> [String] {
        entries.map(\.message)
    }

    private func numbered(_ range: ClosedRange<Int>) -> [String] {
        range.map { "line \($0)" }
    }

    // (a)
    func testOffInfoLinesGoToContextNotMainBuffer() {
        var buffer = DebugLogBuffer()
        buffer.append(entry("one"))
        buffer.append(entry("two"))

        XCTAssertFalse(buffer.isRecordingAll)
        XCTAssertEqual(messages(buffer.entries), [])
        XCTAssertEqual(messages(buffer.context), ["one", "two"])
    }

    // (b)
    func testContextKeepsNewestFiftyAndDropsOldest() {
        var buffer = DebugLogBuffer()
        for i in 1...80 { buffer.append(entry("line \(i)")) }

        XCTAssertEqual(buffer.context.count, DebugLogBuffer.contextLimit)
        XCTAssertEqual(messages(buffer.context), numbered(31...80))
        XCTAssertEqual(buffer.entries.count, 0)
    }

    // (c)
    func testWarningMovesContextInFrontOfItInOrder() {
        var buffer = DebugLogBuffer()
        buffer.append(entry("a"))
        buffer.append(entry("b"))
        buffer.append(entry("c"))
        buffer.append(entry("boom", level: .warning))

        XCTAssertEqual(messages(buffer.entries), ["a", "b", "c", "boom"])
        XCTAssertTrue(buffer.context.isEmpty)
    }

    // (d)
    func testErrorRightAfterErrorRepeatsNoLine() {
        var buffer = DebugLogBuffer()
        buffer.append(entry("a"))
        buffer.append(entry("first", level: .error))
        buffer.append(entry("second", level: .error))

        XCTAssertEqual(messages(buffer.entries), ["a", "first", "second"])
        XCTAssertTrue(buffer.context.isEmpty)
    }

    // (e)
    func testLinesAfterAnErrorPrecedeTheNextErrorNotTheFirst() {
        var buffer = DebugLogBuffer()
        buffer.append(entry("a"))
        buffer.append(entry("first", level: .error))
        buffer.append(entry("b"))
        buffer.append(entry("c"))

        XCTAssertEqual(messages(buffer.entries), ["a", "first"])
        XCTAssertEqual(messages(buffer.context), ["b", "c"])

        buffer.append(entry("second", level: .warning))

        XCTAssertEqual(messages(buffer.entries), ["a", "first", "b", "c", "second"])
        XCTAssertTrue(buffer.context.isEmpty)
    }

    // (f)
    func testOnInfoLinesGoStraightToMainBuffer() {
        var buffer = DebugLogBuffer(recordingAll: true)
        buffer.append(entry("one"))
        buffer.append(entry("two"))

        XCTAssertTrue(buffer.isRecordingAll)
        XCTAssertEqual(messages(buffer.entries), ["one", "two"])
        XCTAssertTrue(buffer.context.isEmpty)
    }

    // (g)
    func testSwitchingOnMovesContextIntoMainBufferInOrder() {
        var buffer = DebugLogBuffer()
        buffer.append(entry("early", level: .warning))
        buffer.append(entry("x"))
        buffer.append(entry("y"))

        buffer.setRecordingAll(true)

        XCTAssertEqual(messages(buffer.entries), ["early", "x", "y"])
        XCTAssertTrue(buffer.context.isEmpty)

        buffer.append(entry("z"))
        XCTAssertEqual(messages(buffer.entries), ["early", "x", "y", "z"])
    }

    func testSwitchingOffClearsNothing() {
        var buffer = DebugLogBuffer(recordingAll: true)
        buffer.append(entry("a"))
        buffer.setRecordingAll(false)

        XCTAssertFalse(buffer.isRecordingAll)
        XCTAssertEqual(messages(buffer.entries), ["a"])

        buffer.append(entry("b"))
        XCTAssertEqual(messages(buffer.entries), ["a"])
        XCTAssertEqual(messages(buffer.context), ["b"])
    }

    // (h)
    func testMainBufferKeepsNewestThousandInOrderAfter1500Appends() {
        var buffer = DebugLogBuffer(recordingAll: true)
        for i in 1...1500 { buffer.append(entry("line \(i)")) }

        let kept = messages(buffer.entries)
        XCTAssertEqual(kept.count, DebugLogBuffer.mainLimit)
        XCTAssertEqual(kept, numbered(501...1500))

        buffer.trimToLimit()
        XCTAssertEqual(messages(buffer.entries), numbered(501...1500))
    }

    // (i)
    func testQueueGeometryInfoIsDroppedWhileOffKeptWhileOnAndWarningAlwaysKept() {
        var off = DebugLogBuffer()
        off.append(entry("geometry", category: "queue-geometry"))
        XCTAssertTrue(off.context.isEmpty)
        XCTAssertTrue(off.entries.isEmpty)

        off.append(entry("other"))
        off.append(entry("clipX drift", level: .warning, category: "queue-geometry"))
        XCTAssertEqual(messages(off.entries), ["other", "clipX drift"])

        var on = DebugLogBuffer(recordingAll: true)
        on.append(entry("geometry", category: "queue-geometry"))
        XCTAssertEqual(messages(on.entries), ["geometry"])
    }

    // (j)
    func testClearEmptiesBothLists() {
        var buffer = DebugLogBuffer()
        buffer.append(entry("main", level: .error))
        buffer.append(entry("context"))
        XCTAssertFalse(buffer.entries.isEmpty)
        XCTAssertFalse(buffer.context.isEmpty)

        buffer.clear()

        XCTAssertTrue(buffer.entries.isEmpty)
        XCTAssertTrue(buffer.context.isEmpty)
    }
}
