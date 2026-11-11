import Cocoa
import VLCKitSPM

enum QueueSortMode: Int, CaseIterable {
    case manual = 0
    case filenameAscending
    case filenameDescending
    case fileSizeAscending
    case fileSizeDescending
    case durationAscending
    case durationDescending

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .filenameAscending:
            return "Name A-Z"
        case .filenameDescending:
            return "Name Z-A"
        case .fileSizeAscending:
            return "Size Low-High"
        case .fileSizeDescending:
            return "Size High-Low"
        case .durationAscending:
            return "Duration Short-Long"
        case .durationDescending:
            return "Duration Long-Short"
        }
    }
}

struct PlaybackSpeedOption: Equatable {
    let rate: Float
    let title: String

    var tag: Int { Self.tag(for: rate) }

    static let normalRate: Float = 1.0

    static let all: [PlaybackSpeedOption] = [
        .init(rate: 0.25, title: "0.25x"),
        .init(rate: 0.50, title: "0.50x"),
        .init(rate: 0.75, title: "0.75x"),
        .init(rate: 1.00, title: "1.00x Normal"),
        .init(rate: 1.25, title: "1.25x"),
        .init(rate: 1.50, title: "1.50x"),
        .init(rate: 2.00, title: "2.00x"),
        .init(rate: 2.50, title: "2.50x"),
        .init(rate: 3.00, title: "3.00x"),
    ]

    static func tag(for rate: Float) -> Int {
        Int((rate * 100).rounded())
    }

    static func option(forTag tag: Int) -> PlaybackSpeedOption? {
        all.first { $0.tag == tag }
    }

    static func validated(_ rate: Float) -> PlaybackSpeedOption {
        all.min { lhs, rhs in
            abs(lhs.rate - rate) < abs(rhs.rate - rate)
        } ?? all[3]
    }
}

class PlayerWindowController: NSWindowController {

    private static var nextDebugOrdinal = 1
    private static let defaultWindowTitle = "dwb player"

    private(set) var player: VLCMediaPlayer!
    private var videoSurface: VideoSurfaceView!
    private var transport: TransportControlsView!
    private var volumeBar: VolumeBarView!
    private var audioDelayBar: AudioDelayBarView!
    private var queuePage: QueuePageView!
    private let intakeRecoveryView = IntakeRecoveryView()
    private let centeredTitleLabel = NSTextField(labelWithString: PlayerWindowController.defaultWindowTitle)
    private let debugOrdinal: Int

    var debugIdentity: String { "player-\(debugOrdinal)" }

    // MARK: - Fullscreen state

    private var isFullscreen         = false
    /// True from windowWillEnterFullScreen until windowDidEnterFullScreen.
    /// Guards windowDidResize from writing styleMask during AppKit's entry animation.
    private var isEnteringFullscreen = false
    /// True from windowWillExitFullScreen until the deferred cleanup block in
    /// windowDidExitFullScreen clears it.  Set EARLY (in windowWillExitFullScreen)
    /// so that exit-animation resize callbacks already see the exiting state.
    private var isExitingFullscreen  = false

    // MARK: - Layout mode (single source of truth)

    private enum LayoutMode { case fullscreen, exitingFullscreenSettling, windowed }

    /// Authoritative layout mode consumed by layoutPlayerViews() and setFullscreenStyle().
    ///
    /// Precedence:
    ///   isExitingFullscreen → .exitingFullscreenSettling  (windowed baseline)
    ///   isFullscreen        → .fullscreen                 (HUD layout)
    ///   otherwise           → .windowed                   (windowed baseline)
    ///
    /// .exitingFullscreenSettling takes priority over .fullscreen so that exit-animation
    /// resize callbacks (which still see isFullscreen=true) choose windowed geometry,
    /// not fullscreen HUD geometry.
    private var layoutMode: LayoutMode {
        if isExitingFullscreen { return .exitingFullscreenSettling }
        if isFullscreen        { return .fullscreen }
        return .windowed
    }

    private var updateTimer:   Timer?
    private var hideHUDTimer:  Timer?
    private var trackingArea:  NSTrackingArea?

    // MARK: - Titlebar auto-hide state

    /// Weak ref to the system titlebar view (superview of traffic-light buttons).
    /// Captured once in installCenteredTitleLabel and used for fade animations.
    private weak var titlebarContainerView:       NSView?
    private var titlebarTriggerTrackingArea:      NSTrackingArea?
    private var titlebarHideTimer:                Timer?
    /// True while the titlebar is in the faded-out (hidden) state.
    private var titlebarIsHidden                  = false

    // M6: dirty flag set by VLC state callbacks; consumed by the 0.25 s timer.
    // Initialized true so the first timer tick initialises transport button states.
    private var needsTransportUpdate = true
    // M4: set by windowOcclusionStateDidChange when window becomes visible; triggers one forced refresh.
    private var needsForceRefreshOnReturn = false

    // Generation tokens prevent stale fade-out completion handlers from re-hiding
    // a view that has already been shown again.
    private var hudShowGeneration          = 0

    // MARK: - Video title overlay

    private let videoTitleOverlay    = TitleOverlayView()

    // MARK: - Transient messages over the video

    private let failureMessageView   = FailureMessageView()
    private let undoToastView        = UndoToastView()
    /// Non-modal status HUD (scale mode, window limit). Takes the volume HUD's slot.
    private let statusHUDView        = StatusHUDView()
    private let dropZoneOverlay      = DropZoneOverlayView()

    // MARK: - Keep-at-top

    /// Per-window keep-on-top state.  Not persisted (defaults off for each new window).
    private(set) var isKeepAtTop = false

    // MARK: - Window opacity

    /// Per-window opacity state. Every new window starts at 100%; nothing is stored.
    private var windowOpacity: CGFloat = SettingsWindowController.defaultPlayerWindowOpacityValue
    var currentWindowOpacity: CGFloat { windowOpacity }

    // MARK: - Dock and Settings targeting

    private static var nextTargetingStamp: UInt64 = 0
    private static func makeTargetingStamp() -> UInt64 {
        nextTargetingStamp += 1
        return nextTargetingStamp
    }
    /// Order stamps read by the Dock reopen and Settings target choices.
    private var lastKeyStamp: UInt64 = 0
    private var minimizeStamp: UInt64?
    /// Outline shown while this window is the Settings target and Settings is on screen.
    private let settingsTargetOutline = SettingsTargetOutlineView()
    private var isSettingsTargetOutlineRequested = false
    /// Set in windowWillClose. A closed window starts no playback and takes no sleep assertion.
    private var isWindowClosed = false

    // MARK: - Sleep prevention

    /// ProcessInfo activity token that blocks display and system idle sleep during video playback.
    /// nil when no assertion is held. Non-nil only while a non-image item is actively playing.
    private var playbackActivity: NSObjectProtocol?

    // MARK: - Seek accumulation

    /// Accumulated seek target for rapid arrow-key holds.
    private var seekTargetMs: Int? = nil
    private var seekTargetResetTimer: Timer? = nil

    // MARK: - Scale

    private(set) var scaleMode: ScaleMode = .fit

    // H4: last-applied scale state — skips redundant VLC writes during live resize/transition.
    private struct AppliedScaleState: Equatable {
        var mode: ScaleMode; var width: Int; var height: Int
    }
    private var lastAppliedScaleState: AppliedScaleState? = nil

    // M2: last-applied fullscreen style flag — skips redundant style writes during live resize.
    private var lastAppliedIsFullscreenStyle: Bool? = nil

    // MARK: - Playback set

    /// Current media URL being played.
    private(set) var currentMediaURL: URL?

    /// Master list of URLs for this window's playback set.
    /// Established by open/drop; never reordered.
    private(set) var playbackSet: [URL] = []

    /// Navigation order: indices into `playbackSet`.
    /// Natural order: [0, 1, 2, …, n-1].
    /// Shuffled:      a permutation of the same indices.
    private var displayOrder: [Int] = []

    /// Explicit folder URLs opened or dropped into this window's queue, in addition order.
    /// Used by the Rescan Folder action to re-enumerate folder contents.
    /// Cleared when the queue is fully replaced or removed.
    private var sourceFolderURLs: [URL] = []
    private var folderScanGeneration: UInt64 = 0
    private var folderScanTask: Task<Void, Never>?
    private enum IntakeRecoveryRetryContext {
        case intake(urls: [URL], appendingExplicitFiles: Bool, isDragDrop: Bool)
        case rescan(folders: [URL])
    }
    private var intakeRecoveryRetryContext: IntakeRecoveryRetryContext?
    private var intakeRecoverySourceURLs: [URL] = []

    /// Current position in `displayOrder`. -1 when no set is loaded.
    private var currentDisplayIndex: Int = -1

    /// Ordered pending Play Next chain (FIFO) stored as set indices into `playbackSet`.
    private var pendingPlayNextSetIndices: [Int] = []

    /// The most recent marker-prefix rename in this window. It is deliberately
    /// not shared between player windows and is cleared after one undo attempt.
    private var markerRenameUndoState = MarkerRenameUndoState() {
        didSet { queuePage?.isUndoAvailable = markerRenameUndoState.canUndo }
    }

    /// Standardized paths of files whose playback failed in this window. The Queue Page
    /// marks them as failed; the set never changes playback, skipping, or the queue.
    private var failedPlaybackPaths = Set<String>()

    /// Index into `playbackSet` for the item currently playing.
    var currentSetIndex: Int {
        guard currentDisplayIndex >= 0, currentDisplayIndex < displayOrder.count else { return -1 }
        return displayOrder[currentDisplayIndex]
    }

    var canRenameCurrentMedia: Bool {
        guard currentSetIndex >= 0, currentSetIndex < playbackSet.count,
              let url = currentMediaURL,
              url.isFileURL,
              playbackSet[currentSetIndex].standardizedFileURL.path == url.standardizedFileURL.path else {
            return false
        }

        // P142: a file on a non-local volume is never checked on the main thread. Rename is
        // unavailable until the background read has finished.
        if VolumeClassifier.shared.kind(for: url) == .nonLocal {
            return nonLocalFiles.existsAsFile(url)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return true
    }

    var canUndoMarkerRename: Bool {
        markerRenameUndoState.canUndo
    }

    var hasPrevious: Bool { currentDisplayIndex > 0 }
    var hasNext:     Bool { canAdvanceAfterCompletion }

    var isCurrentItemBookmarked: Bool {
        guard let url = currentMediaURL else { return false }
        return BookmarkStore.shared.isBookmarked(url: url)
    }

    // MARK: - Shuffle / Repeat

    private(set) var isShuffleOn = false
    private(set) var isRepeatOne = false
    private(set) var isEndlessShuffleOn = false

    // MARK: - Auto-advance

    private enum PlaybackTransitionStrategy: String {
        case reuseCurrentPlayer = "reuse-current-player"
        case freshPlayer = "fresh-player"
    }

    private struct CompletionSequence {
        let id: Int
        let source: String
        let action: PlaybackCompletionAction
        let sourceURL: URL?
        let sourceSessionID: Int
    }

    private struct ExplicitPlayPauseIntent {
        let target: ExplicitPlayPauseTarget
        let mediaURL: URL?
        let sessionID: Int
    }

    private var scheduledPlaybackAction: DispatchWorkItem? = nil
    private var activeCompletionSequence: CompletionSequence? = nil
    private var playbackCompletionSequence = 0
    private var currentPlaybackSessionID = 0

    /// Retained until VLCKit acknowledges an explicit resume, or until this
    /// media session is reset. This prevents an explicit command's delayed
    /// `.paused` callback from being reclassified as paused-near-EOF completion.
    private var explicitPlayPauseIntent: ExplicitPlayPauseIntent? = nil

    private typealias PlaybackCommandAction = (@escaping () -> Void) -> Void

    private struct QueuedPlaybackCommand {
        let id: Int
        let name: String
        let action: PlaybackCommandAction
    }

    private var queuedPlaybackCommands: [QueuedPlaybackCommand] = []
    private var isExecutingPlaybackCommand = false
    private var playbackCommandSequence = 0

    /// Set by stopPlayback(), close(), windowWillClose() before calling player.stop()
    /// so the .stopped handler knows it was user-initiated and skips auto-advance.
    private var isUserStop = false

    /// Set when the queue reaches its natural end (stopLastItem action, not a user stop).
    /// Cleared when any item starts playing, when the user explicitly stops, or when
    /// the queue is cleared. Checked in togglePlayPause to restart from displayOrder[0].
    private var queueEndedNaturally = false

    /// Set by playCurrentItem() whenever player.media != nil at the time of the call.
    /// VLC fires .stopped when media is replaced, regardless of prior player state
    /// (playing, paused, or already stopped from natural EOF). This flag tells the
    /// .stopped handler to ignore that implicit transition event.
    private var suppressNextStopped = false
    // M1: monotonic timestamp (CACurrentMediaTime; 0 = unset)
    private var suppressNextStoppedMT: TimeInterval = 0
    private let replacementStopSuppressionWindow: TimeInterval = 0.75
    private let replacementStartDelay: TimeInterval = 0.05

    /// True when the .ended VLC event was received for the current media.
    /// Combined with lastKnownPosition for a three-signal natural-EOF check.
    private var naturalEOFDetected = false

    /// Last player position sampled by the app-owned progress watchdog while playing.
    /// Preserved across stop/end transitions so autoplay does not depend solely on VLC
    /// events that may arrive late or not at all.
    private var lastKnownPosition: Float = 0
    private var lastKnownTimeMs: Int = 0
    private var lastKnownDurationMs: Int = 0
    // M1: monotonic timestamps (CACurrentMediaTime; 0 = unset)
    private var lastPlayingMT:   TimeInterval = 0
    private var lastProgressMT:  TimeInterval = 0
    private var lastStoppedMT:   TimeInterval = 0
    private var lastStoppedPosition: Float = 0
    private var lastStoppedMediaURL: URL? = nil

    /// Steady-state (post-start-handshake) stall detection: unlike lastProgressMT, which
    /// only tracks "position/time was non-zero" and so never ages out for media frozen at a
    /// fixed non-zero position, these track the last position/time *value* seen and when it
    /// last actually changed. A file that starts fine but goes silent mid-stream (e.g. a
    /// container truncated mid-playback) can leave VLC reporting .playing/.buffering forever
    /// without ever emitting .error or .ended, so nothing else in the completion watchdog can
    /// ever fire for it.
    private var midPlaybackStallClock = MidPlaybackStallClock()
    /// P142: the volume kind of the current item, set when it starts. Picks the stall tolerance.
    private var currentItemVolumeKind: VolumeKind = .local
    private var lastUpdateTickMT: TimeInterval = 0
    /// A gap between two ticks of the 0.25 s update timer longer than this is logged.
    private let mainThreadGapLogSeconds: TimeInterval = 2
    /// A modal panel pauses every window's update timer; the gap it leaves is not a stall.
    private static var lastModalReturnMT: TimeInterval = 0

    /// Position captured on the VLC callback thread at the moment the .ended event fires.
    /// More reliable than capturedPosition at .stopped time because VLC hasn't reset it yet.
    private var positionAtEndedEvent: Float = 0

    /// Timestamp of the most recent user-initiated seek (scrubber drag/tap, arrow-key skip).
    /// Used by the .stopped handler to reject position-based EOF signals when a seek was
    /// recent: after seeking near the end, lastKnownPosition is near 1.0 but does NOT
    /// represent natural EOF. Require naturalEOFDetected instead.
    private var lastUserSeekMT: TimeInterval = 0   // M1: monotonic
    private let userSeekEOFGuardWindow: TimeInterval = 1.5
    private let maxUserSeekPosition: Float = 0.985
    private let eofPositionThreshold: Float = 0.95
    private let pausedNearEOFPositionThreshold: Float = 0.985
    private let pausedNearEOFRemainingMs = 1_000
    private let watchdogRecentPlaybackWindow: TimeInterval = 1.5
    private let watchdogRecentStopWindow: TimeInterval = 1.2
    private let watchdogDefaultEOFToleranceMs = 1_500
    private let delayedPlaybackActionInterval: TimeInterval = 0.30
    private let playbackStartCheckInterval: TimeInterval = 0.35
    private let maxPlaybackStartRetries = 2
    private let maxPlaybackProgressConfirmationRetries = 2
    private let playbackStartProgressAdvanceMs = 250
    private let playbackStartProgressAdvancePosition: Float = 0.002

    private struct PlaybackStartHandshake {
        let id: Int
        let reason: String
        let expectedURL: URL
        let expectedSessionID: Int
        let transitionStrategy: PlaybackTransitionStrategy
        var baselinePosition: Float
        var baselineTimeMs: Int
        var playRetryCount: Int
        var progressRetryCount: Int
        var sawPlaying: Bool
        var recoveryUsed: Bool
        /// P142: volume of the expected file, and when its start window began (`play()` or rebuild).
        let volume: VolumeKind
        var windowStartMT: TimeInterval
    }

    private var playbackStartHandshake: PlaybackStartHandshake? = nil
    private var playbackStartHandshakeWorkItem: DispatchWorkItem? = nil
    private var playbackStartHandshakeSequence = 0
    private var replacementStartWorkItem: DispatchWorkItem? = nil
    private var replacementStartSequence = 0

    /// Per-window, one-shot failure state. A VLC failure can emit both `.error`
    /// and a failed-start handshake result; this keeps one failed attempt to one skip.
    private var activePlaybackFailureAttempt: PlaybackFailureAttempt? = nil

    // MARK: - Queue page (full in-window panel)

    private(set) var isQueuePageOpen = false

    /// The user's dragged Queue Page width, as a fraction of the content width. Nil means the
    /// default width. Belongs to this window only and is never saved.
    private var queuePanelWidthFraction: CGFloat? = nil
    /// Grab zone on the edge between the video area and the Queue Page (windowed only).
    private let queuePanelResizeHandle = QueuePanelResizeHandleView(frame: .zero)

    /// Duration strings keyed by URL, populated lazily via AVFoundation.
    /// Set to "–:––" as a placeholder before the async fetch to prevent re-fetching.
    private var durationCache: [URL: String] = [:]
    private var durationSecondsCache: [URL: Double] = [:]

    // P142: files on non-local volumes. Size and existence are read off the main thread.
    // P142.1: their durations are never probed; each comes from the length VLC reports when the
    // file plays, stored once per queue.
    private lazy var nonLocalFiles: NonLocalFileMetadataStore = {
        let store = NonLocalFileMetadataStore()
        store.onBatch = { [weak self] in self?.nonLocalFactsDidArrive() }
        return store
    }()
    private var reportedDurations = ReportedDurationLedger()
    /// P138: intrinsic GIF loop durations for this window's queue, scanned off the main thread.
    private let gifDurations = GIFDurationStore()
    /// P138: the latest large intake's GIF duration loading, shown on the intake card.
    private var gifIntakeProgress: GIFDurationIntakeProgress?
    private var intakeScanningFolderCount = 1
    private var currentDurationIsProvisional = false
    private var queueSortMode: QueueSortMode = .manual
    /// A rename updates metadata without becoming an implicit user sort action.
    /// Kept until the user explicitly picks a Queue Page sort mode again.
    private var queueSortOrderFrozenAfterRename = false

    var isShowingProvisionalDuration: Bool { currentDurationIsProvisional }

    // MARK: - Image slideshow state (per-window)

    /// NSImageView placed above videoSurface; visible only when current item is an image.
    private var imageDisplayView: ImageSurfaceView?
    /// True when the currently active item is an image slideshow item.
    private(set) var currentItemIsImage = false
    /// True when the currently active image item is an animated GIF.
    private var currentItemIsGIF = false
    /// CACurrentMediaTime() when the current image display started (or resumed). 0 = not running.
    private var imageSlideshowStartMT: TimeInterval = 0
    /// Elapsed time accumulated before the most recent pause.
    private var imageSlideshowPauseAccumulated: TimeInterval = 0
    /// True when the image slideshow is paused by the user.
    private var imageSlideshowPaused = false
    /// Total playback duration for the active image item (still image or configured GIF loops).
    private var currentImagePlaybackDurationSeconds: TimeInterval = 0
    /// Decoded animated GIF state for the active item, when applicable.
    private var currentGIFAnimation: MediaFileSupport.GIFAnimation?
    private var gifFrameTimer: Timer?
    private var gifCurrentFrameIndex = 0
    private var gifCurrentFrameStartedMT: TimeInterval = 0
    private var gifCurrentFrameRemainingDelay: TimeInterval = 0

    // MARK: - Layout constants

    private let transportHeight: CGFloat = 48

    // M3: cached hot-settings flags — refreshed in notification handlers when settings change.
    private var autoHideTitlebarEnabled: Bool = UserDefaults.standard.bool(forKey: SettingsWindowController.autoHideTitlebarKey)
    private var completeVideoWindowModeEnabled: Bool = UserDefaults.standard.bool(forKey: SettingsWindowController.completeVideoWindowModeKey)
    private var configuredSkipDurationMs: Int = SettingsWindowController.currentSkipDurationSeconds() * 1_000
    private var configuredSkipDurationSeconds: Int { configuredSkipDurationMs / 1_000 }
    private var configuredImageDurationSeconds: Double = SettingsWindowController.currentImageDurationSeconds()
    private var configuredGIFLoopCount: Int = SettingsWindowController.currentGIFLoopCount()
    private var configuredShowTitleOverlay: Bool = SettingsWindowController.isShowTitleOverlayEnabled()
    private var gifDurationFallbackLoggedPaths: Set<String> = []

    // MARK: - Per-window audio state

    private var windowVolume: Int32 = PlayerWindowController.defaultPersistedVolume()
    private var windowMuted = false
    private var lastAppliedAudioState: (volume: Int32, muted: Bool)?
    /// P137: armed right before a start that can create a new audio output (which may begin at
    /// another window's volume); consumed by the first `.playing` for that start.
    private var audioReassertPending = false

    // MARK: - Per-window audio sync offset (Bluetooth-latency compensation)

    /// Milliseconds of audio delay applied to VLCMediaPlayer.currentAudioPlaybackDelay.
    /// Positive delays audio further; negative advances it. Seeded from the persisted
    /// default so a device's dialed-in offset carries over to new windows/videos, but
    /// each window may then nudge its own live value independently (no shared state).
    private var windowAudioDelayMs: Int32 = PlayerWindowController.defaultPersistedAudioDelayMs()
    private var lastAppliedAudioDelayMs: Int32?

    // MARK: - Per-window playback speed

    private var playbackSpeed: Float = PlaybackSpeedOption.normalRate
    var currentPlaybackSpeed: Float { playbackSpeed }

    // MARK: - Init

    init() {
        debugOrdinal = PlayerWindowController.nextDebugOrdinal
        PlayerWindowController.nextDebugOrdinal += 1
        super.init(window: nil)
        buildWindow()
        buildPlayer()
        startUpdateTimer()
        observeSettings()
        applyLaunchDefaults()
        gifDurations.onResolved = { [weak self] url, result in
            self?.acceptQueuedGIFDuration(url: url, result: result)
        }
    }

    deinit {
        DebugConsoleController.log("window", "released: window=\(debugIdentity)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used – UI is programmatic")
    }

    // MARK: - Window construction

    private func buildWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 960, height: 540)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let win = NSWindow(contentRect: contentRect,
                           styleMask: style,
                           backing: .buffered,
                           defer: false)
        win.title = Self.defaultWindowTitle
        win.minSize = NSSize(width: 480, height: 180 + transportHeight)
        win.center()
        win.isReleasedWhenClosed = false
        win.isRestorable = false   // restorable state not implemented; suppresses className=(null) warning
        win.tabbingMode = .disallowed

        let cv = win.contentView!

        videoSurface = VideoSurfaceView(frame: .zero)
        cv.addSubview(videoSurface)

        // Image display view — sits above videoSurface, below transport; shown for slideshow items.
        let imgView = ImageSurfaceView(frame: .zero)
        imgView.isHidden = true
        cv.addSubview(imgView)
        imageDisplayView = imgView

        transport = TransportControlsView(frame: .zero)
        cv.addSubview(transport)

        volumeBar = VolumeBarView(frame: .zero)
        volumeBar.onVolumeChanged = { [weak self] vol in
            self?.setVolumeFromBar(vol)
        }
        cv.addSubview(volumeBar)
        cv.addSubview(statusHUDView)

        audioDelayBar = AudioDelayBarView(frame: .zero)
        cv.addSubview(audioDelayBar)

        queuePage = QueuePageView(frame: .zero)
        queuePage.delegate = self
        queuePage.isHidden = true
        queuePage.isUndoAvailable = markerRenameUndoState.canUndo
        cv.addSubview(queuePage)

        // Resize grab zone on the shared edge, directly above the Queue Page.
        queuePanelResizeHandle.isHidden = true
        queuePanelResizeHandle.onDrag = { [weak self] edgeX in
            self?.queuePanelResizeDragged(toEdgeX: edgeX)
        }
        queuePanelResizeHandle.onDragEnd = { [weak self] in
            self?.logQueuePanelWidth(event: "drag-end")
        }
        queuePanelResizeHandle.onReset = { [weak self] in
            self?.resetQueuePanelWidth()
        }
        cv.addSubview(queuePanelResizeHandle, positioned: .above, relativeTo: queuePage)

        // Undo toast and failure message sit above the rail and HUDs.
        undoToastView.onUndo = { [weak self] in
            self?.undoLastMarkerRename()
        }
        cv.addSubview(undoToastView)
        cv.addSubview(failureMessageView)

        // Video title overlay — above the transport HUD.
        cv.addSubview(videoTitleOverlay)

        intakeRecoveryView.actionHandler = { [weak self] action in
            self?.handleIntakeRecoveryAction(action)
        }
        intakeRecoveryView.dismissHandler = { [weak self] in
            self?.clearIntakeRecovery()
        }
        intakeRecoveryView.layoutDidChange = { [weak self] in
            self?.layoutPlayerViews()
        }
        cv.addSubview(intakeRecoveryView)

        // Drop zone covers the video area while a valid drag is over it.
        cv.addSubview(dropZoneOverlay)

        // Settings target outline sits above everything and passes all mouse events through.
        settingsTargetOutline.frame = cv.bounds
        cv.addSubview(settingsTargetOutline)

        self.window = win
        win.delegate = self
        installCenteredTitleLabel(in: win)
        updateWindowTitle(Self.defaultWindowTitle)
        applyWindowOpacity(reason: "initial-window", force: true)

        applyWindowedChromeModeIfNeeded()
        layoutPlayerViews()
        addMouseTracking()
    }

    private func installCenteredTitleLabel(in win: NSWindow) {
        guard let titlebarView = win.standardWindowButton(.closeButton)?.superview else { return }
        titlebarContainerView = titlebarView   // captured for auto-hide animations
        win.titleVisibility = .hidden

        centeredTitleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        centeredTitleLabel.textColor = DWBColor.textPrimary
        centeredTitleLabel.alignment = .center
        centeredTitleLabel.lineBreakMode = .byTruncatingMiddle
        centeredTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        centeredTitleLabel.isEditable = false
        centeredTitleLabel.isBordered = false
        centeredTitleLabel.drawsBackground = false
        centeredTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titlebarView.addSubview(centeredTitleLabel)

        let trafficLightWidth: CGFloat = 92
        NSLayoutConstraint.activate([
            centeredTitleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            centeredTitleLabel.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
            centeredTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor,
                                                        constant: trafficLightWidth),
            centeredTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor,
                                                         constant: -trafficLightWidth)
        ])
    }

    private func updateWindowTitle(_ title: String) {
        window?.title = title
        window?.representedURL = currentMediaURL
        window?.titleVisibility = .hidden
        centeredTitleLabel.stringValue = title
        postTargetingChanged()
    }

    // MARK: - Dock and Settings targeting

    /// A plain snapshot for `PlayerWindowTargeting`. With `treatHiddenAsOnScreen`, a window
    /// that is only off screen because the app is hidden counts as on screen.
    func targetingSnapshot(treatHiddenAsOnScreen: Bool = false) -> PlayerWindowTargeting.WindowSnapshot<ObjectIdentifier> {
        let isMinimized = window?.isMiniaturized == true
        let isVisible = window?.isVisible == true || (treatHiddenAsOnScreen && window != nil)
        return PlayerWindowTargeting.WindowSnapshot(
            id: ObjectIdentifier(self),
            isOnScreen: isVisible && !isMinimized && !isWindowClosed,
            isMinimized: isMinimized && !isWindowClosed,
            lastKeyStamp: lastKeyStamp,
            minimizeStamp: isMinimized ? minimizeStamp : nil
        )
    }

    /// Called by Settings. The outline also stays hidden in fullscreen.
    func setSettingsTargetOutlineVisible(_ visible: Bool) {
        guard visible != isSettingsTargetOutlineRequested else { return }
        isSettingsTargetOutlineRequested = visible
        updateSettingsTargetOutline()
        DebugConsoleController.log("window", "settingsTargetOutline: window=\(debugIdentity) visible=\(visible)")
    }

    private func updateSettingsTargetOutline() {
        let show = isSettingsTargetOutlineRequested && !isWindowClosed
            && !isFullscreen && !isEnteringFullscreen && !isExitingFullscreen
        if show, let cv = window?.contentView, cv.subviews.last !== settingsTargetOutline {
            settingsTargetOutline.frame = cv.bounds
            cv.addSubview(settingsTargetOutline, positioned: .above, relativeTo: nil)
        }
        settingsTargetOutline.isHidden = !show
    }

    private func postTargetingChanged() {
        NotificationCenter.default.post(name: .playerWindowTargetingChanged, object: self)
    }

    private func applyLaunchDefaults() {
        guard UserDefaults.standard.bool(forKey: SettingsWindowController.queuePanelOpenAtLaunchKey) else { return }
        isQueuePageOpen = true
        layoutPlayerViews()
    }

    // MARK: - Player construction

    private func buildPlayer() {
        player = VLCMediaPlayer()
        player.delegate = self
        player.drawable = videoSurface
        applyWindowAudioState(reason: "initial-player", force: true)
        applyAudioDelay(reason: "initial-player", force: true)
        applyPlaybackSpeed(reason: "initial-player")
        transport.controller = self
        transport.player = player
        applyScaleMode()
    }

    // MARK: - Settings observation

    private func observeSettings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(transportVisibilityDidChange),
            name: .transportVisibilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bottomRailButtonVisibilityDidChange),
            name: .bottomRailButtonVisibilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoHideTitlebarSettingDidChange),
            name: .autoHideTitlebarChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(completeVideoWindowModeSettingDidChange),
            name: .completeVideoWindowModeChanged,
            object: nil
        )
        // M3: refresh cached skip duration when the setting changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(skipDurationSettingDidChange),
            name: .skipDurationChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(imageDurationSettingDidChange),
            name: .imageDurationChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gifLoopCountSettingDidChange),
            name: .gifLoopCountChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(titleOverlaySettingDidChange),
            name: .titleOverlaySettingChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(customPrefixValueDidChange),
            name: .customPrefixValueChanged,
            object: nil
        )
        // M4: observe window occlusion changes to force a transport refresh on return.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOcclusionStateDidChange),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: self.window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bookmarkDidChange),
            name: .bookmarkDidChange,
            object: nil
        )
    }

    @objc private func bookmarkDidChange() {
        refreshQueueDisplays()
    }

    var isTextEntryFocused: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSTextView { return true }
        var current: NSView? = responder as? NSView
        while let item = current {
            if item is NSTextField { return true }
            current = item.superview
        }
        return false
    }

    @objc private func transportVisibilityDidChange() {
        transport.applyVisibilitySettings()
        layoutPlayerViews()
        transport.update()
    }

    @objc private func bottomRailButtonVisibilityDidChange() {
        // BottomRailView already observes the same notification and re-applies
        // visibility + invalidates its display cache; we also pump
        // transport.update() so layout reflects the new button set immediately.
        transport.update()
    }

    @objc private func skipDurationSettingDidChange() {
        configuredSkipDurationMs = SettingsWindowController.currentSkipDurationSeconds() * 1_000  // M3
    }

    @objc private func imageDurationSettingDidChange() {
        configuredImageDurationSeconds = SettingsWindowController.currentImageDurationSeconds()
        refreshConfiguredImageDurations()
        applyCurrentImageDurationSettings()
        if isQueuePageOpen { refreshQueuePage() }
    }

    @objc private func gifLoopCountSettingDidChange() {
        configuredGIFLoopCount = SettingsWindowController.currentGIFLoopCount()
        refreshConfiguredImageDurations()
        applyCurrentImageDurationSettings()
        if isQueuePageOpen { refreshQueuePage() }
        DebugConsoleController.log("settings", "gifLoopCount=\(configuredGIFLoopCount)")
    }

    // M4: fires when this window's occlusion state changes. When the window becomes
    // visible again (after being hidden/minimized/covered), schedule one forced
    // cosmetic refresh so the transport HUD re-syncs without waiting for user action.
    @objc private func windowOcclusionStateDidChange() {
        if isEffectivelyVisibleForCosmeticRefresh {
            needsForceRefreshOnReturn = true
        }
    }

    // M4: true when the window is on screen and worth refreshing cosmetic UI for.
    private var isEffectivelyVisibleForCosmeticRefresh: Bool {
        guard let win = window else { return false }
        guard !win.isMiniaturized else { return false }
        return win.occlusionState.contains(.visible)
    }

    @objc private func autoHideTitlebarSettingDidChange() {
        autoHideTitlebarEnabled = UserDefaults.standard.bool(forKey: SettingsWindowController.autoHideTitlebarKey)  // M3
        applyWindowedChromeModeIfNeeded()
    }

    @objc private func completeVideoWindowModeSettingDidChange() {
        completeVideoWindowModeEnabled = UserDefaults.standard.bool(forKey: SettingsWindowController.completeVideoWindowModeKey)
        applyWindowedChromeModeIfNeeded()
        layoutPlayerViews()
        addMouseTracking()
        logChromeState("completeVideoWindowModeSettingDidChange")
    }

    private var shouldApplyCompleteVideoWindowMode: Bool {
        completeVideoWindowModeEnabled && !isFullscreen && !isEnteringFullscreen && !isExitingFullscreen
    }

    private func setStandardWindowButtonsHidden(_ hidden: Bool) {
        guard let win = window else { return }
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
            win.standardWindowButton(buttonType)?.isHidden = hidden
        }
    }

    private func applyWindowedChromeModeIfNeeded() {
        guard let win = window else { return }
        if shouldApplyCompleteVideoWindowMode {
            titlebarHideTimer?.invalidate()
            titlebarHideTimer = nil
            win.styleMask.insert(.fullSizeContentView)
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.titlebarSeparatorStyle = .none
            win.isMovableByWindowBackground = true
            setStandardWindowButtonsHidden(true)
            centeredTitleLabel.isHidden = true
            titlebarContainerView?.alphaValue = 0.0
            titlebarIsHidden = true
            return
        }

        guard !isFullscreen else { return }
        titlebarHideTimer?.invalidate()
        titlebarHideTimer = nil
        win.styleMask.remove(.fullSizeContentView)
        win.titlebarAppearsTransparent = false
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .automatic
        win.isMovableByWindowBackground = false
        setStandardWindowButtonsHidden(false)
        centeredTitleLabel.isHidden = false
        titlebarContainerView?.alphaValue = 1.0
        titlebarIsHidden = false
        if autoHideTitlebarEnabled { scheduleTitlebarHide() }
    }

    @objc private func titleOverlaySettingDidChange() {
        configuredShowTitleOverlay = SettingsWindowController.isShowTitleOverlayEnabled()
        DebugConsoleController.log("settings", "titleOverlay=\(configuredShowTitleOverlay)")
    }

    @objc private func customPrefixValueDidChange() {
        if isQueuePageOpen { refreshQueuePage() }
    }

    /// Active-playback duration. Reuses an already-resolved GIF result; otherwise keeps
    /// the existing synchronous scan for this one item and records it for the queue.
    private func configuredImageDurationMetadata(for url: URL) -> MediaFileSupport.DurationMetadata {
        if MediaFileSupport.isGIF(url) {
            let result: GIFLoopDuration
            if let cached = gifDurations.resolvedResult(for: url) {
                result = cached
            } else {
                result = GIFLoopDuration(MediaFileSupport.gifPlaybackMetadata(for: url, loopCount: configuredGIFLoopCount))
                gifDurations.record(result, for: url)
                updateGIFIntakeProgress { $0.finish(GIFDurationStore.key(for: url)) }
            }
            noteGIFDurationOutcome(url: url, result: result)
            return result.durationMetadata(loopCount: configuredGIFLoopCount)
        }

        return stillImageDurationMetadata()
    }

    private func stillImageDurationMetadata() -> MediaFileSupport.DurationMetadata {
        MediaFileSupport.DurationMetadata(seconds: configuredImageDurationSeconds,
                                          displayString: MediaFileSupport.formatShortDuration(configuredImageDurationSeconds))
    }

    private func noteGIFDurationOutcome(url: URL, result: GIFLoopDuration) {
        guard result == .unreadable else {
            gifDurationFallbackLoggedPaths.remove(url.path)
            return
        }
        if gifDurationFallbackLoggedPaths.insert(url.path).inserted {
            DebugConsoleController.log(level: .error,
                                       category: "media",
                                       message: "gif duration fallback: \(url.lastPathComponent) loops=\(configuredGIFLoopCount)")
        }
    }

    /// Queue-facing image duration: never scans a GIF on the main thread. An unresolved
    /// GIF projects to "Loading..." with no seconds (unknown for totals and sorting).
    private func queueImageDurationMetadata(for url: URL) -> MediaFileSupport.DurationMetadata {
        guard MediaFileSupport.isGIF(url) else { return stillImageDurationMetadata() }
        switch gifDurations.lookup(url) {
        case .resolved(let result):
            return result.durationMetadata(loopCount: configuredGIFLoopCount)
        case .pending:
            return MediaFileSupport.DurationMetadata(seconds: nil,
                                                     displayString: MediaFileSupport.durationLoadingText)
        }
    }

    /// Background GIF scans accepted by the store, applied together on the next main-queue
    /// turn so a large queue gets one cache pass and one sort/refresh per batch.
    private var pendingGIFDurationAcceptances: [(url: URL, result: GIFLoopDuration)] = []
    private var gifResultsSinceQueueRefresh = 0

    /// Main-thread acceptance of a background GIF scan. Updates queue metadata only;
    /// never touches the active item's timer or advances the queue.
    private func acceptQueuedGIFDuration(url: URL, result: GIFLoopDuration) {
        guard !isWindowClosed else { return }
        pendingGIFDurationAcceptances.append((url, result))
        guard pendingGIFDurationAcceptances.count == 1 else { return }
        DispatchQueue.main.async { [weak self] in self?.flushAcceptedGIFDurations() }
    }

    private func flushAcceptedGIFDurations() {
        let batch = pendingGIFDurationAcceptances
        pendingGIFDurationAcceptances.removeAll()
        guard !isWindowClosed, !batch.isEmpty else { return }
        var applied = 0
        var finishedKeys: [String] = []
        defer { if !finishedKeys.isEmpty { updateGIFIntakeProgress { p in finishedKeys.forEach { p.finish($0) } } } }
        for (url, result) in batch {
            if gifIntakeProgress != nil { finishedKeys.append(GIFDurationStore.key(for: url)) }
            // The store drops entries on clear/remove/replace/rename, so a result that is
            // no longer current there was invalidated after acceptance; skip it.
            guard gifDurations.resolvedResult(for: url) == result else { continue }
            noteGIFDurationOutcome(url: url, result: result)
            updateDurationCache(for: url, metadata: result.durationMetadata(loopCount: configuredGIFLoopCount))
            applied += 1
        }
        gifResultsSinceQueueRefresh += applied
        guard GIFDurationRefreshPolicy.shouldRefresh(acceptedSinceRefresh: gifResultsSinceQueueRefresh,
                                                     pendingCount: gifDurations.pendingCount) else { return }
        gifResultsSinceQueueRefresh = 0
        if queueSortMode == .durationAscending || queueSortMode == .durationDescending {
            applyQueueSortIfNeeded(reason: "gif-duration-metadata-update")
        } else if isQueuePageOpen {
            refreshQueuePage()
        }
    }

    /// Starts card-tracked GIF duration loading for a large intake. Every GIF the intake
    /// added is requested in the background now rather than when Queue first opens.
    private func beginGIFIntakeProgress(for media: [URL]) {
        var keys = Set<String>()
        for url in media where MediaFileSupport.isGIF(url) {
            if gifDurations.lookup(url) == .pending { keys.insert(GIFDurationStore.key(for: url)) }
        }
        guard keys.count >= GIFDurationIntakeProgress.minimumTrackedCount else { return }
        gifIntakeProgress = GIFDurationIntakeProgress(keys: keys)
        intakeRecoveryRetryContext = nil
        intakeRecoverySourceURLs = []
        DebugConsoleController.log("queue", "intakeRecovery: loading gifDurations=\(keys.count)")
        updateGIFIntakeProgress { _ in }
    }

    /// Applies `change`, then shows the new count or dismisses the finished card.
    private func updateGIFIntakeProgress(_ change: (inout GIFDurationIntakeProgress) -> Void) {
        guard var progress = gifIntakeProgress else { return }
        change(&progress)
        if progress.isComplete {
            DebugConsoleController.log("queue", "intakeRecovery: gifDurations done total=\(progress.total)")
            clearIntakeRecovery()
            layoutPlayerViews()
            return
        }
        gifIntakeProgress = progress
        intakeRecoveryView.present(.loadingGIFDurations(finished: progress.finished, total: progress.total))
        layoutPlayerViews()
    }

    private func refreshConfiguredImageDurations() {
        for url in playbackSet where MediaFileSupport.isImage(url) {
            let metadata = queueImageDurationMetadata(for: url)
            updateDurationCache(for: url, metadata: metadata)
        }
    }

    private func applyCurrentImageDurationSettings() {
        guard currentItemIsImage, let currentURL = currentMediaURL else { return }
        let metadata = configuredImageDurationMetadata(for: currentURL)
        currentImagePlaybackDurationSeconds = metadata.seconds ?? 0
        transport.imageModeDuration = currentImagePlaybackDurationSeconds
        needsTransportUpdate = true
    }

    // MARK: - Prefix actions (keys, rail buttons)

    /// The one entry point for the `N`, `M` and `R` keys and the rail prefix buttons. `N` and `M`
    /// act on the same targets as the queue footer chips: the selected queue rows, or the
    /// current item when nothing is selected or the Queue Page is closed. `R` opens the rename
    /// sheet for the one selected row, else for the current file.
    func performPrefixAction(_ action: PrefixKeyRouting.Action, source: String) {
        switch action {
        case .primaryPrefix:
            DebugConsoleController.log("rename", "prefixAction: primary source=\(source)")
            applyPrefix(indices: prefixTargetDisplayIndices(), invokedPrimary: true)
        case .secondaryPrefix:
            DebugConsoleController.log("rename", "prefixAction: secondary source=\(source)")
            applyPrefix(indices: prefixTargetDisplayIndices(), invokedPrimary: false)
        case .rename:
            let selected = isQueuePageOpen ? queuePage.selectedDisplayIndices() : []
            if let row = PrefixKeyRouting.selectedRenameRow(selectedDisplayIndices: selected) {
                showRenameSheet(forDisplayIndex: row)
            } else {
                showRenameSheet()
            }
        }
    }

    private func prefixTargetDisplayIndices() -> [Int] {
        if isQueuePageOpen { return queuePage.prefixTargetDisplayIndices() }
        return [currentDisplayIndex]
    }

    // MARK: - Layout

    private func layoutPlayerViews() {
        guard let cv = window?.contentView else { return }
        let b    = cv.bounds
        let mode = layoutMode   // single source of truth — do not branch on isFullscreen directly
        logLayoutSnapshot("layoutPlayerViews")

        // M2: only reapply fullscreen style properties when the style target changes.
        // Skips redundant applySymbol, effectView.alphaValue, and needsLayout calls
        // during live resize and fullscreen-exit settle when mode is already stable.
        let targetFullscreenStyle = (mode == .fullscreen)
        let styleChanged = targetFullscreenStyle != lastAppliedIsFullscreenStyle
        lastAppliedIsFullscreenStyle = targetFullscreenStyle

        if mode == .fullscreen {
            // Stable fullscreen: full-bleed video with cinematic overlay controls.
            queuePage.isHidden = true
            queuePanelResizeHandle.isHidden = true

            videoSurface.frame = b
            videoSurface.layer?.frame = b

            transport.frame = b
            if styleChanged {
                transport.layer?.cornerRadius  = 0
                transport.layer?.masksToBounds = false
                transport.setFullscreenStyle(true)
            }

        } else {
            // Windowed baseline — covers both .windowed and .exitingFullscreenSettling.
            // Geometry is derived ONLY from current contentView bounds; no cached
            // fullscreen frames, no screen bounds, no prior transport frames.
            let queueW: CGFloat = isQueuePageOpen
                ? QueuePanelWidthPolicy.width(contentWidth: b.width, customFraction: queuePanelWidthFraction)
                : 0
            let videoW = max(0, b.width - queueW)

            // Do NOT set videoSurface.layer?.frame here.
            // Setting layer.frame = videoSurface.bounds (origin {0,0}) would override
            // AppKit's view-backed layer placement during live resize/fullscreen
            // transitions. The view's own frame is the source of truth; AppKit keeps
            // the backing layer in sync automatically.  (Apr 21 carry-forward fix.)
            videoSurface.frame = NSRect(x: 0, y: 0, width: videoW, height: b.height)

            transport.frame = NSRect(x: 0, y: 0, width: videoW, height: b.height)
            if styleChanged {
                transport.layer?.cornerRadius  = 0
                transport.layer?.masksToBounds = false
                transport.setFullscreenStyle(false)
            }

            if isQueuePageOpen {
                queuePage.isHidden = false
                queuePage.frame = NSRect(x: videoW, y: 0, width: queueW, height: b.height)
                let grabHalf = QueuePanelMetrics.resizeGrabZoneHalfWidth
                queuePanelResizeHandle.frame = NSRect(x: videoW - grabHalf, y: 0,
                                                      width: grabHalf * 2, height: b.height)
                queuePanelResizeHandle.isHidden = false
            } else {
                queuePage.isHidden = true
                queuePanelResizeHandle.isHidden = true
            }
        }

        // Volume HUD: centered directly above the unified rail's scrubber.
        let barW = VolumeBarView.preferredSize.width
        let barH = VolumeBarView.preferredSize.height
        let centeredBarX = transport.frame.midX - barW / 2
        let barX = min(
            max(transport.frame.minX, centeredBarX),
            max(transport.frame.minX, transport.frame.maxX - barW)
        )
        // The HUD stack starts above the undo toast, which sits just above the rail.
        let railTop = transport.frame.minY + transport.unifiedBottomRailHeight
        let desiredBarY = railTop + HUDStackMetrics.bottomOffsetAboveRail
        let barY = min(max(0, desiredBarY), max(0, b.height - barH - 12))
        volumeBar.frame = NSRect(x: barX,
                                 y: barY,
                                 width: barW,
                                 height: barH)

        // Status HUD: the same slot as the volume HUD, centered over the same rail.
        positionStatusHUD(over: transport.frame, slotY: barY, containerHeight: b.height)

        // Audio sync HUD: stacked directly above the volume HUD so the two never overlap
        // if both happen to be visible at once.
        let delayBarW = AudioDelayBarView.preferredSize.width
        let delayBarH = AudioDelayBarView.preferredSize.height
        let centeredDelayBarX = transport.frame.midX - delayBarW / 2
        let delayBarX = min(
            max(transport.frame.minX, centeredDelayBarX),
            max(transport.frame.minX, transport.frame.maxX - delayBarW)
        )
        let desiredDelayBarY = barY + barH + HUDStackMetrics.gap
        let delayBarY = min(max(0, desiredDelayBarY), max(0, b.height - delayBarH - 12))
        audioDelayBar.frame = NSRect(x: delayBarX,
                                     y: delayBarY,
                                     width: delayBarW,
                                     height: delayBarH)

        // Image display view always matches videoSurface — covers both fullscreen and windowed.
        imageDisplayView?.frame = videoSurface.frame

        let recoveryWidth = min(640, max(0, transport.frame.width - 32))
        let preferredRecoveryHeight = intakeRecoveryView.preferredHeight(for: recoveryWidth)
        let availableRecoveryHeight = max(120, transport.frame.height - 112)
        let recoveryHeight = min(preferredRecoveryHeight, availableRecoveryHeight)
        intakeRecoveryView.frame = NSRect(
            x: 16,
            y: transport.unifiedBottomRailHeight + 12,
            width: recoveryWidth,
            height: recoveryHeight
        )

        applyScaleMode()
        positionVideoTitleOverlay()
        positionFailureMessage()
        positionUndoToast()
        positionDropZone()
    }

    // MARK: - Video title overlay

    /// Show a transient title message at the top-center of the player area.
    /// Restarts the hold when called again so rapid track changes
    /// don't stack multiple hide timers.
    func showVideoTitleOverlay(title: String, duration: TimeInterval = 5.0) {
        let availableWidth = videoSurface?.frame.width ?? window?.contentView?.bounds.width ?? 800
        videoTitleOverlay.configure(title: title, videoWidth: availableWidth)
        positionVideoTitleOverlay()
        videoTitleOverlay.present(hold: duration)
    }

    private func positionVideoTitleOverlay() {
        guard videoTitleOverlay.superview != nil else { return }
        let videoFrame = videoSurface?.frame ?? .zero
        guard videoFrame.width > 0, videoFrame.height > 0 else { return }
        let overlayH = videoTitleOverlay.preferredHeight
        let overlayW = videoTitleOverlay.preferredWidth
        videoTitleOverlay.frame = NSRect(
            x: videoFrame.minX + ((videoFrame.width - overlayW) / 2).rounded(),
            y: videoFrame.maxY - TitleOverlayMetrics.topInset - overlayH,
            width: overlayW,
            height: overlayH
        )
    }

    // MARK: - Failure message, undo toast, drop zone

    private func positionFailureMessage() {
        guard failureMessageView.superview != nil else { return }
        let videoFrame = videoSurface?.frame ?? .zero
        guard videoFrame.width > 0, videoFrame.height > 0 else { return }
        let width = failureMessageView.preferredWidth(maxWidth: videoFrame.width - 32)
        failureMessageView.frame = NSRect(
            x: videoFrame.minX + ((videoFrame.width - width) / 2).rounded(),
            y: videoFrame.maxY - FailureMessageMetrics.topInset - FailureMessageMetrics.height,
            width: width,
            height: FailureMessageMetrics.height
        )
    }

    /// The status HUD sits where the volume HUD does: centered over the transport, with its
    /// bottom `DWBMetrics.hudBottomOffset` above the stage bottom.
    private func positionStatusHUD(over transportFrame: NSRect, slotY: CGFloat, containerHeight: CGFloat) {
        let size = statusHUDView.preferredSize(maxWidth: transportFrame.width - 32)
        let centeredX = transportFrame.midX - size.width / 2
        let x = min(max(transportFrame.minX, centeredX), max(transportFrame.minX, transportFrame.maxX - size.width))
        let y = min(max(0, slotY), max(0, containerHeight - size.height - 12))
        statusHUDView.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func repositionStatusHUD() {
        guard let cv = window?.contentView else { return }
        let railTop = transport.frame.minY + transport.unifiedBottomRailHeight
        positionStatusHUD(over: transport.frame,
                          slotY: railTop + HUDStackMetrics.bottomOffsetAboveRail,
                          containerHeight: cv.bounds.height)
    }

    /// Shows the status HUD in the volume HUD's slot. One HUD at a time: it replaces a
    /// volume HUD that is up, and a later volume change replaces it. Never a modal alert.
    func showStatusHUD(_ content: StatusHUDContent) {
        guard window?.isVisible == true else { return }
        // Leave the volume HUD alone while the user is dragging its meter.
        guard !volumeBar.defersHide else { return }
        volumeBar.dismiss()
        statusHUDView.present(content: content)
        repositionStatusHUD()
    }

    /// Volume HUD entry point: replaces a status HUD that is up.
    private func showVolumeHUD(volume: Int32) {
        statusHUDView.dismiss()
        volumeBar.show(volume: volume)
    }

    private func positionUndoToast() {
        guard undoToastView.superview != nil else { return }
        let videoFrame = videoSurface?.frame ?? .zero
        guard videoFrame.width > 0, videoFrame.height > 0 else { return }
        let width = undoToastView.preferredWidth(maxWidth: videoFrame.width - 32)
        undoToastView.frame = NSRect(
            x: videoFrame.minX + ((videoFrame.width - width) / 2).rounded(),
            y: videoFrame.minY + UndoToastMetrics.bottomInset,
            width: width,
            height: UndoToastMetrics.height
        )
    }

    private func positionDropZone() {
        guard dropZoneOverlay.superview != nil else { return }
        let videoFrame = videoSurface?.frame ?? .zero
        dropZoneOverlay.frame = videoFrame.insetBy(dx: DropZoneCopy.inset, dy: DropZoneCopy.inset)
    }

    /// Called by the video and image surfaces when a valid drag enters.
    func showDropZone(fileCount: Int, folderCount: Int) {
        positionDropZone()
        dropZoneOverlay.present(fileCount: fileCount, folderCount: folderCount)
    }

    /// Called when the drag exits, ends, or drops.
    func hideDropZone() {
        dropZoneOverlay.dismiss()
    }

    private func showUndoToast(renamedTo filename: String) {
        undoToastView.present(renamedTo: filename)
        positionUndoToast()
    }

    private func showUndoToast(renamedFileCount count: Int) {
        undoToastView.present(renamedFileCount: count)
        positionUndoToast()
    }

    private func hideUndoToast() {
        undoToastView.dismiss()
    }

    /// Records a completed marker rename for Command-Z and shows the undo toast: the
    /// filename for one file, "Renamed N files" for a batch. Either form replaces any toast
    /// left over from an earlier rename; Undo and Command-Z revert the whole step.
    private func recordMarkerRename(entries: [MarkerRenameUndoEntry]) {
        markerRenameUndoState.record(entries: entries)
        guard UndoToastMetrics.shouldShow(forRenamedFileCount: entries.count), let entry = entries.first else {
            hideUndoToast()
            return
        }
        if UndoToastMetrics.isBatch(renamedFileCount: entries.count) {
            showUndoToast(renamedFileCount: entries.count)
        } else {
            showUndoToast(renamedTo: entry.renamedURL.lastPathComponent)
        }
    }

    // MARK: - Keep-at-top

    func toggleKeepAtTop() {
        isKeepAtTop.toggle()
        DebugConsoleController.log("window", "keepAtTop: \(isKeepAtTop)")
        applyKeepAtTop()
    }

    private func applyKeepAtTop() {
        window?.level = isKeepAtTop ? .floating : .normal
    }

    // MARK: - File open

    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Media"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MediaFileSupport.supportedContentTypes(
            acceptedKinds: SettingsWindowController.acceptedMediaKinds()
        )
        let response = panel.runModal()
        Self.lastModalReturnMT = CACurrentMediaTime()
        guard response == .OK, !panel.urls.isEmpty else { return }
        handleDroppedURLs(panel.urls, appendingExplicitFiles: false)
    }

    // MARK: - Playback set management

    /// Replace this window's playback set and immediately play the selected item.
    /// Folder drag/drop can request a randomized start without changing other
    /// explicit-open behavior.
    private func openAndPlay(set: [URL], randomizeShuffleStart: Bool = false) {
        guard !set.isEmpty else { return }
        DebugConsoleController.log("queue", "openReplace: count=\(set.count)")
        noteQueueLoaded(set, replacing: true)
        playbackSet     = set
        let replacementPaths = Set(set.map { $0.standardizedFileURL.path })
        gifDurations.retain(paths: replacementPaths)
        updateGIFIntakeProgress { $0.retain(paths: replacementPaths) }
        displayOrder    = Array(0..<set.count)
        pendingPlayNextSetIndices.removeAll()
        currentDisplayIndex = 0
        if isShuffleOn {
            if randomizeShuffleStart {
                applyShuffleWithRandomStart()
            } else {
                applyShuffleKeepingCurrent()
            }
        } else {
            applyQueueSortIfNeeded(reason: "open-replace", refreshUI: false)
        }
        playCurrentItem(startReason: "open-replace")
    }

    /// Insert explicit dropped files at the top of this window's existing queue
    /// without replacing the queue. The first inserted item becomes active unless
    /// a folder drag/drop explicitly requests a randomized Shuffle start.
    private func appendToQueue(files: [URL], randomizeShuffleStart: Bool = false) {
        guard !files.isEmpty else { return }
        let wasEmpty = playbackSet.isEmpty || displayOrder.isEmpty || currentDisplayIndex < 0
        noteQueueLoaded(files, replacing: wasEmpty)
        let start = playbackSet.count
        playbackSet.append(contentsOf: files)

        let newIndices = Array(start..<playbackSet.count)
        displayOrder.insert(contentsOf: newIndices, at: 0)

        NSLog("[dwb-playback] queueInsertTop: count=%d wasEmpty=%d shuffle=%d endless=%d insertedDisplayIdx=%d files=%@",
              files.count,
              wasEmpty ? 1 : 0,
              isShuffleOn ? 1 : 0,
              isEndlessShuffleOn ? 1 : 0,
              0,
              files.map(\.lastPathComponent).joined(separator: ","))
        DebugConsoleController.log("queue", "add: count=\(files.count) wasEmpty=\(wasEmpty) files=\(files.map(\.lastPathComponent).prefix(3).joined(separator: ","))")

        currentDisplayIndex = 0
        pendingPlayNextSetIndices.removeAll()
        if randomizeShuffleStart && isShuffleOn {
            applyShuffleWithRandomStart()
        } else if !isShuffleOn {
            applyQueueSortIfNeeded(reason: "queue-top-insert", refreshUI: false)
        }
        if wasEmpty {
            playCurrentItem(startReason: "queue-top-insert-empty", expectPlaybackHandshake: true)
        } else {
            playCurrentItem(startReason: "queue-top-insert-start", expectPlaybackHandshake: true)
        }
    }

    /// Play the item at `currentDisplayIndex` within `displayOrder`.
    private func playCurrentItem(startReason: String = "direct",
                                 expectPlaybackHandshake: Bool = false,
                                 preserveCompletionSequence: Bool = false,
                                 transitionStrategy: PlaybackTransitionStrategy = .reuseCurrentPlayer) {
        enqueuePlaybackCommand(named: "playCurrentItem-\(startReason)") { [weak self] finish in
            self?.executePlayCurrentItem(startReason: startReason,
                                         expectPlaybackHandshake: expectPlaybackHandshake,
                                         preserveCompletionSequence: preserveCompletionSequence,
                                         transitionStrategy: transitionStrategy)
            finish()
        }
    }

    /// Convenience: sets a one-item playback set.
    func play(url: URL) {
        cancelPendingFolderScan()
        sourceFolderURLs = []
        openAndPlay(set: [url])
    }

    /// Appends `folder` to `sourceFolderURLs` if not already tracked (by standardized path).
    private func trackSourceFolder(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard !sourceFolderURLs.contains(where: { $0.standardizedFileURL.path == path }) else { return }
        sourceFolderURLs.append(folder)
    }

    // MARK: - Navigation

    func playPrevious() {
        guard currentDisplayIndex > 0 else { return }
        currentDisplayIndex -= 1
        DebugConsoleController.log("playback", "previous: displayIdx=\(currentDisplayIndex) source=prevButton")
        playCurrentItem(startReason: "manual-previous")
    }

    func playNext() {
        DebugConsoleController.log("playback", "next: source=nextButton")
        advanceToNextItem(reason: "manual-next")
    }

    // MARK: - Bookmarks

    func toggleBookmark() {
        guard let url = currentMediaURL else { return }
        BookmarkStore.shared.toggleBookmark(url: url)
        refreshQueueDisplays()
    }

    // MARK: - Shuffle

    func toggleShuffle() {
        // Rail button cycles: Off → Shuffle → Endless Shuffle → Off.
        if !isShuffleOn && !isEndlessShuffleOn {
            isShuffleOn = true
            queueSortMode = .manual
            applyShuffleKeepingCurrent()
        } else if isShuffleOn && !isEndlessShuffleOn {
            isEndlessShuffleOn = true
            if isRepeatOne { isRepeatOne = false }
            applyShuffleKeepingCurrent()
        } else {
            isShuffleOn = false
            isEndlessShuffleOn = false
            restoreNaturalOrder()
        }
        DebugConsoleController.log("playback", "shuffle: on=\(isShuffleOn) endless=\(isEndlessShuffleOn)")
        refreshQueueDisplays()
        logPlaybackQueueSnapshot("toggleShuffle")
    }

    /// Selects ordinary Shuffle directly, without advancing the user-facing
    /// Off → Shuffle → Endless → Off cycle. Folder drag/drop uses this after a
    /// successful intake so it can never accidentally select Endless Shuffle.
    private func setShuffleModeForFolderDrop() {
        guard !isShuffleOn || isEndlessShuffleOn else { return }
        isShuffleOn = true
        isEndlessShuffleOn = false
        queueSortMode = .manual
        applyShuffleKeepingCurrent()
        DebugConsoleController.log("playback", "shuffle: on=true endless=false source=folder-drop")
    }

    /// Selects the direct Folder-drop Shuffle mode before queue mutation and
    /// reports the randomized-start scope for this successful intake.
    private func prepareFolderDropShuffleIfNeeded(isDragDrop: Bool,
                                                  containsFolder: Bool,
                                                  addedPlayableMedia: Bool,
                                                  queueWasEmpty: Bool) -> FolderDropShuffleStartScope {
        let currentMode: FolderDropShuffleMode
        if isEndlessShuffleOn {
            currentMode = .endless
        } else if isShuffleOn {
            currentMode = .shuffle
        } else {
            currentMode = .off
        }

        guard FolderDropShufflePolicy.resultingMode(
            currentMode: currentMode,
            isDragDrop: isDragDrop,
            containsFolder: containsFolder,
            addedPlayableMedia: addedPlayableMedia
        ) == .shuffle else { return .none }
        setShuffleModeForFolderDrop()
        return FolderDropShuffleStartPolicy.scope(
            isDragDrop: isDragDrop,
            containsFolder: containsFolder,
            addedPlayableMedia: addedPlayableMedia,
            queueWasEmpty: queueWasEmpty
        )
    }

    /// Shuffle the playback set, keeping the currently playing item at position 0
    /// of the new traversal (already-played context is lost intentionally).
    private func applyShuffleKeepingCurrent() {
        let curPBIdx = currentSetIndex
        var indices = Array(0..<playbackSet.count)
        indices.shuffle()
        if curPBIdx >= 0, let pos = indices.firstIndex(of: curPBIdx) {
            indices.remove(at: pos)
            indices.insert(curPBIdx, at: 0)
        }
        displayOrder = indices
        pendingPlayNextSetIndices.removeAll()
        currentDisplayIndex = 0
    }

    /// Shuffle the full playback set without preserving the previous current
    /// item, so a successful folder drop can begin at a random accepted item.
    private func applyShuffleWithRandomStart() {
        displayOrder = Array(0..<playbackSet.count).shuffled()
        pendingPlayNextSetIndices.removeAll()
        currentDisplayIndex = 0
    }

    /// Restore natural (non-shuffled) order, keeping the current item at its natural index.
    private func restoreNaturalOrder() {
        let curPBIdx = currentSetIndex
        displayOrder = Array(0..<playbackSet.count)
        pendingPlayNextSetIndices.removeAll()
        currentDisplayIndex = curPBIdx >= 0 ? curPBIdx : 0
        applyQueueSortIfNeeded(reason: "restore-natural-order", refreshUI: false)
    }

    func toggleEndlessShuffle() {
        isEndlessShuffleOn.toggle()
        if isEndlessShuffleOn {
            if isRepeatOne { isRepeatOne = false }
            if !isShuffleOn { isShuffleOn = true }
            queueSortMode = .manual
            applyShuffleKeepingCurrent()
        }
        DebugConsoleController.log("playback", "endlessShuffle: on=\(isEndlessShuffleOn)")
        refreshQueueDisplays()
        logPlaybackQueueSnapshot("toggleEndlessShuffle")
    }

    // MARK: - Repeat

    func toggleRepeat() {
        isRepeatOne.toggle()
        if isRepeatOne {
            isEndlessShuffleOn = false
        }
        DebugConsoleController.log("playback", "repeat: on=\(isRepeatOne)")
        transport.update()
        logPlaybackQueueSnapshot("toggleRepeat")
    }

    private var canAdvanceAfterCompletion: Bool {
        guard currentDisplayIndex >= 0, !displayOrder.isEmpty else { return false }
        if currentDisplayIndex < displayOrder.count - 1 { return true }
        return isEndlessShuffleOn && !playbackSet.isEmpty
    }

    @discardableResult
    private func advanceToNextItem(reason: String,
                                   expectPlaybackHandshake: Bool = false,
                                   preserveCompletionSequence: Bool = false,
                                   transitionStrategy: PlaybackTransitionStrategy = .reuseCurrentPlayer) -> Bool {
        guard canAdvanceAfterCompletion else {
            NSLog("[dwb-playback] %@: no next item", reason)
            return false
        }

        if currentDisplayIndex < displayOrder.count - 1 {
            currentDisplayIndex += 1
        } else if isEndlessShuffleOn {
            beginNextEndlessShuffleCycle()
        }

        NSLog("[dwb-playback] %@: advancing to displayIdx=%d endless=%d",
              reason, currentDisplayIndex, isEndlessShuffleOn ? 1 : 0)
        playCurrentItem(startReason: reason,
                        expectPlaybackHandshake: expectPlaybackHandshake,
                        preserveCompletionSequence: preserveCompletionSequence,
                        transitionStrategy: transitionStrategy)
        return true
    }

    private func beginNextEndlessShuffleCycle() {
        let priorSetIndex = currentSetIndex
        var indices = Array(0..<playbackSet.count)
        indices.shuffle()
        if indices.count > 1, indices.first == priorSetIndex,
           let swapIndex = indices.indices.dropFirst().randomElement() {
            indices.swapAt(0, swapIndex)
        }
        displayOrder = indices
        pendingPlayNextSetIndices.removeAll()
        currentDisplayIndex = 0
        NSLog("[dwb-playback] endlessShuffleCycle: priorSetIdx=%d newOrder=[%@]",
              priorSetIndex,
              indices.map(String.init).joined(separator: ","))
    }

    private func applyQueueSortIfNeeded(reason: String,
                                        refreshUI: Bool = true,
                                        preserveCurrentItem: Bool = true) {
        guard queueSortMode != .manual, !displayOrder.isEmpty else {
            if preserveCurrentItem {
                remapCurrentDisplayIndex(toSetIndex: currentSetIndex)
            }
            if refreshUI { refreshQueueDisplays() }
            return
        }

        guard !queueSortOrderFrozenAfterRename else {
            NSLog("[dwb-playback] queueSortApply: skipped reason=%@ mode=%@ renameOrderFrozen=1",
                  reason, queueSortMode.title)
            if refreshUI { refreshQueueDisplays() }
            return
        }

        let currentSetIndex = preserveCurrentItem ? self.currentSetIndex : -1
        displayOrder = stableSortedDisplayOrder(from: displayOrder, mode: queueSortMode)
        if currentSetIndex >= 0 {
            remapCurrentDisplayIndex(toSetIndex: currentSetIndex)
        } else if currentDisplayIndex >= displayOrder.count {
            currentDisplayIndex = max(0, displayOrder.count - 1)
        }

        NSLog("[dwb-playback] queueSortApply: mode=%@ reason=%@ displayIdx=%d order=[%@]",
              queueSortMode.title,
              reason,
              currentDisplayIndex,
              displayOrder.map(String.init).joined(separator: ","))

        if refreshUI { refreshQueueDisplays() }
    }

    private func stableSortedDisplayOrder(from order: [Int], mode: QueueSortMode) -> [Int] {
        let indexedOrder = Array(order.enumerated())
        return indexedOrder.sorted { lhs, rhs in
            let result = compareQueueSort(lhs.element, rhs.element, mode: mode)
            if result != 0 { return result < 0 }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func compareQueueSort(_ lhsSetIndex: Int, _ rhsSetIndex: Int, mode: QueueSortMode) -> Int {
        let lhsURL = playbackURL(forSetIndex: lhsSetIndex)
        let rhsURL = playbackURL(forSetIndex: rhsSetIndex)

        switch mode {
        case .manual:
            return 0
        case .filenameAscending:
            return compareQueueFilenames(lhsURL, rhsURL, ascending: true)
        case .filenameDescending:
            return compareQueueFilenames(lhsURL, rhsURL, ascending: false)
        case .fileSizeAscending:
            return compareIntegers(queueFileSizeSortKey(for: lhsURL), queueFileSizeSortKey(for: rhsURL))
        case .fileSizeDescending:
            return compareIntegers(queueFileSizeSortKey(for: rhsURL), queueFileSizeSortKey(for: lhsURL))
        case .durationAscending:
            return compareDurationKeys(lhsURL, rhsURL, ascending: true)
        case .durationDescending:
            return compareDurationKeys(lhsURL, rhsURL, ascending: false)
        }
    }

    private func compareQueueFilenames(_ lhsURL: URL?, _ rhsURL: URL?, ascending: Bool) -> Int {
        switch (lhsURL, rhsURL) {
        case let (lhs?, rhs?):
            let result = MediaFileSupport.compareFinderNaturalFilenames(lhs, rhs)
            if result == .orderedSame { return 0 }
            let ascendingResult = result == .orderedAscending ? -1 : 1
            return ascending ? ascendingResult : -ascendingResult
        case (nil, nil):
            return 0
        case (nil, _?):
            return ascending ? -1 : 1
        case (_?, nil):
            return ascending ? 1 : -1
        }
    }

    private func compareDurationKeys(_ lhsURL: URL?, _ rhsURL: URL?, ascending: Bool) -> Int {
        let lhs = lhsURL.flatMap { durationSecondsCache[$0] }
        let rhs = rhsURL.flatMap { durationSecondsCache[$0] }

        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs { return ascending ? -1 : 1 }
            if lhs > rhs { return ascending ? 1 : -1 }
            return 0
        case (nil, nil):
            return 0
        case (nil, _?):
            return ascending ? 1 : -1
        case (_?, nil):
            return ascending ? -1 : 1
        }
    }

    private func compareIntegers(_ lhs: Int64, _ rhs: Int64) -> Int {
        if lhs < rhs { return -1 }
        if lhs > rhs { return 1 }
        return 0
    }

    private func queueFileSizeSortKey(for url: URL?) -> Int64 {
        guard let url else { return 0 }
        if VolumeClassifier.shared.kind(for: url) == .nonLocal {
            return nonLocalFiles.sizeSortKey(for: url)   // cached; 0 until the background read lands
        }
        return MediaFileSupport.fileSizeBytes(for: url) ?? 0
    }

    private func playbackURL(forSetIndex setIndex: Int) -> URL? {
        guard setIndex >= 0, setIndex < playbackSet.count else { return nil }
        return playbackSet[setIndex]
    }

    private func remapCurrentDisplayIndex(toSetIndex setIndex: Int) {
        guard setIndex >= 0 else {
            currentDisplayIndex = displayOrder.isEmpty ? -1 : min(max(0, currentDisplayIndex), displayOrder.count - 1)
            return
        }
        guard let remappedIndex = displayOrder.firstIndex(of: setIndex) else {
            currentDisplayIndex = displayOrder.isEmpty ? -1 : min(max(0, currentDisplayIndex), displayOrder.count - 1)
            return
        }
        currentDisplayIndex = remappedIndex
    }

    private func refreshQueueDisplays() {
        transport.update()
        if isQueuePageOpen { refreshQueuePage() }
    }

    private func queueTotalDurationText(for urls: [URL]) -> String {
        guard !urls.isEmpty else { return MediaFileSupport.formatClockDuration(0) }

        var knownTotalSeconds = 0
        var knownCount = 0
        var unknownCount = 0

        for url in urls {
            if let seconds = durationSecondsCache[url], seconds > 0 {
                knownTotalSeconds += Int(seconds.rounded(.down))
                knownCount += 1
            } else {
                unknownCount += 1
            }
        }

        guard knownCount > 0 else { return "--:--" }
        let formatted = MediaFileSupport.formatClockDuration(knownTotalSeconds)
        return unknownCount > 0 ? "\(formatted) +" : formatted
    }

    private func updateDurationCache(for url: URL, metadata: MediaFileSupport.DurationMetadata) {
        durationCache[url] = metadata.displayString
        if let seconds = metadata.seconds, seconds > 0 {
            durationSecondsCache[url] = seconds
        } else {
            durationSecondsCache.removeValue(forKey: url)
        }
    }

    // MARK: - Queue page (full in-window panel)

    func toggleQueuePage() {
        isQueuePageOpen.toggle()
        DebugConsoleController.log("queue", "page: \(isQueuePageOpen ? "open" : "close")")
        if isQueuePageOpen {
            // Synchronous path on user-open so the panel doesn't show empty for a tick.
            refreshQueuePageNow()
        }
        layoutPlayerViews()
        transport.update()
    }

    // MARK: - Queue Page width (drag resize)

    private func queuePanelResizeDragged(toEdgeX edgeX: CGFloat) {
        guard let cv = window?.contentView, isQueuePageOpen, layoutMode != .fullscreen else { return }
        queuePanelWidthFraction = QueuePanelWidthPolicy.customFraction(forEdgeX: edgeX,
                                                                       contentWidth: cv.bounds.width)
        layoutPlayerViews()
    }

    private func resetQueuePanelWidth() {
        queuePanelWidthFraction = nil
        layoutPlayerViews()
        logQueuePanelWidth(event: "reset")
    }

    private func logQueuePanelWidth(event: String) {
        let contentW = window?.contentView?.bounds.width ?? 0
        let fraction = queuePanelWidthFraction.map { String(format: "%.3f", $0) } ?? "default"
        DebugConsoleController.log("queue", String(format: "panelWidth: %@ width=%.0f contentWidth=%.0f fraction=%@",
                                                   event, queuePage.frame.width, contentW, fraction))
    }

    // Coalesces multiple refreshQueuePage() calls within one runloop tick into a
    // single rebuild. Multi-window playback fires this from many paths (videoStart,
    // duration metadata callbacks, settings changes, sort changes, queue mutation),
    // and back-to-back synchronous reloads contributed to main-thread saturation
    // when several windows were active.
    private var pendingQueuePageRefresh = false

    func refreshQueuePage() {
        guard isQueuePageOpen else { return }
        if pendingQueuePageRefresh { return }
        pendingQueuePageRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pendingQueuePageRefresh = false
            if self.isQueuePageOpen { self.refreshQueuePageNow() }
        }
    }

    private func refreshQueuePageNow() {
        let urls = displayOrder.map { playbackSet[$0] }
        var qItems: [QueuePageView.Item] = []
        // Positions in the Play Next chain (1-based), by set index.
        var playNextPositions: [Int: Int] = [:]
        for (offset, setIndex) in pendingPlayNextSetIndices.enumerated() { playNextPositions[setIndex] = offset + 1 }

        var nonLocalURLs: [URL] = []

        for (displayIndex, url) in urls.enumerated() {
            let isNonLocal = VolumeClassifier.shared.kind(for: url) == .nonLocal
            let size: String
            if isNonLocal {
                size = nonLocalFiles.sizeString(for: url)
                nonLocalURLs.append(url)
            } else {
                size = MediaFileSupport.fileSizeString(for: url)
            }
            let dur: String
            if MediaFileSupport.isImage(url) {
                let metadata = queueImageDurationMetadata(for: url)
                updateDurationCache(for: url, metadata: metadata)
                dur = metadata.displayString
            } else if let cached = durationCache[url] {
                dur = cached
            } else {
                // Set placeholder to prevent re-triggering; kick off async fetch. A non-local
                // file is never probed (P142.1): it shows `--:--` until VLC reports its length.
                let mayProbe = mayStartDurationProbe(for: url, volume: isNonLocal ? .nonLocal : .local)
                let placeholder = mayProbe && MediaFileSupport.needsStableDuration(url)
                    ? MediaFileSupport.durationLoadingText
                    : MediaFileSupport.durationUnknownText
                durationCache[url] = placeholder
                if mayProbe {
                    let capturedURL = url
                    MediaFileSupport.loadDurationMetadata(for: url) { [weak self] metadata in
                        guard let self = self else { return }
                        self.updateDurationCache(for: capturedURL, metadata: metadata)
                        if self.queueSortMode == .durationAscending || self.queueSortMode == .durationDescending {
                            self.applyQueueSortIfNeeded(reason: "duration-metadata-update")
                        } else if self.isQueuePageOpen {
                            self.refreshQueuePage()
                        }
                    }
                }
                dur = placeholder
            }
            qItems.append(queueItem(for: url, displayIndex: displayIndex, duration: dur, size: size,
                                    playNextPositions: playNextPositions))
        }

        if !nonLocalURLs.isEmpty { nonLocalFiles.request(nonLocalURLs) }

        queuePage.update(items: qItems,
                         currentIndex: currentDisplayIndex,
                         sortMode: queueSortMode,
                         totalDurationText: queueTotalDurationText(for: urls))
    }

    private func queueItem(for url: URL,
                           displayIndex: Int,
                           duration: String,
                           size: String,
                           playNextPositions: [Int: Int]) -> QueuePageView.Item {
        QueuePageView.Item(
            url: url,
            displayName: url.lastPathComponent,
            duration: duration,
            fileSize: size,
            isBookmarked: BookmarkStore.shared.isBookmarked(url: url),
            isFailed: failedPlaybackPaths.contains(url.standardizedFileURL.path),
            playNextPosition: displayIndex < displayOrder.count ? playNextPositions[displayOrder[displayIndex]] : nil
        )
    }

    // MARK: - Non-local volumes (P142)

    /// A batch of size and existence reads finished: rename may have become available, and the
    /// queue page shows the new sizes. Once per batch, never once per file.
    private func nonLocalFactsDidArrive() {
        guard !isWindowClosed else { return }
        transport.update()
        if queueSortMode == .fileSizeAscending || queueSortMode == .fileSizeDescending {
            applyQueueSortIfNeeded(reason: "size-metadata-update")
        } else if isQueuePageOpen {
            refreshQueuePage()
        }
    }

    /// A queue was loaded or replaced with `urls`: stale non-local state is dropped, and the
    /// load is logged once when any file is on a non-local volume.
    private func noteQueueLoaded(_ urls: [URL], replacing: Bool) {
        VolumeClassifier.shared.refresh()
        let nonLocal = urls.filter { VolumeClassifier.shared.kind(for: $0) == .nonLocal }
        if replacing {
            let keep = Set(urls.map { NonLocalFileMetadataStore.key(for: $0) })
            nonLocalFiles.retain(paths: keep)
            reportedDurations.removeAll()
        }
        guard let first = nonLocal.first else { return }
        DebugConsoleController.log("volume", "non-local: path=\(first.deletingLastPathComponent().lastPathComponent) items=\(nonLocal.count)")
    }

    /// Player starts a duration probe (an `AVURLAsset` load or a VLC parse) only for a local file.
    private func mayStartDurationProbe(for url: URL, volume: VolumeKind) -> Bool {
        let fileKind: DurationProbePolicy.FileKind
        if MediaFileSupport.isImage(url) {
            fileKind = .imageOrGIF
        } else if MediaFileSupport.needsStableDuration(url) {
            fileKind = .mpg
        } else {
            fileKind = .video
        }
        return DurationProbePolicy.mayStartProbe(volume: volume, fileKind: fileKind)
    }

    /// VLC reported `lengthMs` for the playing item. For a non-local item the first positive
    /// length becomes its duration: stored once, shown on the transport and in its queue row.
    /// Called from the existing progress snapshot; nothing here polls.
    private func noteVLCReportedLength(_ lengthMs: Int) {
        guard currentItemVolumeKind == .nonLocal, !currentItemIsImage, !isWindowClosed,
              let url = currentMediaURL,
              player.media?.url?.standardizedFileURL.path == url.standardizedFileURL.path,
              reportedDurations.accept(lengthMs: lengthMs, for: NonLocalFileMetadataStore.key(for: url))
        else { return }
        let seconds = Double(lengthMs) / 1000.0
        let metadata = MediaFileSupport.DurationMetadata(seconds: seconds,
                                                         displayString: MediaFileSupport.formatDuration(seconds))
        updateDurationCache(for: url, metadata: metadata)
        currentDurationIsProvisional = false
        transport.update()
        DebugConsoleController.log("volume", "duration: \(url.lastPathComponent) \(metadata.displayString) from=player")
        if queueSortMode == .durationAscending || queueSortMode == .durationDescending {
            applyQueueSortIfNeeded(reason: "duration-metadata-update")
        } else if isQueuePageOpen {
            refreshQueuePage()
        }
    }

    // MARK: - Reveal in Finder

    func revealInFinder() {
        guard let url = currentMediaURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealInFinder(displayIndex: Int) {
        guard let url = urlForDisplayIndex(displayIndex) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func urlForDisplayIndex(_ displayIndex: Int) -> URL? {
        guard displayIndex >= 0, displayIndex < displayOrder.count else { return nil }
        let pbIdx = displayOrder[displayIndex]
        guard pbIdx >= 0, pbIdx < playbackSet.count else { return nil }
        return playbackSet[pbIdx]
    }

    // MARK: - Rename (menu entry point — renames current item)

    func showRenameSheet() {
        guard canRenameCurrentMedia else { return }
        showRenameSheet(forDisplayIndex: currentDisplayIndex)
    }

    /// Shows the rename sheet for the item at the given display-order index.
    func showRenameSheet(forDisplayIndex displayIndex: Int) {
        guard displayIndex >= 0, displayIndex < displayOrder.count else { return }
        let pbIdx = displayOrder[displayIndex]
        guard pbIdx >= 0, pbIdx < playbackSet.count, let win = window else { return }

        let url  = playbackSet[pbIdx]
        let ext  = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()

        // The design system's rename sheet (9.3). Its validation only prevents a rename that
        // `renameFile(at:to:)` would reject; that method and its failure sheet are unchanged.
        DWBRenameSheet.present(
            on: win,
            filename: url.lastPathComponent,
            stem: stem,
            fileExtension: ext,
            nameExists: { name in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(name, isDirectory: false).path)
            },
            onRename: { [weak self] newName in
                self?.renameFile(at: pbIdx, to: newName)
            }
        )
    }

    func removeCurrentQueueItem() {
        removeQueueItem(displayIndex: currentDisplayIndex)
    }

    func removeAllQueueItems(source: String = "menu") {
        cancelPendingFolderScan()
        failedPlaybackPaths.removeAll()
        guard !playbackSet.isEmpty || !displayOrder.isEmpty else { return }
        NSLog("[dwb-playback] removeAll: source=%@ clearing entire queue (count=%d)", source, playbackSet.count)
        DebugConsoleController.log("queue", "removeAll: source=\(source) count=\(playbackSet.count)")

        // Cancel any pending autoplay / completion sequences before stopping.
        resetPlaybackCompletionSignals(reason: "queue-remove-all-\(source)")
        queuedPlaybackCommands.removeAll()

        // Stop playback — image or video. This is intentionally queue-only and
        // does not delete, rename, move, or otherwise mutate media files.
        if currentItemIsImage {
            clearImageSlideshowState()
        } else if player.media != nil {
            isUserStop = true
            player.stop()
            // isUserStop is reset in the asynchronous .stopped handler.
        }

        // Clear all queue state synchronously. By the time the async .stopped
        // callback fires on main queue, the queue is already empty, so even if
        // isUserStop were missed, advanceToNextItem would correctly find nothing.
        playbackSet.removeAll()
        displayOrder.removeAll()
        pendingPlayNextSetIndices.removeAll()
        sourceFolderURLs.removeAll()
        currentDisplayIndex          = -1
        currentMediaURL              = nil
        currentDurationIsProvisional = false
        queueEndedNaturally          = false
        durationCache.removeAll()
        durationSecondsCache.removeAll()
        reportedDurations.removeAll()
        nonLocalFiles.removeAll()
        gifDurations.removeAll()
        updateGIFIntakeProgress { $0.retain(paths: []) }
        queueSortMode                = .manual

        updateWindowTitle(Self.defaultWindowTitle)
        transport.update()
        if isQueuePageOpen { refreshQueuePage() }
        logPlaybackQueueSnapshot("removeAll")
    }

    func removeQueueItem(displayIndex: Int) {
        guard displayIndex >= 0, displayIndex < displayOrder.count else { return }
        let removedSetIndex = displayOrder[displayIndex]
        guard removedSetIndex >= 0, removedSetIndex < playbackSet.count else { return }

        let removingCurrent = displayIndex == currentDisplayIndex
        let removedURL = playbackSet[removedSetIndex]
        NSLog("[dwb-playback] queueDelete: displayIdx=%d setIdx=%d current=%d file=%@",
              displayIndex, removedSetIndex, removingCurrent ? 1 : 0, removedURL.lastPathComponent)
        DebugConsoleController.log("queue", "remove: file=\(removedURL.lastPathComponent) isCurrent=\(removingCurrent)")

        displayOrder.remove(at: displayIndex)
        playbackSet.remove(at: removedSetIndex)
        durationCache.removeValue(forKey: removedURL)
        durationSecondsCache.removeValue(forKey: removedURL)
        let removedPath = removedURL.standardizedFileURL.path
        if !playbackSet.contains(where: { $0.standardizedFileURL.path == removedPath }) {
            reportedDurations.forget(NonLocalFileMetadataStore.key(for: removedURL))
            nonLocalFiles.invalidate(removedURL)
            gifDurations.invalidate(removedURL)
            updateGIFIntakeProgress { $0.finish(removedPath) }
        }
        displayOrder = displayOrder.map { $0 > removedSetIndex ? $0 - 1 : $0 }
        PlayNextChainPolicy.onQueueItemRemoved(
            removedSetIndex: removedSetIndex,
            pendingSetIndices: &pendingPlayNextSetIndices
        )

        if playbackSet.isEmpty || displayOrder.isEmpty {
            if removingCurrent, player.media != nil {
                enqueueStopPlaybackCommand(reason: "queue-delete-empty")
            }
            currentDisplayIndex = -1
            currentMediaURL = nil
            currentDurationIsProvisional = false
            updateWindowTitle(Self.defaultWindowTitle)
            transport.update()
            if isQueuePageOpen { refreshQueuePage() }
            logPlaybackQueueSnapshot("queueDelete-empty")
            return
        }

        if removingCurrent {
            currentDisplayIndex = min(displayIndex, displayOrder.count - 1)
            playCurrentItem(startReason: "queue-delete-current")
        } else {
            if displayIndex < currentDisplayIndex {
                currentDisplayIndex -= 1
            } else if currentDisplayIndex >= displayOrder.count {
                currentDisplayIndex = displayOrder.count - 1
            }
            transport.update()
            if isQueuePageOpen { refreshQueuePage() }
            logPlaybackQueueSnapshot("queueDelete")
        }
    }

    /// Core rename logic: moves the file on disk and updates all in-memory references.
    @discardableResult
    private func renameFile(at playbackSetIndex: Int, to newName: String) -> Bool {
        guard playbackSetIndex >= 0, playbackSetIndex < playbackSet.count,
              let win = window else { return false }

        let url    = playbackSet[playbackSetIndex]
        let dir    = url.deletingLastPathComponent()
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let validatedName = validatedRenameFilename(trimmedName, originalURL: url) else {
            presentRenameAlert(title: "Cannot Rename",
                               message: "Enter a valid filename. The extension is preserved automatically, and filenames cannot contain path separators.",
                               window: win)
            return false
        }
        let newURL = dir.appendingPathComponent(validatedName, isDirectory: false)

        guard FileManager.default.fileExists(atPath: url.path) else {
            DebugConsoleController.log(level: .warning, category: "rename", message: "missing source: \(url.lastPathComponent)")
            presentRenameAlert(title: "Cannot Rename",
                               message: "The original file could not be found.",
                               window: win)
            return false
        }

        guard newURL.path != url.path else {
            DebugConsoleController.log("rename", "noop: unchanged file=\(url.lastPathComponent)")
            return false
        }

        if FileManager.default.fileExists(atPath: newURL.path) {
            DebugConsoleController.log(level: .warning, category: "rename", message: "collision: \(url.lastPathComponent) → \(validatedName) (target exists)")
            presentRenameAlert(title: "Cannot Rename",
                               message: "A file named \"\(validatedName)\" already exists in this folder.",
                               window: win)
            return false
        }

        do {
            try FileManager.default.moveItem(at: url, to: newURL)
        } catch {
            DebugConsoleController.log(level: .error, category: "error", message: "rename failed: \(url.lastPathComponent) → \(validatedName): \(error.localizedDescription)")
            presentRenameAlert(title: "Rename Failed",
                               message: error.localizedDescription,
                               window: win)
            return false
        }

        DebugConsoleController.log("rename", "success: \(url.lastPathComponent) → \(validatedName)")
        updateRenamedQueueReferences(from: url, to: newURL)
        return true
    }

    private func updateRenamedQueueReferences(from oldURL: URL, to newURL: URL) {
        let matchingIndices = playbackSet.indices.filter {
            playbackSet[$0].standardizedFileURL.path == oldURL.standardizedFileURL.path
        }
        guard !matchingIndices.isEmpty else { return }

        for index in matchingIndices {
            playbackSet[index] = newURL
        }
        if let cachedDuration = durationCache.removeValue(forKey: oldURL) {
            durationCache[newURL] = cachedDuration
        }
        if let cachedSeconds = durationSecondsCache.removeValue(forKey: oldURL) {
            durationSecondsCache[newURL] = cachedSeconds
        }
        gifDurations.move(from: oldURL, to: newURL)
        updateGIFIntakeProgress { $0.finish(GIFDurationStore.key(for: oldURL)) }
        reportedDurations.move(from: NonLocalFileMetadataStore.key(for: oldURL),
                               to: NonLocalFileMetadataStore.key(for: newURL))
        nonLocalFiles.invalidate(oldURL)
        if VolumeClassifier.shared.kind(for: newURL) == .nonLocal { nonLocalFiles.request([newURL]) }

        if currentMediaURL?.standardizedFileURL.path == oldURL.standardizedFileURL.path {
            currentMediaURL = newURL
            updateWindowTitle(newURL.lastPathComponent)
        }

        // A rename changes queue metadata, but must not implicitly reapply an active
        // sort: `displayOrder` is also the live playback order and may contain a
        // P120.1 Play Next chain. An explicit later sort remains authoritative.
        queueSortOrderFrozenAfterRename = queueSortMode != .manual
        refreshQueueDisplays()
        // Note: VLC continues playing from the already-open file descriptor;
        // the new path takes effect the next time playCurrentItem() is called.
    }

    func undoLastMarkerRename() {
        guard let win = window, let step = markerRenameUndoState.step else { return }
        // The step is used (or cleared on failure) from here on, so the toast goes.
        hideUndoToast()

        switch MarkerRenameUndoPlan.build(for: step) {
        case .failure(.missingSource):
            markerRenameUndoState.clear()
            presentRenameAlert(title: "Cannot Rename",
                               message: "The original file could not be found.",
                               window: win)
        case .failure(.destinationCollision(let filename)):
            markerRenameUndoState.clear()
            presentRenameAlert(title: "Cannot Rename",
                               message: "A file named \"\(filename)\" already exists in this folder.",
                               window: win)
        case .success(let plan):
            var completed: [PlannedMarkerRenameUndo] = []
            do {
                for rename in plan {
                    try FileManager.default.moveItem(at: rename.sourceURL, to: rename.destinationURL)
                    completed.append(rename)
                }
            } catch {
                for rename in completed.reversed() {
                    try? FileManager.default.moveItem(at: rename.destinationURL, to: rename.sourceURL)
                }
                markerRenameUndoState.clear()
                presentRenameAlert(title: "Rename Failed", message: error.localizedDescription, window: win)
                return
            }

            for rename in plan {
                updateRenamedQueueReferences(from: rename.sourceURL, to: rename.destinationURL)
            }
            markerRenameUndoState.clear()
        }
    }

    private func validatedRenameFilename(_ filename: String, originalURL: URL) -> String? {
        guard !filename.isEmpty, filename != ".", filename != ".." else { return nil }
        guard filename.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else { return nil }
        guard filename.utf8.allSatisfy({ $0 != 0 }) else { return nil }

        let originalExtension = originalURL.pathExtension
        let candidateURL = URL(fileURLWithPath: filename)
        guard candidateURL.lastPathComponent == filename else { return nil }
        if !originalExtension.isEmpty,
           candidateURL.pathExtension.caseInsensitiveCompare(originalExtension) != .orderedSame {
            return nil
        }
        if originalExtension.isEmpty, !candidateURL.pathExtension.isEmpty {
            return nil
        }
        return filename
    }

    private func presentRenameAlert(title: String, message: String, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    // MARK: - Fullscreen toggle

    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    // MARK: - Drop / open URL handling

    private func presentIntakeFailure(
        _ failure: MediaIntakeFailure,
        sourceURLs: [URL],
        retryContext: IntakeRecoveryRetryContext?
    ) {
        gifIntakeProgress = nil
        intakeRecoverySourceURLs = sourceURLs
        intakeRecoveryRetryContext = retryContext
        intakeRecoveryView.present(MediaIntakeRecoveryMapper.presentation(for: failure))
        layoutPlayerViews()
        DebugConsoleController.log("queue", "intakeRecovery: \(MediaIntakeRecoveryMapper.presentation(for: failure).title)")
    }

    private func presentIntakeScanning(
        folderCount: Int,
        sourceURLs: [URL],
        retryContext: IntakeRecoveryRetryContext
    ) {
        gifIntakeProgress = nil
        intakeScanningFolderCount = max(1, folderCount)
        intakeRecoverySourceURLs = sourceURLs
        intakeRecoveryRetryContext = retryContext
        intakeRecoveryView.present(.scanning(folderCount: intakeScanningFolderCount))
        layoutPlayerViews()
        DebugConsoleController.log("queue", "intakeRecovery: scanning folders=\(folderCount)")
    }

    /// Made on main; the scanner calls it on its own thread. Counts hop back to main and are
    /// ignored once that scan is superseded, cancelled, or finished.
    private func makeIntakeScanFoundReporter(generation: UInt64) -> (Int) -> Void {
        { [weak self] count in
            DispatchQueue.main.async {
                self?.showIntakeScanFound(count, generation: generation)
            }
        }
    }

    private func showIntakeScanFound(_ count: Int, generation: UInt64) {
        guard folderScanGeneration == generation, folderScanTask != nil else { return }
        intakeRecoveryView.present(.scanning(folderCount: intakeScanningFolderCount, foundCount: count))
    }

    private func clearIntakeRecovery() {
        gifIntakeProgress = nil
        intakeRecoveryRetryContext = nil
        intakeRecoverySourceURLs = []
        intakeRecoveryView.dismiss()
    }

    private func handleIntakeRecoveryAction(_ action: MediaIntakeRecoveryAction) {
        switch action {
        case .addMedia:
            openFile()
        case .openAcceptSettings:
            SettingsWindowController.shared.openAcceptSettings()
        case .retryRescan:
            switch intakeRecoveryRetryContext {
            case .intake(let urls, let appendingExplicitFiles, let isDragDrop):
                handleDroppedURLs(
                    urls,
                    appendingExplicitFiles: appendingExplicitFiles,
                    isDragDrop: isDragDrop
                )
            case .rescan(let folders):
                guard !folders.isEmpty else {
                    locateRecoverySource()
                    return
                }
                startAsyncFolderRescan(
                    foldersToScan: folders,
                    acceptedKinds: SettingsWindowController.acceptedMediaKinds()
                )
            case .none:
                locateRecoverySource()
            }
        case .revealSource:
            guard let source = intakeRecoverySourceURLs.first else { return }
            NSWorkspace.shared.activateFileViewerSelecting([source])
        case .locateSource:
            locateRecoverySource()
        case .showDetails:
            break // Expanded locally by IntakeRecoveryView.
        case .cancelIntake:
            cancelIntakeFromCard()
        }
    }

    /// Cancel on the progress card: a running scan stops with the queue unchanged; GIF
    /// loading stops for the intake's remaining files, which load again when Queue shows them.
    private func cancelIntakeFromCard() {
        if folderScanTask != nil {
            cancelPendingFolderScan()
            DebugConsoleController.log("queue", "intakeRecovery: scan cancelled")
        } else if let progress = gifIntakeProgress {
            gifDurations.cancelPending(keys: progress.remaining)
            DebugConsoleController.log("queue", "intakeRecovery: gifDurations cancelled remaining=\(progress.remaining.count)")
        }
        clearIntakeRecovery()
        layoutPlayerViews()
    }

    private func locateRecoverySource() {
        let panel = NSOpenPanel()
        panel.title = "Locate Source Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        let response = panel.runModal()
        Self.lastModalReturnMT = CACurrentMediaTime()
        guard response == .OK, !panel.urls.isEmpty else { return }

        switch intakeRecoveryRetryContext {
        case .intake(_, let appendingExplicitFiles, let isDragDrop):
            handleDroppedURLs(
                panel.urls,
                appendingExplicitFiles: appendingExplicitFiles,
                isDragDrop: isDragDrop
            )
        case .rescan, .none:
            sourceFolderURLs = panel.urls
            startAsyncFolderRescan(
                foldersToScan: panel.urls,
                acceptedKinds: SettingsWindowController.acceptedMediaKinds()
            )
        }
    }

    func handleDroppedURLs(_ urls: [URL],
                           appendingExplicitFiles: Bool = true,
                           isDragDrop: Bool = false) {
        guard !urls.isEmpty else { return }

        let unavailable = urls.filter { !FileManager.default.fileExists(atPath: $0.path) }
        if let missing = unavailable.first {
            presentIntakeFailure(
                .sourceUnavailable(
                    name: missing.lastPathComponent,
                    diagnostic: "The selected local source no longer exists or is unavailable at \(missing.path)."
                ),
                sourceURLs: urls,
                retryContext: .intake(
                    urls: urls,
                    appendingExplicitFiles: appendingExplicitFiles,
                    isDragDrop: isDragDrop
                )
            )
            return
        }

        var dirs:  [URL] = []
        var files: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { dirs.append(url) } else { files.append(url) }
        }

        let acceptedKinds = SettingsWindowController.acceptedMediaKinds()

        guard !dirs.isEmpty else {
            cancelPendingFolderScan()
            let result = MediaFileSupport.expandToSupportedMedia(urls, acceptedKinds: acceptedKinds)
            applyExpandedMediaIntake(result: result,
                                     dirs: dirs,
                                     sourceURLs: urls,
                                     appendingExplicitFiles: appendingExplicitFiles,
                                     isDragDrop: isDragDrop)
            return
        }

        // Folders-only: single-folder drop inserts at top of existing queue (or replaces if empty).
        // Multi-folder selections fall through to the shared expansion path below.
        if !dirs.isEmpty && files.isEmpty {
            if dirs.count == 1 {
                let folder = dirs[0]
                startAsyncSingleFolderIntake(
                    folder: folder,
                    acceptedKinds: acceptedKinds,
                    isDragDrop: isDragDrop
                )
                return
            }
        }

        // Mixed files+folders, multi-folder-only, or files-only:
        // expand all URLs to supported media,
        // preserving top-level selection order (folders expand in-place, sorted).
        // Supports any number of folders. No dedupe is applied here; this preserves
        // the existing queue-ingestion semantics for explicit repeated selections.
        startAsyncExpandedMediaIntake(urls: urls,
                                      dirs: dirs,
                                      appendingExplicitFiles: appendingExplicitFiles,
                                      isDragDrop: isDragDrop,
                                      acceptedKinds: acceptedKinds)
    }

    private func startAsyncSingleFolderIntake(folder: URL,
                                             acceptedKinds: Set<MediaFileSupport.MediaKind>,
                                             isDragDrop: Bool) {
        let generation = beginFolderScanOperation()
        presentIntakeScanning(
            folderCount: 1,
            sourceURLs: [folder],
            retryContext: .intake(
                urls: [folder],
                appendingExplicitFiles: true,
                isDragDrop: isDragDrop
            )
        )
        DebugConsoleController.log("queue", "expandAsync: start singleFolder=\(folder.lastPathComponent)")
        let reportFound = makeIntakeScanFoundReporter(generation: generation)

        folderScanTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try MediaFileSupport.expandToSupportedMedia(
                    [folder],
                    acceptedKinds: acceptedKinds,
                    shouldCancel: { Task.isCancelled },
                    onFound: reportFound
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.folderScanGeneration == generation else { return }
                    self.folderScanTask = nil
                    self.applySingleFolderIntake(
                        folder: folder,
                        result: result,
                        isDragDrop: isDragDrop
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard let self, self.folderScanGeneration == generation else { return }
                    self.folderScanTask = nil
                    DebugConsoleController.log(level: .error,
                                               category: "queue",
                                               message: "expandAsync failed: \(error.localizedDescription)")
                    let failure: MediaIntakeFailure = FileManager.default.fileExists(atPath: folder.path)
                        ? .folderScanFailed(name: folder.lastPathComponent, diagnostic: error.localizedDescription)
                        : .sourceUnavailable(name: folder.lastPathComponent, diagnostic: error.localizedDescription)
                    self.presentIntakeFailure(
                        failure,
                        sourceURLs: [folder],
                        retryContext: .intake(
                            urls: [folder],
                            appendingExplicitFiles: true,
                            isDragDrop: isDragDrop
                        )
                    )
                }
            }
        }
    }

    private func startAsyncExpandedMediaIntake(urls: [URL],
                                               dirs: [URL],
                                               appendingExplicitFiles: Bool,
                                               isDragDrop: Bool,
                                               acceptedKinds: Set<MediaFileSupport.MediaKind>) {
        let generation = beginFolderScanOperation()
        presentIntakeScanning(
            folderCount: dirs.count,
            sourceURLs: urls,
            retryContext: .intake(
                urls: urls,
                appendingExplicitFiles: appendingExplicitFiles,
                isDragDrop: isDragDrop
            )
        )
        DebugConsoleController.log("queue", "expandAsync: start urls=\(urls.count) folders=\(dirs.count)")
        let reportFound = makeIntakeScanFoundReporter(generation: generation)

        folderScanTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try MediaFileSupport.expandToSupportedMedia(
                    urls,
                    acceptedKinds: acceptedKinds,
                    shouldCancel: { Task.isCancelled },
                    onFound: reportFound
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.folderScanGeneration == generation else { return }
                    self.folderScanTask = nil
                    self.applyExpandedMediaIntake(result: result,
                                                  dirs: dirs,
                                                  sourceURLs: urls,
                                                  appendingExplicitFiles: appendingExplicitFiles,
                                                  isDragDrop: isDragDrop)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard let self, self.folderScanGeneration == generation else { return }
                    self.folderScanTask = nil
                    DebugConsoleController.log(level: .error,
                                               category: "queue",
                                               message: "expandAsync failed: \(error.localizedDescription)")
                    self.presentIntakeFailure(
                        .folderScanFailed(name: nil, diagnostic: error.localizedDescription),
                        sourceURLs: dirs,
                        retryContext: .intake(
                            urls: urls,
                            appendingExplicitFiles: appendingExplicitFiles,
                            isDragDrop: isDragDrop
                        )
                    )
                }
            }
        }
    }

    private func applySingleFolderIntake(folder: URL,
                                         result: MediaFileSupport.ExpansionResult,
                                         isDragDrop: Bool) {
        guard !result.media.isEmpty else {
            showEmptyIntakeMessage(
                result: result,
                sourceURLs: [folder],
                retryContext: .intake(
                    urls: [folder],
                    appendingExplicitFiles: true,
                    isDragDrop: isDragDrop
                ),
                emptyFolderNames: [folder.lastPathComponent]
            )
            return
        }

        clearIntakeRecovery()

        let queueEmpty = playbackSet.isEmpty || displayOrder.isEmpty
        let shuffleStartScope = prepareFolderDropShuffleIfNeeded(
            isDragDrop: isDragDrop,
            containsFolder: true,
            addedPlayableMedia: true,
            queueWasEmpty: queueEmpty
        )
        let randomizeShuffleStart = shuffleStartScope != .none
        if queueEmpty {
            sourceFolderURLs = [folder]
            openAndPlay(set: result.media, randomizeShuffleStart: randomizeShuffleStart)
        } else {
            trackSourceFolder(folder)
            appendToQueue(files: result.media, randomizeShuffleStart: randomizeShuffleStart)
        }
        if randomizeShuffleStart {
            refreshQueueDisplays()
            logPlaybackQueueSnapshot("folderDropShuffle")
        }
        beginGIFIntakeProgress(for: result.media)
    }

    private func applyExpandedMediaIntake(result: MediaFileSupport.ExpansionResult,
                                          dirs: [URL],
                                          sourceURLs: [URL],
                                          appendingExplicitFiles: Bool,
                                          isDragDrop: Bool) {
        let expanded = result.media
        let emptyFolders = result.emptyFolderNames

        guard !expanded.isEmpty else {
            if result.excludedMediaCount > 0 || result.supportedMediaCount > 0 {
                showEmptyIntakeMessage(
                    result: result,
                    sourceURLs: sourceURLs,
                    retryContext: .intake(
                        urls: sourceURLs,
                        appendingExplicitFiles: appendingExplicitFiles,
                        isDragDrop: isDragDrop
                    )
                )
            } else if !emptyFolders.isEmpty {
                presentIntakeFailure(
                    .emptyFolders(names: emptyFolders),
                    sourceURLs: sourceURLs,
                    retryContext: .intake(
                        urls: sourceURLs,
                        appendingExplicitFiles: appendingExplicitFiles,
                        isDragDrop: isDragDrop
                    )
                )
            } else {
                presentIntakeFailure(
                    .unsupportedFiles(supportedExtensions: MediaFileSupport.supportedExtensions.sorted()),
                    sourceURLs: sourceURLs,
                    retryContext: .intake(
                        urls: sourceURLs,
                        appendingExplicitFiles: appendingExplicitFiles,
                        isDragDrop: isDragDrop
                    )
                )
            }
            return
        }

        clearIntakeRecovery()

        if !emptyFolders.isEmpty {
            DebugConsoleController.log("queue", "expand: skippedEmptyFolders=\(emptyFolders.count) finalCount=\(expanded.count)")
        } else {
            DebugConsoleController.log("queue", "expand: count=\(expanded.count)")
        }

        let queueWasEmpty = playbackSet.isEmpty || displayOrder.isEmpty
        let shuffleStartScope = prepareFolderDropShuffleIfNeeded(
            isDragDrop: isDragDrop,
            containsFolder: !dirs.isEmpty,
            addedPlayableMedia: true,
            queueWasEmpty: queueWasEmpty
        )
        let randomizeShuffleStart = shuffleStartScope != .none
        if appendingExplicitFiles {
            for dir in dirs { trackSourceFolder(dir) }
            appendToQueue(files: expanded, randomizeShuffleStart: randomizeShuffleStart)
        } else {
            sourceFolderURLs = dirs
            openAndPlay(set: expanded, randomizeShuffleStart: randomizeShuffleStart)
        }
        if randomizeShuffleStart {
            refreshQueueDisplays()
            logPlaybackQueueSnapshot("folderDropShuffle")
        }
        beginGIFIntakeProgress(for: expanded)
    }

    func handleDroppedURL(_ url: URL) {
        handleDroppedURLs([url], appendingExplicitFiles: true)
    }

    private func showEmptyIntakeMessage(result: MediaFileSupport.ExpansionResult,
                                        sourceURLs: [URL],
                                        retryContext: IntakeRecoveryRetryContext,
                                        emptyFolderNames: [String] = []) {
        if SettingsWindowController.acceptedMediaKinds().isEmpty {
            presentIntakeFailure(.mediaKindsDisabled, sourceURLs: sourceURLs, retryContext: retryContext)
            return
        }

        if result.excludedMediaCount > 0 {
            presentIntakeFailure(.mediaKindsDisabled, sourceURLs: sourceURLs, retryContext: retryContext)
            return
        }

        if !emptyFolderNames.isEmpty || !result.emptyFolderNames.isEmpty {
            presentIntakeFailure(
                .emptyFolders(names: emptyFolderNames.isEmpty ? result.emptyFolderNames : emptyFolderNames),
                sourceURLs: sourceURLs,
                retryContext: retryContext
            )
        } else {
            presentIntakeFailure(
                .unsupportedFiles(supportedExtensions: MediaFileSupport.supportedExtensions.sorted()),
                sourceURLs: sourceURLs,
                retryContext: retryContext
            )
        }
    }

    @discardableResult
    private func beginFolderScanOperation() -> UInt64 {
        folderScanTask?.cancel()
        folderScanGeneration &+= 1
        return folderScanGeneration
    }

    private func cancelPendingFolderScan() {
        folderScanTask?.cancel()
        folderScanTask = nil
        folderScanGeneration &+= 1
    }

    // MARK: - Sleep prevention

    private func acquirePlaybackSleepAssertion(reason: String) {
        guard playbackActivity == nil, !isWindowClosed else { return }
        playbackActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )
        NSLog("[dwb-power] sleep-assertion: acquired reason=%@", reason)
    }

    private func releasePlaybackSleepAssertion() {
        guard let token = playbackActivity else { return }
        ProcessInfo.processInfo.endActivity(token)
        playbackActivity = nil
        NSLog("[dwb-power] sleep-assertion: released")
    }

    // MARK: - Playback controls

    func togglePlayPause() {
        enqueuePlaybackCommand(named: "togglePlayPause") { [weak self] finish in
            guard let self = self else { finish(); return }

            // Queue ended naturally — restart from the first item in current display order.
            if self.queueEndedNaturally && !self.displayOrder.isEmpty {
                self.queueEndedNaturally = false
                self.currentDisplayIndex = 0
                DebugConsoleController.log("playback", "queue-restart: source=play-button items=\(self.displayOrder.count)")
                NSLog("[dwb-playback] queueRestart: source=play-button displayIdx=0/%d shuffle=%d endless=%d repeat=%d",
                      self.displayOrder.count,
                      self.isShuffleOn      ? 1 : 0,
                      self.isEndlessShuffleOn ? 1 : 0,
                      self.isRepeatOne      ? 1 : 0)
                self.playCurrentItem(startReason: "queue-restart",
                                     expectPlaybackHandshake: true,
                                     preserveCompletionSequence: false,
                                     transitionStrategy: .freshPlayer)
                finish()
                return
            }

            if self.currentItemIsImage {
                self.toggleImageSlideshowPause()
                finish()
                return
            }
            guard self.player.media != nil else { finish(); return }
            if self.player.isPlaying {
                self.explicitPlayPauseIntent = .init(target: .pause,
                                                      mediaURL: self.player.media?.url,
                                                      sessionID: self.currentPlaybackSessionID)
                DebugConsoleController.log("playback", "pause: source=button")
                self.player.pause()
            } else {
                self.explicitPlayPauseIntent = .init(target: .play,
                                                      mediaURL: self.player.media?.url,
                                                      sessionID: self.currentPlaybackSessionID)
                let hasPendingPausedNearEOFCompletion = self.activeCompletionSequence?.source == "paused-near-eof"
                if ExplicitPlayPauseCompletionPolicy.shouldCancelPendingPausedNearEOFCompletion(
                    for: .play,
                    naturalEOFDetected: self.naturalEOFDetected,
                    hasPendingPausedNearEOFCompletion: hasPendingPausedNearEOFCompletion
                ) {
                    self.cancelScheduledPlaybackAction(reason: "explicit-play-resume")
                    self.clearCompletionSequence(reason: "explicit-play-resume")
                }
                DebugConsoleController.log("playback", "play: source=button")
                // Resuming from pause keeps the audio output; any other state restarts it (P137).
                if self.player.state != .paused { self.audioReassertPending = true }
                self.player.play()
            }
            finish()
        }
    }

    private func toggleImageSlideshowPause() {
        let now = CACurrentMediaTime()
        if imageSlideshowPaused {
            imageSlideshowPaused = false
            imageSlideshowStartMT = now
            resumeGIFAnimationIfNeeded()
        } else {
            if imageSlideshowStartMT > 0 {
                imageSlideshowPauseAccumulated += now - imageSlideshowStartMT
            }
            imageSlideshowPaused = true
            pauseGIFAnimationIfNeeded()
        }
        transport.imageModeIsPlaying = !imageSlideshowPaused
        needsTransportUpdate = true
        NSLog("[dwb-image] pause-toggle: paused=%d elapsed=%.2f", imageSlideshowPaused ? 1 : 0,
              imageSlideshowPauseAccumulated)
        DebugConsoleController.log("image", imageSlideshowPaused ? "paused" : "resumed")
    }

    private func startAnimatedGIFPlayback(url: URL) {
        guard let animation = MediaFileSupport.loadGIFAnimation(for: url) else {
            NSLog("[dwb-gif] animation-load-failed: %@", url.lastPathComponent)
            DebugConsoleController.log(level: .error, category: "media", message: "gif animation load failed: \(url.lastPathComponent)")
            if let fallbackImage = NSImage(contentsOf: url) {
                imageDisplayView?.animates = false
                imageDisplayView?.image = fallbackImage
            } else {
                imageDisplayView?.image = nil
            }
            currentGIFAnimation = nil
            gifFrameTimer?.invalidate()
            gifFrameTimer = nil
            return
        }

        currentGIFAnimation = animation
        gifFrameTimer?.invalidate()
        gifFrameTimer = nil
        gifCurrentFrameIndex = 0
        gifCurrentFrameStartedMT = CACurrentMediaTime()
        gifCurrentFrameRemainingDelay = animation.frameDurations[0]
        imageDisplayView?.animates = false
        let firstFrame = animation.frames[0]
        imageDisplayView?.image = NSImage(cgImage: firstFrame,
                                          size: NSSize(width: firstFrame.width, height: firstFrame.height))
        scheduleNextGIFFrame(after: animation.frameDurations[0])
    }

    private func scheduleNextGIFFrame(after delay: TimeInterval) {
        gifFrameTimer?.invalidate()
        guard currentItemIsGIF, !imageSlideshowPaused else {
            gifCurrentFrameRemainingDelay = delay
            return
        }
        let safeDelay = max(0.02, delay)
        gifCurrentFrameRemainingDelay = safeDelay
        gifCurrentFrameStartedMT = CACurrentMediaTime()
        gifFrameTimer = Timer.scheduledTimer(withTimeInterval: safeDelay, repeats: false) { [weak self] _ in
            self?.advanceGIFFrame()
        }
    }

    private func advanceGIFFrame() {
        guard currentItemIsGIF,
              !imageSlideshowPaused,
              let animation = currentGIFAnimation,
              !animation.frames.isEmpty else { return }

        gifCurrentFrameIndex = (gifCurrentFrameIndex + 1) % animation.frames.count
        let frame = animation.frames[gifCurrentFrameIndex]
        imageDisplayView?.image = NSImage(cgImage: frame,
                                          size: NSSize(width: frame.width, height: frame.height))
        let nextDelay = animation.frameDurations[gifCurrentFrameIndex]
        scheduleNextGIFFrame(after: nextDelay)
    }

    private func pauseGIFAnimationIfNeeded() {
        guard currentItemIsGIF else { return }
        if gifCurrentFrameStartedMT > 0, gifCurrentFrameRemainingDelay > 0 {
            let elapsed = CACurrentMediaTime() - gifCurrentFrameStartedMT
            gifCurrentFrameRemainingDelay = max(0.001, gifCurrentFrameRemainingDelay - elapsed)
        }
        gifFrameTimer?.invalidate()
        gifFrameTimer = nil
    }

    private func resumeGIFAnimationIfNeeded() {
        guard currentItemIsGIF else { return }
        let delay: TimeInterval
        if gifCurrentFrameRemainingDelay > 0 {
            delay = gifCurrentFrameRemainingDelay
        } else if let animation = currentGIFAnimation,
                  gifCurrentFrameIndex >= 0,
                  gifCurrentFrameIndex < animation.frameDurations.count {
            delay = animation.frameDurations[gifCurrentFrameIndex]
        } else {
            delay = 0.1
        }
        scheduleNextGIFFrame(after: delay)
    }

    func stopPlayback() {
        DebugConsoleController.log("playback", "stop: source=user")
        enqueueStopPlaybackCommand(reason: "user-stop")
    }

    /// Called by TransportControlsView and internal seek methods whenever a user-initiated
    /// seek is committed. Resets lastKnownPosition so a stale near-end position captured
    /// before the seek doesn't falsely qualify as natural-EOF position evidence.
    /// Sets lastUserSeekDate so the .stopped handler knows to distrust position heuristics
    /// for the next 1.5 s (require naturalEOFDetected instead).
    func notifyUserSeek(targetPosition: Float? = nil, source: String) {
        lastUserSeekMT    = CACurrentMediaTime()   // M1
        lastKnownPosition = 0
        let target = targetPosition ?? -1
        NSLog("[dwb-playback] notifyUserSeek: source=%@ current=%.3f target=%.3f — lastKnownPosition reset, seek guard active",
              source, player?.position ?? 0, target)
    }

    func clampedUserSeekPosition(_ rawPosition: Float, source: String) -> Float {
        guard rawPosition.isFinite else { return 0 }
        let bounded = max(0, min(1, rawPosition))
        let clamped = min(bounded, maxUserSeekPosition)
        if clamped != bounded {
            NSLog("[dwb-playback] seekClamp: source=%@ requested=%.3f clamped=%.3f maxUserSeek=%.3f",
                  source, bounded, clamped, maxUserSeekPosition)
        }
        return clamped
    }

    func skipBackward10() {
        skipByConfiguredDuration(isForward: false)
    }

    func skipForward10() {
        skipByConfiguredDuration(isForward: true)
    }

    private func skipByConfiguredDuration(isForward: Bool) {
        guard let media = player.media else { return }
        let durationMs = max(Int(media.length.intValue), lastKnownDurationMs)
        guard durationMs > 0 else { return }

        let baseMs = currentSeekBaseTimeMs(durationMs: durationMs)
        let stepMs = configuredSkipDurationMs
        let source = isForward ? "skipForward" : "skipBackward"

        let targetMs: Int
        let rule: String
        if isForward {
            let remainingMs = max(0, durationMs - baseMs)
            if remainingMs > stepMs {
                targetMs = min(durationMs, baseMs + stepMs)
                rule = "exact-forward"
            } else {
                targetMs = safePreEOFTargetTimeMs(durationMs: durationMs, baseMs: baseMs)
                rule = targetMs > baseMs ? "clamp-safe-pre-eof" : "already-near-eof"
            }
        } else {
            targetMs = max(0, baseMs - stepMs)
            rule = "exact-backward"
        }

        seekPlayer(toTimeMs: targetMs,
                   durationMs: durationMs,
                   baseTimeMs: baseMs,
                   source: source,
                   requestedSkipMs: stepMs,
                   rule: rule)
        resetSeekTargetAfterDelay()
    }

    private func currentSeekBaseTimeMs(durationMs: Int) -> Int {
        if let pending = seekTargetMs {
            return max(0, min(durationMs, pending))
        }

        let timeMs = Int(player.time.intValue)
        if timeMs > 0 {
            return max(0, min(durationMs, timeMs))
        }

        let position = player.position
        if position.isFinite, position > 0 {
            let estimatedMs = Int((Double(position) * Double(durationMs)).rounded())
            return max(0, min(durationMs, estimatedMs))
        }

        return 0
    }

    private func safePreEOFTargetTimeMs(durationMs: Int, baseMs: Int) -> Int {
        let safePositionMs = Int((Double(durationMs) * Double(maxUserSeekPosition)).rounded(.down))
        return max(baseMs, min(durationMs, safePositionMs))
    }

    private func seekPlayer(toTimeMs targetMs: Int,
                            durationMs: Int,
                            baseTimeMs: Int,
                            source: String,
                            requestedSkipMs: Int,
                            rule: String) {
        let safeTargetMs = max(0, min(durationMs, targetMs))
        let targetPosition = durationMs > 0
            ? max(0, min(1, Float(safeTargetMs) / Float(durationMs)))
            : 0
        let targetTime = VLCTime(int: Int32(min(safeTargetMs, Int(Int32.max))))
        seekTargetMs = safeTargetMs
        NSLog("[dwb-playback] %@: base=%dms target=%dms pos=%.3f dur=%dms step=%dms rule=%@",
              source,
              baseTimeMs,
              safeTargetMs,
              targetPosition,
              durationMs,
              requestedSkipMs,
              rule)
        notifyUserSeek(targetPosition: targetPosition, source: source)
        player.time = targetTime
        transport.notifySeek(to: targetPosition)
    }

    private func resetSeekTargetAfterDelay() {
        seekTargetResetTimer?.invalidate()
        seekTargetResetTimer = Timer.scheduledTimer(withTimeInterval: 0.5,
                                                    repeats: false) { [weak self] _ in
            self?.seekTargetMs = nil
        }
    }

    private func clearPlaybackCompletionEvidence() {
        naturalEOFDetected = false
        lastKnownPosition = 0
        lastKnownTimeMs = 0
        lastKnownDurationMs = 0
        positionAtEndedEvent = 0
        lastUserSeekMT = 0
        lastPlayingMT = 0
        lastProgressMT = 0
        midPlaybackStallClock.reset()
        lastStoppedMT = 0
        lastStoppedPosition = 0
        lastStoppedMediaURL = nil
        explicitPlayPauseIntent = nil
    }

    private func clearStoppedSuppression() {
        suppressNextStopped = false
        suppressNextStoppedMT = 0
    }

    private func clearCompletionSequence(reason: String, suppressLog: Bool = false) {
        guard let sequence = activeCompletionSequence else { return }
        if !suppressLog {
            NSLog("[dwb-playback] completionSequenceClear: seq=%d action=%@ reason=%@",
                  sequence.id, sequence.action.rawValue, reason)
        }
        activeCompletionSequence = nil
    }

    private func resetPlaybackCompletionSignals(reason: String,
                                               preserveCompletionSequence: Bool = false) {
        cancelScheduledPlaybackAction(reason: reason)
        cancelPlaybackFailureAutoSkip(reason: reason)
        clearPlaybackCompletionEvidence()
        clearStoppedSuppression()
        cancelReplacementStart(reason: reason)
        cancelPlaybackStartHandshake(reason: reason)
        if !preserveCompletionSequence {
            clearCompletionSequence(reason: reason, suppressLog: true)
        }
    }

    private func enqueuePlaybackCommand(named name: String,
                                        action: @escaping PlaybackCommandAction) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.enqueuePlaybackCommand(named: name, action: action)
            }
            return
        }
        guard !isWindowClosed else {
            NSLog("[dwb-playback] commandDropped: name=%@ reason=window-closed", name)
            return
        }

        playbackCommandSequence += 1
        let command = QueuedPlaybackCommand(id: playbackCommandSequence,
                                            name: name,
                                            action: action)
        queuedPlaybackCommands.append(command)
        NSLog("[dwb-playback] commandEnqueue: id=%d name=%@ queued=%d",
              command.id,
              command.name,
              queuedPlaybackCommands.count)
        runNextPlaybackCommandIfNeeded()
    }

    private func runNextPlaybackCommandIfNeeded() {
        guard !isExecutingPlaybackCommand, !queuedPlaybackCommands.isEmpty else { return }
        let command = queuedPlaybackCommands.removeFirst()
        isExecutingPlaybackCommand = true
        NSLog("[dwb-playback] commandStart: id=%d name=%@ remaining=%d",
              command.id,
              command.name,
              queuedPlaybackCommands.count)
        command.action { [weak self] in
            guard let self = self else { return }
            self.isExecutingPlaybackCommand = false
            NSLog("[dwb-playback] commandFinish: id=%d name=%@ pending=%d",
                  command.id,
                  command.name,
                  self.queuedPlaybackCommands.count)
            self.runNextPlaybackCommandIfNeeded()
        }
    }

    private func enqueueStopPlaybackCommand(reason: String) {
        enqueuePlaybackCommand(named: "stop-\(reason)") { [weak self] finish in
            self?.executeStopPlayback(reason: reason)
            finish()
        }
    }

    private func executeStopPlayback(reason: String) {
        resetPlaybackCompletionSignals(reason: reason)
        queuedPlaybackCommands.removeAll()
        isUserStop = true
        queueEndedNaturally = false
        seekTargetMs = nil
        seekTargetResetTimer?.invalidate()
        NSLog("[dwb-playback] stopPlayback: reason=%@ userStop=1 cancelPendingAutoplay=1", reason)
        if currentItemIsImage {
            clearImageSlideshowState()
        } else {
            player.stop()
        }
        if reason == "user-stop" {
            openQueuePageAfterUserStop()
        } else {
            transport.update()
        }
    }

    private func openQueuePageAfterUserStop() {
        isQueuePageOpen = true
        refreshQueuePageNow()
        layoutPlayerViews()
        transport.update()
    }

    private func executePlayCurrentItem(startReason: String,
                                        expectPlaybackHandshake: Bool,
                                        preserveCompletionSequence: Bool,
                                        transitionStrategy: PlaybackTransitionStrategy) {
        let idx = currentSetIndex
        guard idx >= 0, idx < playbackSet.count else {
            NSLog("[dwb-playback] playCurrentItem: reason=%@ ignored-invalid-index displayIdx=%d/%d",
                  startReason,
                  currentDisplayIndex,
                  displayOrder.count)
            return
        }

        let url = playbackSet[idx]
        // A fresh attempt clears the earlier failure mark; a new failure sets it again.
        if failedPlaybackPaths.remove(url.standardizedFileURL.path) != nil { refreshQueuePage() }
        PlayNextChainPolicy.onPlaybackStarted(
            currentSetIndex: idx,
            displayOrder: displayOrder,
            currentDisplayIndex: currentDisplayIndex,
            pendingSetIndices: &pendingPlayNextSetIndices
        )
        let hadExistingMedia = player.media != nil
        seekTargetMs = nil
        seekTargetResetTimer?.invalidate()
        currentPlaybackSessionID += 1
        queueEndedNaturally = false
        resetPlaybackCompletionSignals(reason: "playCurrentItem-\(startReason)",
                                       preserveCompletionSequence: preserveCompletionSequence)

        NSLog("[dwb-playback] playCurrentItem: reason=%@ displayIdx=%d/%d url=%@ mediaWasNonNil=%d expectHandshake=%d preserveCompletion=%d session=%d transition=%@",
              startReason,
              currentDisplayIndex,
              displayOrder.count,
              url.lastPathComponent,
              hadExistingMedia ? 1 : 0,
              expectPlaybackHandshake ? 1 : 0,
              preserveCompletionSequence ? 1 : 0,
              currentPlaybackSessionID,
              transitionStrategy.rawValue)

        currentMediaURL = url
        currentItemVolumeKind = VolumeClassifier.shared.kind(for: url)
        if currentItemVolumeKind == .nonLocal {
            nonLocalFiles.request([url])   // rename availability; read off the main thread
        }

        if MediaFileSupport.isImage(url) {
            // Image path — synchronous setup, no VLC involvement.
            let imageMetadata = configuredImageDurationMetadata(for: url)
            let playbackDuration = imageMetadata.seconds ?? 0
            let kind = MediaFileSupport.isGIF(url) ? "gif" : "image"
            DebugConsoleController.log("media",
                                       "\(kind)Start: \(url.lastPathComponent) dur=\(imageMetadata.displayString) reason=\(startReason)")
            currentDurationIsProvisional = false
            updateDurationCache(for: url, metadata: imageMetadata)
            logPlaybackQueueSnapshot("playCurrentItem")
            updateWindowTitle(url.lastPathComponent)
            if configuredShowTitleOverlay { showVideoTitleOverlay(title: url.lastPathComponent) }
            transport.invalidateCachedDisplayState()
            if isQueuePageOpen { refreshQueuePage() }
            // Stop VLC if it was carrying media (video→image transition).
            if player.media != nil {
                suppressNextStopped = true
                suppressNextStoppedMT = CACurrentMediaTime()
                cancelReplacementStart(reason: "image-\(startReason)")
                cancelPlaybackStartHandshake(reason: "image-\(startReason)")
                player.stop()
            }
            startImageDisplayAndTimer(url: url, playbackDuration: playbackDuration)
            clearCompletionSequence(reason: "image-start")
            return
        }

        // Video path — clear any active image state then use VLC.
        DebugConsoleController.log("media", "videoStart: window=\(debugIdentity) file=\(url.lastPathComponent) session=\(currentPlaybackSessionID) reason=\(startReason) audio=\(audioStateDescription)")
        clearImageSlideshowState()

        let cachedDuration = durationCache[url]
        // A non-local `.mpg` skips the stable-duration loader (P142.1): its duration comes from
        // the length VLC reports, like any other non-local file.
        currentDurationIsProvisional = MediaFileSupport.needsStableDuration(url) &&
            mayStartDurationProbe(for: url, volume: currentItemVolumeKind) &&
            (cachedDuration == nil || cachedDuration == MediaFileSupport.durationLoadingText)
        if currentDurationIsProvisional {
            durationCache[url] = MediaFileSupport.durationLoadingText
            MediaFileSupport.loadDurationMetadata(for: url) { [weak self] metadata in
                guard let self = self else { return }
                self.updateDurationCache(for: url, metadata: metadata)
                if self.currentMediaURL == url {
                    self.currentDurationIsProvisional = false
                    self.transport.update()
                }
                if self.queueSortMode == .durationAscending || self.queueSortMode == .durationDescending {
                    self.applyQueueSortIfNeeded(reason: "current-duration-update")
                } else if self.isQueuePageOpen {
                    self.refreshQueuePage()
                }
            }
        }

        logPlaybackQueueSnapshot("playCurrentItem")
        updateWindowTitle(url.lastPathComponent)
        if configuredShowTitleOverlay { showVideoTitleOverlay(title: url.lastPathComponent) }
        transport.invalidateCachedDisplayState()  // media replaced — force full refresh
        transport.update()
        if isQueuePageOpen { refreshQueuePage() }

        switch transitionStrategy {
        case .freshPlayer:
            startPlaybackWithFreshPlayer(url: url,
                                         startReason: startReason,
                                         sessionID: currentPlaybackSessionID,
                                         expectPlaybackHandshake: expectPlaybackHandshake)
        case .reuseCurrentPlayer:
            scheduleReplacementStart(url: url,
                                     startReason: startReason,
                                     sessionID: currentPlaybackSessionID,
                                     expectPlaybackHandshake: expectPlaybackHandshake,
                                     transitionStrategy: transitionStrategy,
                                     after: hadExistingMedia ? replacementStartDelay : 0)
        }
    }

    // MARK: - Image slideshow

    private func startImageDisplayAndTimer(url: URL, playbackDuration: TimeInterval) {
        isUserStop = false
        currentItemIsImage = true
        currentItemIsGIF = MediaFileSupport.isGIF(url)
        imageSlideshowStartMT = CACurrentMediaTime()
        imageSlideshowPauseAccumulated = 0
        imageSlideshowPaused = false
        currentImagePlaybackDurationSeconds = playbackDuration

        if currentItemIsGIF {
            startAnimatedGIFPlayback(url: url)
        } else {
            guard let image = NSImage(contentsOf: url) else {
                NSLog("[dwb-image] load-failed: %@", url.lastPathComponent)
                DebugConsoleController.log(level: .error, category: "error", message: "image load failed: \(url.lastPathComponent)")
                clearImageSlideshowState()
                schedulePlaybackFailureAutoSkip(failedURL: url,
                                                failedSessionID: currentPlaybackSessionID,
                                                source: "image-load")
                return
            }
            gifFrameTimer?.invalidate()
            gifFrameTimer = nil
            currentGIFAnimation = nil
            imageDisplayView?.animates = false
            imageDisplayView?.image = image
        }

        imageDisplayView?.isHidden = false
        videoSurface.isHidden = true

        transport.isImageMode = true
        transport.isGIFMode = currentItemIsGIF
        transport.imageModeElapsed = 0
        transport.imageModeDuration = playbackDuration
        transport.imageModeIsPlaying = true
        transport.invalidateCachedDisplayState()
        needsTransportUpdate = true
        transport.update()

        NSLog("[dwb-image] started: url=%@ duration=%.3fs gif=%d",
              url.lastPathComponent,
              playbackDuration,
              currentItemIsGIF ? 1 : 0)
        DebugConsoleController.log("image",
                                   "start: \(url.lastPathComponent) dur=\(MediaFileSupport.formatPlaybackDuration(playbackDuration)) gif=\(currentItemIsGIF)")
    }

    private func clearImageSlideshowState() {
        guard currentItemIsImage else { return }
        gifFrameTimer?.invalidate()
        gifFrameTimer = nil
        currentGIFAnimation = nil
        gifCurrentFrameIndex = 0
        gifCurrentFrameStartedMT = 0
        gifCurrentFrameRemainingDelay = 0
        currentItemIsImage = false
        currentItemIsGIF = false
        imageSlideshowStartMT = 0
        imageSlideshowPauseAccumulated = 0
        imageSlideshowPaused = false
        currentImagePlaybackDurationSeconds = 0
        imageDisplayView?.isHidden = true
        imageDisplayView?.image = nil
        imageDisplayView?.animates = false
        videoSurface.isHidden = false
        transport.isImageMode = false
        transport.isGIFMode = false
        transport.invalidateCachedDisplayState()
        NSLog("[dwb-image] cleared")
    }

    private func cancelScheduledPlaybackAction(reason: String) {
        guard scheduledPlaybackAction != nil else { return }
        NSLog("[dwb-playback] autoplayCancel: reason=%@", reason)
        scheduledPlaybackAction?.cancel()
        scheduledPlaybackAction = nil
    }

    private func schedulePlaybackAction(named name: String,
                                        after delay: TimeInterval,
                                        action: @escaping () -> Void) {
        cancelScheduledPlaybackAction(reason: "reschedule-\(name)")
        guard !isWindowClosed else { return }
        NSLog("[dwb-playback] autoplaySchedule: action=%@ delay=%.2fs", name, delay)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.scheduledPlaybackAction = nil
            NSLog("[dwb-playback] autoplayExecute: action=%@", name)
            action()
        }
        scheduledPlaybackAction = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPlaybackFailureAutoSkip(reason: String) {
        guard activePlaybackFailureAttempt != nil else { return }
        NSLog("[dwb-playback] failureAutoSkipCancel: reason=%@", reason)
        activePlaybackFailureAttempt = nil
    }

    /// Advances a confirmed failed item through the normal queue/start path.
    /// This is intentionally separate from completion policy: an error must never
    /// trigger Repeat One or immediately retry a one-item Endless Shuffle queue.
    /// `detail` is logged to the Debug Console (warning) only when the failure is handled,
    /// so a repeating watchdog on an already-handled item cannot flood the log.
    private func schedulePlaybackFailureAutoSkip(failedURL: URL,
                                                 failedSessionID: Int,
                                                 source: String,
                                                 detail: String? = nil) {
        let attempt = PlaybackFailureAttempt(mediaURL: failedURL, sessionID: failedSessionID)
        let action = PlaybackFailureAdvancePolicy(
            currentDisplayIndex: currentDisplayIndex,
            displayOrderCount: displayOrder.count,
            isEndlessShuffleOn: isEndlessShuffleOn
        ).action
        let disposition = PlaybackFailureAdvancePolicy.disposition(
            failedAttempt: attempt,
            currentURL: currentMediaURL,
            currentSessionID: currentPlaybackSessionID,
            isUserStop: isUserStop,
            naturalEOFDetected: naturalEOFDetected,
            activeFailureAttempt: activePlaybackFailureAttempt,
            action: action
        )
        guard currentSetIndex >= 0,
              currentSetIndex < playbackSet.count,
              playbackSet[currentSetIndex].standardizedFileURL.path == failedURL.standardizedFileURL.path else {
            NSLog("[dwb-playback] failureAutoSkip: ignored source=%@ media=%@ session=%d reason=queue-identity-mismatch",
                  source, failedURL.lastPathComponent, failedSessionID)
            return
        }

        switch disposition {
        case .ignoreStaleOrUserStop:
            NSLog("[dwb-playback] failureAutoSkip: ignored source=%@ media=%@ session=%d reason=stale-or-user-stop",
                  source, failedURL.lastPathComponent, failedSessionID)
            return
        case .ignoreDuplicate:
            NSLog("[dwb-playback] failureAutoSkip: ignored source=%@ media=%@ session=%d reason=duplicate-attempt",
                  source, failedURL.lastPathComponent, failedSessionID)
            return
        case .handle:
            break
        }

        resetPlaybackCompletionSignals(reason: "playback-failure-\(source)")
        activePlaybackFailureAttempt = attempt
        failedPlaybackPaths.insert(failedURL.standardizedFileURL.path)
        refreshQueuePage()
        let filename = failedURL.lastPathComponent
        // P142: a start failure or stall on a non-local volume stops here instead of skipping on
        // to the next file on the same volume. Other sources behave as before.
        let stopsHere = PlaybackStartFailureSource(rawValue: source) != nil
            && PlaybackStartWindowPolicy.failureDecision(volume: VolumeClassifier.shared.kind(for: failedURL)) == .failAndStop
        if let detail {
            DebugConsoleController.log(level: .warning, category: "playback", message: detail)
        }
        DebugConsoleController.log(level: .error,
                                   category: "playback",
                                   message: "failure: \(filename) source=\(source) action=\(stopsHere ? .stopAtEnd : action)")
        NSLog("[dwb-playback] failureAutoSkip: source=%@ media=%@ session=%d action=%@ schedule=immediate",
              source, filename, failedSessionID, String(describing: stopsHere ? .stopAtEnd : action))

        if stopsHere {
            DebugConsoleController.log("volume", "no auto-skip: \(filename) source=\(source)")
            showPlaybackFailureOverlay(filename: filename)
            return
        }

        guard action == .skipToNextDistinctItem else {
            NSLog("[dwb-playback] failureAutoSkip: no-distinct-successor media=%@", filename)
            showPlaybackFailureOverlay(filename: filename)
            return
        }

        let advanced = advanceToNextItem(reason: "playback-failure-\(source)",
                                         expectPlaybackHandshake: true,
                                         transitionStrategy: .reuseCurrentPlayer)
        // Shown after advanceToNextItem (which starts the successor and sets its own
        // title overlay) so the failure message is the one left visible, rather than
        // being clobbered immediately by the successor's now-playing overlay.
        showPlaybackFailureOverlay(filename: filename)
        NSLog("[dwb-playback] failureAutoSkip: execute media=%@ advanced=%d",
              failedURL.lastPathComponent, advanced ? 1 : 0)
    }

    /// Non-blocking, non-modal failure message in the design system's failure
    /// style, held for 3 s. Purely cosmetic: never gates, delays, or is required
    /// by advancement.
    private func showPlaybackFailureOverlay(filename: String) {
        failureMessageView.present(filename: filename)
        positionFailureMessage()
    }

    private func cancelReplacementStart(reason: String, suppressLog: Bool = false) {
        let hadPending = replacementStartWorkItem != nil
        replacementStartWorkItem?.cancel()
        replacementStartWorkItem = nil
        if hadPending && !suppressLog {
            NSLog("[dwb-playback] replacementStartCancel: reason=%@", reason)
        }
    }

    private func scheduleReplacementStart(url: URL,
                                          startReason: String,
                                          sessionID: Int,
                                          expectPlaybackHandshake: Bool,
                                          transitionStrategy: PlaybackTransitionStrategy,
                                          after delay: TimeInterval) {
        cancelReplacementStart(reason: "reschedule-\(startReason)", suppressLog: true)
        replacementStartSequence += 1
        let sequence = replacementStartSequence
        if player.media != nil {
            suppressNextStopped = true
            suppressNextStoppedMT = CACurrentMediaTime()   // M1
            NSLog("[dwb-playback] playCurrentItem: suppressNextStopped=1 (replacing existing media)")
            NSLog("[dwb-playback] playCurrentItem: replacementTeardown explicitStop=1 oldMedia=%@ oldState=%d delay=%.2fs",
                  player.media?.url?.lastPathComponent ?? "—",
                  player.state.rawValue,
                  delay)
            player.stop()
        } else {
            NSLog("[dwb-playback] playCurrentItem: replacementTeardown explicitStop=0 oldMedia=%@ oldState=%d delay=0.00s",
                  "—",
                  player.state.rawValue)
        }
        NSLog("[dwb-playback] replacementStartSchedule: id=%d reason=%@ delay=%.2fs targetMedia=%@ transition=%@",
              sequence,
              startReason,
              delay,
              url.lastPathComponent,
              transitionStrategy.rawValue)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.replacementStartSequence == sequence else { return }
            self.replacementStartWorkItem = nil
            let replacementBeginT = CACurrentMediaTime()
            NSLog("[dwb-playback] replacementStart: BEGIN id=%d reason=%@ media=%@ transition=%@ window=%@",
                  sequence,
                  startReason,
                  url.lastPathComponent,
                  transitionStrategy.rawValue,
                  self.debugIdentity)
            NSLog("[dwb-playback] playCurrentItem: replacementStartExecute id=%d reason=%@ media=%@ transition=%@",
                  sequence,
                  startReason,
                  url.lastPathComponent,
                  transitionStrategy.rawValue)
            NSLog("[dwb-playback] playCurrentItem: before player.media = %@ reason=%@ currentState=%d oldMedia=%@",
                  url.lastPathComponent,
                  startReason,
                  self.player.state.rawValue,
                  self.player.media?.url?.lastPathComponent ?? "—")
            // P24: Reassert drawable and invalidate scale cache on the reuse path.
            // Prevents black-screen or stale-crop when VLC drops the drawable after stop()
            // or when an image→video transition left the surface in a detached state.
            self.player.drawable = self.videoSurface
            self.lastAppliedScaleState = nil
            self.applyScaleMode()
            let media = VLCMedia.forPlayback(url: url, site: .reuse)
            self.player.media = media
            self.applyPlaybackSpeed(reason: "reuse-player-media-replacement")
            // P50: Do NOT write the volume here, and never use force:true. This runs right after
            // player.stop(); calling config_PutInt (via audio.volume=) on the main thread at that
            // point acquires a global rwlock write lock that blocks on any active VLCKit reader
            // thread, causing a process-wide main-thread hang across all windows.
            // P137: skipping is not enough on its own. VLC's volume state is shared by every
            // player in the process, so the audio output created by play() below can start at
            // another window's value that this window's cache knows nothing about. The window
            // arms audioReassertPending instead; reassertWindowAudioIfNeeded compares VLC's
            // actual volume with this window's at `.playing` (when the output is up) and writes
            // only if they differ.
            let appliedAudio = self.applyWindowAudioState(reason: "reuse-player-media-replacement")
            // Unlike volume, the delay is reapplied unconditionally (force: true) on every
            // media swap: currentAudioPlaybackDelay is tied to VLC's audio track/demux state,
            // which the reused player replaces along with the media, not to global config.
            self.applyAudioDelay(reason: "reuse-player-media-replacement", force: true)
            NSLog("[dwb-playback] playCurrentItem: assignedMedia=%@ reason=%@ restoredVolume=%d",
                  url.lastPathComponent,
                  startReason,
                  appliedAudio.volume)
            if expectPlaybackHandshake {
                self.armPlaybackStartHandshake(reason: startReason,
                                               expectedURL: url,
                                               expectedSessionID: sessionID,
                                               transitionStrategy: transitionStrategy)
            } else {
                self.cancelPlaybackStartHandshake(reason: "playCurrentItem-\(startReason)-no-handshake")
            }
            NSLog("[dwb-playback] playCurrentItem: before player.play() reason=%@ state=%d media=%@",
                  startReason,
                  self.player.state.rawValue,
                  self.player.media?.url?.lastPathComponent ?? "—")
            self.audioReassertPending = true
            self.player.play()
            NSLog("[dwb-playback] playCurrentItem: after player.play() reason=%@ state=%d isPlaying=%d media=%@",
                  startReason,
                  self.player.state.rawValue,
                  self.player.isPlaying ? 1 : 0,
                  self.player.media?.url?.lastPathComponent ?? "—")
            let replacementElapsedMs = Int((CACurrentMediaTime() - replacementBeginT) * 1000)
            NSLog("[dwb-playback] replacementStart: END id=%d reason=%@ media=%@ elapsedMs=%d window=%@",
                  sequence,
                  startReason,
                  url.lastPathComponent,
                  replacementElapsedMs,
                  self.debugIdentity)
        }

        replacementStartWorkItem = workItem
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            workItem.perform()
        }
    }

    private func armPlaybackStartHandshake(reason: String,
                                           expectedURL: URL,
                                           expectedSessionID: Int,
                                           transitionStrategy: PlaybackTransitionStrategy) {
        cancelPlaybackStartHandshake(reason: "rearm-\(reason)")
        playbackStartHandshakeSequence += 1
        let handshake = PlaybackStartHandshake(id: playbackStartHandshakeSequence,
                                               reason: reason,
                                               expectedURL: expectedURL,
                                               expectedSessionID: expectedSessionID,
                                               transitionStrategy: transitionStrategy,
                                               baselinePosition: player.position,
                                               baselineTimeMs: Int(player.time.intValue),
                                               playRetryCount: 0,
                                               progressRetryCount: 0,
                                               sawPlaying: false,
                                               recoveryUsed: false,
                                               volume: VolumeClassifier.shared.kind(for: expectedURL),
                                               windowStartMT: CACurrentMediaTime())
        playbackStartHandshake = handshake
        NSLog("[dwb-playback] handshakeArm: id=%d reason=%@ expectedMedia=%@ session=%d transition=%@ baselineTimeMs=%d baselinePos=%.3f",
              handshake.id,
              reason,
              expectedURL.lastPathComponent,
              expectedSessionID,
              transitionStrategy.rawValue,
              handshake.baselineTimeMs,
              handshake.baselinePosition)
        schedulePlaybackStartHandshakeCheck(for: handshake.id)
    }

    private func cancelPlaybackStartHandshake(reason: String, suppressLog: Bool = false) {
        let hadHandshake = playbackStartHandshake != nil || playbackStartHandshakeWorkItem != nil
        playbackStartHandshakeWorkItem?.cancel()
        playbackStartHandshakeWorkItem = nil
        playbackStartHandshake = nil
        if hadHandshake && !suppressLog {
            NSLog("[dwb-playback] handshakeCancel: reason=%@", reason)
        }
    }

    private func schedulePlaybackStartHandshakeCheck(for id: Int) {
        playbackStartHandshakeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.verifyPlaybackStartHandshake(id: id)
        }
        playbackStartHandshakeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + playbackStartCheckInterval, execute: workItem)
    }

    private func verifyPlaybackStartHandshake(id: Int) {
        guard var handshake = playbackStartHandshake, handshake.id == id else { return }
        playbackStartHandshakeWorkItem = nil

        let currentMediaURL = player.media?.url
        let mediaAssigned = currentMediaURL?.path == handshake.expectedURL.path
        let currentMediaName = currentMediaURL?.lastPathComponent ?? "—"
        let stateRaw = player.state.rawValue
        let started = player.isPlaying || player.state == .playing
        let timeMs = Int(player.time.intValue)
        let position = player.position
        let progressConfirmed = playbackProgressConfirmed(for: handshake,
                                                          currentTimeMs: timeMs,
                                                          currentPosition: position)

        NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ mediaAssigned=%d state=%d isPlaying=%d sawPlaying=%d playRetry=%d progressRetry=%d recovery=%d currentMedia=%@ timeMs=%d pos=%.3f progress=%d session=%d/%d transition=%@",
              handshake.id,
              handshake.reason,
              mediaAssigned ? 1 : 0,
              stateRaw,
              started ? 1 : 0,
              handshake.sawPlaying ? 1 : 0,
              handshake.playRetryCount,
              handshake.progressRetryCount,
              handshake.recoveryUsed ? 1 : 0,
              currentMediaName,
              timeMs,
              position,
              progressConfirmed ? 1 : 0,
              currentPlaybackSessionID,
              handshake.expectedSessionID,
              handshake.transitionStrategy.rawValue)

        guard currentPlaybackSessionID == handshake.expectedSessionID else {
            NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ session moved on — abandoning",
                  handshake.id, handshake.reason)
            cancelPlaybackStartHandshake(reason: "session-moved", suppressLog: true)
            clearCompletionSequence(reason: "handshake-session-moved", suppressLog: true)
            return
        }

        guard mediaAssigned else {
            let stillCurrentAttempt = currentPlaybackSessionID == handshake.expectedSessionID
                && self.currentMediaURL?.standardizedFileURL.path == handshake.expectedURL.standardizedFileURL.path
            if stillCurrentAttempt {
                NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ final=failure target=%@ failure=media-cleared-before-start",
                      handshake.id,
                      handshake.reason,
                      handshake.expectedURL.lastPathComponent)
                cancelPlaybackStartHandshake(reason: "media-cleared-before-start", suppressLog: true)
                schedulePlaybackFailureAutoSkip(failedURL: handshake.expectedURL,
                                                failedSessionID: handshake.expectedSessionID,
                                                source: "handshake-media-cleared")
            } else {
                NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ media changed before start — abandoning",
                      handshake.id, handshake.reason)
                cancelPlaybackStartHandshake(reason: "media-changed", suppressLog: true)
                clearCompletionSequence(reason: "handshake-media-changed", suppressLog: true)
            }
            return
        }

        if started && !handshake.sawPlaying {
            handshake.sawPlaying = true
            // Reset the progress baseline to the position/time observed right now, at the
            // moment this specific media is first confirmed playing. The baseline captured
            // at arm-time (armPlaybackStartHandshake) can still reflect the *previous* item's
            // leftover position/time on a reuseCurrentPlayer transition, since VLCKit does not
            // guarantee player.position/time are reset synchronously the instant new media is
            // assigned. A stale non-zero baseline (e.g. near 1.0 after the prior item played to
            // completion) can make playbackProgressConfirmed() nearly impossible to satisfy for
            // a perfectly valid new item, wrongly classifying it as failed (handshake-no-progress).
            handshake.baselinePosition = position
            handshake.baselineTimeMs = timeMs
            playbackStartHandshake = handshake
            NSLog("[dwb-playback] handshakeFirstPlaying: id=%d reason=%@ media=%@ transition=%@",
                  handshake.id,
                  handshake.reason,
                  handshake.expectedURL.lastPathComponent,
                  handshake.transitionStrategy.rawValue)
        }

        if progressConfirmed && (handshake.sawPlaying || started) {
            NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ final=success progressConfirmed=1 timeMs=%d pos=%.3f",
                  handshake.id,
                  handshake.reason,
                  timeMs,
                  position)
            reassertWindowAudioIfNeeded(reason: "handshake-progress-confirmed")
            cancelPlaybackStartHandshake(reason: "progress-confirmed", suppressLog: true)
            clearCompletionSequence(reason: "handshake-success", suppressLog: true)
            return
        }

        // P142: a file on a non-local volume gets one long window (and one rebuild after it) in
        // place of the short retry counters below. While waiting nothing touches the player: no
        // `play()` re-issue. Local files fall through to the counters, unchanged.
        if handshake.volume == .nonLocal {
            let failureSource: PlaybackStartFailureSource = (handshake.sawPlaying || started)
                ? .handshakeNoProgress : .handshakeNoPlaying
            let decision = PlaybackStartWindowPolicy.decide(
                volume: .nonLocal,
                source: failureSource,
                elapsedSeconds: CACurrentMediaTime() - handshake.windowStartMT,
                progressSeen: false,
                recoveryAvailable: handshake.transitionStrategy == .reuseCurrentPlayer && !handshake.recoveryUsed)
            switch decision {
            case .wait:
                playbackStartHandshake = handshake
                schedulePlaybackStartHandshakeCheck(for: handshake.id)
            case .rebuild:
                handshake.recoveryUsed = true
                handshake.playRetryCount = 0
                handshake.progressRetryCount = 0
                handshake.sawPlaying = false
                handshake.windowStartMT = CACurrentMediaTime()
                playbackStartHandshake = handshake
                NSLog("[dwb-playback] handshakeRecovery: id=%d reason=%@ recovery=fresh-player-after-start-window target=%@",
                      handshake.id,
                      handshake.reason,
                      handshake.expectedURL.lastPathComponent)
                rebuildPlayerAfterFailedStart(for: handshake)
                schedulePlaybackStartHandshakeCheck(for: handshake.id)
            case .failAndStop, .failAndSkip:
                NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ final=failure target=%@ failure=%@ (start window expired)",
                      handshake.id,
                      handshake.reason,
                      handshake.expectedURL.lastPathComponent,
                      failureSource.rawValue)
                cancelPlaybackStartHandshake(reason: "start-window-expired", suppressLog: true)
                schedulePlaybackFailureAutoSkip(failedURL: handshake.expectedURL,
                                                failedSessionID: handshake.expectedSessionID,
                                                source: failureSource.rawValue)
            }
            return
        }

        if handshake.sawPlaying || started {
            if handshake.progressRetryCount < maxPlaybackProgressConfirmationRetries {
                handshake.progressRetryCount += 1
                handshake.sawPlaying = true
                playbackStartHandshake = handshake
                NSLog("[dwb-playback] handshakeTransientPlayingNoProgress: id=%d reason=%@ retry=%d target=%@ timeMs=%d pos=%.3f",
                      handshake.id,
                      handshake.reason,
                      handshake.progressRetryCount,
                      handshake.expectedURL.lastPathComponent,
                      timeMs,
                      position)
                player.play()
                schedulePlaybackStartHandshakeCheck(for: handshake.id)
                return
            }

            if handshake.transitionStrategy == .reuseCurrentPlayer && !handshake.recoveryUsed {
                handshake.recoveryUsed = true
                handshake.playRetryCount = 0
                handshake.progressRetryCount = 0
                handshake.sawPlaying = false
                playbackStartHandshake = handshake
                NSLog("[dwb-playback] handshakeRecovery: id=%d reason=%@ recovery=fresh-player target=%@",
                      handshake.id,
                      handshake.reason,
                      handshake.expectedURL.lastPathComponent)
                rebuildPlayerAfterFailedStart(for: handshake)
                schedulePlaybackStartHandshakeCheck(for: handshake.id)
                return
            }

            NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ final=failure target=%@ failure=no-progress",
                  handshake.id,
                  handshake.reason,
                  handshake.expectedURL.lastPathComponent)
            cancelPlaybackStartHandshake(reason: "progress-retry-exhausted", suppressLog: true)
            schedulePlaybackFailureAutoSkip(failedURL: handshake.expectedURL,
                                            failedSessionID: handshake.expectedSessionID,
                                            source: "handshake-no-progress")
            return
        }

        if handshake.playRetryCount < maxPlaybackStartRetries {
            handshake.playRetryCount += 1
            playbackStartHandshake = handshake
            NSLog("[dwb-playback] handshakeRetry: id=%d reason=%@ player.play() retry=%d target=%@",
                  handshake.id,
                  handshake.reason,
                  handshake.playRetryCount,
                  handshake.expectedURL.lastPathComponent)
            player.play()
            schedulePlaybackStartHandshakeCheck(for: handshake.id)
            return
        }

        if handshake.transitionStrategy == .reuseCurrentPlayer && !handshake.recoveryUsed {
            handshake.recoveryUsed = true
            handshake.playRetryCount = 0
            handshake.progressRetryCount = 0
            playbackStartHandshake = handshake
            NSLog("[dwb-playback] handshakeRecovery: id=%d reason=%@ rebuilding player for target=%@",
                  handshake.id,
                  handshake.reason,
                  handshake.expectedURL.lastPathComponent)
            rebuildPlayerAfterFailedStart(for: handshake)
            schedulePlaybackStartHandshakeCheck(for: handshake.id)
            return
        }

        NSLog("[dwb-playback] handshakeCheck: id=%d reason=%@ final=failure target=%@ failure=no-playing",
              handshake.id,
              handshake.reason,
              handshake.expectedURL.lastPathComponent)
        cancelPlaybackStartHandshake(reason: "retry-exhausted", suppressLog: true)
        schedulePlaybackFailureAutoSkip(failedURL: handshake.expectedURL,
                                        failedSessionID: handshake.expectedSessionID,
                                        source: "handshake-no-playing")
    }

    private func rebuildPlayerAfterFailedStart(for handshake: PlaybackStartHandshake) {
        let rebuiltPlayer = installFreshPlayer(reason: "handshake-recovery",
                                               targetURL: handshake.expectedURL,
                                               stopOldPlayer: true)

        rebuiltPlayer.media = VLCMedia.forPlayback(url: handshake.expectedURL, site: .handshakeRecovery)
        NSLog("[dwb-playback] handshakeRecovery: id=%d assignedMedia=%@ session=%d volume=%d",
              handshake.id,
              handshake.expectedURL.lastPathComponent,
              handshake.expectedSessionID,
              rebuiltPlayer.audio?.volume ?? windowVolume)
        applyWindowAudioState(reason: "handshake-recovery-media-assigned", force: true)
        applyAudioDelay(reason: "handshake-recovery-media-assigned", force: true)
        applyPlaybackSpeed(reason: "handshake-recovery-media-assigned")
        audioReassertPending = true
        rebuiltPlayer.play()
        transport.invalidateCachedDisplayState()  // fresh player installed — force full refresh
        transport.update()
    }

    private func startPlaybackWithFreshPlayer(url: URL,
                                              startReason: String,
                                              sessionID: Int,
                                              expectPlaybackHandshake: Bool) {
        clearStoppedSuppression()
        let freshPlayer = installFreshPlayer(reason: startReason,
                                             targetURL: url,
                                             stopOldPlayer: true)
        freshPlayer.media = VLCMedia.forPlayback(url: url, site: .freshPlayer)
        applyWindowAudioState(reason: "fresh-player-media-assigned", force: true)
        applyAudioDelay(reason: "fresh-player-media-assigned", force: true)
        applyPlaybackSpeed(reason: "fresh-player-media-assigned")
        NSLog("[dwb-playback] autoplayTransition: target=%@ assignedMedia=1 reason=%@",
              url.lastPathComponent,
              startReason)
        if expectPlaybackHandshake {
            armPlaybackStartHandshake(reason: startReason,
                                      expectedURL: url,
                                      expectedSessionID: sessionID,
                                      transitionStrategy: .freshPlayer)
        } else {
            cancelPlaybackStartHandshake(reason: "playCurrentItem-\(startReason)-no-handshake")
        }
        NSLog("[dwb-playback] autoplayTransition: target=%@ playCall=1 reason=%@",
              url.lastPathComponent,
              startReason)
        audioReassertPending = true
        freshPlayer.play()
    }

    @discardableResult
    private func installFreshPlayer(reason: String,
                                    targetURL: URL,
                                    stopOldPlayer: Bool) -> VLCMediaPlayer {
        let oldPlayer = player
        let oldMedia = oldPlayer?.media?.url?.lastPathComponent ?? "—"
        let oldState = oldPlayer?.state.rawValue ?? -1
        if stopOldPlayer, oldPlayer != nil {
            releasePlaybackSleepAssertion()
            NSLog("[dwb-playback] autoplayTransition: reason=%@ target=%@ oldPlayerDetach=1 oldPlayerStop=1 oldMedia=%@ oldState=%d",
                  reason,
                  targetURL.lastPathComponent,
                  oldMedia,
                  oldState)
            oldPlayer?.delegate = nil
            oldPlayer?.drawable = nil
            oldPlayer?.stop()
        }

        let freshPlayer = VLCMediaPlayer()
        freshPlayer.delegate = self
        freshPlayer.drawable = videoSurface
        player = freshPlayer
        transport.controller = self
        transport.player = freshPlayer
        let appliedAudio = applyWindowAudioState(reason: "fresh-player-install", force: true)
        applyAudioDelay(reason: "fresh-player-install", force: true)
        lastAppliedScaleState = nil   // H4: new player — force VLC scale/crop re-assert.
        applyScaleMode()
        NSLog("[dwb-playback] autoplayTransition: reason=%@ target=%@ newPlayerCreate=1 delegate=1 drawable=1 transport=1 volume=%d scale=%@",
              reason,
              targetURL.lastPathComponent,
              appliedAudio.volume,
              scaleModeLogName())
        return freshPlayer
    }

    private func playbackProgressConfirmed(for handshake: PlaybackStartHandshake,
                                           currentTimeMs: Int,
                                           currentPosition: Float) -> Bool {
        let timeAdvanced = currentTimeMs >= (handshake.baselineTimeMs + playbackStartProgressAdvanceMs)
        let positionAdvanced = currentPosition.isFinite &&
            currentPosition >= (handshake.baselinePosition + playbackStartProgressAdvancePosition)
        return timeAdvanced || positionAdvanced
    }

    private func scaleModeLogName() -> String {
        switch scaleMode {
        case .fit:
            return "fit"
        case .fill:
            return "fill"
        case .stretch:
            return "stretch"
        }
    }

    private func completionActionForCurrentState() -> PlaybackCompletionAction {
        PlaybackCompletionPolicy(
            isRepeatOne: isRepeatOne,
            currentDisplayIndex: currentDisplayIndex,
            displayOrderCount: displayOrder.count,
            isEndlessShuffleOn: isEndlessShuffleOn,
            queueIsEmpty: playbackSet.isEmpty
        ).action
    }

    private func updatePlaybackProgressSnapshot(position: Float? = nil) {
        let nowMT = CACurrentMediaTime()   // M1: monotonic sample for this invocation
        let sampledPosition = position ?? player.position
        let sampledTimeMs = Int(player.time.intValue)
        let sampledDurationMs = Int(player.media?.length.intValue ?? 0)

        if sampledPosition.isFinite && sampledPosition >= 0 {
            lastKnownPosition = max(lastKnownPosition, sampledPosition)
        }
        if sampledTimeMs > 0 {
            lastKnownTimeMs = max(lastKnownTimeMs, sampledTimeMs)
        }
        if sampledDurationMs > 0 {
            lastKnownDurationMs = max(lastKnownDurationMs, sampledDurationMs)
            noteVLCReportedLength(sampledDurationMs)
        }

        lastPlayingMT = nowMT
        if (sampledPosition.isFinite && sampledPosition > 0) || sampledTimeMs > 0 {
            lastProgressMT = nowMT
        }
    }

    private func eofTimeToleranceMs(for durationMs: Int) -> Int {
        guard durationMs > 0 else { return watchdogDefaultEOFToleranceMs }
        let scaled = Int(Double(durationMs) * 0.03)
        return max(1_200, min(2_500, max(watchdogDefaultEOFToleranceMs, scaled)))
    }

    private func scheduleCompletionSequence(action: PlaybackCompletionAction,
                                            source: String,
                                            sourceURL: URL?,
                                            eofDecision: String) {
        guard activeCompletionSequence == nil else { return }

        playbackCompletionSequence += 1
        let sequence = CompletionSequence(id: playbackCompletionSequence,
                                          source: source,
                                          action: action,
                                          sourceURL: sourceURL,
                                          sourceSessionID: currentPlaybackSessionID)
        activeCompletionSequence = sequence

        NSLog("[dwb-playback] completionDecision: source=%@ action=%@ seq=%d media=%@ session=%d eof=%@ transition=reuse-current-player",
              source,
              action.rawValue,
              sequence.id,
              sourceURL?.lastPathComponent ?? currentMediaURL?.lastPathComponent ?? "—",
              currentPlaybackSessionID,
              eofDecision)

        switch action {
        case .repeatCurrent:
            schedulePlaybackAction(named: "completion-\(action.rawValue)-seq\(sequence.id)",
                                   after: delayedPlaybackActionInterval) { [weak self] in
                self?.playCurrentItem(startReason: "autoplay-repeat",
                                      expectPlaybackHandshake: true,
                                      preserveCompletionSequence: true,
                                      transitionStrategy: .reuseCurrentPlayer)
            }
        case .playNext, .endlessShuffleNext:
            let nextReason: String
            switch action {
            case .endlessShuffleNext:
                nextReason = "autoplay-endless-shuffle"
            default:
                nextReason = "autoplay-next"
            }
            schedulePlaybackAction(named: "completion-\(action.rawValue)-seq\(sequence.id)",
                                   after: delayedPlaybackActionInterval) { [weak self] in
                guard let self = self else { return }
                let advanced = self.advanceToNextItem(reason: nextReason,
                                                      expectPlaybackHandshake: true,
                                                      preserveCompletionSequence: true,
                                                      transitionStrategy: .reuseCurrentPlayer)
                if !advanced {
                    self.clearCompletionSequence(reason: "completion-no-next")
                }
            }
        case .stopLastItem:
            queueEndedNaturally = true
            NSLog("[dwb-playback] queueEnd: source=%@ displayIdx=%d naturalEnd=1", source, currentDisplayIndex)
        case .ignoredUserStop:
            clearCompletionSequence(reason: "ignored-user-stop", suppressLog: true)
        }
    }

    private func evaluateCompletionWatchdog(source: String,
                                            capturedMediaURL: URL? = nil,
                                            capturedStoppedPosition: Float? = nil) {
        let nowMT = CACurrentMediaTime()   // M1: single monotonic sample per invocation
        let currentState = player.state
        let recentSeekAge: TimeInterval    = lastUserSeekMT  > 0 ? nowMT - lastUserSeekMT  : -1
        let recentSeek = recentSeekAge >= 0 && recentSeekAge < userSeekEOFGuardWindow
        let recentPlayingAge: TimeInterval = lastPlayingMT   > 0 ? nowMT - lastPlayingMT   : -1
        let recentProgressAge: TimeInterval = lastProgressMT > 0 ? nowMT - lastProgressMT  : -1
        let recentStopAge: TimeInterval    = lastStoppedMT   > 0 ? nowMT - lastStoppedMT   : -1
        let playbackRecentlyActive = (recentPlayingAge >= 0 && recentPlayingAge < watchdogRecentPlaybackWindow)
            || (recentProgressAge >= 0 && recentProgressAge < watchdogRecentPlaybackWindow)
            || naturalEOFDetected
        let stoppedRecently = (recentStopAge >= 0 && recentStopAge < watchdogRecentStopWindow)
            || currentState == .stopped
            || currentState == .ended
        let sampledPosition = max(lastKnownPosition,
                                  max(positionAtEndedEvent,
                                      capturedStoppedPosition ?? lastStoppedPosition))
        let remainingMs = {
            guard lastKnownDurationMs > 0, lastKnownTimeMs > 0 else { return Int.max }
            return max(0, lastKnownDurationMs - lastKnownTimeMs)
        }()
        let pausedNearEOF = !isUserStop
            && !recentSeek
            && !ExplicitPlayPauseCompletionPolicy.suppressesPausedNearEOFCompletion(
                for: explicitPlayPauseIntent?.target
            )
            && currentState == .paused
            && (sampledPosition >= pausedNearEOFPositionThreshold
                || remainingMs <= pausedNearEOFRemainingMs)
        let rendererInactive = !player.isPlaying
            && currentState != .playing
            && currentState != .opening
            && currentState != .buffering
            && !pausedNearEOF
        let nearEOFByPosition = sampledPosition >= eofPositionThreshold
        let nearEOFByTime: Bool = {
            guard lastKnownDurationMs > 0, lastKnownTimeMs > 0 else { return false }
            return (lastKnownDurationMs - lastKnownTimeMs) <= eofTimeToleranceMs(for: lastKnownDurationMs)
        }()
        let strongEOF = naturalEOFDetected || positionAtEndedEvent >= eofPositionThreshold
        let eofDetected = pausedNearEOF || strongEOF || ((nearEOFByTime || nearEOFByPosition) && stoppedRecently)
        let targetURL = capturedMediaURL ?? currentMediaURL ?? lastStoppedMediaURL
        let targetURLName = targetURL?.lastPathComponent ?? currentMediaURL?.lastPathComponent ?? "—"
        let completionSource = pausedNearEOF ? "paused-near-eof" : source
        let staleEvent = {
            guard let capturedPath = capturedMediaURL?.path,
                  let currentPath = currentMediaURL?.path else { return false }
            return capturedPath != currentPath
        }()
        let action = completionActionForCurrentState()
        let completionSeqID = activeCompletionSequence?.id ?? 0
        let eofDecision = eofDetected
            ? (pausedNearEOF ? "paused-near-eof" : (strongEOF ? "strong-eof" : "watchdog-near-eof"))
            : (recentSeek ? "seek-guarded" : "no-eof")

        // Per-tick trace: gated behind Settings > Developer > Verbose Autoplay Trace (default OFF).
        // Terminal-path decision logs (completionDecision, accepted .ended, etc.) are
        // preserved unconditionally below and in scheduleCompletionSequence.
        #if DEBUG
        if SettingsWindowController.isVerboseAutoplayTraceEnabled() {
        NSLog("[dwb-autoplay-trace] watchdog: source=%@ media=%@ displayIdx=%d/%d queueCount=%d displayOrderCount=%d pos=%.3f timeMs=%d durationMs=%d userStop=%d recentSeek=%d suppressNextStopped=%d completionSeq=%d playingAge=%.2f progressAge=%.2f stopAge=%.2f eof=%@",
              completionSource,
              targetURLName,
              currentDisplayIndex,
              displayOrder.count,
              playbackSet.count,
              displayOrder.count,
              sampledPosition,
              lastKnownTimeMs,
              lastKnownDurationMs,
              isUserStop ? 1 : 0,
              recentSeek ? 1 : 0,
              suppressNextStopped ? 1 : 0,
              completionSeqID,
              max(0, recentPlayingAge),
              max(0, recentProgressAge),
              max(0, recentStopAge),
              eofDecision)
        } // isVerboseAutoplayTraceEnabled
        #endif

        guard !staleEvent else {
            NSLog("[dwb-playback] completionDecision: source=%@ action=ignored-stale-event media=%@", source, targetURLName)
            return
        }

        // A truncated file plays until its data runs out, then VLC pauses on its own well
        // before EOF. The only user pause path records an explicit .pause intent, so a
        // .paused event without one, short of EOF, is a playback failure: skip it.
        if source == "paused",
           currentState == .paused,
           !eofDetected,
           !recentSeek,
           !isUserStop,
           !currentItemIsImage,
           playbackStartHandshake == nil,
           explicitPlayPauseIntent?.target != .pause,
           let failedURL = currentMediaURL {
            NSLog("[dwb-playback] completionDecision: source=paused action=failure reason=paused-before-eof-without-user-intent pos=%.3f media=%@",
                  sampledPosition, targetURLName)
            let intentName: String = {
                switch explicitPlayPauseIntent?.target {
                case .pause?: return "pause"
                case .play?:  return "play"
                case nil:     return "none"
                }
            }()
            schedulePlaybackFailureAutoSkip(
                failedURL: failedURL,
                failedSessionID: currentPlaybackSessionID,
                source: "paused-before-eof",
                detail: "paused-before-eof: \(targetURLName) pos=\(String(format: "%.3f", sampledPosition)) intent=\(intentName) session=\(currentPlaybackSessionID)")
            return
        }

        guard (rendererInactive && playbackRecentlyActive) || pausedNearEOF else { return }
        guard !recentSeek, eofDetected else { return }
        guard currentMediaURL != nil, currentDisplayIndex >= 0, !displayOrder.isEmpty else { return }

        scheduleCompletionSequence(action: action,
                                   source: completionSource,
                                   sourceURL: targetURL,
                                   eofDecision: eofDecision)
    }

    /// Detects a video that started fine but has gone silent mid-stream: VLC keeps
    /// reporting .playing/.buffering (isPlaying stays true) but position/time have not
    /// actually moved for midPlaybackStallToleranceSeconds. Complements the start-handshake
    /// (which only covers the initial start-up window) and evaluateCompletionWatchdog (which
    /// only fires on an explicit .paused/.ended/.stopped transition VLC never delivers here).
    private func evaluateMidPlaybackStallWatchdog() {
        guard !currentItemIsImage,
              playbackStartHandshake == nil,
              !isUserStop,
              let stalledURL = currentMediaURL else {
            return
        }
        guard player.isPlaying else {
            midPlaybackStallClock.playbackPaused()
            return
        }

        let nowMT = CACurrentMediaTime()
        let recentSeekAge: TimeInterval = lastUserSeekMT > 0 ? nowMT - lastUserSeekMT : -1
        guard recentSeekAge < 0 || recentSeekAge >= userSeekEOFGuardWindow else { return }

        let timeMs = Int(player.time.intValue)
        let position = player.position
        guard let stalledForSeconds = midPlaybackStallClock.stalledSeconds(
            timeMs: timeMs,
            position: position,
            nowMT: nowMT,
            toleranceSeconds: PlaybackStartWindowPolicy.stallToleranceSeconds(for: currentItemVolumeKind)
        ) else { return }
        guard PlaybackStartWindowPolicy.decide(volume: currentItemVolumeKind,
                                               source: .midPlaybackStall,
                                               elapsedSeconds: stalledForSeconds,
                                               progressSeen: false,
                                               recoveryAvailable: false) != .wait else { return }

        let stalledSessionID = currentPlaybackSessionID
        NSLog("[dwb-playback] midPlaybackStall: media=%@ session=%d stalledForSec=%.1f timeMs=%d pos=%.3f",
              stalledURL.lastPathComponent, stalledSessionID, stalledForSeconds, timeMs, position)
        schedulePlaybackFailureAutoSkip(
            failedURL: stalledURL,
            failedSessionID: stalledSessionID,
            source: "mid-playback-stall",
            detail: "stall: \(stalledURL.lastPathComponent) stalledFor=\(String(format: "%.1f", stalledForSeconds))s timeMs=\(timeMs) pos=\(String(format: "%.3f", position)) session=\(stalledSessionID)")
    }

    // MARK: - Playback speed

    func setPlaybackSpeed(_ rate: Float, source: String = "menu") {
        let option = PlaybackSpeedOption.validated(rate)
        let changed = playbackSpeed != option.rate
        playbackSpeed = option.rate
        applyPlaybackSpeed(reason: source)
        if changed {
            NotificationCenter.default.post(name: .playbackSpeedChanged, object: self)
        }
    }

    private func applyPlaybackSpeed(reason: String) {
        guard player != nil else { return }
        if currentItemIsImage {
            DebugConsoleController.log("playback", "speedImageNoop: window=\(debugIdentity) reason=\(reason) rate=\(playbackSpeed)")
            return
        }
        player.rate = playbackSpeed
        DebugConsoleController.log("playback", "speedApply: window=\(debugIdentity) reason=\(reason) rate=\(playbackSpeed)")
        needsTransportUpdate = true
    }

    // MARK: - Volume

    /// The volume a new window starts at (D-010). Settings shows it when no window is open.
    static func defaultPersistedVolume() -> Int32 {
        let key = SettingsWindowController.persistedVolumeKey
        guard UserDefaults.standard.object(forKey: key) != nil else { return 100 }
        return VolumePolicy.clamped(UserDefaults.standard.integer(forKey: key))
    }

    /// What Settings shows for this window: 0 while muted, otherwise the stored volume.
    var currentEffectiveVolume: Int32 {
        VolumePolicy.effectiveVolume(stored: windowVolume, muted: windowMuted)
    }

    /// Tells Settings when this window's effective volume changed, from any route.
    private func postWindowVolumeChangedIfNeeded(from oldEffective: Int32, wasMuted: Bool) {
        guard oldEffective != currentEffectiveVolume || wasMuted != windowMuted else { return }
        NotificationCenter.default.post(name: .windowVolumeChanged, object: self)
    }

    private var audioStateDescription: String {
        "volume=\(windowVolume) muted=\(windowMuted)"
    }

    private func persistVolume(_ volume: Int32) {
        UserDefaults.standard.set(Int(VolumePolicy.clamped(volume)), forKey: SettingsWindowController.persistedVolumeKey)
    }

    @discardableResult
    private func applyWindowAudioState(reason: String, force: Bool = false) -> (volume: Int32, muted: Bool) {
        let clampedVolume = VolumePolicy.clamped(windowVolume)
        if clampedVolume != windowVolume {
            windowVolume = clampedVolume
        }
        let appliedVolume: Int32 = windowMuted ? 0 : clampedVolume
        let nextState = (volume: appliedVolume, muted: windowMuted)
        let changed = lastAppliedAudioState?.volume != nextState.volume || lastAppliedAudioState?.muted != nextState.muted
        if force || changed {
            // P50: audio.volume= calls config_PutInt (VLCKit global rwlock write) when the audio
            // output is not active. Only write when the window's effective state changed or the
            // caller forces it (e.g. fresh-player-install). Redundant writes on the reuse/
            // replacement path were the source of the multi-window main-thread hang traced in
            // spindump 26-05-19.
            // P137: the cache only knows what this window last wrote. VLC's volume is shared by
            // every player, so another window can change it behind the cache; the start check in
            // reassertWindowAudioIfNeeded covers that by comparing VLC's actual value.
            player?.audio?.volume = appliedVolume
            lastAppliedAudioState = nextState
            // Only log when something actually changed or a caller forced the apply.
            // Unconditional logging here contributed to the per-window-start log
            // storms that saturated the debug console during multi-window playback.
            DebugConsoleController.log("audio", "apply: window=\(debugIdentity) reason=\(reason) storedVolume=\(windowVolume) appliedVolume=\(appliedVolume) muted=\(windowMuted) forced=\(force ? 1 : 0)")
        } else {
            // P50: Skipping redundant VLCKit config write — state unchanged, no global lock acquired.
            DebugConsoleController.log("audio", "applySkip: window=\(debugIdentity) reason=\(reason) storedVolume=\(windowVolume) appliedVolume=\(appliedVolume) noChange=1 configWriteAvoided=1")
        }
        return nextState
    }

    /// P137: writes this window's volume back to VLC only when VLC's actual value differs.
    /// Call it only where an audio output is up (`.playing`, handshake progress confirmed), never
    /// right after `player.stop()` (P50). Does nothing when VLC reports no usable value.
    private func reassertWindowAudioIfNeeded(reason: String) {
        guard let audio = player?.audio else { return }
        let actual = audio.volume
        let intended: Int32 = windowMuted ? 0 : VolumePolicy.clamped(windowVolume)
        guard let corrected = AudioReassertPolicy.valueToWrite(actual: actual, intended: intended) else { return }
        audio.volume = corrected
        lastAppliedAudioState = (volume: corrected, muted: windowMuted)
        needsTransportUpdate = true   // rail and transport icons read VLC's actual volume
        DebugConsoleController.log("audio", "reassert: window=\(debugIdentity) reason=\(reason) read=\(actual) wrote=\(corrected) muted=\(windowMuted)")
    }

    func adjustVolume(by delta: Int) {
        let oldVol = windowVolume
        let wasMuted = windowMuted
        let newVol = VolumePolicy.clamped(Int(windowVolume) + delta)
        windowVolume = newVol
        if newVol > 0 { windowMuted = false }
        DebugConsoleController.log("audio", "volumeChange: window=\(debugIdentity) old=\(oldVol) new=\(newVol) wasMuted=\(wasMuted) muted=\(windowMuted)")
        applyWindowAudioState(reason: "volume-adjust")
        persistVolume(newVol)
        showVolumeHUD(volume: newVol)
        postWindowVolumeChangedIfNeeded(from: VolumePolicy.effectiveVolume(stored: oldVol, muted: wasMuted), wasMuted: wasMuted)
    }

    func setVolumeFromBar(_ vol: Int32) {
        let oldVol = windowVolume
        let wasMuted = windowMuted
        let newVol = VolumePolicy.clamped(vol)
        windowVolume = newVol
        windowMuted = newVol == 0
        DebugConsoleController.log("audio", "volumeSet: window=\(debugIdentity) old=\(oldVol) new=\(newVol) wasMuted=\(wasMuted) muted=\(windowMuted)")
        applyWindowAudioState(reason: "volume-bar")
        persistVolume(newVol)
        showVolumeHUD(volume: newVol)
        postWindowVolumeChangedIfNeeded(from: VolumePolicy.effectiveVolume(stored: oldVol, muted: wasMuted), wasMuted: wasMuted)
    }

    /// Settings' Window volume slider: the volume bar's rules without the HUD.
    func setVolumeFromSettings(_ vol: Int32) {
        let oldVol = windowVolume
        let wasMuted = windowMuted
        let newVol = VolumePolicy.clamped(vol)
        windowVolume = newVol
        windowMuted = newVol == 0
        DebugConsoleController.log("audio", "volumeSet: window=\(debugIdentity) old=\(oldVol) new=\(newVol) wasMuted=\(wasMuted) muted=\(windowMuted) source=settings")
        applyWindowAudioState(reason: "settings")
        persistVolume(newVol)
        postWindowVolumeChangedIfNeeded(from: VolumePolicy.effectiveVolume(stored: oldVol, muted: wasMuted), wasMuted: wasMuted)
    }

    func showVolumeBar(volume: Int32) {
        showVolumeHUD(volume: volume)
    }

    func toggleMuteFromTransport() {
        let oldEffective = currentEffectiveVolume
        let wasMuted = windowMuted
        if windowMuted {
            if windowVolume == 0 { windowVolume = Self.defaultPersistedVolume() }
            if windowVolume == 0 { windowVolume = 100 }
            windowMuted = false
        } else {
            windowMuted = true
        }
        DebugConsoleController.log("audio", "muteToggle: window=\(debugIdentity) oldMuted=\(wasMuted) newMuted=\(windowMuted) storedVolume=\(windowVolume)")
        let applied = applyWindowAudioState(reason: "mute-toggle")
        showVolumeHUD(volume: applied.volume)
        postWindowVolumeChangedIfNeeded(from: oldEffective, wasMuted: wasMuted)
    }

    func volumeUp()   { adjustVolume(by: 10)  }
    func volumeDown() { adjustVolume(by: -10) }

    // MARK: - Audio sync offset (Bluetooth-latency compensation)

    private static func defaultPersistedAudioDelayMs() -> Int32 {
        let key = SettingsWindowController.audioSyncDelayKey
        guard UserDefaults.standard.object(forKey: key) != nil else { return 0 }
        return Self.clampedAudioDelayMs(Int32(UserDefaults.standard.integer(forKey: key)))
    }

    private static func clampedAudioDelayMs(_ ms: Int32) -> Int32 {
        let range = SettingsWindowController.audioSyncDelayRangeMilliseconds
        return min(max(ms, range.lowerBound), range.upperBound)
    }

    private func persistAudioDelayMs(_ ms: Int32) {
        UserDefaults.standard.set(Int(ms), forKey: SettingsWindowController.audioSyncDelayKey)
    }

    /// Applies `windowAudioDelayMs` to the live player's currentAudioPlaybackDelay
    /// (microseconds). Unlike audio.volume, this property does not touch VLCKit's
    /// global config lock (see P50 in applyWindowAudioState), so no deadlock hazard
    /// applies here — the changed-guard below is purely to skip redundant writes and
    /// log spam, matching the codebase's established audio-apply style.
    @discardableResult
    private func applyAudioDelay(reason: String, force: Bool = false) -> Int32 {
        let clamped = Self.clampedAudioDelayMs(windowAudioDelayMs)
        if clamped != windowAudioDelayMs {
            windowAudioDelayMs = clamped
        }
        if force || lastAppliedAudioDelayMs != clamped {
            player?.currentAudioPlaybackDelay = Int(clamped) * 1_000
            lastAppliedAudioDelayMs = clamped
            DebugConsoleController.log("audio", "delayApply: window=\(debugIdentity) reason=\(reason) delayMs=\(clamped)")
        }
        return clamped
    }

    /// Nudges the audio sync offset by `deltaMs` (positive delays audio further,
    /// negative advances it), applies it immediately, persists it as the new
    /// default for future windows/videos, and shows the HUD.
    func adjustAudioDelay(byMilliseconds deltaMs: Int32) {
        windowAudioDelayMs = Self.clampedAudioDelayMs(windowAudioDelayMs + deltaMs)
        let applied = applyAudioDelay(reason: "audio-delay-adjust")
        persistAudioDelayMs(applied)
        audioDelayBar.show(milliseconds: applied)
    }

    func resetAudioDelay() {
        windowAudioDelayMs = 0
        let applied = applyAudioDelay(reason: "audio-delay-reset", force: true)
        persistAudioDelayMs(applied)
        audioDelayBar.show(milliseconds: applied)
    }

    var currentAudioDelayMs: Int32 { windowAudioDelayMs }

    func increaseAudioDelay() { adjustAudioDelay(byMilliseconds: SettingsWindowController.audioSyncDelayStepMilliseconds) }
    func decreaseAudioDelay() { adjustAudioDelay(byMilliseconds: -SettingsWindowController.audioSyncDelayStepMilliseconds) }

    // MARK: - Window opacity

    func setWindowOpacityFromSettings(_ opacity: CGFloat) {
        windowOpacity = SettingsWindowController.clampedPlayerWindowOpacity(opacity)
        applyWindowOpacity(reason: "settings")
    }

    private func applyWindowOpacity(reason: String, force: Bool = false) {
        guard let win = window else { return }
        let clamped = SettingsWindowController.clampedPlayerWindowOpacity(windowOpacity)
        if clamped != windowOpacity {
            windowOpacity = clamped
        }

        let targetAlpha: CGFloat = (isFullscreen || isEnteringFullscreen || isExitingFullscreen) ? 1.0 : clamped
        if force || abs(win.alphaValue - targetAlpha) > 0.0001 {
            win.alphaValue = targetAlpha
            DebugConsoleController.log("window", "opacityApply: window=\(debugIdentity) reason=\(reason) stored=\(SettingsWindowController.playerWindowOpacityPercent(windowOpacity))% applied=\(SettingsWindowController.playerWindowOpacityPercent(targetAlpha))%")
        }
    }

    // MARK: - Scale mode

    func setScaleMode(_ mode: ScaleMode) {
        scaleMode = mode
        applyScaleMode()
        showStatusHUD(.scale(mode))
    }

    private func applyScaleMode() {
        guard player != nil else { return }
        let size = videoSurface.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        // H4: skip redundant VLC writes when effective scale state is unchanged.
        let newState = AppliedScaleState(mode: scaleMode,
                                         width:  Int(size.width),
                                         height: Int(size.height))
        guard newState != lastAppliedScaleState else { return }
        lastAppliedScaleState = newState
        let ratio = "\(newState.width):\(newState.height)"
        switch scaleMode {
        case .fit:
            player.videoAspectRatio  = nil
            player.videoCropGeometry = nil
        case .fill:
            player.videoAspectRatio  = nil
            ratio.withCString { player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) }
        case .stretch:
            ratio.withCString { player.videoAspectRatio = UnsafeMutablePointer(mutating: $0) }
            player.videoCropGeometry = nil
        }
    }

    // MARK: - Update timer

    private func startUpdateTimer() {
        lastUpdateTickMT = 0
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // P142: a long gap between ticks means the main thread was blocked (or the run loop
            // was in menu-tracking mode; Open panels are excluded). Logged as a warning so it is kept even
            // when the console is off.
            let tickMT = CACurrentMediaTime()
            if self.lastUpdateTickMT > 0,
               tickMT - self.lastUpdateTickMT > self.mainThreadGapLogSeconds,
               Self.lastModalReturnMT <= self.lastUpdateTickMT {
                DebugConsoleController.log(level: .warning,
                                           category: "volume",
                                           message: "main-thread gap \(String(format: "%.1f", tickMT - self.lastUpdateTickMT)) s window=\(self.debugIdentity)")
            }
            self.lastUpdateTickMT = tickMT

            // Image slideshow: update transport state and check for auto-advance.
            if self.currentItemIsImage {
                let now = CACurrentMediaTime()
                let elapsed: TimeInterval
                if self.imageSlideshowPaused || self.imageSlideshowStartMT == 0 {
                    elapsed = self.imageSlideshowPauseAccumulated
                } else {
                    elapsed = self.imageSlideshowPauseAccumulated + (now - self.imageSlideshowStartMT)
                }
                let dur = self.currentImagePlaybackDurationSeconds
                self.transport.imageModeElapsed = min(elapsed, dur)
                self.transport.imageModeDuration = dur
                self.transport.imageModeIsPlaying = !self.imageSlideshowPaused
                self.needsTransportUpdate = true

                if !self.imageSlideshowPaused && !self.isUserStop && self.imageSlideshowStartMT > 0 && elapsed >= dur {
                    self.imageSlideshowStartMT = 0  // prevent re-triggering
                    let action = self.completionActionForCurrentState()
                    if action == .stopLastItem {
                        // Freeze at end — image stays visible, slideshow halts.
                        self.queueEndedNaturally = true
                        self.imageSlideshowPaused = true
                        self.imageSlideshowPauseAccumulated = dur
                        self.transport.imageModeIsPlaying = false
                        NSLog("[dwb-image] slideshow-end: last item, stopped naturalEnd=1")
                    } else {
                        NSLog("[dwb-image] slideshow-advance: elapsed=%.2f dur=%.0f action=%@",
                              elapsed, dur, action.rawValue)
                        DebugConsoleController.log("image", "auto-advance: action=\(action.rawValue)")
                        self.scheduleCompletionSequence(action: action,
                                                         source: "image-slideshow",
                                                         sourceURL: self.currentMediaURL,
                                                         eofDecision: "image-elapsed")
                    }
                }
            }

            // Progress snapshot and watchdog always run — correctness-critical.
            if self.player?.isPlaying == true {
                self.updatePlaybackProgressSnapshot()
            }
            self.evaluateCompletionWatchdog(source: "watchdog")
            self.evaluateMidPlaybackStallWatchdog()
            // M6 + M4: cosmetic transport refresh, gated for efficiency.
            // Skipped when the window is not effectively visible (minimized or occluded)
            // to avoid needless AppKit work. needsTransportUpdate is preserved so a
            // refresh fires promptly once the window becomes visible again.
            // needsForceRefreshOnReturn triggers one unconditional refresh on return.
            let forceRefresh = self.needsForceRefreshOnReturn
            if self.player?.isPlaying == true || self.needsTransportUpdate || forceRefresh {
                let shouldUpdate = self.isEffectivelyVisibleForCosmeticRefresh || forceRefresh
                if forceRefresh { self.needsForceRefreshOnReturn = false }
                if shouldUpdate {
                    self.needsTransportUpdate = false
                    self.transport.update()
                }
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
        lastUpdateTickMT = 0
    }

    // MARK: - HUD / transport visibility

    private func showHUD() {
        if transport.isUsingUnifiedBottomRail {
            transport.showChromeFromHost(animated: true)
            return
        }
        hudShowGeneration += 1
        transport.isHidden = false
        transport.setBackdropActive(true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DWBAppearance.shared.duration(0.15)
            transport.animator().alphaValue = 1.0
        }
    }

    private func hideHUD() {
        if transport.isUsingUnifiedBottomRail {
            return
        }
        let gen = hudShowGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DWBAppearance.shared.duration(0.3)
            transport.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            guard let self = self, self.hudShowGeneration == gen else { return }
            self.transport.isHidden = true
            self.transport.setBackdropActive(false)
        }
    }

    private func scheduleHide() {
        if transport.isUsingUnifiedBottomRail {
            transport.scheduleChromeHideFromHost()
            return
        }
        hideHUDTimer?.invalidate()
        hideHUDTimer = Timer.scheduledTimer(withTimeInterval: 2.7, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.isFullscreen { self.hideHUD() }
        }
    }

    // MARK: - Titlebar auto-hide
    //
    // Feature: windowed-mode only. Default OFF (controlled by SettingsWindowController.autoHideTitlebarKey).
    // - hideTitlebar(): fades titlebar view alpha to 0, then sets titlebarAppearsTransparent=true
    //   in the animation completion (deferred to avoid background-disappearing before traffic
    //   lights have finished fading).
    // - showTitlebar(): immediately clears titlebarAppearsTransparent=false, then fades alpha to 1.
    // - titlebarAppearsTransparent writes are guarded by isEnteringFullscreen/isExitingFullscreen/isFullscreen
    //   to preserve prior P06A fullscreen-titlebar stabilization.
    // - The titlebar view alpha is reset to 1.0 in cleanupFullscreenWindowState (called on exit).

    private func showTitlebar() {
        guard !shouldApplyCompleteVideoWindowMode else { return }
        guard !isEnteringFullscreen, !isExitingFullscreen, !isFullscreen else { return }
        guard let tbv = titlebarContainerView else { return }
        guard titlebarIsHidden else { return }   // already visible — skip redundant AppKit work and log
        titlebarIsHidden = false
        DebugConsoleController.log("window", "titlebar: show")
        window?.titlebarAppearsTransparent = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DWBAppearance.shared.duration(0.15)
            tbv.animator().alphaValue = 1.0
        }
    }

    private func hideTitlebar() {
        guard !shouldApplyCompleteVideoWindowMode else { return }
        guard autoHideTitlebarEnabled, !isEnteringFullscreen, !isExitingFullscreen, !isFullscreen else { return }
        guard let tbv = titlebarContainerView else { return }
        guard !titlebarIsHidden else { return }   // already hidden — skip redundant AppKit work and log
        titlebarIsHidden = true
        DebugConsoleController.log("window", "titlebar: hide")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DWBAppearance.shared.duration(0.3)
            tbv.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            // Only apply transparent background once the fade is complete, to prevent
            // a flash where the material disappears before the traffic lights finish fading.
            guard let self = self, self.titlebarIsHidden else { return }
            self.window?.titlebarAppearsTransparent = true
        }
    }

    private func scheduleTitlebarHide() {
        guard !shouldApplyCompleteVideoWindowMode else { return }
        titlebarHideTimer?.invalidate()
        titlebarHideTimer = Timer.scheduledTimer(withTimeInterval: 2.7, repeats: false) { [weak self] _ in
            guard let self = self, self.autoHideTitlebarEnabled, !self.isFullscreen, !self.shouldApplyCompleteVideoWindowMode else { return }
            self.hideTitlebar()
        }
    }

    // MARK: - Mouse tracking

    private func addMouseTracking() {
        guard let cv = window?.contentView else { return }
        removeMouseTracking()
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        cv.addTrackingArea(area)
        trackingArea = area
        // Titlebar zone: separate tracking area so mouse-entered events from the titlebar
        // region (above the content view) restore the titlebar when auto-hide is active.
        if let tbv = titlebarContainerView {
            let tbArea = NSTrackingArea(rect: .zero,
                                        options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                        owner: self,
                                        userInfo: nil)
            tbv.addTrackingArea(tbArea)
            titlebarTriggerTrackingArea = tbArea
        }
    }

    private func removeMouseTracking() {
        if let area = trackingArea {
            window?.contentView?.removeTrackingArea(area)
            trackingArea = nil
        }
        if let tbArea = titlebarTriggerTrackingArea {
            titlebarContainerView?.removeTrackingArea(tbArea)
            titlebarTriggerTrackingArea = nil
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if transport.isUsingUnifiedBottomRail {
            transport.noteChromeActivity()
        } else if isFullscreen {
                showHUD()
                scheduleHide()
        }
        if autoHideTitlebarEnabled, !isFullscreen, !shouldApplyCompleteVideoWindowMode, let cv = window?.contentView {
            // Restore titlebar when cursor enters the top trigger zone (the last 20pt of
            // the content view or the titlebar area above it — both satisfy this check
            // because a location above the content view converts to y > cv.bounds.height).
            let loc = cv.convert(event.locationInWindow, from: nil)
            if loc.y >= cv.bounds.height - 20 {
                showTitlebar()
                scheduleTitlebarHide()
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard autoHideTitlebarEnabled, !isFullscreen, !shouldApplyCompleteVideoWindowMode else { return }
        // Fires when the cursor enters the titlebar view from outside the window
        // (e.g. descending from the menu bar). event.trackingArea identifies the source.
        guard event.trackingArea === titlebarTriggerTrackingArea else { return }
        showTitlebar()
        scheduleTitlebarHide()
    }

    // MARK: - Window close

    override func close() {
        cancelPendingFolderScan()
        resetPlaybackCompletionSignals(reason: "window-close")
        if currentItemIsImage {
            clearImageSlideshowState()
        } else if player.isPlaying {
            isUserStop = true
            player.stop()
        }
        super.close()
    }
}

// MARK: - NSWindowDelegate

extension PlayerWindowController: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        // Closing a window leaves nothing running: no playback, timer, work item,
        // observer, or sleep assertion outlives it (P136).
        isWindowClosed = true
        cancelPendingFolderScan()
        resetPlaybackCompletionSignals(reason: "window-will-close")
        queuedPlaybackCommands.removeAll()
        gifDurations.removeAll()
        gifIntakeProgress = nil
        releasePlaybackSleepAssertion()
        stopUpdateTimer()
        hideHUDTimer?.invalidate()
        titlebarHideTimer?.invalidate()
        seekTargetResetTimer?.invalidate()
        removeMouseTracking()
        NotificationCenter.default.removeObserver(self)
        if currentItemIsImage {
            clearImageSlideshowState()   // also stops the GIF frame timer
        }
        // Stop whenever media is loaded, playing or paused; isUserStop keeps the
        // resulting .stopped from auto-advancing.
        if player.media != nil {
            isUserStop = true
            player.stop()
        }
        updateSettingsTargetOutline()
        DebugConsoleController.log("window", "close: window=\(debugIdentity)")
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.windowControllers.removeAll { $0 === self }
        }
        postTargetingChanged()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        lastKeyStamp = Self.makeTargetingStamp()
        postTargetingChanged()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        minimizeStamp = Self.makeTargetingStamp()
        postTargetingChanged()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        minimizeStamp = nil
        postTargetingChanged()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isEnteringFullscreen = true
        applyWindowOpacity(reason: "fullscreen-will-enter", force: true)
        updateSettingsTargetOutline()
        // AppKit manages window levels during fullscreen; restore normal level first
        // so the transition is clean.  The level is reapplied on exit if needed.
        if isKeepAtTop { window?.level = .normal }
        DebugConsoleController.log("window", "enterFullscreen")
        logChromeState("windowWillEnterFullScreen")
        logLayoutSnapshot("windowWillEnterFullScreen")
    }

    func windowDidResize(_ notification: Notification) {
        logChromeState("windowDidResize [no chrome write]")
        logLayoutSnapshot("windowDidResize")
        // Chrome normalization is intentionally absent from this path.
        //
        // Writing titlebar/chrome properties during live resize (even idempotent
        // same-value writes) forces AppKit to re-evaluate titlebar geometry on every
        // resize event, causing cumulative titlebar height drift — the root cause of
        // the large-titlebar bug after fullscreen exit and free resize.
        //
        // Authoritative chrome restoration happens exactly once: in the deferred block
        // inside windowDidExitFullScreen, after the window system has fully settled.
        // The window is built with correct chrome in buildWindow() and the deferred
        // block restores it after each fullscreen cycle — no per-resize correction needed.
        layoutPlayerViews()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isEnteringFullscreen = false
        isFullscreen         = true
        applyWindowOpacity(reason: "fullscreen-did-enter", force: true)
        DebugConsoleController.log("window", "fullscreenEntered")
        logChromeState("windowDidEnterFullScreen")
        logLayoutSnapshot("windowDidEnterFullScreen")
        // Cancel any pending titlebar auto-hide; macOS owns fullscreen chrome.
        titlebarHideTimer?.invalidate()
        titlebarHideTimer = nil
        titlebarContainerView?.alphaValue = 1.0
        titlebarIsHidden = false
        layoutPlayerViews()
        addMouseTracking()
        transport.isHidden = false
        transport.setBackdropActive(true)
        transport.alphaValue = 1.0
        showHUD()
        scheduleHide()
        window?.makeFirstResponder(videoSurface)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // Set isExitingFullscreen HERE — before AppKit delivers exit-animation
        // windowDidResize callbacks.  Those callbacks still see isFullscreen=true,
        // but layoutMode now returns .exitingFullscreenSettling, so layoutPlayerViews()
        // applies windowed-baseline geometry instead of fullscreen HUD geometry.
        isExitingFullscreen = true
        applyWindowOpacity(reason: "fullscreen-will-exit", force: true)
        DebugConsoleController.log("window", "exitFullscreen")
        logChromeState("windowWillExitFullScreen")
        logLayoutSnapshot("windowWillExitFullScreen")
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isFullscreen        = false
        // isExitingFullscreen is already true (set in windowWillExitFullScreen);
        // re-assert defensively in case the Will callback was skipped.
        isExitingFullscreen = true
        DebugConsoleController.log("window", "fullscreenExited")
        logChromeState("windowDidExitFullScreen")
        logLayoutSnapshot("windowDidExitFullScreen")
        hideHUDTimer?.invalidate()

        // Immediate pass: snap chrome back so the window doesn't look wrong on screen.
        // Because windowDidResize no longer performs chrome writes, the resize callback
        // triggered by this styleMask removal is safe and creates no cascade.
        cleanupFullscreenWindowState()

        transport.isHidden = false
        transport.setBackdropActive(true)
        transport.alphaValue = 1.0
        addMouseTracking()
        layoutPlayerViews()

        // Deferred authoritative pass: after the window system has fully settled,
        // perform the final chrome restore + layout and clear the exiting flag.
        // This is the ONE place that clears isExitingFullscreen; after this point
        // layoutMode returns .windowed and later resizes do not touch chrome.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cleanupFullscreenWindowState()
            self.isExitingFullscreen = false
            self.applyWindowedChromeModeIfNeeded()
            self.applyWindowOpacity(reason: "fullscreen-exit-settled", force: true)
            self.updateSettingsTargetOutline()
            self.logChromeState("windowDidExitFullScreen [deferred settle]")
            self.layoutPlayerViews()
            // Restore keep-at-top level now that AppKit has finished its fullscreen cleanup.
            if self.isKeepAtTop { self.applyKeepAtTop() }
        }
    }

    /// Restore all window-chrome properties that macOS modifies during fullscreen.
    /// Idempotent: safe to call multiple times.
    ///
    /// Uses targeted property restoration rather than full styleMask replacement.
    /// Atomic mask replacement (win.styleMask = saved) triggers additional AppKit
    /// layout passes and is the source of cascading resize events — we avoid it.
    private func cleanupFullscreenWindowState() {
        guard let win = window else { return }
        #if DEBUG
        NSLog("[dwb-chrome] cleanupFullscreenWindowState: targeted restore — fscv=%d tbTrans=%d",
              win.styleMask.contains(.fullSizeContentView) ? 1 : 0,
              win.titlebarAppearsTransparent ? 1 : 0)
        #endif
        win.styleMask.remove(.fullSizeContentView)
        win.titlebarAppearsTransparent = false
        win.titleVisibility            = .hidden
        win.titlebarSeparatorStyle     = .automatic
        win.isMovableByWindowBackground = false
        setStandardWindowButtonsHidden(false)
        centeredTitleLabel.isHidden = false
        // Reset titlebar view alpha in case it was faded before fullscreen entry.
        titlebarContainerView?.alphaValue = 1.0
        titlebarIsHidden = false
    }

    // MARK: - Layout debug logging
    // Temporary verification helper — logs layout-mode decisions around fullscreen
    // transitions so the real branch chosen by layoutPlayerViews() can be confirmed
    // in the console without requiring interactive visual inspection.

    private func logLayoutSnapshot(_ event: String) {
        #if DEBUG
        guard let win = window, let cv = win.contentView else {
            NSLog("[dwb-layout] %@ | no-window", event)
            return
        }
        let styleMaskFS = win.styleMask.contains(.fullScreen)
        let modeStr: String
        switch layoutMode {
        case .fullscreen:                modeStr = "fullscreen"
        case .exitingFullscreenSettling: modeStr = "exiting-settling"
        case .windowed:                  modeStr = "windowed"
        }
        NSLog("[dwb-layout] %@ | styleFS=%d flags(enter=%d,exit=%d,fs=%d) mode=%@ bounds=%@ clr=%@ transport=%@ video=%@ tFS=%d",
              event,
              styleMaskFS ? 1 : 0,
              isEnteringFullscreen ? 1 : 0,
              isExitingFullscreen  ? 1 : 0,
              isFullscreen         ? 1 : 0,
              modeStr,
              NSStringFromRect(cv.bounds),
              NSStringFromRect(win.contentLayoutRect),
              NSStringFromRect(transport?.frame ?? .zero),
              NSStringFromRect(videoSurface?.frame ?? .zero),
              (transport?.isFullscreenStyle ?? false) ? 1 : 0)
        #endif
    }

    // MARK: - Chrome state debug logging
    // Captures actual NSWindow titlebar/chrome property values at key mutation points.
    // Prefixed [dwb-chrome] to distinguish from [dwb-layout] transport geometry logs.

    private func logChromeState(_ event: String) {
        #if DEBUG
        guard let win = window else {
            NSLog("[dwb-chrome] %@ | no-window", event)
            return
        }
        let fsFlag  = win.styleMask.contains(.fullScreen)
        let fscv    = win.styleMask.contains(.fullSizeContentView)
        let tbTrans = win.titlebarAppearsTransparent
        let tbVisStr: String
        switch win.titleVisibility {
        case .visible:     tbVisStr = "visible"
        case .hidden:      tbVisStr = "hidden"
        @unknown default:  tbVisStr = "unknown(\(win.titleVisibility.rawValue))"
        }
        let tbSepStr: String
        switch win.titlebarSeparatorStyle {
        case .automatic:   tbSepStr = "auto"
        case .none:        tbSepStr = "none"
        case .line:        tbSepStr = "line"
        case .shadow:      tbSepStr = "shadow"
        @unknown default:  tbSepStr = "unknown"
        }
        NSLog("[dwb-chrome] %@ | styleFS=%d fscv=%d tbTrans=%d tbVis=%@ tbSep=%@ flags(enter=%d,exit=%d,fs=%d)",
              event,
              fsFlag  ? 1 : 0,
              fscv    ? 1 : 0,
              tbTrans ? 1 : 0,
              tbVisStr,
              tbSepStr,
              isEnteringFullscreen ? 1 : 0,
              isExitingFullscreen  ? 1 : 0,
              isFullscreen         ? 1 : 0)
        #endif
    }

    private func logPlaybackQueueSnapshot(_ event: String) {
        let order = displayOrder.map(String.init).joined(separator: ",")
        let currentURL = currentMediaURL?.lastPathComponent ?? "—"
        NSLog("[dwb-playback] %@: displayIdx=%d/%d currentSetIdx=%d queueCount=%d displayOrder=[%@] shuffle=%d endless=%d repeat=%d current=%@",
              event,
              currentDisplayIndex,
              displayOrder.count,
              currentSetIndex,
              playbackSet.count,
              order,
              isShuffleOn ? 1 : 0,
              isEndlessShuffleOn ? 1 : 0,
              isRepeatOne ? 1 : 0,
              currentURL)
    }
}

// MARK: - VLCMediaPlayerDelegate

extension PlayerWindowController: VLCMediaPlayerDelegate {

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        guard player === self.player else {
            NSLog("[dwb-playback] state=ignored-stale-player state=%d media=%@",
                  player.state.rawValue,
                  player.media?.url?.lastPathComponent ?? "—")
            return
        }

        // Capture state, position, and media identity on the VLC callback thread.
        // player.state may transition again before main-queue blocks run.
        // player.position may already be reset to 0 by the time .stopped blocks run.
        let capturedState     = player.state
        let capturedPosition  = player.position
        let capturedMediaURL  = player.media?.url
        let capturedMediaName = capturedMediaURL?.lastPathComponent ?? "—"

        // M6: mark transport dirty; the 0.25 s timer is the regular consumer.
        DispatchQueue.main.async { [weak self] in
            self?.needsTransportUpdate = true
        }

        // Debug Console: one line per settled state. Opening and buffering are too chatty.
        let consoleStateName: String? = {
            switch capturedState {
            case .playing: return "playing"
            case .paused:  return "paused"
            case .ended:   return "ended"
            case .stopped: return "stopped"
            case .error:   return "error"
            default:       return nil
            }
        }()
        if let consoleStateName {
            DebugConsoleController.log("playback", "state: \(consoleStateName) pos=\(String(format: "%.3f", capturedPosition)) media=\(capturedMediaName)")
        }

        switch capturedState {

        // ── Informational state transitions (logged for tracing; no action needed) ──

        case .opening:
            #if DEBUG
            NSLog("[dwb-playback] state=opening  media=%@", capturedMediaName)
            #endif

        case .buffering:
            // .buffering can fire many times during a clip; gated to reduce log noise.
            #if DEBUG
            NSLog("[dwb-playback] state=buffering pos=%.3f media=%@", capturedPosition, capturedMediaName)
            #endif

        case .playing:
            #if DEBUG
            NSLog("[dwb-playback] state=playing   pos=%.3f media=%@", capturedPosition, capturedMediaName)
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let intent = self.explicitPlayPauseIntent,
                   intent.target == .play,
                   intent.sessionID == self.currentPlaybackSessionID,
                   intent.mediaURL?.path == capturedMediaURL?.path {
                    self.explicitPlayPauseIntent = nil
                }
                self.updatePlaybackProgressSnapshot(position: capturedPosition)
                if !self.currentItemIsImage {
                    self.acquirePlaybackSleepAssertion(reason: "Video playback")
                }
                // P137: first `.playing` of a start that may have created a new audio output.
                // Consumed here whether or not a correction is needed; the handshake check is
                // the second chance. Pause→resume never arms the flag.
                if self.audioReassertPending,
                   !self.currentItemIsImage,
                   capturedMediaURL?.path == self.currentMediaURL?.path {
                    self.audioReassertPending = false
                    self.reassertWindowAudioIfNeeded(reason: "first-playing")
                }
                guard let handshake = self.playbackStartHandshake else {
                    self.clearCompletionSequence(reason: "state-playing", suppressLog: true)
                    return
                }
                guard handshake.expectedURL.path == capturedMediaURL?.path else { return }
                if !handshake.sawPlaying {
                    var updated = handshake
                    updated.sawPlaying = true
                    // See the matching reset in verifyPlaybackStartHandshake: rebase the
                    // progress baseline here too, since this notification can be the first
                    // place we learn the new item is genuinely playing.
                    updated.baselinePosition = capturedPosition
                    updated.baselineTimeMs = Int(self.player.time.intValue)
                    self.playbackStartHandshake = updated
                    NSLog("[dwb-playback] handshakeFirstPlaying: id=%d reason=%@ media=%@ transition=%@",
                          updated.id,
                          updated.reason,
                          capturedMediaName,
                          updated.transitionStrategy.rawValue)
                }
                self.schedulePlaybackStartHandshakeCheck(for: handshake.id)
            }

        case .paused:
            #if DEBUG
            NSLog("[dwb-playback] state=paused     pos=%.3f media=%@", capturedPosition, capturedMediaName)
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updatePlaybackProgressSnapshot(position: capturedPosition)
                self.releasePlaybackSleepAssertion()
                self.evaluateCompletionWatchdog(source: "paused",
                                                capturedMediaURL: capturedMediaURL,
                                                capturedStoppedPosition: capturedPosition)
            }

        case .ended:
            let posAtEnded = capturedPosition
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let capturedURLName = capturedMediaURL?.lastPathComponent ?? "—"
                let currentURLName = self.currentMediaURL?.lastPathComponent ?? "—"
                if let capturedPath = capturedMediaURL?.path,
                   let currentPath = self.currentMediaURL?.path,
                   capturedPath != currentPath {
                    NSLog("[dwb-playback] .ended: capturedURL=%@ currentURL=%@ position=%.3f accepted=0 reason=stale-url-mismatch",
                          capturedURLName,
                          currentURLName,
                          posAtEnded)
                    return
                }
                // VLC reports an unplayable file (corrupt/truncated/missing moov) as .ended at
                // position 0 while the start handshake is still unconfirmed. That is not a
                // natural EOF: marking it as one makes the failure path reject the item as
                // "stale-or-user-stop", so the queue never advances. Leave it to the handshake,
                // which reports the failure once its retries are exhausted.
                if let handshake = self.playbackStartHandshake,
                   handshake.expectedSessionID == self.currentPlaybackSessionID,
                   handshake.expectedURL.path == (capturedMediaURL ?? self.currentMediaURL)?.path {
                    NSLog("[dwb-playback] .ended: capturedURL=%@ position=%.3f accepted=0 reason=start-handshake-unconfirmed",
                          capturedURLName,
                          posAtEnded)
                    return
                }
                self.naturalEOFDetected   = true
                self.positionAtEndedEvent = posAtEnded
                self.lastStoppedMT = CACurrentMediaTime()   // M1
                self.lastStoppedPosition = max(self.lastStoppedPosition, posAtEnded)
                self.lastStoppedMediaURL = capturedMediaURL ?? self.currentMediaURL
                NSLog("[dwb-playback] .ended: capturedURL=%@ currentURL=%@ position=%.3f accepted=1",
                      capturedURLName,
                      currentURLName,
                      posAtEnded)
                NSLog("[dwb-playback] .ended: naturalEOFDetected=1 posAtEnded=%.3f displayIdx=%d/%d repeat=%d shuffle=%d endless=%d hasNext=%d media=%@ session=%d",
                      posAtEnded,
                      self.currentDisplayIndex, self.displayOrder.count,
                      self.isRepeatOne ? 1 : 0,
                      self.isShuffleOn ? 1 : 0,
                      self.isEndlessShuffleOn ? 1 : 0,
                      self.hasNext ? 1 : 0,
                      capturedMediaName,
                      self.currentPlaybackSessionID)
                self.logPlaybackQueueSnapshot(".ended")
                self.evaluateCompletionWatchdog(source: "ended",
                                                capturedMediaURL: capturedMediaURL,
                                                capturedStoppedPosition: posAtEnded)
            }

        case .stopped:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.releasePlaybackSleepAssertion()

                let nowMT = CACurrentMediaTime()   // M1: monotonic sample
                let suppressAge: TimeInterval = self.suppressNextStoppedMT > 0 ? nowMT - self.suppressNextStoppedMT : -1.0
                let suppressFresh = self.suppressNextStopped &&
                    suppressAge >= 0 &&
                    suppressAge < self.replacementStopSuppressionWindow
                let recentSeekAge: TimeInterval = self.lastUserSeekMT > 0 ? nowMT - self.lastUserSeekMT : -1.0
                let recentSeek = recentSeekAge >= 0 && recentSeekAge < self.userSeekEOFGuardWindow
                self.lastStoppedMT = nowMT
                self.lastStoppedPosition = max(self.lastStoppedPosition, capturedPosition)
                self.lastStoppedMediaURL = capturedMediaURL ?? self.currentMediaURL

                #if DEBUG
                NSLog("[dwb-playback] .stopped: userStop=%d suppress=%d naturalEOF=%d lastPos=%.3f capPos=%.3f posAtEnded=%.3f timeMs=%d durationMs=%d recentSeek=%d(%.2fs) suppressAge=%.2fs suppressFresh=%d displayIdx=%d/%d shuffle=%d endless=%d repeat=%d hasNext=%d media=%@ session=%d completionSeq=%d",
                      self.isUserStop          ? 1 : 0,
                      self.suppressNextStopped ? 1 : 0,
                      self.naturalEOFDetected  ? 1 : 0,
                      self.lastKnownPosition,
                      capturedPosition,
                      self.positionAtEndedEvent,
                      self.lastKnownTimeMs,
                      self.lastKnownDurationMs,
                      recentSeek ? 1 : 0,
                      max(0.0, recentSeekAge),
                      max(0.0, suppressAge),
                      suppressFresh ? 1 : 0,
                      self.currentDisplayIndex, self.displayOrder.count,
                      self.isShuffleOn ? 1 : 0,
                      self.isEndlessShuffleOn ? 1 : 0,
                      self.isRepeatOne ? 1 : 0,
                      self.hasNext ? 1 : 0,
                      capturedMediaName,
                      self.currentPlaybackSessionID,
                      self.activeCompletionSequence?.id ?? 0)
                #endif

                if self.isUserStop {
                    self.isUserStop = false
                    self.resetPlaybackCompletionSignals(reason: "stopped-user-stop")
                    NSLog("[dwb-playback] completionDecision: source=stopped action=%@ media=%@",
                          PlaybackCompletionAction.ignoredUserStop.rawValue,
                          capturedMediaName)
                    return
                }

                if suppressFresh && self.replacementStartWorkItem != nil {
                    self.clearStoppedSuppression()
                    NSLog("[dwb-playback] .stopped: reasonCode=replacement-suppressed media=%@",
                          capturedMediaName)
                    return
                }

                if self.suppressNextStopped {
                    NSLog("[dwb-playback] .stopped: suppression flag present (age=%.2fs fresh=%d) — clearing stale suppression if needed",
                          max(0.0, suppressAge),
                          suppressFresh ? 1 : 0)
                    if !suppressFresh || self.replacementStartWorkItem == nil {
                        self.clearStoppedSuppression()
                    }
                }

                self.evaluateCompletionWatchdog(source: "stopped",
                                                capturedMediaURL: capturedMediaURL,
                                                capturedStoppedPosition: capturedPosition)
            }

        case .error:
            let failedURL = capturedMediaURL
            let filename = failedURL?.lastPathComponent ?? "unknown file"
            let failedSessionID = currentPlaybackSessionID
            NSLog("[dwb-playback] state=error   media=%@ session=%d", filename, failedSessionID)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.releasePlaybackSleepAssertion()
                if let failedURL {
                    self.schedulePlaybackFailureAutoSkip(
                        failedURL: failedURL,
                        failedSessionID: failedSessionID,
                        source: "vlc-error",
                        detail: "vlc-error: \(failedURL.lastPathComponent) session=\(failedSessionID) route=direct")
                } else if let trackedURL = self.currentMediaURL,
                          failedSessionID == self.currentPlaybackSessionID {
                    // player.media can already be nil by the time .error is delivered — this
                    // happens even after a start handshake already cleared itself as a success
                    // (e.g. a corrupt file reports brief initial progress before VLC gives up).
                    // Identify the failed attempt from tracked session/media state rather than
                    // requiring a still-active handshake, or the failure is silently dropped and
                    // playback stalls on the broken item indefinitely.
                    NSLog("[dwb-playback] state=error media=— session=%d route=current-tracked-media target=%@ activeHandshake=%d",
                          failedSessionID,
                          trackedURL.lastPathComponent,
                          self.playbackStartHandshake != nil ? 1 : 0)
                    self.schedulePlaybackFailureAutoSkip(
                        failedURL: trackedURL,
                        failedSessionID: failedSessionID,
                        source: "vlc-error-no-media",
                        detail: "vlc-error: \(trackedURL.lastPathComponent) session=\(failedSessionID) route=current-tracked-media")
                } else {
                    NSLog("[dwb-playback] state=error media=— session=%d ignored=no-current-attempt-identity",
                          failedSessionID)
                }
            }

        default:
            #if DEBUG
            NSLog("[dwb-playback] state=other(%d) pos=%.3f media=%@",
                  capturedState.rawValue, capturedPosition, capturedMediaName)
            #endif
        }
    }
}

// MARK: - QueuePageViewDelegate

extension PlayerWindowController: QueuePageViewDelegate {

    func queuePage(_ view: QueuePageView, didSelectDisplayIndex index: Int) {
        DebugConsoleController.log("queue", "select: displayIdx=\(index) source=queuePage")
        currentDisplayIndex = index
        playCurrentItem(startReason: "queue-page-select")
    }

    func queuePage(_ view: QueuePageView, didRequestRenameAt index: Int) {
        showRenameSheet(forDisplayIndex: index)
    }

    /// One-click custom prefix rename. Applies toggle/swap policy to all targets (multi-select safe).
    func queuePage(_ view: QueuePageView, didRequestCustomPrefixRenameAt indices: [Int]) {
        applyPrefix(indices: indices, invokedPrimary: true)
    }

    func queuePage(_ view: QueuePageView, didRequestSecondaryCustomPrefixRenameAt indices: [Int]) {
        applyPrefix(indices: indices, invokedPrimary: false)
    }

    /// The single function behind the footer chips, the `N`/`M` keys and the rail buttons.
    private func applyPrefix(indices: [Int], invokedPrimary: Bool) {
        let primary   = SettingsWindowController.customPrefixValue()
        let secondary = SettingsWindowController.customPrefixSecondaryValue()
        let tag = invokedPrimary ? "customPrefix" : "customPrefixSecondary"
        guard !(invokedPrimary ? primary : secondary).isEmpty else {
            DebugConsoleController.log("rename", "\(tag): noop (empty prefix)")
            return
        }
        performQueuePagePrefixRename(indices: indices, primary: primary, secondary: secondary,
                                     invokedPrimary: invokedPrimary, tag: tag)
    }

    /// Shared implementation for queue-page prefix rename (primary and secondary).
    ///
    /// Applies the toggle/swap prefix-transition policy to each target independently.
    /// Single-file renames proceed immediately; multi-file renames require confirmation.
    private func performQueuePagePrefixRename(indices: [Int], primary: String, secondary: String, invokedPrimary: Bool, tag: String) {
        guard let win = window else { return }

        // Resolve display indices to (pbIdx, url) pairs.
        var targets: [(pbIdx: Int, url: URL)] = []
        for displayIdx in indices {
            guard displayIdx >= 0, displayIdx < displayOrder.count else { continue }
            let pbIdx = displayOrder[displayIdx]
            guard pbIdx >= 0, pbIdx < playbackSet.count else { continue }
            targets.append((pbIdx: pbIdx, url: playbackSet[pbIdx]))
        }
        guard !targets.isEmpty else { return }

        // Apply the toggle/swap transition to each target independently.
        // Items where calculatePrefixTransition returns nil are no-ops (no change needed).
        let pendingRenames: [(pbIdx: Int, oldName: String, newName: String)] = targets.compactMap { target in
            guard let newName = MediaFileSupport.calculatePrefixTransition(
                originalURL: target.url, primary: primary, secondary: secondary, invokedPrimary: invokedPrimary
            ) else { return nil }
            return (pbIdx: target.pbIdx, oldName: target.url.lastPathComponent, newName: newName)
        }

        guard !pendingRenames.isEmpty else {
            DebugConsoleController.log("rename", "\(tag): all targets unchanged by transition, noop source=queuePage")
            return
        }

        // Preflight: verify sources exist and destinations don't collide.
        var seenDestinationPaths = Set<String>()
        for r in pendingRenames {
            guard r.pbIdx < playbackSet.count else { continue }
            let url = playbackSet[r.pbIdx]
            guard FileManager.default.fileExists(atPath: url.path) else {
                presentRenameAlert(title: "Cannot Rename",
                                   message: "The file \"\(r.oldName)\" could not be found. No files were renamed.",
                                   window: win)
                return
            }
            let dir = url.deletingLastPathComponent()
            let destURL = dir.appendingPathComponent(r.newName, isDirectory: false)
            let destKey = destURL.standardizedFileURL.path
            if !seenDestinationPaths.insert(destKey).inserted {
                presentRenameAlert(title: "Cannot Rename",
                                   message: "Two selected files would produce the same destination name \"\(r.newName)\". No files were renamed.",
                                   window: win)
                return
            }
            if FileManager.default.fileExists(atPath: destURL.path) {
                presentRenameAlert(title: "Cannot Rename",
                                   message: "A file named \"\(r.newName)\" already exists. No files were renamed.",
                                   window: win)
                return
            }
        }

        let undoEntries = pendingRenames.compactMap { rename -> MarkerRenameUndoEntry? in
            guard rename.pbIdx >= 0, rename.pbIdx < playbackSet.count else { return nil }
            let originalURL = playbackSet[rename.pbIdx]
            return MarkerRenameUndoEntry(
                originalURL: originalURL,
                renamedURL: originalURL.deletingLastPathComponent().appendingPathComponent(rename.newName)
            )
        }
        guard undoEntries.count == pendingRenames.count else { return }

        if pendingRenames.count == 1 {
            // Single-file fast path: no confirmation required.
            let r = pendingRenames[0]
            DebugConsoleController.log("rename",
                "\(tag): \(r.oldName) → \(r.newName) source=queuePage")
            if renameFile(at: r.pbIdx, to: r.newName) {
                recordMarkerRename(entries: undoEntries)
            }
        } else {
            // Multi-file: show confirmation before any filesystem mutation.
            let invokedPrefix = invokedPrimary ? primary : secondary
            let previewRenames = pendingRenames.map { (old: $0.oldName, new: $0.newName) }
            DWBBatchRenameSheet.present(
                on: win,
                prefix: invokedPrefix,
                isPrimary: invokedPrimary,
                primaryPrefix: primary,
                secondaryPrefix: secondary,
                renames: previewRenames
            ) { [weak self] in
                guard let self = self else { return }
                var allRenamesSucceeded = true
                for r in pendingRenames {
                    guard r.pbIdx < self.playbackSet.count else { continue }
                    DebugConsoleController.log("rename",
                        "\(tag): \(r.oldName) → \(r.newName) source=queuePage confirmed")
                    if !self.renameFile(at: r.pbIdx, to: r.newName) {
                        allRenamesSucceeded = false
                        break
                    }
                }
                if allRenamesSucceeded {
                    self.recordMarkerRename(entries: undoEntries)
                }
            }
        }
    }

    /// Multi-row deletion from Queue Page keyboard delete. Indices are pre-sorted descending.
    func queuePage(_ view: QueuePageView, didRequestDeleteRows indices: [Int]) {
        let plan = QueueDisplayProjection.deletionPlan(
            itemCount: displayOrder.count,
            currentDisplayIndex: currentDisplayIndex,
            requestedDisplayIndices: indices
        )
        for index in plan.descendingDisplayIndices {
            removeQueueItem(displayIndex: index)
        }
    }

    func queuePage(_ view: QueuePageView, didRequestRevealAt index: Int) {
        revealInFinder(displayIndex: index)
    }

    func queuePage(_ view: QueuePageView, didRequestDeleteAt index: Int) {
        removeQueueItem(displayIndex: index)
    }

    func queuePage(_ view: QueuePageView, didChangeSortMode mode: QueueSortMode) {
        queueSortMode = mode
        queueSortOrderFrozenAfterRename = false
        if mode != .manual {
            isShuffleOn = false
            isEndlessShuffleOn = false
        }
        DebugConsoleController.log("queue", "sort: mode=\(mode.title)")
        applyQueueSortIfNeeded(reason: "queue-page-sort-change")
        logPlaybackQueueSnapshot("queueSortChange")
    }

    func queuePageDidRequestClose(_ view: QueuePageView) {
        isQueuePageOpen = false
        layoutPlayerViews()
        transport.update()
    }

    func queuePageDidRequestAddMedia(_ view: QueuePageView) {
        openFile()
    }

    func queuePageDidRequestRescan(_ view: QueuePageView) {
        guard window != nil else { return }

        // Determine folders to scan: explicit tracked folders, else fallback to parent dirs of queue items.
        var foldersToScan: [URL] = sourceFolderURLs
        if foldersToScan.isEmpty {
            var seenPaths = Set<String>()
            for url in playbackSet where url.isFileURL {
                let parent = url.deletingLastPathComponent()
                let path = parent.standardizedFileURL.path
                if seenPaths.insert(path).inserted {
                    foldersToScan.append(parent)
                }
            }
        }

        guard !foldersToScan.isEmpty else {
            presentIntakeFailure(
                .sourceUnavailable(
                    name: nil,
                    diagnostic: "No source folder is associated with this queue. Locate a folder or add media to continue."
                ),
                sourceURLs: [],
                retryContext: .rescan(folders: [])
            )
            return
        }

        startAsyncFolderRescan(foldersToScan: foldersToScan,
                               acceptedKinds: SettingsWindowController.acceptedMediaKinds())
    }

    private func startAsyncFolderRescan(foldersToScan: [URL],
                                        acceptedKinds: Set<MediaFileSupport.MediaKind>) {
        guard !acceptedKinds.isEmpty else {
            presentIntakeFailure(
                .mediaKindsDisabled,
                sourceURLs: foldersToScan,
                retryContext: .rescan(folders: foldersToScan)
            )
            return
        }
        let generation = beginFolderScanOperation()
        presentIntakeScanning(
            folderCount: foldersToScan.count,
            sourceURLs: foldersToScan,
            retryContext: .rescan(folders: foldersToScan)
        )
        DebugConsoleController.log("rescan", "rescanAsync: start folders=\(foldersToScan.count)")

        folderScanTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                var freshURLs: [URL] = []
                var freshPaths = Set<String>()
                for folder in foldersToScan {
                    guard !Task.isCancelled else { throw CancellationError() }
                    let files = try MediaFileSupport.sortedSupportedFiles(
                        inFolder: folder,
                        acceptedKinds: acceptedKinds,
                        shouldCancel: { Task.isCancelled }
                    )
                    for url in files {
                        let path = url.standardizedFileURL.path
                        if freshPaths.insert(path).inserted {
                            freshURLs.append(url)
                        }
                    }
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.folderScanGeneration == generation else { return }
                    self.folderScanTask = nil
                    if freshURLs.isEmpty {
                        self.presentIntakeFailure(
                            .emptyFolders(names: foldersToScan.map(\.lastPathComponent)),
                            sourceURLs: foldersToScan,
                            retryContext: .rescan(folders: foldersToScan)
                        )
                    } else {
                        self.applyFolderRescan(freshURLs: freshURLs, freshPaths: freshPaths)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard let self, self.folderScanGeneration == generation else { return }
                    self.folderScanTask = nil
                    DebugConsoleController.log(level: .error,
                                               category: "rescan",
                                               message: "rescanAsync failed: \(error.localizedDescription)")
                    let unavailable = foldersToScan.first { !FileManager.default.fileExists(atPath: $0.path) }
                    let failure: MediaIntakeFailure = unavailable.map {
                        .sourceUnavailable(name: $0.lastPathComponent, diagnostic: error.localizedDescription)
                    } ?? .folderScanFailed(name: nil, diagnostic: error.localizedDescription)
                    self.presentIntakeFailure(
                        failure,
                        sourceURLs: foldersToScan,
                        retryContext: .rescan(folders: foldersToScan)
                    )
                }
            }
        }
    }

    private func applyFolderRescan(freshURLs: [URL],
                                   freshPaths: Set<String>) {
        clearIntakeRecovery()
        // Capture the currently playing URL before modifying state.
        let playingURL: URL? = currentSetIndex >= 0 && currentSetIndex < playbackSet.count
            ? playbackSet[currentSetIndex]
            : nil
        let playingPath = playingURL?.standardizedFileURL.path

        // Walk current display order: keep items still present on disk, plus the currently
        // playing item even if it has been removed from disk (preserves active playback).
        var newURLs: [URL] = []
        var newURLPaths = Set<String>()
        for pbIdx in displayOrder {
            guard pbIdx >= 0, pbIdx < playbackSet.count else { continue }
            let url = playbackSet[pbIdx]
            let path = url.standardizedFileURL.path
            if freshPaths.contains(path) || path == playingPath {
                if newURLPaths.insert(path).inserted {
                    newURLs.append(url)
                }
            }
        }

        // Append files now present in folder but not already in the new set.
        for url in freshURLs {
            let path = url.standardizedFileURL.path
            if newURLPaths.insert(path).inserted {
                newURLs.append(url)
            }
        }

        // Compute feedback counts before modifying state.
        let originalPaths = Set(playbackSet.map { $0.standardizedFileURL.path })
        let addedCount = freshPaths.subtracting(originalPaths).count
        let removedCount = originalPaths.subtracting(freshPaths).filter { $0 != playingPath }.count

        // Locate new display index for the currently playing item.
        let newCurrentDisplayIndex: Int
        if let playingPath = playingPath,
           let idx = newURLs.firstIndex(where: { $0.standardizedFileURL.path == playingPath }) {
            newCurrentDisplayIndex = idx
        } else {
            newCurrentDisplayIndex = newURLs.isEmpty ? -1 : max(0, min(currentDisplayIndex, newURLs.count - 1))
        }

        // Prune duration caches for removed entries.
        let newPathSet = newURLPaths
        durationCache = durationCache.filter { newPathSet.contains($0.key.standardizedFileURL.path) }
        durationSecondsCache = durationSecondsCache.filter { newPathSet.contains($0.key.standardizedFileURL.path) }
        gifDurations.retain(paths: newPathSet, dropUnreadable: true)
        updateGIFIntakeProgress { $0.retain(paths: newPathSet) }
        reportedDurations.retain(paths: newPathSet)
        nonLocalFiles.retain(paths: newPathSet)

        // Apply new queue state (does not touch playback).
        playbackSet = newURLs
        displayOrder = Array(0..<newURLs.count)
        pendingPlayNextSetIndices.removeAll()
        currentDisplayIndex = newCurrentDisplayIndex

        applyQueueSortIfNeeded(reason: "rescan")
        if isQueuePageOpen { refreshQueuePage() }

        DebugConsoleController.log("rescan", "rescan: added=\(addedCount) removed=\(removedCount) total=\(newURLs.count)")
    }

    /// Row drag-and-drop reorder from Queue Page.
    ///
    /// `from` is the dragged row's index; `to` is the insertion point (0…n, .above semantics).
    /// The manual reorder becomes the authoritative playback order.
    /// If shuffle is ON it is disabled: the explicit manual order replaces the shuffled order.
    /// Remove All: stop any current playback, clear the entire queue, and refresh the UI.
    ///
    /// Playback decision: current media is stopped (same as user-initiated stop) and the
    /// queue becomes empty.  The player does not attempt to advance.  This matches the
    /// expectation that "remove all" means an intentional clean slate.
    func queuePageDidRequestRemoveAll(_ view: QueuePageView) {
        removeAllQueueItems(source: "queuePage")
    }

    /// Footer Undo: the same undo as Command-Z.
    func queuePage(_ view: QueuePageView, didRequestPrefixKeyAction action: PrefixKeyRouting.Action) {
        performPrefixAction(action, source: "queueTable-key")
    }

    func queuePageDidRequestUndoMarkerRename(_ view: QueuePageView) {
        undoLastMarkerRename()
    }

    func queuePage(_ view: QueuePageView, didReorderFromIndex from: Int, toIndex to: Int) {
        guard from >= 0, from < displayOrder.count,
              to >= 0, to <= displayOrder.count else { return }
        // No-op drops (same position or directly below source)
        guard from != to, from != to - 1 else { return }

        // Save the current playback-set index so we can track it through the reorder
        let curSetIdx = currentSetIndex

        // Disable shuffle — manual reorder takes over as the authoritative order
        if isShuffleOn { isShuffleOn = false }
        if curSetIdx >= 0 {
            NSLog("[dwb-playback] queueReorder: manual order wins; from=%d to=%d currentSetIdx=%d",
                  from, to, curSetIdx)
        }

        // Perform the move in displayOrder
        let movedItem = displayOrder.remove(at: from)
        // After removing, the insertion index shifts down by 1 if to > from
        let insertAt = to > from ? to - 1 : to
        displayOrder.insert(movedItem, at: insertAt)
        pendingPlayNextSetIndices.removeAll()

        // Restore currentDisplayIndex to keep pointing at the same item
        if curSetIdx >= 0, let newIdx = displayOrder.firstIndex(of: curSetIdx) {
            currentDisplayIndex = newIdx
        }

        queueSortMode = .manual
        DebugConsoleController.log("queue", "reorder: from=\(from) to=\(to)")
        refreshQueueDisplays()
        logPlaybackQueueSnapshot("queueReorder")
    }

    /// Appends the entry at `displayIndex` to the pending Play Next chain (FIFO).
    ///
    /// Semantics:
    ///   - First Play Next item becomes the immediate next item.
    ///   - Subsequent Play Next selections append after the last pending item (FIFO).
    ///   - Items already in the pending chain or currently playing are safe no-ops.
    ///   - The current playing media identity and playback are uninterrupted.
    func queuePage(_ view: QueuePageView, didRequestPlayNextAt displayIndex: Int) {
        guard currentDisplayIndex >= 0,
              displayIndex >= 0, displayIndex < displayOrder.count,
              displayIndex != currentDisplayIndex else { return }

        let curSetIdx = currentSetIndex

        NSLog("[dwb-playback] playNext: displayIdx=%d currentDisplayIdx=%d currentSetIdx=%d pendingCount=%d",
              displayIndex, currentDisplayIndex, curSetIdx, pendingPlayNextSetIndices.count)

        let changed = PlayNextChainPolicy.applyPlayNext(
            targetDisplayIndex: displayIndex,
            displayOrder: &displayOrder,
            currentDisplayIndex: &currentDisplayIndex,
            pendingSetIndices: &pendingPlayNextSetIndices
        )

        guard changed else { return }

        queueSortMode = .manual
        DebugConsoleController.log("queue",
            "playNext: moved displayIdx=\(displayIndex) chainCount=\(pendingPlayNextSetIndices.count)")
        refreshQueueDisplays()
        logPlaybackQueueSnapshot("queuePlayNext")
    }
}
