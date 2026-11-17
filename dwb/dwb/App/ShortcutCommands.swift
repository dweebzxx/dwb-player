import Foundation

/// The one table of player's keyboard commands: identifier, action name, group, context,
/// default keys, and whether the user can change them. The menu builder, the key handlers,
/// Settings > Shortcuts, the tooltips and the prefix shortcut text all read the active keys
/// from here (default keys plus the user's overrides). Pure values: no views, no AppKit.

// MARK: - Keys

struct ShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int
    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option  = ShortcutModifiers(rawValue: 1 << 1)
    static let shift   = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// Modifier symbols in the standard order: ⌃ ⌥ ⇧ ⌘.
    var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option)  { text += "⌥" }
        if contains(.shift)   { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }

    /// Spoken names in the same order.
    var spokenNames: [String] {
        var names: [String] = []
        if contains(.control) { names.append("control") }
        if contains(.option)  { names.append("option") }
        if contains(.shift)   { names.append("shift") }
        if contains(.command) { names.append("command") }
        return names
    }

    static func fromSymbol(_ symbol: Character) -> ShortcutModifiers? {
        switch symbol {
        case "⌃": return .control
        case "⌥": return .option
        case "⇧": return .shift
        case "⌘": return .command
        default:  return nil
        }
    }

    /// A key with one of these can be a menu key equivalent. A bare or Shift-only key cannot:
    /// a menu equivalent would also fire while a text field is being typed in.
    var allowsMenuRoute: Bool { !isDisjoint(with: [.command, .control, .option]) }
}

/// The non-character keys the dispatch matches by hardware key code.
enum ShortcutSpecialKey: CaseIterable {
    case space, left, right, up, down, delete, forwardDelete, home

    var symbol: String {
        switch self {
        case .space:         return "Space"
        case .left:          return "←"
        case .right:         return "→"
        case .up:            return "↑"
        case .down:          return "↓"
        case .delete:        return "⌫"
        case .forwardDelete: return "⌦"
        case .home:          return "Home"
        }
    }

    var spokenName: String {
        switch self {
        case .space:         return "space"
        case .left:          return "left arrow"
        case .right:         return "right arrow"
        case .up:            return "up arrow"
        case .down:          return "down arrow"
        case .delete:        return "delete"
        case .forwardDelete: return "forward delete"
        case .home:          return "home"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .space:         return 49
        case .left:          return 123
        case .right:         return 124
        case .up:            return 126
        case .down:          return 125
        case .delete:        return 51
        case .forwardDelete: return 117
        case .home:          return 115
        }
    }

    init?(keyCode: UInt16) {
        guard let match = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = match
    }

    init?(symbol: String) {
        guard let match = Self.allCases.first(where: { $0.symbol == symbol }) else { return nil }
        self = match
    }
}

/// A key and its modifiers. Characters are stored lowercase and matched the way the menus
/// match them (`charactersIgnoringModifiers`), so a key follows the user's keyboard layout.
/// Space, the arrows, Delete, Forward Delete and Home are matched by key code.
struct ShortcutKey: Hashable {
    enum Base: Hashable {
        case character(String)
        case special(ShortcutSpecialKey)
    }

    let base: Base
    let modifiers: ShortcutModifiers

    init(_ base: Base, _ modifiers: ShortcutModifiers = []) {
        switch base {
        case .character(let text): self.base = .character(text.lowercased())
        case .special:             self.base = base
        }
        self.modifiers = modifiers
    }

    static func character(_ text: String, _ modifiers: ShortcutModifiers = []) -> ShortcutKey {
        ShortcutKey(.character(text), modifiers)
    }

    static func special(_ key: ShortcutSpecialKey, _ modifiers: ShortcutModifiers = []) -> ShortcutKey {
        ShortcutKey(.special(key), modifiers)
    }

    /// The key without its modifiers, in key cap style: `N`, `,`, `Space`, `←`.
    var baseText: String {
        switch base {
        case .character(let text): return text.uppercased()
        case .special(let key):    return key.symbol
        }
    }

    /// The key in key cap style with modifier symbols first: `⌥⌘S`, `⇧⌘⌫`, `Space`.
    var text: String { modifiers.symbols + baseText }

    /// The words a screen reader says, and the words search matches: `command option S`.
    var spokenText: String {
        let name: String
        switch base {
        case .character(let text): name = Self.spokenCharacter(text)
        case .special(let key):    name = key.spokenName
        }
        return (modifiers.spokenNames + [name]).joined(separator: " ")
    }

    /// The key's cap on the keyboard map, only for an unmodified key that the map draws.
    var mapLabel: String? {
        guard modifiers.isEmpty else { return nil }
        let label = baseText
        return ShortcutKeyboardLayout.allKeys.contains(label) ? label : nil
    }

    /// Reads `text` back (`⌥⌘S`, `Space`, `←`). Returns nil for anything else.
    init?(text: String) {
        var modifiers: ShortcutModifiers = []
        var rest = Substring(text)
        while let first = rest.first, let modifier = ShortcutModifiers.fromSymbol(first) {
            modifiers.insert(modifier)
            rest = rest.dropFirst()
        }
        let remainder = String(rest)
        if let special = ShortcutSpecialKey(symbol: remainder) {
            self.init(.special(special), modifiers)
        } else if remainder.count == 1, Self.isRecordableCharacter(remainder.first!) {
            self.init(.character(remainder), modifiers)
        } else {
            return nil
        }
    }

    /// Builds a key from the parts of a key press. Nil when the press is not a key the
    /// dispatch can match (a modifier alone, Return, Tab, Escape, a function key).
    static func make(keyCode: UInt16,
                     charactersIgnoringModifiers: String?,
                     modifiers: ShortcutModifiers) -> ShortcutKey? {
        // Sheet control keys and navigation keys are never shortcut assignments.
        let excludedCodes: Set<UInt16> = [
            36, 76, 48, 53, 115, 119, 116, 121, // Return, Enter, Tab, Escape, Home, End, Page Up, Page Down
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
            105, 107, 113, 106, 64, 79, 80, 90 // F13–F20
        ]
        guard !excludedCodes.contains(keyCode) else { return nil }
        if let special = ShortcutSpecialKey(keyCode: keyCode) {
            return ShortcutKey(.special(special), modifiers)
        }
        guard let first = charactersIgnoringModifiers?.first, isRecordableCharacter(first) else { return nil }
        return ShortcutKey(.character(String(first)), modifiers)
    }

    /// A letter, digit, punctuation mark or symbol. Not whitespace, a control character, or
    /// the private-use characters AppKit uses for function and arrow keys.
    static func isRecordableCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
    }

    private static func spokenCharacter(_ text: String) -> String {
        switch text {
        case ",":  return "comma"
        case ".":  return "period"
        case "[":  return "left bracket"
        case "]":  return "right bracket"
        case "\\": return "backslash"
        case "/":  return "slash"
        case ";":  return "semicolon"
        case "'":  return "apostrophe"
        case "-":  return "minus"
        case "=":  return "equals"
        case "`":  return "grave accent"
        default:   return text.uppercased()
        }
    }
}

enum ShortcutKeyRules {
    /// Whether the dispatch can deliver `key` reliably. Shift with a character that is not a
    /// letter gives a different character on other layouts, so it is not accepted.
    static func isDeliverable(_ key: ShortcutKey) -> Bool {
        guard key.modifiers.isEmpty || key.modifiers.allowsMenuRoute else { return false }
        switch key.base {
        case .special(.home): return false
        case .character(let text):
            guard text.count == 1, let character = text.first,
                  ShortcutKey.isRecordableCharacter(character) else { return false }
        case .special: break
        }
        if case .character(let text) = key.base,
           key.modifiers.contains(.shift),
           !(text.first?.isLetter ?? false) {
            return false
        }
        return true
    }
}

// MARK: - Contexts

/// Where the keyboard focus can be when a key is pressed.
struct ShortcutFocus: OptionSet, Hashable {
    let rawValue: Int
    static let video           = ShortcutFocus(rawValue: 1 << 0)
    static let image           = ShortcutFocus(rawValue: 1 << 1)
    static let queueTable      = ShortcutFocus(rawValue: 1 << 2)
    static let queueDivider    = ShortcutFocus(rawValue: 1 << 3)
    static let settingsSidebar = ShortcutFocus(rawValue: 1 << 4)
    static let otherControl    = ShortcutFocus(rawValue: 1 << 5)
    static let textEditing     = ShortcutFocus(rawValue: 1 << 6)
    static let all: ShortcutFocus = [.video, .image, .queueTable, .queueDivider,
                                     .settingsSidebar, .otherControl, .textEditing]
}

/// The surfaces whose `keyDown` runs page shortcuts.
enum ShortcutSurface {
    case video, image, queueTable

    var focus: ShortcutFocus {
        switch self {
        case .video:      return .video
        case .image:      return .image
        case .queueTable: return .queueTable
        }
    }
}

/// Where and when a key fires. Two contexts overlap when the focus can be in both at once.
/// The same key can then belong to two commands only if their contexts do not overlap.
enum ShortcutContext: String, CaseIterable {
    /// A menu key equivalent: every window and every focus, including text editing.
    case anywhere
    /// Every window and focus except a text field being edited.
    case playerWindow
    /// The video, or the image or GIF, has focus. Page keys do nothing while text is edited.
    case mediaView
    /// The video, the image or GIF, or the queue list has focus.
    case mediaOrQueue
    /// The queue list has focus (rows selected).
    case queueRows
    case queueDivider
    case settingsSidebar
    /// A text field is being edited.
    case textEditing

    var focus: ShortcutFocus {
        switch self {
        case .anywhere:        return .all
        case .playerWindow:    return ShortcutFocus.all.subtracting(.textEditing)
        case .mediaView:       return [.video, .image]
        case .mediaOrQueue:    return [.video, .image, .queueTable]
        case .queueRows:       return .queueTable
        case .queueDivider:    return .queueDivider
        case .settingsSidebar: return .settingsSidebar
        case .textEditing:     return .textEditing
        }
    }

    func overlaps(_ other: ShortcutContext) -> Bool { !focus.isDisjoint(with: other.focus) }

    var title: String {
        switch self {
        case .anywhere:        return "Any window"
        case .playerWindow:    return "Player window"
        case .mediaView:       return "Video or image in focus"
        case .mediaOrQueue:    return "Video, image, or queue list in focus"
        case .queueRows:       return "Queue list in focus"
        case .queueDivider:    return "Queue panel divider in focus"
        case .settingsSidebar: return "Settings sidebar in focus"
        case .textEditing:     return "Text field being edited"
        }
    }
}

// MARK: - Commands

enum ShortcutGroupID: Int, CaseIterable {
    case playback, navigation, fileActions, bookmarks, window, skipAndAudioSync, textEditing

    var title: String {
        switch self {
        case .playback:         return "Playback"
        case .navigation:       return "Navigation"
        case .fileActions:      return "File actions"
        case .bookmarks:        return "Bookmarks"
        case .window:           return "Window"
        case .skipAndAudioSync: return "Skip & audio sync"
        case .textEditing:      return "Text editing"
        }
    }

    /// Set on the group that only exists in player.
    var appLabel: String? { self == .skipAndAudioSync ? "dwb player" : nil }
}

/// Stable identifiers. The raw value is what `shortcutOverrides` stores.
enum ShortcutCommandID: String, CaseIterable {
    // Playback
    case playPause, skipBackward, skipForward, volumeUp, volumeDown
    case shuffle, endlessShuffle, repeatOne
    // Navigation
    case previousItem, nextItem
    // File actions
    case openFile, revealInFinder, renameFile, clearQueue
    case togglePrimaryPrefix, toggleSecondaryPrefix
    case undoPrefixChange, removeQueueRows
    // Bookmarks
    case toggleBookmark
    // Window
    case newWindow, fourWindowGrid, scaleFit, scaleFill, scaleStretch
    case minimize, openSettings, quit, settingsSidebarNavigation, queueDividerResize
    // Skip & audio sync
    case skip10, skip30, skip60, skip180
    case advanceAudio, delayAudio, resetAudioSync
    // Text editing
    case textUndo, textRedo, cut, copy, paste, selectAll
}

struct ShortcutCommand {
    enum Kind: Equatable {
        /// The user can change the keys. `hasMenuItem`: the first key with ⌘, ⌃ or ⌥ is the
        /// menu key equivalent. Every other key runs from `pageContext`.
        case editable(hasMenuItem: Bool, pageContext: ShortcutContext)
        /// A reference row: the keys and the context are shown, with no editor.
        case fixed(ShortcutContext)
    }

    let id: ShortcutCommandID
    let name: String
    let group: ShortcutGroupID
    let defaultKeys: [ShortcutKey]
    let kind: Kind
    /// Context text shown in the row and matched by search.
    let note: String?

    var isEditable: Bool {
        if case .editable = kind { return true }
        return false
    }

    var hasMenuItem: Bool {
        if case .editable(let hasMenuItem, _) = kind { return hasMenuItem }
        return false
    }

    var pageContext: ShortcutContext? {
        if case .editable(_, let context) = kind { return context }
        return nil
    }

    var tone: ShortcutTone {
        switch id {
        case .togglePrimaryPrefix:   return .markerPrimary
        case .toggleSecondaryPrefix: return .markerSecondary
        default:                     return .accent
        }
    }

    /// One line per command, for the golden test and the report.
    var inventoryLine: String {
        let keys = defaultKeys.map(\.text).joined(separator: ", ")
        let route: String
        switch kind {
        case .editable(let hasMenuItem, let pageContext):
            route = "editable menu=\(hasMenuItem ? ShortcutContext.anywhere.rawValue : "none") page=\(pageContext.rawValue)"
        case .fixed(let context):
            route = "reference context=\(context.rawValue)"
        }
        return "\(id.rawValue) | \(group.title) | \(name) | \(keys) | \(route)"
    }
}

/// A key as the dispatch sees it for one command: the context it fires in, and whether the
/// menu carries it.
struct ShortcutRoutedKey: Equatable {
    let key: ShortcutKey
    let context: ShortcutContext
    let isMenuKey: Bool
}

enum ShortcutCommandTable {
    private static let note = ShortcutNotes.self

    static let all: [ShortcutCommand] = [
        // Playback
        editable(.playPause, "Play or pause", .playback, ["Space"], menu: true, note.menuAndPage),
        editable(.skipBackward, "Rewind by skip duration", .playback, ["←", "⌥←"], menu: true, note.seek),
        editable(.skipForward, "Forward by skip duration", .playback, ["→", "⌥→"], menu: true, note.seek),
        editable(.volumeUp, "Volume up", .playback, ["↑", "⌘↑"], menu: true, note.menuAndPage),
        editable(.volumeDown, "Volume down", .playback, ["↓", "⌘↓"], menu: true, note.menuAndPage),
        editable(.shuffle, "Shuffle", .playback, ["⌥⌘S"], menu: true, nil),
        editable(.endlessShuffle, "Endless shuffle", .playback, ["⌥⌘E"], menu: true, nil),
        editable(.repeatOne, "Repeat one", .playback, ["⌥⌘R"], menu: true, nil),
        // Navigation
        editable(.previousItem, "Previous item", .navigation, [","], menu: false, note.media),
        editable(.nextItem, "Next item", .navigation, ["."], menu: false, note.media),
        // File actions
        editable(.openFile, "Open file", .fileActions, ["⌘O"], menu: true, nil),
        editable(.revealInFinder, "Reveal in Finder", .fileActions, ["⇧⌘R"], menu: true, nil),
        editable(.renameFile, "Rename file", .fileActions, ["R"], menu: true,
                 note.rename, page: .mediaOrQueue),
        editable(.clearQueue, "Clear queue", .fileActions, ["⇧⌘⌫"], menu: true, nil),
        editable(.togglePrimaryPrefix, "Toggle primary prefix", .fileActions, ["N"], menu: false,
                 note.prefix, page: .mediaOrQueue),
        editable(.toggleSecondaryPrefix, "Toggle secondary prefix", .fileActions, ["M"], menu: false,
                 note.prefix, page: .mediaOrQueue),
        fixed(.undoPrefixChange, "Undo prefix change", .fileActions, ["⌘Z"], .playerWindow, note.undoPrefix),
        fixed(.removeQueueRows, "Remove selected queue rows", .fileActions, ["⌫", "⌦"], .queueRows,
              note.removeRows),
        // Bookmarks
        editable(.toggleBookmark, "Toggle bookmark", .bookmarks, ["B"], menu: false, note.media),
        // Window
        editable(.newWindow, "New window", .window, ["⌘N"], menu: true, nil),
        editable(.fourWindowGrid, "Four window grid", .window, ["⌘4"], menu: true, nil),
        editable(.scaleFit, "Fit", .window, ["⌘1"], menu: true, nil),
        editable(.scaleFill, "Fill", .window, ["⌘2"], menu: true, nil),
        editable(.scaleStretch, "Stretch", .window, ["⌘3"], menu: true, nil),
        fixed(.minimize, "Minimize", .window, ["⌘M"], .anywhere, nil),
        fixed(.openSettings, "Open settings", .window, ["⌘,"], .anywhere, nil),
        fixed(.quit, "Quit dwb player", .window, ["⌘Q"], .anywhere, nil),
        fixed(.settingsSidebarNavigation, "Move Settings sidebar selection", .window, ["↑", "↓"],
              .settingsSidebar, note.sidebar),
        fixed(.queueDividerResize, "Resize queue panel", .window, ["←", "→", "Home"], .queueDivider,
              note.divider),
        // Skip & audio sync
        editable(.skip10, "10 seconds", .skipAndAudioSync, ["1"], menu: false, note.skipPreset),
        editable(.skip30, "30 seconds", .skipAndAudioSync, ["3"], menu: false, note.skipPreset),
        editable(.skip60, "60 seconds", .skipAndAudioSync, ["6"], menu: false, note.skipPreset),
        editable(.skip180, "3 minutes", .skipAndAudioSync, ["9"], menu: false, note.skipPreset),
        editable(.advanceAudio, "Advance audio (play sooner)", .skipAndAudioSync, ["[", "⌘["], menu: true,
                 note.menuAndPage),
        editable(.delayAudio, "Delay audio (play later)", .skipAndAudioSync, ["]", "⌘]"], menu: true,
                 note.menuAndPage),
        editable(.resetAudioSync, "Reset audio sync", .skipAndAudioSync, ["\\", "⌘\\"], menu: true,
                 note.menuAndPage),
        // Text editing
        fixed(.textUndo, "Undo typing", .textEditing, ["⌘Z"], .textEditing, note.textUndo),
        fixed(.textRedo, "Redo typing", .textEditing, ["⇧⌘Z"], .textEditing, note.textUndo),
        fixed(.cut, "Cut", .textEditing, ["⌘X"], .anywhere, note.textCommand),
        fixed(.copy, "Copy", .textEditing, ["⌘C"], .anywhere, note.textCommand),
        fixed(.paste, "Paste", .textEditing, ["⌘V"], .anywhere, note.textCommand),
        fixed(.selectAll, "Select all", .textEditing, ["⌘A"], .anywhere, note.textCommand)
    ]

    static func command(_ id: ShortcutCommandID) -> ShortcutCommand {
        all.first { $0.id == id }!
    }

    static var editableIDs: Set<ShortcutCommandID> {
        Set(all.filter(\.isEditable).map(\.id))
    }

    private static func keys(_ texts: [String]) -> [ShortcutKey] {
        texts.map { text in
            guard let key = ShortcutKey(text: text) else { preconditionFailure("bad default key \(text)") }
            return key
        }
    }

    private static func editable(_ id: ShortcutCommandID, _ name: String, _ group: ShortcutGroupID,
                                 _ defaults: [String], menu: Bool, _ note: String?,
                                 page: ShortcutContext = .mediaView) -> ShortcutCommand {
        ShortcutCommand(id: id, name: name, group: group, defaultKeys: keys(defaults),
                        kind: .editable(hasMenuItem: menu, pageContext: page), note: note)
    }

    private static func fixed(_ id: ShortcutCommandID, _ name: String, _ group: ShortcutGroupID,
                              _ defaults: [String], _ context: ShortcutContext,
                              _ note: String?) -> ShortcutCommand {
        ShortcutCommand(id: id, name: name, group: group, defaultKeys: keys(defaults),
                        kind: .fixed(context), note: note)
    }
}

/// The context text of each conditional action. It describes when the action runs; it does
/// not name a key, so it stays right when the user changes the keys.
enum ShortcutNotes {
    static let media = "Video or image in focus. Does nothing while a text field is being edited."
    static let menuAndPage = "Modified keys work in any window. Unmodified keys need the video or image in focus, "
        + "and do nothing while a text field is being edited."
    static let seek = menuAndPage + " Hold a key to keep seeking on video; an image or GIF steps once per press."
    static let prefix = "Video, image, or queue list in focus. Acts on the selected queue rows, or else the "
        + "current file. Does nothing while a text field is being edited."
    static let rename = "Modified keys work in any window. Unmodified keys need the video, image, or queue list in focus. Renames the selected queue row when exactly one "
        + "row is selected, otherwise the current file. Does nothing while a text field is being edited."
    static let skipPreset = "Sets the skip duration. " + media
    static let undoPrefix = "Any window, unless a text field is being edited."
    static let removeRows = "Queue list in focus, with rows selected."
    static let sidebar = "Settings window, with the sidebar in focus."
    static let divider = "Queue panel divider in focus: ← widens, → narrows, Home resets the width."
    static let textUndo = "While a text field is being edited."
    static let textCommand = "Acts on the text field being edited. The key is reserved in every window."
}

// MARK: - Overrides

/// The user's changed keys, kept in player's own `UserDefaults` under `shortcutOverrides`:
/// a dictionary from command identifier to the list of active keys, each key as its text
/// (`["K", "H"]`). A command with no entry uses its default keys. An empty list is a command
/// with no keys.
final class ShortcutOverrideStore {
    static let defaultsKey = "shortcutOverrides"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Reads the stored overrides. Identifiers that are not an editable command are ignored,
    /// and so are key texts that do not parse. An entry whose keys all fail to parse is ignored.
    func load(editableIDs: Set<ShortcutCommandID> = ShortcutCommandTable.editableIDs) -> [ShortcutCommandID: [ShortcutKey]] {
        guard let stored = defaults.dictionary(forKey: Self.defaultsKey) else { return [:] }
        var result: [ShortcutCommandID: [ShortcutKey]] = [:]
        for (identifier, value) in stored {
            guard let id = ShortcutCommandID(rawValue: identifier), editableIDs.contains(id),
                  let texts = value as? [String] else { continue }
            let keys = texts.compactMap { ShortcutKey(text: $0) }.filter(ShortcutKeyRules.isDeliverable)
            if keys.isEmpty && !texts.isEmpty { continue }
            result[id] = keys
        }
        return result
    }

    func save(_ overrides: [ShortcutCommandID: [ShortcutKey]]) {
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        var stored: [String: [String]] = [:]
        for (id, keys) in overrides { stored[id.rawValue] = keys.map(\.text) }
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    /// Removes every override and nothing else.
    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

// MARK: - Bindings

enum ShortcutKeyValidation: Equatable {
    case ok
    /// The key cannot be delivered for this action.
    case invalid
    /// Another command uses the key in a context that can be active at the same time.
    case conflict(ShortcutCommandID)
}

/// The commands plus the user's overrides: everything that answers "which key runs what".
struct ShortcutBindings {
    let commands: [ShortcutCommand]
    private(set) var overrides: [ShortcutCommandID: [ShortcutKey]]

    init(commands: [ShortcutCommand] = ShortcutCommandTable.all,
         overrides: [ShortcutCommandID: [ShortcutKey]] = [:]) {
        self.commands = commands
        self.overrides = overrides.filter { id, _ in commands.first { $0.id == id }?.isEditable == true }
    }

    func command(_ id: ShortcutCommandID) -> ShortcutCommand {
        commands.first { $0.id == id }!
    }

    /// The keys that run `id` now, in assignment order.
    func activeKeys(for id: ShortcutCommandID) -> [ShortcutKey] {
        overrides[id] ?? command(id).defaultKeys
    }

    func activeKeyTexts(for id: ShortcutCommandID) -> [String] {
        activeKeys(for: id).map(\.text)
    }

    /// The key text a tooltip shows: the first active key, or nil when unassigned.
    func primaryKeyText(for id: ShortcutCommandID) -> String? {
        activeKeys(for: id).first?.text
    }

    // MARK: Routes

    /// The context of each key of `command` when it has `keys`. For a command with a menu
    /// item, every key with ⌘, ⌃ or ⌥ is a menu key (`.anywhere`). Other keys
    /// run from the page context.
    func routedKeys(for command: ShortcutCommand, keys: [ShortcutKey]) -> [ShortcutRoutedKey] {
        switch command.kind {
        case .fixed(let context):
            return keys.map { ShortcutRoutedKey(key: $0, context: context, isMenuKey: false) }
        case .editable(let hasMenuItem, let pageContext):
            return keys.map { key in
                hasMenuItem && key.modifiers.allowsMenuRoute
                    ? ShortcutRoutedKey(key: key, context: .anywhere, isMenuKey: true)
                    : ShortcutRoutedKey(key: key, context: pageContext, isMenuKey: false)
            }
        }
    }

    /// The key the menu item of `id` carries now, or nil for no key equivalent.
    func menuKey(for id: ShortcutCommandID) -> ShortcutKey? {
        let command = command(id)
        switch command.kind {
        case .fixed:
            return defaultMenuKeyOfFixed(command)
        case .editable:
            return routedKeys(for: command, keys: activeKeys(for: id)).first { $0.isMenuKey }?.key
        }
    }

    /// All modified keys carried by a menu command, in assignment order.
    func menuKeys(for id: ShortcutCommandID) -> [ShortcutKey] {
        let command = command(id)
        guard command.isEditable else { return menuKey(for: id).map { [$0] } ?? [] }
        return routedKeys(for: command, keys: activeKeys(for: id))
            .filter(\.isMenuKey).map(\.key)
    }

    /// Fixed commands that sit in the menu carry their one default key.
    private func defaultMenuKeyOfFixed(_ command: ShortcutCommand) -> ShortcutKey? {
        switch command.id {
        case .minimize, .openSettings, .quit, .cut, .copy, .paste, .selectAll, .undoPrefixChange, .textRedo:
            return command.defaultKeys.first
        default:
            return nil
        }
    }

    /// The page command a key press runs on `surface`. A menu key never runs from the page:
    /// each key has one route.
    func pageCommand(for key: ShortcutKey, surface: ShortcutSurface) -> ShortcutCommandID? {
        for command in commands where command.isEditable {
            for routed in routedKeys(for: command, keys: activeKeys(for: command.id))
            where !routed.isMenuKey && routed.key == key && routed.context.focus.contains(surface.focus) {
                return command.id
            }
        }
        return nil
    }

    // MARK: Editing

    /// The keys of `id` after replacing the one at `index` with `key`, removing it (`key` nil),
    /// or appending `key` (`index` nil). Repeated keys keep their first place.
    func keys(for id: ShortcutCommandID, replacing index: Int?, with key: ShortcutKey?) -> [ShortcutKey] {
        var keys = activeKeys(for: id)
        switch (index, key) {
        case (let index?, let key?) where keys.indices.contains(index): keys[index] = key
        case (let index?, nil) where keys.indices.contains(index):      keys.remove(at: index)
        case (nil, let key?):                                           keys.append(key)
        default:                                                        break
        }
        var seen = Set<ShortcutKey>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// Whether `candidate` can be assigned to `id` in place of the key at `index` (or added
    /// when `index` is nil). A key another command uses in an overlapping context is a
    /// conflict, never an invalid key. A command never conflicts with itself.
    func validate(_ candidate: ShortcutKey?, for id: ShortcutCommandID, replacing index: Int?) -> ShortcutKeyValidation {
        guard let candidate else { return .invalid }
        let command = command(id)
        guard command.isEditable else { return .invalid }
        guard ShortcutKeyRules.isDeliverable(candidate) else { return .invalid }

        let reserved: [ShortcutKey: ShortcutCommandID] = [
            ShortcutKey(text: "⌘Z")!: .textUndo,
            ShortcutKey(text: "⇧⌘Z")!: .textRedo,
            ShortcutKey(text: "⌘X")!: .cut,
            ShortcutKey(text: "⌘C")!: .copy,
            ShortcutKey(text: "⌘V")!: .paste,
            ShortcutKey(text: "⌘A")!: .selectAll
        ]
        if let owner = reserved[candidate] { return .conflict(owner) }

        let proposed = keys(for: id, replacing: index, with: candidate)
        guard let routed = routedKeys(for: command, keys: proposed).first(where: { $0.key == candidate }) else {
            return .invalid
        }
        for other in commands where other.id != id {
            let otherKeys = routedKeys(for: other, keys: activeKeys(for: other.id))
            if otherKeys.contains(where: { $0.key == candidate && $0.context.overlaps(routed.context) }) {
                return .conflict(other.id)
            }
        }
        return .ok
    }

    /// The bindings with `keys` for `id`. Keys equal to the defaults drop the override.
    func setting(_ keys: [ShortcutKey], for id: ShortcutCommandID) -> ShortcutBindings {
        var next = self
        guard command(id).isEditable else { return next }
        if keys == command(id).defaultKeys {
            next.overrides[id] = nil
        } else {
            next.overrides[id] = keys
        }
        return next
    }

    func restoringDefaults() -> ShortcutBindings {
        ShortcutBindings(commands: commands, overrides: [:])
    }
}

// MARK: - Registry

/// The live bindings for the app, backed by the user's defaults. Reads happen on every key
/// press, so it keeps the parsed bindings in memory and reloads them when they change.
final class ShortcutRegistry {
    static let didChangeNotification = Notification.Name("dwb.shortcutsChanged")
    static let shared = ShortcutRegistry()

    private let store: ShortcutOverrideStore
    private let center: NotificationCenter
    private(set) var bindings: ShortcutBindings

    init(store: ShortcutOverrideStore = ShortcutOverrideStore(),
         center: NotificationCenter = .default) {
        self.store = store
        self.center = center
        self.bindings = ShortcutBindings(overrides: store.load())
    }

    /// Saves the keys of `id` and tells the menus, the Shortcuts page and the hints.
    func setKeys(_ keys: [ShortcutKey], for id: ShortcutCommandID) {
        bindings = bindings.setting(keys, for: id)
        store.save(bindings.overrides)
        center.post(name: Self.didChangeNotification, object: self)
    }

    /// Removes every shortcut override and changes no other preference.
    func restoreDefaults() {
        bindings = bindings.restoringDefaults()
        store.clear()
        center.post(name: Self.didChangeNotification, object: self)
    }

    /// Re-reads the stored overrides, after something else cleared them.
    func reload() {
        bindings = ShortcutBindings(overrides: store.load())
        center.post(name: Self.didChangeNotification, object: self)
    }
}
