import AppKit

/// Page shortcuts: the keys that run when the video, the image or GIF, or the queue list has
/// keyboard focus. The key-to-command match comes from the command table
/// (`ShortcutRegistry`); this file only runs the command. Menu keys never come here: each
/// key has one route, the menu or the page.
enum PlayerKeyDispatch {
    /// Runs the command a key press is assigned to on `surface`, and returns whether one ran.
    /// `seek` replaces the one-step skip on the video, which keeps seeking while the key is held.
    static func handle(_ event: NSEvent,
                       surface: ShortcutSurface,
                       controller wc: PlayerWindowController,
                       isEditingText: Bool,
                       seek: ((_ backward: Bool) -> Void)? = nil) -> Bool {
        guard !isEditingText,
              let key = ShortcutKey(event: event),
              let command = ShortcutRegistry.shared.bindings.pageCommand(for: key, surface: surface) else {
            return false
        }
        let isRepeat = event.isARepeat
        switch command {
        case .playPause:
            if !isRepeat { wc.togglePlayPause() }
        case .skipBackward:
            if !isRepeat { if let seek { seek(true) } else { wc.skipBackward10() } }
        case .skipForward:
            if !isRepeat { if let seek { seek(false) } else { wc.skipForward10() } }
        case .volumeDown:
            wc.volumeDown()
        case .volumeUp:
            wc.volumeUp()
        case .previousItem:
            if !isRepeat { wc.playPrevious() }
        case .nextItem:
            if !isRepeat { wc.playNext() }
        case .togglePrimaryPrefix, .toggleSecondaryPrefix, .renameFile:
            guard let action = PrefixKeyRouting.action(for: command, isEditingText: isEditingText) else { return false }
            if !isRepeat {
                wc.performPrefixAction(action, source: "\(surfaceName(surface))-\(key.baseText.lowercased())")
            }
        case .toggleBookmark:
            if !isRepeat { wc.toggleBookmark() }
        case .skip10:
            SettingsWindowController.setSkipDuration(10)
        case .skip30:
            SettingsWindowController.setSkipDuration(30)
        case .skip60:
            SettingsWindowController.setSkipDuration(60)
        case .skip180:
            SettingsWindowController.setSkipDuration(180)
        case .advanceAudio:
            // Advance audio (play it sooner) — compensates for output devices
            // (e.g. Bluetooth headphones) that add fixed audio latency.
            wc.decreaseAudioDelay()
        case .delayAudio:
            // Delay audio further (play it later).
            wc.increaseAudioDelay()
        case .resetAudioSync:
            if !isRepeat { wc.resetAudioDelay() }
        case .shuffle, .endlessShuffle, .repeatOne, .openFile, .revealInFinder, .clearQueue,
             .newWindow, .fourWindowGrid, .scaleFit, .scaleFill, .scaleStretch:
            // Another key the user gave a menu command: run the menu item itself.
            if !isRepeat { (NSApp.delegate as? AppDelegate)?.performMenuCommand(command) }
        case .undoPrefixChange, .removeQueueRows, .minimize, .openSettings, .quit,
             .settingsSidebarNavigation, .queueDividerResize, .textUndo, .textRedo,
             .cut, .copy, .paste, .selectAll:
            return false
        }
        return true
    }

    private static func surfaceName(_ surface: ShortcutSurface) -> String {
        switch surface {
        case .video:      return "videoPage"
        case .image:      return "imagePage"
        case .queueTable: return "queueTable"
        }
    }
}
