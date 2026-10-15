import Foundation
import Darwin

// File metadata for queued files whose volume is not local.
//
// A file on a non-local volume (a network share, a FUSE or NFS mount) can take a long time to
// answer any file-system call. Everything here is Foundation-only so it can be unit tested, and
// none of it knows what kind of non-local volume it is looking at.

// MARK: - Volume classification

enum VolumeKind: Equatable {
    case local
    case nonLocal
}

/// One row of the kernel mount table.
struct MountEntry: Equatable {
    let mountPoint: String
    let isLocal: Bool
}

/// The single definition of "non-local": a file whose volume is not flagged local, or whose
/// volume cannot be read (no mount table, or no mount point covers the path).
///
/// The answer comes from the kernel mount table (`getfsstat` with `MNT_NOWAIT`), which is read
/// from memory and never contacts a file system. Asking a URL for `volumeIsLocalKey` would itself
/// be a file-system call on the very volume being classified. The table is read once and kept;
/// `refresh()` re-reads it and runs whenever a queue is loaded. A path that reaches a mount
/// through a symlink on a local volume is classified by its own path, so it counts as local.
final class VolumeClassifier {
    static let shared = VolumeClassifier()

    private let provider: () -> [MountEntry]?
    private let lock = NSLock()
    private var table: [MountEntry]?
    private var loaded = false

    init(mountTable provider: @escaping () -> [MountEntry]? = VolumeClassifier.systemMountTable) {
        self.provider = provider
    }

    func kind(for url: URL) -> VolumeKind {
        guard url.isFileURL else { return .local }
        return kind(forPath: url.path)
    }

    func kind(forPath path: String) -> VolumeKind {
        lock.lock()
        defer { lock.unlock() }
        if !loaded {
            table = provider()
            loaded = true
        }
        guard let table else { return .nonLocal }
        var best: MountEntry?
        for entry in table where Self.path(path, isInside: entry.mountPoint) {
            if best == nil || entry.mountPoint.count > best!.mountPoint.count { best = entry }
        }
        guard let best else { return .nonLocal }
        return best.isLocal ? .local : .nonLocal
    }

    /// Forget the cached table; the next lookup reads it again.
    func refresh() {
        lock.lock()
        loaded = false
        table = nil
        lock.unlock()
    }

    private static func path(_ path: String, isInside mountPoint: String) -> Bool {
        if mountPoint == "/" { return path.hasPrefix("/") }
        return path == mountPoint || path.hasPrefix(mountPoint + "/")
    }

    /// The live mount table, or nil when it cannot be read.
    static func systemMountTable() -> [MountEntry]? {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return nil }
        let buffer = Array<statfs>(unsafeUninitializedCapacity: Int(count)) { storage, initialized in
            let byteCount = Int32(MemoryLayout<statfs>.stride * Int(count))
            let filled = getfsstat(storage.baseAddress, byteCount, MNT_NOWAIT)
            initialized = filled > 0 ? Int(filled) : 0
        }
        guard !buffer.isEmpty else { return nil }
        return buffer.map { fs in
            var name = fs.f_mntonname
            let mountPoint = withUnsafePointer(to: &name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            return MountEntry(mountPoint: mountPoint,
                              isLocal: (fs.f_flags & UInt32(MNT_LOCAL)) != 0)
        }
    }
}

// MARK: - File facts cache

/// What the queue needs to know about one file: its size, and whether it exists as a file.
struct NonLocalFileFacts: Equatable {
    let size: Int64?
    let existsAsFile: Bool
}

/// Size and existence for non-local files, read off the main thread and cached by standardized
/// path. Until a file's facts arrive, its size shows as `--`, sorts as 0, and rename is
/// unavailable. Main-thread only, apart from the reads, which run on `readQueue`.
final class NonLocalFileMetadataStore {
    static let sizePlaceholder = "--"
    /// A batch is this many files. The queue page refreshes once per batch.
    static let batchSize = 20

    var onBatch: (() -> Void)?

    private let reader: (URL) -> NonLocalFileFacts
    private let readQueue = DispatchQueue(label: "dwb.nonlocal-file-facts", qos: .utility)
    private var facts: [String: NonLocalFileFacts] = [:]
    private var requested = Set<String>()

    init(reader: @escaping (URL) -> NonLocalFileFacts = NonLocalFileMetadataStore.readFromDisk) {
        self.reader = reader
    }

    static func key(for url: URL) -> String { url.standardizedFileURL.path }

    func facts(for url: URL) -> NonLocalFileFacts? { facts[Self.key(for: url)] }

    func store(_ value: NonLocalFileFacts, for url: URL) {
        let key = Self.key(for: url)
        facts[key] = value
        requested.insert(key)
    }

    func sizeString(for url: URL) -> String {
        guard let size = facts(for: url)?.size, size > 0 else { return Self.sizePlaceholder }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func sizeSortKey(for url: URL) -> Int64 { facts(for: url)?.size ?? 0 }

    /// Rename needs a file that is known to exist; unknown means unavailable.
    func existsAsFile(_ url: URL) -> Bool { facts(for: url)?.existsAsFile == true }

    /// Starts reading the facts of every URL not yet known or in flight. Returns at once.
    func request(_ urls: [URL]) {
        var wanted: [URL] = []
        for url in urls where requested.insert(Self.key(for: url)).inserted { wanted.append(url) }
        var start = 0
        while start < wanted.count {
            let batch = Array(wanted[start..<min(start + Self.batchSize, wanted.count)])
            start += Self.batchSize
            readQueue.async { [reader, weak self] in
                let results = batch.map { ($0, reader($0)) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    for (url, value) in results where self.requested.contains(Self.key(for: url)) {
                        self.facts[Self.key(for: url)] = value
                    }
                    self.onBatch?()
                }
            }
        }
    }

    func invalidate(_ url: URL) {
        let key = Self.key(for: url)
        facts.removeValue(forKey: key)
        requested.remove(key)
    }

    /// Drops everything not in `paths` (standardized). Reads still in flight for dropped paths
    /// are discarded when they land.
    func retain(paths: Set<String>) {
        facts = facts.filter { paths.contains($0.key) }
        requested = requested.filter { paths.contains($0) }
    }

    func removeAll() {
        facts.removeAll()
        requested.removeAll()
    }

    /// The one file-system call per file. Runs on `readQueue`.
    static func readFromDisk(_ url: URL) -> NonLocalFileFacts {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return NonLocalFileFacts(size: nil, existsAsFile: false)
        }
        let size = values.fileSize.flatMap { $0 >= 0 ? Int64($0) : nil }
        return NonLocalFileFacts(size: size, existsAsFile: values.isDirectory != true)
    }
}

// MARK: - Duration probing policy

/// Player reads no duration off a non-local volume on its own: each file a probe touches makes
/// a network mount fetch tens of megabytes, and a large folder would queue hundreds of them.
/// A non-local file's duration arrives from VLC when the file plays. This is the one place the
/// rule is written down.
enum DurationProbePolicy {
    enum FileKind: Equatable {
        case video
        /// `.mpg`, whose duration needs the repeated stable-duration read.
        case mpg
        /// Images and GIFs have their own duration handling and are never probed.
        case imageOrGIF
    }

    /// True when player may start a duration probe (an `AVURLAsset` load or a VLC parse) for a
    /// file. Local video and `.mpg` files: yes. Anything non-local: no.
    static func mayStartProbe(volume: VolumeKind, fileKind: FileKind) -> Bool {
        switch fileKind {
        case .imageOrGIF: return false
        case .video, .mpg: return volume == .local
        }
    }
}

/// Which items of one queue already had a length reported by VLC. A non-local item's length is
/// stored the first time VLC reports one above 0; later reports for the same item are ignored.
/// Keyed by `NonLocalFileMetadataStore.key(for:)`. Main-thread only.
struct ReportedDurationLedger {
    private var reported = Set<String>()

    /// True only for the first report above 0 for `key`.
    mutating func accept(lengthMs: Int, for key: String) -> Bool {
        guard lengthMs > 0 else { return false }
        return reported.insert(key).inserted
    }

    mutating func forget(_ key: String) { reported.remove(key) }

    mutating func move(from oldKey: String, to newKey: String) {
        if reported.remove(oldKey) != nil { reported.insert(newKey) }
    }

    /// Drops everything not in `paths` (standardized).
    mutating func retain(paths: Set<String>) { reported = reported.filter { paths.contains($0) } }

    mutating func removeAll() { reported.removeAll() }
}
