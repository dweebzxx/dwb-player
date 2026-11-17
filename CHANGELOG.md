# Changelog

All notable changes to dwb player are recorded here.

## 1.5.2 — 2026-11-17

Covers the changes made since 1.5.1: a redesigned Settings window and customizable keyboard shortcuts.

### Added

- **Customizable keyboard shortcuts.** Settings > Shortcuts lists every shortcut in dwb player, with a keyboard map and search. Click a key to change or remove it, add more keys to an action, or assign an unassigned action. A key that another action already uses in the same context, or that cannot be delivered reliably, is refused with a message. Restore Defaults… on the page resets only the shortcuts. Changes apply to dwb player only, update the menus and tooltips at once, and are kept between launches.
- **Edit menu.** The Edit menu now has Undo, Redo, Cut, Copy, Paste, and Select All. Their keys (Command-Z, Shift-Command-Z, Command-X, Command-C, Command-V, Command-A) are reserved for text editing and cannot be assigned to other actions.
- **Reference rows.** The Shortcuts page also lists fixed keys that cannot be changed: Delete and Forward Delete for removing selected queue rows, the arrow keys and Home on the queue panel divider, and the Settings sidebar arrows.

### Changed

- **Settings pages.** Playback, Appearance & Controls (renamed from Controls), Queue & Files, Advanced, and About were rebuilt with grouped sections and supporting text under each setting. Accepted media (Videos, Images, GIFs) moved to Queue & Files, and the media-recovery action "Open Settings" now opens that page. Stored values, defaults, and ranges did not change.
- **Playback page.** Playback speed, Skip duration, and "Show filename when playback starts" are under Video. Image duration and GIF loops are typed numbers with steppers instead of menus. Playback speed shows `1.00× (Normal)`.
- **Hide title bar.** Turning on Hide title bar disables Automatically hide title bar and keeps its saved value. The Window menu's Auto-hide Titlebar item follows the same rule.
- **Filename prefixes.** The Queue & Files page shows the live keys for the primary and secondary prefix, so it follows any change made on the Shortcuts page.
- **Play or pause.** Space is the only default key. Command-Space is no longer assigned; a key you set yourself is kept.
- **Exact modifiers.** A shortcut now runs only with the modifiers it is assigned. For example, Shift-← no longer seeks.
- **Tooltips.** The rail tooltips for Previous and Next file now show their real keys (`,` and `.`).
- **Repeat one.** The Settings checkbox, the rail button, and the More menu all call this action Repeat one (it was "Replay" and "Repeat current file").
- **Advanced page.** Show debug console, Detailed autoplay logging, Clear All Bookmarks…, and Restore Default Settings… in one page. The confirmations name dwb player. Restore Default Settings also clears shortcut changes, and the default keys apply right away.
- **About page.** Shows the version, license, minimum macOS version, the playback framework, and the VLC backend version on separate rows. The build value shows `--`.

### Fixed

- The Debug Console filter text no longer overlaps its search icon.

## 1.5.1 — 2026-11-15

Covers the changes made since the previous release notes (2026-07-23).

### Added

- **Play Next.** Right-click a Queue Page row and choose Play Next to play it right after the current item, including while a search filter is active. Repeated Play Next choices form an ordered chain.
- **Audio sync offset.** A manual audio delay for Bluetooth and other laggy outputs: `[` advances and `]` delays the audio by 50 ms, `\` resets it, and the Playback menu has matching Audio Sync items.
- **Advance after prefix.** An optional Settings > Queue & Files setting (off by default). After `N`, `M`, or a rail prefix button adds a prefix to the current item, playback moves on to the next item. Removing a prefix never advances, and the Queue Page's own prefix controls never advance.
- **Undo Prefix Change.** Edit > Undo Prefix Change (Command-Z) undoes the last prefix change.
- **Settings window volume.** A Window volume slider in Settings with a percent readout and a Default button. Like Window opacity, it controls one window, and the row names which window it targets.
- **Resizable Queue Page.** In windowed mode, drag the edge the Queue Page shares with the video to make the panel narrower, down to 200 pt. Double-click the edge to reset it. The width is not saved between launches.
- **Edit menu commands.** Copy, Paste, and Select All, and the menu order is now dwb player, File, Edit, Playback.
- **Error history with the console off.** The Debug Console now keeps recent warnings and errors, plus the lines leading up to them, in memory only (nothing is written to disk). Opening the console afterward shows what happened. A playback start that never reaches the playing state is also recorded, with the file and player state.

### Changed

- **Queue Page redesign.** A compact list with one header row and a two-row footer at every width, a faded app icon for the empty queue, and updated hover, selected, playing, and drag states.
- **Prefix rename keys.** The primary prefix is applied with `N` and the secondary with `M`. Applying the active prefix again removes it, and applying the other prefix replaces it instead of stacking. The footer has three controls: primary, secondary, and Undo.
- **Keyboard shortcuts.** Several shortcuts moved to unmodified keys. The full map is in Settings > Shortcuts.
- **Volume.** The per-window volume ceiling is now 200% (it was 150%), 100% stays normal volume, and the volume HUD is a compact segmented display that shows the full percentage.
- **Scrubber.** Clicking the scrubber now shows visible progress where you click, and the knob is proportionate.
- **Folder drops.** Dropping a folder starts ordinary Shuffle from a randomized item.
- **Playback bar.** The bar appears only when the mouse moves inside the player window. Keyboard shortcuts no longer reveal it.
- **Window behavior.** Closing the last player window keeps the app running in the Dock. A Dock click restores a minimized window before opening a new one. Settings names the window it controls and outlines it.
- **Prefix buttons off.** Turning off "Prefix buttons" now hides the prefix actions from the playback bar and its More menu, and `N`, `M`, and `R` work with an image or GIF in view.
- **Visual refresh.** Updated color foundation, playback-bar messages and HUDs, and Queue and Settings styling to the dwb design system.
- **Network volumes.** Files on non-local volumes are not probed for duration in bulk; a row shows `--:--` until the file has played. Browsing a network mount no longer stalls the app.
- **AV1.** AV1 video is decoded with VLC's bundled libaom decoder.

### Fixed

- Failed or unplayable media now shows a one-second message and playback moves on to the next item on its own. Valid media is no longer skipped by mistake, and renaming files keeps a sorted queue in its current order until you sort again.
- Pressing Play/Pause near the end of a video no longer skips to the next item.
- A paused video that was resumed after a long pause no longer shows a false "can't be played" message or gets skipped.
- One window's mute or volume no longer changes another window's volume.
- Opening the Queue Page no longer freezes on large animated GIFs; their durations are read in the background.
- A playback start that never began could go unreported with the console off; it is now logged.
- The volume HUD no longer clips its percentage label.
