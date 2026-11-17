import XCTest

final class ShortcutsModelTests: XCTestCase {
    private var bindings: ShortcutBindings { ShortcutBindings() }
    private var groups: [ShortcutGroup] { ShortcutsCatalog.groups(bindings: bindings) }
    private var allEntries: [ShortcutEntry] { groups.flatMap(\.items) }

    private func entry(_ id: ShortcutCommandID, in groups: [ShortcutGroup]? = nil) -> ShortcutEntry? {
        (groups ?? self.groups).flatMap(\.items).first { $0.id == id }
    }

    func testGroupsAreByTaskInTheApprovedOrder() {
        XCTAssertEqual(groups.map(\.title),
                       ["Playback", "Navigation", "File actions", "Bookmarks", "Window",
                        "Skip & audio sync", "Text editing"])
    }

    func testOnlySkipAndAudioSyncIsLabelledPlayerOnly() {
        XCTAssertEqual(groups.map(\.appLabel), [nil, nil, nil, nil, nil, "dwb player", nil])
    }

    func testEveryCommandAppearsInExactlyOneGroup() {
        XCTAssertEqual(allEntries.map(\.id).count, ShortcutCommandID.allCases.count)
        XCTAssertEqual(Set(allEntries.map(\.id)), Set(ShortcutCommandID.allCases))
    }

    func testTheApprovedActionNamesAreUsed() {
        let names: [ShortcutCommandID: String] = [
            .playPause: "Play or pause", .volumeUp: "Volume up", .volumeDown: "Volume down",
            .previousItem: "Previous item", .nextItem: "Next item",
            .togglePrimaryPrefix: "Toggle primary prefix", .toggleSecondaryPrefix: "Toggle secondary prefix",
            .renameFile: "Rename file", .undoPrefixChange: "Undo prefix change", .toggleBookmark: "Toggle bookmark"
        ]
        for (id, name) in names { XCTAssertEqual(entry(id)?.action, name) }
    }

    func testEveryActionNameIsSentenceCase() {
        for entry in allEntries {
            let words = entry.action.split(separator: " ").dropFirst()
            for word in words {
                // Only proper names and acronyms keep a capital after the first word.
                if let first = word.first, first.isUppercase {
                    XCTAssertTrue(["Finder", "Settings"].contains(String(word)), entry.action)
                }
            }
        }
    }

    func testFileActionsHoldThePrefixesRenameAndUndo() {
        let fileActions = groups.first { $0.title == "File actions" }
        XCTAssertEqual(fileActions?.items.map(\.action),
                       ["Open file", "Reveal in Finder", "Rename file", "Clear queue", "Toggle primary prefix",
                        "Toggle secondary prefix", "Undo prefix change", "Remove selected queue rows"])
        XCTAssertEqual(entry(.togglePrimaryPrefix)?.tone, .markerPrimary)
        XCTAssertEqual(entry(.toggleSecondaryPrefix)?.tone, .markerSecondary)
        XCTAssertEqual(entry(.renameFile)?.tone, .accent)
    }

    func testSkipPresetsAndAudioSyncSitInTheLabelledGroup() {
        let player = groups.first { $0.title == "Skip & audio sync" }?.items.map(\.action) ?? []
        XCTAssertEqual(player, ["10 seconds", "30 seconds", "60 seconds", "3 minutes",
                                "Advance audio (play sooner)", "Delay audio (play later)", "Reset audio sync"])
        XCTAssertEqual(groups.first { $0.title == "Bookmarks" }?.items.map(\.action), ["Toggle bookmark"])
    }

    func testAllTheKeysOfACommandAreOnOneRowOneCapEach() {
        XCTAssertEqual(entry(.skipBackward)?.keyTexts, ["←", "⌥←"])
        XCTAssertEqual(entry(.volumeUp)?.keyTexts, ["↑", "⌘↑"])
        XCTAssertEqual(entry(.removeQueueRows)?.keyTexts, ["⌫", "⌦"])
        XCTAssertEqual(entry(.undoPrefixChange)?.keyTexts, ["⌘Z"])
    }

    func testCommandsThatDoTheSameThingInDifferentContextsStayOnSeparateRows() {
        XCTAssertEqual(allEntries.filter { $0.keyTexts.contains("⌘Z") }.map(\.action), ["Undo prefix change", "Undo typing"])
    }

    func testReferenceRowsAreNotEditable() {
        let reference = allEntries.filter { !$0.isEditable }.map(\.id)
        XCTAssertTrue(reference.contains(.quit))
        XCTAssertTrue(reference.contains(.undoPrefixChange))
        XCTAssertTrue(reference.contains(.removeQueueRows))
        XCTAssertFalse(reference.contains(.nextItem))
    }

    func testConditionalActionsCarryContextTextInTheRow() {
        XCTAssertTrue(entry(.renameFile)?.note?.contains("exactly one row is selected") == true)
        XCTAssertTrue(entry(.nextItem)?.note?.contains("text field is being edited") == true)
        XCTAssertTrue(entry(.skipBackward)?.note?.contains("image or GIF steps once per press") == true)
        XCTAssertTrue(entry(.undoPrefixChange)?.note?.contains("text field is being edited") == true)
        XCTAssertNotNil(entry(.removeQueueRows)?.note)
        XCTAssertNil(entry(.openFile)?.note, "a menu command that works anywhere needs no condition")
    }

    func testAnUnassignedActionHasNoKeys() {
        let changed = bindings.setting([], for: .togglePrimaryPrefix)
        let row = entry(.togglePrimaryPrefix, in: ShortcutsCatalog.groups(bindings: changed))
        XCTAssertEqual(row?.keys, [])
        XCTAssertEqual(row?.isEditable, true)
    }

    func testMapKeysKeepOnlyUnmodifiedKeysOnTheMap() {
        XCTAssertEqual(entry(.skipBackward)?.mapKeys, ["←"])
        XCTAssertEqual(entry(.undoPrefixChange)?.mapKeys, [])
        XCTAssertEqual(entry(.advanceAudio)?.mapKeys, ["["])
        XCTAssertEqual(entry(.playPause)?.mapKeys, ["Space"])
    }

    func testMarkerKeysTakeTheMarkerTones() {
        let tones = ShortcutKeyMap.tones(for: groups)
        XCTAssertEqual(tones["N"], .markerPrimary)
        XCTAssertEqual(tones["M"], .markerSecondary)
        XCTAssertEqual(tones["Space"], .accent)
        XCTAssertNil(tones["Q"], "keys without a shortcut stay unused")
    }

    func testTheMapFollowsAChangedKey() {
        let changed = ShortcutsCatalog.groups(bindings: bindings.setting([key("K")], for: .togglePrimaryPrefix))
        let tones = ShortcutKeyMap.tones(for: changed)
        XCTAssertEqual(tones["K"], .markerPrimary)
        XCTAssertNil(tones["N"])
        XCTAssertEqual(entry(.togglePrimaryPrefix, in: changed)?.keyTexts, ["K"])
    }

    private func key(_ text: String) -> ShortcutKey { ShortcutKey(text: text)! }

    // MARK: Search

    private func actions(_ query: String) -> [String] {
        ShortcutsSearch.filter(groups, query: query).flatMap(\.items).map(\.action)
    }

    func testEmptyQueryKeepsEveryGroupAndRow() {
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: ""), groups)
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: "   "), groups)
    }

    func testTypingVolLeavesTheVolumeRows() {
        XCTAssertEqual(actions("vol"), ["Volume up", "Volume down"])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: "VOLUME"), ShortcutsSearch.filter(groups, query: "volume"))
    }

    func testSearchMatchesTheCommandSymbolAndTheSpokenWord() {
        let symbol = Set(actions("⌘"))
        let word = Set(actions("command"))
        XCTAssertEqual(symbol, word)
        XCTAssertTrue(symbol.contains("Volume up"))
        XCTAssertTrue(symbol.contains("Undo prefix change"))
        XCTAssertFalse(symbol.contains("Next item"))
    }

    func testSearchMatchesKeyTextAndSpokenKeyNames() {
        XCTAssertEqual(actions("⌘z"), ["Undo prefix change", "Undo typing", "Redo typing"])
        XCTAssertEqual(actions("command z"), ["Undo prefix change", "Undo typing", "Redo typing"])
        XCTAssertTrue(actions("option").contains("Shuffle"))
        XCTAssertTrue(actions("left arrow").contains("Rewind by skip duration"))
        XCTAssertTrue(actions("comma").contains("Previous item"))
    }

    func testSearchMatchesPrefixRows() {
        XCTAssertEqual(actions("prefix"), ["Toggle primary prefix", "Toggle secondary prefix", "Undo prefix change"])
    }

    func testSearchMatchesGroupNamesAndKeepsTheWholeGroup() {
        let result = ShortcutsSearch.filter(groups, query: "bookmarks")
        XCTAssertEqual(result.map(\.title), ["Bookmarks"])
        XCTAssertEqual(result.first?.items.map(\.action), ["Toggle bookmark"])
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: "skip & audio").first?.items.count, 7)
    }

    func testSearchMatchesContextText() {
        XCTAssertEqual(actions("exactly one row"), ["Rename file"])
        XCTAssertTrue(actions("steps once per press").contains("Rewind by skip duration"))
    }

    func testSearchDropsGroupsLeftEmpty() {
        let result = ShortcutsSearch.filter(groups, query: "primary prefix")
        XCTAssertEqual(result.map(\.title), ["File actions"])
        XCTAssertEqual(result.first?.items.count, 1)
    }

    func testNoMatchReturnsNoGroups() {
        XCTAssertTrue(ShortcutsSearch.filter(groups, query: "zzz").isEmpty)
        XCTAssertTrue(ShortcutsSearch.filter(groups, query: "zzzz").isEmpty)
    }

    func testSearchSeesTheActiveKeysNotTheDefaults() {
        let changed = ShortcutsCatalog.groups(bindings: bindings.setting([key("J")], for: .nextItem))
        XCTAssertEqual(ShortcutsSearch.filter(changed, query: "next item").flatMap(\.items).first?.keyTexts, ["J"])
        let sameKeyRows = ShortcutsSearch.filter(changed, query: " j").flatMap(\.items).map(\.action)
        XCTAssertTrue(sameKeyRows.contains("Next item"))
    }

    // MARK: Keyboard map

    func testKeyboardLayoutHasLettersPunctuationSpaceAndArrows() {
        let keys = ShortcutKeyboardLayout.allKeys
        XCTAssertTrue(keys.isSuperset(of: ["Q", "A", "Z", "[", "]", "\\", ",", ".", "Space", "←", "↑", "↓", "→"]))
        XCTAssertEqual(ShortcutKeyboardLayout.rows.map(\.count), [13, 9, 9])
    }

    func testKeyMapDimensionsMatchTheDesignSystem() {
        XCTAssertEqual(ShortcutKeyboardLayout.keyWidth, 26)
        XCTAssertEqual(ShortcutKeyboardLayout.keyHeight, 24)
        XCTAssertEqual(ShortcutKeyboardLayout.spaceWidth, 150)
    }
}

final class SettingsPagesModelTests: XCTestCase {
    func testAdvancedDescriptionAndSectionOrder() {
        XCTAssertEqual(SettingsPages.all[4].description, "Diagnostics, bookmarks, and default settings.")
        XCTAssertEqual(SettingsAdvancedAboutContent.Advanced.sectionTitles,
                       ["Diagnostics", "Bookmarks", "Reset"])
    }

    func testAdvancedDiagnosticLabelsAndHelp() {
        let copy = SettingsAdvancedAboutContent.Advanced.self
        XCTAssertEqual(copy.debugConsole, "Show debug console")
        XCTAssertEqual(copy.autoplayLogging, "Detailed autoplay logging")
        XCTAssertEqual(copy.autoplayHelp, "Records additional autoplay diagnostics in debug builds only.")
        XCTAssertEqual(copy.cancel, "Cancel")
    }

    func testAdvancedBookmarkAndResetCopy() {
        let copy = SettingsAdvancedAboutContent.Advanced.self
        XCTAssertEqual(copy.clearBookmarks, "Clear All Bookmarks…")
        XCTAssertEqual(copy.clearBookmarksHelp, "Clears this app's bookmarks without deleting media files. This cannot be undone.")
        XCTAssertEqual(copy.clearBookmarksTitle, "Clear all bookmarks for dwb player?")
        XCTAssertEqual(copy.clearBookmarksMessage, "This removes all bookmarks saved by this app. Media files are not deleted. This cannot be undone.")
        XCTAssertEqual(copy.clearBookmarksConfirm, "Clear All Bookmarks")
        XCTAssertEqual(copy.restoreDefaults, "Restore Default Settings…")
        XCTAssertEqual(copy.restoreDefaultsHelp, "Restores this app's settings and keyboard shortcuts. Media files, queues, and bookmarks are not deleted.")
        XCTAssertEqual(copy.restoreDefaultsTitle, "Restore default settings for dwb player?")
        XCTAssertEqual(copy.restoreDefaultsMessage, "This resets this app's settings and customized keyboard shortcuts. Media files, queues, and bookmarks are not deleted.")
        XCTAssertEqual(copy.restoreDefaultsConfirm, "Restore Defaults")
    }

    func testAboutBundleFactsAndVersionLine() {
        let about = SettingsAdvancedAboutContent.About.self
        XCTAssertEqual(about.description, "Play and review local videos, images, and GIFs.")
        XCTAssertEqual(about.displayedBuild, "--")
        XCTAssertEqual(about.githubTitle, "View on GitHub")
        XCTAssertEqual(about.issuesTitle, "Report an Issue")
        XCTAssertEqual(about.versionLine(version: "1.2", build: about.displayedBuild), "Version 1.2 · Build --")
        let facts = about.facts(info: ["LSMinimumSystemVersion": "13.0"], vlcBackendVersion: "3.0.0")
        XCTAssertEqual(facts.map(\.label),
                       ["License", "Requires", "Interface", "Playback framework", "VLC backend"])
        XCTAssertEqual(facts.map(\.value),
                       ["MIT License", "macOS 13.0 or later", "AppKit", "VLCKit", "3.0.0"])
    }

    func testPageNamesAndOrder() {
        XCTAssertEqual(SettingsPages.all.map(\.name),
                       ["Playback", "Appearance & Controls", "Queue & Files", "Shortcuts", "Advanced", "About"])
    }

    func testPageIdentifiersAreUnchanged() {
        XCTAssertEqual(SettingsPages.all.map(\.identifier),
                       ["playback", "controls", "queueFiles", "shortcuts", "advanced", "about"])
    }

    func testPlaybackControlsAndQueuePagesUseTheApprovedDescriptions() {
        XCTAssertEqual(SettingsPages.all[0].description, "Video playback, image timing, and GIF loops.")
        XCTAssertEqual(SettingsPages.all[1].description, "Customize playback controls and window appearance.")
        XCTAssertEqual(SettingsPages.all[2].description, "Choose accepted media, queue behavior, and filename prefixes.")
    }

    func testTheShortcutsPageIsEditable() {
        let shortcuts = SettingsPages.all.first { $0.identifier == "shortcuts" }
        XCTAssertEqual(shortcuts?.description, "Find and customize keyboard shortcuts for this app.")
        XCTAssertFalse(shortcuts?.description.lowercased().contains("read-only") ?? true)
    }

    func testSidebarGroupsAreGeneralAndSystem() {
        XCTAssertEqual(SettingsPages.groups.map(\.label), ["General", "System"])
        XCTAssertEqual(SettingsPages.groups[0].pageIndices.map { SettingsPages.all[$0].name },
                       ["Playback", "Appearance & Controls", "Queue & Files", "Shortcuts"])
        XCTAssertEqual(SettingsPages.groups[1].pageIndices.map { SettingsPages.all[$0].name },
                       ["Advanced", "About"])
    }

    func testEveryPageHasAOneLineDescription() {
        for page in SettingsPages.all {
            XCTAssertFalse(page.description.isEmpty, page.name)
            XCTAssertFalse(page.description.contains("\n"), page.name)
        }
    }

    func testArrowNavigationCrossesGroupsAndStopsAtTheEnds() {
        XCTAssertEqual(SettingsPages.neighbor(of: 3, offset: 1), 4, "Shortcuts → Advanced")
        XCTAssertEqual(SettingsPages.neighbor(of: 4, offset: -1), 3)
        XCTAssertNil(SettingsPages.neighbor(of: 0, offset: -1))
        XCTAssertNil(SettingsPages.neighbor(of: 5, offset: 1))
    }

    func testSettingsWindowSizesComeFromTheDesignSystem() {
        XCTAssertEqual(DWBMetrics.settingsSize, NSSize(width: 820, height: 550))
        XCTAssertEqual(DWBMetrics.settingsMinSize, NSSize(width: 760, height: 500))
        XCTAssertEqual(DWBMetrics.sidebarWidth, 188)
        XCTAssertEqual(DWBMetrics.sidebarRow, 32)
        XCTAssertEqual(DWBMetrics.labelColumn, 156)
    }
}

final class SettingsNumericChoicesTests: XCTestCase {
    private let imageChoices: [Double] = [0.5, 0.75, 1, 2, 3, 5, 10]
    private let loopChoices: [Double] = [1, 3, 5, 10]

    // MARK: Snapping

    func testAChoiceStaysItself() {
        for choice in imageChoices {
            XCTAssertEqual(SettingsNumericChoices.nearest(to: choice, in: imageChoices), choice)
        }
        for choice in loopChoices {
            XCTAssertEqual(SettingsNumericChoices.nearest(to: choice, in: loopChoices), choice)
        }
    }

    func testAValueBetweenChoicesSnapsToTheNearest() {
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 8, in: imageChoices), 10)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 2.4, in: imageChoices), 2)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 0.7, in: imageChoices), 0.75)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 7, in: loopChoices), 5)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 8, in: loopChoices), 10)
    }

    func testATieGoesToTheSmallerChoice() {
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 4, in: imageChoices), 3)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 7.5, in: imageChoices), 5)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 0.625, in: imageChoices), 0.5)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 2, in: loopChoices), 1)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 4, in: loopChoices), 3)
    }

    func testBelowTheFirstAndAboveTheLastChoiceGiveTheEnds() {
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 0, in: imageChoices), 0.5)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: -4, in: imageChoices), 0.5)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 99, in: imageChoices), 10)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 0, in: loopChoices), 1)
        XCTAssertEqual(SettingsNumericChoices.nearest(to: 1000, in: loopChoices), 10)
    }

    func testNoChoicesGiveNothing() {
        XCTAssertNil(SettingsNumericChoices.nearest(to: 3, in: []))
        XCTAssertNil(SettingsNumericChoices.stepped(from: 3, direction: 1, in: []))
    }

    // MARK: Stepping

    func testSteppingMovesOneChoiceAndStopsAtTheEnds() {
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 3, direction: 1, in: imageChoices), 5)
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 3, direction: -1, in: imageChoices), 2)
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 10, direction: 1, in: imageChoices), 10)
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 0.5, direction: -1, in: imageChoices), 0.5)
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 5, direction: 1, in: loopChoices), 10)
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 1, direction: -1, in: loopChoices), 1)
    }

    func testSteppingFromAValueBetweenChoicesStartsFromTheNearestChoice() {
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 4, direction: 1, in: imageChoices), 5, "4 is 3, then up")
        XCTAssertEqual(SettingsNumericChoices.stepped(from: 8, direction: -1, in: imageChoices), 5, "8 is 10, then down")
    }

    // MARK: Parsing

    func testPlainNumbersParse() {
        XCTAssertEqual(SettingsNumericChoices.parse("8"), 8)
        XCTAssertEqual(SettingsNumericChoices.parse(" 0.75 "), 0.75)
        XCTAssertEqual(SettingsNumericChoices.parse("0,5"), 0.5, "a comma is the decimal point when there is no dot")
        XCTAssertEqual(SettingsNumericChoices.parse("7.4"), 7.4)
    }

    func testTextThatIsNotANumberGivesNil() {
        for text in ["abc", "", "   ", "1e3", "0x10", "1.2.3", "1,2,3", "nan", "inf", "3 s", "--1", "."] {
            XCTAssertNil(SettingsNumericChoices.parse(text), "'\(text)'")
        }
    }

    // MARK: Display

    func testDisplayTextDropsTrailingZeros() {
        XCTAssertEqual(SettingsNumericChoices.displayText(0.5), "0.5")
        XCTAssertEqual(SettingsNumericChoices.displayText(0.75), "0.75")
        XCTAssertEqual(SettingsNumericChoices.displayText(1), "1")
        XCTAssertEqual(SettingsNumericChoices.displayText(10), "10")
    }
}

final class SettingsTitlebarDependencyTests: XCTestCase {
    func testAutoHideMenuStateForAllFourSettingCombinations() {
        for hide in [false, true] {
            for auto in [false, true] {
                let state = SettingsTitlebarDependency.autoHideMenuState(
                    hideTitlebar: hide, autoHideTitlebar: auto)
                XCTAssertEqual(state, .init(isEnabled: !hide, isChecked: auto))
                XCTAssertEqual(state, SettingsTitlebarDependency.autoHideRowState(
                    hideTitlebar: hide, autoHideTitlebar: auto))
            }
        }
    }
    func testHideTitleBarOffKeepsTheAutomaticOptionEnabled() {
        XCTAssertEqual(SettingsTitlebarDependency.autoHideRowState(hideTitlebar: false, autoHideTitlebar: false),
                       .init(isEnabled: true, isChecked: false))
        XCTAssertEqual(SettingsTitlebarDependency.autoHideRowState(hideTitlebar: false, autoHideTitlebar: true),
                       .init(isEnabled: true, isChecked: true))
    }

    func testHideTitleBarOnDisablesTheAutomaticOptionAndKeepsItsSavedValue() {
        XCTAssertEqual(SettingsTitlebarDependency.autoHideRowState(hideTitlebar: true, autoHideTitlebar: false),
                       .init(isEnabled: false, isChecked: false))
        XCTAssertEqual(SettingsTitlebarDependency.autoHideRowState(hideTitlebar: true, autoHideTitlebar: true),
                       .init(isEnabled: false, isChecked: true))
    }

    func testTurningHideTitleBarOffAgainRestoresTheSavedValue() {
        let saved = true
        let whileOn = SettingsTitlebarDependency.autoHideRowState(hideTitlebar: true, autoHideTitlebar: saved)
        let afterOff = SettingsTitlebarDependency.autoHideRowState(hideTitlebar: false, autoHideTitlebar: saved)
        XCTAssertEqual(whileOn.isChecked, afterOff.isChecked)
        XCTAssertTrue(afterOff.isEnabled)
    }
}

final class SettingsPlaybackSpeedTitleTests: XCTestCase {
    func testPopupTitlesUseTheTimesSignAndMarkNormal() {
        let rates: [Float] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 2.50, 3.00]
        XCTAssertEqual(rates.map { SettingsPlaybackSpeedTitle.title(rate: $0, isNormal: $0 == 1.0) },
                       ["0.25\u{00D7}", "0.50\u{00D7}", "0.75\u{00D7}", "1.00\u{00D7} (Normal)",
                        "1.25\u{00D7}", "1.50\u{00D7}", "2.00\u{00D7}", "2.50\u{00D7}", "3.00\u{00D7}"])
    }

    func testTheTimesSignIsU00D7NotTheLetterX() {
        let title = SettingsPlaybackSpeedTitle.title(rate: 1.25, isNormal: false)
        XCTAssertTrue(title.unicodeScalars.contains("\u{00D7}"))
        XCTAssertFalse(title.contains("x"))
    }
}

final class PrefixShortcutTextTests: XCTestCase {
    private func key(_ text: String) -> ShortcutKey { ShortcutKey(text: text)! }

    func testOneKeyShowsShortcutAndTheKey() {
        XCTAssertEqual(PrefixShortcutText.text(keys: ["N"]), "Shortcut: N")
    }

    func testSeveralKeysShowShortcutsInAssignmentOrder() {
        XCTAssertEqual(PrefixShortcutText.text(keys: ["N", "H"]), "Shortcuts: N, H")
        XCTAssertEqual(PrefixShortcutText.text(keys: ["H", "N", "⌥N"]), "Shortcuts: H, N, ⌥N")
    }

    func testNoKeyShowsUnassigned() {
        XCTAssertEqual(PrefixShortcutText.text(keys: []), "Shortcut: Unassigned")
    }

    func testTheCurrentPrefixKeysComeFromTheCommandTable() {
        let bindings = ShortcutBindings()
        XCTAssertEqual(ShortcutsCatalog.currentKeys(for: .togglePrimaryPrefix, in: bindings), ["N"])
        XCTAssertEqual(ShortcutsCatalog.currentKeys(for: .toggleSecondaryPrefix, in: bindings), ["M"])
        XCTAssertEqual(PrefixShortcutText.primary(in: bindings), "Shortcut: N")
        XCTAssertEqual(PrefixShortcutText.secondary(in: bindings), "Shortcut: M")
    }

    func testTheTextFollowsTheActiveKeysItIsGiven() {
        let changed = ShortcutBindings()
            .setting([key("K"), key("H")], for: .togglePrimaryPrefix)
            .setting([], for: .toggleSecondaryPrefix)
        XCTAssertEqual(PrefixShortcutText.primary(in: changed), "Shortcuts: K, H")
        XCTAssertEqual(PrefixShortcutText.secondary(in: changed), "Shortcut: Unassigned")
    }

    func testChangingThePrefixKeyToKShowsShortcutK() {
        let changed = ShortcutBindings().setting([key("K")], for: .togglePrimaryPrefix)
        XCTAssertEqual(PrefixShortcutText.primary(in: changed), "Shortcut: K")
        XCTAssertEqual(PrefixShortcutText.secondary(in: changed), "Shortcut: M", "the other prefix is unchanged")
    }
}

final class ShortcutHintTests: XCTestCase {
    func testAHintNamesTheFirstActiveKey() {
        let bindings = ShortcutBindings()
        XCTAssertEqual(ShortcutHint.title("Bookmark", for: .toggleBookmark, in: bindings), "Bookmark (B)")
        XCTAssertEqual(ShortcutHint.title("Play / Pause", for: .playPause, in: bindings), "Play / Pause (Space)")
        XCTAssertEqual(ShortcutHint.title("Previous file", for: .previousItem, in: bindings), "Previous file (,)")
        XCTAssertEqual(ShortcutHint.title("Settings", for: .openSettings, in: bindings), "Settings (⌘,)")
    }

    func testAHintFollowsAChangedKeyAndDropsWhenUnassigned() {
        let changed = ShortcutBindings().setting([ShortcutKey(text: "J")!], for: .toggleBookmark)
        XCTAssertEqual(ShortcutHint.title("Bookmark", for: .toggleBookmark, in: changed), "Bookmark (J)")
        let none = ShortcutBindings().setting([], for: .toggleBookmark)
        XCTAssertEqual(ShortcutHint.title("Bookmark", for: .toggleBookmark, in: none), "Bookmark")
    }
}
