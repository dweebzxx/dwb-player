import Cocoa

// MARK: - Debug level

enum DebugLevel: Int, Comparable {
    case info = 0, warning, error

    static func < (lhs: DebugLevel, rhs: DebugLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log entry

struct DebugLogEntry {
    let date: Date
    let level: DebugLevel
    let category: String
    let message: String
}

// MARK: - Controller

/// App-wide in-app debug console. Off by default; toggle in Settings > Developer.
/// Ring buffer of 1000 entries. Supports category, level, and text filtering,
/// plus Pause/Resume for freezing the visible log while the app continues buffering.
final class DebugConsoleController: NSWindowController {

    static let shared = DebugConsoleController()

    // MARK: - Constants

    private static let maxEntries = 1000
    // Slack so we trim in bulk (O(1) amortized) instead of removing one element per overflow log.
    private static let maxEntriesSlack = 256
    // Cap text-view rebuild rate during log storms. With multiple windows generating
    // sustained logs, an unthrottled rebuild blocks the main thread enough to freeze
    // the whole app (debug console included).
    private static let minRenderInterval: CFTimeInterval = 0.05  // ~20 Hz max

    // MARK: - Buffer state

    private var entries: [DebugLogEntry] = []
    private(set) var isEnabled: Bool = false
    private var isPaused: Bool = false
    private var knownCategories: [String] = []

    // Coalesced render scheduling. All log appends in one runloop pass produce at most
    // one text-view rebuild; the rebuild itself is rate-limited to minRenderInterval.
    private var pendingRender: Bool = false
    private var lastRenderMT: CFTimeInterval = 0

    // MARK: - Filter state

    private var filterCategory: String? = nil     // nil = all categories
    private var filterMinLevel: DebugLevel? = nil // nil = all levels
    private var filterText: String = ""

    // MARK: - UI

    private let textView          = NSTextView()
    private let scrollView        = NSScrollView()
    private let searchField       = NSSearchField()
    private let categoryPopup     = DWBPopUpButton(width: 140)
    private let levelSegment      = DWBSegmentedControl()
    private let pauseButton       = DWBButton(title: "Pause", variant: .neutral, size: .small)
    private let statusLabel       = NSTextField(labelWithString: "")
    private let toolbarView       = NSView()
    private let footerView        = NSView()
    private let toolbarRule       = NSView()
    private let footerRule        = NSView()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Level as status color + glyph + word, so the level never rests on color alone.
    private struct LevelStyle {
        let word: String
        let symbol: String
        let color: NSColor
        let rowTint: NSColor?
    }

    private func levelStyle(_ level: DebugLevel) -> LevelStyle {
        switch level {
        case .info:    return LevelStyle(word: "INFO", symbol: "info.circle",
                                         color: DWBAppearance.shared.textSecondary, rowTint: nil)
        case .warning: return LevelStyle(word: "WARN", symbol: "exclamationmark.triangle.fill",
                                         color: DWBColor.cautionText, rowTint: nil)
        case .error:   return LevelStyle(word: "ERR", symbol: "xmark.octagon.fill",
                                         color: DWBColor.errorText, rowTint: DWBColor.errorFill.withAlphaComponent(0.16))
        }
    }

    private static let logFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let logFontBold = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    private lazy var logParagraphStyle: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.tabStops = [92, 150, 262].map { NSTextTab(textAlignment: .left, location: $0) }
        p.defaultTabInterval = 40
        p.headIndent = 262
        p.lineBreakMode = .byWordWrapping
        return p
    }()

    /// One log line as shown in the console. Copy, snapshot and export keep using
    /// `formatEntry`, so their text is unchanged.
    private func displayLine(for entry: DebugLogEntry) -> NSAttributedString {
        let appearance = DWBAppearance.shared
        let style = levelStyle(entry.level)
        let base: [NSAttributedString.Key: Any] = [
            .font: Self.logFont,
            .paragraphStyle: logParagraphStyle
        ]
        let line = NSMutableAttributedString()
        func add(_ text: String, color: NSColor, font: NSFont = Self.logFont) {
            var attributes = base
            attributes[.foregroundColor] = color
            attributes[.font] = font
            line.append(NSAttributedString(string: text, attributes: attributes))
        }
        add(timeFormatter.string(from: entry.date), color: appearance.textTertiary)
        add("\t", color: appearance.textTertiary)
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        if let glyph = NSImage(systemSymbolName: style.symbol, accessibilityDescription: style.word)?
            .withSymbolConfiguration(configuration)?.tinted(with: style.color) {
            let attachment = NSTextAttachment()
            attachment.image = glyph
            attachment.bounds = NSRect(x: 0, y: -1.5, width: glyph.size.width, height: glyph.size.height)
            var attributes = base
            attributes[.foregroundColor] = style.color
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttributes(attributes, range: NSRange(location: 0, length: attachmentString.length))
            line.append(attachmentString)
        }
        add(" \(style.word)", color: style.color, font: Self.logFontBold)
        add("\t", color: appearance.textSecondary)
        add(entry.category, color: appearance.textSecondary)
        add("\t", color: appearance.textSecondary)
        add(entry.message, color: DWBColor.textPrimary)
        add("\n", color: DWBColor.textPrimary)
        if let tint = style.rowTint {
            line.addAttribute(.backgroundColor, value: tint, range: NSRange(location: 0, length: line.length))
        }
        return line
    }

    // MARK: - Log entry points (main-thread only; dispatches if called off-main)

    static func log(_ category: String, _ message: String) {
        log(level: .info, category: category, message: message)
    }

    static func log(level: DebugLevel, category: String, message: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { log(level: level, category: category, message: message) }
            return
        }
        guard shared.isEnabled else { return }
        shared.appendEntry(DebugLogEntry(date: Date(), level: level, category: category, message: message))
    }

    // MARK: - Internal append

    private func appendEntry(_ entry: DebugLogEntry) {
        if !knownCategories.contains(entry.category) {
            knownCategories.append(entry.category)
            knownCategories.sort()
            rebuildCategoryPopup()
        }
        entries.append(entry)
        // Amortize trim: only shift the array once the slack is exceeded.
        if entries.count > Self.maxEntries + Self.maxEntriesSlack {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        scheduleRender()
    }

    /// Coalesces text-view rebuilds + status updates onto a single async tick,
    /// rate-limited to minRenderInterval. Safe to call from any code path.
    private func scheduleRender() {
        if pendingRender { return }
        pendingRender = true
        DispatchQueue.main.async { [weak self] in self?.drainRender() }
    }

    private func drainRender() {
        let now = CACurrentMediaTime()
        let elapsed = now - lastRenderMT
        if elapsed < Self.minRenderInterval {
            // Re-queue to honor the minimum interval without dropping the render.
            DispatchQueue.main.asyncAfter(deadline: .now() + (Self.minRenderInterval - elapsed)) { [weak self] in
                self?.drainRender()
            }
            return
        }
        pendingRender = false
        lastRenderMT = now
        // Lazy trim to exact cap before rendering.
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        if !isPaused, window?.isVisible == true {
            rebuildTextView()
        }
        updateStatus()
    }

    // MARK: - Filtering

    private func entryMatchesFilters(_ entry: DebugLogEntry) -> Bool {
        if let cat = filterCategory, cat != entry.category { return false }
        if let minLev = filterMinLevel, entry.level < minLev { return false }
        if !filterText.isEmpty {
            let q = filterText.lowercased()
            if !entry.message.lowercased().contains(q) && !entry.category.lowercased().contains(q) {
                return false
            }
        }
        return true
    }

    private func visibleEntries() -> [DebugLogEntry] {
        entries.filter { entryMatchesFilters($0) }
    }

    private func rebuildTextView() {
        guard let storage = textView.textStorage else { return }
        let combined = NSMutableAttributedString()
        for e in visibleEntries() {
            combined.append(displayLine(for: e))
        }
        storage.setAttributedString(combined)
        textView.scrollToEndOfDocument(nil)
    }

    private func updateStatus() {
        let total   = entries.count
        let visible = filterCategory == nil && filterMinLevel == nil && filterText.isEmpty
            ? total
            : visibleEntries().count
        let pausedSuffix = isPaused ? " — PAUSED" : ""
        statusLabel.stringValue = "Showing \(visible) of \(total) total\(pausedSuffix)"
    }

    private func formatEntry(_ entry: DebugLogEntry) -> String {
        let ts = timeFormatter.string(from: entry.date)
        switch entry.level {
        case .info:    return "[\(ts)] [\(entry.category)] \(entry.message)"
        case .warning: return "[\(ts)] [WARN] [\(entry.category)] \(entry.message)"
        case .error:   return "[\(ts)] [ERR ] [\(entry.category)] \(entry.message)"
        }
    }

    // MARK: - Category popup

    private func rebuildCategoryPopup() {
        let selected = filterCategory
        categoryPopup.removeAllItems()
        categoryPopup.addItem(withTitle: "All Categories")
        categoryPopup.lastItem?.tag = -1
        for cat in knownCategories {
            categoryPopup.addItem(withTitle: cat)
        }
        if let cat = selected,
           let item = categoryPopup.itemArray.first(where: { $0.title == cat }) {
            categoryPopup.select(item)
        } else {
            categoryPopup.selectItem(withTag: -1)
        }
    }

    // MARK: - Settings observation

    @objc private func debugConsoleSettingDidChange() {
        let enabled = SettingsWindowController.isDebugConsoleEnabled()
        if enabled && !isEnabled {
            isEnabled = true
            rebuildTextView()
            updateStatus()
            showWindow(nil)
            appendEntry(DebugLogEntry(date: Date(), level: .info,
                                      category: "console", message: "Debug Console enabled"))
        } else if !enabled && isEnabled {
            appendEntry(DebugLogEntry(date: Date(), level: .info,
                                      category: "console", message: "Debug Console disabled"))
            isEnabled = false
            window?.orderOut(nil)
        }
    }

    // MARK: - Button actions

    @objc private func pauseTapped() {
        isPaused.toggle()
        pauseButton.title = isPaused ? "Resume" : "Pause"
        if !isPaused {
            rebuildTextView()
        }
        updateStatus()
    }

    @objc private func clearTapped() {
        entries.removeAll()
        knownCategories.removeAll()
        filterCategory = nil
        rebuildCategoryPopup()
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        updateStatus()
    }

    @objc private func copyAllTapped() {
        let text = sanitizedText(entries.map { formatEntry($0) }.joined(separator: "\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyFeedback()
    }

    @objc private func exportTapped() {
        let panel = NSSavePanel()
        panel.title = "Export Debug Log"
        let safe = timeFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        panel.nameFieldStringValue = "dwb player debug-\(safe).txt"
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self = self else { return }
            let text = self.sanitizedText(self.entries.map { self.formatEntry($0) }.joined(separator: "\n"))
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "The debug log could not be written to the selected location.\n\n\(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func copySnapshotTapped() {
        let total = entries.count
        let visible = visibleEntries().count
        let pausedNote = isPaused ? " [PAUSED]" : ""
        let ts = timeFormatter.string(from: Date())
        var lines: [String] = [
            "dwb player Debug Snapshot — \(ts)",
            "Buffer: \(total) entries, \(visible) visible\(pausedNote)",
            ""
        ]
        let recent = entries.suffix(20)
        lines.append("Last \(recent.count) of \(total) entries:")
        lines.append(contentsOf: recent.map { formatEntry($0) })
        let text = sanitizedText(lines.joined(separator: "\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopyFeedback()
    }

    // MARK: - Sanitization helpers

    private func sanitizedText(_ raw: String) -> String {
        let prefixes = [
            SettingsWindowController.customPrefixValue(),
            SettingsWindowController.customPrefixSecondaryValue()
        ].filter { !$0.isEmpty }
        return DebugLogSanitizer(prefixesToRedact: prefixes).sanitize(raw)
    }

    private func showCopyFeedback() {
        statusLabel.stringValue = "Copied to clipboard (sanitized)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if self.statusLabel.stringValue == "Copied to clipboard (sanitized)" {
                self.updateStatus()
            }
        }
    }

    @objc private func categoryChanged(_ sender: NSPopUpButton) {
        let title = sender.titleOfSelectedItem ?? ""
        filterCategory = (title == "All Categories") ? nil : title
        if !isPaused { rebuildTextView() }
        updateStatus()
    }

    @objc private func levelChanged(_ sender: DWBSegmentedControl) {
        switch sender.selectedSegment {
        case 1:  filterMinLevel = .warning
        case 2:  filterMinLevel = .error
        default: filterMinLevel = nil
        }
        if !isPaused { rebuildTextView() }
        updateStatus()
    }

    @objc private func searchTextChanged(_ notification: Notification) {
        filterText = searchField.stringValue
        if !isPaused { rebuildTextView() }
        updateStatus()
    }

    // MARK: - Init

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "dwb player Debug Console"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 500, height: 300)
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
            panel.standardWindowButton(buttonType)?.isHidden = false
            panel.standardWindowButton(buttonType)?.isEnabled = true
        }
        super.init(window: panel)
        buildUI()
        isEnabled = SettingsWindowController.isDebugConsoleEnabled()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugConsoleSettingDidChange),
            name: .debugConsoleSettingChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchTextChanged(_:)),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )
        DWBAppearance.observe(self, selector: #selector(appearanceDidChange))
        if isEnabled { showWindow(nil) }
    }

    @objc private func appearanceDidChange() {
        restyleChrome()
        rebuildTextView()
        updateStatus()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI construction

    /// Framed console: `surfaceSunken` log between a `canvas` toolbar (top) and footer (bottom).
    private func buildUI() {
        guard let cv = window?.contentView else { return }
        window?.backgroundColor = DWBColor.surfaceSunken

        let W = cv.bounds.width   // 780
        let H = cv.bounds.height
        let toolbarH: CGFloat = 76
        let footerH: CGFloat = 24

        // ── Toolbar (top) ─────────────────────────────────────────────
        toolbarView.wantsLayer = true
        toolbarView.frame = NSRect(x: 0, y: H - toolbarH, width: W, height: toolbarH)
        toolbarView.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(toolbarView)

        toolbarRule.wantsLayer = true
        toolbarRule.frame = NSRect(x: 0, y: 0, width: W, height: 1)
        toolbarRule.autoresizingMask = [.width]
        toolbarView.addSubview(toolbarRule)

        // Row 1 — filter controls
        let filterY: CGFloat = 42
        let filterH: CGFloat = 24
        let catW:    CGFloat = 140
        let lvlW:    CGFloat = 156
        let gap:     CGFloat = 8
        let searchW  = W - 10 - gap - catW - gap - lvlW - 10

        searchField.placeholderString = "Filter…"
        searchField.font = .systemFont(ofSize: 11)
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = DWBMetrics.radiusPill
        searchField.layer?.borderWidth = 1
        searchField.frame = NSRect(x: 10, y: filterY, width: searchW, height: filterH)
        searchField.autoresizingMask = [.width]
        searchField.setAccessibilityLabel("Filter log")
        toolbarView.addSubview(searchField)

        categoryPopup.translatesAutoresizingMaskIntoConstraints = true
        categoryPopup.target = self
        categoryPopup.action = #selector(categoryChanged(_:))
        categoryPopup.addItem(withTitle: "All Categories")
        categoryPopup.lastItem?.tag = -1
        categoryPopup.frame = NSRect(x: W - lvlW - gap - catW - 10, y: filterY, width: catW, height: filterH)
        categoryPopup.autoresizingMask = [.minXMargin]
        categoryPopup.setAccessibilityLabel("Category filter")
        toolbarView.addSubview(categoryPopup)

        levelSegment.segments = ["All", "⚠ Warn", "✕ Err"]
        levelSegment.selectedSegment = 0
        levelSegment.target = self
        levelSegment.action = #selector(levelChanged(_:))
        let segmentSize = levelSegment.intrinsicContentSize
        levelSegment.frame = NSRect(x: W - segmentSize.width - 10, y: filterY - 1, width: segmentSize.width, height: segmentSize.height)
        levelSegment.autoresizingMask = [.minXMargin]
        levelSegment.setAccessibilityLabel("Level filter")
        toolbarView.addSubview(levelSegment)

        // Row 2 — action buttons
        let btnY: CGFloat = 10
        func makeBtn(_ title: String, action: Selector) -> DWBButton {
            let b = DWBButton(title: title, variant: .neutral, size: .small)
            b.target = self
            b.action = action
            b.translatesAutoresizingMaskIntoConstraints = true
            return b
        }

        let btns: [DWBButton] = [
            makeBtn("Clear",    action: #selector(clearTapped)),
            makeBtn("Copy All", action: #selector(copyAllTapped)),
            makeBtn("Snapshot", action: #selector(copySnapshotTapped)),
            makeBtn("Export…",  action: #selector(exportTapped)),
        ]
        var bx: CGFloat = 10
        for btn in btns {
            let bw = max(54, btn.intrinsicContentSize.width)
            btn.frame = NSRect(x: bx, y: btnY, width: bw, height: 24)
            toolbarView.addSubview(btn)
            bx += bw + 6
        }

        pauseButton.translatesAutoresizingMaskIntoConstraints = true
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        let pauseW = max(60, pauseButton.intrinsicContentSize.width)
        pauseButton.frame = NSRect(x: W - pauseW - 10, y: btnY, width: pauseW, height: 24)
        pauseButton.autoresizingMask = [.minXMargin]
        toolbarView.addSubview(pauseButton)

        // ── Footer (bottom) ───────────────────────────────────────────
        footerView.wantsLayer = true
        footerView.frame = NSRect(x: 0, y: 0, width: W, height: footerH)
        footerView.autoresizingMask = [.width]
        cv.addSubview(footerView)

        footerRule.wantsLayer = true
        footerRule.frame = NSRect(x: 0, y: footerH - 1, width: W, height: 1)
        footerRule.autoresizingMask = [.width]
        footerView.addSubview(footerRule)

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        statusLabel.frame = NSRect(x: 12, y: 4, width: W - 24, height: 14)
        statusLabel.autoresizingMask = [.width]
        statusLabel.setAccessibilityLabel("Log status")
        footerView.addSubview(statusLabel)

        // ── Log ───────────────────────────────────────────────────────
        scrollView.frame = NSRect(x: 0, y: footerH, width: W, height: H - toolbarH - footerH)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = DWBColor.surfaceSunken
        cv.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = DWBColor.surfaceSunken
        textView.font = Self.logFont
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("Debug log")
        scrollView.documentView = textView

        restyleChrome()
        updateStatus()
    }

    /// Colors that depend on Increase Contrast.
    private func restyleChrome() {
        let appearance = DWBAppearance.shared
        toolbarView.layer?.backgroundColor = DWBColor.canvas.cgColor
        footerView.layer?.backgroundColor = DWBColor.canvas.cgColor
        toolbarRule.layer?.backgroundColor = appearance.border.cgColor
        footerRule.layer?.backgroundColor = appearance.border.cgColor
        statusLabel.textColor = appearance.textTertiary
        searchField.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        searchField.layer?.borderColor = appearance.border.cgColor
        searchField.textColor = DWBColor.textPrimary
        searchField.placeholderAttributedString = NSAttributedString(string: "Filter…", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: appearance.textTertiary
        ])
    }
}
