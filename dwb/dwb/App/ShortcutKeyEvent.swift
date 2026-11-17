import AppKit

/// The AppKit side of `ShortcutKey`: reading a key press, and writing a menu key equivalent.

extension ShortcutModifiers {
    init(flags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option)  { result.insert(.option) }
        if flags.contains(.shift)   { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option)  { flags.insert(.option) }
        if contains(.shift)   { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }
}

extension ShortcutKey {
    /// The key of a key press, matched the way the menus match it: key codes for Space, the
    /// arrows, Delete, Forward Delete and Home; the characters without modifiers for the rest.
    /// Nil for a press the dispatch cannot match (Return, Tab, Escape, a function key).
    init?(event: NSEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return nil }
        guard let key = ShortcutKey.make(keyCode: event.keyCode,
                                         charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                         modifiers: ShortcutModifiers(flags: event.modifierFlags)) else {
            return nil
        }
        self = key
    }

    /// The menu item's `keyEquivalent` and `keyEquivalentModifierMask` for this key.
    var menuEquivalent: (character: String, modifiers: NSEvent.ModifierFlags) {
        let character: String
        switch base {
        case .character(let text):
            character = text
        case .special(let key):
            switch key {
            case .space:         character = " "
            case .left:          character = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            case .right:         character = String(UnicodeScalar(NSRightArrowFunctionKey)!)
            case .up:            character = String(UnicodeScalar(NSUpArrowFunctionKey)!)
            case .down:          character = String(UnicodeScalar(NSDownArrowFunctionKey)!)
            // AppKit represents Delete as NSDeleteCharacter for menu shortcuts.
            case .delete:        character = String(UnicodeScalar(NSDeleteCharacter)!)
            case .forwardDelete: character = String(UnicodeScalar(NSDeleteFunctionKey)!)
            case .home:          character = String(UnicodeScalar(NSHomeFunctionKey)!)
            }
        }
        return (character, modifiers.eventFlags)
    }
}

extension NSMenuItem {
    /// Gives the item the active menu key of `id` from the command table, or no key.
    func applyShortcut(for id: ShortcutCommandID,
                       bindings: ShortcutBindings = ShortcutRegistry.shared.bindings) {
        if let key = bindings.menuKey(for: id) {
            let equivalent = key.menuEquivalent
            keyEquivalent = equivalent.character
            keyEquivalentModifierMask = equivalent.modifiers
        } else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
        }
    }
}

enum ShortcutMenuKeyInstaller {
    /// The visible item shows the first modified key. Hidden peers carry the rest.
    static func apply(to item: NSMenuItem, id: ShortcutCommandID, bindings: ShortcutBindings,
                      removing previousAliases: [NSMenuItem]) -> [NSMenuItem] {
        item.applyShortcut(for: id, bindings: bindings)
        guard let menu = item.menu else { return [] }
        for alias in previousAliases { menu.removeItem(alias) }
        guard let index = menu.items.firstIndex(of: item) else { return [] }
        var aliases: [NSMenuItem] = []
        for (offset, key) in bindings.menuKeys(for: id).dropFirst().enumerated() {
            let alias = NSMenuItem(title: item.title, action: item.action, keyEquivalent: "")
            alias.target = item.target
            alias.tag = item.tag
            alias.isHidden = true
            alias.allowsKeyEquivalentWhenHidden = true
            let equivalent = key.menuEquivalent
            alias.keyEquivalent = equivalent.character
            alias.keyEquivalentModifierMask = equivalent.modifiers
            menu.insertItem(alias, at: index + offset + 1)
            aliases.append(alias)
        }
        return aliases
    }
}

enum ShortcutEditMenuBuilder {
    static func make(undoTarget: AnyObject, undoAction: Selector, redoAction: Selector,
                     bind: (NSMenuItem, ShortcutCommandID) -> Void) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: undoAction, keyEquivalent: "")
        undo.target = undoTarget
        undo.tag = 50
        bind(undo, .undoPrefixChange)
        menu.addItem(undo)

        let redo = NSMenuItem(title: "Redo", action: redoAction, keyEquivalent: "")
        redo.target = undoTarget
        redo.tag = 51
        bind(redo, .textRedo)
        menu.addItem(redo)
        menu.addItem(.separator())

        for (title, action, id) in [
            ("Cut", #selector(NSText.cut(_:)), ShortcutCommandID.cut),
            ("Copy", #selector(NSText.copy(_:)), .copy),
            ("Paste", #selector(NSText.paste(_:)), .paste),
            ("Select All", #selector(NSText.selectAll(_:)), .selectAll)
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            bind(item, id)
            menu.addItem(item)
        }
        return menu
    }
}
