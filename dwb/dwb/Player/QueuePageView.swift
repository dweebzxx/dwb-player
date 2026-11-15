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
    private let headerRule       = QueueRuleView(kind: .rule)
    private let searchFieldView  = QueueSearchFieldView(frame: .zero)
    private var searchField: QueueSearchField { searchFieldView.searchField }
    private let sortButton       = QueueHeaderButton(frame: .zero)
    private let bookmarkFilterButton = QueueHeaderButton(frame: .zero)
    private let closeButton      = QueueHeaderButton(frame: .zero)
    let scrollView               = NSScrollView()
    let tableView                = QueuePageTableView()
    private let emptyStateView   = NSView()
    private let emptyStateLogoView = NSImageView()
    private let emptyStateCircleView = NSView()
    private let emptyStateGlyphView = NSImageView()
    private let emptyStateLabel  = NSTextField(labelWithString: "No media in queue")
    private let emptyStateDetailLabel = NSTextField(wrappingLabelWithString: "Add files or folders to build the queue.")
    private let addMediaButton   = QueueEmptyActionButton(style: .outlinePill)
    private let filteredActionButton = QueueEmptyActionButton(style: .filteredAction)
    private let footerView       = NSView()
    private let footerTopRule    = QueueRuleView(kind: .rule)
    private let footerActionRule = QueueRuleView(kind: .rule)
    private let removeCell       = QueueFooterCellButton(frame: .zero)
    private let primaryCell      = QueueFooterCellButton(frame: .zero)
    private let secondaryCell    = QueueFooterCellButton(frame: .zero)
    private let undoCell         = QueueFooterCellButton(frame: .zero)
    private let actionDividers   = (0..<3).map { _ in QueueRuleView(kind: .divider) }
    private let rescanCell       = QueueFooterCellButton(frame: .zero)
    private let clearCell        = QueueFooterCellButton(frame: .zero)
    private let totalLabel       = NSTextField(labelWithString: "")
    private let totalDividers    = (0..<2).map { _ in QueueRuleView(kind: .divider) }
    private enum EmptyStateAction {
        case addMedia
        case clearFilters
    }
    private var emptyStateAction: EmptyStateAction = .addMedia
    private let dropIndicator = QueueDropIndicatorView(frame: .zero)
    /// The visible row being dragged, shown at 0.4 alpha until the drag ends.
    private var draggedVisibleRow: Int?

    // Column identifiers
    private static let colName = NSUserInterfaceItemIdentifier("name")

    // Padding constants used by QueueColumnGeometry (the table's one layout column).
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
        let appearance = DWBAppearance.shared

        // ── Header (§10.2): one 52 pt row, no title ──────────────────────────
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(headerView)

        searchField.placeholderString = "Search queue"
        applySearchPlaceholder()
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.toolTip = "Search queue filenames"
        searchField.setAccessibilityLabel("Search queue")
        searchField.setAccessibilityIdentifier("queue.header.search")
        headerView.addSubview(searchFieldView)

        searchFieldView.clearButton.toolTip = "Clear search text"
        searchFieldView.clearButton.setAccessibilityLabel("Clear search text")
        searchFieldView.clearButton.setAccessibilityIdentifier("queue.header.clearSearch")
        searchFieldView.clearButton.target = self
        searchFieldView.clearButton.action = #selector(clearSearchTapped)

        sortButton.symbolName = "arrow.up.arrow.down"
        sortButton.symbolPointSize = 13
        sortButton.symbolWeight = .regular
        sortButton.target = self
        sortButton.action = #selector(sortButtonTapped)
        sortButton.setAccessibilityLabel("Queue sort order")
        sortButton.setAccessibilityHelp("Choose how queue items are sorted")
        sortButton.setAccessibilityIdentifier("queue.header.sort")
        headerView.addSubview(sortButton)
        updateSortControlSelection()

        bookmarkFilterButton.symbolPointSize = 15
        bookmarkFilterButton.target = self
        bookmarkFilterButton.action = #selector(bookmarkFilterTapped)
        bookmarkFilterButton.setAccessibilityLabel("Bookmark filter")
        bookmarkFilterButton.setAccessibilityHelp("Show only bookmarked queue files")
        bookmarkFilterButton.setAccessibilityIdentifier("queue.header.bookmarkFilter")
        headerView.addSubview(bookmarkFilterButton)
        updateBookmarkFilterButton()

        closeButton.symbolName = "xmark"
        closeButton.symbolPointSize = 15
        closeButton.toolTip = "Close Queue"
        closeButton.setAccessibilityLabel("Close Queue")
        closeButton.setAccessibilityHelp("Close the Queue Page")
        closeButton.setAccessibilityIdentifier("queue.header.close")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        headerView.addSubview(closeButton)
        headerView.addSubview(headerRule)

        // ── Table ─────────────────────────────────────────────────────────
        // Rows own their name, duration and size; the table intentionally has one layout
        // column and ignores legacy column-visibility defaults.
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
        // Heights vary (flat 44, playing 52, section 28); `heightOfRow` answers per row.
        tableView.rowHeight    = DWBMetrics.queueFlatRowHeight
        // Rows are positioned by `QueueRowGeometry`; the automatic (inset) table style
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
        // The drop line (§10.4) replaces the system's insertion indicator.
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
        // List padding (§10.1): 0 top, 12 bottom. The 6 pt sides are inside the row geometry.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: DWBMetrics.queueListBottomPadding, right: 0)
        addSubview(scrollView)

        emptyStateView.wantsLayer = true
        emptyStateView.layer?.backgroundColor = NSColor.clear.cgColor
        emptyStateView.setAccessibilityRole(.group)
        emptyStateView.setAccessibilityIdentifier("queue.emptyState")
        addSubview(emptyStateView)

        // The faded app icon is the only imagery; the title stays the loudest thing (§10.6).
        emptyStateLogoView.image = NSApp.applicationIconImage
        emptyStateLogoView.imageScaling = .scaleProportionallyUpOrDown
        emptyStateLogoView.alphaValue = DWBMetrics.queueEmptyIconAlpha
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
        emptyStateLabel.lineBreakMode = .byTruncatingTail
        emptyStateView.addSubview(emptyStateLabel)

        emptyStateDetailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        emptyStateDetailLabel.textColor = appearance.textTertiary
        emptyStateDetailLabel.alignment = .center
        emptyStateDetailLabel.drawsBackground = false
        emptyStateDetailLabel.isEditable = false
        emptyStateDetailLabel.isBordered = false
        emptyStateDetailLabel.isSelectable = false
        emptyStateDetailLabel.lineBreakMode = .byWordWrapping
        emptyStateView.addSubview(emptyStateDetailLabel)

        for button in [addMediaButton, filteredActionButton] {
            button.target = self
            button.action = #selector(emptyStateActionTapped)
            emptyStateView.addSubview(button)
        }
        addMediaButton.labelText = "Add Media"
        addMediaButton.toolTip = "Add media to the queue"
        addMediaButton.setAccessibilityLabel("Add Media")
        addMediaButton.setAccessibilityHelp("Choose local files or folders to add to the queue")
        addMediaButton.setAccessibilityIdentifier("queue.empty.addMedia")
        filteredActionButton.isHidden = true

        // Re-run the column layout when the clip view's width changes — this happens
        // when the vertical scroller toggles, which would otherwise leave the row extending
        // past the visible area on the right edge.
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

        // ── Footer (§10.5): two rows at every width ───────────────────────────
        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = DWBColor.canvas.cgColor
        addSubview(footerView)
        footerView.addSubview(footerTopRule)
        footerView.addSubview(footerActionRule)

        removeCell.symbolName = "minus.circle"
        removeCell.toolTip = "Remove from Queue"
        removeCell.setAccessibilityLabel("Remove from Queue")
        removeCell.setAccessibilityHelp("Remove the selected rows from the queue without deleting files")
        removeCell.setAccessibilityIdentifier("queue.footer.removeSelected")
        removeCell.target = self
        removeCell.action = #selector(deleteTapped)

        // The marker sections show the user's own prefix text in the marker colors.
        for cell in [primaryCell, secondaryCell] {
            cell.labelFont = QueueFooterCellButton.markerFont
        }
        primaryCell.setAccessibilityIdentifier("queue.footer.primaryPrefix")
        primaryCell.target = self
        primaryCell.action = #selector(customPrefixTapped)
        secondaryCell.setAccessibilityIdentifier("queue.footer.secondaryPrefix")
        secondaryCell.target = self
        secondaryCell.action = #selector(customPrefixSecondaryTapped)

        undoCell.symbolName = "arrow.uturn.backward"
        undoCell.toolTip = "Undo the last prefix change (⌘Z)"
        undoCell.setAccessibilityLabel("Undo last prefix change")
        undoCell.setAccessibilityHelp("Restores the filenames changed by the most recent prefix change in this window")
        undoCell.setAccessibilityIdentifier("queue.footer.undoMarkerRename")
        undoCell.target = self
        undoCell.action = #selector(undoMarkerRenameTapped)

        for cell in [removeCell, primaryCell, secondaryCell, undoCell] { footerView.addSubview(cell) }
        for divider in actionDividers { footerView.addSubview(divider) }

        rescanCell.symbolName = "arrow.clockwise"
        rescanCell.labelText = "Rescan"
        rescanCell.toolTip = "Rescan Folder — refresh the queue from current folder contents on disk"
        rescanCell.setAccessibilityLabel("Rescan Folder")
        rescanCell.setAccessibilityHelp("Refresh the queue from current folder contents on disk")
        rescanCell.setAccessibilityIdentifier("queue.footer.rescan")
        rescanCell.target = self
        rescanCell.action = #selector(rescanTapped)

        clearCell.symbolName = "trash"
        clearCell.labelText = "Clear queue"
        clearCell.toolTip = "Clear Queue"
        clearCell.setAccessibilityLabel("Clear Queue")
        clearCell.setAccessibilityHelp("Remove every item from this window's queue without deleting files")
        clearCell.setAccessibilityIdentifier("queue.footer.clear")
        clearCell.target = self
        clearCell.action = #selector(removeAllTapped)

        totalLabel.font = QueueFooterTotal.font
        totalLabel.textColor = appearance.textSecondary
        totalLabel.alignment = .center
        totalLabel.lineBreakMode = .byTruncatingTail
        totalLabel.usesSingleLineMode = true
        totalLabel.setAccessibilityLabel("Total queue duration")
        totalLabel.setAccessibilityIdentifier("queue.footer.totalDuration")
        for view in [rescanCell, clearCell, totalLabel] { footerView.addSubview(view) }
        for divider in totalDividers { footerView.addSubview(divider) }

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

        // A one-point structural edge keeps the video and Queue Page visually
        // connected without changing either region's geometry or hit testing.
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

    // MARK: - Layout

    override func layout() {
        super.layout()
        let b = bounds
        let edge = QueuePanelLayout.edgeWidth
        let contentW = QueuePanelLayout.contentWidth(panelWidth: b.width)
        let headerH = QueuePanelMetrics.headerHeight
        let footerH = DWBMetrics.queueFooterHeight

        // Header: one row at every width (§10.2).
        headerView.frame = NSRect(x: edge, y: b.height - headerH, width: contentW, height: headerH)
        headerRule.frame = NSRect(x: 0, y: 0, width: contentW, height: QueueHeaderLayout.bottomRule)
        let header = QueueHeaderLayout.make(panelWidth: b.width,
                                            sortLabelWidth: QueueHeaderButton.labelWidth(currentSortMode.title))
        let outset = QueueSearchFieldView.outset
        searchFieldView.frame = header.search.insetBy(dx: -outset, dy: -outset)
        sortButton.frame = header.sort
        sortButton.label = header.isCompact ? nil : currentSortMode.title
        bookmarkFilterButton.frame = header.bookmark
        closeButton.frame = header.close

        // List: between the header and the fixed 78 pt footer.
        let listTop = b.height - headerH
        scrollView.frame = NSRect(x: edge, y: footerH, width: contentW, height: max(0, listTop - footerH))
        emptyStateView.frame = scrollView.frame
        layoutEmptyState()
        scrollView.layoutSubtreeIfNeeded()
        // Do not manually set tableView.headerView.frame here — tile() owns header width,
        // and writing it inside a layout pass posts a frame-change notification that fed
        // back into the P43.6 recursive layout storm.
        applyColumnLayout(reason: "layout", forceDiagnostic: false)

        // Footer: two rows at every width (§10.5).
        footerView.frame = NSRect(x: edge, y: 0, width: contentW, height: footerH)
        layoutFooter(panelWidth: b.width)

        sharedEdgeDivider.frame = NSRect(x: 0, y: 0, width: edge, height: b.height)
    }

    /// Places the footer's sections from `QueueFooterLayout` and refreshes their state.
    private func layoutFooter(panelWidth: CGFloat) {
        let plan = QueueFooterLayout.make(panelWidth: panelWidth)
        footerTopRule.frame = plan.topRule
        footerActionRule.frame = plan.actionRule
        let actionCells = [removeCell, primaryCell, secondaryCell, undoCell]
        for (cell, frame) in zip(actionCells, plan.actionCells) { cell.frame = frame }
        for (divider, frame) in zip(actionDividers, plan.actionDividers) { divider.frame = frame }
        rescanCell.frame = plan.rescan
        clearCell.frame = plan.clear
        for (divider, frame) in zip(totalDividers, plan.totalDividers) { divider.frame = frame }

        let hasItems = !items.isEmpty
        for cell in [removeCell, primaryCell, secondaryCell, undoCell, rescanCell, clearCell] {
            cell.isCompact = plan.isCompact
        }
        // Remove acts on the selection, or the playing file when nothing is selected.
        removeCell.isEnabled = !tableView.selectedRowIndexes.isEmpty || currentDisplayIndexIfVisible() != nil
        undoCell.isEnabled = isUndoAvailable
        rescanCell.isEnabled = hasItems
        clearCell.isEnabled = hasItems
        rescanCell.showsLabel = !plan.isCompact
        clearCell.showsLabel = !plan.isCompact

        applyMarkerState(primaryMarkerState(), to: primaryCell, color: PlayerTheme.current.markerPrimary)
        if let secondary = secondaryMarkerState() {
            secondaryCell.isHidden = false
            applyMarkerState(secondary, to: secondaryCell, color: PlayerTheme.current.markerSecondary)
        } else {
            // Equal prefixes: the secondary action is not offered, but its place in the grid stays.
            secondaryCell.isHidden = true
        }

        // The total shortens to fit the center cell minus 16; it never wraps or adds a row.
        let isFiltered = !currentSearchQuery.isEmpty || bookmarkFilterEnabled
        let candidates = QueueFooterTotal.candidates(durationText: totalDurationText, itemCount: items.count,
                                                     visibleCount: visibleItems.count, isFiltered: isFiltered)
        let text = QueueFooterTotal.fitted(candidates, availableWidth: plan.totalFitWidth,
                                           measure: QueueFooterTotal.measuredWidth)
        if totalLabel.stringValue != text { totalLabel.stringValue = text }
        let full = QueueFooterTotal.accessibilityText(durationText: totalDurationText, itemCount: items.count,
                                                      visibleCount: visibleItems.count, isFiltered: isFiltered)
        totalLabel.toolTip = full
        totalLabel.setAccessibilityValue(full)
        let textHeight = ceil(totalLabel.intrinsicContentSize.height)
        totalLabel.frame = NSRect(x: plan.total.minX + QueueFooterTotal.textInset,
                                  y: floor((plan.total.height - textHeight) / 2),
                                  width: max(0, plan.total.width - QueueFooterTotal.textInset * 2),
                                  height: textHeight)
    }

    private func applyMarkerState(_ state: QueueMarkerState, to cell: QueueFooterCellButton, color: NSColor) {
        cell.labelText = state.label
        cell.labelColor = state.isBlank ? DWBColor.textDisabled : color
        cell.mark = state.isEnabled ? state.mark : .none
        cell.isEnabled = state.isEnabled
        cell.toolTip = state.tooltip
        cell.setAccessibilityLabel(state.accessibilityLabel)
        cell.setAccessibilityValue(state.accessibilityValue)
    }

    /// The empty queue (§10.6): faded app icon · 10 · title · 6 · detail · 10 · Add Media pill. A
    /// filtered state: glyph circle · 13 · title · 13 · one button. Centered in the list area.
    private func layoutEmptyState() {
        let b = emptyStateView.bounds
        let padding = DWBMetrics.queueEmptyPadding
        let showsCircle = !emptyStateCircleView.isHidden
        let columnWidth = max(0, b.width - padding * 2)
        let titleHeight: CGFloat = 20
        let button: QueueEmptyActionButton = showsCircle ? filteredActionButton : addMediaButton
        let buttonSize = button.preferredSize()
        let buttonWidth = min(buttonSize.width, columnWidth)

        if showsCircle {
            let circle = QueueFilteredEmptyState.circleDiameter
            let gap = DWBMetrics.queueEmptyGap
            let totalHeight = circle + gap + titleHeight + gap + buttonSize.height
            var y = floor((b.height + totalHeight) / 2) - circle
            let circleFrame = NSRect(x: floor((b.width - circle) / 2), y: y, width: circle, height: circle)
            emptyStateCircleView.frame = circleFrame
            let glyph = QueueFilteredEmptyState.glyphSize
            emptyStateGlyphView.frame = NSRect(x: circleFrame.midX - glyph / 2, y: circleFrame.midY - glyph / 2,
                                               width: glyph, height: glyph)
            emptyStateLogoView.frame = .zero
            y -= gap + titleHeight
            emptyStateLabel.frame = NSRect(x: padding, y: y, width: columnWidth, height: titleHeight)
            emptyStateDetailLabel.frame = .zero
            y -= gap + buttonSize.height
            filteredActionButton.frame = NSRect(x: floor((b.width - buttonWidth) / 2), y: y,
                                                width: buttonWidth, height: buttonSize.height)
            addMediaButton.frame = .zero
        } else {
            let icon = DWBMetrics.queueEmptyIcon
            let detailWidth = min(columnWidth, DWBMetrics.queueEmptyDetailMaxWidth)
            let detailHeight = ceil(emptyStateDetailLabel.cell?
                .cellSize(forBounds: NSRect(x: 0, y: 0, width: detailWidth, height: .greatestFiniteMagnitude)).height ?? 14)
            let totalHeight = icon + DWBMetrics.queueEmptyIconToTitle + titleHeight + DWBMetrics.queueEmptyTitleToDetail
                + detailHeight + DWBMetrics.queueEmptyDetailToButton + buttonSize.height
            var y = floor((b.height + totalHeight) / 2) - icon
            emptyStateLogoView.frame = NSRect(x: floor((b.width - icon) / 2), y: y, width: icon, height: icon)
            emptyStateCircleView.frame = .zero
            emptyStateGlyphView.frame = .zero
            y -= DWBMetrics.queueEmptyIconToTitle + titleHeight
            emptyStateLabel.frame = NSRect(x: padding, y: y, width: columnWidth, height: titleHeight)
            y -= DWBMetrics.queueEmptyTitleToDetail + detailHeight
            emptyStateDetailLabel.frame = NSRect(x: floor((b.width - detailWidth) / 2), y: y,
                                                 width: detailWidth, height: detailHeight)
            y -= DWBMetrics.queueEmptyDetailToButton + buttonSize.height
            addMediaButton.frame = NSRect(x: floor((b.width - buttonWidth) / 2), y: y,
                                          width: buttonWidth, height: buttonSize.height)
            filteredActionButton.frame = .zero
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

    /// Right edge of the footer's total label, in QueuePageView coordinates. Diagnostic only:
    /// `logQueueCoordinateState` warns when it passes the visible clip's right edge.
    private func totalDurationRightEdgeInPanel() -> CGFloat {
        footerView.convert(totalLabel.frame, to: self).maxX
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

    /// The footer is rebuilt from the current counts in `layout()`.
    private func updateTotalDurationLabel() {
        needsLayout = true
    }

    private func updateEmptyState() {
        if items.isEmpty {
            emptyStateLabel.stringValue = "No media in queue"
            emptyStateDetailLabel.stringValue = "Add files or folders to build the queue."
            emptyStateDetailLabel.isHidden = false
            emptyStateAction = .addMedia
            addMediaButton.isHidden = false
            filteredActionButton.isHidden = true
            showsFilteredEmptyStateGlyph(nil)
            emptyStateView.isHidden = false
            scrollView.isHidden = true
            emptyStateView.setAccessibilityLabel("Queue empty")
            emptyStateView.setAccessibilityValue(emptyStateDetailLabel.stringValue)
        } else if visibleItems.isEmpty {
            let filtered = QueueFilteredEmptyState.make(query: currentSearchQuery,
                                                        bookmarkFilterEnabled: bookmarkFilterEnabled)
            emptyStateLabel.stringValue = filtered.title
            // §10.6: the filtered states have no detail line; the hint stays available to VoiceOver.
            let hint: String
            switch filtered {
            case .noBookmarks: hint = "Show all queued files or bookmark an item from the playback bar."
            case .noMatches: hint = "Clear the current search and bookmark filter to show the queue."
            }
            emptyStateDetailLabel.stringValue = hint
            emptyStateDetailLabel.isHidden = true
            showsFilteredEmptyStateGlyph(filtered.symbolName)
            emptyStateAction = .clearFilters
            addMediaButton.isHidden = true
            filteredActionButton.isHidden = false
            filteredActionButton.labelText = filtered.actionTitle
            filteredActionButton.setAccessibilityLabel(filtered.actionTitle)
            filteredActionButton.setAccessibilityHelp("Clear Queue search and bookmark filters")
            filteredActionButton.setAccessibilityIdentifier("queue.empty.clearFilters")
            emptyStateView.isHidden = false
            scrollView.isHidden = true
            emptyStateView.setAccessibilityLabel(emptyStateLabel.stringValue)
            emptyStateView.setAccessibilityValue(hint)
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
        // The 18 pt glyph is textSecondary in the circle (§10.6).
        emptyStateGlyphView.contentTintColor = DWBAppearance.shared.textSecondary
    }

    // MARK: - Increase Contrast / appearance

    @objc private func appearanceDidChange() {
        applyAppearance()
    }

    /// Re-applies every token that depends on Increase Contrast. Runs at setup and
    /// whenever the shared appearance changes, so the panel updates live.
    private func applyAppearance() {
        let appearance = DWBAppearance.shared
        sharedEdgeDivider.layer?.backgroundColor = appearance.border.cgColor
        totalLabel.textColor = appearance.textSecondary
        emptyStateDetailLabel.textColor = appearance.textTertiary
        applyEmptyStateCircleAppearance()
        applySearchPlaceholder()
        updateBookmarkFilterButton()
        searchFieldView.needsDisplay = true
        needsLayout = true
        tableView.reloadData()
    }

    private func applySearchPlaceholder() {
        searchField.placeholderAttributedString = NSAttributedString(string: "Search queue", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: DWBAppearance.shared.textTertiary
        ])
    }

    /// Saturation 0.6 on the empty-state icon (§10.6).
    private static func fadedIconFilters() -> [CIFilter] {
        guard let filter = CIFilter(name: "CIColorControls") else { return [] }
        filter.setValue(DWBMetrics.queueEmptyIconSaturation, forKey: kCIInputSaturationKey)
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
            updateClearSearchButton()
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

    /// Filenames the footer's prefix sections act on: the selected rows, or the current
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

    private func primaryMarkerState() -> QueueMarkerState {
        .make(kind: .primary,
              prefix: SettingsWindowController.customPrefixValue(),
              targetNames: markerTargetNames(),
              queueHasItems: !items.isEmpty)
    }

    /// nil when the secondary prefix equals the primary: it is not offered as a separate action.
    private func secondaryMarkerState() -> QueueMarkerState? {
        let primary = SettingsWindowController.customPrefixValue()
        let secondary = SettingsWindowController.customPrefixSecondaryValue()
        guard QueueMarkerState.secondaryIsShown(primary: primary, secondary: secondary) else { return nil }
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

    /// Opens the sort menu (§10.7): 190 wide, 4 pt below the button, the current order checked.
    @objc private func sortButtonTapped() {
        let menu = NSMenu()
        menu.minimumWidth = DWBMetrics.queueSortMenuWidth
        for mode in QueueSortMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(sortMenuItemChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = mode == currentSortMode ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: sortButton.frame.minX, y: sortButton.frame.minY - DWBMetrics.queueSortMenuOffset),
                   in: headerView)
    }

    @objc private func sortMenuItemChosen(_ sender: NSMenuItem) {
        guard let mode = QueueSortMode(rawValue: sender.tag) else { return }
        delegate?.queuePage(self, didChangeSortMode: mode)
    }

    @objc private func clearSearchTapped() {
        // Clears only the text; the bookmark filter and the filtered-empty-state behavior are unchanged.
        searchField.stringValue = ""
        searchFieldChanged()
        window?.makeFirstResponder(searchField)
    }

    private func updateClearSearchButton() {
        let hasText = !searchField.stringValue.isEmpty
        if searchFieldView.clearButton.isHidden == hasText {
            searchFieldView.clearButton.isHidden = !hasText
            searchFieldView.needsLayout = true
        }
    }

    @objc private func searchFieldChanged() {
        updateClearSearchButton()
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
        searchFieldView.setFocused(true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchFieldView.setFocused(false)
    }

    private func updateBookmarkFilterButton() {
        // On = bookmark.fill in accentText on accentTint; off = bookmark in textPrimary (§10.2).
        bookmarkFilterButton.symbolName = bookmarkFilterEnabled ? "bookmark.fill" : "bookmark"
        bookmarkFilterButton.isToggledOn = bookmarkFilterEnabled
        bookmarkFilterButton.toolTip = bookmarkFilterEnabled ? "Showing bookmarked queue files" : "Show bookmarked queue files"
        bookmarkFilterButton.setAccessibilityValue(bookmarkFilterEnabled ? "Showing bookmarked files" : "Showing all queue files")
    }

    /// The sort button's tooltip and VoiceOver value always name the active order, which is all a
    /// compact (icon-only) button has to show it.
    private func updateSortControlSelection() {
        let title = currentSortMode.title
        sortButton.toolTip = "Sort: \(title)"
        sortButton.setAccessibilityValue(title)
        sortButton.label = QueuePanelLayout.isCompact(panelWidth: bounds.width) ? nil : title
        sortButton.needsLayout = true
        needsLayout = true
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
        menu.minimumWidth = DWBMetrics.queueRowMenuWidth
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

    // MARK: Drop line (§10.4)

    /// Puts the 2 pt drop line on the boundary above `row` (below the last row when `row` is the end).
    private func showDropIndicator(aboveVisibleRow row: Int) {
        guard visibleRows.count > 0 else { return hideDropIndicator() }
        let boundaryY = row < visibleRows.count
            ? tableView.rect(ofRow: row).minY
            : tableView.rect(ofRow: visibleRows.count - 1).maxY
        let shape = QueueRowGeometry.shapeRect(inRowBounds: NSRect(x: 0, y: 0, width: tableView.bounds.width,
                                                                   height: DWBMetrics.queueFlatRowHeight),
                                               isCurrent: false,
                                               visibleWidth: scrollView.contentView.bounds.width)
        dropIndicator.frame = QueueDropIndicatorMetrics.frame(onBoundaryY: boundaryY, spanning: shape)
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

    /// Section blocks are 28, flat items 44, and the playing item 52 (48 card + 4 gap). A reload
    /// after any change of the current item, sort, filter or rename asks again for every row.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < visibleRows.count else { return DWBMetrics.queueFlatRowHeight }
        if case .section = visibleRows[row] { return DWBMetrics.queueSectionHeight }
        let isCurrent = displayIndex(forVisibleRow: row) == currentDisplayIndex
        return QueueRowGeometry.tableRowHeight(isCurrent: isCurrent)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // The footer's prefix sections read "applied" or "mixed" from the selected filenames.
        needsLayout = true
        // The row above a selected row hides its separator so nothing crosses the selected edge.
        let selected = tableView.selectedRowIndexes
        tableView.enumerateAvailableRowViews { rowView, row in
            (rowView as? QueuePageRowView)?.isRowBelowSelected = selected.contains(row + 1)
        }
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
        rv.isRowBelowSelected = tableView.selectedRowIndexes.contains(row + 1)
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
    private static let noteFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        let italic = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: italic, size: 11.5) ?? base
    }()

    init(reuseID: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = reuseID
        label.drawsBackground = false
        label.isEditable = false
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // The label sits 6 pt inside the list's own 6 pt side padding (§10.3).
        let host = superview ?? self
        let inset = DWBMetrics.queueListSidePadding + DWBMetrics.queueSectionInset
        let x = convert(NSPoint(x: inset, y: 0), from: host).x
        let height: CGFloat = 16
        label.frame = NSRect(x: x, y: floor((bounds.height - height) / 2), width: max(0, bounds.width - x - 8), height: height)
    }

    func configure(title: String) {
        let appearance = DWBAppearance.shared
        let text = QueueSectionLabelStyle.displayText(forTitle: title)
        switch QueueSectionLabelStyle.style(forTitle: title) {
        case .label:
            // 10 pt semibold textTertiary, sentence case, no tracking.
            label.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: appearance.textTertiary
            ])
        case .note:
            label.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: Self.noteFont,
                .foregroundColor: appearance.textTertiary
            ])
        }
        setAccessibilityLabel(text)
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
    private var isCurrent = false
    private var isFailed = false

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
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.setAccessibilityElement(false)
        addSubview(metadataLabel)

        bookmarkIndicator.imageScaling = .scaleProportionallyDown
        bookmarkIndicator.setAccessibilityElement(false)
        addSubview(bookmarkIndicator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // The table places a cell a few points inside its row view, so the row shape is worked
        // out in row coordinates and each rect is converted into this cell.
        let host = superview ?? self
        let shape = QueueRowGeometry.shapeRect(inRowBounds: host.bounds, isCurrent: isCurrent,
                                               visibleWidth: host.visibleRect.width)
        let content = QueueRowGeometry.content(inShape: shape,
                                               isCurrent: isCurrent,
                                               isFailed: isFailed,
                                               nameNaturalWidth: titleLabel.naturalWidth,
                                               tagWidth: showsTag ? tagView.preferredWidth : nil,
                                               showsBookmark: showsBookmark)
        func local(_ rect: NSRect?) -> NSRect { rect.map { convert($0, from: host) } ?? .zero }
        leadingGlyph.frame = local(content.glyph)
        titleLabel.frame = local(content.name)
        tagView.frame = local(content.tag)
        bookmarkIndicator.frame = local(content.bookmark)
        metadataLabel.frame = local(content.meta)
    }

    func configure(item: QueuePageView.Item, isCurrent: Bool, query: String) {
        let appearance = DWBAppearance.shared
        self.isCurrent = isCurrent
        isFailed = item.isFailed
        let look = QueueRowAppearance.make(isCurrent: isCurrent,
                                           isSelected: false,
                                           isHovering: false,
                                           isFailed: item.isFailed,
                                           isBookmarked: item.isBookmarked)
        let titleColor = look.filenameIsDimmed ? appearance.textSecondary : DWBColor.textPrimary
        let text = item.displayName
        // While searching the name clips at the end so the highlighted match stays visible;
        // otherwise it truncates in the middle by measurement. The full name is never changed.
        titleLabel.truncation = query.isEmpty ? .middle : .tail
        titleLabel.attributedText = QueueNameStyle.attributedName(
            text,
            fontSize: 12.5,
            weight: look.filenameWeight,
            color: titleColor,
            primaryPrefix: SettingsWindowController.customPrefixValue(),
            secondaryPrefix: SettingsWindowController.customPrefixSecondaryValue(),
            query: query
        )
        toolTip = text

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
        metadataLabel.stringValue = item.isFailed
            ? "Playback failed · Double-click to retry"
            : "\(item.duration) · \(item.fileSize)"

        switch look.leadingGlyph {
        case .playing:
            leadingGlyph.image = Self.symbol("play.fill", size: DWBMetrics.queuePlayingGlyph,
                                             weight: .semibold, description: "Now playing")
            leadingGlyph.contentTintColor = PlayerTheme.current.accentText
            leadingGlyph.isHidden = false
        case .failed:
            leadingGlyph.image = Self.symbol("exclamationmark.triangle.fill", size: 12,
                                             weight: .medium, description: "Failed")
            leadingGlyph.contentTintColor = DWBColor.errorText
            leadingGlyph.isHidden = false
        case .none:
            leadingGlyph.image = nil
            leadingGlyph.isHidden = true
        }

        showsBookmark = look.showsBookmark
        if look.showsBookmark {
            bookmarkIndicator.image = Self.symbol("bookmark.fill", size: 10,
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
    var isCurrent: Bool = false { didSet { if isCurrent != oldValue { needsDisplay = true } } }
    var isBookmarked: Bool = false
    var isFailed: Bool = false
    /// True while the row below is selected: this row then draws no separator, so nothing
    /// crosses the selected row's top edge.
    var isRowBelowSelected: Bool = false { didSet { if isRowBelowSelected != oldValue { needsDisplay = true } } }

    private static let minimumDrawableDimension: CGFloat = 1
    private var accessibilityItemLabel = "Queue item"
    private var isHovering = false
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

    /// Draws the flat row or the playing card (§10.4). Every stroke is inside the shape, the bar is
    /// clipped to the card's own rounded boundary, and the separator is the row's last half point.
    override func drawBackground(in dirtyRect: NSRect) {
        guard !isSection else { return }
        let shape = QueueRowGeometry.shapeRect(inRowBounds: bounds, isCurrent: isCurrent,
                                               visibleWidth: visibleRect.width)
        let radius = QueueRowGeometry.cornerRadius(isCurrent: isCurrent)
        guard Self.isDrawable(shape),
              let path = Self.roundedPath(for: shape, radius: radius) else { return }

        let look = QueueRowAppearance.make(isCurrent: isCurrent,
                                           isSelected: isSelected,
                                           isHovering: isHovering,
                                           isFailed: isFailed,
                                           isBookmarked: isBookmarked,
                                           isNextRowSelected: isRowBelowSelected)
        switch look.fill {
        case .none:             break
        case .accentTintStrong: PlayerTheme.current.accentTintStrong.setFill(); path.fill()
        case .overlaySelected:  DWBColor.overlaySelected.setFill(); path.fill()
        case .overlayHover:     DWBColor.overlayHover.setFill(); path.fill()
        }

        if look.edge != .none {
            let width = look.edge.lineWidth
            let color: NSColor = look.edge == .quiet ? DWBAppearance.shared.border : DWBColor.borderStrong
            let inner = QueueRowGeometry.edgeRect(forShape: shape, lineWidth: width)
            if let edgePath = Self.roundedPath(for: inner, radius: max(0, radius - width / 2)) {
                color.setStroke()
                edgePath.lineWidth = width
                edgePath.stroke()
            }
        }

        if look.showsCurrentBar {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            PlayerTheme.current.accentText.setFill()
            QueueRowGeometry.barRect(forCard: shape).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if look.showsSeparator {
            DWBColor.gridLine.setFill()
            QueueRowGeometry.separatorRect(forShape: shape).fill()
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
