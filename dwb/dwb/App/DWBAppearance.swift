import AppKit

extension Notification.Name {
    /// Posted once, from `DWBAppearance`, when Increase Contrast or the app's Reduce Motion
    /// setting changes. Every part that draws with a contrast-dependent token observes this
    /// one name instead of watching the system and the preference itself.
    static let dwbAppearanceDidChange = Notification.Name("dwb.appearanceDidChange")
}

/// The Increase Contrast substitutions from `tokens-and-specs.md` section 6, as pure
/// functions of the switch so they can be tested without the system setting.
enum DWBContrast {
    /// IC: `border` becomes `borderStrong`.
    static func border(_ increaseContrast: Bool) -> NSColor {
        increaseContrast ? DWBColor.borderStrong : DWBColor.border
    }

    /// IC: `textSecondary` becomes `textPrimary`.
    static func textSecondary(_ increaseContrast: Bool) -> NSColor {
        increaseContrast ? DWBColor.textPrimary : DWBColor.textSecondary
    }

    /// IC: `textTertiary` becomes `textSecondary`.
    static func textTertiary(_ increaseContrast: Bool) -> NSColor {
        increaseContrast ? DWBColor.textSecondary : DWBColor.textTertiary
    }

    /// IC: `accentTint` goes from 0.18 to 0.28.
    static func accentTintAlpha(_ increaseContrast: Bool) -> CGFloat {
        increaseContrast ? 0.28 : 0.18
    }

    static func accentTint(_ theme: DWBTheme, _ increaseContrast: Bool) -> NSColor {
        theme.accentFill.withAlphaComponent(accentTintAlpha(increaseContrast))
    }

    /// IC: every translucent backing becomes opaque.
    static func opaque(_ color: NSColor, _ increaseContrast: Bool) -> NSColor {
        increaseContrast ? color.withAlphaComponent(1) : color
    }

    /// IC: the focus ring is 3 pt in `accentText`; otherwise 2 pt in the accent fill.
    static func focusRingColor(_ theme: DWBTheme, _ increaseContrast: Bool) -> NSColor {
        theme.focusRing(increaseContrast: increaseContrast)
    }

    static func focusRingWidth(_ increaseContrast: Bool) -> CGFloat {
        increaseContrast ? DWBMetrics.focusWidthIC : DWBMetrics.focusWidth
    }
}

/// The one shared place that reads Increase Contrast and Reduce Motion and tells the
/// app when either changes (`.dwbAppearanceDidChange`).
final class DWBAppearance {
    static let shared = DWBAppearance()

    private(set) var increaseContrast: Bool
    private(set) var reduceMotion: Bool
    private let theme = PlayerTheme.current

    private init() {
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        reduceMotion = Self.currentReduceMotion()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        // Reduce Motion is the app's own setting (it defaults to the system value), so a
        // change to the stored preference counts as a change here too.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// The app's "Reduce motion" setting. Falls back to the system value before the
    /// preference has been registered or written.
    static func currentReduceMotion() -> Bool {
        let defaults = UserDefaults.standard
        let key = SettingsDefaultsRegistry.Keys.chromeReducedMotion
        if defaults.object(forKey: key) == nil {
            return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        return defaults.bool(forKey: key)
    }

    /// Touch the shared instance early so the observers exist before any part draws.
    func start() {}

    @objc private func systemDisplayOptionsChanged() {
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        reduceMotion = Self.currentReduceMotion()
        NotificationCenter.default.post(name: .dwbAppearanceDidChange, object: nil)
    }

    @objc private func userDefaultsChanged() {
        let current = Self.currentReduceMotion()
        guard current != reduceMotion else { return }
        reduceMotion = current
        NotificationCenter.default.post(name: .dwbAppearanceDidChange, object: nil)
    }

    // MARK: - Contrast-aware tokens

    var border: NSColor { DWBContrast.border(increaseContrast) }
    var textSecondary: NSColor { DWBContrast.textSecondary(increaseContrast) }
    var textTertiary: NSColor { DWBContrast.textTertiary(increaseContrast) }
    var accentTint: NSColor { DWBContrast.accentTint(theme, increaseContrast) }
    var focusRingColor: NSColor { DWBContrast.focusRingColor(theme, increaseContrast) }
    var focusRingWidth: CGFloat { DWBContrast.focusRingWidth(increaseContrast) }

    /// Fade duration that is zero under Reduce Motion.
    func duration(_ base: TimeInterval) -> TimeInterval {
        DWBMotion.duration(base, reduceMotion: reduceMotion)
    }
}

extension DWBAppearance {
    /// Registers `observer` for `.dwbAppearanceDidChange`. Pair with `stopObserving`.
    static func observe(_ observer: Any, selector: Selector) {
        shared.start()
        NotificationCenter.default.addObserver(observer, selector: selector,
                                               name: .dwbAppearanceDidChange, object: nil)
    }

    static func stopObserving(_ observer: Any) {
        NotificationCenter.default.removeObserver(observer, name: .dwbAppearanceDidChange, object: nil)
    }
}
