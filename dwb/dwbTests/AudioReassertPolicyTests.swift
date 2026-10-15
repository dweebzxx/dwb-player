import XCTest

final class AudioReassertPolicyTests: XCTestCase {

    func testNoWriteWhenActualMatchesIntended() {
        XCTAssertNil(AudioReassertPolicy.valueToWrite(actual: 80, intended: 80))
    }

    func testWritesIntendedWhenActualIsAnotherWindowsValue() {
        // Window B intends 100; a new output started at window A's 20.
        XCTAssertEqual(AudioReassertPolicy.valueToWrite(actual: 20, intended: 100), 100)
    }

    func testMutedWindowWritesZeroWhenActualIsNonzero() {
        XCTAssertEqual(AudioReassertPolicy.valueToWrite(actual: 100, intended: 0), 0)
    }

    func testUnmutedWindowWritesIntendedWhenActualIsZero() {
        // Window B intends 100; another window left the shared value at 0.
        XCTAssertEqual(AudioReassertPolicy.valueToWrite(actual: 0, intended: 100), 100)
    }

    func testNoWriteWhenActualIsUnusable() {
        // nil and -1 both mean VLC has no audio output yet.
        XCTAssertNil(AudioReassertPolicy.valueToWrite(actual: nil, intended: 100))
        XCTAssertNil(AudioReassertPolicy.valueToWrite(actual: -1, intended: 100))
        XCTAssertNil(AudioReassertPolicy.valueToWrite(actual: -1, intended: 0))
    }

    func testSoftwareGainAboveNormalVolumeIsCompared() {
        XCTAssertNil(AudioReassertPolicy.valueToWrite(actual: 150, intended: 150))
        XCTAssertEqual(AudioReassertPolicy.valueToWrite(actual: 100, intended: 150), 150)
        XCTAssertEqual(AudioReassertPolicy.valueToWrite(actual: 150, intended: 100), 100)
        XCTAssertEqual(AudioReassertPolicy.valueToWrite(actual: 0, intended: 200), 200)
    }

    func testMutedWindowWithZeroActualNeedsNoWrite() {
        XCTAssertNil(AudioReassertPolicy.valueToWrite(actual: 0, intended: 0))
    }
}
