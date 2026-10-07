import XCTest

final class ShortcutsModelTests: XCTestCase {
    private var groups: [ShortcutGroup] { ShortcutsCatalog.groups }
    private var allEntries: [ShortcutEntry] { groups.flatMap(\.items) }

    func testGroupsAreByTaskInTheDesignSystemOrder() {
        XCTAssertEqual(groups.map(\.title),
                       ["Playback", "Navigation", "File markers", "Queue & window", "Skip & audio sync"])
    }

    func testOnlyTheLastGroupIsLabelledPlayerOnly() {
        XCTAssertEqual(groups.map(\.appLabel), [nil, nil, nil, nil, "dwb player"])
    }

    func testEveryExistingShortcutIsListedExactlyOnce() {
        // The 34 rows from the previous five window-based groups, regrouped by task.
        let expected: [String] = [
            "Open Settings", "Quit dwb player", "Open File", "Reveal in Finder", "Clear Queue", "New Window",
            "Play / Pause", "Rewind by skip duration", "Forward by skip duration", "Volume Up", "Volume Down",
            "Previous Item", "Next Item", "Bookmark Current Item", "Primary Prefix Rename",
            "Secondary Prefix Rename", "Undo Marker Rename", "Advance Audio (Play Sooner)",
            "Delay Audio (Play Later)", "Reset Audio Sync", "Shuffle", "Endless Shuffle", "Repeat One",
            "10 seconds", "30 seconds", "60 seconds", "3 minutes",
            "Fit", "Fill", "Stretch", "Minimize", "Four Window Grid",
            "Remove selected queue rows", "Move Settings sidebar selection"
        ]
        let actual = allEntries.map(\.action)
        XCTAssertEqual(Set(actual), Set(expected))
        XCTAssertEqual(actual.count, expected.count, "no shortcut is listed twice")
    }

    func testFileMarkerGroupHoldsTheTwoPrefixesAndUndo() {
        let markers = groups.first { $0.title == "File markers" }
        XCTAssertEqual(markers?.items.map(\.action),
                       ["Primary Prefix Rename", "Secondary Prefix Rename", "Undo Marker Rename"])
        XCTAssertEqual(markers?.items.map(\.keys), [["N"], ["M"], ["⌘Z"]])
        XCTAssertEqual(markers?.items.map(\.tone), [.markerPrimary, .markerSecondary, .accent])
    }

    func testSkipPresetsBookmarkAndAudioSyncSitInTheLabelledGroup() {
        let player = groups.last?.items.map(\.action) ?? []
        XCTAssertTrue(player.contains("10 seconds"))
        XCTAssertTrue(player.contains("Bookmark Current Item"))
        XCTAssertTrue(player.contains("Reset Audio Sync"))
    }

    func testKeysAreSplitIntoOneCapEach() {
        let rewind = allEntries.first { $0.action == "Rewind by skip duration" }
        XCTAssertEqual(rewind?.keys, ["←", "⌥←"])
        let remove = allEntries.first { $0.action == "Remove selected queue rows" }
        XCTAssertEqual(remove?.keys, ["Delete", "Forward Delete"])
    }

    func testMapKeysKeepOnlyUnmodifiedKeysOnTheMap() {
        let rewind = allEntries.first { $0.action == "Rewind by skip duration" }
        XCTAssertEqual(rewind?.mapKeys, ["←"])
        let undo = allEntries.first { $0.action == "Undo Marker Rename" }
        XCTAssertEqual(undo?.mapKeys, [])
        let audio = allEntries.first { $0.action == "Advance Audio (Play Sooner)" }
        XCTAssertEqual(audio?.mapKeys, ["["])
    }

    func testMarkerKeysTakeTheMarkerTones() {
        let tones = ShortcutKeyMap.tones(for: groups)
        XCTAssertEqual(tones["N"], .markerPrimary)
        XCTAssertEqual(tones["M"], .markerSecondary)
        XCTAssertEqual(tones["Space"], .accent)
        XCTAssertNil(tones["Q"], "keys without a shortcut stay unused")
    }

    // MARK: Search

    func testEmptyQueryKeepsEveryGroupAndRow() {
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: ""), groups)
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: "   "), groups)
    }

    func testTypingAudioLeavesTheAudioSyncRows() {
        let result = ShortcutsSearch.filter(groups, query: "audio")
        XCTAssertEqual(result.map(\.title), ["Skip & audio sync"])
        XCTAssertEqual(result.flatMap(\.items).map(\.action),
                       ["Advance Audio (Play Sooner)", "Delay Audio (Play Later)", "Reset Audio Sync"])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(ShortcutsSearch.filter(groups, query: "AUDIO"), ShortcutsSearch.filter(groups, query: "audio"))
    }

    func testSearchMatchesKeyText() {
        let result = ShortcutsSearch.filter(groups, query: "⌘z").flatMap(\.items).map(\.action)
        XCTAssertEqual(result, ["Undo Marker Rename"])
    }

    func testSearchDropsGroupsLeftEmpty() {
        let result = ShortcutsSearch.filter(groups, query: "primary prefix")
        XCTAssertEqual(result.map(\.title), ["File markers"])
        XCTAssertEqual(result.first?.items.count, 1)
    }

    func testNoMatchReturnsNoGroups() {
        XCTAssertTrue(ShortcutsSearch.filter(groups, query: "zzzz").isEmpty)
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
    func testPageNamesAndOrderAreUnchanged() {
        XCTAssertEqual(SettingsPages.all.map(\.name),
                       ["Playback", "Controls", "Queue & Files", "Shortcuts", "Advanced", "About"])
    }

    func testSidebarGroupsAreGeneralAndSystem() {
        XCTAssertEqual(SettingsPages.groups.map(\.label), ["General", "System"])
        XCTAssertEqual(SettingsPages.groups[0].pageIndices.map { SettingsPages.all[$0].name },
                       ["Playback", "Controls", "Queue & Files", "Shortcuts"])
        XCTAssertEqual(SettingsPages.groups[1].pageIndices.map { SettingsPages.all[$0].name },
                       ["Advanced", "About"])
    }

    func testEveryPageHasAOneLineDescription() {
        for page in SettingsPages.all {
            XCTAssertFalse(page.description.isEmpty, page.name)
            XCTAssertFalse(page.description.contains("\n"), page.name)
        }
        XCTAssertEqual(SettingsPages.all[0].description, "How files play, and which media types the queue accepts.")
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
