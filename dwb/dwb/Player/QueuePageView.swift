import Cocoa

/// Delegate for queue-page interactions.
protocol QueuePageViewDelegate: AnyObject {
    func queuePage(_ view: QueuePageView, didSelectDisplayIndex index: Int)
    func queuePage(_ view: QueuePageView, didRequestRenameAt index: Int)
    func queuePage(_ view: QueuePageView, didRequestRevealAt index: Int)
    func queuePage(_ view: QueuePageView, didRequestDeleteAt index: Int)
    func queuePage(_ view: QueuePageView, didChangeSortMode mode: QueueSortMode)
    func queuePageDidRequestClose(_ view: QueuePageView)
    /// Called when the user drags a row from `from` to the insertion point `to`
    /// (NSTableView .above drop-operation semantics; 0…items.count).
    func queuePage(_ view: QueuePageView, didReorderFromIndex from: Int, toIndex to: Int)
    /// Called when the user activates "Remove All" in the queue page.
    func queuePageDidRequestRemoveAll(_ view: QueuePageView)
    /// Called when the user triggers the one-click custom prefix rename action (feature-gated).
    /// `indices` is always ascending. Caller must preflight all targets before renaming any.
    func queuePage(_ view: QueuePageView, didRequestCustomPrefixRenameAt indices: [Int])
    /// Called when the user triggers the secondary custom prefix rename action (feature-gated).
    /// `indices` is always ascending. Caller must preflight all targets before renaming any.
    func queuePage(_ view: QueuePageView, didRequestSecondaryCustomPrefixRenameAt indices: [Int])
    /// Called when the user presses Delete/Backspace with multiple rows selected.
    /// `indices` is sorted descending so the caller can delete safely without index shifts.
    func queuePage(_ view: QueuePageView, didRequestDeleteRows indices: [Int])
    /// Called from the queue empty state to use the app's existing media-open flow.
    func queuePageDidRequestAddMedia(_ view: QueuePageView)
    /// Called when the user triggers the folder rescan action from the queue footer.
    func queuePageDidRequestRescan(_ view: QueuePageView)
    /// Called when the user invokes Play Next on a queue entry from the context menu.
    /// `displayIndex` is the canonical display-order index of the entry to move.
    func queuePage(_ view: QueuePageView, didRequestPlayNextAt displayIndex: Int)
    /// Called when the user presses Undo in the footer's marker group. Runs the same
    /// undo as Command-Z.
    func queuePageDidRequestUndoMarkerRename(_ view: QueuePageView)
    /// Called when `N`, `M` or `R` is pressed with the queue table focused (no modifiers, no
    /// text field being edited).
    func queuePage(_ view: QueuePageView, didRequestPrefixKeyAction action: PrefixKeyRouting.Action)
}

private final class QueueSharedEdgeDividerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Full in-window Queue Page panel.
/// Designed to occupy ~35–45 % of the window width as a right-side panel.
/// Shows the playback set in current traversal order with filename, duration,
/// and file size. Supports single-click selection, double-click playback, and
/// queue file actions.
final class QueuePageView: NSView, NSSearchFieldDelegate {

    // MARK: - Item model

    struct Item {
        let url:         URL
        var displayName: String
        var duration:    String   // "1:23:45" or "--:--"
        var fileSize:    String   // "12.3 MB" or "--"
        var isBookmarked: Bool = false
        /// True when playback of this file failed in this window. Display-only.
        var isFailed: Bool = false
        /// 1-based position in the Play Next chain; nil when the item is not waiting in it.
        var playNextPosition: Int? = nil
    }

    private enum VisibleRow {
        case section(String)
        case item(displayIndex: Int, item: Item)

        var displayIndex: Int? {
            if case let .item(displayIndex, _) = self { return displayIndex }
            return nil
        }

        var item: Item? {
            if case let .item(_, item) = self { return item }
            return nil
        }
    }

    // MARK: - Public state

    weak var delegate: QueuePageViewDelegate?

    /// Call update(items:currentIndex:) to refresh data and reload the table.
    private(set) var items: [Item] = []
    private var visibleItems: [Item] = []
    private var visibleToDisplayIndices: [Int] = []
    private var visibleRows: [VisibleRow] = []
    private var pendingSelectionAnchorRow: Int?
    private(set) var currentDisplayIndex: Int = -1
    private var currentSortMode: QueueSortMode = .manual
    private var allowsManualReorder = true
    private var isUpdatingSortControl = false
    /// True while the user has scrolled upward into the PREVIOUS history area.
    /// Suppresses auto-follow until they scroll back down past NOW PLAYING.
    private var userIsReviewingHistory = false
    private var totalDurationText = MediaFileSupport.formatClockDuration(0)
    private var bookmarkFilterEnabled = false
    private let sharedEdgeDivider = QueueSharedEdgeDividerView(frame: .zero)

    /// True while this window has a marker rename it can still undo. Set by the window controller.
    var isUndoAvailable: Bool = false {
        didSet { needsLayout = true }
    }

    func update(items: [Item], currentIndex: Int, sortMode: QueueSortMode, totalDurationText: String) {
        let selectedURLs = Set(tableView.selectedRowIndexes.compactMap { row -> URL? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.url
        })
        let scroll = currentIndex != currentDisplayIndex && currentIndex >= 0 && !userIsReviewingHistory
        self.items = items
        self.currentDisplayIndex = currentIndex
        self.totalDurationText = totalDurationText
        currentSortMode = sortMode
        allowsManualReorder = sortMode == .manual && currentSearchQuery.isEmpty
        updateSortControlSelection()
        updateHeaderSortIndicators()
        applySearchFilter(preservingSelectedURLs: selectedURLs)
        if scroll {
            scrollNowPlayingToTop()
        }
        applyColumnLayout(reason: "queue-reload", forceDiagnostic: false)
    }

    /// Scrolls so the NOW PLAYING section header is at the top of the visible area.
    private func scrollNowPlayingToTop() {
        guard currentDisplayIndex >= 0,
              let itemRow = visibleRow(forDisplayIndex: currentDisplayIndex) else { return }
        let targetRow = max(0, itemRow - 1)
        let rowRect = tableView.rect(ofRow: targetRow)
        let targetY = max(0, rowRect.minY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        userIsReviewingHistory = false
    }

    // MARK: - Subviews

    private let headerView       = NSView()
    private let titleLabel       = NSTextField(labelWithString: "Queue")
    private let searchSortPill   = QueueSearchSortPillView()
    private let searchSortDivider = QueuePassthroughView()
    private let searchIconView   = QueueCenteredSymbolView()
    private let sortPopUpButton  = NSPopUpButton()
    private let sortButtonBackground = NSView()
    private let sortTitleView    = QueueCenteredTextView()
    private let sortChevronView  = QueueCenteredSymbolView()
    private let searchField      = NSSearchField()
    private let bookmarkFilterButton = QueueHeaderSymbolButton(frame: .zero)
    private let closeButton      = QueueHeaderSymbolButton(frame: .zero)
    private let topSeparator     = NSView()
    let scrollView               = NSScrollView()
    let tableView                = QueuePageTableView()
    private let emptyStateView   = NSView()
    private let emptyStateLogoView = NSImageView()
    private let emptyStateCircleView = NSView()
    private let emptyStateGlyphView = NSImageView()
    private let emptyStateLabel  = NSTextField(labelWithString: "No media in queue")
    private let emptyStateDetailLabel = NSTextField(labelWithString: "Add files or folders to build the queue.")
    private let addMediaButton   = QueuePillButton(style: .outlineAccent, labelColor: { PlayerTheme.current.accentText })
    private let bottomSeparator  = NSView()
    private let bottomBar        = NSView()
    private let deleteButton              = NSButton()
    private let markerGroup               = QueueMarkerChipGroupView(frame: .zero)
    private var customPrefixButton: QueueMarkerChipButton { markerGroup.primaryChip }
    private var customPrefixSecondaryButton: QueueMarkerChipButton { markerGroup.secondaryChip }
    private let rescanButton              = QueuePillButton(labelColor: { DWBColor.textPrimary })
    private let footerClearSeparator      = NSView()
    private let removeAllButton           = QueuePillButton(labelColor: { DWBColor.errorText })
    private let totalDurationLabel = NSTextField(labelWithString: "Total: 00:00:00")
    private enum EmptyStateAction {
        case addMedia
        case clearFilters
    }
    private var emptyStateAction: EmptyStateAction = .addMedia
    private let dropIndicator = QueueDropIndicatorView(frame: .zero)
    /// The visible row being dragged, shown at 0.4 alpha until the drag ends.
    private var draggedVisibleRow: Int?
    private var usesCompactFooterIcons = false

    // Column identifiers
    private static let colName = NSUserInterfaceItemIdentifier("name")

    // Footer-safe trailing boundary: keeps the total-duration label visually
    // separated from the far-right panel edge, aligning it under the metadata
    // columns rather than hugging the Size column's right text edge. This is
    // intentionally a footer-only inset; it does not affect column/header/row geometry.
    private static let totalDurationTrailingInset: CGFloat = 72

    // Padding constants used by QueueColumnGeometry to keep header labels, row
    // cells, and the bottom total-duration label aligned to the same content insets.
    fileprivate static let cellLeadingPadding: CGFloat = 8
    fileprivate static let cellTrailingPadding: CGFloat = 8

    // Pasteboard type for internal row-reorder drag
    private static let draggedRowType = NSPasteboard.PasteboardType("com.dwb.queueRow")
    private var lastCoordinateDiagnosticTimeByReason: [String: Date] = [:]

    // Layout reentrancy guard and coalescing state.
    // isApplyingColumnLayout is set while inside applyColumnLayout; prevents
    // synchronous recursion. pendingColumnLayout captures any request that
    // arrives while the guard is held — the defer block drains it via
    // DispatchQueue.main.async so it never recurses on the same call stack.
    private var isApplyingColumnLayout = false
    private var pendingColumnLayout: (reason: String, force: Bool)? = nil

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupViews()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupViews() {
        layer?.backgroundColor = DWBColor.surface.cgColor

        // ── Header ──────────────────────────────────────────────────────────
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(headerView)

        titleLabel.font           = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor      = DWBColor.textPrimary
        titleLabel.drawsBackground = false
        titleLabel.isEditable     = false
        titleLabel.isBordered     = false
        headerView.addSubview(titleLabel)

        searchSortPill.wantsLayer = true
        searchSortPill.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        searchSortPill.layer?.borderColor = DWBAppearance.shared.border.cgColor
        searchSortPill.layer?.borderWidth = 1
        searchSortPill.layer?.cornerRadius = DWBMetrics.radiusPill
        headerView.addSubview(searchSortPill)

        searchSortDivider.wantsLayer = true
        searchSortDivider.layer?.backgroundColor = DWBAppearance.shared.border.cgColor
        searchSortPill.addSubview(searchSortDivider)

        // Nested "button" background for the sort control so "Sort: Manual"
        // reads as a distinct pill/button rather than loose text sharing the
        // search field's background. Only the two right corners are rounded
        // (radius matches the outer pill) so it sits flush with the outer
        // pill's right edge.
        sortButtonBackground.wantsLayer = true
        sortButtonBackground.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        sortButtonBackground.layer?.cornerRadius = 12
        sortButtonBackground.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        searchSortPill.addSubview(sortButtonBackground)

        searchIconView.configure(symbolName: "magnifyingglass",
                                 pointSize: 12,
                                 weight: .regular,
                                 color: DWBAppearance.shared.textTertiary,
                                 accessibilityDescription: nil)
        searchSortPill.addSubview(searchIconView)

        sortTitleView.font = .systemFont(ofSize: 10.5, weight: .regular)
        sortTitleView.textColor = DWBAppearance.shared.textSecondary
        searchSortPill.addSubview(sortTitleView)

        sortChevronView.configure(symbolName: "chevron.up.chevron.down",
                                  pointSize: 10,
                                  weight: .medium,
                                  color: DWBAppearance.shared.textSecondary,
                                  accessibilityDescription: nil)
        searchSortPill.addSubview(sortChevronView)

        sortPopUpButton.cell = QueueTransparentPopUpButtonCell(textCell: "", pullsDown: false)
        sortPopUpButton.font = .systemFont(ofSize: 10.5, weight: .regular)
        sortPopUpButton.bezelStyle = .rounded
        sortPopUpButton.isBordered = false
        sortPopUpButton.target = self
        sortPopUpButton.action = #selector(sortModeChanged)
        sortPopUpButton.toolTip = "Queue sort order"
        sortPopUpButton.setAccessibilityLabel("Queue sort order")
        sortPopUpButton.setAccessibilityHelp("Choose how queue cards are sorted")
        sortPopUpButton.setAccessibilityIdentifier("queue.header.sort")
        QueueSortMode.allCases.forEach { mode in
            let title = mode == .manual ? "Sort: Manual" : "Sort: \(mode.title)"
            sortPopUpButton.addItem(withTitle: title)
            sortPopUpButton.lastItem?.tag = mode.rawValue
        }
        updateSortControlSelection()
        searchSortPill.addSubview(sortPopUpButton)

        searchField.cell = QueueSearchFieldCell(textCell: "")
        searchField.isEditable = true
        searchField.placeholderString = "Search queue"
        applySearchPlaceholder()
        searchField.font = .systemFont(ofSize: 11)
        searchField.textColor = DWBColor.textPrimary
        searchField.backgroundColor = .clear
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.toolTip = "Search queue filenames"
        searchField.setAccessibilityLabel("Search queue")
        searchField.setAccessibilityIdentifier("queue.header.search")
        searchSortPill.searchField = searchField
        searchSortPill.addSubview(searchField)

        bookmarkFilterButton.isBordered = false
        bookmarkFilterButton.bezelStyle = .regularSquare
        bookmarkFilterButton.symbolPointSize = 13
        bookmarkFilterButton.symbolWeight = .medium
        bookmarkFilterButton.target = self
        bookmarkFilterButton.action = #selector(bookmarkFilterTapped)
        bookmarkFilterButton.setButtonType(.toggle)
        bookmarkFilterButton.toolTip = "Show bookmarked queue files"
        bookmarkFilterButton.setAccessibilityLabel("Bookmark filter")
        bookmarkFilterButton.setAccessibilityHelp("Show only bookmarked queue files")
        bookmarkFilterButton.setAccessibilityIdentifier("queue.header.bookmarkFilter")
        headerView.addSubview(bookmarkFilterButton)
        updateBookmarkFilterButton()

        closeButton.isBordered     = false
        closeButton.bezelStyle     = .regularSquare
        closeButton.symbolName     = "xmark"
        closeButton.symbolPointSize = 10
        closeButton.symbolWeight   = .medium
        closeButton.contentTintColor = DWBAppearance.shared.textSecondary
        closeButton.toolTip          = "Close Queue"
        closeButton.setAccessibilityLabel("Close Queue")
        closeButton.setAccessibilityHelp("Close the Queue Page")
        closeButton.setAccessibilityIdentifier("queue.header.close")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        headerView.addSubview(closeButton)

        // ── Separators ────────────────────────────────────────────────────
        for sep in [topSeparator, bottomSeparator] {
            sep.wantsLayer = true
            sep.layer?.backgroundColor = DWBAppearance.shared.border.cgColor
            addSubview(sep)
        }

        // ── Table ─────────────────────────────────────────────────────────
        // Card rows own their duration and size metadata; the table intentionally
        // has one layout column and ignores legacy column-visibility defaults.
        let nameCol = NSTableColumn(identifier: Self.colName)
        nameCol.title  = "File"
        nameCol.resizingMask = []
        nameCol.minWidth = 1
        nameCol.headerCell = QueueColumnHeaderCell(title: "File", alignment: .left)

        tableView.addTableColumn(nameCol)
        updateHeaderSortIndicators()
        // applyColumnLayout() is the single source of truth; AppKit must not mutate widths.
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.headerView   = nil
        tableView.rowHeight    = QueuePanelMetrics.tableRowHeight
        // Rows are positioned by `QueuePanelMetrics`; the automatic (inset) table style
        // would add its own side padding on top.
        tableView.style        = .fullWidth
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.gridColor = DWBColor.gridLine
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsMultipleSelection = true
        tableView.setAccessibilityLabel("Queue items")
        tableView.setAccessibilityIdentifier("queue.table")
        tableView.dataSource   = self
        tableView.delegate     = self
        tableView.target       = self
        tableView.action       = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(for: row)
        }

        // Enable row reordering via drag-and-drop
        tableView.registerForDraggedTypes([Self.draggedRowType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        // The drop line (9.7) replaces the system's insertion indicator.
        tableView.draggingDestinationFeedbackStyle = .none
        tableView.onDragEnded = { [weak self] in self?.endDragFeedback() }
        tableView.addSubview(dropIndicator)

        let lockedClipView = LockedHorizontalClipView()
        lockedClipView.drawsBackground = false
        scrollView.contentView          = lockedClipView
        scrollView.documentView           = tableView
        scrollView.hasVerticalScroller     = true
        scrollView.hasHorizontalScroller   = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.autohidesScrollers      = true
        scrollView.borderType              = .noBorder
        scrollView.backgroundColor         = .clear
        addSubview(scrollView)

        emptyStateView.wantsLayer = true
        emptyStateView.layer?.backgroundColor = NSColor.clear.cgColor
        emptyStateView.setAccessibilityRole(.group)
        emptyStateView.setAccessibilityIdentifier("queue.emptyState")
        addSubview(emptyStateView)

        // The faded app icon is the only imagery; the title stays the loudest thing.
        emptyStateLogoView.image = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
        emptyStateLogoView.imageScaling = .scaleProportionallyUpOrDown
        emptyStateLogoView.alphaValue = 0.32
        emptyStateLogoView.isEditable = false
        emptyStateLogoView.setAccessibilityElement(false)
        emptyStateLogoView.focusRingType = .none
        emptyStateLogoView.wantsLayer = true
        emptyStateLogoView.contentFilters = Self.fadedIconFilters()
        emptyStateView.addSubview(emptyStateLogoView)

        // The filtered empty states use a neutral circle with a glyph instead of the app icon.
        emptyStateCircleView.wantsLayer = true
        emptyStateCircleView.layer?.cornerRadius = QueueFilteredEmptyState.circleDiameter / 2
        emptyStateCircleView.layer?.borderWidth = 1
        emptyStateCircleView.isHidden = true
        emptyStateView.addSubview(emptyStateCircleView)
        emptyStateGlyphView.imageScaling = .scaleProportionallyDown
        emptyStateGlyphView.setAccessibilityElement(false)
        emptyStateGlyphView.isHidden = true
        emptyStateView.addSubview(emptyStateGlyphView)
        applyEmptyStateCircleAppearance()

        emptyStateLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        emptyStateLabel.textColor = DWBColor.textPrimary
        emptyStateLabel.alignment = .center
        emptyStateLabel.drawsBackground = false
        emptyStateLabel.isEditable = false
        emptyStateLabel.isBordered = false
        emptyStateLabel.isSelectable = false
        emptyStateView.addSubview(emptyStateLabel)

        emptyStateDetailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        emptyStateDetailLabel.textColor = DWBAppearance.shared.textTertiary
        emptyStateDetailLabel.alignment = .center
        emptyStateDetailLabel.drawsBackground = false
        emptyStateDetailLabel.isEditable = false
        emptyStateDetailLabel.isBordered = false
        emptyStateDetailLabel.isSelectable = false
        emptyStateDetailLabel.lineBreakMode = .byWordWrapping
        emptyStateView.addSubview(emptyStateDetailLabel)

        addMediaButton.labelText = "Add Media"
        addMediaButton.toolTip = "Add media to the queue"
        addMediaButton.setAccessibilityLabel("Add Media")
        addMediaButton.setAccessibilityHelp("Choose local files or folders to add to the queue")
        addMediaButton.setAccessibilityIdentifier("queue.empty.addMedia")
        addMediaButton.target = self
        addMediaButton.action = #selector(emptyStateActionTapped)
        emptyStateView.addSubview(addMediaButton)

        // Re-run the column layout when the clip view's width changes — this happens
        // when the vertical scroller toggles, which would otherwise leave the Size
        // column extending past the visible cell area on the right edge.
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scrollContentDidResize),
                                               name: NSView.frameDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scrollContentDidResize),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(scrollDidEndLive),
                                               name: NSScrollView.didEndLiveScrollNotification,
                                               object: scrollView)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleCustomPrefixValueChanged),
                                               name: .customPrefixValueChanged,
                                               object: nil)

        // ── Bottom bar ────────────────────────────────────────────────────
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(bottomBar)

        deleteButton.isBordered     = false
        deleteButton.bezelStyle     = .regularSquare
        deleteButton.imageScaling   = .scaleProportionallyDown
        let removeCfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let img = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Remove") {
            deleteButton.image = img.withSymbolConfiguration(removeCfg) ?? img
        }
        deleteButton.contentTintColor = DWBColor.errorText
        deleteButton.toolTip   = "Remove from Queue"
        deleteButton.setAccessibilityLabel("Remove from Queue")
        deleteButton.setAccessibilityHelp("Remove the selected rows from the queue without deleting files")
        deleteButton.setAccessibilityIdentifier("queue.footer.removeSelected")
        deleteButton.focusRingType = .default
        deleteButton.target    = self
        deleteButton.action    = #selector(deleteTapped)
        bottomBar.addSubview(deleteButton)

        // Marker chip group: primary and secondary prefix chips plus Undo.
        bottomBar.addSubview(markerGroup)

        customPrefixButton.setAccessibilityIdentifier("queue.footer.primaryPrefix")
        customPrefixButton.target = self
        customPrefixButton.action = #selector(customPrefixTapped)

        customPrefixSecondaryButton.setAccessibilityIdentifier("queue.footer.secondaryPrefix")
        customPrefixSecondaryButton.target = self
        customPrefixSecondaryButton.action = #selector(customPrefixSecondaryTapped)

        markerGroup.undoButton.target = self
        markerGroup.undoButton.action = #selector(undoMarkerRenameTapped)

        rescanButton.labelText = "Rescan"
        rescanButton.setIconSymbol("arrow.clockwise", description: "Rescan Folder")
        rescanButton.toolTip        = "Rescan Folder — refresh the queue from current folder contents on disk"
        rescanButton.setAccessibilityLabel("Rescan Folder")
        rescanButton.setAccessibilityHelp("Refresh the queue from current folder contents on disk")
        rescanButton.setAccessibilityIdentifier("queue.footer.rescan")
        rescanButton.target         = self
        rescanButton.action         = #selector(rescanTapped)
        bottomBar.addSubview(rescanButton)

        footerClearSeparator.wantsLayer = true
        bottomBar.addSubview(footerClearSeparator)

        removeAllButton.labelText    = "Clear Queue"
        removeAllButton.setIconSymbol("trash.slash", description: "Clear Queue")
        removeAllButton.toolTip      = "Clear Queue"
        removeAllButton.setAccessibilityLabel("Clear Queue")
        removeAllButton.setAccessibilityHelp("Remove every item from this window's queue without deleting files")
        removeAllButton.setAccessibilityIdentifier("queue.footer.clear")
        removeAllButton.target       = self
        removeAllButton.action       = #selector(removeAllTapped)
        bottomBar.addSubview(removeAllButton)

        tableView.prefixKeyHandler = { [weak self] action in
            guard let self = self else { return }
            self.delegate?.queuePage(self, didRequestPrefixKeyAction: action)
        }

        // Wire up keyboard-delete handler so Delete/Backspace on a selected row
        // removes that item.  Re-selecting the appropriate row is handled after
        // the table reloads (see QueuePageTableView.keyDown).
        tableView.deleteRowsHandler = { [weak self] indices in
            guard let self = self else { return }
            self.pendingSelectionAnchorRow = indices.min()
            let projection = self.visibleRows.map { row -> QueueDisplayProjection.Row in
                if let displayIndex = row.displayIndex { return .item(displayIndex: displayIndex) }
                return .section("")
            }
            let displayIndices = QueueDisplayProjection
                .displayIndices(forVisibleRows: IndexSet(indices), in: projection)
                .sorted(by: >)
            guard !displayIndices.isEmpty else { return }
            if displayIndices.count == 1 {
                self.delegate?.queuePage(self, didRequestDeleteAt: displayIndices[0])
            } else {
                self.delegate?.queuePage(self, didRequestDeleteRows: displayIndices)
            }
        }

        totalDurationLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        totalDurationLabel.textColor = DWBAppearance.shared.textSecondary
        totalDurationLabel.alignment = .right
        totalDurationLabel.lineBreakMode = .byClipping
        totalDurationLabel.setAccessibilityLabel("Total queue duration")
        totalDurationLabel.setAccessibilityIdentifier("queue.footer.totalDuration")
        bottomBar.addSubview(totalDurationLabel)

        sharedEdgeDivider.wantsLayer = true
        sharedEdgeDivider.layer?.backgroundColor = DWBAppearance.shared.border.cgColor
        sharedEdgeDivider.setAccessibilityElement(false)
        addSubview(sharedEdgeDivider)

        DWBAppearance.observe(self, selector: #selector(appearanceDidChange))
        applyAppearance()

        DispatchQueue.main.async { [weak self] in
            self?.applyColumnLayout(reason: "queue-setup", forceDiagnostic: true)
        }
        needsLayout = true
    }

    // MARK: - Layout constants

    private let headerH: CGFloat = QueuePanelMetrics.headerHeight
    private var footerPlan = QueueFooterLayoutPlan(usesCompactIcons: false, usesCompactUndo: false,
                                                    groupWraps: false, totalOnOwnRow: false)

    override func layout() {
        super.layout()
        let b = bounds

        // Header
        headerView.frame = NSRect(x: 0, y: b.height - headerH, width: b.width, height: headerH)
        let headerAxisY = headerView.bounds.midY
        let edgePad: CGFloat = 12
        let interItemGap: CGFloat = 8
        let queueTitleToPillGap: CGFloat = 10
        let queueTitleTrailingSafety: CGFloat = 5
        let buttonSize = QueuePanelMetrics.headerButton
        closeButton.frame = NSRect(x: max(edgePad, b.width - edgePad - buttonSize),
                                   y: floor(headerAxisY - buttonSize / 2),
                                   width: buttonSize,
                                   height: buttonSize)
        bookmarkFilterButton.frame = NSRect(x: max(edgePad, closeButton.frame.minX - interItemGap - buttonSize),
                                            y: floor(headerAxisY - buttonSize / 2),
                                            width: buttonSize,
                                            height: buttonSize)

        let titlePreferredWidth = ceil(titleLabel.intrinsicContentSize.width) + queueTitleTrailingSafety
        let titleAvailableWidth = max(0, bookmarkFilterButton.frame.minX - interItemGap - 16)
        let titleWidth = min(titlePreferredWidth, titleAvailableWidth)
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        titleLabel.frame = NSRect(x: 16,
                                  y: floor(headerAxisY - titleHeight / 2),
                                  width: titleWidth,
                                  height: titleHeight)
        let pillX = titleLabel.frame.maxX + queueTitleToPillGap
        let pillRight = bookmarkFilterButton.frame.minX - interItemGap
        let maxPillW = max(260, min(560, b.width * 0.66))
        let pillW = max(0, min(pillRight - pillX, maxPillW))
        let pillH = QueuePanelMetrics.searchPillHeight
        searchSortPill.frame = NSRect(x: pillX,
                                      y: floor(headerAxisY - pillH / 2),
                                      width: pillW,
                                      height: pillH)
        searchSortPill.isHidden = pillW <= 0
        let dividerH: CGFloat = 18
        let innerPad: CGFloat = 9
        let searchIconSlotWidth: CGFloat = 20
        let searchFieldX = innerPad + searchIconSlotWidth + 1
        let minimumSearchTextWidth: CGFloat = 72
        let minimumSortWidth: CGFloat = 84
        let sortWidth = min(CGFloat(122), max(minimumSortWidth, pillW * 0.34))
        let sortVisible = pillW >= searchFieldX + minimumSearchTextWidth + 6 + sortWidth
        let effectiveSortWidth = sortVisible ? sortWidth : 0
        let dividerX = sortVisible ? max(0, pillW - effectiveSortWidth - 1) : pillW
        let searchAreaWidth = sortVisible ? dividerX : pillW
        searchSortPill.searchFocusRect = NSRect(x: 0,
                                                y: 0,
                                                width: max(0, searchAreaWidth),
                                                height: pillH)
        searchSortDivider.frame = NSRect(x: dividerX,
                                         y: centeredY(height: dividerH, in: pillH),
                                         width: 1,
                                         height: dividerH)
        searchSortDivider.isHidden = !sortVisible
        searchIconView.frame = NSRect(x: innerPad,
                                      y: 0,
                                      width: searchIconSlotWidth,
                                      height: pillH)
        let searchFieldHeight: CGFloat = 20
        searchField.frame = NSRect(x: searchFieldX,
                                   y: centeredY(height: searchFieldHeight, in: pillH),
                                   width: max(0, searchAreaWidth - searchFieldX - 5),
                                   height: searchFieldHeight)
        let sortHeight: CGFloat = 24
        let sortFrame = NSRect(x: dividerX + 1,
                               y: centeredY(height: sortHeight, in: pillH),
                               width: max(0, effectiveSortWidth),
                               height: sortHeight)
        sortPopUpButton.isHidden = !sortVisible
        sortButtonBackground.isHidden = !sortVisible
        sortTitleView.isHidden = !sortVisible
        sortChevronView.isHidden = !sortVisible
        sortPopUpButton.frame = sortFrame
        sortButtonBackground.frame = sortVisible
            ? NSRect(x: dividerX + 1, y: 0, width: max(0, pillW - dividerX - 1), height: pillH)
            : .zero
        let sortInnerPad: CGFloat = 8
        let chevronSlotWidth: CGFloat = 20
        sortChevronView.frame = NSRect(x: max(sortFrame.minX, sortFrame.maxX - chevronSlotWidth),
                                       y: sortFrame.minY,
                                       width: min(chevronSlotWidth, sortFrame.width),
                                       height: sortFrame.height)
        sortTitleView.frame = NSRect(x: sortFrame.minX + sortInnerPad,
                                     y: sortFrame.minY,
                                     width: max(0, sortChevronView.frame.minX - sortFrame.minX - sortInnerPad - 4),
                                     height: sortFrame.height)

        topSeparator.frame = NSRect(x: 0, y: b.height - headerH - 1, width: b.width, height: 1)

        // Footer height depends on the footer plan, which depends on the width.
        footerPlan = makeFooterPlan(width: b.width)
        let footerH = QueuePanelMetrics.footerHeight(plan: footerPlan)

        // Table scroll view
        let tableTop = b.height - headerH - 1
        let tableH   = max(0, tableTop - footerH - 1)
        scrollView.frame = NSRect(x: 0, y: footerH + 1, width: b.width, height: tableH)
        emptyStateView.frame = scrollView.frame.insetBy(dx: 22, dy: 28)
        layoutEmptyState()
        scrollView.layoutSubtreeIfNeeded()
        // Do not manually set tableView.headerView.frame here — tile() owns header width,
        // and writing it inside a layout pass posts a frame-change notification that fed
        // back into the P43.6 recursive layout storm.
        applyColumnLayout(reason: "layout", forceDiagnostic: false)

        bottomSeparator.frame = NSRect(x: 0, y: footerH, width: b.width, height: 1)

        // Bottom bar: marker row (Remove + chip group) above the action row, or a
        // single row when there are no marker actions.
        bottomBar.frame = NSRect(x: 0, y: 0, width: b.width, height: footerH)
        layoutFooter(width: b.width, height: footerH)

        // A one-point structural edge keeps the video and Queue Page visually
        // connected without changing either region's geometry or hit testing.
        sharedEdgeDivider.frame = NSRect(x: 0, y: 0, width: 1, height: b.height)
    }

    /// Applies the chip states, measures the footer's items and returns the plan for `width`.
    private func makeFooterPlan(width: CGFloat) -> QueueFooterLayoutPlan {
        let compactIcons = QueueFooterLayoutPlan.usesCompactIcons(width: width)
        if rescanButton.isIconOnly != compactIcons || removeAllButton.isIconOnly != compactIcons {
            rescanButton.isIconOnly = compactIcons
            removeAllButton.isIconOnly = compactIcons
        }
        markerGroup.apply(primary: primaryChipState(),
                          secondary: secondaryChipState(),
                          undoEnabled: isUndoAvailable,
                          compactUndo: footerPlan.usesCompactUndo)
        let plan = QueueFooterLayoutPlan.make(
            width: width,
            removeButtonWidth: QueuePanelMetrics.footerRemoveButtonSize,
            fullGroupWidth: markerGroup.preferredWidth(compactUndo: false),
            compactUndoGroupWidth: markerGroup.preferredWidth(compactUndo: true),
            rescanWidth: rescanButton.preferredWidth(),
            totalWidth: ceil(totalDurationLabel.intrinsicContentSize.width),
            clearWidth: removeAllButton.preferredWidth())
        markerGroup.apply(primary: primaryChipState(),
                          secondary: secondaryChipState(),
                          undoEnabled: isUndoAvailable,
                          compactUndo: plan.usesCompactUndo)
        return plan
    }

    /// Rows from the bottom: Rescan row, then the total label when it needs its own row,
    /// then the marker group (own row when wrapped), then Remove (beside the group unless wrapped).
    private func layoutFooter(width: CGFloat, height: CGFloat) {
        let plan = footerPlan
        let pad = QueuePanelMetrics.footerHorizontalPadding
        let gap = QueuePanelMetrics.footerRowGap
        let rowSpacing = QueuePanelMetrics.footerRowSpacing
        let pillH = QueuePanelMetrics.footerPillHeight
        let removeSize = QueuePanelMetrics.footerRemoveButtonSize
        let groupH = QueuePanelMetrics.markerGroupHeight
        let rowWidth = width - pad * 2

        // Last row: Rescan, total, divider, Clear Queue.
        let actionRowY = QueuePanelMetrics.footerBottomPadding
        var nextRowY = actionRowY + pillH + rowSpacing

        let rescanW = rescanButton.preferredWidth()
        rescanButton.frame = NSRect(x: pad, y: actionRowY, width: rescanW, height: pillH)
        rescanButton.isEnabled = !items.isEmpty

        let clearW = removeAllButton.preferredWidth()
        removeAllButton.frame = NSRect(x: width - pad - clearW, y: actionRowY, width: clearW, height: pillH)
        removeAllButton.isEnabled = !items.isEmpty

        let dividerW = QueuePanelMetrics.footerDividerWidth
        footerClearSeparator.isHidden = false
        footerClearSeparator.frame = NSRect(x: removeAllButton.frame.minX - gap - dividerW,
                                            y: actionRowY + floor((pillH - 16) / 2),
                                            width: dividerW, height: 16)
        let totalHeight = ceil(totalDurationLabel.intrinsicContentSize.height)
        if plan.totalOnOwnRow {
            let rowH = QueuePanelMetrics.footerTotalRowHeight
            totalDurationLabel.frame = NSRect(x: pad,
                                              y: nextRowY + floor((rowH - totalHeight) / 2),
                                              width: rowWidth, height: totalHeight)
            nextRowY += rowH + rowSpacing
        } else {
            let totalX = rescanButton.frame.maxX + gap
            totalDurationLabel.frame = NSRect(x: totalX,
                                              y: actionRowY + floor((pillH - totalHeight) / 2),
                                              width: max(0, footerClearSeparator.frame.minX - gap - totalX),
                                              height: totalHeight)
        }

        // Marker group, then Remove.
        markerGroup.isHidden = false
        let groupW = markerGroup.preferredWidth(compactUndo: plan.usesCompactUndo)
        if plan.groupWraps {
            markerGroup.frame = NSRect(x: pad, y: nextRowY, width: groupW, height: groupH)
            let removeRowY = nextRowY + groupH + rowSpacing
            deleteButton.frame = NSRect(x: pad, y: removeRowY, width: removeSize, height: removeSize)
        } else {
            deleteButton.frame = NSRect(x: pad,
                                        y: nextRowY + floor((groupH - removeSize) / 2),
                                        width: removeSize, height: removeSize)
            markerGroup.frame = NSRect(x: deleteButton.frame.maxX + gap, y: nextRowY,
                                       width: groupW, height: groupH)
        }
    }

    private func layoutEmptyState() {
        let b = emptyStateView.bounds
        let contentW = min(b.width, 320)
        let x = floor((b.width - contentW) / 2)
        let showsCircle = !emptyStateCircleView.isHidden
        // The app icon, or the 44 pt circle for a filtered state, leads the block.
        let iconSize: CGFloat = showsCircle ? QueueFilteredEmptyState.circleDiameter : 96
        let buttonH = QueuePanelMetrics.footerPillHeight
        let buttonW = max(96, addMediaButton.preferredWidth())
        let showsButton = !addMediaButton.isHidden
        // icon, 16 gap, title, 4 gap, detail, 14 gap, button
        let titleH: CGFloat = 20
        let detailH: CGFloat = 34
        let totalH = iconSize + 16 + titleH + 4 + detailH + (showsButton ? 14 + buttonH : 0)
        var y = floor((b.height + totalH) / 2)

        y -= iconSize
        let iconFrame = NSRect(x: floor((b.width - iconSize) / 2), y: y, width: iconSize, height: iconSize)
        if showsCircle {
            emptyStateCircleView.frame = iconFrame
            let glyphSide = QueueFilteredEmptyState.glyphSize
            emptyStateGlyphView.frame = NSRect(x: iconFrame.midX - glyphSide / 2, y: iconFrame.midY - glyphSide / 2,
                                               width: glyphSide, height: glyphSide)
            emptyStateLogoView.frame = .zero
        } else {
            emptyStateLogoView.frame = iconFrame
            emptyStateCircleView.frame = .zero
            emptyStateGlyphView.frame = .zero
        }
        y -= 16 + titleH
        emptyStateLabel.frame = NSRect(x: x, y: y, width: contentW, height: titleH)
        y -= 4 + detailH
        emptyStateDetailLabel.frame = NSRect(x: x, y: y, width: contentW, height: detailH)
        if showsButton {
            y -= 14 + buttonH
            addMediaButton.frame = NSRect(x: x + floor((contentW - buttonW) / 2), y: y, width: buttonW, height: buttonH)
        } else {
            addMediaButton.frame = .zero
        }
    }

    @objc private func scrollContentDidResize() {
        // Vertical scrolling and vertical-scroller toggles both mutate the clip view.
        // Schedule (do not run inline) so that the synchronous notification chain
        // produced by tile()/setFrame writes cannot recurse on the same call stack.
        scheduleColumnLayout(reason: "clip-geometry-change")
        updateScrollHistoryState()
    }

    private func updateScrollHistoryState() {
        guard currentDisplayIndex >= 0 else { return }
        guard let itemRow = visibleRow(forDisplayIndex: currentDisplayIndex), itemRow > 0 else { return }
        let sectionRow = itemRow - 1
        let sectionRect = tableView.rect(ofRow: sectionRow)
        let clipOriginY = scrollView.contentView.bounds.origin.y
        if clipOriginY < sectionRect.minY - 5 {
            userIsReviewingHistory = true
        }
    }

    @objc private func scrollDidEndLive() {
        guard userIsReviewingHistory else { return }
        guard currentDisplayIndex >= 0,
              let itemRow = visibleRow(forDisplayIndex: currentDisplayIndex),
              itemRow > 0 else { return }
        let sectionRow = itemRow - 1
        let sectionRect = tableView.rect(ofRow: sectionRow)
        let clipOriginY = scrollView.contentView.bounds.origin.y
        // User scrolled back down to or past NOW PLAYING — snap to it
        if clipOriginY >= sectionRect.minY - 10 {
            let targetY = max(0, sectionRect.minY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            userIsReviewingHistory = false
        }
    }

    /// Coalesces column layout requests from frame/bounds notifications.
    /// Multiple notifications fired synchronously while layout is active are merged
    /// into a single deferred run on the next main-run-loop turn.
    private func scheduleColumnLayout(reason: String, force: Bool = false) {
        if let existing = pendingColumnLayout {
            pendingColumnLayout = (reason, existing.force || force)
            return
        }
        pendingColumnLayout = (reason, force)
        if isApplyingColumnLayout { return }  // defer block will drain it
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let req = self.pendingColumnLayout else { return }
            self.pendingColumnLayout = nil
            self.applyColumnLayout(reason: req.reason, forceDiagnostic: req.force)
        }
    }

    /// Single source of truth for queue column layout.
    ///
    /// The one card column absorbs the clip-view width so no horizontal overflow
    /// can occur. Duration and size remain card subtitle metadata, not columns.
    private func applyColumnLayout(reason: String, forceDiagnostic: Bool) {
        // ── Reentrancy guard ───────────────────────────────────────────────
        // Any synchronous notification that fires while we are tiling (from
        // tile()/setFrame writes) calls scheduleColumnLayout, which sets
        // pendingColumnLayout and returns. But if applyColumnLayout is called
        // DIRECTLY (from layout() or update())
        // while already active, capture the request here and let the defer
        // block drain it on the next main-loop turn.
        if isApplyingColumnLayout {
            pendingColumnLayout = (reason, forceDiagnostic || pendingColumnLayout?.force == true)
            return
        }
        isApplyingColumnLayout = true
        defer {
            isApplyingColumnLayout = false
            if let pending = pendingColumnLayout {
                pendingColumnLayout = nil
                DispatchQueue.main.async { [weak self] in
                    self?.applyColumnLayout(reason: pending.reason,
                                            forceDiagnostic: pending.force)
                }
            }
        }

        guard let nameCol = tableView.tableColumn(withIdentifier: Self.colName) else { return }

        // Check for clip x drift and log — do NOT scroll/reflect here.
        // LockedHorizontalClipView already enforces x = 0; mutation from inside
        // this method is what created the P43.6 recursive notification storm.
        lockHorizontalClipOrigin(reason: reason)

        let clipView = scrollView.contentView

        let rawAvailable = max(0, floor(clipView.bounds.width))
        let available = rawAvailable

        // Transient startup state: clip has not yet received real dimensions from
        // AppKit (this is normal — the view may enter the hierarchy before the first
        // real layout pass). Assigning zero-width columns would produce corrupt
        // geometry. Log the skip and schedule one coalesced retry so the layout
        // converges once the clip is meaningful. Natural frame/bounds notifications
        // (from layout(), scrollContentDidResize) will also trigger re-entry.
        // Guard the retry on reason to avoid an infinite spin if the clip stays zero.
        if rawAvailable <= 1 || available <= 1 {
            logQueueCoordinateState(reason: reason, outcome: "skipped-zero-clip", force: false)
            if reason != "zero-clip-retry" {
                scheduleColumnLayout(reason: "zero-clip-retry")
            }
            return
        }

        let nameWidth = max(0, floor(available))

        // ── Idempotent writes ──────────────────────────────────────────────
        // Only write a column width when it has actually changed (≥ 0.5 pt).
        //
        // The table frame is corrected here too: origin.x must converge to 0 and
        // size.width must converge to the available clip width. P43.7 removed all
        // frame writes to break the recursive notification storm; P43.8 restores
        // only this minimal, guarded, idempotent correction.
        //
        // Constraints:
        //   * Only tableView.frame is touched (documentView is tableView; we do
        //     not write scrollView.documentView.frame separately).
        //   * tableView.headerView.frame is NEVER written here — tile() owns it.
        //   * No scroll(to:), scrollToPoint, or reflectScrolledClipView calls.
        //   * The whole block runs under `isApplyingColumnLayout`, so any
        //     synchronous frame-change notification fired by these writes is
        //     coalesced into pendingColumnLayout by scheduleColumnLayout and
        //     never re-enters the call stack.
        //   * tile() is only called when at least one width OR the table frame
        //     was actually changed — avoiding unnecessary notification traffic.
        let tol: CGFloat = 0.5
        var widthsChanged = false
        if abs(nameCol.width - nameWidth) > tol { nameCol.width = nameWidth; widthsChanged = true }

        let currentFrame = tableView.frame
        let needsOriginFix = abs(currentFrame.origin.x) > tol
        let needsWidthFix  = abs(currentFrame.size.width - available) > tol
        var frameChanged = false
        if needsOriginFix || needsWidthFix {
            var target = currentFrame
            target.origin.x = 0
            target.size.width = available
            tableView.frame = target
            frameChanged = true
        }

        if widthsChanged || frameChanged { tableView.tile() }

        let outcome: String
        switch (widthsChanged, frameChanged) {
        case (true,  true):  outcome = "applied-widths-and-frame"
        case (true,  false): outcome = "applied-widths"
        case (false, true):  outcome = "applied-frame"
        case (false, false): outcome = "skipped"
        }
        logQueueCoordinateState(reason: reason, outcome: outcome, force: forceDiagnostic)
    }

    /// Checks for horizontal clip x drift and logs a warning if detected.
    /// Does NOT call scroll(to:) or reflectScrolledClipView — those calls drive
    /// NSClipView._immediateScrollToPoint, posting a bounds-change notification
    /// that is the root cause of the P43.6 recursive layout storm.
    /// LockedHorizontalClipView.constrainBoundsRect / setBoundsOrigin already
    /// enforce origin.x = 0; if drift appears here a bypass occurred externally.
    private func lockHorizontalClipOrigin(reason: String) {
        let x = scrollView.contentView.bounds.origin.x
        guard abs(x) > 0.5 else { return }
        let msg = "clipX drift reason=\(reason) x=\(String(format: "%.3f", x))"
        DebugConsoleController.log(level: .warning, category: "queue-geometry", message: msg)
        NSLog("dwb queueGeometryWarning %@", msg)
    }

    private func visibleColumnWidthSum() -> CGFloat {
        tableView.tableColumns.reduce(CGFloat(0)) { partial, column in
            column.isHidden ? partial : partial + column.width
        }
    }

    private func columnRectDescription(_ identifier: NSUserInterfaceItemIdentifier) -> String {
        guard let column = tableView.tableColumn(withIdentifier: identifier) else { return "missing" }
        guard !column.isHidden else { return "hidden" }
        let index = tableView.column(withIdentifier: identifier)
        guard index >= 0 else { return "missing-index" }
        return NSStringFromRect(tableView.rect(ofColumn: index))
    }

    private func logQueueCoordinateState(reason: String, outcome: String, force: Bool) {
        if !force {
            let now = Date()
            if let last = lastCoordinateDiagnosticTimeByReason[reason],
               now.timeIntervalSince(last) < 0.75 {
                return
            }
            lastCoordinateDiagnosticTimeByReason[reason] = now
        }

        let clip       = scrollView.contentView
        let clipInPanel = clip.convert(clip.bounds, to: self)
        let visibleClipRight = clipInPanel.maxX
        let docWidth   = scrollView.documentView?.frame.width ?? 0
        let tableFrame = tableView.frame
        let visibleSum = visibleColumnWidthSum()
        let footerRight = totalDurationRightEdgeInPanel()
        // Diagnostic-only: `guarded` is always 1 here (we only log from inside
        // applyColumnLayout); kept as an explicit field so future readers can
        // grep for it next to outcome.
        let guarded = isApplyingColumnLayout ? 1 : 0
        let message = String(format:
            "reason=%@ outcome=%@ guarded=%d clipX=%.3f clipW=%.3f docW=%.3f" +
            " tableX=%.3f tableW=%.3f visibleColumnSum=%.3f" +
            " fileRect=%@" +
            " footerRight=%.3f visibleClipRight=%.3f",
            reason, outcome, guarded,
            clip.bounds.origin.x, clip.bounds.width, docWidth,
            tableFrame.origin.x, tableFrame.size.width, visibleSum,
            columnRectDescription(Self.colName),
            footerRight, visibleClipRight)
        DebugConsoleController.log("queue-geometry", message)
        NSLog("dwb queueGeometry %@", message)

        #if DEBUG
        // Gate geometry invariant checks on clipReady. When the clip has not yet
        // received real AppKit dimensions (e.g. during initial view setup), the
        // values are meaningless and must not trigger diagnostic stops.
        // Warnings remain useful once the clip is ready; they are warning-only —
        // assertionFailure has been removed to allow DEBUG launches to proceed
        // normally through transient startup geometry states.
        let clipReady = window != nil
            && bounds.width > 1
            && bounds.height > 1
            && clip.bounds.width > 1
        if clipReady {
            let tolerance: CGFloat = 0.5
            var warnings: [String] = []
            if abs(clip.bounds.origin.x) > tolerance {
                warnings.append(String(format: "clip.bounds.origin.x %.3f exceeds tolerance",
                                       clip.bounds.origin.x))
            }
            if docWidth > clip.bounds.width + tolerance {
                warnings.append(String(format: "documentView.frame.width %.3f exceeds clip %.3f",
                                       docWidth, clip.bounds.width))
            }
            if tableFrame.size.width > clip.bounds.width + tolerance {
                warnings.append(String(format: "tableView.frame.width %.3f exceeds clip %.3f",
                                       tableFrame.size.width, clip.bounds.width))
            }
            if visibleSum > clip.bounds.width + tolerance {
                warnings.append(String(format: "visible column sum %.3f exceeds clip %.3f",
                                       visibleSum, clip.bounds.width))
            }
            if footerRight > visibleClipRight + tolerance {
                warnings.append(String(format: "footer right edge %.3f exceeds visible clip right %.3f",
                                       footerRight, visibleClipRight))
            }
            if !warnings.isEmpty {
                let warningText = "reason=\(reason) outcome=\(outcome) " + warnings.joined(separator: "; ")
                DebugConsoleController.log(level: .warning, category: "queue-geometry",
                                           message: warningText)
                NSLog("dwb queueGeometryWarning %@", warningText)
                // Warning-only: no assertionFailure until layout has stabilized
                // across startup, queue reload, and resize sequences.
            }
        }
        #endif
    }

    private func centeredY(height: CGFloat, in containerHeight: CGFloat) -> CGFloat {
        floor((containerHeight - height) / 2)
    }

    /// Right edge for the bottom-bar total-duration label, in QueuePageView
    /// coordinates.
    ///
    /// Geometry is derived from the real `NSTableView.rect(ofColumn:)` converted
    /// into this view's coordinate space — no manual panel-coordinate construction
    /// from `scrollView.frame.minX - clipView.bounds.origin.x`. Preference order is
    /// The result is clamped to a footer-safe right limit: visibleClipRight minus
    /// `totalDurationTrailingInset` (72 pt). This intentionally moves the label
    /// left so it sits under the metadata columns rather than hugging the panel
    /// edge. The inset is a footer-only boundary — it does not affect column,
    /// header, or row geometry. The label is additionally bounded by the card
    /// column text rect.
    private func totalDurationRightEdgeInPanel() -> CGFloat {
        let clipView = scrollView.contentView
        let clipInPanel = clipView.convert(clipView.bounds, to: self)
        let visibleClipRight = clipInPanel.maxX
        // Footer-safe right boundary: keeps the total label visually inside the
        // metadata area rather than at the raw panel edge.
        let footerRightLimit = max(0, visibleClipRight - Self.totalDurationTrailingInset)

        let columnIndex = tableView.column(withIdentifier: Self.colName)
        guard columnIndex >= 0 else { return footerRightLimit }
        let columnRectInTable = tableView.rect(ofColumn: columnIndex)
        guard columnRectInTable.width > 0 else { return footerRightLimit }
        let columnRectInPanel = tableView.convert(columnRectInTable, to: self)
        let textRect = QueueColumnGeometry.textRect(in: columnRectInPanel,
                                                    textHeight: columnRectInPanel.height)
        return min(textRect.maxX, footerRightLimit)
    }

    private func selectedRowsOrCurrentRowDescending() -> [Int] {
        let selected = tableView.selectedRowIndexes
        if !selected.isEmpty {
            pendingSelectionAnchorRow = selected.min()
            let projection = visibleRows.map { row -> QueueDisplayProjection.Row in
                if let displayIndex = row.displayIndex { return .item(displayIndex: displayIndex) }
                return .section("")
            }
            return QueueDisplayProjection.displayIndices(forVisibleRows: selected, in: projection).sorted(by: >)
        }
        return currentDisplayIndexIfVisible().map { [$0] } ?? []
    }

    private var currentSearchQuery: String {
        searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleItem(at row: Int) -> Item? {
        guard row >= 0, row < visibleRows.count else { return nil }
        return visibleRows[row].item
    }

    private func displayIndex(forVisibleRow row: Int) -> Int? {
        guard row >= 0, row < visibleRows.count else { return nil }
        return visibleRows[row].displayIndex
    }

    private func visibleRow(forDisplayIndex displayIndex: Int) -> Int? {
        visibleRows.firstIndex { $0.displayIndex == displayIndex }
    }

    private func currentDisplayIndexIfVisible() -> Int? {
        guard currentDisplayIndex >= 0,
              visibleRow(forDisplayIndex: currentDisplayIndex) != nil else { return nil }
        return currentDisplayIndex
    }

    private func applySearchFilter(preservingSelectedURLs selectedURLs: Set<URL>) {
        let query = currentSearchQuery
        let bookmarkedPaths = BookmarkStore.shared.bookmarkedPaths()
        let pairs = QueueDisplayProjection.filteredPairs(
            from: items,
            displayName: { $0.displayName },
            urlPath: { $0.url.standardizedFileURL.path },
            query: query,
            bookmarkedPaths: bookmarkedPaths,
            bookmarkFilterEnabled: bookmarkFilterEnabled
        )
        visibleToDisplayIndices = pairs.map(\.0)
        visibleItems = pairs.map(\.1)
        rebuildVisibleRows(from: pairs)
        allowsManualReorder = QueueDisplayProjection.allowsManualReorder(
            isManualSort: currentSortMode == .manual,
            query: query,
            bookmarkFilterEnabled: bookmarkFilterEnabled
        )
        updateTotalDurationLabel()
        tableView.reloadData()
        if !selectedURLs.isEmpty {
            let remapped = IndexSet(visibleRows.indices.filter { row in
                guard let item = visibleRows[row].item else { return false }
                return selectedURLs.contains(item.url)
            })
            if !remapped.isEmpty {
                tableView.selectRowIndexes(remapped, byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
        }
        if tableView.selectedRowIndexes.isEmpty, let anchor = pendingSelectionAnchorRow {
            let projection = visibleRows.map { row -> QueueDisplayProjection.Row in
                if let displayIndex = row.displayIndex { return .item(displayIndex: displayIndex) }
                return .section("")
            }
            if let row = QueueDisplayProjection.nearestSelectableRow(anchor: anchor, in: projection) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            }
        }
        pendingSelectionAnchorRow = nil
        updateEmptyState()
        needsLayout = true
    }

    private func rebuildVisibleRows(from pairs: [(Int, Item)]) {
        let filterActive = !currentSearchQuery.isEmpty || bookmarkFilterEnabled
        let itemByDisplayIndex = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })
        visibleRows = QueueDisplayProjection.sectionedRows(
            displayIndices: pairs.map(\.0),
            currentDisplayIndex: currentDisplayIndex,
            filterActive: filterActive
        ).compactMap { row in
            switch row {
            case .section(let title):
                return .section(title)
            case .item(let displayIndex):
                guard let item = itemByDisplayIndex[displayIndex] else { return nil }
                return .item(displayIndex: displayIndex, item: item)
            }
        }
    }

    private func updateTotalDurationLabel() {
        totalDurationLabel.stringValue = QueueFooterText.total(
            duration: totalDurationText,
            itemCount: items.count,
            visibleCount: visibleItems.count,
            isFiltered: !currentSearchQuery.isEmpty || bookmarkFilterEnabled)
        totalDurationLabel.setAccessibilityValue(totalDurationLabel.stringValue)
    }

    private func updateEmptyState() {
        if items.isEmpty {
            emptyStateLabel.stringValue = "No media in queue"
            emptyStateDetailLabel.stringValue = "Add files or folders to build the queue."
            emptyStateAction = .addMedia
            addMediaButton.labelText = "Add Media"
            addMediaButton.setAccessibilityLabel("Add Media")
            addMediaButton.setAccessibilityHelp("Choose local files or folders to add to the queue")
            addMediaButton.setAccessibilityIdentifier("queue.empty.addMedia")
            addMediaButton.isHidden = false
            showsFilteredEmptyStateGlyph(nil)
            emptyStateView.isHidden = false
            scrollView.isHidden = true
            emptyStateView.setAccessibilityLabel("Queue empty")
            emptyStateView.setAccessibilityValue(emptyStateDetailLabel.stringValue)
        } else if visibleItems.isEmpty {
            let filtered = QueueFilteredEmptyState.make(query: currentSearchQuery,
                                                        bookmarkFilterEnabled: bookmarkFilterEnabled)
            emptyStateLabel.stringValue = filtered.title
            switch filtered {
            case .noBookmarks:
                emptyStateDetailLabel.stringValue = "Show all queued files or bookmark an item from the playback bar."
            case .noMatches:
                emptyStateDetailLabel.stringValue = "Clear the current search and bookmark filter to show the queue."
            }
            showsFilteredEmptyStateGlyph(filtered.symbolName)
            emptyStateAction = .clearFilters
            addMediaButton.labelText = filtered.actionTitle
            addMediaButton.setAccessibilityLabel(addMediaButton.labelText)
            addMediaButton.setAccessibilityHelp("Clear Queue search and bookmark filters")
            addMediaButton.setAccessibilityIdentifier("queue.empty.clearFilters")
            addMediaButton.isHidden = false
            emptyStateView.isHidden = false
            scrollView.isHidden = true
            emptyStateView.setAccessibilityLabel(emptyStateLabel.stringValue)
            emptyStateView.setAccessibilityValue(emptyStateDetailLabel.stringValue)
        } else {
            emptyStateView.isHidden = true
            scrollView.isHidden = false
        }
        layoutEmptyState()
    }

    /// Shows the neutral circle with `symbolName`, or the app icon when nil.
    private func showsFilteredEmptyStateGlyph(_ symbolName: String?) {
        let filtered = symbolName != nil
        emptyStateLogoView.isHidden = filtered
        emptyStateCircleView.isHidden = !filtered
        emptyStateGlyphView.isHidden = !filtered
        if let symbolName {
            let configuration = NSImage.SymbolConfiguration(pointSize: QueueFilteredEmptyState.glyphSize, weight: .regular)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            emptyStateGlyphView.image = image?.withSymbolConfiguration(configuration) ?? image
        }
        applyEmptyStateCircleAppearance()
    }

    private func applyEmptyStateCircleAppearance() {
        emptyStateCircleView.layer?.backgroundColor = DWBColor.surfaceElevated.cgColor
        emptyStateCircleView.layer?.borderColor = DWBAppearance.shared.border.cgColor
        emptyStateGlyphView.contentTintColor = DWBAppearance.shared.textTertiary
    }

    // MARK: - Increase Contrast / appearance

    @objc private func appearanceDidChange() {
        applyAppearance()
    }

    /// Re-applies every token that depends on Increase Contrast. Runs at setup and
    /// whenever the shared appearance changes, so the panel updates live.
    private func applyAppearance() {
        let appearance = DWBAppearance.shared
        searchSortPill.layer?.borderColor = appearance.border.cgColor
        searchSortDivider.layer?.backgroundColor = appearance.border.cgColor
        topSeparator.layer?.backgroundColor = appearance.border.cgColor
        bottomSeparator.layer?.backgroundColor = appearance.border.cgColor
        sharedEdgeDivider.layer?.backgroundColor = appearance.border.cgColor
        footerClearSeparator.layer?.backgroundColor = appearance.border.cgColor
        sortTitleView.textColor = appearance.textSecondary
        sortChevronView.color = appearance.textSecondary
        searchIconView.color = appearance.textTertiary
        closeButton.contentTintColor = appearance.textSecondary
        totalDurationLabel.textColor = appearance.textSecondary
        emptyStateDetailLabel.textColor = appearance.textTertiary
        applyEmptyStateCircleAppearance()
        applySearchPlaceholder()
        updateBookmarkFilterButton()
        searchSortPill.needsDisplay = true
        tableView.reloadData()
    }

    private func applySearchPlaceholder() {
        searchField.placeholderAttributedString = NSAttributedString(string: "Search queue", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: DWBAppearance.shared.textTertiary
        ])
    }

    /// Saturation 0.6 on the empty-state icon, as in the design system.
    private static func fadedIconFilters() -> [CIFilter] {
        guard let filter = CIFilter(name: "CIColorControls") else { return [] }
        filter.setValue(0.6, forKey: kCIInputSaturationKey)
        return [filter]
    }

    // MARK: - Actions

    @objc private func closeTapped()  { delegate?.queuePageDidRequestClose(self) }

    @objc private func addMediaTapped() {
        delegate?.queuePageDidRequestAddMedia(self)
    }

    @objc private func emptyStateActionTapped() {
        switch emptyStateAction {
        case .addMedia:
            addMediaTapped()
        case .clearFilters:
            searchField.stringValue = ""
            bookmarkFilterEnabled = false
            updateBookmarkFilterButton()
            applySearchFilter(preservingSelectedURLs: [])
            window?.makeFirstResponder(searchField)
        }
    }

    @objc private func bookmarkFilterTapped() {
        bookmarkFilterEnabled.toggle()
        updateBookmarkFilterButton()
        let selectedURLs = Set(tableView.selectedRowIndexes.compactMap { row -> URL? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.url
        })
        applySearchFilter(preservingSelectedURLs: selectedURLs)
    }

    @objc private func rowClicked() {
        // Single-click selection is handled by NSTableView so Command-click,
        // Shift-click, and keyboard selection extension keep normal AppKit behavior.
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard let displayIndex = displayIndex(forVisibleRow: row) else { return }
        delegate?.queuePage(self, didSelectDisplayIndex: displayIndex)
    }

    @objc private func deleteTapped() {
        let rows = selectedRowsOrCurrentRowDescending()
        guard !rows.isEmpty else { return }
        if rows.count == 1 {
            delegate?.queuePage(self, didRequestDeleteAt: rows[0])
        } else {
            delegate?.queuePage(self, didRequestDeleteRows: rows)
        }
    }

    @objc private func customPrefixTapped() {
        delegate?.queuePage(self, didRequestCustomPrefixRenameAt: prefixTargetDisplayIndices())
    }

    @objc private func customPrefixSecondaryTapped() {
        delegate?.queuePage(self, didRequestSecondaryCustomPrefixRenameAt: prefixTargetDisplayIndices())
    }

    @objc private func handleCustomPrefixValueChanged() {
        needsLayout = true
    }

    /// Filenames the footer's prefix chips act on: the selected rows, or the current
    /// item when nothing is selected (the same targets `customPrefixTapped` uses).
    private func markerTargetNames() -> [String] {
        let selected = tableView.selectedRowIndexes
        if selected.isEmpty {
            guard let index = currentDisplayIndexIfVisible(),
                  items.indices.contains(index) else { return [] }
            return [items[index].displayName]
        }
        return selected.compactMap { visibleItem(at: $0)?.displayName }
    }

    /// Display indices of the selected rows, ascending.
    func selectedDisplayIndices() -> [Int] {
        tableView.selectedRowIndexes.sorted().compactMap { displayIndex(forVisibleRow: $0) }
    }

    /// What a prefix action targets: the selected rows, or the current item when none is selected.
    func prefixTargetDisplayIndices() -> [Int] {
        if tableView.selectedRowIndexes.isEmpty {
            return currentDisplayIndexIfVisible().map { [$0] } ?? []
        }
        return selectedDisplayIndices()
    }

    private func primaryChipState() -> QueueMarkerChipState {
        .make(kind: .primary,
              prefix: SettingsWindowController.customPrefixValue(),
              targetNames: markerTargetNames(),
              queueHasItems: !items.isEmpty)
    }

    /// nil when the secondary prefix equals the primary: it is not offered as a separate action.
    private func secondaryChipState() -> QueueMarkerChipState? {
        let primary = SettingsWindowController.customPrefixValue()
        let secondary = SettingsWindowController.customPrefixSecondaryValue()
        guard QueueMarkerChipState.secondaryIsShown(primary: primary, secondary: secondary) else { return nil }
        return .make(kind: .secondary,
                     prefix: secondary,
                     targetNames: markerTargetNames(),
                     queueHasItems: !items.isEmpty)
    }

    @objc private func undoMarkerRenameTapped() {
        guard isUndoAvailable else { return }
        delegate?.queuePageDidRequestUndoMarkerRename(self)
    }

    @objc private func rescanTapped() {
        delegate?.queuePageDidRequestRescan(self)
    }

    @objc private func removeAllTapped() {
        delegate?.queuePageDidRequestRemoveAll(self)
    }

    @objc private func sortModeChanged() {
        guard !isUpdatingSortControl,
              let mode = QueueSortMode(rawValue: sortPopUpButton.selectedTag()) else { return }
        delegate?.queuePage(self, didChangeSortMode: mode)
    }

    @objc private func searchFieldChanged() {
        let selectedURLs = Set(tableView.selectedRowIndexes.compactMap { row -> URL? in
            guard let item = visibleItem(at: row) else { return nil }
            return item.url
        })
        applySearchFilter(preservingSelectedURLs: selectedURLs)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchFieldChanged()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchSortPill.isSearchFocused = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchSortPill.isSearchFocused = false
    }

    private func updateBookmarkFilterButton() {
        let symbol = bookmarkFilterEnabled ? "bookmark.fill" : "bookmark"
        bookmarkFilterButton.symbolName = symbol
        bookmarkFilterButton.contentTintColor = bookmarkFilterEnabled ? PlayerTheme.current.accentText : DWBAppearance.shared.textSecondary
        bookmarkFilterButton.state = bookmarkFilterEnabled ? .on : .off
        bookmarkFilterButton.refreshAppearance()
        bookmarkFilterButton.toolTip = bookmarkFilterEnabled ? "Showing bookmarked queue files" : "Show bookmarked queue files"
        bookmarkFilterButton.setAccessibilityValue(bookmarkFilterEnabled ? "Showing bookmarked files" : "Showing all queue files")
    }

    private func updateSortControlSelection() {
        isUpdatingSortControl = true
        sortPopUpButton.selectItem(withTag: currentSortMode.rawValue)
        sortTitleView.stringValue = sortPopUpButton.titleOfSelectedItem ?? "Sort: \(currentSortMode.title)"
        isUpdatingSortControl = false
    }

    private func updateHeaderSortIndicators() {
        tableView.tableColumn(withIdentifier: Self.colName)?.headerCell.stringValue = headerTitle("File",
                                                                                                  ascendingMode: .filenameAscending,
                                                                                                  descendingMode: .filenameDescending)
        tableView.headerView?.needsDisplay = true
    }

    private func headerTitle(_ base: String,
                             ascendingMode: QueueSortMode,
                             descendingMode: QueueSortMode) -> String {
        if currentSortMode == ascendingMode {
            return "\(base) ^"
        }
        if currentSortMode == descendingMode {
            return "\(base) v"
        }
        return base
    }

    private func nextHeaderSortMode(for column: NSTableColumn) -> QueueSortMode? {
        switch column.identifier {
        case Self.colName:
            return currentSortMode == .filenameAscending ? .filenameDescending : .filenameAscending
        default:
            return nil
        }
    }

    private func makeContextMenu(for row: Int) -> NSMenu {
        guard let targetDisplayIndex = displayIndex(forVisibleRow: row) else { return NSMenu() }
        let menu = NSMenu()
        addContextItem("Play", action: #selector(contextPlay(_:)), row: row, to: menu)
        menu.addItem(.separator())

        // Play Next — disabled when nothing is playing or when the target IS the current item.
        let playNextEnabled = currentDisplayIndex >= 0 && targetDisplayIndex != currentDisplayIndex
        addContextItem("Play Next", action: #selector(contextPlayNext(_:)), row: row, to: menu,
                       enabled: playNextEnabled)

        menu.addItem(.separator())
        addContextItem("Reveal in Finder", action: #selector(contextReveal(_:)), row: row, to: menu)
        addContextItem("Rename...", action: #selector(contextRename(_:)), row: row, to: menu)
        menu.addItem(.separator())
        addContextItem("Remove from Queue", action: #selector(contextDelete(_:)), row: row, to: menu)
        return menu
    }

    private func addContextItem(_ title: String, action: Selector, row: Int, to menu: NSMenu,
                                 enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = displayIndex(forVisibleRow: row)
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func contextPlay(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didSelectDisplayIndex: row)
    }

    @objc private func contextPlayNext(_ sender: NSMenuItem) {
        guard let displayIdx = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestPlayNextAt: displayIdx)
    }

    @objc private func contextReveal(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestRevealAt: row)
    }

    @objc private func contextRename(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestRenameAt: row)
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        delegate?.queuePage(self, didRequestDeleteAt: row)
    }
}

final class QueuePageTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    /// Called when Delete or Backspace is pressed with one or more selected rows.
    /// Indices are sorted descending so the caller can remove them safely.
    var deleteRowsHandler: (([Int]) -> Void)?
    /// Called for an unmodified `N`, `M` or `R` while the table is focused.
    var prefixKeyHandler: ((PrefixKeyRouting.Action) -> Void)?
    /// Called when a drag over the table exits or ends, so the drop line can go.
    var onDragEnded: (() -> Void)?

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        onDragEnded?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragEnded?()
    }

    // Select on mouseDown so the highlight appears immediately, before drag detection
    // and before the action fires on mouseUp. Without this, selectionHighlightStyle = .none
    // means the system never automatically selects, and the visual update can lag or miss.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .shift, .option]).isEmpty {
            let point = convert(event.locationInWindow, from: nil)
            let r = row(at: point)
            if r >= 0 { selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuProvider?(row)
    }

    override func keyDown(with event: NSEvent) {
        if QueueDisplayProjection.isDeletionKeyCode(event.keyCode) {
            let rows = selectedRowIndexes
            guard !rows.isEmpty else { return }
            deleteRowsHandler?(rows.sorted(by: >))
            return
        }
        let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if let action = PrefixKeyRouting.action(forCharacters: event.charactersIgnoringModifiers,
                                                hasModifiers: hasModifiers,
                                                isEditingText: window?.firstResponder is NSText) {
            if !event.isARepeat { prefixKeyHandler?(action) }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - NSTableViewDataSource

extension QueuePageView: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRows.count }

    // MARK: Drag source — write dragged row index to pasteboard

    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard allowsManualReorder else { return nil }
        guard let displayIndex = displayIndex(forVisibleRow: row) else { return nil }
        // This view preserves the pre-existing single-row reorder model. Multi-row
        // selection is supported, but multi-row drag reorder is intentionally not.
        guard tableView.selectedRowIndexes.count <= 1 else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(displayIndex), forType: Self.draggedRowType)
        return item
    }

    /// The dragged row stays in the list at 0.4 alpha while its image follows the pointer.
    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint,
                   forRowIndexes rowIndexes: IndexSet) {
        guard let row = rowIndexes.first else { return }
        draggedVisibleRow = row
        tableView.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = QueueDropIndicatorMetrics.draggedRowAlpha
    }

    func tableView(_ tableView: NSTableView,
                   draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint,
                   operation: NSDragOperation) {
        endDragFeedback()
    }

    // MARK: Drop target — accept only same-table moves, inserting between rows

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard allowsManualReorder else {
            hideDropIndicator()
            return []
        }
        // Only accept drops that insert between rows (not on top of a row)
        guard dropOperation == .above else {
            tableView.setDropRow(row, dropOperation: .above)
            showDropIndicator(aboveVisibleRow: row)
            return .move
        }
        showDropIndicator(aboveVisibleRow: row)
        return .move
    }

    // MARK: Drop line (9.7)

    /// Puts the drop line in the gap above `row` (below the last row when `row` is the end).
    private func showDropIndicator(aboveVisibleRow row: Int) {
        guard visibleRows.count > 0 else { return hideDropIndicator() }
        let boundaryY = row < visibleRows.count
            ? tableView.rect(ofRow: row).minY
            : tableView.rect(ofRow: visibleRows.count - 1).maxY
        let pill = QueuePanelMetrics.pillRect(inRowBounds: NSRect(x: 0, y: 0, width: tableView.bounds.width,
                                                                 height: QueuePanelMetrics.tableRowHeight),
                                              visibleWidth: scrollView.contentView.bounds.width)
        let inset = QueueDropIndicatorMetrics.sideInset
        let diameter = QueueDropIndicatorMetrics.ringDiameter
        dropIndicator.frame = NSRect(x: pill.minX + inset,
                                     y: boundaryY - diameter / 2,
                                     width: max(0, pill.width - inset * 2),
                                     height: diameter)
        dropIndicator.isHidden = false
        dropIndicator.needsDisplay = true
    }

    private func hideDropIndicator() {
        dropIndicator.isHidden = true
    }

    /// Ends the drop line and the dragged row's dimming.
    fileprivate func endDragFeedback() {
        hideDropIndicator()
        if let row = draggedVisibleRow {
            tableView.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = 1
        }
        draggedVisibleRow = nil
        for row in 0..<visibleRows.count {
            tableView.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = 1
        }
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        hideDropIndicator()
        guard allowsManualReorder else { return false }
        guard let str = info.draggingPasteboard.string(forType: Self.draggedRowType),
              let from = Int(str) else { return false }
        let to = displayInsertionIndex(forVisibleRow: row)
        // No-op: drop on same position or the position immediately below the source
        guard from != to, from != to - 1 else { return false }
        delegate?.queuePage(self, didReorderFromIndex: from, toIndex: to)
        return true
    }

    private func displayInsertionIndex(forVisibleRow row: Int) -> Int {
        guard row < visibleRows.count else { return items.count }
        if let displayIndex = displayIndex(forVisibleRow: row) {
            return displayIndex
        }
        var nextRow = row + 1
        while nextRow < visibleRows.count {
            if let displayIndex = displayIndex(forVisibleRow: nextRow) {
                return displayIndex
            }
            nextRow += 1
        }
        return items.count
    }
}

// MARK: - NSTableViewDelegate

extension QueuePageView: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let mode = nextHeaderSortMode(for: tableColumn) else { return }
        delegate?.queuePage(self, didChangeSortMode: mode)
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < visibleRows.count, let colID = tableColumn?.identifier else { return nil }
        guard colID == Self.colName else { return nil }

        if case let .section(title) = visibleRows[row] {
            let reuseID = NSUserInterfaceItemIdentifier("qpSectionCell")
            var cell = tableView.makeView(withIdentifier: reuseID, owner: nil) as? QueuePageSectionCell
            if cell == nil {
                cell = QueuePageSectionCell(reuseID: reuseID)
            }
            cell?.configure(title: title)
            return cell
        }

        guard let item = visibleItem(at: row), let displayIndex = displayIndex(forVisibleRow: row) else { return nil }
        let isCurrent = displayIndex == currentDisplayIndex

        let reuseID = NSUserInterfaceItemIdentifier("qpMediaCell")
        var cell = tableView.makeView(withIdentifier: reuseID, owner: nil) as? QueuePageCell
        if cell == nil {
            cell = QueuePageCell(reuseID: reuseID)
        }

        cell?.configure(item: item, isCurrent: isCurrent, query: currentSearchQuery)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < visibleRows.count else { return QueuePanelMetrics.tableRowHeight }
        if case .section = visibleRows[row] { return QueuePanelMetrics.sectionRowHeight }
        return QueuePanelMetrics.tableRowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // The footer's prefix chips read "applied" from the selected filenames.
        needsLayout = true
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < visibleRows.count else { return false }
        if case .section = visibleRows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = QueuePageRowView()
        guard row >= 0, row < visibleRows.count else { return rv }
        if case .section = visibleRows[row] {
            rv.isSection = true
        } else if let displayIndex = displayIndex(forVisibleRow: row) {
            rv.isCurrent = displayIndex == currentDisplayIndex
            if let item = visibleItem(at: row) {
                rv.configureAccessibility(item: item, displayIndex: displayIndex)
            }
        } else {
            rv.isCurrent = false
        }
        rv.isBookmarked = visibleItem(at: row)?.isBookmarked ?? false
        rv.isFailed = visibleItem(at: row)?.isFailed ?? false
        return rv
    }
}

// MARK: - QueuePageCell

fileprivate struct QueueColumnGeometry {
    let identifier: NSUserInterfaceItemIdentifier
    let title: String
    let alignment: NSTextAlignment
    let columnRect: NSRect
    let textRect: NSRect

    static func textRect(in rect: NSRect, textHeight: CGFloat) -> NSRect {
        NSRect(x: rect.minX + QueuePageView.cellLeadingPadding,
               y: rect.minY + floor((rect.height - textHeight) / 2),
               width: max(0, rect.width - QueuePageView.cellLeadingPadding - QueuePageView.cellTrailingPadding),
               height: textHeight)
    }
}

private final class QueuePageSectionCell: NSView {
    private let label = NSTextField(labelWithString: "")

    init(reuseID: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = reuseID
        label.drawsBackground = false
        label.isEditable = false
        label.isBordered = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let host = superview ?? self
        let x = convert(NSPoint(x: QueuePanelMetrics.listLeadingInset + 4, y: 0), from: host).x
        label.frame = NSRect(x: x, y: 4, width: max(0, bounds.width - x - 8), height: 14)
    }

    func configure(title: String) {
        switch QueueSectionLabelStyle.style(forTitle: title) {
        case .capsLabel:
            // 10 pt bold caps, +4% tracking.
            label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: DWBAppearance.shared.textTertiary,
                .kern: QueuePanelMetrics.sectionLabelKern
            ])
        case .emptyNote:
            label.attributedStringValue = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: DWBAppearance.shared.textTertiary
            ])
        }
        setAccessibilityLabel(title)
    }
}

private final class QueuePageCell: NSView {

    private let leadingGlyph = NSImageView()
    private let titleLabel = QueueNameLabel()
    private let tagView = QueuePlayNextTagView()
    private let metadataLabel = NSTextField(labelWithString: "")
    private let bookmarkIndicator = NSImageView()
    private var showsBookmark = false
    private var showsTag = false

    init(reuseID: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = reuseID
        setAccessibilityElement(false)

        leadingGlyph.imageScaling = .scaleProportionallyDown
        leadingGlyph.setAccessibilityElement(false)
        addSubview(leadingGlyph)

        addSubview(titleLabel)
        tagView.isHidden = true
        addSubview(tagView)

        metadataLabel.drawsBackground = false
        metadataLabel.isEditable = false
        metadataLabel.isBordered = false
        metadataLabel.lineBreakMode = .byTruncatingMiddle
        metadataLabel.setAccessibilityElement(false)
        addSubview(metadataLabel)

        bookmarkIndicator.imageScaling = .scaleProportionallyDown
        bookmarkIndicator.setAccessibilityElement(false)
        addSubview(bookmarkIndicator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // The table places a cell a few points inside its row view, so the pill is worked
        // out in row coordinates and converted into this cell.
        let host = superview ?? self
        let pill = convert(QueuePanelMetrics.pillRect(inRowBounds: host.bounds,
                                                      visibleWidth: host.visibleRect.width),
                           from: host)
        let slotX = pill.minX + QueuePanelMetrics.rowLeadingPadding
        let slotW = QueuePanelMetrics.glyphSlotWidth
        leadingGlyph.frame = NSRect(x: slotX, y: floor(bounds.midY - 7), width: slotW, height: 14)

        let bookmarkSize = QueuePanelMetrics.bookmarkGlyphSize + 2
        bookmarkIndicator.frame = NSRect(x: pill.maxX - QueuePanelMetrics.rowTrailingPadding - bookmarkSize,
                                         y: floor(bounds.midY - bookmarkSize / 2),
                                         width: bookmarkSize, height: bookmarkSize)

        let textX = slotX + slotW + QueuePanelMetrics.rowContentGap
        let textRight = showsBookmark
            ? bookmarkIndicator.frame.minX - QueuePanelMetrics.rowContentGap
            : pill.maxX - QueuePanelMetrics.rowTrailingPadding
        let textW = max(0, textRight - textX)
        let titleH = titleLabel.lineHeight
        let metaH = ceil(metadataLabel.intrinsicContentSize.height)
        let blockH = titleH + QueuePanelMetrics.titleMetaGap + metaH
        let blockBottom = floor(bounds.midY - blockH / 2)
        metadataLabel.frame = NSRect(x: textX, y: blockBottom, width: textW, height: metaH)
        let titleY = blockBottom + metaH + QueuePanelMetrics.titleMetaGap
        if showsTag {
            // The Play Next tag follows the name; a long name shortens to leave it room.
            let tagW = tagView.preferredWidth
            let gap = QueuePanelMetrics.titleTagGap
            let nameW = min(titleLabel.naturalWidth, max(0, textW - tagW - gap))
            titleLabel.frame = NSRect(x: textX, y: titleY, width: nameW, height: titleH)
            tagView.frame = NSRect(x: textX + nameW + gap,
                                   y: titleY + floor((titleH - DWBMetrics.playNextTag) / 2),
                                   width: tagW, height: DWBMetrics.playNextTag)
        } else {
            titleLabel.frame = NSRect(x: textX, y: titleY, width: textW, height: titleH)
            tagView.frame = .zero
        }
    }

    func configure(item: QueuePageView.Item, isCurrent: Bool, query: String) {
        let appearance = DWBAppearance.shared
        let look = QueueRowAppearance.make(isCurrent: isCurrent,
                                           isSelected: false,
                                           isHovering: false,
                                           isFailed: item.isFailed,
                                           isBookmarked: item.isBookmarked)
        let titleColor = look.filenameIsDimmed ? appearance.textSecondary : DWBColor.textPrimary
        let text = item.displayName
        titleLabel.attributedText = QueueNameStyle.attributedName(
            text,
            fontSize: 12.5,
            weight: look.filenameWeight,
            color: titleColor,
            primaryPrefix: SettingsWindowController.customPrefixValue(),
            secondaryPrefix: SettingsWindowController.customPrefixSecondaryValue(),
            query: query
        )

        // The Play Next tag is hidden on the current row.
        if let position = item.playNextPosition, !isCurrent {
            tagView.configure(position: position)
            tagView.isHidden = false
            showsTag = true
        } else {
            tagView.isHidden = true
            showsTag = false
        }

        metadataLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        metadataLabel.textColor = look.metadataIsError ? DWBColor.errorText : appearance.textTertiary
        metadataLabel.stringValue = "\(item.duration)  •  \(item.fileSize)"

        switch look.leadingGlyph {
        case .playing:
            leadingGlyph.image = Self.symbol("play.fill", size: QueuePanelMetrics.playGlyphSize,
                                             weight: .bold, description: "Now playing")
            leadingGlyph.contentTintColor = PlayerTheme.current.accentText
            leadingGlyph.isHidden = false
        case .failed:
            leadingGlyph.image = Self.symbol("exclamationmark.triangle.fill", size: QueuePanelMetrics.failedGlyphSize,
                                             weight: .medium, description: "Failed")
            leadingGlyph.contentTintColor = DWBColor.errorText
            leadingGlyph.isHidden = false
        case .none:
            leadingGlyph.image = nil
            leadingGlyph.isHidden = true
        }

        showsBookmark = look.showsBookmark
        if look.showsBookmark {
            bookmarkIndicator.image = Self.symbol("bookmark.fill", size: QueuePanelMetrics.bookmarkGlyphSize,
                                                  weight: .medium, description: "Bookmarked")
            bookmarkIndicator.contentTintColor = appearance.textSecondary
            bookmarkIndicator.isHidden = false
        } else {
            bookmarkIndicator.image = nil
            bookmarkIndicator.isHidden = true
        }
        needsLayout = true
        var states: [String] = [isCurrent ? "now playing" : "queued"]
        if item.isFailed { states.append("failed to play") }
        if let position = item.playNextPosition, !isCurrent { states.append("play next \(position)") }
        setAccessibilityLabel(item.isBookmarked ? "\(text), bookmarked" : text)
        setAccessibilityValue(states.joined(separator: ", "))
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, description: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        return image?.withSymbolConfiguration(configuration) ?? image
    }
}

// MARK: - QueuePageRowView

private final class QueuePageRowView: NSTableRowView {

    var isSection: Bool = false
    var isCurrent: Bool = false
    var isBookmarked: Bool = false
    var isFailed: Bool = false

    private static let minimumDrawableDimension: CGFloat = 1
    private var accessibilityItemLabel = "Queue item"
    private var isHovering = false
    private var isPressing = false
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        needsDisplay = true
        super.mouseDown(with: event)
        isPressing = false
        needsDisplay = true
    }

    // Ensure the row redraws whenever isSelected changes. With selectionHighlightStyle = .none,
    // AppKit may not reliably call setNeedsDisplay on the row view after a programmatic
    // selectRowIndexes call, so we force it here.
    override var isSelected: Bool {
        get { super.isSelected }
        set {
            if super.isSelected != newValue {
                super.isSelected = newValue
                needsDisplay = true
                updateAccessibilityState()
            }
        }
    }

    func configureAccessibility(item: QueuePageView.Item, displayIndex: Int) {
        accessibilityItemLabel = item.displayName
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        setAccessibilityIdentifier("queue.row.\(displayIndex)")
        setAccessibilityLabel(item.displayName)
        isBookmarked = item.isBookmarked
        isFailed = item.isFailed
        updateAccessibilityState(duration: item.duration, fileSize: item.fileSize)
    }

    private func updateAccessibilityState(duration: String? = nil, fileSize: String? = nil) {
        guard !isSection else { return }
        var states: [String] = []
        if isCurrent { states.append("now playing") }
        if isFailed { states.append("failed to play") }
        if isBookmarked { states.append("bookmarked") }
        if isSelected { states.append("selected") }
        if let duration { states.append("duration \(duration)") }
        if let fileSize { states.append("size \(fileSize)") }
        setAccessibilityLabel(accessibilityItemLabel)
        setAccessibilityValue(states.isEmpty ? "queued" : states.joined(separator: ", "))
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard !isSection else { return }
        let pill = QueuePanelMetrics.pillRect(inRowBounds: bounds, visibleWidth: visibleRect.width)
        guard Self.isDrawable(pill),
              let path = Self.roundedPath(for: pill, radius: DWBMetrics.radiusRow) else { return }

        let look = QueueRowAppearance.make(isCurrent: isCurrent,
                                           isSelected: isSelected,
                                           isHovering: isHovering,
                                           isFailed: isFailed,
                                           isBookmarked: isBookmarked)
        switch look.fill {
        case .none:            break
        case .accentTint:      DWBAppearance.shared.accentTint.setFill(); path.fill()
        case .overlaySelected: DWBColor.overlaySelected.setFill(); path.fill()
        case .overlayHover:    DWBColor.overlayHover.setFill(); path.fill()
        }
        if isPressing {
            DWBColor.overlayPressed.setFill()
            path.fill()
        }

        let edge: NSColor
        switch look.edge {
        case .gridLine:    edge = DWBColor.gridLine
        case .accentFill:  edge = PlayerTheme.current.accentFill
        case .borderStrong: edge = DWBColor.borderStrong
        }
        let edgePath = Self.roundedPath(for: pill.insetBy(dx: 0.5, dy: 0.5), radius: DWBMetrics.radiusRow - 0.5) ?? path
        edge.setStroke()
        edgePath.lineWidth = 1
        edgePath.stroke()

        if look.showsCurrentBar {
            PlayerTheme.current.accentFill.setFill()
            let barRect = NSRect(x: pill.minX + QueuePanelMetrics.currentBarLeading,
                                 y: pill.minY + QueuePanelMetrics.currentBarVerticalInset,
                                 width: QueuePanelMetrics.currentBarWidth,
                                 height: pill.height - QueuePanelMetrics.currentBarVerticalInset * 2)
            Self.roundedPath(for: barRect, radius: QueuePanelMetrics.currentBarRadius)?.fill()
        }
    }

    // Use drawBackground for selection so we don't get the system blue.
    override var isEmphasized: Bool { get { false } set {} }

    private static func roundedPath(for rect: NSRect, radius: CGFloat) -> NSBezierPath? {
        guard isDrawable(rect),
              radius.isFinite else { return nil }
        let safeRadius = min(max(0, radius), rect.width / 2, rect.height / 2)
        guard safeRadius.isFinite else { return nil }
        return NSBezierPath(roundedRect: rect, xRadius: safeRadius, yRadius: safeRadius)
    }

    private static func isDrawable(_ rect: NSRect) -> Bool {
        guard !rect.isNull,
              !rect.isInfinite,
              !rect.isEmpty,
              rect.width >= minimumDrawableDimension,
              rect.height >= minimumDrawableDimension else { return false }
        return rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
    }
}

// MARK: - Native Queue Table Header

private final class QueueSearchSortPillView: NSView {
    weak var searchField: NSSearchField?
    var searchFocusRect: NSRect = .zero
    var isSearchFocused = false {
        didSet { needsDisplay = true }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if searchFocusRect.contains(point),
           let searchField = searchField,
           !searchField.isHidden,
           searchField.frame.width > 0 {
            window?.makeFirstResponder(searchField)
            return
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSearchFocused, !searchFocusRect.isEmpty else { return }
        let focusRect = searchFocusRect.insetBy(dx: 1.5, dy: 1.5)
        DWBAppearance.shared.focusRingColor.setStroke()
        let path = NSBezierPath(roundedRect: focusRect, xRadius: 10.5, yRadius: 10.5)
        path.lineWidth = DWBAppearance.shared.focusRingWidth
        path.stroke()
    }
}

private final class QueuePassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class QueueSearchFieldCell: NSSearchFieldCell {
    private let textLeading: CGFloat = 0
    private let textTrailing: CGFloat = 6
    private let cancelButtonSize: CGFloat = 14
    private let cancelButtonTrailing: CGFloat = 3
    private let cancelButtonGap: CGFloat = 4

    override init(textCell string: String) {
        super.init(textCell: string)
        // NSCell.init(textCell:) creates a non-editable label cell; restore editability.
        isEditable = true
        usesSingleLineMode = true
        isScrollable = true
        lineBreakMode = .byClipping
    }

    required init(coder: NSCoder) { fatalError() }

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        .zero
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        guard !stringValue.isEmpty else { return .zero }
        return NSRect(x: rect.maxX - cancelButtonTrailing - cancelButtonSize,
                      y: rect.minY + floor((rect.height - cancelButtonSize) / 2),
                      width: cancelButtonSize,
                      height: cancelButtonSize)
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        let cancelRect = cancelButtonRect(forBounds: rect)
        let rightEdge = cancelRect.isEmpty ? rect.maxX : cancelRect.minX - cancelButtonGap
        let x = rect.minX + textLeading
        let width = max(0, rightEdge - x - textTrailing)
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        return NSRect(x: x,
                      y: rect.minY + floor((rect.height - textHeight) / 2),
                      width: width,
                      height: textHeight)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        searchTextRect(forBounds: rect)
    }

    override func edit(withFrame rect: NSRect,
                       in controlView: NSView,
                       editor textObj: NSText,
                       delegate: Any?,
                       event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect),
                   in: controlView,
                   editor: textObj,
                   delegate: delegate,
                   event: event)
    }

    override func select(withFrame rect: NSRect,
                         in controlView: NSView,
                         editor textObj: NSText,
                         delegate: Any?,
                         start selStart: Int,
                         length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect),
                     in: controlView,
                     editor: textObj,
                     delegate: delegate,
                     start: selStart,
                     length: selLength)
    }
}

private final class QueueTransparentPopUpButtonCell: NSPopUpButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {}
}

private final class QueueHeaderSymbolButton: NSButton {
    private let symbolView = QueueCenteredSymbolView()
    private var isHovering = false
    private var isPressing = false
    private var trackingAreaReference: NSTrackingArea?

    var symbolName: String? {
        get { symbolView.symbolName }
        set { symbolView.symbolName = newValue }
    }

    var symbolPointSize: CGFloat {
        get { symbolView.pointSize }
        set { symbolView.pointSize = newValue }
    }

    var symbolWeight: NSFont.Weight {
        get { symbolView.weight }
        set { symbolView.weight = newValue }
    }

    override var contentTintColor: NSColor? {
        didSet {
            symbolView.color = contentTintColor ?? DWBColor.textSecondary
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        image = nil
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        symbolView.color = contentTintColor ?? DWBColor.textSecondary
        addSubview(symbolView)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        symbolView.frame = bounds
        layer?.cornerRadius = DWBMetrics.radiusControl
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressing = true
        updateAppearance()
        super.mouseDown(with: event)
        isPressing = false
        updateAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateAppearance()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        updateAppearance()
        return resigned
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    func refreshAppearance() {
        updateAppearance()
    }

    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 2, dy: 2) }

    override func drawFocusRingMask() {
        NSBezierPath(ovalIn: focusRingMaskBounds).fill()
    }

    private func updateAppearance() {
        let focused = window?.firstResponder === self
        let selected = state == .on
        let appearance = DWBAppearance.shared
        let fill: NSColor
        if isPressing {
            fill = DWBColor.overlayPressed
        } else if selected {
            fill = PlayerTheme.current.accentTintStrong
        } else if isHovering {
            fill = DWBColor.overlayHover
        } else {
            fill = .clear
        }
        layer?.backgroundColor = fill.cgColor
        let border: NSColor
        if focused {
            border = appearance.focusRingColor
        } else if selected {
            border = PlayerTheme.current.accentFill
        } else if isHovering {
            border = appearance.border
        } else {
            border = .clear
        }
        layer?.borderColor = border.cgColor
        layer?.borderWidth = focused ? appearance.focusRingWidth : 1
        alphaValue = isEnabled ? 1.0 : DWBMetrics.disabledAlpha
    }
}

private final class QueueCenteredSymbolView: NSView {
    var symbolName: String? {
        didSet { rebuildImage() }
    }
    var pointSize: CGFloat = 13 {
        didSet { rebuildImage() }
    }
    var weight: NSFont.Weight = .regular {
        didSet { rebuildImage() }
    }
    var color: NSColor = DWBColor.textPrimary {
        didSet { needsDisplay = true }
    }
    private var symbolImage: NSImage?

    func configure(symbolName: String,
                   pointSize: CGFloat,
                   weight: NSFont.Weight,
                   color: NSColor,
                   accessibilityDescription: String?) {
        self.pointSize = pointSize
        self.weight = weight
        self.color = color
        self.symbolName = symbolName
        setAccessibilityElement(accessibilityDescription != nil)
        if let accessibilityDescription {
            setAccessibilityLabel(accessibilityDescription)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let symbolImage else { return }
        let alignmentRect = symbolImage.alignmentRect
        let drawOrigin = NSPoint(x: bounds.midX - alignmentRect.midX,
                                 y: bounds.midY - alignmentRect.midY)
        let drawRect = NSRect(origin: drawOrigin, size: symbolImage.size)
        symbolImage.draw(in: drawRect,
                         from: .zero,
                         operation: .sourceOver,
                         fraction: 1.0,
                         respectFlipped: true,
                         hints: nil)
        color.setFill()
        drawRect.fill(using: .sourceAtop)
    }

    private func rebuildImage() {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            symbolImage = nil
            needsDisplay = true
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        symbolImage = image.withSymbolConfiguration(configuration) ?? image
        symbolImage?.isTemplate = true
        needsDisplay = true
    }
}

private final class QueueCenteredTextView: NSView {
    var stringValue: String = "" {
        didSet { needsDisplay = true }
    }
    var font: NSFont = .systemFont(ofSize: 10.5, weight: .regular) {
        didSet { needsDisplay = true }
    }
    var textColor: NSColor = DWBColor.textPrimary {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let textRect = NSRect(x: 0,
                              y: bounds.minY + floor((bounds.height - textHeight) / 2),
                              width: bounds.width,
                              height: textHeight)
        (stringValue as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

private final class LockedHorizontalClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        rect.origin.x = 0
        return rect
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }
}

private final class QueueColumnHeaderCell: NSTableHeaderCell {
    private let textAlignment: NSTextAlignment

    init(title: String, alignment: NSTextAlignment) {
        self.textAlignment = alignment
        super.init(textCell: title)
        self.stringValue = title
        self.alignment = alignment
    }

    required init(coder: NSCoder) { fatalError() }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        paragraph.alignment = textAlignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: DWBAppearance.shared.textTertiary,
            .paragraphStyle: paragraph
        ]
        let labelRect = QueueColumnGeometry.textRect(in: cellFrame, textHeight: 11)
        stringValue.draw(in: labelRect, withAttributes: attrs)

        DWBColor.gridLine.setFill()
        NSRect(x: floor(cellFrame.maxX), y: cellFrame.minY + 3, width: 1, height: max(0, cellFrame.height - 6)).fill()
    }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        draw(withFrame: cellFrame, in: controlView)
    }
}
