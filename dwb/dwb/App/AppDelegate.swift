import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {

    private let maxPlayerWindowCount = 5

    var windowControllers: [PlayerWindowController] = []
    private weak var rewindMenuItem: NSMenuItem?
    private weak var forwardMenuItem: NSMenuItem?
    private weak var audioSyncStatusMenuItem: NSMenuItem?
    private var hasReceivedOpenEventDuringLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        DWBAppearance.shared.start()
        SettingsWindowController.registerDefaults()
        _ = DebugConsoleController.shared   // eagerly init so it observes settings from launch
        buildMainMenu()
        observeSettings()
        updateSkipMenuItemTitles()
        openInitialPlayerWindowIfNeeded()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        DebugConsoleController.log("app", "launched: version=\(version) build=\(build) pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugConsoleController.log("app", "terminating")
    }

    /// Closing the last player window leaves the app running in the Dock (D-003, P136).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        openSubmittedURLs(urls, source: "openFiles")
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openSubmittedURLs([URL(fileURLWithPath: filename)], source: "openFile")
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openSubmittedURLs(urls, source: "openURLs")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pruneClosedPlayerWindowControllers()
        // After Command-H every window reads as not visible. Unhiding brings the
        // existing windows back, so a hidden window still counts as on screen here.
        let appWasHidden = sender.isHidden
        if appWasHidden {
            sender.unhide(nil)
        }
        let snapshots = windowControllers.map { $0.targetingSnapshot(treatHiddenAsOnScreen: appWasHidden) }
        let choice = PlayerWindowTargeting.reopenChoice(windows: snapshots)
        let controller: (ObjectIdentifier) -> PlayerWindowController? = { id in
            self.windowControllers.first { ObjectIdentifier($0) == id }
        }

        switch choice {
        case .bringForward(let id):
            controller(id)?.window?.makeKeyAndOrderFront(nil)
        case .restoreMinimized(let id):
            controller(id)?.window?.deminiaturize(nil)
            controller(id)?.window?.makeKeyAndOrderFront(nil)
        case .openNewWindow:
            _ = openNewPlayerWindow()
        }
        DebugConsoleController.log("window", "dockReopen: choice=\(Self.reopenChoiceDescription(choice)) hidden=\(appWasHidden) windows=\(windowControllers.count)")

        sender.activate(ignoringOtherApps: true)
        return false
    }

    private static func reopenChoiceDescription(_ choice: PlayerWindowTargeting.ReopenChoice<ObjectIdentifier>) -> String {
        switch choice {
        case .bringForward: return "bring-forward"
        case .restoreMinimized: return "restore-minimized"
        case .openNewWindow: return "new-window"
        }
    }

    // MARK: - Window management

    @discardableResult
    func openNewPlayerWindow() -> PlayerWindowController? {
        pruneClosedPlayerWindowControllers()
        guard windowControllers.count < maxPlayerWindowCount else {
            presentWindowCapDenial(context: "new-window")
            return nil
        }
        let wc = PlayerWindowController()
        // Cascade from the most recently opened window so new windows don't
        // stack exactly on top of existing ones.  cascadeTopLeft(from:) uses
        // AppKit's standard bottom-left origin screen coordinates; the "top-left"
        // of a window is (frame.minX, frame.maxY).
        if let prevWindow = windowControllers.last?.window {
            wc.window?.cascadeTopLeft(from: NSPoint(x: prevWindow.frame.minX,
                                                    y: prevWindow.frame.maxY))
        }
        wc.showWindow(nil)
        windowControllers.append(wc)
        return wc
    }

    private func openInitialPlayerWindowIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  !self.hasReceivedOpenEventDuringLaunch,
                  self.usablePlayerWindowController() == nil else { return }
            _ = self.openNewPlayerWindow()
        }
    }

    private func openSubmittedURLs(_ urls: [URL], source: String) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        hasReceivedOpenEventDuringLaunch = true

        guard let wc = usablePlayerWindowController() ?? openNewPlayerWindow() else { return }
        wc.window?.deminiaturize(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSLog("[dwb-open] source=%@ count=%d files=%@",
              source,
              fileURLs.count,
              fileURLs.map(\.lastPathComponent).joined(separator: ","))

        // Native Finder/Dock open events are explicit external submissions, so
        // use the same queue-top insertion semantics as an explicit file drop.
        wc.handleDroppedURLs(fileURLs, appendingExplicitFiles: true)
        noteRecentDocumentURLs(from: fileURLs)
    }

    private func usablePlayerWindowController() -> PlayerWindowController? {
        if let wc = NSApp.keyWindow?.windowController as? PlayerWindowController,
           wc.window?.isVisible == true {
            return wc
        }
        if let wc = NSApp.mainWindow?.windowController as? PlayerWindowController,
           wc.window?.isVisible == true {
            return wc
        }
        for window in NSApp.orderedWindows {
            if let wc = window.windowController as? PlayerWindowController,
               window.isVisible {
                return wc
            }
        }
        return windowControllers.last { $0.window?.isVisible == true }
    }

    private func pruneClosedPlayerWindowControllers() {
        windowControllers.removeAll { $0.window == nil }
    }

    private func presentWindowCapDenial(context: String) {
        DebugConsoleController.log(level: .warning,
                                   category: "window",
                                   message: "windowCapDenied: context=\(context) cap=\(maxPlayerWindowCount) current=\(windowControllers.count)")
        let content = StatusHUDContent.windowLimit(maxWindows: maxPlayerWindowCount)
        // The non-modal status HUD on the key player window, never an alert.
        if let wc = usablePlayerWindowController() {
            wc.showStatusHUD(content)
            return
        }
        // No player window is visible to carry the HUD (all closed, minimized or hidden),
        // so this one case keeps the alert.
        let alert = NSAlert()
        alert.messageText = content.title
        alert.informativeText = content.detail ?? ""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let sheetWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: sheetWindow)
        } else {
            alert.runModal()
        }
    }

    private func orderedPlayerWindowControllers() -> [PlayerWindowController] {
        pruneClosedPlayerWindowControllers()
        var ordered: [PlayerWindowController] = []
        if let front = usablePlayerWindowController() {
            ordered.append(front)
        }
        for window in NSApp.orderedWindows {
            guard let wc = window.windowController as? PlayerWindowController,
                  !ordered.contains(where: { $0 === wc }) else { continue }
            ordered.append(wc)
        }
        for wc in windowControllers where !ordered.contains(where: { $0 === wc }) {
            ordered.append(wc)
        }
        return ordered
    }

    private func gridTargetScreen(from selected: [PlayerWindowController]) -> NSScreen? {
        if let front = usablePlayerWindowController(),
           let screen = front.window?.screen {
            return screen
        }
        return selected.first(where: { $0.window?.isKeyWindow == true })?.window?.screen
            ?? selected.first(where: { $0.window?.isMainWindow == true })?.window?.screen
            ?? NSScreen.main
    }

    private func arrangeFourWindowGrid() {
        var selected = orderedPlayerWindowControllers()
        let initialCount = selected.count
        let needed = max(0, 4 - selected.count)

        for _ in 0..<needed {
            guard let wc = openNewPlayerWindow() else {
                DebugConsoleController.log(level: .warning,
                                           category: "window",
                                           message: "fourWindowGrid: deniedByCap initial=\(initialCount) selected=\(selected.count) cap=\(maxPlayerWindowCount)")
                return
            }
            selected.append(wc)
        }

        selected = Array(selected.prefix(4))
        guard selected.count == 4 else {
            presentWindowCapDenial(context: "four-window-grid")
            return
        }

        guard let screen = gridTargetScreen(from: selected) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let halfW = floor(visibleFrame.width / 2)
        let halfH = floor(visibleFrame.height / 2)
        let frames = [
            NSRect(x: visibleFrame.minX, y: visibleFrame.minY + halfH, width: halfW, height: visibleFrame.height - halfH),
            NSRect(x: visibleFrame.minX + halfW, y: visibleFrame.minY + halfH, width: visibleFrame.width - halfW, height: visibleFrame.height - halfH),
            NSRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfW, height: halfH),
            NSRect(x: visibleFrame.minX + halfW, y: visibleFrame.minY, width: visibleFrame.width - halfW, height: halfH)
        ]

        for (wc, frame) in zip(selected, frames) {
            wc.window?.setFrame(frame, display: true, animate: false)
            wc.window?.deminiaturize(nil)
            wc.showWindow(nil)
        }
        selected.first?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DebugConsoleController.log("window", "fourWindowGrid: initial=\(initialCount) opened=\(needed) arranged=\(selected.map(\.debugIdentity).joined(separator: ",")) screen=\(screen.localizedName) frame=\(Int(visibleFrame.width))x\(Int(visibleFrame.height))")
    }

    private func noteRecentDocumentURLs(from urls: [URL]) {
        for url in urls where shouldAddToRecentDocuments(url) {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
    }

    private func shouldAddToRecentDocuments(_ url: URL) -> Bool {
        guard url.isFileURL,
              MediaFileSupport.isSupported(url) else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        if isDescendant(resolvedURL, of: FileManager.default.temporaryDirectory) {
            return false
        }
        if isDescendant(resolvedURL, of: Bundle.main.bundleURL) {
            return false
        }
        return true
    }

    private func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
        let childPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let ancestorPath = ancestor.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/"
        return childPath == ancestorPath || childPath.hasPrefix(prefix)
    }

    // MARK: - Menu actions

    @objc func openFile(_ sender: Any) {
        guard let wc = NSApp.keyWindow?.windowController as? PlayerWindowController else {
            guard let wc = openNewPlayerWindow() else { return }
            wc.openFile()
            return
        }
        wc.openFile()
    }

    @objc func revealInFinder(_ sender: Any) {
        frontPlayerWindowController?.revealInFinder()
    }

    @objc func renameCurrentFile(_ sender: Any) {
        frontPlayerWindowController?.showRenameSheet()
    }

    @objc func undoMarkerRename(_ sender: Any) {
        if let textEditor = activeTextEditor() {
            textEditor.undoManager?.undo()
            return
        }
        frontPlayerWindowController?.undoLastMarkerRename()
    }

    @objc func redoTyping(_ sender: Any) {
        activeTextEditor()?.undoManager?.redo()
    }

    @objc func removeCurrentQueueItem(_ sender: Any) {
        frontPlayerWindowController?.removeCurrentQueueItem()
    }

    @objc func deleteAllQueueItems(_ sender: Any) {
        frontPlayerWindowController?.removeAllQueueItems(source: "menu")
    }

    @objc func newWindow(_ sender: Any) {
        _ = openNewPlayerWindow()
    }

    @objc func fourWindowGrid(_ sender: Any) {
        arrangeFourWindowGrid()
    }

    @objc func playPause(_ sender: Any) {
        frontPlayerWindowController?.togglePlayPause()
    }

    @objc func stop(_ sender: Any) {
        frontPlayerWindowController?.stopPlayback()
    }

    @objc func volumeUp(_ sender: Any) {
        frontPlayerWindowController?.volumeUp()
    }

    @objc func volumeDown(_ sender: Any) {
        frontPlayerWindowController?.volumeDown()
    }

    @objc func advanceAudio(_ sender: Any) {
        frontPlayerWindowController?.decreaseAudioDelay()
    }

    @objc func delayAudio(_ sender: Any) {
        frontPlayerWindowController?.increaseAudioDelay()
    }

    @objc func resetAudioSync(_ sender: Any) {
        frontPlayerWindowController?.resetAudioDelay()
    }

    @objc func rewind10(_ sender: Any) {
        frontPlayerWindowController?.skipBackward10()
    }

    @objc func forward10(_ sender: Any) {
        frontPlayerWindowController?.skipForward10()
    }

    @objc func toggleShuffle(_ sender: Any) {
        frontPlayerWindowController?.toggleShuffle()
    }

    @objc func toggleEndlessShuffle(_ sender: Any) {
        frontPlayerWindowController?.toggleEndlessShuffle()
    }

    @objc func toggleRepeatOne(_ sender: Any) {
        frontPlayerWindowController?.toggleRepeat()
    }

    @objc func setPlaybackSpeedFromMenu(_ sender: NSMenuItem) {
        guard let option = PlaybackSpeedOption.option(forTag: sender.tag - 1000) else { return }
        frontPlayerWindowController?.setPlaybackSpeed(option.rate, source: "playback-menu")
    }

    @objc func setScaleFit(_ sender: Any) {
        frontPlayerWindowController?.setScaleMode(.fit)
    }

    @objc func setScaleFill(_ sender: Any) {
        frontPlayerWindowController?.setScaleMode(.fill)
    }

    @objc func setScaleStretch(_ sender: Any) {
        frontPlayerWindowController?.setScaleMode(.stretch)
    }

    @objc func openSettings(_ sender: Any) {
        SettingsWindowController.shared.openSettings()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let controller = frontPlayerWindowController
        let commandState = PlayerCommandState(
            hasPlayerWindow: controller != nil,
            queueCount: controller?.playbackSet.count ?? 0,
            hasCurrentMedia: controller?.currentMediaURL != nil,
            canRenameCurrentMedia: controller?.canRenameCurrentMedia == true,
            shuffleEnabled: controller?.isShuffleOn == true,
            endlessShuffleEnabled: controller?.isEndlessShuffleOn == true,
            repeatOneEnabled: controller?.isRepeatOne == true,
            selectedPlaybackSpeedTag: PlaybackSpeedOption.validated(
                controller?.currentPlaybackSpeed ?? PlaybackSpeedOption.normalRate
            ).tag
        )
        if let result = PlayerCommandValidation.result(forTag: menuItem.tag, state: commandState) {
            if let isOn = result.isOn {
                menuItem.state = isOn ? .on : .off
            }
            return result.isEnabled
        }

        // With no usable player window these commands have nothing to act on.
        if controller == nil, let action = menuItem.action, Self.playerWindowOnlyActions.contains(action) {
            return false
        }

        switch menuItem.tag {
        case 50:
            if let textEditor = activeTextEditor() {
                menuItem.title = "Undo"
                return textEditor.undoManager?.canUndo == true
            }
            let canUndoMarkerRename = controller?.canUndoMarkerRename == true
            menuItem.title = canUndoMarkerRename ? "Undo Prefix Change" : "Undo"
            return canUndoMarkerRename
        case 51:
            return activeTextEditor()?.undoManager?.canRedo == true
        case 1:
            menuItem.state = frontPlayerWindowController?.scaleMode == .fit     ? .on : .off
        case 2:
            menuItem.state = frontPlayerWindowController?.scaleMode == .fill    ? .on : .off
        case 3:
            menuItem.state = frontPlayerWindowController?.scaleMode == .stretch ? .on : .off
        case 30: // Keep Window On Top
            menuItem.state = frontPlayerWindowController?.isKeepAtTop == true ? .on : .off
        case 31: // Auto-hide Titlebar
            let row = SettingsTitlebarDependency.autoHideMenuState(
                hideTitlebar: SettingsWindowController.isCompleteVideoWindowModeEnabled(),
                autoHideTitlebar: SettingsWindowController.isAutoHideTitlebarEnabled())
            menuItem.state = row.isChecked ? .on : .off
            return row.isEnabled
        case 41: // Reset Audio Sync — only actionable when an offset is actually set
            return (frontPlayerWindowController?.currentAudioDelayMs ?? 0) != 0
        default:
            break
        }
        return true
    }

    /// Refreshes the read-only "Offset: … ms" row the instant the Audio Sync submenu
    /// opens. It carries no action, so AppKit's automatic validateMenuItem(_:) pass
    /// (used for the tagged items above) never reaches it — NSMenuDelegate is the hook
    /// tailored for a submenu's own about-to-open moment instead.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu.items.contains(where: { $0 === audioSyncStatusMenuItem }) else { return }
        let ms = frontPlayerWindowController?.currentAudioDelayMs ?? 0
        let sign = ms > 0 ? "+" : ""
        audioSyncStatusMenuItem?.title = "Offset: \(sign)\(ms) ms"
    }

    private static let playerWindowOnlyActions: Set<Selector> = [
        #selector(playPause(_:)),
        #selector(stop(_:)),
        #selector(rewind10(_:)),
        #selector(forward10(_:)),
        #selector(volumeUp(_:)),
        #selector(volumeDown(_:)),
        #selector(advanceAudio(_:)),
        #selector(delayAudio(_:)),
        #selector(setScaleFit(_:)),
        #selector(setScaleFill(_:)),
        #selector(setScaleStretch(_:)),
        #selector(toggleKeepAtTop(_:))
    ]

    private var frontPlayerWindowController: PlayerWindowController? {
        return usablePlayerWindowController()
    }

    private func activeTextEditor() -> NSTextView? {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
              editor.isEditable else { return nil }
        return editor
    }

    private func observeSettings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(skipDurationDidChange),
            name: .skipDurationChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: ShortcutRegistry.didChangeNotification,
            object: nil
        )
    }

    @objc private func skipDurationDidChange() {
        updateSkipMenuItemTitles()
    }

    private func updateSkipMenuItemTitles() {
        let seconds = SettingsWindowController.currentSkipDurationSeconds()
        rewindMenuItem?.title = SettingsWindowController.skipActionTitle(isForward: false, seconds: seconds)
        forwardMenuItem?.title = SettingsWindowController.skipActionTitle(isForward: true, seconds: seconds)
    }

    // MARK: - Main menu (programmatic)

    /// The menu items that carry a key from the command table, by command.
    private var shortcutMenuItems: [ShortcutCommandID: NSMenuItem] = [:]
    private var shortcutAliasItems: [ShortcutCommandID: [NSMenuItem]] = [:]

    /// Gives `item` the active menu key of `id`. The key comes from the command table, so a
    /// changed shortcut shows in the menu (`shortcutsDidChange`).
    private func bindShortcut(_ item: NSMenuItem, _ id: ShortcutCommandID) {
        shortcutMenuItems[id] = item
        item.applyShortcut(for: id)
    }

    @objc private func shortcutsDidChange() {
        refreshShortcutMenuItems(bindings: ShortcutRegistry.shared.bindings)
    }

    func refreshShortcutMenuItems(bindings: ShortcutBindings) {
        for (id, item) in shortcutMenuItems {
            shortcutAliasItems[id] = ShortcutMenuKeyInstaller.apply(
                to: item, id: id, bindings: bindings, removing: shortcutAliasItems[id] ?? [])
        }
    }

    /// Runs the menu item of `id` for a page key the user gave it, when the item is enabled.
    func performMenuCommand(_ id: ShortcutCommandID) {
        guard let item = shortcutMenuItems[id], let action = item.action, validateMenuItem(item) else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    func buildMainMenu() {
        let mainMenu = NSMenu()

        // ── App menu ────────────────────────────────────────────────────────
        let appItem = NSMenuItem()
        appItem.title = "dwb player"
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "dwb player")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About dwb player",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}",
                                      action: #selector(openSettings(_:)),
                                      keyEquivalent: "")
        settingsItem.target = self
        bindShortcut(settingsItem, .openSettings)
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: "Quit dwb player",
                                       action: #selector(NSApplication.terminate(_:)),
                                       keyEquivalent: "")
        bindShortcut(quitItem, .quit)

        // ── File menu ───────────────────────────────────────────────────────
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu

        let openItem = NSMenuItem(title: "Open\u{2026}",
                                  action: #selector(openFile(_:)),
                                  keyEquivalent: "")
        openItem.target = self
        bindShortcut(openItem, .openFile)
        fileMenu.addItem(openItem)

        fileMenu.addItem(.separator())

        let revealItem = NSMenuItem(title: "Reveal in Finder",
                                    action: #selector(revealInFinder(_:)),
                                    keyEquivalent: "")
        revealItem.target = self
        bindShortcut(revealItem, .revealInFinder)
        revealItem.tag    = 10
        fileMenu.addItem(revealItem)

        let renameItem = NSMenuItem(title: "Rename\u{2026}",
                                    action: #selector(renameCurrentFile(_:)),
                                    keyEquivalent: "")
        renameItem.target = self
        bindShortcut(renameItem, .renameFile)
        renameItem.tag    = 11
        fileMenu.addItem(renameItem)

        let removeItem = NSMenuItem(title: "Remove Current from Queue",
                                    action: #selector(removeCurrentQueueItem(_:)),
                                    keyEquivalent: "")
        removeItem.target = self
        removeItem.tag    = 12
        fileMenu.addItem(removeItem)

        let deleteAllItem = NSMenuItem(title: "Clear Queue",
                                       action: #selector(deleteAllQueueItems(_:)),
                                       keyEquivalent: "")
        deleteAllItem.target = self
        bindShortcut(deleteAllItem, .clearQueue)
        deleteAllItem.tag    = 13
        fileMenu.addItem(deleteAllItem)

        fileMenu.addItem(.separator())

        let newWindowItem = NSMenuItem(title: "New Window",
                                       action: #selector(newWindow(_:)),
                                       keyEquivalent: "")
        newWindowItem.target = self
        bindShortcut(newWindowItem, .newWindow)
        fileMenu.addItem(newWindowItem)

        // ── Edit menu ───────────────────────────────────────────────────────
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        editItem.submenu = ShortcutEditMenuBuilder.make(
            undoTarget: self, undoAction: #selector(undoMarkerRename(_:)),
            redoAction: #selector(redoTyping(_:)), bind: bindShortcut)

        // ── Playback menu ───────────────────────────────────────────────────
        let playbackItem = NSMenuItem()
        mainMenu.addItem(playbackItem)
        let playbackMenu = NSMenu(title: "Playback")
        playbackItem.submenu = playbackMenu

        let playPauseItem = NSMenuItem(title: "Play / Pause",
                                       action: #selector(playPause(_:)),
                                       keyEquivalent: "")
        playPauseItem.target = self
        bindShortcut(playPauseItem, .playPause)
        playbackMenu.addItem(playPauseItem)

        let stopItem = NSMenuItem(title: "Stop",
                                  action: #selector(stop(_:)),
                                  keyEquivalent: "")
        stopItem.target = self
        playbackMenu.addItem(stopItem)

        playbackMenu.addItem(.separator())

        let rewind10Item = NSMenuItem(title: SettingsWindowController.skipActionTitle(isForward: false,
                                                                                     seconds: SettingsWindowController.currentSkipDurationSeconds()),
                                      action: #selector(rewind10(_:)),
                                      keyEquivalent: "")
        rewind10Item.target = self
        bindShortcut(rewind10Item, .skipBackward)
        playbackMenu.addItem(rewind10Item)
        self.rewindMenuItem = rewind10Item

        let forward10Item = NSMenuItem(title: SettingsWindowController.skipActionTitle(isForward: true,
                                                                                       seconds: SettingsWindowController.currentSkipDurationSeconds()),
                                       action: #selector(forward10(_:)),
                                       keyEquivalent: "")
        forward10Item.target = self
        bindShortcut(forward10Item, .skipForward)
        playbackMenu.addItem(forward10Item)
        self.forwardMenuItem = forward10Item

        playbackMenu.addItem(.separator())

        let volUpItem = NSMenuItem(title: "Volume Up",
                                   action: #selector(volumeUp(_:)),
                                   keyEquivalent: "")
        volUpItem.target = self
        bindShortcut(volUpItem, .volumeUp)
        playbackMenu.addItem(volUpItem)

        let volDownItem = NSMenuItem(title: "Volume Down",
                                     action: #selector(volumeDown(_:)),
                                     keyEquivalent: "")
        volDownItem.target = self
        bindShortcut(volDownItem, .volumeDown)
        playbackMenu.addItem(volDownItem)

        playbackMenu.addItem(.separator())

        let shuffleItem = NSMenuItem(title: "Shuffle",
                                     action: #selector(toggleShuffle(_:)),
                                     keyEquivalent: "")
        shuffleItem.target = self
        bindShortcut(shuffleItem, .shuffle)
        shuffleItem.tag = 20
        playbackMenu.addItem(shuffleItem)

        let endlessShuffleItem = NSMenuItem(title: "Endless Shuffle",
                                            action: #selector(toggleEndlessShuffle(_:)),
                                            keyEquivalent: "")
        endlessShuffleItem.target = self
        bindShortcut(endlessShuffleItem, .endlessShuffle)
        endlessShuffleItem.tag = 21
        playbackMenu.addItem(endlessShuffleItem)

        let repeatOneItem = NSMenuItem(title: "Repeat One",
                                       action: #selector(toggleRepeatOne(_:)),
                                       keyEquivalent: "")
        repeatOneItem.target = self
        bindShortcut(repeatOneItem, .repeatOne)
        repeatOneItem.tag = 22
        playbackMenu.addItem(repeatOneItem)

        playbackMenu.addItem(.separator())

        let speedItem = NSMenuItem(title: "Playback Speed", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu(title: "Playback Speed")
        for option in PlaybackSpeedOption.all {
            let item = NSMenuItem(title: option.title,
                                  action: #selector(setPlaybackSpeedFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = 1000 + option.tag
            speedMenu.addItem(item)
        }
        speedItem.submenu = speedMenu
        playbackMenu.addItem(speedItem)

        playbackMenu.addItem(.separator())

        // Audio Sync — manual audio/video offset. Compensates for fixed output-device
        // latency (e.g. Bluetooth headphones) by shifting audio earlier/later relative
        // to video. Also reachable by the page keys of the command table when the video
        // or image has focus (see PlayerKeyDispatch).
        let audioSyncItem = NSMenuItem(title: "Audio Sync", action: nil, keyEquivalent: "")
        let audioSyncMenu = NSMenu(title: "Audio Sync")

        let audioSyncStatusItem = NSMenuItem(title: "Offset: 0 ms", action: nil, keyEquivalent: "")
        audioSyncStatusItem.isEnabled = false
        audioSyncStatusItem.tag = 40
        audioSyncMenu.addItem(audioSyncStatusItem)
        self.audioSyncStatusMenuItem = audioSyncStatusItem

        audioSyncMenu.addItem(.separator())

        let advanceAudioItem = NSMenuItem(title: "Advance Audio (Play Sooner)",
                                          action: #selector(advanceAudio(_:)),
                                          keyEquivalent: "")
        advanceAudioItem.target = self
        bindShortcut(advanceAudioItem, .advanceAudio)
        audioSyncMenu.addItem(advanceAudioItem)

        let delayAudioItem = NSMenuItem(title: "Delay Audio (Play Later)",
                                        action: #selector(delayAudio(_:)),
                                        keyEquivalent: "")
        delayAudioItem.target = self
        bindShortcut(delayAudioItem, .delayAudio)
        audioSyncMenu.addItem(delayAudioItem)

        audioSyncMenu.addItem(.separator())

        let resetAudioSyncItem = NSMenuItem(title: "Reset Audio Sync",
                                            action: #selector(resetAudioSync(_:)),
                                            keyEquivalent: "")
        resetAudioSyncItem.target = self
        bindShortcut(resetAudioSyncItem, .resetAudioSync)
        resetAudioSyncItem.tag = 41
        audioSyncMenu.addItem(resetAudioSyncItem)

        audioSyncMenu.delegate = self
        audioSyncItem.submenu = audioSyncMenu
        playbackMenu.addItem(audioSyncItem)

        // ── Video menu ──────────────────────────────────────────────────────
        let videoItem = NSMenuItem()
        mainMenu.addItem(videoItem)
        let videoMenu = NSMenu(title: "Video")
        videoItem.submenu = videoMenu

        let fitItem = NSMenuItem(title: "Fit",
                                 action: #selector(setScaleFit(_:)),
                                 keyEquivalent: "")
        fitItem.target = self
        bindShortcut(fitItem, .scaleFit)
        fitItem.tag = 1
        videoMenu.addItem(fitItem)

        let fillItem = NSMenuItem(title: "Fill",
                                  action: #selector(setScaleFill(_:)),
                                  keyEquivalent: "")
        fillItem.target = self
        bindShortcut(fillItem, .scaleFill)
        fillItem.tag = 2
        videoMenu.addItem(fillItem)

        let stretchItem = NSMenuItem(title: "Stretch",
                                     action: #selector(setScaleStretch(_:)),
                                     keyEquivalent: "")
        stretchItem.target = self
        bindShortcut(stretchItem, .scaleStretch)
        stretchItem.tag = 3
        videoMenu.addItem(stretchItem)

        // ── Window menu ─────────────────────────────────────────────────────
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        let minimizeItem = windowMenu.addItem(withTitle: "Minimize",
                                              action: #selector(NSWindow.performMiniaturize(_:)),
                                              keyEquivalent: "")
        bindShortcut(minimizeItem, .minimize)
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")

        windowMenu.addItem(.separator())

        let gridItem = NSMenuItem(title: "Four Window Grid",
                                  action: #selector(fourWindowGrid(_:)),
                                  keyEquivalent: "")
        gridItem.target = self
        bindShortcut(gridItem, .fourWindowGrid)
        windowMenu.addItem(gridItem)

        windowMenu.addItem(.separator())

        let keepAtTopItem = NSMenuItem(title: "Keep Window On Top",
                                       action: #selector(toggleKeepAtTop(_:)),
                                       keyEquivalent: "")
        keepAtTopItem.target = self
        keepAtTopItem.tag    = 30
        windowMenu.addItem(keepAtTopItem)

        let autoHideTitlebarItem = NSMenuItem(title: "Auto-hide Titlebar",
                                              action: #selector(toggleAutoHideTitlebar(_:)),
                                              keyEquivalent: "")
        autoHideTitlebarItem.target = self
        autoHideTitlebarItem.tag    = 31
        windowMenu.addItem(autoHideTitlebarItem)

        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
        shortcutsDidChange()
    }

    @objc func toggleKeepAtTop(_ sender: Any) {
        frontPlayerWindowController?.toggleKeepAtTop()
    }

    @objc func toggleAutoHideTitlebar(_ sender: Any) {
        let current = SettingsWindowController.isAutoHideTitlebarEnabled()
        UserDefaults.standard.set(!current, forKey: SettingsWindowController.autoHideTitlebarKey)
        NotificationCenter.default.post(name: .autoHideTitlebarChanged, object: nil)
    }
}
