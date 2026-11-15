# Changelog

All notable changes to dwb player are recorded here.

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
