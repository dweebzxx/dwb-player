import Foundation

/// P138: Queue-facing GIF duration metadata. The frame scan behind a GIF's duration
/// (`CGImageSourceGetCount` plus per-frame timing reads) can block for seconds on
/// large files or slow storage, so Queue rebuilds and settings refreshes never run it
/// on the main thread. They read this per-window store instead; missing entries are
/// scanned by the shared bounded loader and accepted back on the main thread.

/// The GIF's intrinsic duration for one loop. The configured loop multiplier is
/// applied at projection time so a loop-count change never needs a rescan.
enum GIFLoopDuration: Equatable {
    case seconds(Double)
    /// ImageIO could not produce frame timing; projects to the existing fallback.
    case unreadable

    init(_ metadata: MediaFileSupport.GIFPlaybackMetadata?) {
        if let metadata {
            self = .seconds(metadata.loopDurationSeconds)
        } else {
            self = .unreadable
        }
    }

    /// Same arithmetic and formatting as `MediaFileSupport.configuredImageDurationMetadata`.
    func durationMetadata(loopCount: Int) -> MediaFileSupport.DurationMetadata {
        let total: Double
        switch self {
        case .seconds(let loopSeconds):
            total = loopSeconds * Double(max(1, loopCount))
        case .unreadable:
            total = MediaFileSupport.fallbackGIFPlaybackDurationSeconds(loopCount: loopCount)
        }
        return MediaFileSupport.DurationMetadata(seconds: total,
                                                 displayString: MediaFileSupport.formatPlaybackDuration(total))
    }
}

/// Runs GIF scans on a small shared background queue and delivers results on main.
final class GIFDurationLoader {
    typealias Reader = (URL) -> GIFLoopDuration

    /// At most this many GIF scans run at once across all windows; further
    /// requests wait in the queue (and are cancelled if invalidated first).
    static let maxConcurrentScans = 2
    static let shared = GIFDurationLoader()

    static let imageIOReader: Reader = { url in
        GIFLoopDuration(MediaFileSupport.gifPlaybackMetadata(for: url, loopCount: 1))
    }

    private let queue: OperationQueue
    private let reader: Reader

    init(reader: @escaping Reader = GIFDurationLoader.imageIOReader,
         maxConcurrentScans: Int = GIFDurationLoader.maxConcurrentScans) {
        self.reader = reader
        queue = OperationQueue()
        queue.name = "com.dwb.gif-duration-metadata"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = maxConcurrentScans
    }

    /// Returns a cancel handle. A cancelled request that has not started never reads
    /// the file; a cancelled request already running still finishes its scan, and its
    /// result is discarded by the caller's request token.
    func load(_ url: URL, completion: @escaping (GIFLoopDuration) -> Void) -> () -> Void {
        let reader = self.reader
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard operation?.isCancelled == false else { return }
            let result = reader(url)
            DispatchQueue.main.async { completion(result) }
        }
        queue.addOperation(operation)
        return { operation.cancel() }
    }
}

/// Per-window GIF duration state, keyed by standardized file path. Main-thread only.
final class GIFDurationStore {
    typealias Scheduler = (URL, @escaping (GIFLoopDuration) -> Void) -> (() -> Void)

    enum Lookup: Equatable {
        case resolved(GIFLoopDuration)
        case pending
    }

    /// Called on main when a still-current request resolves.
    var onResolved: ((URL, GIFLoopDuration) -> Void)?

    private let schedule: Scheduler
    private var resolved: [String: GIFLoopDuration] = [:]
    private var pending: [String: (token: UInt64, cancel: () -> Void)] = [:]
    private var nextToken: UInt64 = 0

    init(schedule: @escaping Scheduler) {
        self.schedule = schedule
    }

    convenience init(loader: GIFDurationLoader = .shared) {
        self.init(schedule: { url, completion in loader.load(url, completion: completion) })
    }

    static func key(for url: URL) -> String { url.standardizedFileURL.path }

    /// Returns resolved metadata, or `.pending` after ensuring exactly one request is in flight.
    func lookup(_ url: URL) -> Lookup {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = Self.key(for: url)
        if let result = resolved[key] { return .resolved(result) }
        if pending[key] == nil {
            nextToken &+= 1
            let token = nextToken
            // Insert before scheduling so a synchronous scheduler still finds the token.
            pending[key] = (token, {})
            let cancel = schedule(url) { [weak self] result in
                self?.accept(result, key: key, url: url, token: token)
            }
            if pending[key]?.token == token { pending[key] = (token, cancel) }
        }
        return resolved[key].map(Lookup.resolved) ?? .pending
    }

    /// Records a result read synchronously elsewhere (active playback); supersedes any pending request.
    func record(_ result: GIFLoopDuration, for url: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = Self.key(for: url)
        pending.removeValue(forKey: key)?.cancel()
        resolved[key] = result
    }

    func resolvedResult(for url: URL) -> GIFLoopDuration? {
        resolved[Self.key(for: url)]
    }

    func invalidate(_ url: URL) {
        let key = Self.key(for: url)
        pending.removeValue(forKey: key)?.cancel()
        resolved.removeValue(forKey: key)
    }

    func removeAll() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        resolved.removeAll()
    }

    /// Drops everything whose path is not in `paths`. With `dropUnreadable`, also
    /// forgets cached failures so an explicit rescan retries them.
    func retain(paths: Set<String>, dropUnreadable: Bool = false) {
        for key in Array(pending.keys) where !paths.contains(key) {
            pending.removeValue(forKey: key)?.cancel()
        }
        resolved = resolved.filter { key, result in
            paths.contains(key) && !(dropUnreadable && result == .unreadable)
        }
    }

    /// Rename: a resolved result describes the same file and moves; a pending request
    /// for the old path is dropped so its completion cannot land on the new path.
    func move(from oldURL: URL, to newURL: URL) {
        let oldKey = Self.key(for: oldURL)
        let newKey = Self.key(for: newURL)
        guard oldKey != newKey else { return }
        pending.removeValue(forKey: oldKey)?.cancel()
        pending.removeValue(forKey: newKey)?.cancel()
        if let result = resolved.removeValue(forKey: oldKey) {
            resolved[newKey] = result
        } else {
            resolved.removeValue(forKey: newKey)
        }
    }

    /// Stops the given pending requests without recording a result; a later lookup asks again.
    func cancelPending(keys: Set<String>) {
        for key in keys { pending.removeValue(forKey: key)?.cancel() }
    }

    var pendingCount: Int { pending.count }

    private func accept(_ result: GIFLoopDuration, key: String, url: URL, token: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard pending[key]?.token == token else { return }
        pending.removeValue(forKey: key)
        resolved[key] = result
        onResolved?(url, result)
    }
}

/// P138: when accepted GIF results rebuild Queue. Queue reloads every row, so a large
/// queue refreshes once per `batchSize` results and once more when nothing is pending.
enum GIFDurationRefreshPolicy {
    static let batchSize = 100

    static func shouldRefresh(acceptedSinceRefresh: Int, pendingCount: Int) -> Bool {
        acceptedSinceRefresh > 0 && (pendingCount == 0 || acceptedSinceRefresh >= batchSize)
    }
}

/// P138: progress of one intake's GIF duration loading, by store key. Keys that resolve,
/// or leave the queue, count as finished so the card always reaches its total.
struct GIFDurationIntakeProgress: Equatable {
    /// Smaller intakes load without a card.
    static let minimumTrackedCount = 10

    let total: Int
    private(set) var remaining: Set<String>

    init(keys: Set<String>) {
        total = keys.count
        remaining = keys
    }

    var finished: Int { total - remaining.count }
    var isComplete: Bool { remaining.isEmpty }

    mutating func finish(_ key: String) { remaining.remove(key) }
    mutating func retain(paths: Set<String>) { remaining.formIntersection(paths) }
}
