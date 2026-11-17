import Cocoa

private enum MediaDropRouting {
    static func readDroppedURLs(from sender: NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard
                .readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return nil }
        return urls
    }

    static func isValidDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = readDroppedURLs(from: sender) else { return false }
        return urls.contains { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue || MediaFileSupport.isSupported(url)
        }
    }

    /// Counts the droppable items so the drop zone can say how many will be added.
    static func dropSummary(from sender: NSDraggingInfo) -> (fileCount: Int, folderCount: Int) {
        guard let urls = readDroppedURLs(from: sender) else { return (0, 0) }
        var files = 0
        var folders = 0
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                folders += 1
            } else if MediaFileSupport.isSupported(url) {
                files += 1
            }
        }
        return (files, folders)
    }

    /// The drop zone lives in the player window, above the rail, so both the
    /// video and image surfaces drive the same overlay.
    static func setDropZoneVisible(_ visible: Bool,
                                   summary: (fileCount: Int, folderCount: Int)? = nil,
                                   in window: NSWindow?) {
        guard let wc = window?.windowController as? PlayerWindowController else { return }
        if visible, let summary {
            wc.showDropZone(fileCount: summary.fileCount, folderCount: summary.folderCount)
        } else {
            wc.hideDropZone()
        }
    }

    static func performDrop(_ sender: NSDraggingInfo, in window: NSWindow?) -> Bool {
        guard let urls = readDroppedURLs(from: sender),
              let wc = window?.windowController as? PlayerWindowController else { return false }
        wc.handleDroppedURLs(urls, appendingExplicitFiles: true, isDragDrop: true)
        return true
    }
}

/// The NSView into which VLCMediaPlayer renders its video output.
/// Background is black. Scroll wheel adjusts volume (0–200), clamped.
/// Double-click toggles fullscreen. Accepts file/folder drops (single or multi).
/// The transport keys (Space, the arrows and the others in the command table) drive playback when this view is first responder.
class VideoSurfaceView: NSView {

    private var isDragHighlighted = false

    /// Timer that fires repeated configured-duration seeks while Left/Right Arrow is held.
    /// Nil when no key is held.
    private var seekTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used – UI is programmatic")
    }

    override var acceptsFirstResponder: Bool { true }
    // L1: full-bleed black/video host — no transparency needed.
    override var isOpaque: Bool { true }

    // MARK: - Keyboard transport
    //
    // Which key runs which command comes from the command table (`ShortcutRegistry`), not from
    // this file. A key that carries a menu item (for example ⌘↑ or ⌥←) runs from the menu and
    // never reaches this handler; every other key runs here when this view owns first-responder
    // focus, so not when a text field or other control is active.

    /// The key code of the arrow key that started the current hold-to-seek, so releasing
    /// that key (and no other) stops it.
    private var seekKeyCode: UInt16?

    override func keyDown(with event: NSEvent) {
        guard let wc = window?.windowController as? PlayerWindowController else {
            super.keyDown(with: event)
            return
        }
        let handled = PlayerKeyDispatch.handle(event,
                                               surface: .video,
                                               controller: wc,
                                               isEditingText: window?.firstResponder is NSText) { [weak self, weak wc] backward in
            guard let self, let wc else { return }
            self.seekTimer?.invalidate()
            self.seekKeyCode = event.keyCode
            if backward { wc.skipBackward10() } else { wc.skipForward10() }
            self.scheduleSeekRepeat(backward: backward, controller: wc)
        }
        if !handled { super.keyDown(with: event) }
    }

    /// Cancel the hold-to-seek timer the moment the key that started it is released.
    override func keyUp(with event: NSEvent) {
        if let seekKeyCode, event.keyCode == seekKeyCode {
            seekTimer?.invalidate()
            seekTimer = nil
            self.seekKeyCode = nil
        } else {
            super.keyUp(with: event)
        }
    }

    /// Start a two-phase timer for smooth hold-to-seek:
    ///   Phase 1 — 350 ms initial delay (avoids spurious repeat on quick taps)
    ///   Phase 2 — 80 ms repeating interval (smooth continued seeking)
    private func scheduleSeekRepeat(backward: Bool, controller: PlayerWindowController) {
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self, weak controller] _ in
            guard let self = self, let wc = controller else { return }
            self.seekTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak wc] _ in
                if backward { wc?.skipBackward10() } else { wc?.skipForward10() }
            }
        }
    }

    // MARK: - Scroll / Volume

    /// Vertical scroll adjusts volume. Scroll down = louder, scroll up = quieter
    /// (reversed from natural direction per user preference).
    override func scrollWheel(with event: NSEvent) {
        guard let wc = window?.windowController as? PlayerWindowController else {
            super.scrollWheel(with: event)
            return
        }
        // Negate deltaY: scroll up (positive deltaY with natural scrolling) → quieter
        let delta = Int(-event.deltaY * 5.0)
        wc.adjustVolume(by: delta)
    }

    // MARK: - Double-click fullscreen

    override func mouseDown(with event: NSEvent) {
        // Clicking the video area makes it first responder so keyboard events land here
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        }
        super.mouseDown(with: event)
    }

    // MARK: - Drag highlight

    private func setDragHighlight(_ on: Bool, sender: NSDraggingInfo? = nil) {
        guard isDragHighlighted != on else { return }
        isDragHighlighted = on
        MediaDropRouting.setDropZoneVisible(on,
                                            summary: sender.map { MediaDropRouting.dropSummary(from: $0) },
                                            in: window)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isValidDrop(sender) else { return [] }
        setDragHighlight(true, sender: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isValidDrop(sender) else {
            setDragHighlight(false)
            return []
        }
        setDragHighlight(true, sender: sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDragHighlight(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDragHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlight(false)
        return MediaDropRouting.performDrop(sender, in: window)
    }

    private func isValidDrop(_ sender: NSDraggingInfo) -> Bool {
        MediaDropRouting.isValidDrop(sender)
    }
}

final class ImageSurfaceView: NSImageView {
    private var isDragHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used – UI is programmatic")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // The video surface is hidden while an image shows, so a click here must take
        // focus or the keys below never arrive.
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            window?.toggleFullScreen(nil)
        }
        super.mouseDown(with: event)
    }

    /// The same keys as `VideoSurfaceView.keyDown`, so an image or GIF on screen answers
    /// the keyboard like a video. Arrows step once per press: the hold-to-seek timer is
    /// video-only.
    override func keyDown(with event: NSEvent) {
        guard let wc = window?.windowController as? PlayerWindowController else {
            super.keyDown(with: event)
            return
        }
        let handled = PlayerKeyDispatch.handle(event,
                                               surface: .image,
                                               controller: wc,
                                               isEditingText: window?.firstResponder is NSText)
        if !handled { super.keyDown(with: event) }
    }

    private func setDragHighlight(_ on: Bool, sender: NSDraggingInfo? = nil) {
        guard isDragHighlighted != on else { return }
        isDragHighlighted = on
        MediaDropRouting.setDropZoneVisible(on,
                                            summary: sender.map { MediaDropRouting.dropSummary(from: $0) },
                                            in: window)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard MediaDropRouting.isValidDrop(sender) else { return [] }
        setDragHighlight(true, sender: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard MediaDropRouting.isValidDrop(sender) else {
            setDragHighlight(false)
            return []
        }
        setDragHighlight(true, sender: sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDragHighlight(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDragHighlight(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlight(false)
        return MediaDropRouting.performDrop(sender, in: window)
    }
}
