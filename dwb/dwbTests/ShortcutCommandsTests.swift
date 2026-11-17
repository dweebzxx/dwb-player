import AppKit
import XCTest

// The command table (`ShortcutCommands.swift`): the golden inventory, key notation,
// conflicts, invalid keys, the override store, and dispatch with an override.

private func key(_ text: String) -> ShortcutKey {
    guard let key = ShortcutKey(text: text) else { preconditionFailure("bad key \(text)") }
    return key
}

private func makeSuite(_ name: String = #function) -> UserDefaults {
    let suiteName = "dwb.tests.shortcuts.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// MARK: - Golden inventory

final class ShortcutInventoryTests: XCTestCase {
    /// Every keyboard path found in the code, with its context. This list was written from
    /// `AppDelegate.buildMainMenu`, `VideoSurfaceView.keyDown` (video and image), `QueuePageTableView.keyDown`,
    /// the Settings sidebar and queue divider key handlers, and the standard text commands.
    private let inventory: [String] = [
        "playPause | Playback | Play or pause | Space | editable menu=anywhere page=mediaView",
        "skipBackward | Playback | Rewind by skip duration | ←, ⌥← | editable menu=anywhere page=mediaView",
        "skipForward | Playback | Forward by skip duration | →, ⌥→ | editable menu=anywhere page=mediaView",
        "volumeUp | Playback | Volume up | ↑, ⌘↑ | editable menu=anywhere page=mediaView",
        "volumeDown | Playback | Volume down | ↓, ⌘↓ | editable menu=anywhere page=mediaView",
        "shuffle | Playback | Shuffle | ⌥⌘S | editable menu=anywhere page=mediaView",
        "endlessShuffle | Playback | Endless shuffle | ⌥⌘E | editable menu=anywhere page=mediaView",
        "repeatOne | Playback | Repeat one | ⌥⌘R | editable menu=anywhere page=mediaView",
        "previousItem | Navigation | Previous item | , | editable menu=none page=mediaView",
        "nextItem | Navigation | Next item | . | editable menu=none page=mediaView",
        "openFile | File actions | Open file | ⌘O | editable menu=anywhere page=mediaView",
        "revealInFinder | File actions | Reveal in Finder | ⇧⌘R | editable menu=anywhere page=mediaView",
        "renameFile | File actions | Rename file | R | editable menu=anywhere page=mediaOrQueue",
        "clearQueue | File actions | Clear queue | ⇧⌘⌫ | editable menu=anywhere page=mediaView",
        "togglePrimaryPrefix | File actions | Toggle primary prefix | N | editable menu=none page=mediaOrQueue",
        "toggleSecondaryPrefix | File actions | Toggle secondary prefix | M | editable menu=none page=mediaOrQueue",
        "undoPrefixChange | File actions | Undo prefix change | ⌘Z | reference context=playerWindow",
        "removeQueueRows | File actions | Remove selected queue rows | ⌫, ⌦ | reference context=queueRows",
        "toggleBookmark | Bookmarks | Toggle bookmark | B | editable menu=none page=mediaView",
        "newWindow | Window | New window | ⌘N | editable menu=anywhere page=mediaView",
        "fourWindowGrid | Window | Four window grid | ⌘4 | editable menu=anywhere page=mediaView",
        "scaleFit | Window | Fit | ⌘1 | editable menu=anywhere page=mediaView",
        "scaleFill | Window | Fill | ⌘2 | editable menu=anywhere page=mediaView",
        "scaleStretch | Window | Stretch | ⌘3 | editable menu=anywhere page=mediaView",
        "minimize | Window | Minimize | ⌘M | reference context=anywhere",
        "openSettings | Window | Open settings | ⌘, | reference context=anywhere",
        "quit | Window | Quit dwb player | ⌘Q | reference context=anywhere",
        "settingsSidebarNavigation | Window | Move Settings sidebar selection | ↑, ↓ | reference context=settingsSidebar",
        "queueDividerResize | Window | Resize queue panel | ←, →, Home | reference context=queueDivider",
        "skip10 | Skip & audio sync | 10 seconds | 1 | editable menu=none page=mediaView",
        "skip30 | Skip & audio sync | 30 seconds | 3 | editable menu=none page=mediaView",
        "skip60 | Skip & audio sync | 60 seconds | 6 | editable menu=none page=mediaView",
        "skip180 | Skip & audio sync | 3 minutes | 9 | editable menu=none page=mediaView",
        "advanceAudio | Skip & audio sync | Advance audio (play sooner) | [, ⌘[ | editable menu=anywhere page=mediaView",
        "delayAudio | Skip & audio sync | Delay audio (play later) | ], ⌘] | editable menu=anywhere page=mediaView",
        "resetAudioSync | Skip & audio sync | Reset audio sync | \\, ⌘\\ | editable menu=anywhere page=mediaView",
        "textUndo | Text editing | Undo typing | ⌘Z | reference context=textEditing",
        "textRedo | Text editing | Redo typing | ⇧⌘Z | reference context=textEditing",
        "cut | Text editing | Cut | ⌘X | reference context=anywhere",
        "copy | Text editing | Copy | ⌘C | reference context=anywhere",
        "paste | Text editing | Paste | ⌘V | reference context=anywhere",
        "selectAll | Text editing | Select all | ⌘A | reference context=anywhere"
    ]

    func testTheDefaultTableEqualsTheInventory() {
        XCTAssertEqual(ShortcutCommandTable.all.map(\.inventoryLine), inventory)
    }

    func testEveryIdentifierHasExactlyOneCommand() {
        let ids = ShortcutCommandTable.all.map(\.id)
        XCTAssertEqual(Set(ids), Set(ShortcutCommandID.allCases))
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testTheEditableCommandsAreEveryCommandExceptTheFixedEntries() {
        let fixed: Set<ShortcutCommandID> = [.undoPrefixChange, .removeQueueRows, .minimize, .openSettings, .quit,
                                             .settingsSidebarNavigation, .queueDividerResize,
                                             .textUndo, .textRedo, .cut, .copy, .paste, .selectAll]
        XCTAssertEqual(Set(ShortcutCommandTable.all.filter { !$0.isEditable }.map(\.id)), fixed)
        XCTAssertEqual(ShortcutCommandTable.editableIDs, Set(ShortcutCommandID.allCases).subtracting(fixed))
    }

    func testNoTwoDefaultKeysShareAKeyInContextsThatCanBeActiveTogether() {
        let bindings = ShortcutBindings()
        var routed: [(ShortcutCommandID, ShortcutRoutedKey)] = []
        for command in bindings.commands {
            for entry in bindings.routedKeys(for: command, keys: command.defaultKeys) {
                routed.append((command.id, entry))
            }
        }
        for (i, first) in routed.enumerated() {
            for second in routed[(i + 1)...] where first.0 != second.0 && first.1.key == second.1.key {
                XCTAssertFalse(first.1.context.overlaps(second.1.context),
                               "\(first.0) and \(second.0) share \(first.1.key.text)")
            }
        }
    }

    func testTheSameKeyIsFixedInOneContextAndUsedInAnother() {
        // ⌘Z is two commands in two contexts; ↑ is Volume up in the video and a sidebar move in Settings.
        let bindings = ShortcutBindings()
        XCTAssertEqual(bindings.commands.filter { $0.defaultKeys.contains(key("⌘Z")) }.map(\.id),
                       [.undoPrefixChange, .textUndo])
        XCTAssertEqual(bindings.commands.filter { $0.defaultKeys.contains(key("↑")) }.map(\.id),
                       [.volumeUp, .settingsSidebarNavigation])
    }

    func testMenuKeysAreTheFirstKeyWithCommandControlOrOption() {
        let bindings = ShortcutBindings()
        XCTAssertNil(bindings.menuKey(for: .playPause))
        XCTAssertEqual(bindings.menuKey(for: .skipBackward), key("⌥←"))
        XCTAssertEqual(bindings.menuKey(for: .volumeUp), key("⌘↑"))
        XCTAssertEqual(bindings.menuKey(for: .advanceAudio), key("⌘["))
        XCTAssertEqual(bindings.menuKey(for: .clearQueue), key("⇧⌘⌫"))
        XCTAssertEqual(bindings.menuKey(for: .undoPrefixChange), key("⌘Z"))
        XCTAssertEqual(bindings.menuKey(for: .quit), key("⌘Q"))
        XCTAssertNil(bindings.menuKey(for: .renameFile), "R is a page key; the Rename menu item has no key")
        XCTAssertNil(bindings.menuKey(for: .nextItem))
    }

    func testEveryKeyHasOneRouteTheMenuOrThePage() {
        let bindings = ShortcutBindings()
        // A menu key never runs from the page, and the page keys never carry a menu item.
        XCTAssertNil(bindings.pageCommand(for: key("⌘↑"), surface: .video))
        XCTAssertNil(bindings.pageCommand(for: key("⌥←"), surface: .video))
        XCTAssertNil(bindings.pageCommand(for: key("⌘["), surface: .image))
        XCTAssertEqual(bindings.pageCommand(for: key("↑"), surface: .video), .volumeUp)
        XCTAssertEqual(bindings.pageCommand(for: key("["), surface: .image), .advanceAudio)
    }

    func testTextEditingRowsAndOrder() {
        let rows = ShortcutCommandTable.all.filter { $0.group == .textEditing }
        XCTAssertEqual(rows.map(\.id), [.textUndo, .textRedo, .cut, .copy, .paste, .selectAll])
        XCTAssertEqual(rows.map(\.name), ["Undo typing", "Redo typing", "Cut", "Copy", "Paste", "Select all"])
        XCTAssertEqual(rows.map { $0.defaultKeys.single?.text }, ["⌘Z", "⇧⌘Z", "⌘X", "⌘C", "⌘V", "⌘A"])
        XCTAssertEqual(rows.map(\.note), [
            "While a text field is being edited.", "While a text field is being edited.",
            "Acts on the text field being edited. The key is reserved in every window.",
            "Acts on the text field being edited. The key is reserved in every window.",
            "Acts on the text field being edited. The key is reserved in every window.",
            "Acts on the text field being edited. The key is reserved in every window."
        ])
        XCTAssertEqual(ShortcutCommandTable.command(.undoPrefixChange).group, .fileActions)
    }

    func testPlayPauseDefaultsToSpaceOnly() {
        let bindings = ShortcutBindings()
        XCTAssertEqual(bindings.activeKeys(for: .playPause), [key("Space")])
        XCTAssertNil(bindings.menuKey(for: .playPause))
        XCTAssertEqual(bindings.pageCommand(for: key("Space"), surface: .video), .playPause)
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

// MARK: - Key notation

final class ShortcutKeyNotationTests: XCTestCase {
    func testModifiersAreWrittenInTheStandardOrder() {
        XCTAssertEqual(ShortcutKey.character("s", [.command, .option]).text, "⌥⌘S")
        XCTAssertEqual(ShortcutKey.character("s", [.command, .shift, .option, .control]).text, "⌃⌥⇧⌘S")
        XCTAssertEqual(ShortcutKey.special(.delete, [.command, .shift]).text, "⇧⌘⌫")
        XCTAssertEqual(ShortcutModifiers([.command, .control]).symbols, "⌃⌘")
    }

    func testSpecialKeysUseTheirKeyCapText() {
        XCTAssertEqual(ShortcutKey.special(.space).text, "Space")
        XCTAssertEqual([ShortcutSpecialKey.left, .right, .up, .down].map { ShortcutKey.special($0).text }, ["←", "→", "↑", "↓"])
        XCTAssertEqual(ShortcutKey.special(.forwardDelete).text, "⌦")
        XCTAssertEqual(ShortcutKey.special(.home).text, "Home")
    }

    func testCharactersAreShownUppercaseAndStoredLowercase() {
        XCTAssertEqual(ShortcutKey.character("N").text, "N")
        XCTAssertEqual(ShortcutKey.character("N"), ShortcutKey.character("n"))
        XCTAssertEqual(ShortcutKey.character(",").text, ",")
        XCTAssertEqual(ShortcutKey.character("\\").text, "\\")
    }

    func testKeysReadBackFromTheirText() {
        for text in ["N", "⌥⌘S", "⇧⌘⌫", "Space", "←", "⌘↑", ",", "[", "⌘\\", "Home", "⌦", "1"] {
            XCTAssertEqual(ShortcutKey(text: text)?.text, text, text)
        }
        XCTAssertEqual(ShortcutKey(text: "⌘⌥S"), ShortcutKey(text: "⌥⌘S"), "modifier order in the input does not matter")
    }

    func testTextThatIsNotAKeyDoesNotParse() {
        for text in ["", "⌘", "⌥⌘", "NN", "Spaces", "space", "Enter", "⌘Tab"] {
            XCTAssertNil(ShortcutKey(text: text), "'\(text)'")
        }
    }

    func testSpokenFormsNameTheModifiersAndKeys() {
        XCTAssertEqual(key("⌥⌘S").spokenText, "option command S")
        XCTAssertEqual(key("⇧⌘⌫").spokenText, "shift command delete")
        XCTAssertEqual(key("←").spokenText, "left arrow")
        XCTAssertEqual(key(",").spokenText, "comma")
        XCTAssertEqual(key("⌘\\").spokenText, "command backslash")
        XCTAssertEqual(key("Space").spokenText, "space")
    }

    func testOnlyUnmodifiedKeysOnTheMapHaveAMapLabel() {
        XCTAssertEqual(key("N").mapLabel, "N")
        XCTAssertEqual(key("Space").mapLabel, "Space")
        XCTAssertEqual(key("←").mapLabel, "←")
        XCTAssertEqual(key("[").mapLabel, "[")
        XCTAssertNil(key("⌘N").mapLabel)
        XCTAssertNil(key("1").mapLabel, "digits are not on the map")
        XCTAssertNil(key("⌫").mapLabel)
    }

    func testKeyPressesBecomeKeysTheWayTheDispatchMatchesThem() {
        // Key codes for Space and the arrows; characters ignoring modifiers for the rest.
        XCTAssertEqual(ShortcutKey.make(keyCode: 49, charactersIgnoringModifiers: " ", modifiers: []), key("Space"))
        XCTAssertEqual(ShortcutKey.make(keyCode: 123, charactersIgnoringModifiers: "\u{F702}", modifiers: [.option]), key("⌥←"))
        XCTAssertEqual(ShortcutKey.make(keyCode: 126, charactersIgnoringModifiers: "\u{F700}", modifiers: [.command]), key("⌘↑"))
        XCTAssertEqual(ShortcutKey.make(keyCode: 51, charactersIgnoringModifiers: "\u{7F}", modifiers: [.command, .shift]), key("⇧⌘⌫"))
        XCTAssertEqual(ShortcutKey.make(keyCode: 45, charactersIgnoringModifiers: "n", modifiers: []), key("N"))
        XCTAssertEqual(ShortcutKey.make(keyCode: 45, charactersIgnoringModifiers: "N", modifiers: [.shift]), key("⇧N"))
        XCTAssertEqual(ShortcutKey.make(keyCode: 43, charactersIgnoringModifiers: ",", modifiers: []), key(","))
    }

    func testKeysTheDispatchCannotMatchGiveNil() {
        XCTAssertNil(ShortcutKey.make(keyCode: 36, charactersIgnoringModifiers: "\r", modifiers: []), "Return")
        XCTAssertNil(ShortcutKey.make(keyCode: 48, charactersIgnoringModifiers: "\t", modifiers: []), "Tab")
        XCTAssertNil(ShortcutKey.make(keyCode: 53, charactersIgnoringModifiers: "\u{1B}", modifiers: []), "Escape")
        XCTAssertNil(ShortcutKey.make(keyCode: 122, charactersIgnoringModifiers: "\u{F704}", modifiers: []), "F1")
        XCTAssertNil(ShortcutKey.make(keyCode: 55, charactersIgnoringModifiers: "", modifiers: [.command]), "a modifier alone")
        XCTAssertNil(ShortcutKey.make(keyCode: 0, charactersIgnoringModifiers: nil, modifiers: []))
    }

    func testEveryRecordableBaseKeyAndEveryExcludedControlKey() {
        for text in ["A", "5", ".", "€", "Space", "←", "→", "↑", "↓", "⌫", "⌦"] {
            XCTAssertTrue(ShortcutKeyRules.isDeliverable(key(text)), text)
        }
        for text in ["Return", "Enter", "Tab", "Escape", "F1", "Home", "End", "Page Up", "Page Down"] {
            if let parsed = ShortcutKey(text: text) {
                XCTAssertFalse(ShortcutKeyRules.isDeliverable(parsed), text)
            } else {
                XCTAssertNil(ShortcutKey(text: text), text)
            }
        }
        for code in [UInt16(36), 76, 48, 53, 115, 119, 116, 121, 122] {
            XCTAssertNil(ShortcutKey.make(keyCode: code, charactersIgnoringModifiers: "a", modifiers: []), "key code \(code)")
        }
        XCTAssertNil(ShortcutKey.make(keyCode: 55, charactersIgnoringModifiers: "", modifiers: [.command]))
    }

    func testModifierRuleAcceptsEveryCommandControlOptionMixAndRejectsShiftOnly() {
        for text in ["A", "5", ".", "Space", "←", "→", "↑", "↓", "⌫", "⌦"] {
            let base = key(text).base
            XCTAssertTrue(ShortcutKeyRules.isDeliverable(ShortcutKey(base)), text)
            for modifiers in [ShortcutModifiers.command, .control, .option,
                                                 [.command, .control], [.command, .option], [.control, .option],
                                                 [.command, .control, .option]] {
                XCTAssertTrue(ShortcutKeyRules.isDeliverable(ShortcutKey(base, modifiers)), text)
                let shifted = ShortcutKey(base, modifiers.union(.shift))
                let isNonLetterCharacter: Bool
                if case .character(let character) = base { isNonLetterCharacter = !(character.first?.isLetter ?? false) }
                else { isNonLetterCharacter = false }
                XCTAssertEqual(ShortcutKeyRules.isDeliverable(shifted), !isNonLetterCharacter, shifted.text)
            }
            XCTAssertEqual(ShortcutKeyRules.isDeliverable(ShortcutKey(base, .shift)), false, text)
        }
        XCTAssertTrue(ShortcutKeyRules.isDeliverable(key("⇧⌘A")))
        XCTAssertFalse(ShortcutKeyRules.isDeliverable(key("⇧⌘5")))
    }
}

// MARK: - Conflicts and invalid keys

final class ShortcutConflictTests: XCTestCase {
    private let bindings = ShortcutBindings()

    func testAKeyAnotherCommandUsesInTheSameContextIsAConflict() {
        XCTAssertEqual(bindings.validate(key("N"), for: .nextItem, replacing: 0), .conflict(.togglePrimaryPrefix))
        XCTAssertEqual(bindings.validate(key("←"), for: .nextItem, replacing: 0), .conflict(.skipBackward))
        XCTAssertEqual(bindings.validate(key("⌘O"), for: .nextItem, replacing: 0), .conflict(.openFile),
                       "a menu key is active in every window")
    }

    func testACommandNeverConflictsWithItself() {
        XCTAssertEqual(bindings.validate(key("."), for: .nextItem, replacing: 0), .ok)
        XCTAssertEqual(bindings.validate(key("↑"), for: .volumeUp, replacing: 0), .ok)
        // The command's own other key is not a conflict either; the keys are merged.
        XCTAssertEqual(bindings.validate(key("⌘↑"), for: .volumeUp, replacing: 0), .ok)
    }

    func testContextsThatCannotBeActiveTogetherMayShareAKey() {
        // Delete removes queue rows only with the queue list focused; the video view has no Delete key.
        XCTAssertEqual(bindings.validate(key("⌫"), for: .nextItem, replacing: 0), .ok)
        // The Settings sidebar uses ← and →? No: it uses ↑ and ↓, which the video view also uses.
        XCTAssertEqual(bindings.validate(key("↑"), for: .volumeUp, replacing: 0), .ok)
        XCTAssertFalse(ShortcutContext.textEditing.overlaps(.mediaView))
        XCTAssertFalse(ShortcutContext.textEditing.overlaps(.playerWindow))
        XCTAssertFalse(ShortcutContext.settingsSidebar.overlaps(.mediaView))
        XCTAssertFalse(ShortcutContext.queueDivider.overlaps(.mediaOrQueue))
        XCTAssertTrue(ShortcutContext.queueRows.overlaps(.mediaOrQueue))
        XCTAssertTrue(ShortcutContext.anywhere.overlaps(.textEditing))
    }

    func testAPlayerWindowCommandCannotTakeCommandZ() {
        XCTAssertEqual(bindings.validate(key("⌘Z"), for: .nextItem, replacing: 0), .conflict(.textUndo))
        XCTAssertEqual(bindings.validate(key("⌘Z"), for: .toggleBookmark, replacing: nil), .conflict(.textUndo))
    }

    func testTheTextEditingCommandZIsReservedDespiteItsSeparateContext() {
        // Only the player-window entry is named; the text-editing entry is in a context
        // that player-window page commands never share.
        XCTAssertFalse(ShortcutContext.mediaView.overlaps(.textEditing))
        XCTAssertFalse(ShortcutContext.mediaOrQueue.overlaps(.textEditing))
        XCTAssertEqual(bindings.validate(key("⌘Z"), for: .nextItem, replacing: 0), .conflict(.textUndo), "the text key is reserved")
    }

    func testAKeyAFixedEntryOwnsInAnOverlappingContextIsAConflict() {
        XCTAssertEqual(bindings.validate(key("⌘Q"), for: .toggleBookmark, replacing: 0), .conflict(.quit))
        XCTAssertEqual(bindings.validate(key("⌘,"), for: .toggleBookmark, replacing: 0), .conflict(.openSettings))
        XCTAssertEqual(bindings.validate(key("⌘C"), for: .toggleBookmark, replacing: 0), .conflict(.copy))
        // Rename works in the queue list, where Delete removes rows.
        XCTAssertEqual(bindings.validate(key("⌫"), for: .renameFile, replacing: 0), .conflict(.removeQueueRows))
    }

    func testAConflictNeverOverwritesTheOtherCommand() {
        let after = bindings.setting(bindings.keys(for: .nextItem, replacing: 0, with: key("J")), for: .nextItem)
        XCTAssertEqual(after.activeKeys(for: .togglePrimaryPrefix), [key("N")])
        XCTAssertEqual(after.validate(key("J"), for: .previousItem, replacing: 0), .conflict(.nextItem))
    }

    func testTheNewKeyAfterAChangeIsFreeAndTheOldKeyIsFreeAgain() {
        let after = bindings.setting([key("J")], for: .nextItem)
        XCTAssertEqual(after.validate(key("."), for: .previousItem, replacing: 0), .ok)
        XCTAssertEqual(after.validate(key("J"), for: .previousItem, replacing: 0), .conflict(.nextItem))
    }

    func testAnExtraModifiedKeyOnAMenuCommandRunsThroughTheMenu() {
        XCTAssertEqual(bindings.validate(key("⌘J"), for: .volumeUp, replacing: nil), .ok)
        let after = bindings.setting(bindings.keys(for: .volumeUp, replacing: nil, with: key("⌘J")), for: .volumeUp)
        XCTAssertEqual(after.menuKey(for: .volumeUp), key("⌘↑"))
        XCTAssertEqual(after.menuKeys(for: .volumeUp), [key("⌘↑"), key("⌘J")])
        XCTAssertNil(after.pageCommand(for: key("⌘J"), surface: .video))
    }

    func testAnyNumberAndMixOfKeysAreAcceptedForEachEditableAction() {
        var bindings = ShortcutBindings()
        XCTAssertEqual(bindings.validate(key("⌥⌘K"), for: .nextItem, replacing: nil), .ok)
        bindings = bindings.setting([key("."), key("⌥⌘K"), key("⌃K")], for: .nextItem)
        XCTAssertEqual(bindings.pageCommand(for: key("⌥⌘K"), surface: .video), .nextItem)
        XCTAssertEqual(bindings.pageCommand(for: key("⌃K"), surface: .video), .nextItem)
        XCTAssertEqual(bindings.menuKeys(for: .nextItem), [])

        XCTAssertEqual(bindings.validate(key("⌃P"), for: .playPause, replacing: nil), .ok)
        bindings = bindings.setting([key("Space"), key("⌃P"), key("⌥P")], for: .playPause)
        XCTAssertEqual(bindings.validate(key("⌥P"), for: .playPause, replacing: nil), .ok)
        XCTAssertEqual(bindings.activeKeys(for: .playPause), [key("Space"), key("⌃P"), key("⌥P")])
        XCTAssertEqual(bindings.menuKeys(for: .playPause), [key("⌃P"), key("⌥P")])
        XCTAssertEqual(bindings.menuKey(for: .playPause), key("⌃P"))
        XCTAssertEqual(bindings.pageCommand(for: key("Space"), surface: .video), .playPause)
        XCTAssertNil(bindings.pageCommand(for: key("⌃P"), surface: .video))
        XCTAssertNil(bindings.pageCommand(for: key("⌥P"), surface: .video))
    }

    func testAKeyPressHasOnlyOneRouteAndAConflictUsesItsRouteContext() {
        let bindings = ShortcutBindings().setting([key("Space"), key("⌃P"), key("⌥P")], for: .playPause)
        let routed = bindings.routedKeys(for: bindings.command(.playPause), keys: bindings.activeKeys(for: .playPause))
        XCTAssertEqual(routed.map(\.context), [.mediaView, .anywhere, .anywhere])
        XCTAssertEqual(routed.filter { $0.key == key("⌥P") }.count, 1)
        XCTAssertNil(bindings.pageCommand(for: key("⌥P"), surface: .video))
        XCTAssertEqual(bindings.validate(key("⌥P"), for: .nextItem, replacing: nil), .conflict(.playPause))
        XCTAssertEqual(bindings.validate(key("Space"), for: .nextItem, replacing: nil), .conflict(.playPause))
    }

    func testEveryTextEditingKeyIsReservedForEveryEditableAction() {
        let reserved: [(String, ShortcutCommandID)] = [
            ("⌘Z", .textUndo), ("⇧⌘Z", .textRedo), ("⌘X", .cut),
            ("⌘C", .copy), ("⌘V", .paste), ("⌘A", .selectAll)
        ]
        for id in ShortcutCommandTable.editableIDs {
            for (text, owner) in reserved {
                XCTAssertEqual(bindings.validate(key(text), for: id, replacing: nil), .conflict(owner), "\(id): \(text)")
            }
        }
    }

    // MARK: Invalid keys

    func testAModifierAloneOrAnUnmatchableKeyIsInvalid() {
        XCTAssertEqual(bindings.validate(nil, for: .nextItem, replacing: 0), .invalid)
    }

    func testShiftOnlyAndShiftWithANonLetterCharacterAreInvalid() {
        XCTAssertEqual(bindings.validate(ShortcutKey.character("1", .shift), for: .nextItem, replacing: 0), .invalid)
        XCTAssertEqual(bindings.validate(ShortcutKey.character("[", .shift), for: .nextItem, replacing: 0), .invalid)
        XCTAssertEqual(bindings.validate(key("⇧J"), for: .nextItem, replacing: 0), .invalid)
        XCTAssertEqual(bindings.validate(key("⇧⌫"), for: .nextItem, replacing: 0), .invalid)
        XCTAssertEqual(bindings.validate(key("⇧⌘J"), for: .nextItem, replacing: 0), .ok)
        XCTAssertEqual(bindings.validate(key("⇧⌥⌫"), for: .nextItem, replacing: 0), .ok)
    }

    func testAFixedCommandHasNoEditor() {
        XCTAssertEqual(bindings.validate(key("J"), for: .quit, replacing: 0), .invalid)
        XCTAssertEqual(bindings.validate(key("J"), for: .undoPrefixChange, replacing: 0), .invalid)
    }

    func testAKeyAnotherCommandOwnsIsAConflictNotInvalid() {
        // ⇧⌘R belongs to Reveal in Finder; it is deliverable, so the message is the conflict.
        XCTAssertEqual(bindings.validate(key("⇧⌘R"), for: .nextItem, replacing: 0), .conflict(.revealInFinder))
    }
}

// MARK: - Overrides

final class ShortcutOverrideStoreTests: XCTestCase {
    func testOverridesRoundTripThroughUserDefaults() {
        let defaults = makeSuite()
        let store = ShortcutOverrideStore(defaults: defaults)
        store.save([.nextItem: [key("J")], .togglePrimaryPrefix: [key("K"), key("H")], .volumeUp: [key("↑")]])
        let loaded = ShortcutOverrideStore(defaults: defaults).load()
        XCTAssertEqual(loaded[.nextItem], [key("J")])
        XCTAssertEqual(loaded[.togglePrimaryPrefix], [key("K"), key("H")])
        XCTAssertEqual(loaded[.volumeUp], [key("↑")])
        XCTAssertEqual(loaded.count, 3)
    }

    func testTheStoredFormatIsOneDictionaryFromIdentifierToKeyTexts() {
        let defaults = makeSuite()
        ShortcutOverrideStore(defaults: defaults).save([.nextItem: [key("J")], .togglePrimaryPrefix: [key("K"), key("H")]])
        let stored = defaults.dictionary(forKey: "shortcutOverrides") as? [String: [String]]
        XCTAssertEqual(stored, ["nextItem": ["J"], "togglePrimaryPrefix": ["K", "H"]])
        XCTAssertEqual(ShortcutOverrideStore.defaultsKey, "shortcutOverrides")
    }

    func testUnknownIdentifiersAndFixedCommandsInStoredDataAreIgnored() {
        let defaults = makeSuite()
        defaults.set(["noSuchCommand": ["J"], "quit": ["J"], "nextItem": ["J"]], forKey: "shortcutOverrides")
        let loaded = ShortcutOverrideStore(defaults: defaults).load()
        XCTAssertEqual(loaded, [.nextItem: [key("J")]])
    }

    func testKeyTextsThatDoNotParseAreIgnored() {
        let defaults = makeSuite()
        defaults.set(["nextItem": ["J", "not a key"], "previousItem": ["nope"], "shuffle": []],
                     forKey: "shortcutOverrides")
        let loaded = ShortcutOverrideStore(defaults: defaults).load()
        XCTAssertEqual(loaded[.nextItem], [key("J")])
        XCTAssertNil(loaded[.previousItem], "an entry whose keys all fail to parse falls back to the defaults")
        XCTAssertEqual(loaded[.shuffle], [], "an empty list is a command with no keys")
    }

    func testStoredInvalidKeyIsIgnoredWithoutRewritingOtherKeys() {
        let defaults = makeSuite()
        let original = ["nextItem": ["J", "Home", "⇧K", "Return", "⌥⌘K"]]
        defaults.set(original, forKey: "shortcutOverrides")
        let loaded = ShortcutOverrideStore(defaults: defaults).load()
        XCTAssertEqual(loaded[.nextItem], [key("J"), key("⌥⌘K")])
        XCTAssertEqual(defaults.dictionary(forKey: "shortcutOverrides") as? [String: [String]], original)
    }

    func testStoredDataOfTheWrongShapeIsIgnored() {
        let defaults = makeSuite()
        defaults.set("not a dictionary", forKey: "shortcutOverrides")
        XCTAssertTrue(ShortcutOverrideStore(defaults: defaults).load().isEmpty)
        defaults.set(["nextItem": "J"], forKey: "shortcutOverrides")
        XCTAssertTrue(ShortcutOverrideStore(defaults: defaults).load().isEmpty)
    }

    func testSavingNoOverridesRemovesTheKey() {
        let defaults = makeSuite()
        let store = ShortcutOverrideStore(defaults: defaults)
        store.save([.nextItem: [key("J")]])
        store.save([:])
        XCTAssertNil(defaults.object(forKey: "shortcutOverrides"))
    }

    func testRemoveKeepsTheOtherKeysOfTheCommand() {
        let bindings = ShortcutBindings()
        // Volume up has ↑ and ⌘↑. Remove ⌘↑ (index 1).
        let keys = bindings.keys(for: .volumeUp, replacing: 1, with: nil)
        XCTAssertEqual(keys, [key("↑")])
        let after = bindings.setting(keys, for: .volumeUp)
        XCTAssertNil(after.menuKey(for: .volumeUp), "the menu item has no key")
        XCTAssertEqual(after.pageCommand(for: key("↑"), surface: .video), .volumeUp, "↑ still works")
    }

    func testRemovingTheOnlyKeyLeavesTheCommandUnassigned() {
        let bindings = ShortcutBindings()
        let after = bindings.setting(bindings.keys(for: .togglePrimaryPrefix, replacing: 0, with: nil), for: .togglePrimaryPrefix)
        XCTAssertEqual(after.activeKeys(for: .togglePrimaryPrefix), [])
        XCTAssertEqual(after.overrides[.togglePrimaryPrefix], [], "stored as an empty list, not as the default")
        XCTAssertNil(after.pageCommand(for: key("N"), surface: .video))
    }

    func testAddingAKeyKeepsTheOthersAndDropsRepeats() {
        let bindings = ShortcutBindings()
        XCTAssertEqual(bindings.keys(for: .togglePrimaryPrefix, replacing: nil, with: key("H")), [key("N"), key("H")])
        XCTAssertEqual(bindings.keys(for: .togglePrimaryPrefix, replacing: nil, with: key("N")), [key("N")])
    }

    func testKeysEqualToTheDefaultsDropTheOverride() {
        let changed = ShortcutBindings().setting([key("J")], for: .nextItem)
        XCTAssertNotNil(changed.overrides[.nextItem])
        XCTAssertNil(changed.setting([key(".")], for: .nextItem).overrides[.nextItem])
    }

    func testRestoreDefaultsClearsEveryOverrideAndNothingElse() {
        let defaults = makeSuite()
        defaults.set(60, forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds)
        defaults.set("keep_", forKey: SettingsDefaultsRegistry.Keys.customPrefixValue)
        let registry = ShortcutRegistry(store: ShortcutOverrideStore(defaults: defaults), center: NotificationCenter())
        registry.setKeys([key("J")], for: .nextItem)
        registry.setKeys([key("K")], for: .togglePrimaryPrefix)
        registry.restoreDefaults()
        XCTAssertTrue(ShortcutOverrideStore(defaults: defaults).load().isEmpty)
        XCTAssertEqual(registry.bindings.activeKeys(for: .nextItem), [key(".")])
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds), 60)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.customPrefixValue), "keep_")
    }

    func testRestoreAllSettingsToDefaultClearsTheOverridesWithTheOtherPreferences() {
        let defaults = makeSuite()
        defaults.set(60, forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds)
        defaults.set("keep_", forKey: SettingsDefaultsRegistry.Keys.customPrefixValue)
        let registry = ShortcutRegistry(store: ShortcutOverrideStore(defaults: defaults), center: NotificationCenter())
        registry.setKeys([key("J")], for: .nextItem)
        SettingsDefaultsRegistry.restoreAll(in: defaults, reduceMotionDefault: false)
        XCTAssertNil(defaults.object(forKey: "shortcutOverrides"))
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds), 10)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.customPrefixValue), "")
        registry.reload()
        XCTAssertEqual(registry.bindings.activeKeys(for: .nextItem), [key(".")])
    }

    func testAdvancedResetReloadsDefaultPageAndMenuKeys() {
        let defaults = makeSuite()
        let registry = ShortcutRegistry(store: ShortcutOverrideStore(defaults: defaults), center: NotificationCenter())
        registry.setKeys([key("J")], for: .nextItem)
        registry.setKeys([key("K")], for: .volumeUp)
        XCTAssertEqual(registry.bindings.pageCommand(for: key("J"), surface: .video), .nextItem)
        XCTAssertNil(registry.bindings.menuKey(for: .volumeUp))

        SettingsDefaultsRegistry.restoreAll(in: defaults, reduceMotionDefault: false)
        registry.reload()

        XCTAssertNil(defaults.object(forKey: "shortcutOverrides"))
        XCTAssertNil(registry.bindings.pageCommand(for: key("J"), surface: .video))
        XCTAssertEqual(registry.bindings.pageCommand(for: key("."), surface: .video), .nextItem)
        XCTAssertEqual(registry.bindings.menuKey(for: .volumeUp), key("⌘↑"))
    }

    func testTheRegistryReloadsSavedOverridesOnTheNextLaunch() {
        let defaults = makeSuite()
        ShortcutRegistry(store: ShortcutOverrideStore(defaults: defaults), center: NotificationCenter())
            .setKeys([key("J")], for: .nextItem)
        let relaunched = ShortcutRegistry(store: ShortcutOverrideStore(defaults: defaults), center: NotificationCenter())
        XCTAssertEqual(relaunched.bindings.activeKeys(for: .nextItem), [key("J")])
    }

    func testEveryChangePostsOneNotification() {
        let center = NotificationCenter()
        let registry = ShortcutRegistry(store: ShortcutOverrideStore(defaults: makeSuite()), center: center)
        var count = 0
        let token = center.addObserver(forName: ShortcutRegistry.didChangeNotification, object: nil, queue: nil) { _ in count += 1 }
        defer { center.removeObserver(token) }
        registry.setKeys([key("J")], for: .nextItem)
        registry.restoreDefaults()
        registry.reload()
        XCTAssertEqual(count, 3)
    }
}

// MARK: - Dispatch with an override

final class ShortcutDispatchTests: XCTestCase {
    private let bindings = ShortcutBindings()

    func testTheDefaultKeysRunTheirCommandsOnTheVideoAndOnImages() {
        let expected: [(String, ShortcutCommandID)] = [
            ("Space", .playPause), ("←", .skipBackward), ("→", .skipForward), ("↑", .volumeUp), ("↓", .volumeDown),
            (",", .previousItem), (".", .nextItem), ("N", .togglePrimaryPrefix), ("M", .toggleSecondaryPrefix),
            ("R", .renameFile), ("B", .toggleBookmark), ("1", .skip10), ("3", .skip30), ("6", .skip60), ("9", .skip180),
            ("[", .advanceAudio), ("]", .delayAudio), ("\\", .resetAudioSync)
        ]
        for surface in [ShortcutSurface.video, .image] {
            for (text, command) in expected {
                XCTAssertEqual(bindings.pageCommand(for: key(text), surface: surface), command, "\(text) on \(surface)")
            }
        }
    }

    func testTheQueueListRunsOnlyThePrefixAndRenameKeys() {
        XCTAssertEqual(bindings.pageCommand(for: key("N"), surface: .queueTable), .togglePrimaryPrefix)
        XCTAssertEqual(bindings.pageCommand(for: key("M"), surface: .queueTable), .toggleSecondaryPrefix)
        XCTAssertEqual(bindings.pageCommand(for: key("R"), surface: .queueTable), .renameFile)
        XCTAssertNil(bindings.pageCommand(for: key("Space"), surface: .queueTable))
        XCTAssertNil(bindings.pageCommand(for: key("B"), surface: .queueTable))
        XCTAssertNil(bindings.pageCommand(for: key("."), surface: .queueTable))
    }

    func testAKeyWithModifiersDoesNotRunAPlainKeyCommand() {
        for surface in [ShortcutSurface.video, .image, .queueTable] {
            XCTAssertNil(bindings.pageCommand(for: key("⇧N"), surface: surface))
            XCTAssertNil(bindings.pageCommand(for: key("⌘N"), surface: surface))
            XCTAssertNil(bindings.pageCommand(for: key("⌥R"), surface: surface))
        }
        XCTAssertNil(bindings.pageCommand(for: key("⇧Space"), surface: .video))
    }

    func testChangingNextItemToJMovesTheKeyOnTheVideoAndOnImages() {
        let changed = bindings.setting([key("J")], for: .nextItem)
        for surface in [ShortcutSurface.video, .image] {
            XCTAssertEqual(changed.pageCommand(for: key("J"), surface: surface), .nextItem)
            XCTAssertNil(changed.pageCommand(for: key("."), surface: surface), "the old key no longer works")
        }
        XCTAssertNil(changed.pageCommand(for: key("J"), surface: .queueTable), "Next item is not a queue-list key")
    }

    func testChangingTheRenameKeyMovesItInTheQueueSelectionContextToo() {
        let changed = bindings.setting([key("K")], for: .renameFile)
        XCTAssertEqual(changed.pageCommand(for: key("K"), surface: .queueTable), .renameFile)
        XCTAssertEqual(changed.pageCommand(for: key("K"), surface: .video), .renameFile)
        XCTAssertNil(changed.pageCommand(for: key("R"), surface: .queueTable))
        XCTAssertNil(changed.pageCommand(for: key("R"), surface: .image))
    }

    func testChangingThePrefixKeyAndAddingASecondKey() {
        let changed = bindings.setting([key("K"), key("H")], for: .togglePrimaryPrefix)
        for surface in [ShortcutSurface.video, .image, .queueTable] {
            XCTAssertEqual(changed.pageCommand(for: key("K"), surface: surface), .togglePrimaryPrefix)
            XCTAssertEqual(changed.pageCommand(for: key("H"), surface: surface), .togglePrimaryPrefix)
            XCTAssertNil(changed.pageCommand(for: key("N"), surface: surface))
        }
    }

    func testAKeyTheUserGaveTwoCommandsInDifferentContextsRunsEachInItsOwn() {
        // Delete is fixed for queue rows; a page command in the video may use it.
        let changed = bindings.setting([key("⌫")], for: .nextItem)
        XCTAssertEqual(changed.validate(key("⌫"), for: .nextItem, replacing: 0), .ok)
        XCTAssertEqual(changed.pageCommand(for: key("⌫"), surface: .video), .nextItem)
        XCTAssertNil(changed.pageCommand(for: key("⌫"), surface: .queueTable), "queue rows keep their Delete")
    }

    func testMovingAMenuKeyChangesTheMenuAndLeavesThePageAlone() {
        let changed = bindings.setting([key("↑"), key("⌥⌘U")], for: .volumeUp)
        XCTAssertEqual(changed.menuKey(for: .volumeUp), key("⌥⌘U"))
        XCTAssertNil(changed.pageCommand(for: key("⌥⌘U"), surface: .video), "a menu key never runs from the page")
        XCTAssertNil(changed.pageCommand(for: key("⌘↑"), surface: .video), "the old menu key is gone")
        XCTAssertEqual(changed.pageCommand(for: key("↑"), surface: .video), .volumeUp)
    }

    func testAPageKeyOnAMenuCommandNeedsNoMenuKey() {
        let changed = bindings.setting([key("J")], for: .shuffle)
        XCTAssertNil(changed.menuKey(for: .shuffle))
        XCTAssertEqual(changed.pageCommand(for: key("J"), surface: .video), .shuffle)
        XCTAssertNil(changed.pageCommand(for: key("⌥⌘S"), surface: .video))
    }

    func testFixedCommandsNeverRunFromThePage() {
        for surface in [ShortcutSurface.video, .image, .queueTable] {
            XCTAssertNil(bindings.pageCommand(for: key("⌘Z"), surface: surface))
            XCTAssertNil(bindings.pageCommand(for: key("⌫"), surface: surface))
            XCTAssertNil(bindings.pageCommand(for: key("⌘Q"), surface: surface))
        }
    }

    func testOverridesForFixedCommandsAreNotApplied() {
        let tampered = ShortcutBindings(overrides: [.quit: [key("J")], .nextItem: [key("L")]])
        XCTAssertEqual(tampered.activeKeys(for: .quit), [key("⌘Q")])
        XCTAssertEqual(tampered.activeKeys(for: .nextItem), [key("L")])
    }
}

final class ShortcutMenuBuilderTests: XCTestCase {
    func testEditMenuOrderActionsAndKeyEquivalents() {
        let target = NSObject()
        let undoAction = NSSelectorFromString("undoMarkerRename:")
        let redoAction = NSSelectorFromString("redoTyping:")
        let bindings = ShortcutBindings()
        let edit = ShortcutEditMenuBuilder.make(
            undoTarget: target, undoAction: undoAction, redoAction: redoAction,
            bind: { item, id in item.applyShortcut(for: id, bindings: bindings) })
        let items = edit.items
        XCTAssertEqual(items.map(\.title), ["Undo", "Redo", "", "Cut", "Copy", "Paste", "Select All"])
        XCTAssertTrue(items[2].isSeparatorItem)
        XCTAssertEqual(items.map(\.keyEquivalent), ["z", "z", "", "x", "c", "v", "a"])
        XCTAssertEqual(items[0].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(items[1].keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(items[0].action, undoAction)
        XCTAssertEqual(items[1].action, redoAction)
        XCTAssertTrue(items[0].target === target && items[1].target === target)
        XCTAssertEqual(items[3].action, #selector(NSText.cut(_:)))
        XCTAssertEqual(items[4].action, #selector(NSText.copy(_:)))
        XCTAssertEqual(items[5].action, #selector(NSText.paste(_:)))
        XCTAssertEqual(items[6].action, #selector(NSText.selectAll(_:)))
        for item in items[3...] { XCTAssertNil(item.target) }
    }

    func testEveryModifiedPlayPauseKeyIsInstalledAsAMenuEquivalent() {
        let target = NSObject()
        let action = NSSelectorFromString("playPause:")
        let menu = NSMenu(title: "Playback")
        let item = NSMenuItem(title: "Play / Pause", action: action, keyEquivalent: "")
        item.target = target
        menu.addItem(item)
        let bindings = ShortcutBindings().setting([key("Space"), key("⌃P"), key("⌥P")], for: .playPause)
        let aliases = ShortcutMenuKeyInstaller.apply(to: item, id: .playPause, bindings: bindings, removing: [])
        let items = menu.items.filter { $0.action == action }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.keyEquivalent), ["p", "p"])
        XCTAssertEqual(items.map(\.keyEquivalentModifierMask), [[.control], [.option]])
        XCTAssertFalse(items[0].isHidden)
        XCTAssertTrue(items[1].isHidden)
        XCTAssertTrue(items[1].allowsKeyEquivalentWhenHidden)
        XCTAssertTrue(items[0].target === target && items[1].target === target)
        XCTAssertEqual(items[0].tag, items[1].tag)
        XCTAssertNil(bindings.pageCommand(for: key("⌥P"), surface: .video))
        XCTAssertEqual(aliases.count, 1)
        let restored = ShortcutMenuKeyInstaller.apply(to: item, id: .playPause,
            bindings: ShortcutBindings(), removing: aliases)
        XCTAssertTrue(restored.isEmpty)
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertEqual(item.keyEquivalent, "")
    }
}
