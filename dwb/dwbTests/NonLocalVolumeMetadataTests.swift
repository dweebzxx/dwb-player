import XCTest

final class VolumeClassifierTests: XCTestCase {

    private func classifier(_ entries: [MountEntry]?) -> VolumeClassifier {
        VolumeClassifier(mountTable: { entries })
    }

    func testPathOnLocalVolumeIsLocal() {
        let c = classifier([MountEntry(mountPoint: "/", isLocal: true),
                            MountEntry(mountPoint: "/Volumes/media", isLocal: true)])
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Users/me/a.mp4")), .local)
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Volumes/media/b.mp4")), .local)
    }

    func testPathOnNonLocalVolumeIsNonLocal() {
        let c = classifier([MountEntry(mountPoint: "/", isLocal: true),
                            MountEntry(mountPoint: "/Users/me/mnt/share", isLocal: false)])
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Users/me/mnt/share/dir/a.mp4")), .nonLocal)
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Users/me/mnt/share")), .nonLocal)
    }

    func testMountPointMatchRespectsPathBoundary() {
        let c = classifier([MountEntry(mountPoint: "/", isLocal: true),
                            MountEntry(mountPoint: "/Users/me/mnt/share", isLocal: false)])
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Users/me/mnt/share2/a.mp4")), .local)
    }

    func testLongestMountPointWins() {
        let c = classifier([MountEntry(mountPoint: "/", isLocal: true),
                            MountEntry(mountPoint: "/Volumes/a", isLocal: true),
                            MountEntry(mountPoint: "/Volumes/a/net", isLocal: false)])
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Volumes/a/net/x.mp4")), .nonLocal)
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Volumes/a/x.mp4")), .local)
    }

    func testUnreadableMountTableIsNonLocal() {
        XCTAssertEqual(classifier(nil).kind(for: URL(fileURLWithPath: "/Users/me/a.mp4")), .nonLocal)
    }

    func testPathWithNoMountPointIsNonLocal() {
        let c = classifier([MountEntry(mountPoint: "/Volumes/media", isLocal: true)])
        XCTAssertEqual(c.kind(for: URL(fileURLWithPath: "/Users/me/a.mp4")), .nonLocal)
    }

    func testTableIsReadOnceUntilRefreshed() {
        var reads = 0
        let c = VolumeClassifier(mountTable: {
            reads += 1
            return [MountEntry(mountPoint: "/", isLocal: true)]
        })
        for _ in 0..<50 { _ = c.kind(forPath: "/Users/me/a.mp4") }
        XCTAssertEqual(reads, 1)
        c.refresh()
        _ = c.kind(forPath: "/Users/me/a.mp4")
        XCTAssertEqual(reads, 2)
    }

    func testSystemMountTableClassifiesRootAndTemporaryDirectoryAsLocal() {
        let table = VolumeClassifier.systemMountTable()
        XCTAssertNotNil(table)
        let c = VolumeClassifier(mountTable: { table })
        XCTAssertEqual(c.kind(forPath: "/"), .local)
        XCTAssertEqual(c.kind(forPath: NSTemporaryDirectory()), .local)
    }
}

final class NonLocalFileMetadataStoreTests: XCTestCase {

    func testMissReturnsPlaceholders() {
        let store = NonLocalFileMetadataStore(reader: { _ in NonLocalFileFacts(size: nil, existsAsFile: false) })
        let url = URL(fileURLWithPath: "/mnt/a.mp4")
        XCTAssertEqual(store.sizeString(for: url), "--")
        XCTAssertEqual(store.sizeSortKey(for: url), 0)
        XCTAssertFalse(store.existsAsFile(url))
        XCTAssertNil(store.facts(for: url))
    }

    func testStoredValueIsReturned() {
        let store = NonLocalFileMetadataStore(reader: { _ in NonLocalFileFacts(size: nil, existsAsFile: false) })
        let url = URL(fileURLWithPath: "/mnt/a.mp4")
        store.store(NonLocalFileFacts(size: 1_500_000, existsAsFile: true), for: url)
        XCTAssertEqual(store.sizeString(for: url),
                       ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file))
        XCTAssertEqual(store.sizeSortKey(for: url), 1_500_000)
        XCTAssertTrue(store.existsAsFile(url))
    }

    func testZeroSizeShowsPlaceholder() {
        let store = NonLocalFileMetadataStore(reader: { _ in NonLocalFileFacts(size: nil, existsAsFile: false) })
        let url = URL(fileURLWithPath: "/mnt/empty.mp4")
        store.store(NonLocalFileFacts(size: 0, existsAsFile: true), for: url)
        XCTAssertEqual(store.sizeString(for: url), "--")
    }

    func testValuesAreKeyedByStandardizedPath() {
        let store = NonLocalFileMetadataStore(reader: { _ in NonLocalFileFacts(size: nil, existsAsFile: false) })
        store.store(NonLocalFileFacts(size: 42, existsAsFile: true),
                    for: URL(fileURLWithPath: "/mnt/dir/../a.mp4"))
        XCTAssertEqual(store.sizeSortKey(for: URL(fileURLWithPath: "/mnt/a.mp4")), 42)
        XCTAssertEqual(NonLocalFileMetadataStore.key(for: URL(fileURLWithPath: "/mnt/./a.mp4")), "/mnt/a.mp4")
    }

    func testInvalidateAndRetain() {
        let store = NonLocalFileMetadataStore(reader: { _ in NonLocalFileFacts(size: nil, existsAsFile: false) })
        let a = URL(fileURLWithPath: "/mnt/a.mp4")
        let b = URL(fileURLWithPath: "/mnt/b.mp4")
        store.store(NonLocalFileFacts(size: 1, existsAsFile: true), for: a)
        store.store(NonLocalFileFacts(size: 2, existsAsFile: true), for: b)
        store.invalidate(a)
        XCTAssertNil(store.facts(for: a))
        XCTAssertNotNil(store.facts(for: b))
        store.retain(paths: [])
        XCTAssertNil(store.facts(for: b))
    }

    func testRequestReadsOffMainThreadInBatchesAndNotTwice() {
        let readsOnMain = NSLock()
        var mainThreadReads = 0
        var readCount = 0
        let store = NonLocalFileMetadataStore(reader: { _ in
            readsOnMain.lock()
            if Thread.isMainThread { mainThreadReads += 1 }
            readCount += 1
            readsOnMain.unlock()
            return NonLocalFileFacts(size: 10, existsAsFile: true)
        })
        let urls = (0..<45).map { URL(fileURLWithPath: "/mnt/f\($0).mp4") }
        let batches = 3   // 45 files, 20 per batch
        let done = expectation(description: "batches")
        done.expectedFulfillmentCount = batches
        var batchCallbacks = 0
        store.onBatch = {
            batchCallbacks += 1
            done.fulfill()
        }
        store.request(urls)
        store.request(urls)   // already requested: no second read
        wait(for: [done], timeout: 5)
        XCTAssertEqual(batchCallbacks, batches)
        XCTAssertEqual(readCount, 45)
        XCTAssertEqual(mainThreadReads, 0)
        XCTAssertEqual(store.sizeSortKey(for: urls[44]), 10)
        XCTAssertTrue(store.existsAsFile(urls[0]))
    }
}

final class DurationProbePolicyTests: XCTestCase {

    func testLocalVideoMayBeProbed() {
        XCTAssertTrue(DurationProbePolicy.mayStartProbe(volume: .local, fileKind: .video))
    }

    func testLocalMpgMayBeProbed() {
        XCTAssertTrue(DurationProbePolicy.mayStartProbe(volume: .local, fileKind: .mpg))
    }

    func testNonLocalVideoIsNeverProbed() {
        XCTAssertFalse(DurationProbePolicy.mayStartProbe(volume: .nonLocal, fileKind: .video))
    }

    func testNonLocalMpgIsNeverProbed() {
        XCTAssertFalse(DurationProbePolicy.mayStartProbe(volume: .nonLocal, fileKind: .mpg))
    }

    func testImagesAndGIFsAreNotProbesOnEitherVolume() {
        XCTAssertFalse(DurationProbePolicy.mayStartProbe(volume: .local, fileKind: .imageOrGIF))
        XCTAssertFalse(DurationProbePolicy.mayStartProbe(volume: .nonLocal, fileKind: .imageOrGIF))
    }
}

final class ReportedDurationLedgerTests: XCTestCase {

    func testFirstPositiveLengthIsAccepted() {
        var ledger = ReportedDurationLedger()
        XCTAssertTrue(ledger.accept(lengthMs: 93_000, for: "/mnt/a.mkv"))
    }

    func testSecondReportForTheSameItemIsIgnored() {
        var ledger = ReportedDurationLedger()
        XCTAssertTrue(ledger.accept(lengthMs: 93_000, for: "/mnt/a.mkv"))
        XCTAssertFalse(ledger.accept(lengthMs: 93_000, for: "/mnt/a.mkv"))
        XCTAssertFalse(ledger.accept(lengthMs: 94_500, for: "/mnt/a.mkv"))
    }

    func testZeroOrNegativeLengthIsIgnoredAndDoesNotUseUpTheItem() {
        var ledger = ReportedDurationLedger()
        XCTAssertFalse(ledger.accept(lengthMs: 0, for: "/mnt/a.mkv"))
        XCTAssertFalse(ledger.accept(lengthMs: -1, for: "/mnt/a.mkv"))
        XCTAssertTrue(ledger.accept(lengthMs: 5_000, for: "/mnt/a.mkv"))
    }

    func testItemsAreIndependent() {
        var ledger = ReportedDurationLedger()
        XCTAssertTrue(ledger.accept(lengthMs: 1_000, for: "/mnt/a.mkv"))
        XCTAssertTrue(ledger.accept(lengthMs: 2_000, for: "/mnt/b.mkv"))
    }

    func testNewQueueAcceptsTheItemAgain() {
        var ledger = ReportedDurationLedger()
        XCTAssertTrue(ledger.accept(lengthMs: 1_000, for: "/mnt/a.mkv"))
        ledger.removeAll()
        XCTAssertTrue(ledger.accept(lengthMs: 1_000, for: "/mnt/a.mkv"))
    }

    func testForgetRetainAndMove() {
        var ledger = ReportedDurationLedger()
        _ = ledger.accept(lengthMs: 1_000, for: "/mnt/a.mkv")
        _ = ledger.accept(lengthMs: 1_000, for: "/mnt/b.mkv")
        _ = ledger.accept(lengthMs: 1_000, for: "/mnt/c.mkv")
        ledger.forget("/mnt/a.mkv")
        XCTAssertTrue(ledger.accept(lengthMs: 1_000, for: "/mnt/a.mkv"))
        ledger.retain(paths: ["/mnt/b.mkv"])
        XCTAssertFalse(ledger.accept(lengthMs: 1_000, for: "/mnt/b.mkv"))
        XCTAssertTrue(ledger.accept(lengthMs: 1_000, for: "/mnt/c.mkv"))
        ledger.move(from: "/mnt/b.mkv", to: "/mnt/b2.mkv")
        XCTAssertFalse(ledger.accept(lengthMs: 1_000, for: "/mnt/b2.mkv"))
        XCTAssertTrue(ledger.accept(lengthMs: 1_000, for: "/mnt/b.mkv"))
    }
}
