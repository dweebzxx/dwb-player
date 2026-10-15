import Foundation
import XCTest
import ImageIO
import UniformTypeIdentifiers

/// P138: Queue GIF durations load off the main thread, are cached per file, and reject stale results.
final class GIFDurationMetadataTests: XCTestCase {

    /// Captures scheduled scans so each test decides when (and whether) they complete.
    private final class ManualScheduler {
        private(set) var requests: [(url: URL, complete: (GIFLoopDuration) -> Void)] = []
        private(set) var cancelledPaths: [String] = []

        var scheduler: GIFDurationStore.Scheduler {
            { [unowned self] url, completion in
                requests.append((url, completion))
                return { [unowned self] in cancelledPaths.append(url.path) }
            }
        }

        func complete(_ index: Int, with result: GIFLoopDuration) {
            requests[index].complete(result)
        }
    }

    private let gifA = URL(fileURLWithPath: "/tmp/dwb-p138/a.gif")
    private let gifB = URL(fileURLWithPath: "/tmp/dwb-p138/b.gif")

    // MARK: - Store policy

    func testUnresolvedLookupReturnsPendingBeforeReaderCompletes() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolved: [URL] = []
        store.onResolved = { url, _ in resolved.append(url) }

        XCTAssertEqual(store.lookup(gifA), .pending)
        XCTAssertEqual(manual.requests.count, 1)
        XCTAssertTrue(resolved.isEmpty)

        manual.complete(0, with: .seconds(0.5))
        XCTAssertEqual(resolved, [gifA])
        XCTAssertEqual(store.lookup(gifA), .resolved(.seconds(0.5)))
    }

    func testDuplicateLookupsWhilePendingScheduleOneScan() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)

        for _ in 0..<5 { XCTAssertEqual(store.lookup(gifA), .pending) }
        // The same file reached through a non-standardized URL is the same request.
        XCTAssertEqual(store.lookup(URL(fileURLWithPath: "/tmp/dwb-p138/./a.gif")), .pending)
        XCTAssertEqual(manual.requests.count, 1)
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testResolvedMetadataIsReusedWithoutRescan() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        _ = store.lookup(gifA)
        manual.complete(0, with: .seconds(1.2))

        for _ in 0..<5 { XCTAssertEqual(store.lookup(gifA), .resolved(.seconds(1.2))) }
        XCTAssertEqual(manual.requests.count, 1)
    }

    func testLoopCountChangeWhilePendingUsesLatestMultiplierWithoutRescan() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var loopCount = 1
        var accepted: MediaFileSupport.DurationMetadata?
        // Mirrors the controller: projection reads the loop count at acceptance time.
        store.onResolved = { _, result in accepted = result.durationMetadata(loopCount: loopCount) }

        _ = store.lookup(gifA)
        loopCount = 5
        XCTAssertEqual(store.lookup(gifA), .pending)   // settings refresh while pending
        manual.complete(0, with: .seconds(0.5))

        XCTAssertEqual(manual.requests.count, 1)
        XCTAssertEqual(accepted?.seconds ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(accepted?.displayString, "0:02")
    }

    func testLoopCountChangeAfterResolutionUsesLatestMultiplierWithoutRescan() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        _ = store.lookup(gifA)
        manual.complete(0, with: .seconds(7))

        for (loops, expected) in [(1, 7.0), (3, 21.0), (10, 70.0)] {
            guard case .resolved(let result) = store.lookup(gifA) else { return XCTFail("expected resolved") }
            let metadata = result.durationMetadata(loopCount: loops)
            XCTAssertEqual(metadata.seconds ?? 0, expected, accuracy: 0.0001)
            XCTAssertEqual(metadata.displayString, MediaFileSupport.formatPlaybackDuration(expected))
        }
        XCTAssertEqual(manual.requests.count, 1)
    }

    func testClearRejectsLateCompletion() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolvedCount = 0
        store.onResolved = { _, _ in resolvedCount += 1 }

        _ = store.lookup(gifA)
        _ = store.lookup(gifB)
        store.removeAll()
        manual.complete(0, with: .seconds(1))
        manual.complete(1, with: .seconds(2))

        XCTAssertEqual(resolvedCount, 0)
        XCTAssertNil(store.resolvedResult(for: gifA))
        XCTAssertNil(store.resolvedResult(for: gifB))
        XCTAssertEqual(Set(manual.cancelledPaths), [gifA.path, gifB.path])
    }

    func testRemovalRejectsLateCompletionAndReAddRequestsFreshScan() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolvedCount = 0
        store.onResolved = { _, _ in resolvedCount += 1 }

        _ = store.lookup(gifA)
        store.invalidate(gifA)
        manual.complete(0, with: .seconds(1))
        XCTAssertEqual(resolvedCount, 0)
        XCTAssertNil(store.resolvedResult(for: gifA))

        // Re-adding the file starts a new request; only that one is accepted.
        XCTAssertEqual(store.lookup(gifA), .pending)
        XCTAssertEqual(manual.requests.count, 2)
        manual.complete(1, with: .seconds(3))
        XCTAssertEqual(resolvedCount, 1)
        XCTAssertEqual(store.resolvedResult(for: gifA), .seconds(3))
    }

    func testQueueReplacementKeepsSharedEntriesAndRejectsDroppedRequests() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolved: [URL] = []
        store.onResolved = { url, _ in resolved.append(url) }

        _ = store.lookup(gifA)
        manual.complete(0, with: .seconds(1))
        resolved.removeAll()
        _ = store.lookup(gifB)

        store.retain(paths: [GIFDurationStore.key(for: gifA)])
        manual.complete(1, with: .seconds(2))

        XCTAssertTrue(resolved.isEmpty)
        XCTAssertNil(store.resolvedResult(for: gifB))
        XCTAssertEqual(store.lookup(gifA), .resolved(.seconds(1)))
        XCTAssertEqual(manual.requests.count, 2)
    }

    func testRenameDropsPendingRequestAndMovesResolvedResult() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolvedCount = 0
        store.onResolved = { _, _ in resolvedCount += 1 }
        let renamedA = URL(fileURLWithPath: "/tmp/dwb-p138/a-renamed.gif")
        let renamedB = URL(fileURLWithPath: "/tmp/dwb-p138/b-renamed.gif")

        // Resolved: moves to the new path with no rescan.
        _ = store.lookup(gifA)
        manual.complete(0, with: .seconds(4))
        store.move(from: gifA, to: renamedA)
        XCTAssertNil(store.resolvedResult(for: gifA))
        XCTAssertEqual(store.lookup(renamedA), .resolved(.seconds(4)))

        // Pending: the old request's completion cannot land on either path.
        _ = store.lookup(gifB)
        store.move(from: gifB, to: renamedB)
        manual.complete(1, with: .seconds(9))
        XCTAssertNil(store.resolvedResult(for: gifB))
        XCTAssertNil(store.resolvedResult(for: renamedB))
        XCTAssertEqual(resolvedCount, 1)
        XCTAssertEqual(store.lookup(renamedB), .pending)
        XCTAssertEqual(manual.requests.count, 3)
    }

    func testSupersededRequestCannotOverwriteNewerMetadata() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolvedCount = 0
        store.onResolved = { _, _ in resolvedCount += 1 }

        _ = store.lookup(gifA)
        // Active playback scanned the same file synchronously first.
        store.record(.seconds(2), for: gifA)
        manual.complete(0, with: .unreadable)

        XCTAssertEqual(store.resolvedResult(for: gifA), .seconds(2))
        XCTAssertEqual(resolvedCount, 0)
        XCTAssertEqual(manual.cancelledPaths, [gifA.path])
    }

    func testUnreadableResolvesToExistingFallbackWithoutRepeatedScans() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        _ = store.lookup(gifA)
        manual.complete(0, with: .unreadable)

        for _ in 0..<5 { XCTAssertEqual(store.lookup(gifA), .resolved(.unreadable)) }
        XCTAssertEqual(manual.requests.count, 1)

        let metadata = GIFLoopDuration.unreadable.durationMetadata(loopCount: 3)
        let expected = MediaFileSupport.fallbackGIFPlaybackDurationSeconds(loopCount: 3)
        XCTAssertEqual(metadata.seconds, expected)
        XCTAssertEqual(metadata.displayString, MediaFileSupport.formatPlaybackDuration(expected))

        // An explicit folder rescan forgets the failure so the file is retried.
        store.retain(paths: [GIFDurationStore.key(for: gifA)], dropUnreadable: true)
        XCTAssertEqual(store.lookup(gifA), .pending)
        XCTAssertEqual(manual.requests.count, 2)
    }

    func testRescanKeepsResolvedDurationsForRetainedFiles() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        _ = store.lookup(gifA)
        manual.complete(0, with: .seconds(1))

        store.retain(paths: [GIFDurationStore.key(for: gifA)], dropUnreadable: true)
        XCTAssertEqual(store.lookup(gifA), .resolved(.seconds(1)))
        XCTAssertEqual(manual.requests.count, 1)
    }

    func testCancelPendingStopsRequestsAndLaterLookupAsksAgain() {
        let manual = ManualScheduler()
        let store = GIFDurationStore(schedule: manual.scheduler)
        var resolvedCount = 0
        store.onResolved = { _, _ in resolvedCount += 1 }

        _ = store.lookup(gifA)
        _ = store.lookup(gifB)
        store.cancelPending(keys: [GIFDurationStore.key(for: gifA)])
        manual.complete(0, with: .seconds(1))
        XCTAssertEqual(resolvedCount, 0)
        XCTAssertEqual(manual.cancelledPaths, [gifA.path])
        XCTAssertEqual(store.pendingCount, 1)

        XCTAssertEqual(store.lookup(gifA), .pending)
        XCTAssertEqual(manual.requests.count, 3)
    }

    func testRefreshPolicyBatchesLargeLoadsAndFlushesTheTail() {
        let batch = GIFDurationRefreshPolicy.batchSize
        XCTAssertFalse(GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: 0, pendingCount: 0))
        XCTAssertFalse(GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: 1, pendingCount: 4_000))
        XCTAssertFalse(GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: batch - 1, pendingCount: 1))
        XCTAssertTrue(GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: batch, pendingCount: 4_000))
        XCTAssertTrue(GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: 3, pendingCount: 0))

        // 4,000 results arriving one at a time rebuild Queue 40 times, not 4,000.
        var pending = 4_000, since = 0, refreshes = 0
        while pending > 0 {
            pending -= 1; since += 1
            if GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: since, pendingCount: pending) {
                refreshes += 1; since = 0
            }
        }
        XCTAssertEqual(refreshes, 4_000 / batch)
        XCTAssertEqual(since, 0)
    }

    // MARK: - Intake progress

    func testIntakeProgressCountsResolvedAndRemovedKeysAsFinished() {
        var progress = GIFDurationIntakeProgress(keys: ["/a.gif", "/b.gif", "/c.gif", "/d.gif"])
        XCTAssertEqual(progress.total, 4)
        XCTAssertEqual(progress.finished, 0)

        progress.finish("/a.gif")
        progress.finish("/a.gif")            // duplicate result
        progress.finish("/elsewhere.gif")    // not part of this intake
        XCTAssertEqual(progress.finished, 1)

        progress.retain(paths: ["/c.gif", "/d.gif", "/new.gif"])   // rescan/replace removed b
        XCTAssertEqual(progress.finished, 2)
        XCTAssertFalse(progress.isComplete)

        progress.retain(paths: [])                                  // Clear Queue
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.finished, 4)
    }

    func testFolderScanReportsRunningFoundCount() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileCount = MediaFileSupport.foundProgressInterval * 2 + 10
        for index in 0..<fileCount {
            try Data().write(to: dir.appendingPathComponent("clip\(index).mp4"))
        }
        try Data().write(to: dir.appendingPathComponent("notes.txt"))

        var reported: [Int] = []
        let result = try MediaFileSupport.expandToSupportedMedia([dir],
                                                                 acceptedKinds: [.video, .image, .gif],
                                                                 shouldCancel: { false },
                                                                 onFound: { reported.append($0) })
        XCTAssertEqual(result.media.count, fileCount)
        let interval = MediaFileSupport.foundProgressInterval
        XCTAssertEqual(reported, [interval, interval * 2, fileCount])
    }

    // MARK: - Background loader

    func testLoaderReadsOffMainThreadAndAcceptsOnMainThread() {
        let readerRanOnMain = Locked<Bool?>(nil)
        let loader = GIFDurationLoader(reader: { _ in
            readerRanOnMain.set(Thread.isMainThread)
            return .seconds(0.3)
        })
        let store = GIFDurationStore(loader: loader)
        let accepted = expectation(description: "accepted")
        store.onResolved = { url, result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(url, self.gifA)
            XCTAssertEqual(result, .seconds(0.3))
            accepted.fulfill()
        }

        XCTAssertEqual(store.lookup(gifA), .pending)
        wait(for: [accepted], timeout: 5)
        XCTAssertEqual(readerRanOnMain.value, false)
        XCTAssertEqual(store.lookup(gifA), .resolved(.seconds(0.3)))
    }

    func testLoaderRunsAtMostTwoScansAtOnce() {
        XCTAssertEqual(GIFDurationLoader.maxConcurrentScans, 2)
        let active = Locked(0)
        let peak = Locked(0)
        let started = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        let loader = GIFDurationLoader(reader: { _ in
            let now = active.update { $0 += 1; return $0 }
            peak.update { $0 = max($0, now); return $0 }
            started.signal()
            gate.wait()
            active.update { $0 -= 1; return $0 }
            return .seconds(1)
        })

        let total = 6
        let done = expectation(description: "all scans delivered")
        done.expectedFulfillmentCount = total
        for index in 0..<total {
            _ = loader.load(URL(fileURLWithPath: "/tmp/dwb-p138/\(index).gif")) { _ in done.fulfill() }
        }
        // Two scans block on the gate before any is released, so the bound is contended.
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        for _ in 0..<total { gate.signal() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(peak.value, 2)
    }

    // MARK: - ImageIO reader parity

    func testImageIOReaderReturnsIntrinsicLoopMatchingExistingDurations() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gif = try createTestGIF(in: dir, frameCount: 5, delay: 0.1)
        let tinyDelayGIF = try createTestGIF(in: dir, frameCount: 4, delay: 0.01)
        let unreadable = dir.appendingPathComponent("broken.gif")
        try Data("not a gif".utf8).write(to: unreadable)

        for url in [gif, tinyDelayGIF, unreadable] {
            let result = GIFDurationLoader.imageIOReader(url)
            for loops in [1, 3, 5, 10] {
                let existing = MediaFileSupport.configuredImageDurationMetadata(for: url,
                                                                               stillImageDurationSeconds: 3,
                                                                               gifLoopCount: loops)
                let projected = result.durationMetadata(loopCount: loops)
                XCTAssertEqual(projected.seconds ?? -1, existing.seconds ?? -2, accuracy: 0.0001, url.lastPathComponent)
                XCTAssertEqual(projected.displayString, existing.displayString, url.lastPathComponent)
            }
        }
        guard case .seconds(let loop) = GIFDurationLoader.imageIOReader(gif) else { return XCTFail("expected seconds") }
        XCTAssertEqual(loop, 0.5, accuracy: 0.0001)
        guard case .seconds(let clampedLoop) = GIFDurationLoader.imageIOReader(tinyDelayGIF) else { return XCTFail("expected seconds") }
        XCTAssertEqual(clampedLoop, 4 * 0.02, accuracy: 0.0001)
        XCTAssertEqual(GIFDurationLoader.imageIOReader(unreadable), .unreadable)
    }

    // MARK: - Helpers

    private final class Locked<Value> {
        private let lock = NSLock()
        private var stored: Value
        init(_ value: Value) { stored = value }
        var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ newValue: Value) { lock.lock(); stored = newValue; lock.unlock() }
        @discardableResult
        func update(_ body: (inout Value) -> Value) -> Value {
            lock.lock(); defer { lock.unlock() }
            return body(&stored)
        }
    }

    private func createTestGIF(in dir: URL, frameCount: Int, delay: Double) throws -> URL {
        let url = dir.appendingPathComponent("test-\(UUID().uuidString).gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil),
              let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "test", code: 1)
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let image = context.makeImage() else { throw NSError(domain: "test", code: 2) }
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay,
                                                          kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        for _ in 0..<frameCount { CGImageDestinationAddImage(destination, image, properties) }
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "test", code: 3) }
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwbTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
