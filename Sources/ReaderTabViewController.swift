import Cocoa
import PDFKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Zotero 7 Native Theming & Flipped Views
enum ZoteroTheme {
    static let sidebarBg = NSColor.windowBackgroundColor
    static let sidebarHeaderBg = NSColor.windowBackgroundColor
    static let dividerColor = NSColor.separatorColor
    static let activeRailItemBg = NSColor.controlAccentColor.withAlphaComponent(0.14)
    static let cardBg = NSColor.controlBackgroundColor
    static let cardBorder = NSColor.separatorColor.withAlphaComponent(0.35)
    static let tagBg = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class ModernCardView: NSView {
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    private var hostedView: NSView?
    private let padding: NSEdgeInsets

    var contentView: NSView? {
        get { hostedView }
        set {
            hostedView?.removeFromSuperview()
            hostedView = newValue
            guard let view = newValue else { return }
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor, constant: padding.top),
                view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
                view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
                view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding.bottom)
            ])
        }
    }

    init(padding: NSEdgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)) {
        self.padding = padding
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        updateColors()
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        layer?.backgroundColor = ZoteroTheme.cardBg.cgColor
        layer?.borderColor = ZoteroTheme.cardBorder.cgColor
    }

    override func updateLayer() {
        super.updateLayer()
        updateColors()
    }
}

final class ModernTagChipView: NSView {
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    private let label: NSTextField
    private let delBtn: NSButton
    private let onDelete: () -> Void

    override var intrinsicContentSize: NSSize {
        let labelWidth = label.intrinsicContentSize.width
        return NSSize(width: ceil(labelWidth) + 33, height: 22)
    }

    init(tag: String, onDelete: @escaping () -> Void) {
        self.onDelete = onDelete
        let lbl = NSTextField(labelWithString: tag)
        lbl.font = .systemFont(ofSize: 11.5, weight: .medium)
        lbl.textColor = .labelColor
        lbl.isBezeled = false
        lbl.isEditable = false
        lbl.drawsBackground = false
        lbl.lineBreakMode = .byTruncatingTail
        lbl.translatesAutoresizingMaskIntoConstraints = false
        self.label = lbl

        let btn = ModernHoverButton()
        btn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "删除标签")?
            .withSymbolConfiguration(.init(pointSize: 11.0, weight: .medium))
        btn.normalTintColor = .secondaryLabelColor
        btn.hoverTintColor = .systemRed
        btn.hoverBgColor = NSColor.systemRed.withAlphaComponent(0.15)
        btn.cornerRadius = 6
        btn.identifier = NSUserInterfaceItemIdentifier(tag)
        btn.translatesAutoresizingMaskIntoConstraints = false
        self.delBtn = btn

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 0.5
        updateColors()

        btn.target = self
        btn.action = #selector(deleteClicked)

        addSubview(lbl)
        addSubview(btn)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            lbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            lbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            btn.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 4),
            btn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            btn.centerYAnchor.constraint(equalTo: centerYAnchor),
            btn.widthAnchor.constraint(equalToConstant: 13),
            btn.heightAnchor.constraint(equalToConstant: 13)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateColors() {
        layer?.backgroundColor = ZoteroTheme.tagBg.cgColor
        layer?.borderColor = ZoteroTheme.cardBorder.cgColor
    }

    override func updateLayer() {
        super.updateLayer()
        updateColors()
    }

    @objc private func deleteClicked() {
        onDelete()
    }
}

final class TagFlowView: NSView {
    override var isFlipped: Bool { true }

    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    private var items: [NSView] = []
    private var calculatedHeight: CGFloat = 24
    private var lastLayoutWidth: CGFloat = 0
    private var heightConstraint: NSLayoutConstraint?

    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: calculatedHeight)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let hc = heightAnchor.constraint(equalToConstant: 24)
        hc.priority = NSLayoutConstraint.Priority(999)
        hc.isActive = true
        self.heightConstraint = hc
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setViews(_ views: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        items = views
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        let targetWidth = bounds.width > 20 ? bounds.width : 260
        recalculateLayout(forWidth: targetWidth)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let currentWidth = bounds.width
        if currentWidth > 20 {
            recalculateLayout(forWidth: currentWidth)
        }
    }

    private func recalculateLayout(forWidth width: CGFloat) {
        lastLayoutWidth = width
        guard !items.isEmpty else {
            if calculatedHeight != 0 {
                calculatedHeight = 0
                heightConstraint?.constant = 0
                invalidateIntrinsicContentSize()
            }
            return
        }

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for item in items {
            let size = item.intrinsicContentSize.width > 0 ? item.intrinsicContentSize : item.fittingSize
            let itemWidth = min(width, max(20, ceil(size.width)))
            let itemHeight = max(22, ceil(size.height))

            if currentX + itemWidth > width && currentX > 0 {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            item.frame = NSRect(x: currentX, y: currentY, width: itemWidth, height: itemHeight)
            currentX += itemWidth + horizontalSpacing
            rowHeight = max(rowHeight, itemHeight)
        }

        let newHeight = currentY + rowHeight
        if abs(calculatedHeight - newHeight) > 0.5 {
            calculatedHeight = newHeight
            heightConstraint?.constant = newHeight
            invalidateIntrinsicContentSize()
        }
    }
}

final class ZoteroRightDrawerView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        ZoteroTheme.sidebarBg.setFill()
        bounds.fill()
    }
}

final class ZoteroSidebarHeaderView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        ZoteroTheme.sidebarHeaderBg.setFill()
        bounds.fill()

        ZoteroTheme.dividerColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

// MARK: - Reader Tab View Controller (Minimalist, Modern macOS Dual-Pane Reader)
final class ReaderTabViewController: NSViewController, NSSearchFieldDelegate, WKScriptMessageHandler {
    private(set) var paperId: String
    /// When set, the tab shows an in-memory unlocked PDF and is never written to the library.
    private var transientSession: TransientOpenSession?
    var onRequestOpenPaperTab: ((String) -> Void)?

    let leftCol = CleanPDFColumnView(side: .original)
    let rightCol = CleanPDFColumnView(side: .translated)
    private let splitView = DualPDFSplitView()
    private var columnSplitRatio: CGFloat = 0.5

    // 极简现代化顶栏控件
    private let topBar = NSVisualEffectView()
    private let outlineToggleBtn = ModernHoverButton()
    var leftSidebarToggleBtn: NSButton { outlineToggleBtn }
    private let modeSeg = NSSegmentedControl(labels: ["原文", "译文", "分屏"], trackingMode: .selectOne, target: nil, action: nil)
    private let swapBtn = ModernHoverButton()
    var isSwapButtonHidden: Bool { swapBtn.isHidden }
    var isSyncButtonHidden: Bool { syncScrollBtn.isHidden }
    var syncButtonTitle: String { syncScrollBtn.title }
    var modeSegmentLabels: [String] { (0..<modeSeg.segmentCount).map { modeSeg.label(forSegment: $0) ?? "" } }
    var dualSplitView: DualPDFSplitView { splitView }
    func canCollapseColumn(_ col: CleanPDFColumnView) -> Bool {
        splitView(splitView, canCollapseSubview: col)
    }
    func setColumnSplitRatioForTesting(_ ratio: CGFloat) { columnSplitRatio = ratio }
    private var dualColumnSeparator: NSView?
    let syncScrollBtn = ModernHoverButton()
    private let resetAlignBtn = ModernHoverButton()

    // 双栏各自独立的页码步进、跳转与缩放控制
    let leftPrevPageBtn = ModernHoverButton()
    let leftPageJumpBtn = ModernHoverButton()
    let leftNextPageBtn = ModernHoverButton()
    let leftZoomOutBtn = ModernHoverButton()
    let leftZoomFitBtn = ModernHoverButton()
    let leftZoomInBtn = ModernHoverButton()
    private let leftControlsContainer = NSStackView()

    let rightPrevPageBtn = ModernHoverButton()
    let rightPageJumpBtn = ModernHoverButton()
    let rightNextPageBtn = ModernHoverButton()
    let rightZoomOutBtn = ModernHoverButton()
    let rightZoomFitBtn = ModernHoverButton()
    let rightZoomInBtn = ModernHoverButton()
    private let rightControlsContainer = NSStackView()
    private var dualColumnControlsSep: NSView?

    var prevPageBtn: ModernHoverButton { leftPrevPageBtn }
    var pageJumpBtn: ModernHoverButton { leftPageJumpBtn }
    var nextPageBtn: ModernHoverButton { leftNextPageBtn }

    let unifiedMarkupToolbar = UnifiedMarkupToolbarView()
    private let markupToolbarToggleBtn = ModernHoverButton()
    private let topBarShowButton = ModernHoverButton()
    private var unifiedMarkupHidden = false
    private let unifiedMarkupDefaultsKey = "ReaderUnifiedMarkupHidden"
    var isTopBarHiddenForTesting: Bool { topBar.isHidden }
    var markupToolbarToggleForTesting: ModernHoverButton { markupToolbarToggleBtn }
    var topBarShowButtonForTesting: ModernHoverButton { topBarShowButton }
    var isTopBarShowButtonVisibleForTesting: Bool { !topBarShowButton.isHidden }

    private let searchField = NSSearchField()
    private let searchMatchLabel = NSTextField(labelWithString: "")
    private let searchNavSeg = NSSegmentedControl()
    private let searchCloseBtn = ModernHoverButton()
    private let searchContainer = NSStackView()
    private weak var searchTargetColumn: CleanPDFColumnView?
    private var commandScrollMonitor: Any?
    private var undoKeyMonitor: Any?
    private let drawerToggleBtn = ModernHoverButton()
    private let saveToLibraryBtn = ModernHoverButton()
    private let transientStatusLabel = NSTextField(labelWithString: "未入库")

    // 左侧浮动覆盖式边栏（大纲目录与页面预览，无碰撞直接覆盖）
    private let leftOverlaySidebar = NSVisualEffectView()
    private var outlineSidebarLeadingConstraint: NSLayoutConstraint?
    private var outlineSidebarTrailingConstraint: NSLayoutConstraint?
    private let leftOverlaySeg = NSSegmentedControl(labels: ["大纲", "缩略图"], trackingMode: .selectOne, target: nil, action: nil)
    private let leftOverlayCloseBtn = ModernHoverButton()
    private let thumbnailsContainer = NSView()
    private let pdfThumbnailView = PDFThumbnailView()
    private var isLeftOverlayOpen = false

    // 每栏仅保留最近一次跳转前的位置；返回后清空，不累积历史。
    private var leftJumpRecord: ReadingJumpRecord?
    private var rightJumpRecord: ReadingJumpRecord?
    private weak var lastJumpCol: CleanPDFColumnView?

    // 双栏与侧边栏两级布局：外层 masterSplitView 分隔 PDF 绘图区与右侧边栏，内层 splitView 保持双栏 50%/50% 对等
    private let masterSplitView = ReaderGeometrySplitView()
    private let pdfCanvasContainer = NSView()

    // 右侧工作台分栏 (Zotero 7 原生排版：顶部论文标题、左侧信息/笔记/翻译面板、右侧垂直图标栏)
    private let rightDrawer = ZoteroRightDrawerView()
    private var isDrawerOpen = false
    private var preferredDrawerWidth: CGFloat = 360
    private(set) var currentWorkbenchTab: Int = 0 // 0: Info, 1: Notes, 2: Translation, 3: Attachments, 4: Tags, 5: Links
    private var notesNeedRefresh = true
    private var linksNeedRefresh = true

    private let sidebarHeaderView = ZoteroSidebarHeaderView()
    private let sidebarPaperTitleLabel = NSTextField(labelWithString: "")

    private let workbenchRailView = NSView()
    private var workbenchRailButtons: [ModernHoverButton] = []

    private let workbenchContentScrollView = NSScrollView()
    let tabInfoContainer = FlippedStackView()
    let tabNotesContainer = FlippedStackView()
    let tabTranslationContainer = FlippedStackView()
    let tabAttachmentsContainer = FlippedStackView()
    let tabTagsContainer = FlippedStackView()
    let tabLinksContainer = FlippedStackView()

    private let metadataFieldsStack = FlippedStackView()
    private let searchToggleBtn = ModernHoverButton()
    private let linksStackView = FlippedStackView()

    // 侧边栏划词翻译与学术解析 (Tab 2)
    private let sidebarTransSourceTextView = NSTextView()
    private let sidebarTransResultWebView = WKWebView()
    private let sidebarTransStatusLabel = NSTextField(labelWithString: "")
    private let sidebarTransProgress = NSProgressIndicator()
    private let sidebarTransModeSeg = NSSegmentedControl(labels: ["学术精读", "术语解析", "要点提炼", "英文润色"], trackingMode: .selectOne, target: nil, action: nil)
    private var sidebarTransActiveTask: URLSessionDataTask?
    private var sidebarTransResultMarkdown: String = ""
    private var sidebarTransLastResult: LLMTranslationResult?
    private var sidebarTransActionButtons: [NSButton] = []
    private var sidebarTransRequestID = UUID()

    // 侧边栏附件管理 (Tab 3)
    private let attachmentsListStack = FlippedStackView()

    // 侧边栏外部链接 (Tab 5)
    private let linksCardsStack = FlippedStackView()

    // 侧边栏标签管理 (Tab 4)
    private let tagsFlowView = TagFlowView()
    private let tagsInputField = NSTextField()
    private let tagsCountBadge = NSTextField(labelWithString: "")
    private let suggestedTagsFlowView = TagFlowView()

    private let outlineContainer = NSView()
    private let outlineTableView = NSTableView()
    private weak var outlineActiveColumn: CleanPDFColumnView?
    private var navigationSourceColumn: CleanPDFColumnView {
        if isLeftOverlayOpen, let active = outlineActiveColumn, !active.isHidden { return active }
        return primaryActiveColumn()
    }
    private var outlineItems: [(title: String, pageIndex: Int, depth: Int)] = []
    private weak var outlineSourceColumn: CleanPDFColumnView?
    private weak var outlineSourceDocument: PDFDocument?
    private var isUpdatingOutlineSelection = false
    private var notesWebView: WKWebView!
    let sidebarNoteView = PaperNoteColumnView()
    private let noteSelector = NSPopUpButton()
    private var selectedSidebarNoteId: String?
    private var translationActionButtons: [NSButton] = []
    private var translationRequestID = UUID()

    // 同步滚动、对齐微调偏移与缩放状态
    private var isScrollSyncEnabled = true
    private var isClosed = false
    private lazy var viewportCoordinator: PDFViewportCoordinator = {
        let coordinator = PDFViewportCoordinator(columns: [leftCol, rightCol])
        coordinator.layoutViews = { [weak self] in
            guard let self = self else { return }
            self.view.layoutSubtreeIfNeeded()
            self.splitView.adjustSubviews()
            self.view.layoutSubtreeIfNeeded()
        }
        coordinator.isTrackingGeometry = { [weak self] in
            guard let self = self else { return false }
            return self.splitView.isTrackingDivider || self.masterSplitView.isTrackingDivider
        }
        coordinator.didFinishLayout = { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.persistReaderState(from: self.primaryActiveColumn())
            self.updatePageIndicatorAndSaveProgress()
        }
        return coordinator
    }()
    private var isLoadingDocuments: Bool { viewportCoordinator.phase == .loading }
    private var isChangingLayout: Bool { viewportCoordinator.isChangingLayout }
    private var isRestoringLayout: Bool { viewportCoordinator.phase == .restoring }
    private var viewportStates: [String: PDFColumnReadingState] {
        get { viewportCoordinator.states }
        set { viewportCoordinator.states = newValue }
    }
    private var loadedPDFFiles: [String: Date] = [:]
    private var searchGeneration = UUID()
    private let toolbarLeftStack = NSStackView()
    private let toolbarCenterStack = NSStackView()
    private let toolbarRightStack = NSStackView()
    private var toolbarHeight: NSLayoutConstraint!
    private var toolbarCenterY: NSLayoutConstraint!
    private var toolbarSeparation: [NSLayoutConstraint] = []
    private var toolbarUsesTwoRows = false
    private var pendingLibraryFields: LibraryChange.Fields = []
    private let annotationRenderer = PDFAnnotationRenderer()
    private let searchController = PDFSearchController()
    private var searchTask: DispatchWorkItem?
    private weak var lastReadingColumn: CleanPDFColumnView?
    private var isSwapped = false
    /// 左右两栏页内相对偏移量（rightRatio - leftRatio），支持按住 ⌥ Option 滚动实时微调校准并持久化
    private(set) var pageRatioOffset: Double = 0.0

    // 页内搜索匹配集
    private var currentSearchMatches: [(col: CleanPDFColumnView, selection: PDFSelection)] = []
    private var currentSearchMatchIndex: Int = 0

    // 划词与高亮悬浮气泡
    private let selectionPopover = NSPopover()
    private weak var activeSelectionPDFView: InteractivePDFView?
    private var activeSheetWindow: NSWindow?
    private var activeTranslationTask: URLSessionDataTask?
    private var currentTranslatedMarkdown: String = ""
    private var currentTranslationMode: LLMTranslationMode = .academicChinese
    private weak var translationPreviewWebView: WKWebView?
    private weak var translationProviderLabel: NSTextField?

    init(paperId: String, transientSession: TransientOpenSession? = nil) {
        self.paperId = paperId
        self.transientSession = transientSession
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var currentPaper: PaperItem? {
        LibraryStore.shared.paper(withId: paperId)
    }

    var isTransientOpen: Bool {
        if transientSession != nil { return true }
        if let paper = currentPaper { return paper.isTransient }
        return LibraryStore.shared.isTransientPaper(id: paperId)
    }
    var transientSourceURL: URL? {
        if let transientSession { return transientSession.sourceURL }
        return TransientStore.shared.sourceURL(for: paperId)
    }

    deinit {
        searchTask?.cancel()
        searchController.cancel()
        removeCommandScrollMonitor()
        removeUndoKeyMonitor()
        NotificationCenter.default.removeObserver(self)
    }

    /// True when either column still has DualPDF_Markup that would be lost on close.
    /// Persisted annotations (library or transient state.json) do not count.
    func hasUnpersistedColumnMarkup() -> Bool {
        [leftCol, rightCol].contains { $0.pdfView.hasUnpersistedSessionMarkup }
    }

    func prepareForClose() {
        guard !isClosed else { return }
        removeCommandScrollMonitor()
        removeUndoKeyMonitor()
        if isViewLoaded {
            finishPendingLayout()
            persistReaderState(from: primaryActiveColumn())
        }
        sidebarNoteView.cleanupForClose()
        LibraryStore.shared.flushReadingState()
        isClosed = true
        viewportCoordinator.close()
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        searchTask?.cancel()
        searchController.cancel()
        NotificationCenter.default.removeObserver(self)
        notesWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "noteAction")
        selectionPopover.close()
        leftCol.pdfView.dismissTextMarkupPopover()
        rightCol.pdfView.dismissTextMarkupPopover()
        if let sheet = activeSheetWindow { sheet.sheetParent?.endSheet(sheet) }
        annotationRenderer.reset()
        currentSearchMatches.removeAll()
        pdfThumbnailView.pdfView = nil
        leftCol.pdfView.document = nil
        rightCol.pdfView.document = nil
        for column in [leftCol, rightCol] {
            splitView.removeArrangedSubview(column)
            column.removeFromSuperview()
        }
    }

    func didResignActiveTab() {
        guard isViewLoaded, !isClosed else { return }
        finishPendingLayout()
        persistReaderState(from: primaryActiveColumn())
        sidebarNoteView.flushPendingSave()
        LibraryStore.shared.flushReadingState()
        viewportCoordinator.isActive = false
        invalidateSearch()
    }

    override func loadView() {
        let root = ReaderRootView(frame: NSRect(x: 0, y: 0, width: 1360, height: 840))
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root

        let offset = currentPaper?.syncOffsetDelta ?? 0
        pageRatioOffset = offset.isFinite ? offset : 0
        if let state = currentPaper?.readerState {
            viewportStates = [PDFSide.original.rawValue: state.leftColumn, PDFSide.translated.rawValue: state.rightColumn]
            leftCol.contentSource = .pdf(id: state.leftColumn.pdfDocumentId)
            rightCol.contentSource = .pdf(id: state.rightColumn.pdfDocumentId)
            isScrollSyncEnabled = state.syncEnabled
            isSwapped = state.swapped
            columnSplitRatio = state.splitRatio.isFinite ? CGFloat(min(0.95, max(0.05, state.splitRatio))) : 0.5
        } else if let saved = currentPaper?.readingPosition, let pdfID = saved.pdfDocumentId {
            let column = saved.side == .original ? leftCol : rightCol
            column.contentSource = .pdf(id: pdfID)
        }
        viewportCoordinator.restoreAlignments(currentPaper?.readerState?.alignments ?? [], legacyOffset: pageRatioOffset)
        pageRatioOffset = viewportCoordinator.alignmentOffset

        setupMainCanvasAndDrawer(in: root)
        setupFloatingBackBanners()
        setupSyncAndCallbacks()
        installCommandScrollMonitor()
        installUndoKeyMonitor()
        root.onGeometryWillChange = { [weak self] in self?.beginLayoutChange() }
        root.onGeometryDidChange = { [weak self] in self?.scheduleLayoutCompletion() }
        root.onLayout = { [weak self] in self?.updateToolbarLayout() }
        loadPaperDocuments()
        refreshTransientChrome()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onLibraryChanged(_:)),
            name: LibraryStore.libraryDidChangeNotification,
            object: nil
        )
    }

    // MARK: - 1. Minimalist Modern macOS Top Bar (38pt height, 3 Balanced Groups)
    private func setupMinimalTopBar(in container: NSView) {
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.translatesAutoresizingMaskIntoConstraints = false

        // --- Group A (Left): 视图模式 & 同步控制 ---
        let barIconConfig = NSImage.SymbolConfiguration(pointSize: 14.0, weight: .medium)
        let barSubIconConfig = NSImage.SymbolConfiguration(pointSize: 13.0, weight: .medium)

        configureToolbarIconButton(outlineToggleBtn)
        outlineToggleBtn.controlSize = .small
        outlineToggleBtn.setButtonType(.pushOnPushOff)
        outlineToggleBtn.isToggleButton = true
        outlineToggleBtn.state = .off
        outlineToggleBtn.image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "大纲与缩略图")?.withSymbolConfiguration(barIconConfig)
        outlineToggleBtn.toolTip = "大纲与缩略图 (⌘1)"
        outlineToggleBtn.keyEquivalent = "1"
        outlineToggleBtn.keyEquivalentModifierMask = [.command]
        outlineToggleBtn.target = self
        outlineToggleBtn.action = #selector(toggleLeftSidebarAction)

        let savedMode = currentPaper?.readerState?.displayMode ?? 2
        modeSeg.selectedSegment = (0...2).contains(savedMode) ? savedMode : 2
        modeSeg.controlSize = .regular
        modeSeg.segmentDistribution = .fillProportionally
        modeSeg.toolTip = "切换阅读模式：原文 / 译文 / 分屏"
        modeSeg.target = self
        modeSeg.action = #selector(modeChangedAction)
        modeSeg.translatesAutoresizingMaskIntoConstraints = false
        modeSeg.widthAnchor.constraint(equalToConstant: 168).isActive = true

        configureToolbarIconButton(swapBtn)
        swapBtn.controlSize = .small
        swapBtn.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "左右互换")?.withSymbolConfiguration(barSubIconConfig)
        swapBtn.toolTip = "左右两栏位置互换 (⇧⌘X)"
        swapBtn.target = self
        swapBtn.action = #selector(swapColumnsAction)

        configureToolbarButton(syncScrollBtn)
        syncScrollBtn.controlSize = .small
        syncScrollBtn.setButtonType(.pushOnPushOff)
        syncScrollBtn.state = isScrollSyncEnabled ? .on : .off
        syncScrollBtn.imagePosition = .imageOnly
        syncScrollBtn.title = ""
        syncScrollBtn.target = self
        syncScrollBtn.action = #selector(toggleSyncScrollAction)
        syncScrollBtn.translatesAutoresizingMaskIntoConstraints = false
        syncScrollBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        syncScrollBtn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        updateSyncButtonStyle()

        configureToolbarButton(resetAlignBtn)
        resetAlignBtn.controlSize = .small
        resetAlignBtn.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        resetAlignBtn.title = "重置对齐"
        resetAlignBtn.toolTip = "重置双栏对齐偏移"
        resetAlignBtn.target = self
        resetAlignBtn.action = #selector(resetSyncAlignmentAction)
        resetAlignBtn.isHidden = abs(pageRatioOffset) < 0.005

        // --- Group B (Center): 双栏各自独立的页码步进/跳转 & 缩放控制 ---
        func configureColumnControls(
            columnTitle: String,
            prevBtn: ModernHoverButton, pageBtn: ModernHoverButton, nextBtn: ModernHoverButton,
            zoomOut: ModernHoverButton, zoomFit: ModernHoverButton, zoomIn: ModernHoverButton,
            container: NSStackView,
            prevAction: Selector, nextAction: Selector, pageAction: Selector,
            zoomOutAction: Selector, zoomFitAction: Selector, zoomInAction: Selector
        ) {
            configureToolbarIconButton(prevBtn)
            prevBtn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "上一页")?.withSymbolConfiguration(barSubIconConfig)
            prevBtn.toolTip = "\(columnTitle)上一页"
            prevBtn.target = self
            prevBtn.action = prevAction

            configureToolbarButton(pageBtn)
            pageBtn.controlSize = .small
            pageBtn.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            pageBtn.title = "1 / 1"
            pageBtn.toolTip = "点击跳转\(columnTitle)指定页码"
            pageBtn.target = self
            pageBtn.action = pageAction

            configureToolbarIconButton(nextBtn)
            nextBtn.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "下一页")?.withSymbolConfiguration(barSubIconConfig)
            nextBtn.toolTip = "\(columnTitle)下一页"
            nextBtn.target = self
            nextBtn.action = nextAction

            configureToolbarIconButton(zoomOut)
            zoomOut.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "缩小")?.withSymbolConfiguration(barSubIconConfig)
            zoomOut.toolTip = "缩小\(columnTitle)页面"
            zoomOut.target = self
            zoomOut.action = zoomOutAction

            configureToolbarButton(zoomFit)
            zoomFit.controlSize = .small
            zoomFit.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            zoomFit.title = "—"
            zoomFit.toolTip = "\(columnTitle)自适应列宽"
            zoomFit.target = self
            zoomFit.action = zoomFitAction

            configureToolbarIconButton(zoomIn)
            zoomIn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "放大")?.withSymbolConfiguration(barSubIconConfig)
            zoomIn.toolTip = "放大\(columnTitle)页面"
            zoomIn.target = self
            zoomIn.action = zoomInAction

            container.subviews.forEach { $0.removeFromSuperview() }
            container.orientation = .horizontal
            container.spacing = 6
            container.alignment = .centerY
            container.translatesAutoresizingMaskIntoConstraints = false

            pageBtn.heightAnchor.constraint(equalToConstant: 26).isActive = true
            pageBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            zoomFit.heightAnchor.constraint(equalToConstant: 26).isActive = true
            zoomFit.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            container.addArrangedSubview(ToolbarCapsuleView(views: [prevBtn, pageBtn, nextBtn]))
            container.addArrangedSubview(ToolbarCapsuleView(views: [zoomOut, zoomFit, zoomIn]))
        }

        configureColumnControls(
            columnTitle: "左栏",
            prevBtn: leftPrevPageBtn, pageBtn: leftPageJumpBtn, nextBtn: leftNextPageBtn,
            zoomOut: leftZoomOutBtn, zoomFit: leftZoomFitBtn, zoomIn: leftZoomInBtn,
            container: leftControlsContainer,
            prevAction: #selector(leftPrevPageAction),
            nextAction: #selector(leftNextPageAction),
            pageAction: #selector(leftPromptPageJumpAction),
            zoomOutAction: #selector(leftZoomOutAction),
            zoomFitAction: #selector(leftZoomFitAction),
            zoomInAction: #selector(leftZoomInAction)
        )

        configureColumnControls(
            columnTitle: "右栏",
            prevBtn: rightPrevPageBtn, pageBtn: rightPageJumpBtn, nextBtn: rightNextPageBtn,
            zoomOut: rightZoomOutBtn, zoomFit: rightZoomFitBtn, zoomIn: rightZoomInBtn,
            container: rightControlsContainer,
            prevAction: #selector(rightPrevPageAction),
            nextAction: #selector(rightNextPageAction),
            pageAction: #selector(rightPromptPageJumpAction),
            zoomOutAction: #selector(rightZoomOutAction),
            zoomFitAction: #selector(rightZoomFitAction),
            zoomInAction: #selector(rightZoomInAction)
        )

        // --- Group C (Right): Zotero 7 原生排版 (页内搜索 / 侧边栏图标) ---
        searchField.placeholderString = "页内查找 (⌘F)…"
        searchField.controlSize = .small
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldReturnPressed)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        searchMatchLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        searchMatchLabel.textColor = .secondaryLabelColor
        searchMatchLabel.isHidden = true

        searchNavSeg.segmentCount = 2
        searchNavSeg.setImage(NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "上一个匹配"), forSegment: 0)
        searchNavSeg.setImage(NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "下一个匹配"), forSegment: 1)
        searchNavSeg.setWidth(22, forSegment: 0)
        searchNavSeg.setWidth(22, forSegment: 1)
        searchNavSeg.trackingMode = .momentary
        searchNavSeg.controlSize = .small
        searchNavSeg.target = self
        searchNavSeg.action = #selector(searchNavClicked)
        searchNavSeg.isHidden = true

        configureToolbarIconButton(searchCloseBtn)
        searchCloseBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭搜索")?
            .withSymbolConfiguration(.init(pointSize: 12.0, weight: .medium))
        searchCloseBtn.hoverTintColor = .labelColor
        searchCloseBtn.cornerRadius = 4
        searchCloseBtn.toolTip = "关闭搜索 (Esc)"
        searchCloseBtn.target = self
        searchCloseBtn.action = #selector(closeSearchAction)
        searchCloseBtn.translatesAutoresizingMaskIntoConstraints = false

        searchContainer.subviews.forEach { $0.removeFromSuperview() }
        searchContainer.orientation = .horizontal
        searchContainer.spacing = 6
        searchContainer.alignment = .centerY
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.isHidden = true
        searchContainer.addArrangedSubview(searchField)
        searchContainer.addArrangedSubview(searchMatchLabel)
        searchContainer.addArrangedSubview(searchNavSeg)
        searchContainer.addArrangedSubview(searchCloseBtn)

        configureToolbarIconButton(searchToggleBtn)
        searchToggleBtn.controlSize = .small
        searchToggleBtn.setButtonType(.pushOnPushOff)
        searchToggleBtn.isToggleButton = true
        searchToggleBtn.state = .off
        searchToggleBtn.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "在文档中搜索")?.withSymbolConfiguration(barIconConfig)
        searchToggleBtn.toolTip = "在文档中搜索 (⌘F)"
        searchToggleBtn.keyEquivalent = "f"
        searchToggleBtn.keyEquivalentModifierMask = [.command]
        searchToggleBtn.target = self
        searchToggleBtn.action = #selector(toggleSearchFieldAction)

        configureToolbarIconButton(markupToolbarToggleBtn)
        markupToolbarToggleBtn.controlSize = .small
        markupToolbarToggleBtn.setButtonType(.pushOnPushOff)
        markupToolbarToggleBtn.isToggleButton = true
        markupToolbarToggleBtn.state = .on
        markupToolbarToggleBtn.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "隐藏顶栏")?
            .withSymbolConfiguration(barIconConfig)
        markupToolbarToggleBtn.toolTip = "隐藏顶栏"
        markupToolbarToggleBtn.target = self
        markupToolbarToggleBtn.action = #selector(toggleMarkupToolbarAction)

        configureToolbarIconButton(drawerToggleBtn)
        drawerToggleBtn.controlSize = .small
        drawerToggleBtn.setButtonType(.pushOnPushOff)
        drawerToggleBtn.isToggleButton = true
        drawerToggleBtn.state = .off
        drawerToggleBtn.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "切换侧边栏")?.withSymbolConfiguration(barIconConfig)
        drawerToggleBtn.title = ""
        drawerToggleBtn.imagePosition = .imageOnly
        drawerToggleBtn.toolTip = "切换侧边栏 (⌘I)"
        drawerToggleBtn.keyEquivalent = "i"
        drawerToggleBtn.keyEquivalentModifierMask = [.command]
        drawerToggleBtn.target = self
        drawerToggleBtn.action = #selector(toggleRightDrawerAction)

        let dualSep = makeToolbarSeparator()
        self.dualColumnSeparator = dualSep

        // --- 3 个自平衡分区（左对齐组、绝对中心组、右对齐组） ---
        let leftBarStack = toolbarLeftStack
        [
            modeSeg,
            swapBtn,
            dualSep,
            syncScrollBtn
        ].forEach { leftBarStack.addArrangedSubview($0) }
        leftBarStack.orientation = .horizontal
        leftBarStack.spacing = 6
        leftBarStack.alignment = .centerY
        leftBarStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(leftBarStack)

        // 阅读器顶栏只保留模式切换与「分屏」专属的互换、同步按钮。
        // 单栏页码与缩放改由每栏底部页码胶囊、专属工具栏和 ⌘+滚轮承担。
        let centerBarStack = toolbarCenterStack
        centerBarStack.orientation = .horizontal
        centerBarStack.spacing = 8
        centerBarStack.alignment = .centerY
        centerBarStack.translatesAutoresizingMaskIntoConstraints = false
        centerBarStack.addArrangedSubview(unifiedMarkupToolbar)
        topBar.addSubview(centerBarStack)

        configureToolbarButton(saveToLibraryBtn)
        saveToLibraryBtn.controlSize = .small
        saveToLibraryBtn.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "存入文献库")?.withSymbolConfiguration(barIconConfig)
        saveToLibraryBtn.title = "存入文献库"
        saveToLibraryBtn.imagePosition = .imageLeading
        saveToLibraryBtn.toolTip = "存入文献库 (⌘S)"
        saveToLibraryBtn.target = self
        saveToLibraryBtn.action = #selector(saveToLibraryAction)
        saveToLibraryBtn.isHidden = true
        saveToLibraryBtn.setContentCompressionResistancePriority(.required, for: .horizontal)

        transientStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        transientStatusLabel.textColor = .secondaryLabelColor
        transientStatusLabel.isHidden = true
        transientStatusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let rightBarStack = toolbarRightStack
        // P0-2「未入库」/「存入文献库」+ 统一批注顶栏显隐 + 搜索默认收起；
        // 右侧边栏开关始终保留在顶栏最右侧。
        [
            transientStatusLabel,
            saveToLibraryBtn,
            searchContainer,
            searchToggleBtn,
            markupToolbarToggleBtn,
            drawerToggleBtn
        ].forEach { rightBarStack.addArrangedSubview($0) }
        rightBarStack.orientation = .horizontal
        rightBarStack.spacing = 6
        rightBarStack.alignment = .centerY
        rightBarStack.detachesHiddenViews = true
        rightBarStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(rightBarStack)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(sep)

        container.addSubview(topBar)

        topBarShowButton.bezelStyle = .texturedRounded
        topBarShowButton.controlSize = .small
        topBarShowButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "显示顶栏")?
            .withSymbolConfiguration(barSubIconConfig)
        topBarShowButton.toolTip = "显示顶栏"
        topBarShowButton.target = self
        topBarShowButton.action = #selector(toggleMarkupToolbarAction)
        topBarShowButton.translatesAutoresizingMaskIntoConstraints = false
        topBarShowButton.isHidden = true
        container.addSubview(topBarShowButton)

        toolbarHeight = topBar.heightAnchor.constraint(equalToConstant: 42)
        toolbarCenterY = centerBarStack.centerYAnchor.constraint(equalTo: topBar.topAnchor, constant: 21)
        toolbarSeparation = [
            leftBarStack.trailingAnchor.constraint(lessThanOrEqualTo: centerBarStack.leadingAnchor, constant: -12),
            rightBarStack.leadingAnchor.constraint(greaterThanOrEqualTo: centerBarStack.trailingAnchor, constant: 12)
        ]
        // Allow the window to reach its declared minimum before switching rows.
        toolbarSeparation.forEach { $0.priority = .defaultLow }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: container.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarHeight,

            // 左侧组：贴紧左边界 12pt
            leftBarStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            leftBarStack.centerYAnchor.constraint(equalTo: topBar.topAnchor, constant: 21),

            // 中间组：绝对居中于窗口 / 顶栏（精准正对双栏分界线）
            centerBarStack.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            toolbarCenterY,
            centerBarStack.leadingAnchor.constraint(greaterThanOrEqualTo: topBar.leadingAnchor, constant: 12),
            centerBarStack.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -12),

            // 右侧组：贴紧右边界 12pt，不挤压中间控制区
            rightBarStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            rightBarStack.centerYAnchor.constraint(equalTo: topBar.topAnchor, constant: 21),
            rightBarStack.leadingAnchor.constraint(greaterThanOrEqualTo: leftBarStack.trailingAnchor, constant: 12),

            sep.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),

            topBarShowButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            topBarShowButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            topBarShowButton.widthAnchor.constraint(equalToConstant: 26),
            topBarShowButton.heightAnchor.constraint(equalToConstant: 20)
        ])
        setupUnifiedMarkupToolbar()
        updateToolbarLayout()
    }

    private func configureToolbarButton(_ button: ModernHoverButton) {
        button.isBordered = false
        button.normalTintColor = .secondaryLabelColor
    }

    private func configureToolbarIconButton(_ button: ModernHoverButton) {
        configureToolbarButton(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func setupUnifiedMarkupToolbar() {
        unifiedMarkupHidden = UserDefaults.standard.bool(forKey: unifiedMarkupDefaultsKey)
        applyMarkupToolbarVisibility()
        unifiedMarkupToolbar.setColor(leftCol.pdfView.markupColor)
        unifiedMarkupToolbar.onToolChanged = { [weak self] tool in
            self?.applyUnifiedMarkupTool(tool)
        }
        unifiedMarkupToolbar.onColorChanged = { [weak self] color in
            guard let self = self else { return }
            self.leftCol.pdfView.markupColor = color
            self.rightCol.pdfView.markupColor = color
        }
        unifiedMarkupToolbar.onUndo = { [weak self] in
            guard let self = self else { return }
            self.primaryActiveColumn().pdfView.undoMarkup()
            self.refreshUnifiedMarkupState()
        }
        unifiedMarkupToolbar.onRedo = { [weak self] in
            guard let self = self else { return }
            self.primaryActiveColumn().pdfView.redoMarkup()
            self.refreshUnifiedMarkupState()
        }
        refreshUnifiedMarkupState()
    }

    private func applyMarkupToolbarVisibility() {
        topBar.isHidden = unifiedMarkupHidden
        toolbarHeight.constant = unifiedMarkupHidden ? 0 : (toolbarUsesTwoRows ? 80 : 42)
        topBarShowButton.isHidden = !unifiedMarkupHidden
        // The canvas was added after the bar; keep the restore handle above it.
        topBarShowButton.superview?.addSubview(topBarShowButton, positioned: .above, relativeTo: nil)
        markupToolbarToggleBtn.state = unifiedMarkupHidden ? .off : .on
        markupToolbarToggleBtn.toolTip = unifiedMarkupHidden ? "显示顶栏" : "隐藏顶栏"
    }

    @objc func toggleReaderTopBarAction() {
        toggleMarkupToolbarAction()
    }

    @objc private func toggleMarkupToolbarAction() {
        unifiedMarkupHidden.toggle()
        UserDefaults.standard.set(unifiedMarkupHidden, forKey: unifiedMarkupDefaultsKey)
        beginLayoutChange()
        applyMarkupToolbarVisibility()
        view.layoutSubtreeIfNeeded()
        scheduleLayoutCompletion()
    }

    private func applyUnifiedMarkupTool(_ tool: PDFMarkupTool) {
        for column in [leftCol, rightCol] {
            column.pdfView.markupTool = tool
            column.columnToolbar.setActiveTool(tool)
        }
        unifiedMarkupToolbar.setSelectedTool(tool)
    }

    func refreshUnifiedMarkupState() {
        let column = primaryActiveColumn()
        unifiedMarkupToolbar.setUndoRedoEnabled(canUndo: column.pdfView.canUndoMarkup,
                                               canRedo: column.pdfView.canRedoMarkup)
    }

    private func makeToolbarSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 1),
            box.heightAnchor.constraint(equalToConstant: 15)
        ])
        return box
    }

    // MARK: - 2. Dual-Pane SplitView + Resizable Right Workbench + Floating Left Overlay
    private func setupMainCanvasAndDrawer(in root: NSView) {
        // 顶栏横跨整个窗口顶部，侧栏展开/收起时顶栏按钮保持静止固定在右上角
        setupMinimalTopBar(in: root)

        masterSplitView.isVertical = true
        masterSplitView.dividerStyle = .thin
        masterSplitView.delegate = self
        masterSplitView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(masterSplitView)

        pdfCanvasContainer.translatesAutoresizingMaskIntoConstraints = false
        masterSplitView.addArrangedSubview(pdfCanvasContainer)

        setupRightDrawerContents()

        rightDrawer.translatesAutoresizingMaskIntoConstraints = false
        rightDrawer.isHidden = true
        masterSplitView.addArrangedSubview(rightDrawer)

        masterSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        masterSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        NSLayoutConstraint.activate([
            masterSplitView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            masterSplitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            masterSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            masterSplitView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            pdfCanvasContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(isSwapped ? rightCol : leftCol)
        splitView.addArrangedSubview(isSwapped ? leftCol : rightCol)
        pdfCanvasContainer.addSubview(splitView)

        splitView.splitRatioProvider = { [weak self] in
            self?.columnSplitRatio ?? 0.5
        }
        splitView.onSplitRatioChanged = { [weak self] newRatio in
            self?.columnSplitRatio = newRatio
        }
        splitView.onDividerDoubleClicked = { [weak self] in
            guard let self = self else { return }
            self.columnSplitRatio = 0.5
            self.applyColumnSplitRatio()
        }
        for split in [masterSplitView, splitView] {
            split.onGeometryWillChange = { [weak self] in self?.beginLayoutChange() }
            split.onGeometryDidChange = { [weak self] in self?.scheduleLayoutCompletion() }
        }
        splitView.onDividerDragEnded = { [weak self] in
            guard let self = self, self.splitView.bounds.width > 1 else { return }
            let total = self.splitView.bounds.width - self.splitView.dividerThickness
            self.columnSplitRatio = (self.splitView.subviews.first?.frame.width ?? total / 2) / total
        }
        masterSplitView.onDividerDragEnded = { [weak self] in
            guard let self = self else { return }
            self.updateDrawerVisibility()
            if self.isDrawerOpen { self.preferredDrawerWidth = self.rightDrawer.frame.width }
        }

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: pdfCanvasContainer.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: pdfCanvasContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: pdfCanvasContainer.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: pdfCanvasContainer.bottomAnchor)
        ])

        setupLeftOverlaySidebar(in: pdfCanvasContainer)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.applyColumnSplitRatio()
        }
    }

    private func setupLeftOverlaySidebar(in container: NSView) {
        leftOverlaySidebar.material = .hudWindow
        leftOverlaySidebar.blendingMode = .withinWindow
        leftOverlaySidebar.state = .active
        leftOverlaySidebar.wantsLayer = true
        leftOverlaySidebar.layer?.cornerRadius = 10
        leftOverlaySidebar.layer?.borderWidth = 0.8
        leftOverlaySidebar.layer?.borderColor = NSColor.separatorColor.cgColor
        leftOverlaySidebar.layer?.shadowColor = NSColor.black.withAlphaComponent(0.25).cgColor
        leftOverlaySidebar.layer?.shadowOpacity = 0.85
        leftOverlaySidebar.layer?.shadowRadius = 14
        leftOverlaySidebar.layer?.shadowOffset = CGSize(width: 4, height: -2)
        leftOverlaySidebar.translatesAutoresizingMaskIntoConstraints = false
        leftOverlaySidebar.isHidden = true

        let topBarView = NSView()
        topBarView.translatesAutoresizingMaskIntoConstraints = false

        leftOverlaySeg.selectedSegment = 0
        leftOverlaySeg.controlSize = .small
        leftOverlaySeg.segmentDistribution = .fillEqually
        leftOverlaySeg.target = self
        leftOverlaySeg.action = #selector(leftOverlaySegChanged)
        leftOverlaySeg.translatesAutoresizingMaskIntoConstraints = false

        leftOverlayCloseBtn.bezelStyle = .inline
        leftOverlayCloseBtn.isBordered = false
        leftOverlayCloseBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭大纲与页面预览")
        leftOverlayCloseBtn.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        leftOverlayCloseBtn.contentTintColor = .secondaryLabelColor
        leftOverlayCloseBtn.target = self
        leftOverlayCloseBtn.action = #selector(toggleLeftSidebarAction)
        leftOverlayCloseBtn.translatesAutoresizingMaskIntoConstraints = false

        topBarView.addSubview(leftOverlaySeg)
        topBarView.addSubview(leftOverlayCloseBtn)

        leftOverlaySidebar.addSubview(topBarView)

        // 1) 目录大纲
        outlineContainer.translatesAutoresizingMaskIntoConstraints = false
        leftOverlaySidebar.addSubview(outlineContainer)

        let outlineScroll = NSScrollView()
        outlineScroll.drawsBackground = false
        outlineScroll.hasVerticalScroller = true
        outlineScroll.translatesAutoresizingMaskIntoConstraints = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineCol"))
        col.title = "章节与页码导航"
        outlineTableView.addTableColumn(col)
        outlineTableView.headerView = nil
        outlineTableView.style = .sourceList
        outlineTableView.rowHeight = 30
        outlineTableView.delegate = self
        outlineTableView.dataSource = self
        outlineTableView.target = self
        outlineTableView.action = #selector(outlineRowClicked)
        outlineScroll.documentView = outlineTableView
        outlineContainer.addSubview(outlineScroll)

        // 2) 页面预览
        thumbnailsContainer.translatesAutoresizingMaskIntoConstraints = false
        thumbnailsContainer.isHidden = true
        leftOverlaySidebar.addSubview(thumbnailsContainer)

        pdfThumbnailView.pdfView = primaryActiveColumn().pdfView
        pdfThumbnailView.thumbnailSize = NSSize(width: 140, height: 180)
        pdfThumbnailView.backgroundColor = .clear
        pdfThumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailsContainer.addSubview(pdfThumbnailView)

        container.addSubview(leftOverlaySidebar)

        let outlineLeading = leftOverlaySidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8)
        let outlineTrailing = leftOverlaySidebar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8)
        outlineLeading.isActive = true
        outlineSidebarLeadingConstraint = outlineLeading
        outlineSidebarTrailingConstraint = outlineTrailing

        NSLayoutConstraint.activate([
            leftOverlaySidebar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            leftOverlaySidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            leftOverlaySidebar.widthAnchor.constraint(equalToConstant: 280),

            topBarView.topAnchor.constraint(equalTo: leftOverlaySidebar.topAnchor, constant: 8),
            topBarView.leadingAnchor.constraint(equalTo: leftOverlaySidebar.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: leftOverlaySidebar.trailingAnchor),
            topBarView.heightAnchor.constraint(equalToConstant: 32),

            leftOverlaySeg.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 12),
            leftOverlaySeg.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            leftOverlaySeg.widthAnchor.constraint(equalToConstant: 210),

            leftOverlayCloseBtn.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -10),
            leftOverlayCloseBtn.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            leftOverlayCloseBtn.widthAnchor.constraint(equalToConstant: 22),
            leftOverlayCloseBtn.heightAnchor.constraint(equalToConstant: 22),

            outlineContainer.topAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: 6),
            outlineContainer.leadingAnchor.constraint(equalTo: leftOverlaySidebar.leadingAnchor, constant: 4),
            outlineContainer.trailingAnchor.constraint(equalTo: leftOverlaySidebar.trailingAnchor, constant: -4),
            outlineContainer.bottomAnchor.constraint(equalTo: leftOverlaySidebar.bottomAnchor, constant: -6),

            outlineScroll.topAnchor.constraint(equalTo: outlineContainer.topAnchor),
            outlineScroll.leadingAnchor.constraint(equalTo: outlineContainer.leadingAnchor),
            outlineScroll.trailingAnchor.constraint(equalTo: outlineContainer.trailingAnchor),
            outlineScroll.bottomAnchor.constraint(equalTo: outlineContainer.bottomAnchor),

            thumbnailsContainer.topAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: 6),
            thumbnailsContainer.leadingAnchor.constraint(equalTo: leftOverlaySidebar.leadingAnchor, constant: 4),
            thumbnailsContainer.trailingAnchor.constraint(equalTo: leftOverlaySidebar.trailingAnchor, constant: -4),
            thumbnailsContainer.bottomAnchor.constraint(equalTo: leftOverlaySidebar.bottomAnchor, constant: -6),

            pdfThumbnailView.topAnchor.constraint(equalTo: thumbnailsContainer.topAnchor),
            pdfThumbnailView.leadingAnchor.constraint(equalTo: thumbnailsContainer.leadingAnchor),
            pdfThumbnailView.trailingAnchor.constraint(equalTo: thumbnailsContainer.trailingAnchor),
            pdfThumbnailView.bottomAnchor.constraint(equalTo: thumbnailsContainer.bottomAnchor)
        ])
    }

    @objc private func toggleSearchFieldAction() {
        if searchContainer.isHidden {
            searchTargetColumn = nil
            openSearchAction()
        } else {
            closeSearchAction()
        }
    }

    private func openSearchAction() {
        searchContainer.isHidden = false
        searchToggleBtn.isHidden = true
        searchToggleBtn.state = .on
        if let target = searchTargetColumn {
            searchField.placeholderString = target === leftCol ? "在左栏中查找…" : "在右栏中查找…"
        } else {
            searchField.placeholderString = "页内查找 (⌘F)…"
        }
        updateToolbarLayout()
        view.window?.makeFirstResponder(searchField)
    }

    @objc private func closeSearchAction() {
        invalidateSearch()
        searchContainer.isHidden = true
        searchToggleBtn.isHidden = false
        searchToggleBtn.state = .off
        currentSearchMatches.removeAll()
        leftCol.pdfView.clearSelection()
        rightCol.pdfView.clearSelection()
        searchField.stringValue = ""
        searchField.placeholderString = "页内查找 (⌘F)…"
        searchTargetColumn = nil
        searchNavSeg.isHidden = true
        searchMatchLabel.isHidden = true
        searchMatchLabel.stringValue = ""
        updateToolbarLayout()
        view.window?.makeFirstResponder(primaryActiveColumn().pdfView)
    }

    private func setupRightDrawerContents() {
        let mainInspectorArea = NSView()
        mainInspectorArea.translatesAutoresizingMaskIntoConstraints = false
        rightDrawer.addSubview(mainInspectorArea)

        workbenchRailView.translatesAutoresizingMaskIntoConstraints = false
        rightDrawer.addSubview(workbenchRailView)

        let railSep = NSBox()
        railSep.boxType = .custom
        railSep.borderWidth = 0
        railSep.fillColor = ZoteroTheme.dividerColor
        railSep.translatesAutoresizingMaskIntoConstraints = false
        rightDrawer.addSubview(railSep)

        NSLayoutConstraint.activate([
            mainInspectorArea.topAnchor.constraint(equalTo: rightDrawer.topAnchor),
            mainInspectorArea.bottomAnchor.constraint(equalTo: rightDrawer.bottomAnchor),
            mainInspectorArea.leadingAnchor.constraint(equalTo: rightDrawer.leadingAnchor),
            mainInspectorArea.trailingAnchor.constraint(equalTo: railSep.leadingAnchor),

            railSep.topAnchor.constraint(equalTo: rightDrawer.topAnchor),
            railSep.bottomAnchor.constraint(equalTo: rightDrawer.bottomAnchor),
            railSep.trailingAnchor.constraint(equalTo: workbenchRailView.leadingAnchor),
            railSep.widthAnchor.constraint(equalToConstant: 1),

            workbenchRailView.topAnchor.constraint(equalTo: rightDrawer.topAnchor),
            workbenchRailView.bottomAnchor.constraint(equalTo: rightDrawer.bottomAnchor),
            workbenchRailView.trailingAnchor.constraint(equalTo: rightDrawer.trailingAnchor),
            workbenchRailView.widthAnchor.constraint(equalToConstant: 44)
        ])

        setupSidebarHeader(in: mainInspectorArea)
        setupSidebarContentTabs(in: mainInspectorArea)
        setupWorkbenchRail()

        updateRightSidebarMetadataUI()
        switchWorkbenchTab(to: 0)
    }

    private func setupSidebarHeader(in mainView: NSView) {
        sidebarHeaderView.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(sidebarHeaderView)

        sidebarPaperTitleLabel.font = .systemFont(ofSize: 13.0, weight: .semibold)
        sidebarPaperTitleLabel.textColor = .labelColor
        sidebarPaperTitleLabel.lineBreakMode = .byTruncatingTail
        sidebarPaperTitleLabel.maximumNumberOfLines = 1
        sidebarPaperTitleLabel.isSelectable = true
        sidebarPaperTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebarHeaderView.addSubview(sidebarPaperTitleLabel)

        NSLayoutConstraint.activate([
            sidebarHeaderView.topAnchor.constraint(equalTo: mainView.topAnchor),
            sidebarHeaderView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            sidebarHeaderView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            sidebarHeaderView.heightAnchor.constraint(equalToConstant: 38),

            sidebarPaperTitleLabel.leadingAnchor.constraint(equalTo: sidebarHeaderView.leadingAnchor, constant: 14),
            sidebarPaperTitleLabel.centerYAnchor.constraint(equalTo: sidebarHeaderView.centerYAnchor),
            sidebarPaperTitleLabel.trailingAnchor.constraint(equalTo: sidebarHeaderView.trailingAnchor, constant: -14)
        ])
    }

    private func setupWorkbenchRail() {
        workbenchRailButtons.removeAll()
        workbenchRailView.subviews.forEach { $0.removeFromSuperview() }

        let railStack = NSStackView()
        railStack.orientation = .vertical
        railStack.alignment = .centerX
        railStack.spacing = 8
        railStack.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        railStack.translatesAutoresizingMaskIntoConstraints = false
        workbenchRailView.addSubview(railStack)

        NSLayoutConstraint.activate([
            railStack.topAnchor.constraint(equalTo: workbenchRailView.topAnchor),
            railStack.leadingAnchor.constraint(equalTo: workbenchRailView.leadingAnchor),
            railStack.trailingAnchor.constraint(equalTo: workbenchRailView.trailingAnchor)
        ])

        let tabDefs: [(icon: String, tooltip: String, tag: Int)] = [
            ("info.circle", "文献信息", 0),
            ("square.and.pencil", "随手笔记", 1),
            ("character.book.closed", "划词翻译", 2),
            ("paperclip", "附件", 3),
            ("tag", "标签", 4),
            ("link", "相关条目与链接", 5)
        ]

        for def in tabDefs {
            let btn = ModernHoverButton()
            btn.image = NSImage(systemSymbolName: def.icon, accessibilityDescription: def.tooltip)?
                .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
            btn.normalTintColor = .secondaryLabelColor
            btn.hoverTintColor = .controlAccentColor
            btn.activeTintColor = .controlAccentColor
            btn.hoverBgColor = ZoteroTheme.activeRailItemBg.withAlphaComponent(0.08)
            btn.activeBgColor = ZoteroTheme.activeRailItemBg
            btn.cornerRadius = 6
            btn.toolTip = def.tooltip
            btn.tag = def.tag
            btn.target = self
            btn.action = #selector(workbenchRailButtonClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 32).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
            btn.isSelectedTab = (def.tag == currentWorkbenchTab)
            railStack.addArrangedSubview(btn)
            workbenchRailButtons.append(btn)
        }
    }

    @objc private func workbenchRailButtonClicked(_ sender: NSButton) {
        switchWorkbenchTab(to: sender.tag)
    }

    func switchWorkbenchTab(to index: Int) {
        sidebarNoteView.flushPendingSave()
        currentWorkbenchTab = index
        for btn in workbenchRailButtons {
            btn.isSelectedTab = (btn.tag == index)
        }

        tabInfoContainer.isHidden = (index != 0)
        tabNotesContainer.isHidden = (index != 1)
        tabTranslationContainer.isHidden = (index != 2)
        tabAttachmentsContainer.isHidden = (index != 3)
        tabTagsContainer.isHidden = (index != 4)
        tabLinksContainer.isHidden = (index != 5)

        if index == 0 {
            updateRightSidebarMetadataUI()
        } else if index == 1 {
            refreshSidebarNotes()
            notesNeedRefresh = true
            refreshNotesDrawerWebView()
        } else if index == 2 {
            if sidebarTransSourceTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let sel = (leftCol.pdfView.currentSelection ?? rightCol.pdfView.currentSelection)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !sel.isEmpty {
                    sidebarTransSourceTextView.string = sel
                }
            }
            refreshTranslationTabUI()
        } else if index == 3 {
            refreshAttachmentsTabUI()
        } else if index == 4 {
            refreshTagsTabUI()
        } else if index == 5 {
            refreshLinksDrawerView()
        }
    }

    private func setupSidebarContentTabs(in mainView: NSView) {
        workbenchContentScrollView.drawsBackground = false
        workbenchContentScrollView.hasVerticalScroller = true
        workbenchContentScrollView.hasHorizontalScroller = false
        workbenchContentScrollView.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(workbenchContentScrollView)

        let contentStack = FlippedStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 20, right: 14)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        workbenchContentScrollView.documentView = contentStack

        NSLayoutConstraint.activate([
            workbenchContentScrollView.topAnchor.constraint(equalTo: sidebarHeaderView.bottomAnchor),
            workbenchContentScrollView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor),
            workbenchContentScrollView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor),
            workbenchContentScrollView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: workbenchContentScrollView.widthAnchor)
        ])

        setupInfoTab(in: contentStack)
        setupNotesTab(in: contentStack)
        setupTranslationTab(in: contentStack)
        setupAttachmentsTab(in: contentStack)
        setupTagsTab(in: contentStack)
        setupLinksTab(in: contentStack)
    }

    private func setupInfoTab(in parentStack: NSStackView) {
        tabInfoContainer.orientation = .vertical
        tabInfoContainer.alignment = .leading
        tabInfoContainer.spacing = 8
        tabInfoContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabInfoContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let secTitle = NSTextField(labelWithString: "条目信息")
        secTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        secTitle.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshBtn = NSButton()
        refreshBtn.bezelStyle = .inline
        refreshBtn.isBordered = false
        refreshBtn.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "刷新元数据")?
            .withSymbolConfiguration(.init(pointSize: 12.0, weight: .medium))
        refreshBtn.contentTintColor = .secondaryLabelColor
        refreshBtn.toolTip = "重新拉取官方元数据"
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshMetadataAndCitationsAction)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.widthAnchor.constraint(equalToConstant: 22).isActive = true
        refreshBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true

        secHeader.setViews([secTitle, spacer, refreshBtn], in: .leading)

        metadataFieldsStack.orientation = .vertical
        metadataFieldsStack.alignment = .leading
        metadataFieldsStack.spacing = 4
        metadataFieldsStack.translatesAutoresizingMaskIntoConstraints = false

        tabInfoContainer.addArrangedSubview(secHeader)
        tabInfoContainer.addArrangedSubview(metadataFieldsStack)

        NSLayoutConstraint.activate([
            tabInfoContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabInfoContainer.widthAnchor),
            metadataFieldsStack.widthAnchor.constraint(equalTo: tabInfoContainer.widthAnchor)
        ])
    }

    private func setupNotesTab(in parentStack: NSStackView) {
        tabNotesContainer.orientation = .vertical
        tabNotesContainer.alignment = .leading
        tabNotesContainer.spacing = 10
        tabNotesContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabNotesContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let secTitle = NSTextField(labelWithString: "随手笔记")
        secTitle.font = .systemFont(ofSize: 13.0, weight: .semibold)
        secTitle.textColor = .labelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let addSnippetBtn = NSButton(title: "＋ 引用", target: self, action: #selector(addGeneralPageNoteAction))
        addSnippetBtn.bezelStyle = .inline
        addSnippetBtn.controlSize = .small
        addSnippetBtn.font = .systemFont(ofSize: 11.5)

        let openMdBtn = NSButton(title: "定位", target: self, action: #selector(revealNotesMarkdownAction))
        openMdBtn.bezelStyle = .inline
        openMdBtn.controlSize = .small
        openMdBtn.font = .systemFont(ofSize: 11.5)

        secHeader.setViews([secTitle, spacer, addSnippetBtn, openMdBtn], in: .leading)

        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "noteAction")
        notesWebView = WKWebView(frame: .zero, configuration: config)
        notesWebView.setValue(false, forKey: "drawsBackground")
        notesWebView.translatesAutoresizingMaskIntoConstraints = false

        tabNotesContainer.addArrangedSubview(secHeader)
        noteSelector.target = self
        noteSelector.action = #selector(sidebarNoteSelectionChanged(_:))
        noteSelector.translatesAutoresizingMaskIntoConstraints = false
        noteSelector.setAccessibilityLabel("选择论文笔记")
        tabNotesContainer.addArrangedSubview(noteSelector)
        sidebarNoteView.translatesAutoresizingMaskIntoConstraints = false
        tabNotesContainer.addArrangedSubview(sidebarNoteView)
        let annotationsTitle = NSTextField(labelWithString: "划线与批注")
        annotationsTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        tabNotesContainer.addArrangedSubview(annotationsTitle)
        tabNotesContainer.addArrangedSubview(notesWebView)
        configureSidebarNoteCallbacks()
        refreshSidebarNotes()

        NSLayoutConstraint.activate([
            tabNotesContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabNotesContainer.widthAnchor),
            noteSelector.widthAnchor.constraint(equalTo: tabNotesContainer.widthAnchor),
            sidebarNoteView.widthAnchor.constraint(equalTo: tabNotesContainer.widthAnchor),
            sidebarNoteView.heightAnchor.constraint(equalToConstant: 440),
            notesWebView.widthAnchor.constraint(equalTo: tabNotesContainer.widthAnchor),
            notesWebView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])
    }

    // MARK: - Sidebar Helper Components
    private func makeSidebarCardView(padding: NSEdgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)) -> ModernCardView {
        return ModernCardView(padding: padding)
    }

    private func makeCompactActionButton(title: String, symbol: String? = nil, action: Selector, tint: NSColor = .controlAccentColor) -> ModernHoverButton {
        let btn = ModernHoverButton()
        btn.title = title
        if let symbol = symbol {
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 11.0, weight: .medium))
            btn.imagePosition = .imageLeading
        }
        btn.normalTintColor = tint
        btn.hoverTintColor = tint
        btn.hoverBgColor = tint.withAlphaComponent(0.12)
        btn.cornerRadius = 5
        btn.font = .systemFont(ofSize: 11.5, weight: .medium)
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    private func formattedFileSize(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "未知大小"
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }

    // MARK: - Tab 2: 划词翻译与学术解析 (Translation)

    private func configureSidebarNoteCallbacks() {
        sidebarNoteView.onCreateNewNoteRequested = { [weak self] in self?.promptToCreateNewNote() }
        sidebarNoteView.onDeleteCurrentNoteRequested = { [weak self] noteId in
            guard let self = self else { return }
            self.sidebarNoteView.flushPendingSave()
            if LibraryStore.shared.deleteNoteDocument(for: self.paperId, noteId: noteId) {
                self.selectedSidebarNoteId = nil
                self.refreshSidebarNotes()
            }
        }
        sidebarNoteView.onNoteContentChanged = { [weak self] note in
            guard let self = self else { return }
            LibraryStore.shared.saveNoteDocument(for: self.paperId, note: note, notify: true)
        }
        sidebarNoteView.onJumpLinkClicked = { [weak self] url in self?.handleNoteJumpURL(url) }
        sidebarNoteView.onInsertCurrentPDFSelectionLinkRequested = { [weak self] in
            guard let self = self else { return }
            self.insertJumpLinkFromPDFColumn(self.primaryActiveColumn())
        }
    }

    private func refreshSidebarNotes() {
        // 先落稿，再读取最新 store 快照，避免旧快照覆盖刚保存的正文。
        sidebarNoteView.flushPendingSave()
        guard let paper = currentPaper else { return }
        let notes = paper.effectiveNoteDocuments
        guard let note = notes.first(where: { $0.id == selectedSidebarNoteId }) ?? notes.first else { return }
        selectedSidebarNoteId = note.id
        noteSelector.removeAllItems()
        for item in notes {
            noteSelector.addItem(withTitle: item.title)
            noteSelector.lastItem?.representedObject = item.id
        }
        if let index = notes.firstIndex(where: { $0.id == note.id }) { noteSelector.selectItem(at: index) }
        sidebarNoteView.loadNote(note, allNotes: notes)
    }

    @objc private func sidebarNoteSelectionChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        sidebarNoteView.flushPendingSave()
        selectedSidebarNoteId = id
        refreshSidebarNotes()
    }

    func openNotesSidebar(noteId: String? = nil) {
        sidebarNoteView.flushPendingSave()
        if let id = noteId { selectedSidebarNoteId = id }
        if !isDrawerOpen { toggleRightDrawerAction() }
        switchWorkbenchTab(to: 1)
    }

    private func setupTranslationTab(in parentStack: NSStackView) {
        tabTranslationContainer.orientation = .vertical
        tabTranslationContainer.alignment = .leading
        tabTranslationContainer.spacing = 10
        tabTranslationContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabTranslationContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let secTitle = NSTextField(labelWithString: "划词翻译")
        secTitle.font = .systemFont(ofSize: 13.0, weight: .semibold)
        secTitle.textColor = .labelColor

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let settingsBtn = NSButton()
        settingsBtn.bezelStyle = .inline
        settingsBtn.isBordered = false
        settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "翻译模型与密钥设置")
        settingsBtn.toolTip = "模型与 API 设置"
        settingsBtn.target = self
        settingsBtn.action = #selector(openTranslationSettingsModal)

        secHeader.addArrangedSubview(secTitle)
        secHeader.addArrangedSubview(headerSpacer)
        secHeader.addArrangedSubview(settingsBtn)

        sidebarTransModeSeg.segmentCount = 4
        sidebarTransModeSeg.setLabel("精读", forSegment: 0)
        sidebarTransModeSeg.setLabel("解析", forSegment: 1)
        sidebarTransModeSeg.setLabel("提炼", forSegment: 2)
        sidebarTransModeSeg.setLabel("润色", forSegment: 3)
        sidebarTransModeSeg.setToolTip("学术精读", forSegment: 0)
        sidebarTransModeSeg.setToolTip("术语解析与推导", forSegment: 1)
        sidebarTransModeSeg.setToolTip("要点提炼", forSegment: 2)
        sidebarTransModeSeg.setToolTip("英文润色", forSegment: 3)
        sidebarTransModeSeg.selectedSegment = 0
        sidebarTransModeSeg.controlSize = .small
        sidebarTransModeSeg.segmentDistribution = .fillEqually
        sidebarTransModeSeg.target = self
        sidebarTransModeSeg.action = #selector(sidebarTransModeChanged(_:))
        sidebarTransModeSeg.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 6
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        sidebarTransStatusLabel.font = .systemFont(ofSize: 11.5)
        sidebarTransStatusLabel.textColor = .secondaryLabelColor

        sidebarTransProgress.style = .spinning
        sidebarTransProgress.controlSize = .small
        sidebarTransProgress.isDisplayedWhenStopped = false
        sidebarTransProgress.translatesAutoresizingMaskIntoConstraints = false

        statusRow.addArrangedSubview(sidebarTransStatusLabel)
        statusRow.addArrangedSubview(sidebarTransProgress)

        let sourceCard = makeSidebarCardView()
        let sourceCardStack = FlippedStackView()
        sourceCardStack.orientation = .vertical
        sourceCardStack.alignment = .leading
        sourceCardStack.spacing = 6
        sourceCardStack.translatesAutoresizingMaskIntoConstraints = false
        sourceCard.contentView = sourceCardStack

        let sourceHeaderRow = NSStackView()
        sourceHeaderRow.orientation = .horizontal
        sourceHeaderRow.alignment = .centerY
        sourceHeaderRow.spacing = 6
        sourceHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        let sourceLabel = NSTextField(labelWithString: "原文")
        sourceLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        sourceLabel.textColor = .secondaryLabelColor

        let sourceSpacer = NSView()
        sourceSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let clearBtn = makeCompactActionButton(title: "清空", symbol: "xmark.circle", action: #selector(sidebarClearTransSourceAction), tint: .secondaryLabelColor)

        sourceHeaderRow.addArrangedSubview(sourceLabel)
        sourceHeaderRow.addArrangedSubview(sourceSpacer)
        sourceHeaderRow.addArrangedSubview(clearBtn)

        let sourceScroll = NSScrollView()
        sourceScroll.drawsBackground = true
        sourceScroll.backgroundColor = .textBackgroundColor
        sourceScroll.hasVerticalScroller = true
        sourceScroll.hasHorizontalScroller = false
        sourceScroll.autohidesScrollers = true
        sourceScroll.borderType = .bezelBorder
        sourceScroll.translatesAutoresizingMaskIntoConstraints = false
        sourceScroll.heightAnchor.constraint(equalToConstant: 76).isActive = true

        sidebarTransSourceTextView.isRichText = false
        sidebarTransSourceTextView.isEditable = true
        sidebarTransSourceTextView.font = .systemFont(ofSize: 12.0)
        sidebarTransSourceTextView.textColor = .textColor
        sidebarTransSourceTextView.drawsBackground = false
        sidebarTransSourceTextView.isVerticallyResizable = true
        sidebarTransSourceTextView.isHorizontallyResizable = false
        sidebarTransSourceTextView.autoresizingMask = [.width]
        sidebarTransSourceTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        sidebarTransSourceTextView.textContainer?.widthTracksTextView = true
        sourceScroll.documentView = sidebarTransSourceTextView

        let actionBtnRow = NSStackView()
        actionBtnRow.orientation = .horizontal
        actionBtnRow.spacing = 8
        actionBtnRow.alignment = .centerY
        actionBtnRow.translatesAutoresizingMaskIntoConstraints = false

        let translateBtn = NSButton(title: "翻译", target: self, action: #selector(sidebarTranslateAction))
        translateBtn.bezelStyle = .rounded
        translateBtn.controlSize = .small
        translateBtn.keyEquivalent = "\r"

        let transPageBtn = NSButton(title: "当前页", target: self, action: #selector(sidebarTranslateCurrentPageAction))
        transPageBtn.bezelStyle = .rounded
        transPageBtn.controlSize = .small

        actionBtnRow.addArrangedSubview(translateBtn)
        actionBtnRow.addArrangedSubview(transPageBtn)

        sourceCardStack.addArrangedSubview(sourceHeaderRow)
        sourceCardStack.addArrangedSubview(sourceScroll)
        sourceCardStack.addArrangedSubview(actionBtnRow)

        let resultCard = makeSidebarCardView()
        let resultCardStack = FlippedStackView()
        resultCardStack.orientation = .vertical
        resultCardStack.alignment = .leading
        resultCardStack.spacing = 6
        resultCardStack.translatesAutoresizingMaskIntoConstraints = false
        resultCard.contentView = resultCardStack

        let resultHeaderRow = NSStackView()
        resultHeaderRow.orientation = .horizontal
        resultHeaderRow.alignment = .centerY
        resultHeaderRow.spacing = 6
        resultHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        let resultTitle = NSTextField(labelWithString: "译文")
        resultTitle.font = .systemFont(ofSize: 11.5, weight: .semibold)
        resultTitle.textColor = .secondaryLabelColor

        let resultSpacer = NSView()
        resultSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let copyBtn = makeCompactActionButton(title: "复制", symbol: "doc.on.doc", action: #selector(sidebarCopyTranslationAction))
        let insertNoteBtn = makeCompactActionButton(title: "存入笔记", symbol: "plus.square", action: #selector(sidebarInsertTranslationToNoteAction))
        sidebarTransActionButtons = [copyBtn, insertNoteBtn]
        sidebarTransActionButtons.forEach { $0.isEnabled = false }

        resultHeaderRow.addArrangedSubview(resultTitle)
        resultHeaderRow.addArrangedSubview(resultSpacer)
        resultHeaderRow.addArrangedSubview(copyBtn)
        resultHeaderRow.addArrangedSubview(insertNoteBtn)

        sidebarTransResultWebView.setValue(false, forKey: "drawsBackground")
        sidebarTransResultWebView.translatesAutoresizingMaskIntoConstraints = false

        resultCardStack.addArrangedSubview(resultHeaderRow)
        resultCardStack.addArrangedSubview(sidebarTransResultWebView)

        tabTranslationContainer.addArrangedSubview(secHeader)
        tabTranslationContainer.addArrangedSubview(sidebarTransModeSeg)
        tabTranslationContainer.addArrangedSubview(statusRow)
        tabTranslationContainer.addArrangedSubview(sourceCard)
        tabTranslationContainer.addArrangedSubview(resultCard)

        NSLayoutConstraint.activate([
            tabTranslationContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            sidebarTransModeSeg.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            sourceCard.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            resultCard.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            sourceHeaderRow.widthAnchor.constraint(equalTo: sourceCardStack.widthAnchor),
            sourceScroll.widthAnchor.constraint(equalTo: sourceCardStack.widthAnchor),
            resultHeaderRow.widthAnchor.constraint(equalTo: resultCardStack.widthAnchor),
            sidebarTransResultWebView.widthAnchor.constraint(equalTo: resultCardStack.widthAnchor),
            sidebarTransResultWebView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        refreshTranslationTabUI()
    }

    // MARK: - Tab 3: PDF 附件与文档 (Attachments)
    private func setupAttachmentsTab(in parentStack: NSStackView) {
        tabAttachmentsContainer.orientation = .vertical
        tabAttachmentsContainer.alignment = .leading
        tabAttachmentsContainer.spacing = 10
        tabAttachmentsContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabAttachmentsContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let secTitle = NSTextField(labelWithString: "附件")
        secTitle.font = .systemFont(ofSize: 13.0, weight: .semibold)
        secTitle.textColor = .labelColor

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let addAttachBtn = NSButton(title: "＋ 导入…", target: self, action: #selector(importAttachmentFromSidebar))
        addAttachBtn.bezelStyle = .inline
        addAttachBtn.isBordered = false
        addAttachBtn.contentTintColor = .controlAccentColor
        addAttachBtn.font = .systemFont(ofSize: 12.0, weight: .medium)

        secHeader.addArrangedSubview(secTitle)
        secHeader.addArrangedSubview(headerSpacer)
        secHeader.addArrangedSubview(addAttachBtn)

        attachmentsListStack.orientation = .vertical
        attachmentsListStack.alignment = .leading
        attachmentsListStack.spacing = 8
        attachmentsListStack.translatesAutoresizingMaskIntoConstraints = false

        tabAttachmentsContainer.addArrangedSubview(secHeader)
        tabAttachmentsContainer.addArrangedSubview(attachmentsListStack)

        NSLayoutConstraint.activate([
            tabAttachmentsContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabAttachmentsContainer.widthAnchor),
            attachmentsListStack.widthAnchor.constraint(equalTo: tabAttachmentsContainer.widthAnchor)
        ])

        refreshAttachmentsTabUI()
    }

    // MARK: - Tab 4: 论文标签 (Tags)
    private func setupTagsTab(in parentStack: NSStackView) {
        tabTagsContainer.orientation = .vertical
        tabTagsContainer.alignment = .leading
        tabTagsContainer.spacing = 10
        tabTagsContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabTagsContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let secTitle = NSTextField(labelWithString: "标签")
        secTitle.font = .systemFont(ofSize: 13.0, weight: .semibold)
        secTitle.textColor = .labelColor

        tagsCountBadge.font = .systemFont(ofSize: 12.0)
        tagsCountBadge.textColor = .secondaryLabelColor

        secHeader.addArrangedSubview(secTitle)
        secHeader.addArrangedSubview(tagsCountBadge)

        let tagsCard = makeSidebarCardView()
        let tagsCardStack = FlippedStackView()
        tagsCardStack.orientation = .vertical
        tagsCardStack.alignment = .leading
        tagsCardStack.spacing = 8
        tagsCardStack.translatesAutoresizingMaskIntoConstraints = false
        tagsCard.contentView = tagsCardStack

        let currentTagsTitle = NSTextField(labelWithString: "当前标签")
        currentTagsTitle.font = .systemFont(ofSize: 11.5, weight: .bold)
        currentTagsTitle.textColor = .secondaryLabelColor

        tagsCardStack.addArrangedSubview(currentTagsTitle)
        tagsCardStack.addArrangedSubview(tagsFlowView)

        let addTagCard = makeSidebarCardView()
        let addTagStack = FlippedStackView()
        addTagStack.orientation = .vertical
        addTagStack.alignment = .leading
        addTagStack.spacing = 6
        addTagStack.translatesAutoresizingMaskIntoConstraints = false
        addTagCard.contentView = addTagStack

        let inputRow = NSStackView()
        inputRow.orientation = .horizontal
        inputRow.spacing = 6
        inputRow.alignment = .centerY
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        tagsInputField.placeholderString = "新标签…"
        tagsInputField.identifier = NSUserInterfaceItemIdentifier("readerTagInput")
        tagsInputField.controlSize = .small
        tagsInputField.target = self
        tagsInputField.action = #selector(addTagFromInput)
        tagsInputField.translatesAutoresizingMaskIntoConstraints = false
        tagsInputField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let addBtn = NSButton(title: "添加", target: self, action: #selector(addTagFromInput))
        addBtn.bezelStyle = .rounded
        addBtn.controlSize = .small
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.setContentHuggingPriority(.required, for: .horizontal)

        inputRow.addArrangedSubview(tagsInputField)
        inputRow.addArrangedSubview(addBtn)

        addTagStack.addArrangedSubview(inputRow)

        let suggestCard = makeSidebarCardView()
        let suggestStack = FlippedStackView()
        suggestStack.orientation = .vertical
        suggestStack.alignment = .leading
        suggestStack.spacing = 8
        suggestStack.translatesAutoresizingMaskIntoConstraints = false
        suggestCard.contentView = suggestStack

        let suggestTitle = NSTextField(labelWithString: "常用标签")
        suggestTitle.font = .systemFont(ofSize: 11.5, weight: .bold)
        suggestTitle.textColor = .secondaryLabelColor

        suggestStack.addArrangedSubview(suggestTitle)
        suggestStack.addArrangedSubview(suggestedTagsFlowView)

        tabTagsContainer.addArrangedSubview(secHeader)
        tabTagsContainer.addArrangedSubview(tagsCard)
        tabTagsContainer.addArrangedSubview(addTagCard)
        tabTagsContainer.addArrangedSubview(suggestCard)

        NSLayoutConstraint.activate([
            tabTagsContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabTagsContainer.widthAnchor),
            tagsCard.widthAnchor.constraint(equalTo: tabTagsContainer.widthAnchor),
            tagsFlowView.widthAnchor.constraint(equalTo: tagsCardStack.widthAnchor),

            addTagCard.widthAnchor.constraint(equalTo: tabTagsContainer.widthAnchor),
            inputRow.widthAnchor.constraint(equalTo: addTagStack.widthAnchor),

            suggestCard.widthAnchor.constraint(equalTo: tabTagsContainer.widthAnchor),
            suggestedTagsFlowView.widthAnchor.constraint(equalTo: suggestStack.widthAnchor)
        ])

        refreshTagsTabUI()
    }

    // MARK: - Tab 5: 外部链接与文献引用 (External Links)

    @discardableResult
    func addTags(_ text: String) -> Bool {
        guard var paper = currentPaper, let tags = LibraryViewController.metadataTags(from: text), !tags.isEmpty else { return false }
        for tag in tags where !paper.tags.contains(tag) { paper.tags.append(tag) }
        guard LibraryStore.shared.savePaper(paper) else { return false }
        refreshTagsTabUI()
        return true
    }

    static func detectedLanguage(in document: PDFDocument?) -> String {
        guard let document = document else { return "未识别" }
        let sample = (0..<min(document.pageCount, 2)).compactMap { document.page(at: $0)?.string }.joined(separator: " ")
        let text = String(sample.prefix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 20, let code = NSLinguisticTagger.dominantLanguage(for: text) else { return "未识别" }
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return "\(name)（PDF 自动识别）"
    }

    private func setupLinksTab(in parentStack: NSStackView) {
        tabLinksContainer.orientation = .vertical
        tabLinksContainer.alignment = .leading
        tabLinksContainer.spacing = 10
        tabLinksContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabLinksContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let secTitle = NSTextField(labelWithString: "链接与文献")
        secTitle.font = .systemFont(ofSize: 13.0, weight: .semibold)
        secTitle.textColor = .labelColor

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let addLinkBtn = NSButton(title: "＋ 添加…", target: self, action: #selector(promptAddCustomExternalLink))
        addLinkBtn.bezelStyle = .inline
        addLinkBtn.isBordered = false
        addLinkBtn.contentTintColor = .controlAccentColor
        addLinkBtn.font = .systemFont(ofSize: 12.0, weight: .medium)

        secHeader.addArrangedSubview(secTitle)
        secHeader.addArrangedSubview(headerSpacer)
        secHeader.addArrangedSubview(addLinkBtn)

        linksCardsStack.orientation = .vertical
        linksCardsStack.alignment = .leading
        linksCardsStack.spacing = 8
        linksCardsStack.translatesAutoresizingMaskIntoConstraints = false

        tabLinksContainer.addArrangedSubview(secHeader)
        tabLinksContainer.addArrangedSubview(linksCardsStack)

        NSLayoutConstraint.activate([
            tabLinksContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabLinksContainer.widthAnchor),
            linksCardsStack.widthAnchor.constraint(equalTo: tabLinksContainer.widthAnchor)
        ])

        refreshLinksDrawerView()
    }

    func updateRightSidebarMetadataUI() {
        guard let p = currentPaper else { return }
        sidebarPaperTitleLabel.stringValue = p.title
        sidebarPaperTitleLabel.toolTip = p.title

        metadataFieldsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        func addRow(key: String, value: String, isLink: Bool = false, linkAction: Selector? = nil) {
            let row = FlippedView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let keyLabel = NSTextField(labelWithString: key)
            keyLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
            keyLabel.textColor = .secondaryLabelColor
            keyLabel.alignment = .right
            keyLabel.translatesAutoresizingMaskIntoConstraints = false

            let valView: NSView
            if isLink {
                let btn = NSButton(title: value, target: self, action: linkAction ?? #selector(openArxivLinkFromSidebar))
                btn.bezelStyle = .inline
                btn.isBordered = false
                btn.contentTintColor = .controlAccentColor
                btn.font = .systemFont(ofSize: 12.0)
                btn.alignment = .left
                btn.translatesAutoresizingMaskIntoConstraints = false
                valView = btn
            } else {
                let valLabel = NSTextField(wrappingLabelWithString: value)
                valLabel.font = .systemFont(ofSize: 12.0)
                valLabel.textColor = .labelColor
                valLabel.isSelectable = true
                valLabel.translatesAutoresizingMaskIntoConstraints = false
                valView = valLabel
            }

            row.addSubview(keyLabel)
            row.addSubview(valView)

            NSLayoutConstraint.activate([
                keyLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                keyLabel.widthAnchor.constraint(equalToConstant: 52),
                keyLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),

                valView.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 10),
                valView.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
                valView.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
                valView.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2)
            ])
            metadataFieldsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: metadataFieldsStack.widthAnchor).isActive = true
        }

        let authorList = p.authors.components(separatedBy: CharacterSet(charactersIn: ";,，；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !authorList.isEmpty {
            let maxShow = 5
            for (idx, author) in authorList.prefix(maxShow).enumerated() {
                addRow(key: idx == 0 ? "作者" : "", value: author)
            }
            if authorList.count > maxShow {
                addRow(key: "", value: "还有 \(authorList.count - maxShow) 人…")
            }
        }

        if !p.category.isEmpty {
            addRow(key: "分类", value: p.category)
        }
        if !p.venue.isEmpty {
            addRow(key: "期刊", value: p.venue)
        }

        let aid = p.cleanArxivId ?? ""
        if !aid.isEmpty {
            addRow(key: "arXiv", value: aid)
        }
        if !p.year.isEmpty {
            addRow(key: "年份", value: p.year)
        }
        if !aid.isEmpty {
            addRow(key: "DOI", value: "10.48550/arXiv.\(aid)")
            addRow(key: "网址", value: "https://arxiv.org/abs/\(aid)", isLink: true, linkAction: #selector(openArxivLinkFromSidebar))
        }

        if let citations = p.citationCount {
            addRow(key: "引用", value: "\(citations.formatted()) 次")
        }
    }

    // MARK: - Tab 2: 翻译与学术解析 (Actions & UI Refresh)
    private func refreshTranslationTabUI() {
        if let result = sidebarTransLastResult {
            sidebarTransStatusLabel.stringValue = result.isSuccess ? "● 引擎：\(result.providerLabel)" : "● 翻译失败：\(result.providerLabel)"
            sidebarTransStatusLabel.textColor = result.isSuccess ? .secondaryLabelColor : .systemRed
            return
        }
        guard sidebarTransActiveTask == nil else { return }
        let model = LLMTranslationService.shared.modelName
        let isConfigured = LLMTranslationService.shared.isRemoteConfigured
        if isConfigured {
            sidebarTransStatusLabel.stringValue = "● 引擎: \(model) (已配置)"
            sidebarTransStatusLabel.textColor = NSColor(calibratedRed: 0.1, green: 0.65, blue: 0.25, alpha: 1.0)
        } else {
            sidebarTransStatusLabel.stringValue = "● 本地引擎: 双栏对照内置解析 (未配置 API Key)"
            sidebarTransStatusLabel.textColor = .secondaryLabelColor
        }

        if sidebarTransResultMarkdown.isEmpty {
            sidebarTransResultWebView.loadHTMLString("", baseURL: nil)
        }
    }

    @objc private func openTranslationSettingsModal() {
        LLMTranslationService.shared.presentSettingsModal(from: view.window) { [weak self] in
            self?.refreshTranslationTabUI()
        }
    }

    @objc private func sidebarTransModeChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: currentTranslationMode = .academicChinese
        case 1: currentTranslationMode = .explainAndFormula
        case 2: currentTranslationMode = .conciseSummary
        default: currentTranslationMode = .englishPolish
        }
        if !sidebarTransSourceTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sidebarTranslateAction()
        }
    }

    @objc private func sidebarTranslateAction() {
        let rawText = sidebarTransSourceTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }

        sidebarTransRequestID = UUID()
        let requestID = sidebarTransRequestID
        sidebarTransResultMarkdown = ""
        sidebarTransLastResult = nil
        sidebarTransActionButtons.forEach { $0.isEnabled = false }
        sidebarTransStatusLabel.stringValue = "● 正在生成结果…"
        sidebarTransStatusLabel.textColor = .secondaryLabelColor
        sidebarTransProgress.startAnimation(nil)
        let loadingHTML = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: "*正在调用学术大模型进行翻译与术语解析…*")
        sidebarTransResultWebView.loadHTMLString(loadingHTML, baseURL: nil)

        sidebarTransActiveTask?.cancel()
        sidebarTransActiveTask = LLMTranslationService.shared.translate(
            text: rawText,
            mode: currentTranslationMode,
            pairedPageText: nil
        ) { [weak self] result in
            guard let self = self, !self.isClosed else { return }
            guard self.sidebarTransRequestID == requestID else { return }
            self.sidebarTransActiveTask = nil
            self.sidebarTransProgress.stopAnimation(nil)
            self.sidebarTransResultMarkdown = result.isSuccess ? result.translatedMarkdown : ""
            self.sidebarTransActionButtons.forEach { $0.isEnabled = result.isSuccess }
            self.sidebarTransLastResult = result
            self.refreshTranslationTabUI()
            let html = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: result.translatedMarkdown)
            self.sidebarTransResultWebView.loadHTMLString(html, baseURL: nil)
        }
    }

    @objc private func sidebarTranslateCurrentPageAction() {
        let col = primaryActiveColumn()
        guard let page = col.pdfView.currentPage, let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pageText.isEmpty else {
            return
        }
        sidebarTransSourceTextView.string = String(pageText.prefix(2500))
        sidebarTranslateAction()
    }

    @objc private func sidebarClearTransSourceAction() {
        sidebarTransRequestID = UUID()
        sidebarTransActiveTask?.cancel()
        sidebarTransActiveTask = nil
        sidebarTransProgress.stopAnimation(nil)
        sidebarTransSourceTextView.string = ""
        sidebarTransResultMarkdown = ""
        sidebarTransLastResult = nil
        sidebarTransActionButtons.forEach { $0.isEnabled = false }
        refreshTranslationTabUI()
    }

    @objc private func sidebarCopyTranslationAction() {
        guard !sidebarTransResultMarkdown.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sidebarTransResultMarkdown, forType: .string)
    }

    @objc private func sidebarInsertTranslationToNoteAction() {
        guard !sidebarTransResultMarkdown.isEmpty else { return }
        let src = sidebarTransSourceTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet: String
        if !src.isEmpty {
            let quoted = src.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
            snippet = "\n\n\(quoted)\n\n\(sidebarTransResultMarkdown)\n"
        } else {
            snippet = "\n\n\(sidebarTransResultMarkdown)\n"
        }
        openNotesSidebar()
        sidebarNoteView.appendOrInsertMarkdownLink(snippet)
    }

    // MARK: - Tab 3: PDF 附件与文档 (Actions & UI Refresh)
    private func refreshAttachmentsTabUI() {
        attachmentsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let p = currentPaper else { return }

        // --- Section 1: 核心 PDF 文档 ---
        let coreHeader = NSTextField(labelWithString: "核心论文 PDF")
        coreHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
        coreHeader.textColor = .secondaryLabelColor
        attachmentsListStack.addArrangedSubview(coreHeader)

        let folder = LibraryStore.shared.folderURL(for: p.id)

        // 1) 原版 PDF 卡片
        let origCard = makeSidebarCardView()
        let origStack = FlippedStackView()
        origStack.orientation = .vertical
        origStack.alignment = .leading
        origStack.spacing = 6
        origStack.translatesAutoresizingMaskIntoConstraints = false
        origCard.contentView = origStack

        let origTopRow = NSStackView()
        origTopRow.orientation = .horizontal
        origTopRow.alignment = .centerY
        origTopRow.spacing = 6
        origTopRow.translatesAutoresizingMaskIntoConstraints = false

        let origIcon = NSImageView()
        origIcon.image = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14.0, weight: .medium))
        origIcon.contentTintColor = .controlAccentColor

        let origTitle = NSTextField(labelWithString: "原版 PDF")
        origTitle.font = .systemFont(ofSize: 12.0, weight: .semibold)

        let origSpacer = NSView()
        origSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        origTopRow.addArrangedSubview(origIcon)
        origTopRow.addArrangedSubview(origTitle)
        origTopRow.addArrangedSubview(origSpacer)

        let origDetails: NSTextField
        let origBtnRow = NSStackView()
        origBtnRow.orientation = .horizontal
        origBtnRow.spacing = 8
        origBtnRow.translatesAutoresizingMaskIntoConstraints = false

        if let origFn = p.originalFilename {
            let origPath = folder.appendingPathComponent(origFn).path
            let sizeStr = formattedFileSize(at: origPath)
            origDetails = NSTextField(labelWithString: "\(origFn) · \(sizeStr)")
            origDetails.font = .systemFont(ofSize: 11.0)
            origDetails.textColor = .secondaryLabelColor
            origDetails.lineBreakMode = .byTruncatingMiddle
            origDetails.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let revealBtn = makeCompactActionButton(title: "Finder", symbol: "folder", action: #selector(revealOriginalInFinder))
            let replaceBtn = makeCompactActionButton(title: "替换…", symbol: "arrow.triangle.2.circlepath", action: #selector(importOrigPDFFromSidebar))
            origBtnRow.addArrangedSubview(revealBtn)
            origBtnRow.addArrangedSubview(replaceBtn)
        } else {
            origDetails = NSTextField(labelWithString: "未绑定")
            origDetails.font = .systemFont(ofSize: 11.0)
            origDetails.textColor = .placeholderTextColor

            let addBtn = makeCompactActionButton(title: "导入…", symbol: "plus", action: #selector(importOrigPDFFromSidebar))
            origBtnRow.addArrangedSubview(addBtn)
        }

        origStack.addArrangedSubview(origTopRow)
        origStack.addArrangedSubview(origDetails)
        origStack.addArrangedSubview(origBtnRow)
        attachmentsListStack.addArrangedSubview(origCard)
        origCard.widthAnchor.constraint(equalTo: attachmentsListStack.widthAnchor).isActive = true
        origTopRow.widthAnchor.constraint(equalTo: origStack.widthAnchor).isActive = true
        origDetails.widthAnchor.constraint(equalTo: origStack.widthAnchor).isActive = true

        // 2) 中文译版 PDF 卡片
        let transCard = makeSidebarCardView()
        let transStack = FlippedStackView()
        transStack.orientation = .vertical
        transStack.alignment = .leading
        transStack.spacing = 6
        transStack.translatesAutoresizingMaskIntoConstraints = false
        transCard.contentView = transStack

        let transTopRow = NSStackView()
        transTopRow.orientation = .horizontal
        transTopRow.alignment = .centerY
        transTopRow.spacing = 6
        transTopRow.translatesAutoresizingMaskIntoConstraints = false

        let transIcon = NSImageView()
        transIcon.image = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14.0, weight: .medium))
        transIcon.contentTintColor = NSColor.systemGreen

        let transTitle = NSTextField(labelWithString: "中文译版")
        transTitle.font = .systemFont(ofSize: 12.0, weight: .semibold)

        let transSpacer = NSView()
        transSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        transTopRow.addArrangedSubview(transIcon)
        transTopRow.addArrangedSubview(transTitle)
        transTopRow.addArrangedSubview(transSpacer)

        let transDetails: NSTextField
        let transBtnRow = NSStackView()
        transBtnRow.orientation = .horizontal
        transBtnRow.spacing = 8
        transBtnRow.translatesAutoresizingMaskIntoConstraints = false

        if let transFn = p.translatedFilename {
            let transPath = folder.appendingPathComponent(transFn).path
            let sizeStr = formattedFileSize(at: transPath)
            transDetails = NSTextField(labelWithString: "\(transFn) · \(sizeStr)")
            transDetails.font = .systemFont(ofSize: 11.0)
            transDetails.textColor = .secondaryLabelColor
            transDetails.lineBreakMode = .byTruncatingMiddle
            transDetails.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let revealBtn = makeCompactActionButton(title: "Finder", symbol: "folder", action: #selector(revealTranslatedInFinder))
            let replaceBtn = makeCompactActionButton(title: "替换…", symbol: "arrow.triangle.2.circlepath", action: #selector(importTransPDFFromSidebar))
            let removeBtn = makeCompactActionButton(title: "移除", symbol: "trash", action: #selector(removeTranslatedPDFFindFromSidebar), tint: .systemRed)

            transBtnRow.addArrangedSubview(revealBtn)
            transBtnRow.addArrangedSubview(replaceBtn)
            transBtnRow.addArrangedSubview(removeBtn)
        } else {
            transDetails = NSTextField(labelWithString: "未导入")
            transDetails.font = .systemFont(ofSize: 11.0)
            transDetails.textColor = .placeholderTextColor

            let addBtn = makeCompactActionButton(title: "导入…", symbol: "plus", action: #selector(importTransPDFFromSidebar))
            transBtnRow.addArrangedSubview(addBtn)
        }

        transStack.addArrangedSubview(transTopRow)
        transStack.addArrangedSubview(transDetails)
        transStack.addArrangedSubview(transBtnRow)
        attachmentsListStack.addArrangedSubview(transCard)
        transCard.widthAnchor.constraint(equalTo: attachmentsListStack.widthAnchor).isActive = true
        transTopRow.widthAnchor.constraint(equalTo: transStack.widthAnchor).isActive = true
        transDetails.widthAnchor.constraint(equalTo: transStack.widthAnchor).isActive = true

        // --- Section 2: 附加文件列表 (Local files) ---
        let localResources = p.resources.filter { $0.isLocalFile }
        if !localResources.isEmpty {
            let attachHeader = NSTextField(labelWithString: "附加文件 (\(localResources.count))")
            attachHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
            attachHeader.textColor = .secondaryLabelColor
            attachmentsListStack.addArrangedSubview(attachHeader)

            for res in localResources {
                let card = makeSidebarCardView()
                let cStack = FlippedStackView()
                cStack.orientation = .vertical
                cStack.alignment = .leading
                cStack.spacing = 5
                cStack.translatesAutoresizingMaskIntoConstraints = false
                card.contentView = cStack

                let topRow = NSStackView()
                topRow.orientation = .horizontal
                topRow.alignment = .centerY
                topRow.spacing = 6
                topRow.translatesAutoresizingMaskIntoConstraints = false

                let ext = (res.urlOrPath as NSString).pathExtension.lowercased()
                let iconName: String
                switch ext {
                case "pdf": iconName = "doc.fill"
                case "zip", "tar", "gz", "7z": iconName = "archivebox.fill"
                case "py", "sh", "swift", "cpp", "c", "js", "ts": iconName = "curlybraces"
                case "png", "jpg", "jpeg", "svg": iconName = "photo.fill"
                default: iconName = "paperclip"
                }
                let iconView = NSImageView()
                iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13.0, weight: .medium))
                iconView.contentTintColor = .secondaryLabelColor

                let nameLbl = NSTextField(labelWithString: res.title)
                nameLbl.font = .systemFont(ofSize: 12.0, weight: .medium)
                nameLbl.lineBreakMode = .byTruncatingMiddle
                nameLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

                topRow.addArrangedSubview(iconView)
                topRow.addArrangedSubview(nameLbl)
                topRow.addArrangedSubview(spacer)

                let sizeStr = formattedFileSize(at: res.urlOrPath)
                let detailLbl = NSTextField(labelWithString: "大小: \(sizeStr)")
                detailLbl.font = .systemFont(ofSize: 11.0)
                detailLbl.textColor = .tertiaryLabelColor
                detailLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let btnRow = NSStackView()
                btnRow.orientation = .horizontal
                btnRow.spacing = 8
                btnRow.translatesAutoresizingMaskIntoConstraints = false

                let openBtn = NSButton(title: "打开", target: self, action: #selector(openAttachmentFileFromBtn(_:)))
                openBtn.bezelStyle = .inline
                openBtn.isBordered = false
                openBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
                openBtn.contentTintColor = .controlAccentColor
                openBtn.identifier = NSUserInterfaceItemIdentifier(res.urlOrPath)

                let finderBtn = NSButton(title: "Finder", target: self, action: #selector(revealAttachmentInFinderFromBtn(_:)))
                finderBtn.bezelStyle = .inline
                finderBtn.isBordered = false
                finderBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
                finderBtn.contentTintColor = .secondaryLabelColor
                finderBtn.identifier = NSUserInterfaceItemIdentifier(res.urlOrPath)

                let delBtn = NSButton(title: "删除", target: self, action: #selector(deleteAttachmentFromBtn(_:)))
                delBtn.bezelStyle = .inline
                delBtn.isBordered = false
                delBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
                delBtn.contentTintColor = .systemRed
                delBtn.identifier = NSUserInterfaceItemIdentifier(res.id)

                btnRow.addArrangedSubview(openBtn)
                btnRow.addArrangedSubview(finderBtn)
                btnRow.addArrangedSubview(delBtn)

                cStack.addArrangedSubview(topRow)
                cStack.addArrangedSubview(detailLbl)
                cStack.addArrangedSubview(btnRow)

                attachmentsListStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: attachmentsListStack.widthAnchor).isActive = true
                topRow.widthAnchor.constraint(equalTo: cStack.widthAnchor).isActive = true
                detailLbl.widthAnchor.constraint(equalTo: cStack.widthAnchor).isActive = true
                card.widthAnchor.constraint(equalTo: attachmentsListStack.widthAnchor).isActive = true
            }
        }
    }

    @objc private func importOrigPDFFromSidebar() {
        promptToImportOrReplacePDF(in: leftCol)
    }

    @objc private func importTransPDFFromSidebar() {
        promptToImportOrReplacePDF(in: rightCol)
    }

    @objc private func importAttachmentFromSidebar() {
        guard let p = currentPaper else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要导入到该条目的附件文件"
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            _ = LibraryStore.shared.importAttachmentFile(for: p.id, from: url)
        }
        refreshAttachmentsTabUI()
    }

    @objc private func revealOriginalInFinder() {
        guard let p = currentPaper, let fn = p.originalFilename else { return }
        let path = LibraryStore.shared.folderURL(for: p.id).appendingPathComponent(fn)
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    @objc private func revealTranslatedInFinder() {
        guard let p = currentPaper, let fn = p.translatedFilename else { return }
        let path = LibraryStore.shared.folderURL(for: p.id).appendingPathComponent(fn)
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    @objc private func removeTranslatedPDFFindFromSidebar() {
        guard let p = currentPaper else { return }
        LibraryStore.shared.removeTranslatedPDF(for: p.id)
        rightCol.pdfView.document = nil
        refreshAttachmentsTabUI()
    }

    @objc private func openAttachmentFileFromBtn(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func revealAttachmentInFinderFromBtn(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func deleteAttachmentFromBtn(_ sender: NSButton) {
        guard let resId = sender.identifier?.rawValue, let p = currentPaper else { return }
        LibraryStore.shared.deleteExternalResource(for: p.id, resourceId: resId)
        refreshAttachmentsTabUI()
    }

    // MARK: - Tab 4: 论文标签 (Actions & UI Refresh)
    private func refreshTagsTabUI() {
        guard let p = currentPaper else { return }

        tagsCountBadge.stringValue = "(\(p.tags.count))"

        if p.tags.isEmpty {
            let emptyLbl = NSTextField(labelWithString: "暂无标签")
            emptyLbl.font = .systemFont(ofSize: 11.5)
            emptyLbl.textColor = .placeholderTextColor
            emptyLbl.isBezeled = false
            emptyLbl.isEditable = false
            emptyLbl.drawsBackground = false
            tagsFlowView.setViews([emptyLbl])
        } else {
            let chips = p.tags.map { tag in
                ModernTagChipView(tag: tag) { [weak self] in
                    guard let self = self, let paper = self.currentPaper else { return }
                    LibraryStore.shared.removeTag(tag, for: paper.id)
                    self.refreshTagsTabUI()
                }
            }
            tagsFlowView.setViews(chips)
        }

        let availableTags = LibraryStore.shared.allUniqueTags.filter { !p.tags.contains($0) }
        if availableTags.isEmpty {
            let emptyLbl = NSTextField(labelWithString: "暂无推荐标签")
            emptyLbl.font = .systemFont(ofSize: 11.5)
            emptyLbl.textColor = .placeholderTextColor
            emptyLbl.isBezeled = false
            emptyLbl.isEditable = false
            emptyLbl.drawsBackground = false
            suggestedTagsFlowView.setViews([emptyLbl])
        } else {
            let buttons = availableTags.prefix(12).map { tag -> NSButton in
                let btn = ModernHoverButton(title: "＋ \(tag)")
                btn.font = .systemFont(ofSize: 11.5, weight: .medium)
                btn.normalTintColor = .controlAccentColor
                btn.hoverTintColor = .controlAccentColor
                btn.hoverBgColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
                btn.cornerRadius = 4
                btn.identifier = NSUserInterfaceItemIdentifier(tag)
                btn.target = self
                btn.action = #selector(addSuggestedTagFromBtn(_:))
                return btn
            }
            suggestedTagsFlowView.setViews(buttons)
        }
    }

    @objc private func addTagFromInput() {
        guard addTags(tagsInputField.stringValue) else { return }
        tagsInputField.stringValue = ""
    }

    @objc private func removeTagFromBtn(_ sender: NSButton) {
        guard let tag = sender.identifier?.rawValue, let p = currentPaper else { return }
        LibraryStore.shared.removeTag(tag, for: p.id)
        refreshTagsTabUI()
    }

    @objc private func addSuggestedTagFromBtn(_ sender: NSButton) {
        guard let tag = sender.identifier?.rawValue, let p = currentPaper else { return }
        LibraryStore.shared.addTag(tag, for: p.id)
        refreshTagsTabUI()
    }

    // MARK: - Tab 5: 外部链接与文献引用 (Actions & UI Refresh)
    private func refreshLinksDrawerView() {
        linksCardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let p = currentPaper else { return }

        // --- Section 1: 官方学术导航 ---
        let navHeader = NSTextField(labelWithString: "学术文献")
        navHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
        navHeader.textColor = .secondaryLabelColor
        linksCardsStack.addArrangedSubview(navHeader)

        let aid = p.cleanArxivId ?? ""

        // 1) arXiv 官方主页卡片
        let arxivCard = makeSidebarCardView()
        let arxivStack = FlippedStackView()
        arxivStack.orientation = .vertical
        arxivStack.alignment = .leading
        arxivStack.spacing = 5
        arxivStack.translatesAutoresizingMaskIntoConstraints = false
        arxivCard.contentView = arxivStack

        let arxivTopRow = NSStackView()
        arxivTopRow.orientation = .horizontal
        arxivTopRow.alignment = .centerY
        arxivTopRow.spacing = 6
        arxivTopRow.translatesAutoresizingMaskIntoConstraints = false

        let arxivIcon = NSImageView()
        arxivIcon.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13.0, weight: .medium))
        arxivIcon.contentTintColor = .controlAccentColor

        let arxivTitle = NSTextField(labelWithString: "arXiv")
        arxivTitle.font = .systemFont(ofSize: 12.0, weight: .semibold)

        let arxivSpacer = NSView()
        arxivSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        arxivTopRow.addArrangedSubview(arxivIcon)
        arxivTopRow.addArrangedSubview(arxivTitle)
        arxivTopRow.addArrangedSubview(arxivSpacer)

        let arxivUrlLbl: NSTextField
        let arxivBtnRow = NSStackView()
        arxivBtnRow.orientation = .horizontal
        arxivBtnRow.spacing = 8
        arxivBtnRow.translatesAutoresizingMaskIntoConstraints = false

        if !aid.isEmpty {
            let urlStr = "https://arxiv.org/abs/\(aid)"
            arxivUrlLbl = NSTextField(labelWithString: urlStr)
            arxivUrlLbl.font = .systemFont(ofSize: 11.0)
            arxivUrlLbl.textColor = .secondaryLabelColor
            arxivUrlLbl.lineBreakMode = .byTruncatingMiddle

            let openBtn = makeCompactActionButton(title: "打开", symbol: "safari", action: #selector(openArxivLinkFromSidebar))
            let copyBtn = makeCompactActionButton(title: "复制", symbol: "doc.on.doc", action: #selector(copyArxivLinkFromSidebar))
            arxivBtnRow.addArrangedSubview(openBtn)
            arxivBtnRow.addArrangedSubview(copyBtn)
        } else {
            arxivUrlLbl = NSTextField(labelWithString: "未关联 arXiv ID")
            arxivUrlLbl.font = .systemFont(ofSize: 11.0)
            arxivUrlLbl.textColor = .placeholderTextColor

            let bindBtn = makeCompactActionButton(title: "绑定…", symbol: "plus", action: #selector(promptBindArxivId))
            arxivBtnRow.addArrangedSubview(bindBtn)
        }

        arxivStack.addArrangedSubview(arxivTopRow)
        arxivStack.addArrangedSubview(arxivUrlLbl)
        arxivStack.addArrangedSubview(arxivBtnRow)
        linksCardsStack.addArrangedSubview(arxivCard)
        arxivCard.widthAnchor.constraint(equalTo: linksCardsStack.widthAnchor).isActive = true
        arxivTopRow.widthAnchor.constraint(equalTo: arxivStack.widthAnchor).isActive = true
        arxivUrlLbl.widthAnchor.constraint(equalTo: arxivStack.widthAnchor).isActive = true
        arxivUrlLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 2) 幻觉翻译卡片
        if !aid.isEmpty {
            let hjfyCard = makeSidebarCardView()
            let hjfyStack = FlippedStackView()
            hjfyStack.orientation = .vertical
            hjfyStack.alignment = .leading
            hjfyStack.spacing = 5
            hjfyStack.translatesAutoresizingMaskIntoConstraints = false
            hjfyCard.contentView = hjfyStack

            let hjfyTopRow = NSStackView()
            hjfyTopRow.orientation = .horizontal
            hjfyTopRow.alignment = .centerY
            hjfyTopRow.spacing = 6
            hjfyTopRow.translatesAutoresizingMaskIntoConstraints = false

            let hjfyIcon = NSImageView()
            hjfyIcon.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13.0, weight: .medium))
            hjfyIcon.contentTintColor = NSColor.systemIndigo

            let hjfyTitle = NSTextField(labelWithString: "幻觉翻译")
            hjfyTitle.font = .systemFont(ofSize: 12.0, weight: .semibold)

            let hjfySpacer = NSView()
            hjfySpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            hjfyTopRow.addArrangedSubview(hjfyIcon)
            hjfyTopRow.addArrangedSubview(hjfyTitle)
            hjfyTopRow.addArrangedSubview(hjfySpacer)

            let urlStr = "https://hjfy.top/arxiv/\(aid)"
            let hjfyUrlLbl = NSTextField(labelWithString: urlStr)
            hjfyUrlLbl.font = .systemFont(ofSize: 11.0)
            hjfyUrlLbl.textColor = .secondaryLabelColor
            hjfyUrlLbl.lineBreakMode = .byTruncatingMiddle
            hjfyUrlLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let hjfyBtnRow = NSStackView()
            hjfyBtnRow.orientation = .horizontal
            hjfyBtnRow.spacing = 8
            hjfyBtnRow.translatesAutoresizingMaskIntoConstraints = false

            let openBtn = makeCompactActionButton(title: "前往", symbol: "safari", action: #selector(openHjfyLinkFromSidebar))
            let copyBtn = makeCompactActionButton(title: "复制", symbol: "doc.on.doc", action: #selector(copyHjfyLinkFromSidebar))
            hjfyBtnRow.addArrangedSubview(openBtn)
            hjfyBtnRow.addArrangedSubview(copyBtn)

            hjfyStack.addArrangedSubview(hjfyTopRow)
            hjfyStack.addArrangedSubview(hjfyUrlLbl)
            hjfyStack.addArrangedSubview(hjfyBtnRow)
            linksCardsStack.addArrangedSubview(hjfyCard)
            hjfyCard.widthAnchor.constraint(equalTo: linksCardsStack.widthAnchor).isActive = true
            hjfyTopRow.widthAnchor.constraint(equalTo: hjfyStack.widthAnchor).isActive = true
            hjfyUrlLbl.widthAnchor.constraint(equalTo: hjfyStack.widthAnchor).isActive = true

            // 3) DOI 官方出版链接
            let doiCard = makeSidebarCardView()
            let doiStack = FlippedStackView()
            doiStack.orientation = .vertical
            doiStack.alignment = .leading
            doiStack.spacing = 5
            doiStack.translatesAutoresizingMaskIntoConstraints = false
            doiCard.contentView = doiStack

            let doiTitle = NSTextField(labelWithString: "DOI")
            doiTitle.font = .systemFont(ofSize: 12.0, weight: .semibold)

            let doiUrl = "https://doi.org/10.48550/arXiv.\(aid)"
            let doiLbl = NSTextField(labelWithString: doiUrl)
            doiLbl.font = .systemFont(ofSize: 11.0)
            doiLbl.textColor = .secondaryLabelColor
            doiLbl.lineBreakMode = .byTruncatingMiddle
            doiLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let doiBtnRow = NSStackView()
            doiBtnRow.orientation = .horizontal
            doiBtnRow.spacing = 8
            doiBtnRow.translatesAutoresizingMaskIntoConstraints = false

            let doiOpenBtn = NSButton(title: "打开", target: self, action: #selector(openDoiLinkFromSidebar))
            doiOpenBtn.bezelStyle = .inline
            doiOpenBtn.isBordered = false
            doiOpenBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
            doiOpenBtn.contentTintColor = .controlAccentColor

            let doiCopyBtn = NSButton(title: "复制", target: self, action: #selector(copyDoiLinkFromSidebar))
            doiCopyBtn.bezelStyle = .inline
            doiCopyBtn.isBordered = false
            doiCopyBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
            doiCopyBtn.contentTintColor = .controlAccentColor

            doiBtnRow.addArrangedSubview(doiOpenBtn)
            doiBtnRow.addArrangedSubview(doiCopyBtn)

            doiStack.addArrangedSubview(doiTitle)
            doiStack.addArrangedSubview(doiLbl)
            doiStack.addArrangedSubview(doiBtnRow)

            linksCardsStack.addArrangedSubview(doiCard)
            doiCard.widthAnchor.constraint(equalTo: linksCardsStack.widthAnchor).isActive = true
            doiTitle.widthAnchor.constraint(equalTo: doiStack.widthAnchor).isActive = true
            doiLbl.widthAnchor.constraint(equalTo: doiStack.widthAnchor).isActive = true
        }

        // --- Section 2: 自定义外部链接 ---
        let customLinks = p.resources.filter { !$0.isLocalFile }
        if !customLinks.isEmpty {
            let customHeader = NSTextField(labelWithString: "外部链接 (\(customLinks.count))")
            customHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
            customHeader.textColor = .secondaryLabelColor
            linksCardsStack.addArrangedSubview(customHeader)

            for res in customLinks {
                let card = makeSidebarCardView()
                let cStack = FlippedStackView()
                cStack.orientation = .vertical
                cStack.alignment = .leading
                cStack.spacing = 5
                cStack.translatesAutoresizingMaskIntoConstraints = false
                card.contentView = cStack

                let topRow = NSStackView()
                topRow.orientation = .horizontal
                topRow.alignment = .centerY
                topRow.spacing = 6
                topRow.translatesAutoresizingMaskIntoConstraints = false

                let iconView = NSImageView()
                iconView.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13.0, weight: .medium))
                iconView.contentTintColor = .controlAccentColor

                let nameLbl = NSTextField(labelWithString: res.title)
                nameLbl.font = .systemFont(ofSize: 12.0, weight: .semibold)
                nameLbl.lineBreakMode = .byTruncatingTail
                nameLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

                topRow.addArrangedSubview(iconView)
                topRow.addArrangedSubview(nameLbl)
                topRow.addArrangedSubview(spacer)

                let urlLbl = NSTextField(labelWithString: res.urlOrPath)
                urlLbl.font = .systemFont(ofSize: 11.0)
                urlLbl.textColor = .secondaryLabelColor
                urlLbl.lineBreakMode = .byTruncatingMiddle
                urlLbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

                let btnRow = NSStackView()
                btnRow.orientation = .horizontal
                btnRow.spacing = 8
                btnRow.translatesAutoresizingMaskIntoConstraints = false

                let openBtn = NSButton(title: "打开", target: self, action: #selector(openCustomLinkFromBtn(_:)))
                openBtn.bezelStyle = .inline
                openBtn.isBordered = false
                openBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
                openBtn.contentTintColor = .controlAccentColor
                openBtn.identifier = NSUserInterfaceItemIdentifier(res.urlOrPath)

                let copyBtn = NSButton(title: "复制", target: self, action: #selector(copyCustomLinkFromBtn(_:)))
                copyBtn.bezelStyle = .inline
                copyBtn.isBordered = false
                copyBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
                copyBtn.contentTintColor = .controlAccentColor
                copyBtn.identifier = NSUserInterfaceItemIdentifier(res.urlOrPath)

                let delBtn = NSButton(title: "删除", target: self, action: #selector(deleteCustomLinkFromBtn(_:)))
                delBtn.bezelStyle = .inline
                delBtn.isBordered = false
                delBtn.font = .systemFont(ofSize: 11.5, weight: .medium)
                delBtn.contentTintColor = .systemRed
                delBtn.identifier = NSUserInterfaceItemIdentifier(res.id)

                btnRow.addArrangedSubview(openBtn)
                btnRow.addArrangedSubview(copyBtn)
                btnRow.addArrangedSubview(delBtn)

                cStack.addArrangedSubview(topRow)
                cStack.addArrangedSubview(urlLbl)
                cStack.addArrangedSubview(btnRow)

                linksCardsStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: linksCardsStack.widthAnchor).isActive = true
                topRow.widthAnchor.constraint(equalTo: cStack.widthAnchor).isActive = true
                urlLbl.widthAnchor.constraint(equalTo: cStack.widthAnchor).isActive = true
            }
        }

        // --- Section 3: 关联文献 ---
        if !p.relatedPapers.isEmpty {
            let relHeader = NSTextField(labelWithString: "关联文献 (\(p.relatedPapers.count))")
            relHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
            relHeader.textColor = .secondaryLabelColor
            linksCardsStack.addArrangedSubview(relHeader)

            for rel in p.relatedPapers {
                let targetTitle = LibraryStore.shared.paper(withId: rel.targetPaperId)?.title ?? rel.targetPaperId
                let card = makeDrawerResourceCard(
                    symbol: "doc.on.doc.fill",
                    title: targetTitle,
                    subtitle: rel.relationNote.isEmpty ? "点击在新标签页打开" : rel.relationNote,
                    openId: rel.targetPaperId,
                    openAction: #selector(openRelatedPaperFromDrawer(_:)),
                    removeId: rel.targetPaperId,
                    removeAction: #selector(unlinkRelatedFromDrawer(_:))
                )
                linksCardsStack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: linksCardsStack.widthAnchor).isActive = true
            }
        }

        let addRelBtn = NSButton(title: "＋ 关联文献…", target: self, action: #selector(addRelatedPaperInDrawer))
        addRelBtn.bezelStyle = .rounded
        addRelBtn.controlSize = .small
        linksCardsStack.addArrangedSubview(addRelBtn)
    }

    private func makeDrawerResourceCard(
        symbol: String,
        title: String,
        subtitle: String,
        openId: String,
        openAction: Selector,
        removeId: String,
        removeAction: Selector
    ) -> NSView {
        let card = makeSidebarCardView(padding: NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10))
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)

        let titleBtn = NSButton(title: title, target: self, action: openAction)
        titleBtn.isBordered = false
        titleBtn.font = .systemFont(ofSize: 12, weight: .semibold)
        titleBtn.contentTintColor = .labelColor
        titleBtn.alignment = .left
        titleBtn.identifier = NSUserInterfaceItemIdentifier(openId)

        let subLbl = NSTextField(labelWithString: subtitle)
        subLbl.font = .systemFont(ofSize: 10.5)
        subLbl.textColor = .secondaryLabelColor
        subLbl.lineBreakMode = .byTruncatingMiddle

        let vStack = NSStackView(views: [titleBtn, subLbl])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 2

        let delBtn = NSButton()
        delBtn.bezelStyle = .inline
        delBtn.isBordered = false
        delBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "删除关联")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        delBtn.contentTintColor = .secondaryLabelColor
        delBtn.target = self
        delBtn.action = removeAction
        delBtn.identifier = NSUserInterfaceItemIdentifier(removeId)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, vStack, spacer, delBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        card.contentView = row
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return card
    }

    @objc private func openRelatedPaperFromDrawer(_ sender: NSButton) {
        if let targetId = sender.identifier?.rawValue {
            onRequestOpenPaperTab?(targetId)
        }
    }

    @objc private func openArxivLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId, let url = URL(string: "https://arxiv.org/abs/\(aid)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyArxivLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://arxiv.org/abs/\(aid)", forType: .string)
    }

    @objc private func openHjfyLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId, let url = URL(string: "https://hjfy.top/arxiv/\(aid)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyHjfyLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://hjfy.top/arxiv/\(aid)", forType: .string)
    }

    @objc private func openDoiLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId, let url = URL(string: "https://doi.org/10.48550/arXiv.\(aid)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyDoiLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://doi.org/10.48550/arXiv.\(aid)", forType: .string)
    }

    @objc private func promptBindArxivId() {
        guard var p = currentPaper else { return }
        let alert = NSAlert()
        alert.messageText = "绑定 arXiv ID"
        alert.informativeText = "输入论文的 arXiv ID (例如: 1706.03762v7 或 1706.03762)："
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "1706.03762"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let aid = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !aid.isEmpty {
                p.arxivId = aid
                LibraryStore.shared.savePaper(p, notify: true)
                refreshLinksDrawerView()
                updateRightSidebarMetadataUI()
            }
        }
    }

    @objc private func promptAddCustomExternalLink() {
        guard let p = currentPaper else { return }
        let alert = NSAlert()
        alert.messageText = "添加外部链接"
        alert.informativeText = "输入链接标题与完整 URL 地址 (如 GitHub 源码、项目主页等)："
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.frame = NSRect(x: 0, y: 0, width: 300, height: 60)

        let titleInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        titleInput.placeholderString = "链接标题 (如: GitHub 官方开源代码)"

        let urlInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        urlInput.placeholderString = "https://github.com/..."

        container.addArrangedSubview(titleInput)
        container.addArrangedSubview(urlInput)
        alert.accessoryView = container

        if alert.runModal() == .alertFirstButtonReturn {
            let title = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                LibraryStore.shared.addExternalLink(for: p.id, title: title, url: url)
                refreshLinksDrawerView()
            }
        }
    }

    @objc private func openCustomLinkFromBtn(_ sender: NSButton) {
        guard let urlStr = sender.identifier?.rawValue, let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyCustomLinkFromBtn(_ sender: NSButton) {
        guard let urlStr = sender.identifier?.rawValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlStr, forType: .string)
    }

    @objc private func deleteCustomLinkFromBtn(_ sender: NSButton) {
        guard let resId = sender.identifier?.rawValue, let p = currentPaper else { return }
        LibraryStore.shared.deleteExternalResource(for: p.id, resourceId: resId)
        refreshLinksDrawerView()
    }

    @objc private func refreshMetadataAndCitationsAction() {
        guard let p = currentPaper else { return }
        LibraryStore.shared.refreshPaperArxivMetadata(paperId: p.id) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRightSidebarMetadataUI()
            }
        }
    }

    @objc func toggleLeftSidebarAction() {
        toggleOutlineSidebar(for: primaryActiveColumn())
    }

    func toggleOutlineSidebar(for column: CleanPDFColumnView) {
        isLeftOverlayOpen.toggle()
        if isLeftOverlayOpen {
            outlineActiveColumn = column
            positionOutlineSidebar(for: column)
        } else {
            outlineActiveColumn = nil
        }
        leftOverlaySidebar.isHidden = !isLeftOverlayOpen
        outlineToggleBtn.state = isLeftOverlayOpen ? .on : .off
        leftCol.columnToolbar.setOutlineActive(isLeftOverlayOpen)
        rightCol.columnToolbar.setOutlineActive(isLeftOverlayOpen)
        if isLeftOverlayOpen {
            pdfThumbnailView.pdfView = column.pdfView
        }
    }

    private func positionOutlineSidebar(for column: CleanPDFColumnView) {
        let isVisualRight: Bool
        if modeSeg.selectedSegment == 0 {
            isVisualRight = false
        } else if modeSeg.selectedSegment == 1 {
            isVisualRight = true
        } else {
            isVisualRight = column === (isSwapped ? leftCol : rightCol)
        }
        outlineSidebarLeadingConstraint?.isActive = !isVisualRight
        outlineSidebarTrailingConstraint?.isActive = isVisualRight
        leftOverlaySidebar.layer?.shadowOffset = CGSize(width: isVisualRight ? -4 : 4, height: -2)
    }

    @objc private func leftOverlaySegChanged() {
        let isTOC = (leftOverlaySeg.selectedSegment == 0)
        outlineContainer.isHidden = !isTOC
        thumbnailsContainer.isHidden = isTOC
        if !isTOC {
            pdfThumbnailView.pdfView = navigationSourceColumn.pdfView
        }
    }

    // MARK: - Stable viewport state across AppKit / PDFKit layout passes
    private var toolbarLeftColumn: CleanPDFColumnView {
        if modeSeg.selectedSegment != 2 { return modeSeg.selectedSegment == 0 ? leftCol : rightCol }
        return isSwapped ? rightCol : leftCol
    }

    private var toolbarRightColumn: CleanPDFColumnView {
        if modeSeg.selectedSegment != 2 { return modeSeg.selectedSegment == 0 ? leftCol : rightCol }
        return isSwapped ? leftCol : rightCol
    }

    private func updateToolbarLayout() {
        guard toolbarHeight != nil, view.bounds.width > 0 else { return }
        if unifiedMarkupHidden {
            toolbarHeight.constant = 0
            return
        }
        let needed = toolbarCenterStack.fittingSize.width +
            2 * max(toolbarLeftStack.fittingSize.width, toolbarRightStack.fittingSize.width) + 48
        let twoRows = view.bounds.width < needed
        let separationActive = toolbarSeparation.contains { $0.isActive }
        guard twoRows != toolbarUsesTwoRows || separationActive == twoRows else { return }
        beginLayoutChange()
        toolbarUsesTwoRows = twoRows
        NSLayoutConstraint.deactivate(toolbarSeparation)
        toolbarHeight.constant = twoRows ? 80 : 42
        toolbarCenterY.constant = twoRows ? 60 : 21
        if !twoRows { NSLayoutConstraint.activate(toolbarSeparation) }
        scheduleLayoutCompletion()
    }

    private func cacheViewport(_ column: CleanPDFColumnView) {
        viewportCoordinator.capture(column)
    }

    private func captureVisibleViewports() { viewportCoordinator.captureVisible() }

    private func beginLayoutChange() {
        guard isViewLoaded, !isClosed else { return }
        viewportCoordinator.beginLayout()
    }

    private func scheduleLayoutCompletion() { viewportCoordinator.scheduleCompletion() }

    private func finishPendingLayout() { viewportCoordinator.finishLayout() }

    private func persistReaderState(from column: CleanPDFColumnView, markReading: Bool = false) {
        guard isViewLoaded, !isLoadingDocuments, !isChangingLayout, !isRestoringLayout, !isClosed,
              viewportCoordinator.isActive, !view.isHiddenOrHasHiddenAncestor, !column.isHidden else { return }
        captureVisibleViewports()
        let left = viewportStates[leftCol.side.rawValue] ?? PDFColumnReadingState(pdfDocumentId: leftCol.activePDFDocumentId, continuousPage: 0)
        let right = viewportStates[rightCol.side.rawValue] ?? PDFColumnReadingState(pdfDocumentId: rightCol.activePDFDocumentId, continuousPage: 0)
        viewportCoordinator.setAlignment(pageRatioOffset)
        let state = ReaderState(leftColumn: left, rightColumn: right, syncEnabled: isScrollSyncEnabled,
            displayMode: modeSeg.selectedSegment, swapped: isSwapped, splitRatio: Double(columnSplitRatio),
            alignments: viewportCoordinator.savedAlignments)
        LibraryStore.shared.updateReadingState(for: paperId) { paper in
            paper.readerState = state
            paper.syncOffsetDelta = pageRatioOffset
            if column.pdfView.document != nil, let position = viewportStates[column.side.rawValue] {
                let count = column.pdfView.document?.pageCount ?? 1
                let page = Int(floor(min(Double(max(0, count - 1)), max(0, position.continuousPage))))
                paper.lastReadPage = page
                paper.readingPosition = ReadingPosition(side: column.side, continuousPage: position.continuousPage,
                    pdfDocumentId: column.activePDFDocumentId)
                if markReading && paper.status == .unread && page > 0 { paper.status = .reading }
            }
        }
    }

    private func updateDrawerVisibility() {
        isDrawerOpen = !rightDrawer.isHidden && !masterSplitView.isSubviewCollapsed(rightDrawer)
        drawerToggleBtn.state = isDrawerOpen ? .on : .off
    }

    private func updateNavigationSource() {
        let column = navigationSourceColumn
        pdfThumbnailView.pdfView = column.pdfView
        if outlineSourceColumn !== column || outlineSourceDocument !== column.pdfView.document {
            rebuildOutlineData()
        }
    }

    // MARK: - 3. Floating "返回" Capsule Banners (for Reference & Page Jumps)
    private func setupFloatingBackBanners() {
        updateBannerPositions()
        leftCol.onBackJumpClicked = { [weak self] in
            guard let self = self else { return }
            self.popBackJumpAction(for: self.leftCol)
        }
        rightCol.onBackJumpClicked = { [weak self] in
            guard let self = self else { return }
            self.popBackJumpAction(for: self.rightCol)
        }
    }

    private func updateBannerPositions() {
        let colOnLeft = isSwapped ? rightCol : leftCol
        let colOnRight = isSwapped ? leftCol : rightCol
        colOnLeft.updateBannerPosition(isRightAligned: false)
        colOnRight.updateBannerPosition(isRightAligned: true)
    }

    func pushJumpRecord(from col: CleanPDFColumnView, label: String = "返回") {
        finishPendingLayout()
        guard col.contentSource.isPDF,
              let sv = col.internalScrollView(),
              let doc = col.pdfView.document else { return }
        let pageIdx = col.pdfView.currentPage.map { doc.index(for: $0) } ?? 0
        let record = ReadingJumpRecord(
            side: col.side,
            pdfDocumentId: col.activePDFDocumentId,
            pageIndex: pageIdx,
            scrollOriginY: sv.contentView.bounds.origin.y,
            descriptionLabel: label
        )
        lastJumpCol = col
        if col === leftCol {
            leftJumpRecord = record
            leftCol.backJumpBanner.isHidden = false
            leftCol.backJumpButton.keyEquivalent = "["
            leftCol.backJumpButton.keyEquivalentModifierMask = [.command]
            rightCol.backJumpButton.keyEquivalent = ""
        } else {
            rightJumpRecord = record
            rightCol.backJumpBanner.isHidden = false
            rightCol.backJumpButton.keyEquivalent = "["
            rightCol.backJumpButton.keyEquivalentModifierMask = [.command]
            leftCol.backJumpButton.keyEquivalent = ""
        }
    }

    func popBackJumpAction(for col: CleanPDFColumnView) {
        finishPendingLayout()
        let isLeft = (col === leftCol)
        guard let record = (isLeft ? leftJumpRecord : rightJumpRecord) else {
            col.backJumpBanner.isHidden = true
            col.backJumpButton.keyEquivalent = ""
            return
        }
        if isLeft {
            leftJumpRecord = nil
        } else {
            rightJumpRecord = nil
        }
        if col.isHidden { setDisplayMode(2) }

        if col.contentSource != .pdf(id: record.pdfDocumentId) {
            setColumnSource(col, source: .pdf(id: record.pdfDocumentId))
            view.layoutSubtreeIfNeeded()
        }

        if let sv = col.internalScrollView() {
            navigate(in: col) {
                sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: record.scrollOriginY))
                sv.reflectScrolledClipView(sv.contentView)
            }
        }

        col.backJumpBanner.isHidden = true
        col.backJumpButton.keyEquivalent = ""
        let otherCol = isLeft ? rightCol : leftCol
        let otherRecord = isLeft ? rightJumpRecord : leftJumpRecord
        if otherRecord != nil {
            otherCol.backJumpButton.keyEquivalent = "["
            otherCol.backJumpButton.keyEquivalentModifierMask = [.command]
            lastJumpCol = otherCol
        } else {
            lastJumpCol = nil
        }
        updatePageIndicatorAndSaveProgress()
    }

    @objc func popBackJumpAction() {
        if let last = lastJumpCol {
            if last === leftCol && leftJumpRecord != nil {
                popBackJumpAction(for: leftCol)
                return
            } else if last === rightCol && rightJumpRecord != nil {
                popBackJumpAction(for: rightCol)
                return
            }
        }
        if leftJumpRecord != nil {
            popBackJumpAction(for: leftCol)
        } else if rightJumpRecord != nil {
            popBackJumpAction(for: rightCol)
        }
    }

    // MARK: - 4. Sync Engine + Option-Key Offset Calibration + Callbacks
    private func setupSyncAndCallbacks() {
        // PDFKit can replace its internal clip view when a document is installed.
        // Resolve the current clip view at delivery instead of observing an old one.
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification, object: nil)
        for col in [leftCol, rightCol] {
            col.pdfView.onInteraction = { [weak self, weak col] in
                guard let self = self, let col = col, !col.isHidden else { return }
                self.finishPendingLayout()
                self.lastReadingColumn = col
                self.updateNavigationSource()
                self.refreshUnifiedMarkupState()
            }
            col.pdfView.onMagnificationWillChange = { [weak self] in self?.beginLayoutChange() }
            col.pdfView.onMagnificationDidChange = { [weak self, weak col] in
                guard let self = self, let col = col else { return }
                self.adoptZoom(from: col)
                self.finishPendingLayout()
            }
            col.pdfView.onPageStep = { [weak self, weak col] delta in
                guard let self = self, let col = col else { return }
                self.stepPage(in: col, delta: delta)
            }
            col.pdfView.onZoomCommand = { [weak self, weak col] automatic, scale in
                guard let self = self, let col = col else { return }
                self.setZoom(col, autoScales: automatic, scaleFactor: scale)
            }
            col.pdfView.onCommandScrollZoom = { [weak self, weak col] scale in
                guard let self = self, let col = col else { return }
                self.applyCommandScrollZoom(in: col, to: scale)
            }
            col.onPageCapsuleStep = { [weak self, weak col] delta in
                guard let self = self, let col = col else { return }
                self.stepPage(in: col, delta: delta)
                col.revealPageCapsule()
            }
            col.onPageCapsuleCommit = { [weak self, weak col] page in
                guard let self = self, let col = col else { return }
                self.goToColumnPageIndex(col, pageIndex: page - 1, recordHistory: true)
                col.revealPageCapsule()
            }
            col.onMarkupStateChanged = { [weak self] in self?.refreshUnifiedMarkupState() }
            col.onToolbarLayoutChanged = { [weak self] in
                guard let self = self, !self.isClosed else { return }
                self.beginLayoutChange()
                self.view.layoutSubtreeIfNeeded()
                self.scheduleLayoutCompletion()
            }
            self.configureColumnToolbar(for: col)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfScaleChanged(_:)),
                name: .PDFViewScaleChanged,
                object: col.pdfView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pdfPageChanged(_:)),
                name: .PDFViewPageChanged,
                object: col.pdfView
            )

            col.currentPaperProvider = { [weak self] in
                self?.currentPaper
            }
            col.onSelectColumnSource = { [weak self, weak col] newSource in
                guard let self = self, let col = col else { return }
                self.setColumnSource(col, source: newSource)
            }
            col.onAddAdditionalPDFRequested = { [weak self, weak col] in
                guard let self = self, let col = col else { return }
                self.promptToAddAdditionalPDF(for: col)
            }
            col.onRemoveAdditionalPDFRequested = { [weak self, weak col] pdfId in
                guard let self = self, let col = col else { return }
                if LibraryStore.shared.removeAdditionalPDF(from: self.paperId, pdfId: pdfId) {
                    self.setColumnSource(col, source: .pdf(id: col.side.rawValue))
                }
            }
            col.onBindPDFRequested = { [weak self, weak col] side in
                guard let self = self, let col = col else { return }
                self.promptToImportOrReplacePDF(in: col)
            }
            col.onRevealPDFInFinder = { [weak self, weak col] side in
                guard let self = self,
                      let col = col,
                      let paper = self.currentPaper,
                      let url = LibraryStore.shared.pdfURL(for: paper, pdfId: col.activePDFDocumentId) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            let dropHandler: (URL) -> Void = { [weak self, weak col] url in
                guard let self = self, let col = col else { return }
                self.handleDroppedPDFOnColumn(url, col: col)
            }
            let multiDropHandler: ([URL]) -> Void = { [weak self, weak col] urls in
                guard let self = self, let col = col, let first = urls.first else { return }
                self.handleDroppedPDFOnColumn(first, col: col)
                if urls.count >= 2 {
                    self.presentColumnDropLimitBanner(openedName: first.lastPathComponent)
                }
            }
            col.onFileDropped = dropHandler
            col.onFilesDropped = multiDropHandler
            col.pdfView.onFileDropped = dropHandler
            col.pdfView.onFilesDropped = multiDropHandler
            col.pdfView.onOptionScrollPerformed = { [weak self] in
                self?.recordOptionScrollCalibrationOffset()
            }
            col.pdfView.onTextSelectedForPopover = { [weak self, weak col] selection, rectInView in
                guard let col = col else { return }
                self?.showSelectionActionPopover(for: col.pdfView, selection: selection, rectInView: rectInView)
            }
            col.pdfView.onAnnotationClicked = { [weak self, weak col] annot, pt in
                guard let col = col else { return }
                self?.showExistingAnnotationPopover(annot, in: col.pdfView, at: pt)
            }
            col.pdfView.onMarkupCreate = { [weak self, weak col] annotations in
                guard let self, let col else { return }
                self.persistMarkupCreate(annotations, in: col)
            }
            col.pdfView.onMarkupUpdate = { [weak self, weak col] annotation in
                guard let self, let col else { return }
                self.persistMarkupUpdate(annotation, in: col)
            }
            col.pdfView.onMarkupDelete = { [weak self] ids in
                self?.persistMarkupDelete(ids)
            }
            col.pdfView.onMarkupVisibilityChanged = { [weak self, weak col] ids in
                guard let self, let col else { return }
                self.annotationRenderer.setHidden(ids, in: col)
            }
            col.pdfView.onMarkupStateChanged = { [weak col] in
                guard let col else { return }
                col.columnToolbar.setUndoRedoEnabled(
                    canUndo: col.pdfView.canUndoMarkup,
                    canRedo: col.pdfView.canRedoMarkup)
            }
            col.pdfView.onBeforeInternalLinkJump = { [weak self, weak col] destPage, destPoint, isCmdPressed in
                guard let self = self, let col = col else { return false }
                return self.handleReferenceJump(from: col, toPage: destPage, point: destPoint, inOppositePaneOnly: isCmdPressed)
            }
            col.pdfView.onContextMenuTranslate = { [weak self] text in
                guard let self = self else { return }
                self.sidebarTransSourceTextView.string = text
                if !self.isDrawerOpen { self.toggleRightDrawerAction() }
                self.switchWorkbenchTab(to: 2)
                self.sidebarTranslateAction()
            }
            col.pdfView.onContextMenuHighlight = { [weak self, weak col] selection, color in
                guard let self = self, let col = col else { return }
                self.activeSelectionPDFView = col.pdfView
                _ = self.createAnnotationFromCurrentSelection(color: color, note: "", linkedURL: nil, linkedTitle: nil)
                self.applyAnnotationsToPDFViews()
            }
            col.pdfView.onContextMenuAddNote = { [weak self, weak col] selection in
                guard let self = self, let col = col else { return }
                self.activeSelectionPDFView = col.pdfView
                self.quoteSelectionToPaperNote(from: col.pdfView, selection: selection)
                if !self.isDrawerOpen { self.toggleRightDrawerAction() }
                self.switchWorkbenchTab(to: 1)
            }
            col.pdfView.onContextMenuSwapColumns = { [weak self] in
                self?.swapColumnsAction()
            }
            col.pdfView.onContextMenuResetSync = { [weak self] in
                self?.resetSyncAlignmentAction()
            }
        }
    }

    func computeContinuousPagePosition(in col: CleanPDFColumnView) -> Double? {
        PDFScrollSynchronizer.continuousPosition(in: col)
    }

    /// 当用户按住 ⌥ Option 键单栏滚动微调时，计算并保存左右两栏的对齐偏移差
    func recordOptionScrollCalibrationOffset() {
        finishPendingLayout()
        guard !isLoadingDocuments, !leftCol.isHidden, !rightCol.isHidden,
              let leftPos = computeContinuousPagePosition(in: leftCol),
              let rightPos = computeContinuousPagePosition(in: rightCol) else { return }
        pageRatioOffset = rightPos - leftPos
        resetAlignBtn.isHidden = abs(pageRatioOffset) < 0.005
        viewportCoordinator.setAlignment(pageRatioOffset)
        persistReaderState(from: primaryActiveColumn())
    }

    private func handleReferenceJump(
        from sourceCol: CleanPDFColumnView,
        toPage destPage: PDFPage,
        point: NSPoint,
        inOppositePaneOnly: Bool
    ) -> Bool {
        finishPendingLayout()
        guard let srcDoc = sourceCol.pdfView.document, destPage.document === srcDoc else { return false }
        let targetPageIndex = srcDoc.index(for: destPage)

        if inOppositePaneOnly {
            let oppositeCol = (sourceCol === leftCol) ? rightCol : leftCol
            if let oppDoc = oppositeCol.pdfView.document,
               targetPageIndex < oppDoc.pageCount,
               let oppPage = oppDoc.page(at: targetPageIndex) {
                if oppositeCol.isHidden { setDisplayMode(2) }
                pushJumpRecord(from: oppositeCol, label: "参考文献跳转前")
                navigate(in: oppositeCol, synchronize: false, activate: false) { oppositeCol.pdfView.go(to: oppPage) }
                return true
            }
            return false
        } else {
            pushJumpRecord(from: sourceCol, label: "正文原位")
            navigate(in: sourceCol) { sourceCol.pdfView.go(to: PDFDestination(page: destPage, at: point)) }
            return true
        }
    }

    @objc private func clipViewBoundsChanged(_ note: Notification) {
        guard !isClosed, !view.isHiddenOrHasHiddenAncestor,
              let clipView = note.object as? NSClipView,
              let source = [leftCol, rightCol].first(where: { $0.internalScrollView()?.contentView === clipView }),
              viewportCoordinator.receivedScroll(in: source) else { return }
        lastReadingColumn = source
        source.revealPageCapsule()
        syncScroll(from: source, to: source === leftCol ? rightCol : leftCol)
        // The target column moves programmatically inside syncScroll, where
        // bounds notifications are suppressed. Refresh both capsules after
        // that move so each column shows its own post-sync page.
        updatePageIndicatorAndSaveProgress()
        refreshUnifiedMarkupState()
        scheduleReadingPositionSave(from: source)
    }

    func syncScroll(from source: CleanPDFColumnView, to target: CleanPDFColumnView) {
        guard viewportCoordinator.acceptsEvents, !isClosed, !view.isHiddenOrHasHiddenAncestor,
              !source.isHidden, !target.isHidden, source.pdfView.bounds.width > 0, target.pdfView.bounds.width > 0 else { return }
        if NSEvent.modifierFlags.contains(.option) {
            recordOptionScrollCalibrationOffset()
            return
        }
        guard isScrollSyncEnabled else { return }
        viewportCoordinator.performUpdate {
            PDFScrollSynchronizer.synchronize(from: source, to: target,
                offset: source === leftCol ? pageRatioOffset : -pageRatioOffset)
            cacheViewport(source)
            cacheViewport(target)
        }
        persistReaderState(from: source)
    }

    @objc private func pdfScaleChanged(_ note: Notification) {
        guard viewportCoordinator.acceptsEvents, !isClosed, !view.isHiddenOrHasHiddenAncestor,
              let pdfView = note.object as? PDFView,
              let source = [leftCol, rightCol].first(where: { $0.pdfView === pdfView }), !source.isHidden else { return }
        if !pdfView.autoScales, let state = viewportStates[source.side.rawValue],
           abs(state.scaleFactor - Double(pdfView.scaleFactor)) < 0.000_001 { return }
        // PDFKit may deliver scale notifications after its bounds have changed.
        // Keep the last stable reading anchor and adopt only the requested zoom.
        viewportCoordinator.beginLayout(capture: false)
        adoptZoom(from: source)
        finishPendingLayout()
    }

    private func adoptZoom(from source: CleanPDFColumnView) {
        viewportCoordinator.setZoom(in: source, autoScales: source.pdfView.autoScales,
            scaleFactor: source.pdfView.scaleFactor)
    }

    @objc private func pdfPageChanged(_ note: Notification) {
        guard viewportCoordinator.acceptsEvents, !isClosed, !view.isHiddenOrHasHiddenAncestor else { return }
        // Page notifications are derived display state; they must not choose the
        // active pane or initiate a second scroll while PDFKit is still laying out.
        updatePageIndicatorAndSaveProgress()
        refreshUnifiedMarkupState()
        stripVisibleLinkAnnotationBorders()
    }

    func primaryActiveColumn() -> CleanPDFColumnView {
        if modeSeg.selectedSegment == 1 {
            return rightCol
        }
        if modeSeg.selectedSegment == 0 {
            return leftCol
        }
        if let column = lastReadingColumn, !column.isHidden, column.pdfView.document != nil { return column }
        return leftCol.pdfView.document != nil ? leftCol : rightCol
    }

    private func currentPageIndex(in column: CleanPDFColumnView) -> Int {
        guard let document = column.pdfView.document, document.pageCount > 0 else { return 0 }
        if let position = computeContinuousPagePosition(in: column), position.isFinite {
            return min(document.pageCount - 1, max(0, Int(floor(position))))
        }
        return column.pdfView.currentPage.map { min(document.pageCount - 1, max(0, document.index(for: $0))) } ?? 0
    }

    private func updatePageIndicatorAndSaveProgress() {
        updateZoomIndicators()
        updateNavigationSource()
        // 更新左栏页码
        if let leftDoc = toolbarLeftColumn.pdfView.document {
            let leftTotal = leftDoc.pageCount
            let leftIdx = currentPageIndex(in: toolbarLeftColumn)
            leftPageJumpBtn.title = "\(leftIdx + 1) / \(leftTotal) 页"
            leftPrevPageBtn.isEnabled = (leftIdx > 0)
            leftNextPageBtn.isEnabled = (leftIdx + 1 < leftTotal)
        } else {
            leftPageJumpBtn.title = "- / -"
            leftPrevPageBtn.isEnabled = false
            leftNextPageBtn.isEnabled = false
        }

        // 更新右栏页码
        if let rightDoc = toolbarRightColumn.pdfView.document {
            let rightTotal = rightDoc.pageCount
            let rightIdx = currentPageIndex(in: toolbarRightColumn)
            rightPageJumpBtn.title = "\(rightIdx + 1) / \(rightTotal) 页"
            rightPrevPageBtn.isEnabled = (rightIdx > 0)
            rightNextPageBtn.isEnabled = (rightIdx + 1 < rightTotal)
        } else {
            rightPageJumpBtn.title = "- / -"
            rightPrevPageBtn.isEnabled = false
            rightNextPageBtn.isEnabled = false
        }

        // 每栏底部页码胶囊按该栏自己的 PDF 独立更新，互换双栏后也不会串页。
        for column in [leftCol, rightCol] {
            if let doc = column.pdfView.document {
                let idx = currentPageIndex(in: column)
                column.pageCapsule.update(page: idx + 1, total: doc.pageCount)
            } else {
                column.pageCapsule.update(page: 1, total: 1)
            }
        }

        // 同步高亮右侧目录当前所在章节
        let activePDF = primaryActiveColumn().pdfView
        if activePDF.document != nil {
            let currentIdx = currentPageIndex(in: primaryActiveColumn())
            if let matchRow = outlineItems.lastIndex(where: { $0.pageIndex <= currentIdx }) {
                isUpdatingOutlineSelection = true
                outlineTableView.selectRowIndexes(IndexSet(integer: matchRow), byExtendingSelection: false)
                outlineTableView.scrollRowToVisible(matchRow)
                isUpdatingOutlineSelection = false
            }
        }
    }

    private func revealVisiblePageCapsulesAfterLayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, !self.isClosed, !self.view.isHiddenOrHasHiddenAncestor else { return }
            for column in [self.leftCol, self.rightCol] where !column.isHidden && column.pdfView.document != nil {
                column.revealPageCapsule()
            }
        }
    }

    private func scheduleReadingPositionSave(from column: CleanPDFColumnView) {
        guard viewportCoordinator.acceptsEvents, !isClosed, !view.isHiddenOrHasHiddenAncestor, !column.isHidden,
              column.pdfView.document != nil else { return }
        lastReadingColumn = column
        persistReaderState(from: column, markReading: true)
        updateNavigationSource()
    }

    private func fileModificationDate(_ url: URL?) -> Date? {
        guard let url = url else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - 5. Load Paper PDFs, Restore Reading Page, Render Highlights & Build Outline
    private func pdfFileVersions(in paper: PaperItem) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: paper.allPDFDescriptors.compactMap { descriptor in
            guard let url = LibraryStore.shared.pdfURL(for: paper, pdfId: descriptor.id),
                  let date = fileModificationDate(url) else { return nil }
            return (descriptor.id, date)
        })
    }

    func loadPaperDocuments() {
        guard let paper = currentPaper, !isClosed else { return }
        if !isLoadingDocuments && !isChangingLayout { captureVisibleViewports() }
        if viewportStates.isEmpty, let position = paper.readingPosition {
            viewportStates[position.side.rawValue] = PDFColumnReadingState(
                pdfDocumentId: position.pdfDocumentId ?? position.side.rawValue,
                continuousPage: position.continuousPage)
        }
        viewportCoordinator.setAlignment(pageRatioOffset)
        viewportCoordinator.beginLoading()
        notesNeedRefresh = true
        linksNeedRefresh = true
        leftJumpRecord = nil
        rightJumpRecord = nil
        leftCol.backJumpBanner.isHidden = true
        rightCol.backJumpBanner.isHidden = true
        leftCol.backJumpButton.keyEquivalent = ""
        rightCol.backJumpButton.keyEquivalent = ""
        lastJumpCol = nil
        invalidateSearch()
        loadedPDFFiles = pdfFileVersions(in: paper)
        for col in [leftCol, rightCol] {
            loadColumnContent(for: col, source: col.contentSource, in: paper)
        }
        pageRatioOffset = viewportCoordinator.alignmentOffset
        resetAlignBtn.isHidden = modeSeg.selectedSegment != 2 || abs(pageRatioOffset) < 0.005
        if lastReadingColumn == nil, let saved = paper.readingPosition {
            lastReadingColumn = saved.side == .original ? leftCol : rightCol
        }
        applyDisplayMode(modeSeg.selectedSegment)
        refreshSidebarNotes()
        refreshTagsTabUI()
        applyAnnotationsToPDFViews()
        rebuildOutlineData()
        refreshNotesDrawerWebView()
        refreshLinksDrawerView()
        updateDrawerBadgeTitles()

        // Documents are installed synchronously. Explicit actions can now finish
        // their layout immediately; a queued load can no longer overwrite them.
        viewportCoordinator.documentsInstalled()
        scheduleLayoutCompletion()
        revealVisiblePageCapsulesAfterLayout()
        if !searchField.stringValue.isEmpty { performInPDFSearch() }
    }


    @objc private func saveToLibraryAction() {
        (view.window?.windowController as? MultiTabMainWindowController)?.presentSaveToLibrary(for: paperId)
    }

    func prepareForPromoteSnapshot() {
        persistReaderState(from: primaryActiveColumn())
        LibraryStore.shared.flushReadingState()
    }

    func adoptLibraryPaper(id newId: String) {
        let oldId = paperId
        // C3: keep unlocked PDFDocument across promote (re-key if needed).
        if TransientStore.shared.unlockedDocument(for: newId) == nil {
            TransientStore.shared.transferUnlockedDocument(from: oldId, to: newId)
        }
        transientSession = nil
        paperId = newId
        // Prevent didBecomeActiveTab from treating library PDF paths as a "file change"
        // and reloading a locked document from disk.
        if let paper = currentPaper {
            loadedPDFFiles = pdfFileVersions(in: paper)
        }
        refreshTransientChrome()
        // Keep current PDFView documents and viewportStates; only rebind identity.
        updateRightSidebarMetadataUI()
        updateDrawerBadgeTitles()
    }

    private func refreshTransientChrome() {
        let transient = isTransientOpen
        saveToLibraryBtn.isHidden = !transient
        transientStatusLabel.isHidden = !transient
        if transient {
            let hasNotes = currentPaper?.transientHasNotes == true
            transientStatusLabel.textColor = hasNotes ? .controlAccentColor : .secondaryLabelColor
            transientStatusLabel.font = .systemFont(ofSize: 11, weight: hasNotes ? .semibold : .medium)
        }
        updateToolbarLayout()
    }

    func didBecomeActiveTab() {
        guard !isClosed else { return }
        let wasActive = viewportCoordinator.isActive
        viewportCoordinator.isActive = true
        if !wasActive { viewportCoordinator.beginLayout(capture: false) }
        applyPendingLibraryChanges()
        if let paper = currentPaper, self.pdfFileVersions(in: paper) != loadedPDFFiles {
            loadPaperDocuments()
        }
        LibraryStore.shared.updateReadingState(for: paperId) { $0.lastOpenedAt = Date() }
        updateRightSidebarMetadataUI()
        updateDrawerBadgeTitles()
        beginLayoutChange()
        view.layoutSubtreeIfNeeded()
        applyColumnSplitRatio()
        scheduleLayoutCompletion()
        revealVisiblePageCapsulesAfterLayout()
        if !searchField.stringValue.isEmpty { performInPDFSearch() }
    }

    static func stripLinkAnnotationBorders(in document: PDFDocument) {
        let border = PDFBorder()
        border.lineWidth = 0
        let noneHighlightKey = PDFAnnotationKey(rawValue: "H")
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annot in page.annotations where annot.type == "Link" || annot.type == "/Link" {
                annot.border = border
                annot.color = .clear
                annot.setValue("/N", forAnnotationKey: noneHighlightKey)
            }
        }
    }

    private func stripVisibleLinkAnnotationBorders() {
        let border = PDFBorder()
        border.lineWidth = 0
        let noneHighlightKey = PDFAnnotationKey(rawValue: "H")
        for column in [leftCol, rightCol] {
            for page in column.pdfView.visiblePages {
                for annotation in page.annotations where annotation.type == "Link" || annotation.type == "/Link" {
                    if annotation.border?.lineWidth != 0 || annotation.color != .clear {
                        annotation.border = border
                        annotation.color = .clear
                        annotation.setValue("/N", forAnnotationKey: noneHighlightKey)
                    }
                }
            }
        }
    }

    @objc private func onLibraryChanged(_ notification: Notification) {
        guard !isClosed else { return }
        let change = notification.userInfo?["change"] as? LibraryChange
        guard change?.affects(paperId) ?? true else { return }
        pendingLibraryFields.formUnion(change?.fields ?? .all)
        if !view.isHidden { applyPendingLibraryChanges() }
    }

    /// PDF 栏只显示当前论文的 PDF，笔记始终在右侧边栏。
    func setColumnSource(_ col: CleanPDFColumnView, source: ColumnContentSource, syncModeSeg: Bool = true) {
        guard let paper = currentPaper, !isClosed else { return }
        finishPendingLayout()
        if source == col.contentSource, col.pdfView.document != nil { return }
        beginLayoutChange()
        invalidateSearch()
        selectionPopover.close()
        viewportCoordinator.setAlignment(pageRatioOffset)
        loadColumnContent(for: col, source: source, in: paper)
        pageRatioOffset = viewportCoordinator.alignmentOffset
        resetAlignBtn.isHidden = modeSeg.selectedSegment != 2 || abs(pageRatioOffset) < 0.005
        annotationRenderer.apply(paper.annotations, to: col)
        finishPendingLayout()
        rebuildOutlineData()
        updatePageIndicatorAndSaveProgress()
        if !searchField.stringValue.isEmpty { performInPDFSearch() }
    }

    private func loadColumnContent(for col: CleanPDFColumnView, source: ColumnContentSource, in paper: PaperItem) {
        guard case .pdf(let requestedPDFId) = source else { return }
        let validPDFIds = Set(paper.allPDFDescriptors.map(\.id))
        let effectivePDFId = validPDFIds.contains(requestedPDFId) ? requestedPDFId : col.side.rawValue
        let initial = isLoadingDocuments && viewportStates[col.side.rawValue] == nil ? Double(max(0, paper.lastReadPage)) + 0.5 : 0
        viewportCoordinator.selectDocument(effectivePDFId, in: col, initialPage: initial)
        col.pdfView.highlightedSelections = nil
        col.pdfView.clearSelection()
        col.pdfView.resetMarkupHistory()
        col.columnToolbar.setViewMode(col.pdfView.displayMode)
        if let unlocked = TransientStore.shared.unlockedDocument(for: paperId) ?? transientSession?.document,
           (effectivePDFId == PDFSide.original.rawValue || col.side == .original) {
            ReaderTabViewController.stripLinkAnnotationBorders(in: unlocked)
            col.applyContentSource(.pdf(id: PDFSide.original.rawValue), paper: paper, hasPDFDocument: true)
            col.pdfView.document = unlocked
            let saved = viewportStates[col.side.rawValue]
            if saved?.pdfDocumentId != PDFSide.original.rawValue {
                viewportStates[col.side.rawValue] = PDFColumnReadingState(pdfDocumentId: PDFSide.original.rawValue, continuousPage: 0)
            }
            col.pdfView.autoScales = viewportStates[col.side.rawValue]?.autoScales ?? true
            return
        }
        if let url = LibraryStore.shared.pdfURL(for: paper, pdfId: effectivePDFId),
           let doc = PDFDocument(url: url) {
            ReaderTabViewController.stripLinkAnnotationBorders(in: doc)
            col.applyContentSource(.pdf(id: effectivePDFId), paper: paper, hasPDFDocument: true)
            col.pdfView.document = doc
            col.pdfView.autoScales = false
        } else {
            col.pdfView.document = nil
            col.applyContentSource(.pdf(id: effectivePDFId), paper: paper, hasPDFDocument: false)
        }
    }

    private func applyPendingLibraryChanges() {
        let fields = pendingLibraryFields
        pendingLibraryFields = []
        guard !fields.isEmpty else { return }
        if fields.contains(.pdf) {
            // C3: after promoting an unlocked encrypted PDF, keep the in-memory document.
            if TransientStore.shared.unlockedDocument(for: paperId) != nil,
               leftCol.pdfView.document != nil || rightCol.pdfView.document != nil {
                updateRightSidebarMetadataUI()
                return
            }
            loadPaperDocuments(); return
        }
        if fields.contains(.metadata) {
            updateRightSidebarMetadataUI()
        }
        if fields.contains(.annotations) {
            notesNeedRefresh = true
            applyAnnotationsToPDFViews()
            refreshNotesDrawerWebView()
            refreshSidebarNotes()
        }
        if fields.contains(.resources) {
            linksNeedRefresh = true
            refreshLinksDrawerView()
            refreshAttachmentsTabUI()
        }
        if fields.contains(.metadata) {
            refreshTagsTabUI()
        }
        if !fields.intersection([.annotations, .resources]).isEmpty { updateDrawerBadgeTitles() }
    }

    private func updateDrawerBadgeTitles() {
        guard let paper = currentPaper else { return }
        let noteCount = paper.annotations.count
        drawerToggleBtn.title = ""
        if workbenchRailButtons.indices.contains(1) {
            workbenchRailButtons[1].toolTip = noteCount > 0 ? "随手笔记与高亮 (\(noteCount))" : "随手笔记与高亮"
        }
    }

    private func applyAnnotationsToPDFViews() {
        guard let paper = currentPaper else { return }
        for column in [leftCol, rightCol] {
            annotationRenderer.apply(paper.annotations, to: column)
            column.pdfView.clearSelectedMarkupIfMissing()
        }
    }

    private func persistMarkupCreate(_ annotations: [PaperAnnotation], in column: CleanPDFColumnView) {
        guard !annotations.isEmpty, var paper = currentPaper else { return }
        for source in annotations {
            var annotation = source
            annotation.side = column.side
            annotation.pdfDocumentId = column.activePDFDocumentId
            if let index = paper.annotations.firstIndex(where: { $0.id == annotation.id }) {
                paper.annotations[index] = annotation
            } else {
                paper.annotations.append(annotation)
            }
        }
        guard LibraryStore.shared.savePaper(paper, notify: true) else { return }
        applyAnnotationsToPDFViews()
    }

    private func persistMarkupUpdate(_ annotation: PaperAnnotation, in column: CleanPDFColumnView) {
        guard var paper = currentPaper,
              let index = paper.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        var annotation = annotation
        annotation.side = column.side
        annotation.pdfDocumentId = column.activePDFDocumentId
        paper.annotations[index] = annotation
        guard LibraryStore.shared.savePaper(paper, notify: true) else { return }
        applyAnnotationsToPDFViews()
    }

    private func persistMarkupDelete(_ ids: [String]) {
        guard var paper = currentPaper else { return }
        let idSet = Set(ids)
        paper.annotations.removeAll { idSet.contains($0.id) }
        guard LibraryStore.shared.savePaper(paper, notify: true) else { return }
        applyAnnotationsToPDFViews()
    }

    private func showSelectionActionPopover(for pdfView: InteractivePDFView, selection: PDFSelection, rectInView: NSRect) {
        activeSelectionPDFView = pdfView

        let vc = NSViewController()
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 6
        container.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)

        for color in HighlightColor.allCases {
            let swatch = HighlightSwatchButton(color: color, selected: false, target: self, action: #selector(quickHighlightSwatchClicked(_:)))
            container.addArrangedSubview(swatch)
        }

        container.addArrangedSubview(makeToolbarSeparator())

        let quoteToNoteBtn = ModernHoverButton(title: "引用笔记", image: NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "引用笔记") ?? NSImage(), target: self, action: #selector(popoverQuoteToNoteClicked), cornerRadius: 5)
        quoteToNoteBtn.imagePosition = .imageLeading
        quoteToNoteBtn.bezelStyle = .texturedRounded
        quoteToNoteBtn.controlSize = .small
        quoteToNoteBtn.normalTintColor = .controlAccentColor
        quoteToNoteBtn.hoverTintColor = .controlAccentColor
        quoteToNoteBtn.hoverBgColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        container.addArrangedSubview(quoteToNoteBtn)

        let translateBtn = ModernHoverButton(title: "翻译", image: NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "翻译") ?? NSImage(), target: self, action: #selector(popoverLLMTranslateClicked), cornerRadius: 5)
        translateBtn.imagePosition = .imageLeading
        translateBtn.bezelStyle = .texturedRounded
        translateBtn.controlSize = .small
        translateBtn.normalTintColor = .labelColor
        translateBtn.hoverTintColor = .controlAccentColor
        translateBtn.hoverBgColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
        container.addArrangedSubview(translateBtn)

        let noteBtn = ModernHoverButton(title: "批注", image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "批注") ?? NSImage(), target: self, action: #selector(popoverAddNoteClicked), cornerRadius: 5)
        noteBtn.imagePosition = .imageLeading
        noteBtn.bezelStyle = .texturedRounded
        noteBtn.controlSize = .small
        noteBtn.normalTintColor = .labelColor
        noteBtn.hoverTintColor = .controlAccentColor
        noteBtn.hoverBgColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
        container.addArrangedSubview(noteBtn)

        let copyBtn = ModernHoverButton(title: "复制", image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制") ?? NSImage(), target: self, action: #selector(popoverCopyClicked), cornerRadius: 5)
        copyBtn.imagePosition = .imageLeading
        copyBtn.bezelStyle = .texturedRounded
        copyBtn.controlSize = .small
        copyBtn.normalTintColor = .labelColor
        copyBtn.hoverTintColor = .controlAccentColor
        copyBtn.hoverBgColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
        container.addArrangedSubview(copyBtn)

        vc.view = container
        selectionPopover.contentViewController = vc
        selectionPopover.behavior = .transient
        selectionPopover.show(relativeTo: rectInView, of: pdfView, preferredEdge: .maxY)
    }

    @objc private func quickHighlightSwatchClicked(_ sender: HighlightSwatchButton) {
        _ = createAnnotationFromCurrentSelection(color: sender.highlightColor, note: "", linkedURL: nil, linkedTitle: nil)
        selectionPopover.close()
    }

    @objc private func popoverQuoteToNoteClicked() {
        guard let pdfView = activeSelectionPDFView else { return }
        _ = quoteSelectionToPaperNote(from: pdfView)
        selectionPopover.close()
    }

    @objc private func popoverLLMTranslateClicked() {
        guard let pdfView = activeSelectionPDFView,
              let sel = pdfView.currentSelection,
              let firstPage = sel.pages.first else { return }
        let rectInView = pdfView.convert(sel.bounds(for: firstPage), from: firstPage)
        presentLLMTranslationPopover(for: pdfView, selection: sel, rectInView: rectInView)
    }

    @objc private func popoverAddNoteClicked() {
        selectionPopover.close()
        guard let ann = createAnnotationFromCurrentSelection(color: .yellow, note: "", linkedURL: nil, linkedTitle: nil) else { return }
        presentNoteEditorModal(for: ann)
    }

    @objc private func popoverAttachLinkClicked() {
        selectionPopover.close()
        guard let ann = createAnnotationFromCurrentSelection(color: .blue, note: "", linkedURL: nil, linkedTitle: nil) else { return }
        presentAttachLinkModal(for: ann)
    }

    @objc private func popoverCopyClicked() {
        if let str = activeSelectionPDFView?.currentSelection?.string {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
        activeSelectionPDFView?.clearSelection()
        selectionPopover.close()
    }

    private func createAnnotationFromCurrentSelection(
        color: HighlightColor,
        note: String,
        linkedURL: String?,
        linkedTitle: String?
    ) -> PaperAnnotation? {
        guard let pdfView = activeSelectionPDFView, let selection = pdfView.currentSelection,
              let document = pdfView.document, var paper = currentPaper,
              let annotation = PDFSelectionAnnotationFactory.make(selection: selection, document: document,
                  side: pdfView.side, pdfDocumentId: pdfView.activePDFDocumentId,
                  color: color, note: note, linkedURL: linkedURL, linkedTitle: linkedTitle) else { return nil }
        paper.annotations.append(annotation)
        guard LibraryStore.shared.savePaper(paper, notify: true) else { return nil }
        pdfView.clearSelection()
        return annotation
    }

    // MARK: - 6A. Direct Selection-to-Note Jumpable Link Creation (选中直接在笔记中创建可跳转链接)
    @discardableResult
    func quoteSelectionToPaperNote(
        from pdfView: InteractivePDFView,
        selection explicitSelection: PDFSelection? = nil,
        customTranslation: String? = nil
    ) -> (annotation: PaperAnnotation, linkMarkdown: String, updatedNote: PaperNoteDocument)? {
        guard let selection = explicitSelection ?? pdfView.currentSelection,
              let document = pdfView.document,
              var paper = currentPaper,
              let annotation = PDFSelectionAnnotationFactory.make(
                  selection: selection,
                  document: document,
                  side: pdfView.side,
                  pdfDocumentId: pdfView.activePDFDocumentId,
                  color: .yellow,
                  note: customTranslation ?? "",
                  linkedURL: nil,
                  linkedTitle: nil
              ) else { return nil }

        paper.annotations.append(annotation)
        guard LibraryStore.shared.savePaper(paper, notify: true) else { return nil }
        pdfView.clearSelection()

        let pdfBadge = annotation.shortSourceBadge(in: paper)
        let compactExcerpt = annotation.displayText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shortLabelExcerpt = compactExcerpt.count > 36 ? String(compactExcerpt.prefix(36)) + "…" : compactExcerpt
        let jumpURL = "dualpdf://jump?annot=\(annotation.id)&pdf=\(annotation.effectivePDFId)&page=\(annotation.pageIndex)"
        var snippet = "- [📍 \(pdfBadge) · P.\(annotation.pageIndex + 1): “\(shortLabelExcerpt)”](\(jumpURL))\n  > \(compactExcerpt)"
        if let trans = customTranslation?.trimmingCharacters(in: .whitespacesAndNewlines), !trans.isEmpty {
            let formattedTrans = trans.replacingOccurrences(of: "\n", with: "\n  ")
            snippet += "\n  **AI 结果**：\(formattedTrans)"
        }

        openNotesSidebar()
        sidebarNoteView.appendOrInsertMarkdownLink(snippet)
        guard let updatedNote = sidebarNoteView.currentNote else { return nil }
        return (annotation, snippet, updatedNote)
    }

    private func insertJumpLinkFromPDFColumn(_ pdfCol: CleanPDFColumnView) {
        if let sel = pdfCol.pdfView.currentSelection,
           let str = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty {
            _ = quoteSelectionToPaperNote(from: pdfCol.pdfView, selection: sel)
            return
        }
        // 若当前 PDF 未划选文字，则直接插入指向该栏当前阅读页码的可跳转书签链接
        guard let paper = currentPaper,
              let doc = pdfCol.pdfView.document else { return }
        let pageIdx = pdfCol.pdfView.currentPage.map { doc.index(for: $0) } ?? 0
        let pdfId = pdfCol.activePDFDocumentId
        let pdfTitle = paper.pdfTitle(for: pdfId)
        let jumpURL = "dualpdf://jump?pdf=\(pdfId)&page=\(pageIdx)"
        let snippet = "- [📍 \(pdfTitle) · 第 \(pageIdx + 1) 页书签](\(jumpURL))"
        openNotesSidebar()
        sidebarNoteView.appendOrInsertMarkdownLink(snippet)
    }

    // MARK: - 6B. Selection LLM Translation Popover (划词支持 LLM 翻译)
    func presentLLMTranslationPopover(for pdfView: InteractivePDFView, selection: PDFSelection, rectInView: NSRect) {
        activeSelectionPDFView = pdfView
        activeTranslationTask?.cancel()

        let vc = NSViewController()
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        // 顶部栏：标题 + 翻译模式选择 + 接口设置按钮
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        let titleIcon = NSImageView(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI") ?? NSImage())
        titleIcon.contentTintColor = .controlAccentColor
        titleIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        headerRow.addArrangedSubview(titleIcon)

        let titleLbl = NSTextField(labelWithString: "AI 划词翻译")
        titleLbl.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLbl.textColor = .labelColor
        headerRow.addArrangedSubview(titleLbl)

        let modePop = NSPopUpButton()
        modePop.controlSize = .small
        modePop.font = .systemFont(ofSize: 11, weight: .medium)
        for m in LLMTranslationMode.allCases {
            modePop.addItem(withTitle: m.displayName)
        }
        if let idx = LLMTranslationMode.allCases.firstIndex(of: currentTranslationMode) {
            modePop.selectItem(at: idx)
        }
        modePop.target = self
        modePop.action = #selector(translationModeChanged(_:))
        headerRow.addArrangedSubview(modePop)

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(headerSpacer)

        let settingsBtn = NSButton(title: " 接口设置", image: NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "接口设置") ?? NSImage(), target: self, action: #selector(translationSettingsClicked))
        settingsBtn.imagePosition = .imageLeading
        settingsBtn.bezelStyle = .inline
        settingsBtn.controlSize = .small
        settingsBtn.font = .systemFont(ofSize: 10.5, weight: .medium)
        headerRow.addArrangedSubview(settingsBtn)

        rootStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalToConstant: 376).isActive = true

        let providerLbl = NSTextField(labelWithString: "正在调用翻译引擎…")
        providerLbl.font = .systemFont(ofSize: 10.5)
        providerLbl.textColor = .secondaryLabelColor
        self.translationProviderLabel = providerLbl
        rootStack.addArrangedSubview(providerLbl)

        // 渲染区（支持 Markdown + LaTeX 数学公式）
        let card = ModernSurfaceCardView()
        card.cornerRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(webView)
        self.translationPreviewWebView = webView

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 376),
            card.heightAnchor.constraint(equalToConstant: 185),
            webView.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            webView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 2),
            webView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2),
            webView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -2)
        ])
        rootStack.addArrangedSubview(card)

        // 底部动作按钮：插入到笔记(带跳转链接) / 存为高亮批注 / 复制译文
        let insertNoteBtn = NSButton(title: " 插入到笔记", image: NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "插入到笔记") ?? NSImage(), target: self, action: #selector(translationInsertToNoteClicked))
        insertNoteBtn.imagePosition = .imageLeading
        insertNoteBtn.bezelStyle = .rounded
        insertNoteBtn.controlSize = .small
        insertNoteBtn.contentTintColor = .controlAccentColor

        let saveAnnotBtn = NSButton(title: " 存为批注", image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "存为批注") ?? NSImage(), target: self, action: #selector(translationSaveAsAnnotClicked))
        saveAnnotBtn.imagePosition = .imageLeading
        saveAnnotBtn.bezelStyle = .rounded
        saveAnnotBtn.controlSize = .small

        let copyTransBtn = NSButton(title: " 复制译文", image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制译文") ?? NSImage(), target: self, action: #selector(translationCopyClicked))
        copyTransBtn.imagePosition = .imageLeading
        copyTransBtn.bezelStyle = .rounded
        copyTransBtn.controlSize = .small

        translationActionButtons = [insertNoteBtn, saveAnnotBtn, copyTransBtn]
        translationActionButtons.forEach { $0.isEnabled = false }
        let actionRow = NSStackView(views: translationActionButtons)
        actionRow.orientation = .horizontal
        actionRow.spacing = 6
        rootStack.addArrangedSubview(actionRow)

        vc.view = rootStack
        selectionPopover.contentViewController = vc
        selectionPopover.behavior = .transient
        if !selectionPopover.isShown {
            selectionPopover.show(relativeTo: rectInView, of: pdfView, preferredEdge: .maxY)
        }

        triggerSelectionTranslation()
    }

    private func triggerSelectionTranslation() {
        guard let pdfView = activeSelectionPDFView,
              let sel = pdfView.currentSelection,
              let rawText = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else { return }

        let firstPage = sel.pages.first
        let pageIdx = firstPage.flatMap { pdfView.document?.index(for: $0) } ?? 0
        let sourceCol = (pdfView === leftCol.pdfView) ? leftCol : rightCol
        let oppositeCol = (pdfView === leftCol.pdfView) ? rightCol : leftCol

        var pairedPage: PDFPage? = nil
        if oppositeCol.contentSource.isPDF,
           oppositeCol.activePDFDocumentId != sourceCol.activePDFDocumentId,
           let oppDoc = oppositeCol.pdfView.document,
           pageIdx >= 0, pageIdx < oppDoc.pageCount {
            pairedPage = oppDoc.page(at: pageIdx)
        } else if let paper = currentPaper {
            let targetSide: PDFSide = (sourceCol.activePDFDocumentId == PDFSide.translated.rawValue) ? .original : .translated
            if let pairedURL = LibraryStore.shared.pdfURL(for: paper, side: targetSide),
               let pairedDoc = PDFDocument(url: pairedURL),
               pageIdx >= 0, pageIdx < pairedDoc.pageCount {
                pairedPage = pairedDoc.page(at: pageIdx)
            }
        }

        var pairedPageText: String? = nil
        if let oppPage = pairedPage {
            if let srcPage = firstPage {
                let selBounds = sel.bounds(for: srcPage)
                let srcBounds = srcPage.bounds(for: .mediaBox)
                let oppBounds = oppPage.bounds(for: .mediaBox)
                if srcBounds.height > 10 && oppBounds.height > 10 {
                    let normMinY = (selBounds.minY - srcBounds.minY) / srcBounds.height
                    let normMaxY = (selBounds.maxY - srcBounds.minY) / srcBounds.height
                    let padY: CGFloat = 0.016
                    let targetMinY = oppBounds.minY + max(0, normMinY - padY) * oppBounds.height
                    let targetMaxY = oppBounds.minY + min(1, normMaxY + padY) * oppBounds.height
                    let alignedRect = NSRect(
                        x: oppBounds.minX,
                        y: targetMinY,
                        width: oppBounds.width,
                        height: max(22, targetMaxY - targetMinY)
                    )
                    if let spatialStr = oppPage.selection(for: alignedRect)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       spatialStr.count >= 4 {
                        pairedPageText = spatialStr
                    }
                }
            }
            if pairedPageText == nil {
                pairedPageText = oppPage.string
            }
        }

        // 同步划选内容到右侧边栏翻译工作台
        sidebarTransSourceTextView.string = rawText
        if isDrawerOpen && currentWorkbenchTab == 2 {
            sidebarTranslateAction()
        }

        translationProviderLabel?.stringValue = "正在生成 \(currentTranslationMode.displayName)…"
        let loadingHTML = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: "*正在翻译划选段落与数学公式…*")
        translationPreviewWebView?.loadHTMLString(loadingHTML, baseURL: nil)

        activeTranslationTask?.cancel()
        translationRequestID = UUID()
        let requestID = translationRequestID
        currentTranslatedMarkdown = ""
        translationActionButtons.forEach { $0.isEnabled = false }
        activeTranslationTask = LLMTranslationService.shared.translate(
            text: rawText,
            mode: currentTranslationMode,
            pairedPageText: pairedPageText
        ) { [weak self] result in
            guard let self = self, !self.isClosed, self.translationRequestID == requestID else { return }
            self.currentTranslatedMarkdown = result.isSuccess ? result.translatedMarkdown : ""
            self.translationActionButtons.forEach { $0.isEnabled = result.isSuccess }
            self.translationProviderLabel?.stringValue = "引擎：\(result.providerLabel)"
            let html = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: result.translatedMarkdown)
            self.translationPreviewWebView?.loadHTMLString(html, baseURL: nil)
        }
    }

    @objc private func translationModeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < LLMTranslationMode.allCases.count else { return }
        currentTranslationMode = LLMTranslationMode.allCases[idx]
        triggerSelectionTranslation()
    }

    @objc private func translationSettingsClicked() {
        LLMTranslationService.shared.presentSettingsModal(from: view.window) { [weak self] in
            self?.triggerSelectionTranslation()
        }
    }

    @objc private func translationInsertToNoteClicked() {
        guard let pdfView = activeSelectionPDFView else { return }
        _ = quoteSelectionToPaperNote(from: pdfView, customTranslation: currentTranslatedMarkdown)
        selectionPopover.close()
    }

    @objc private func translationSaveAsAnnotClicked() {
        guard !currentTranslatedMarkdown.isEmpty else { return }
        _ = createAnnotationFromCurrentSelection(
            color: .green,
            note: currentTranslatedMarkdown,
            linkedURL: nil,
            linkedTitle: nil
        )
        selectionPopover.close()
    }

    @objc private func translationCopyClicked() {
        guard !currentTranslatedMarkdown.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentTranslatedMarkdown, forType: .string)
        selectionPopover.close()
    }

    /// 点击已有高亮时弹出的现代化气泡（支持一键切换高亮颜色 + 渲染 LaTeX 公式笔记）
    private func showExistingAnnotationPopover(_ annot: PaperAnnotation, in pdfView: InteractivePDFView, at point: NSPoint) {
        let vc = NSViewController()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        // 顶部栏：位置标识 + 4 色一键切换圆点
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6

        let header = NSTextField(labelWithString: "\(annot.side.shortBadge) · 第 \(annot.pageIndex + 1) 页")
        header.font = .systemFont(ofSize: 11.5, weight: .semibold)
        header.textColor = .secondaryLabelColor
        topRow.addArrangedSubview(header)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topRow.addArrangedSubview(spacer)

        for c in HighlightColor.allCases {
            let sw = HighlightSwatchButton(color: c, selected: c == annot.color, target: self, action: #selector(changeExistingAnnotColor(_:)))
            sw.identifier = NSUserInterfaceItemIdentifier("\(annot.id)|\(c.rawValue)")
            topRow.addArrangedSubview(sw)
        }
        stack.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(equalToConstant: 290).isActive = true

        // 若有 Markdown+LaTeX 笔记，使用轻量 WKWebView 直接渲染数学公式
        if !annot.markdownNote.isEmpty {
            let noteWeb = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            noteWeb.setValue(false, forKey: "drawsBackground")
            noteWeb.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                noteWeb.widthAnchor.constraint(equalToConstant: 290),
                noteWeb.heightAnchor.constraint(equalToConstant: 105)
            ])
            let html = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: annot.markdownNote)
            noteWeb.loadHTMLString(html, baseURL: nil)
            stack.addArrangedSubview(noteWeb)
        }

        if let link = annot.linkedURL {
            let openLinkBtn = NSButton(title: " 🔗 \(annot.linkedTitle ?? link)", target: self, action: #selector(openAnnotLinkFromPopover(_:)))
            openLinkBtn.bezelStyle = .rounded
            openLinkBtn.controlSize = .small
            openLinkBtn.contentTintColor = .controlAccentColor
            openLinkBtn.identifier = NSUserInterfaceItemIdentifier(link)
            stack.addArrangedSubview(openLinkBtn)
        }

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 6

        let editBtn = NSButton(title: annot.markdownNote.isEmpty ? "添加笔记 (LaTeX)" : "编辑笔记", target: self, action: #selector(editAnnotFromPopover(_:)))
        editBtn.bezelStyle = .rounded
        editBtn.controlSize = .small
        editBtn.identifier = NSUserInterfaceItemIdentifier(annot.id)

        let attachBtn = NSButton(title: "挂接链接/文件", target: self, action: #selector(attachAnnotFromPopover(_:)))
        attachBtn.bezelStyle = .rounded
        attachBtn.controlSize = .small
        attachBtn.identifier = NSUserInterfaceItemIdentifier(annot.id)

        let delBtn = NSButton(title: "删除", target: self, action: #selector(deleteAnnotFromPopover(_:)))
        delBtn.bezelStyle = .rounded
        delBtn.controlSize = .small
        delBtn.contentTintColor = .systemRed
        delBtn.identifier = NSUserInterfaceItemIdentifier(annot.id)

        btnRow.addArrangedSubview(editBtn)
        btnRow.addArrangedSubview(attachBtn)
        btnRow.addArrangedSubview(delBtn)
        stack.addArrangedSubview(btnRow)

        vc.view = stack
        selectionPopover.contentViewController = vc
        selectionPopover.behavior = .transient
        selectionPopover.show(relativeTo: NSRect(x: point.x, y: point.y, width: 2, height: 2), of: pdfView, preferredEdge: .maxY)
    }

    @objc private func changeExistingAnnotColor(_ sender: HighlightSwatchButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        let parts = raw.components(separatedBy: "|")
        guard parts.count == 2,
              var paper = currentPaper,
              let idx = paper.annotations.firstIndex(where: { $0.id == parts[0] }),
              let newColor = HighlightColor(rawValue: parts[1]) else { return }
        paper.annotations[idx].color = newColor
        paper.annotations[idx].colorHex = newColor.solidColor.hexString
        LibraryStore.shared.savePaper(paper, notify: true)
        selectionPopover.close()
    }

    @objc private func openAnnotLinkFromPopover(_ sender: NSButton) {
        selectionPopover.close()
        if let link = sender.identifier?.rawValue {
            openUniversalLink(link)
        }
    }

    @objc private func editAnnotFromPopover(_ sender: NSButton) {
        selectionPopover.close()
        guard let id = sender.identifier?.rawValue,
              let annot = currentPaper?.annotations.first(where: { $0.id == id }) else { return }
        presentNoteEditorModal(for: annot)
    }

    @objc private func attachAnnotFromPopover(_ sender: NSButton) {
        selectionPopover.close()
        guard let id = sender.identifier?.rawValue,
              let annot = currentPaper?.annotations.first(where: { $0.id == id }) else { return }
        presentAttachLinkModal(for: annot)
    }

    @objc private func deleteAnnotFromPopover(_ sender: NSButton) {
        selectionPopover.close()
        guard let id = sender.identifier?.rawValue,
              var paper = currentPaper else { return }
        paper.annotations.removeAll { $0.id == id }
        LibraryStore.shared.savePaper(paper, notify: true)
    }

    // MARK: - 7. Sheet Modals for Editing Markdown+LaTeX Notes & Attaching Links/Files
    func presentNoteEditorModal(for annot: PaperAnnotation) {
        guard !isClosed else { return }
        let editorVC = NoteEditorSheetController(annotation: annot) { [weak self] chosenColor, updatedMarkdown in
            guard let self = self,
                  var paper = self.currentPaper,
                  let idx = paper.annotations.firstIndex(where: { $0.id == annot.id }) else { return false }
            paper.annotations[idx].color = chosenColor
            paper.annotations[idx].colorHex = chosenColor.solidColor.hexString
            paper.annotations[idx].markdownNote = updatedMarkdown
            guard LibraryStore.shared.savePaper(paper, notify: true) else { return false }
            if !self.isDrawerOpen {
                self.toggleRightDrawerAction()
            }
            self.notesNeedRefresh = true
            self.refreshNotesDrawerWebView()
            return true
        }

        if let parentWin = view.window {
            let sheetWin = NSWindow(contentViewController: editorVC)
            sheetWin.styleMask = [.titled, .closable]
            sheetWin.setContentSize(NSSize(width: 540, height: 430))
            activeSheetWindow = sheetWin
            parentWin.beginSheet(sheetWin) { [weak self] _ in
                self?.activeSheetWindow = nil
            }
        }
    }

    private func presentAttachLinkModal(for annot: PaperAnnotation) {
        let alert = NSAlert()
        alert.messageText = "在选中文字上挂接网页、本地文件或关联论文"
        alert.informativeText = "绑定后，点击 PDF 中的这处高亮或下划线即可一键打开目标网页、本地代码或关联论文。"
        alert.addButton(withTitle: "保存绑定")
        alert.addButton(withTitle: "选择本地文件…")
        alert.addButton(withTitle: "取消")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 115))

        let titleField = NSTextField(frame: NSRect(x: 0, y: 82, width: 420, height: 24))
        titleField.placeholderString = "链接显示名称（例如：官方实现代码 / 附录证明 / 关联论文）"
        titleField.stringValue = annot.linkedTitle ?? ""
        container.addSubview(titleField)

        let urlField = NSTextField(frame: NSRect(x: 0, y: 46, width: 420, height: 24))
        urlField.placeholderString = "输入 https:// 网页地址、本地路径 或从下方选择库内论文"
        urlField.stringValue = annot.linkedURL ?? ""
        container.addSubview(urlField)

        let paperPop = NSPopUpButton(frame: NSRect(x: 0, y: 8, width: 420, height: 26))
        paperPop.addItem(withTitle: "— 或者直接选择文献库中的另一篇论文进行绑定 —")
        let otherPapers = LibraryStore.shared.papers.filter { $0.id != self.paperId }
        for p in otherPapers {
            paperPop.addItem(withTitle: "📄 \(p.title)")
        }
        container.addSubview(paperPop)

        alert.accessoryView = container
        let resp = alert.runModal()

        if resp == .alertFirstButtonReturn {
            guard var paper = currentPaper,
                  let idx = paper.annotations.firstIndex(where: { $0.id == annot.id }) else { return }

            let popIdx = paperPop.indexOfSelectedItem
            if popIdx > 0 && popIdx - 1 < otherPapers.count {
                let targetP = otherPapers[popIdx - 1]
                paper.annotations[idx].linkedURL = "paper://\(targetP.id)"
                paper.annotations[idx].linkedTitle = titleField.stringValue.isEmpty ? "论文: \(targetP.title)" : titleField.stringValue
            } else {
                let rawURL = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                paper.annotations[idx].linkedURL = rawURL.isEmpty ? nil : rawURL
                paper.annotations[idx].linkedTitle = titleField.stringValue.isEmpty ? rawURL : titleField.stringValue
            }
            LibraryStore.shared.savePaper(paper, notify: true)

        } else if resp == .alertSecondButtonReturn {
            let panel = NSOpenPanel()
            panel.title = "选择要挂接到该段文字的本地文件"
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            if panel.runModal() == .OK, let fileURL = panel.url,
               let res = LibraryStore.shared.addLocalAttachment(to: self.paperId, fileURL: fileURL),
               var paper = currentPaper,
               let idx = paper.annotations.firstIndex(where: { $0.id == annot.id }) {
                paper.annotations[idx].linkedURL = res.urlOrPath
                paper.annotations[idx].linkedTitle = titleField.stringValue.isEmpty ? res.title : titleField.stringValue
                LibraryStore.shared.savePaper(paper, notify: true)
            }
        }
    }

    @objc private func addGeneralPageNoteAction() {
        guard var paper = currentPaper else { return }
        let activeCol = primaryActiveColumn()
        let doc = activeCol.pdfView.document
        let pageIdx = activeCol.pdfView.currentPage.flatMap { doc?.index(for: $0) } ?? 0
        let newAnnot = PaperAnnotation(
            side: activeCol.side,
            pageIndex: pageIdx,
            rects: [],
            selectedText: "第 \(pageIdx + 1) 页随笔笔记",
            color: .yellow,
            markdownNote: "",
            linkedURL: nil,
            linkedTitle: nil,
            pdfDocumentId: activeCol.activePDFDocumentId
        )
        paper.annotations.append(newAnnot)
        LibraryStore.shared.savePaper(paper, notify: true)
        presentNoteEditorModal(for: newAnnot)
    }

    @objc private func revealNotesMarkdownAction() {
        let url = LibraryStore.shared.markdownNotesURL(for: paperId)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openUniversalLink(_ urlOrPath: String) {
        if urlOrPath.hasPrefix("dualpdf://jump") {
            handleNoteJumpURL(urlOrPath)
            return
        }
        if urlOrPath.hasPrefix("paper://") {
            let targetId = String(urlOrPath.dropFirst("paper://".count))
            onRequestOpenPaperTab?(targetId)
            return
        }
        if urlOrPath.hasPrefix("http://") || urlOrPath.hasPrefix("https://"),
           let url = URL(string: urlOrPath) {
            NSWorkspace.shared.open(url)
            return
        }
        let fileURL = URL(fileURLWithPath: urlOrPath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        } else if let webURL = URL(string: urlOrPath) {
            NSWorkspace.shared.open(webURL)
        }
    }

    // MARK: - 8. Top Bar, Page Navigation & Menu Shortcut Actions
    func setDisplayMode(_ segment: Int) {
        // 非法模式回到双 PDF；笔记仅由右侧栏入口打开。
        let pdfMode = (0..<modeSeg.segmentCount).contains(segment) ? segment : 2
        modeSeg.selectedSegment = pdfMode
        applyDisplayMode(pdfMode)
    }

    private func updateZoomIndicators() {
        func update(_ button: ModernHoverButton, for column: CleanPDFColumnView) {
            guard column.pdfView.document != nil else {
                button.title = "—"
                button.toolTip = "当前缩放 —，点击适应列宽"
                return
            }

            let zoomPercent = Int((column.pdfView.scaleFactor * 100).rounded())
            button.title = "\(zoomPercent)%"
            button.toolTip = "当前缩放 \(zoomPercent)%，点击适应列宽"
        }

        update(leftZoomFitBtn, for: toolbarLeftColumn)
        update(rightZoomFitBtn, for: toolbarRightColumn)
    }

    func focusSearchField() {
        searchTargetColumn = nil
        openSearchAction()
    }

    @objc func modeChangedAction() {
        applyDisplayMode(modeSeg.selectedSegment)
    }

    func applyColumnSplitRatio() {
        guard (modeSeg.selectedSegment == 2 || modeSeg.selectedSegment == 3),
              !leftCol.isHidden, !rightCol.isHidden,
              splitView.bounds.width > 200 else { return }
        let total = splitView.bounds.width - splitView.dividerThickness
        guard total > 100 else { return }
        splitView.adjustSubviews()
    }

    private func applyDisplayMode(_ segment: Int) {
        beginLayoutChange()
        switch segment {
        case 0:
            leftCol.isHidden = false
            rightCol.isHidden = true
            swapBtn.isHidden = true
            dualColumnSeparator?.isHidden = true
            syncScrollBtn.isHidden = true
            resetAlignBtn.isHidden = true
            leftControlsContainer.isHidden = false
            rightControlsContainer.isHidden = true
            dualColumnControlsSep?.isHidden = true
        case 1:
            leftCol.isHidden = true
            rightCol.isHidden = false
            swapBtn.isHidden = true
            dualColumnSeparator?.isHidden = true
            syncScrollBtn.isHidden = true
            resetAlignBtn.isHidden = true
            leftControlsContainer.isHidden = true
            rightControlsContainer.isHidden = false
            dualColumnControlsSep?.isHidden = true
        default:
            leftCol.isHidden = false
            rightCol.isHidden = false
            swapBtn.isHidden = false
            swapBtn.isEnabled = true
            dualColumnSeparator?.isHidden = false
            syncScrollBtn.isHidden = false
            resetAlignBtn.isHidden = abs(pageRatioOffset) < 0.005
            leftControlsContainer.isHidden = false
            rightControlsContainer.isHidden = false
            dualColumnControlsSep?.isHidden = false
            applyColumnSplitRatio()
        }
        updateToolbarLayout()
        splitView.adjustSubviews()
        if isLeftOverlayOpen {
            if let active = outlineActiveColumn, active.isHidden { outlineActiveColumn = primaryActiveColumn() }
            positionOutlineSidebar(for: outlineActiveColumn ?? primaryActiveColumn())
        }
        if segment != 2 { lastReadingColumn = segment == 0 ? leftCol : rightCol }
        if !isLoadingDocuments { finishPendingLayout() }
        updateNavigationSource()
        updatePageIndicatorAndSaveProgress()
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            performInPDFSearch()
        }
    }

    private func configureColumnToolbar(for col: CleanPDFColumnView) {
        let toolbar = col.columnToolbar
        toolbar.setUnifiedMarkupEnabled(true)
        toolbar.onOutline = { [weak self, weak col] in
            guard let self = self, let col = col else { return }
            if self.isLeftOverlayOpen, self.primaryActiveColumn() !== col {
                // Keep the existing overlay open but move it to the column
                // whose outline button was just clicked.
                self.lastReadingColumn = col
                self.outlineActiveColumn = col
                self.updateNavigationSource()
                self.positionOutlineSidebar(for: col)
                return
            }
            self.lastReadingColumn = col
            self.updateNavigationSource()
            self.toggleOutlineSidebar(for: col)
        }
        toolbar.onContinuous = { [weak self, weak col] in
            guard let self = self, let col = col else { return }
            self.beginLayoutChange()
            col.toggleContinuousMode()
            self.view.layoutSubtreeIfNeeded()
            self.scheduleLayoutCompletion()
            self.updatePageIndicatorAndSaveProgress()
        }
        toolbar.onFitWidth = { [weak self, weak col] in
            guard let self = self, let col = col else { return }
            self.fitColumn(col)
        }
        toolbar.onSearch = { [weak self, weak col] in
            guard let self = self, let col = col else { return }
            self.lastReadingColumn = col
            self.searchTargetColumn = col
            self.updateNavigationSource()
            self.openSearchAction()
            if !self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.performInPDFSearch()
            }
        }
        toolbar.onNotes = { [weak self, weak col] in
            guard let self = self, let col = col else { return }
            self.lastReadingColumn = col
            if !self.isDrawerOpen { self.toggleRightDrawerAction() }
            self.switchWorkbenchTab(to: 1)
        }
        toolbar.onToolChanged = { [weak self] tool in
            self?.applyUnifiedMarkupTool(tool)
        }
        toolbar.onColorChanged = { [weak self] color in
            guard let self = self else { return }
            self.leftCol.pdfView.markupColor = color
            self.rightCol.pdfView.markupColor = color
            self.unifiedMarkupToolbar.setColor(color)
            self.leftCol.pdfView.updateSelectedMarkupColor(color)
            self.rightCol.pdfView.updateSelectedMarkupColor(color)
        }
        toolbar.onUndo = { [weak self] in
            self?.primaryActiveColumn().pdfView.undoMarkup()
            self?.refreshUnifiedMarkupState()
        }
        toolbar.onRedo = { [weak self] in
            self?.primaryActiveColumn().pdfView.redoMarkup()
            self?.refreshUnifiedMarkupState()
        }
        toolbar.setViewMode(col.pdfView.displayMode)
        toolbar.setOutlineActive(isLeftOverlayOpen)
        toolbar.setUndoRedoEnabled(canUndo: col.pdfView.canUndoMarkup, canRedo: col.pdfView.canRedoMarkup)
    }

    private func installCommandScrollMonitor() {
        guard commandScrollMonitor == nil else { return }
        commandScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, !self.isClosed,
                  event.modifierFlags.contains(.command),
                  !self.view.isHiddenOrHasHiddenAncestor,
                  let window = self.view.window, event.window === window else { return event }
            let point = self.view.convert(event.locationInWindow, from: nil)
            guard let hit = self.view.hitTest(point) else { return event }
            var candidate: NSView? = hit
            var target: CleanPDFColumnView?
            while let view = candidate {
                if let column = view as? CleanPDFColumnView { target = column; break }
                candidate = view.superview
            }
            guard let column = target, !column.isHidden, column.pdfView.document != nil else { return event }
            self.lastReadingColumn = column
            let step = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * 0.012
                : event.scrollingDeltaY * 0.08
            guard step.isFinite else { return nil }
            let proposed = column.pdfView.scaleFactor * CGFloat(exp(step))
            let clamped = min(5.0, max(0.25, proposed))
            if abs(clamped - column.pdfView.scaleFactor) > 0.0001 {
                self.applyCommandScrollZoom(in: column, to: clamped)
            }
            return nil
        }
    }

    private func installUndoKeyMonitor() {
        guard undoKeyMonitor == nil else { return }
        undoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, !self.isClosed,
                  !self.view.isHiddenOrHasHiddenAncestor,
                  let window = self.view.window, event.window === window,
                  event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers?.lowercased(),
                  characters == "z" else { return event }
            guard !self.readerIsEditingText() else { return event }
            let column: CleanPDFColumnView?
            if let last = self.lastReadingColumn, !last.isHidden {
                column = last
            } else {
                column = self.primaryActiveColumn()
            }
            guard let column, !column.isHidden, column.pdfView.document != nil else { return event }
            if event.modifierFlags.contains(.shift) {
                column.pdfView.redoMarkup()
            } else {
                column.pdfView.undoMarkup()
            }
            return nil
        }
    }

    private func removeUndoKeyMonitor() {
        guard let undoKeyMonitor else { return }
        NSEvent.removeMonitor(undoKeyMonitor)
        self.undoKeyMonitor = nil
    }

    private func readerIsEditingText() -> Bool {
        guard let responder = view.window?.firstResponder else { return false }
        if responder is NSTextView { return true }
        var node: NSView? = responder as? NSView
        while let current = node {
            if current is WKWebView { return true }
            node = current.superview
        }
        return false
    }

    private func removeCommandScrollMonitor() {
        guard let commandScrollMonitor else { return }
        NSEvent.removeMonitor(commandScrollMonitor)
        self.commandScrollMonitor = nil
    }

    private func applyCommandScrollZoom(in column: CleanPDFColumnView, to scale: CGFloat) {
        guard !isClosed, !column.isHidden, column.pdfView.document != nil else { return }
        let clamped = min(5.0, max(0.25, scale))
        guard abs(column.pdfView.scaleFactor - clamped) > 0.0001 else { return }
        setZoom(column, autoScales: false, scaleFactor: clamped)
    }

    @objc func swapColumnsAction() {
        guard modeSeg.selectedSegment == 2 else { return }
        finishPendingLayout()
        beginLayoutChange()
        isSwapped.toggle()
        splitView.removeArrangedSubview(leftCol)
        splitView.removeArrangedSubview(rightCol)
        if isSwapped {
            splitView.addArrangedSubview(rightCol)
            splitView.addArrangedSubview(leftCol)
        } else {
            splitView.addArrangedSubview(leftCol)
            splitView.addArrangedSubview(rightCol)
        }
        updateBannerPositions()
        applyColumnSplitRatio()
        if isLeftOverlayOpen { positionOutlineSidebar(for: outlineActiveColumn ?? primaryActiveColumn()) }
        finishPendingLayout()
    }

    func updateSyncButtonStyle() {
        let isSync = (syncScrollBtn.state == .on)
        syncScrollBtn.wantsLayer = true
        syncScrollBtn.layer?.cornerRadius = 6
        if isSync {
            syncScrollBtn.normalTintColor = .controlAccentColor
            syncScrollBtn.normalBgColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
            syncScrollBtn.image = NSImage(systemSymbolName: "link", accessibilityDescription: "双栏同步中")?
                .withSymbolConfiguration(.init(pointSize: 11.5, weight: .semibold))
            syncScrollBtn.title = ""
            syncScrollBtn.toolTip = "双栏同步滚动已开启 (点击关闭)\n小技巧：按住 ⌥ Option 键滚动任意一栏可微调双栏段落对齐差"
        } else {
            syncScrollBtn.normalTintColor = .secondaryLabelColor
            syncScrollBtn.normalBgColor = .clear
            syncScrollBtn.image = NSImage(systemSymbolName: "link", accessibilityDescription: "独立滚动")?
                .withSymbolConfiguration(.init(pointSize: 11.5, weight: .regular))
            syncScrollBtn.title = ""
            syncScrollBtn.toolTip = "双栏独立滚动 (同步已关闭，点击开启同步)"
        }
        syncScrollBtn.updateColors()
    }

    @objc func toggleSyncScrollAction() {
        finishPendingLayout()
        isScrollSyncEnabled = (syncScrollBtn.state == .on)
        updateSyncButtonStyle()
        if isScrollSyncEnabled {
            let active = primaryActiveColumn()
            let opp = (active === leftCol) ? rightCol : leftCol
            syncScroll(from: active, to: opp)
        }
        persistReaderState(from: primaryActiveColumn())
    }

    @objc func resetSyncAlignmentAction() {
        finishPendingLayout()
        pageRatioOffset = 0.0
        resetAlignBtn.isHidden = true
        viewportCoordinator.setAlignment(0)
        let active = primaryActiveColumn()
        let opp = (active === leftCol) ? rightCol : leftCol
        syncScroll(from: active, to: opp)
        persistReaderState(from: active)
    }

    // Toolbar actions resolve visual positions after a column swap.
    @objc func leftPrevPageAction() { stepPage(in: toolbarLeftColumn, delta: -1) }
    @objc func leftNextPageAction() { stepPage(in: toolbarLeftColumn, delta: 1) }
    @objc func leftPromptPageJumpAction() { promptPageJump(for: toolbarLeftColumn) }
    @objc func leftZoomInAction() { zoomColumn(toolbarLeftColumn, factor: 1.15) }
    @objc func leftZoomOutAction() { zoomColumn(toolbarLeftColumn, factor: 1 / 1.15) }
    @objc func leftZoomFitAction() { fitColumn(toolbarLeftColumn) }
    @objc func rightPrevPageAction() { stepPage(in: toolbarRightColumn, delta: -1) }
    @objc func rightNextPageAction() { stepPage(in: toolbarRightColumn, delta: 1) }
    @objc func rightPromptPageJumpAction() { promptPageJump(for: toolbarRightColumn) }
    @objc func rightZoomInAction() { zoomColumn(toolbarRightColumn, factor: 1.15) }
    @objc func rightZoomOutAction() { zoomColumn(toolbarRightColumn, factor: 1 / 1.15) }
    @objc func rightZoomFitAction() { fitColumn(toolbarRightColumn) }

    private func stepPage(in column: CleanPDFColumnView, delta: Int) {
        finishPendingLayout()
        guard column.pdfView.document != nil else { return }
        let current = currentPageIndex(in: column)
        goToColumnPageIndex(column, pageIndex: current + delta, recordHistory: false)
    }

    private func zoomColumn(_ column: CleanPDFColumnView, factor: CGFloat) {
        finishPendingLayout()
        guard !column.isHidden, column.pdfView.document != nil else { return }
        let scale = max(0.001, min(column.pdfView.scaleFactor * factor, 64))
        setZoom(column, autoScales: false, scaleFactor: scale)
    }

    private func setZoom(_ column: CleanPDFColumnView, autoScales: Bool, scaleFactor: CGFloat? = nil) {
        finishPendingLayout()
        guard !isClosed, !column.isHidden, column.pdfView.document != nil else { return }
        beginLayoutChange()
        viewportCoordinator.setZoom(in: column, autoScales: autoScales, scaleFactor: scaleFactor)
        lastReadingColumn = column
        finishPendingLayout()
    }

    private func fitColumn(_ column: CleanPDFColumnView) {
        setZoom(column, autoScales: true)
    }

    private func promptPageJump(for column: CleanPDFColumnView) {
        guard let doc = column.pdfView.document, doc.pageCount > 0 else { return }
        let cur = currentPageIndex(in: column) + 1
        let colName = modeSeg.selectedSegment == 2
            ? (column === toolbarLeftColumn ? "左栏" : "右栏")
            : (column === leftCol ? "原文栏" : "译文栏")
        let alert = NSAlert()
        alert.messageText = "跳转到\(colName)指定页码"
        alert.informativeText = "请输入目标页码 (1 – \(doc.pageCount))："
        alert.addButton(withTitle: "跳转")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        input.stringValue = "\(cur)"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn,
           let targetPage = Int(input.stringValue.trimmingCharacters(in: .whitespaces)),
           targetPage >= 1, targetPage <= doc.pageCount {
            goToColumnPageIndex(column, pageIndex: targetPage - 1, recordHistory: true)
        }
    }

    // --- 兼容旧版入口 ---
    @objc func prevPageAction() { leftPrevPageAction() }
    @objc func nextPageAction() { leftNextPageAction() }
    @objc private func promptPageJumpAction() { leftPromptPageJumpAction() }

    private func goToColumnPageIndex(_ column: CleanPDFColumnView, pageIndex: Int, recordHistory: Bool) {
        finishPendingLayout()
        guard !column.isHidden, let doc = column.pdfView.document,
              pageIndex >= 0, pageIndex < doc.pageCount, let page = doc.page(at: pageIndex) else { return }
        if recordHistory { pushJumpRecord(from: column, label: "页码跳转前") }
        navigate(in: column) { column.pdfView.go(to: page) }
    }

    private func navigate(in column: CleanPDFColumnView, synchronize: Bool = true, activate: Bool = true, _ action: () -> Void) {
        finishPendingLayout()
        guard !isClosed, viewportCoordinator.acceptsEvents, !column.isHidden, column.pdfView.document != nil else { return }
        if activate { lastReadingColumn = column }
        viewportCoordinator.performUpdate {
            action()
            cacheViewport(column)
        }
        if synchronize { syncScroll(from: column, to: column === leftCol ? rightCol : leftCol) }
        if activate { scheduleReadingPositionSave(from: column) }
        else { persistReaderState(from: primaryActiveColumn()) }
        updatePageIndicatorAndSaveProgress()
    }

    private func goToPageIndex(_ pageIndex: Int, recordHistory: Bool) {
        goToColumnPageIndex(primaryActiveColumn(), pageIndex: pageIndex, recordHistory: recordHistory)
    }

    @objc func zoomInActiveColumnAction() { zoomColumn(primaryActiveColumn(), factor: 1.15) }
    @objc func zoomOutActiveColumnAction() { zoomColumn(primaryActiveColumn(), factor: 1 / 1.15) }
    @objc func zoomFitActiveColumnAction() { fitColumn(primaryActiveColumn()) }

    @objc func toggleRightDrawerAction() {
        sidebarNoteView.flushPendingSave()
        finishPendingLayout()
        beginLayoutChange()
        let wasOpen = !rightDrawer.isHidden && !masterSplitView.isSubviewCollapsed(rightDrawer)
        if wasOpen { preferredDrawerWidth = rightDrawer.frame.width }
        isDrawerOpen = !wasOpen
        drawerToggleBtn.state = isDrawerOpen ? .on : .off
        rightDrawer.isHidden = !isDrawerOpen
        masterSplitView.adjustSubviews()
        if isDrawerOpen {
            let width = min(max(280, preferredDrawerWidth), max(280, masterSplitView.bounds.width - 440))
            masterSplitView.setPosition(masterSplitView.bounds.width - width - masterSplitView.dividerThickness, ofDividerAt: 0)
            notesNeedRefresh = true
            refreshNotesDrawerWebView()
            updateRightSidebarMetadataUI()
        } else {
            masterSplitView.setPosition(masterSplitView.bounds.width, ofDividerAt: 0)
        }
        masterSplitView.adjustSubviews()
        pdfCanvasContainer.layoutSubtreeIfNeeded()
        applyColumnSplitRatio()
        finishPendingLayout()
    }

    private func promptToImportOrReplacePDF(in col: CleanPDFColumnView) {
        let activePDFId = col.activePDFDocumentId
        let panel = NSOpenPanel()
        panel.title = "选择要绑定或替换到此栏的 PDF 文件（仅限当前论文集）"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleDroppedPDFOnColumn(url, col: col, targetPDFId: activePDFId)
    }

    private func presentColumnDropLimitBanner(openedName: String) {
        if let wc = view.window?.windowController as? MultiTabMainWindowController {
            wc.showStatusBanner(DocumentOpenCopy.columnOnlyOne(openedName))
            return
        }
        let alert = NSAlert()
        alert.messageText = DocumentOpenCopy.columnOnlyOne(openedName)
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func handleDroppedPDFOnColumn(_ url: URL, col: CleanPDFColumnView, targetPDFId: String? = nil) {
        let pdfId = targetPDFId ?? col.activePDFDocumentId
        if pdfId == PDFSide.original.rawValue {
            LibraryStore.shared.importPDF(for: paperId, side: .original, from: url)
            setColumnSource(col, source: .pdf(id: PDFSide.original.rawValue))
        } else if pdfId == PDFSide.translated.rawValue {
            LibraryStore.shared.importPDF(for: paperId, side: .translated, from: url)
            setColumnSource(col, source: .pdf(id: PDFSide.translated.rawValue))
        } else {
            let existingTitle = currentPaper?.pdfTitle(for: pdfId)
            if let doc = LibraryStore.shared.addAdditionalPDF(to: paperId, from: url, title: existingTitle, replacingId: pdfId) {
                setColumnSource(col, source: .pdf(id: doc.id))
            }
        }
    }

    private func promptToAddAdditionalPDF(for col: CleanPDFColumnView) {
        let panel = NSOpenPanel()
        panel.title = "向当前论文集添加新的 PDF 文档（如补充材料、附录或另一译本）"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "设置本论文集内新 PDF 的显示名称"
        alert.informativeText = "该 PDF 将归属于当前论文集，可在左栏或右栏随时切换对照阅读。"
        alert.addButton(withTitle: "添加并在此栏打开")
        alert.addButton(withTitle: "取消")

        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        titleField.stringValue = url.deletingPathExtension().lastPathComponent
        alert.accessoryView = titleField

        if alert.runModal() == .alertFirstButtonReturn {
            if let added = LibraryStore.shared.addAdditionalPDF(to: paperId, from: url, title: titleField.stringValue) {
                setColumnSource(col, source: .pdf(id: added.id))
            }
        }
    }

    private func promptToCreateNewNote() {
        sidebarNoteView.flushPendingSave()
        let alert = NSAlert()
        alert.messageText = "新建本论文精读笔记"
        alert.informativeText = "每篇论文可包含多篇独立 Markdown + LaTeX 笔记，统一在右侧边栏编辑和预览。"
        alert.addButton(withTitle: "创建并打开")
        alert.addButton(withTitle: "取消")

        let count = (currentPaper?.effectiveNoteDocuments.count ?? 1) + 1
        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        titleField.stringValue = "精读笔记 \(count)"
        alert.accessoryView = titleField

        if alert.runModal() == .alertFirstButtonReturn {
            if let created = LibraryStore.shared.createNoteDocument(for: paperId, title: titleField.stringValue) {
                openNotesSidebar(noteId: created.id)
            }
        }
    }

    // MARK: - 9. Right Drawer Refresh (Outline / Notes WebView / Links & Related Papers)
    private func rebuildOutlineData() {
        outlineItems.removeAll()
        let column = navigationSourceColumn
        let docWithOutline = column.pdfView.document
        outlineSourceColumn = column
        outlineSourceDocument = docWithOutline

        if let doc = docWithOutline, let outlineRoot = doc.outlineRoot {
            func traverse(_ node: PDFOutline, depth: Int) {
                for i in 0..<node.numberOfChildren {
                    guard let child = node.child(at: i) else { continue }
                    let pageIdx = child.destination?.page.flatMap { doc.index(for: $0) } ?? 0
                    outlineItems.append((title: child.label ?? "章节", pageIndex: pageIdx, depth: depth))
                    traverse(child, depth: depth + 1)
                }
            }
            traverse(outlineRoot, depth: 0)
        }
        if outlineItems.isEmpty, let d = docWithOutline {
            let maxTextScanPages = min(d.pageCount, 12)
            for i in 0..<d.pageCount {
                if i < maxTextScanPages {
                    let firstLine = d.page(at: i)?.string?
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .first(where: { $0.count > 3 && !$0.contains("deepseek") }) ?? "第 \(i + 1) 页"
                    outlineItems.append((title: String(firstLine.prefix(30)), pageIndex: i, depth: 0))
                } else {
                    outlineItems.append((title: "第 \(i + 1) 页", pageIndex: i, depth: 0))
                }
            }
        }
        outlineTableView.reloadData()
    }

    private func refreshNotesDrawerWebView() {
        guard isDrawerOpen, notesNeedRefresh else { return }
        guard let paper = currentPaper else { return }
        notesNeedRefresh = false
        let html = MarkdownMathRenderer.buildNotesFeedHTML(paper: paper, annotations: paper.annotations)
        notesWebView.loadHTMLString(html, baseURL: nil)
    }

    @objc private func unlinkRelatedFromDrawer(_ sender: NSButton) {
        if let targetId = sender.identifier?.rawValue {
            LibraryStore.shared.unlinkRelatedPapers(paperAId: paperId, paperBId: targetId)
            refreshLinksDrawerView()
        }
    }

    @objc private func addRelatedPaperInDrawer() {
        let others = LibraryStore.shared.papers.filter { $0.id != paperId }
        guard !others.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "添加双向关联论文"
        alert.addButton(withTitle: "建立关联")
        alert.addButton(withTitle: "取消")

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 64))
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 34, width: 360, height: 26))
        for p in others { pop.addItem(withTitle: p.title) }
        let noteF = NSTextField(frame: NSRect(x: 0, y: 2, width: 360, height: 24))
        noteF.placeholderString = "关联关系备注（如：基线架构 / 后续演进）"
        box.addSubview(pop)
        box.addSubview(noteF)
        alert.accessoryView = box

        if alert.runModal() == .alertFirstButtonReturn {
            let idx = pop.indexOfSelectedItem
            if idx >= 0 && idx < others.count {
                LibraryStore.shared.linkRelatedPapers(paperAId: paperId, paperBId: others[idx].id, note: noteF.stringValue)
                refreshLinksDrawerView()
            }
        }
    }

    // MARK: - WKScriptMessageHandler (Respond to clicks inside the LaTeX Notes WebView)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "noteAction",
              let dict = message.body as? [String: String],
              let action = dict["action"],
              var paper = currentPaper else { return }

        if action == "jumpLink", let url = dict["extra"], !url.isEmpty {
            handleNoteJumpURL(url)
            return
        }

        guard let id = dict["id"],
              let annot = paper.annotations.first(where: { $0.id == id }) else { return }

        switch action {
        case "jump":
            jumpToAnnotation(annot)
        case "edit":
            presentNoteEditorModal(for: annot)
        case "delete":
            paper.annotations.removeAll { $0.id == id }
            LibraryStore.shared.savePaper(paper, notify: true)
        case "openLink":
            if let link = annot.linkedURL {
                openUniversalLink(link)
            }
        default:
            break
        }
    }

    func handleNoteJumpURL(_ urlString: String) {
        guard !isClosed, let paper = currentPaper else { return }
        finishPendingLayout()
        guard urlString.hasPrefix("dualpdf://jump") else {
            openUniversalLink(urlString)
            return
        }
        guard let comps = URLComponents(string: urlString) else { return }
        var params: [String: String] = [:]
        for item in (comps.queryItems ?? []) {
            if let val = item.value { params[item.name] = val }
        }

        if let annotId = params["annot"],
           let annot = paper.annotations.first(where: { $0.id == annotId }) {
            jumpToAnnotation(annot)
            return
        }

        let targetPDFId = params["pdf"] ?? PDFSide.original.rawValue
        let targetPageIdx = params["page"].flatMap { Int($0) } ?? 0

        let targetCol: CleanPDFColumnView
        if leftCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = leftCol
        } else if rightCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = rightCol
        } else {
            targetCol = primaryActiveColumn()
        }

        if targetCol.isHidden {
            setDisplayMode(2)
            view.layoutSubtreeIfNeeded()
        }
        pushJumpRecord(from: targetCol, label: "返回")
        if targetCol.contentSource != .pdf(id: targetPDFId) {
            setColumnSource(targetCol, source: .pdf(id: targetPDFId))
            view.layoutSubtreeIfNeeded()
        }
        if let doc = targetCol.pdfView.document,
           targetPageIdx >= 0, targetPageIdx < doc.pageCount,
           let page = doc.page(at: targetPageIdx) {
            navigate(in: targetCol) { targetCol.pdfView.go(to: page) }
        }
        updatePageIndicatorAndSaveProgress()
    }

    func jumpToAnnotation(_ annot: PaperAnnotation) {
        guard !isClosed else { return }
        finishPendingLayout()
        let targetPDFId = annot.effectivePDFId

        let targetCol: CleanPDFColumnView
        if leftCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = leftCol
        } else if rightCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = rightCol
        } else {
            targetCol = (annot.side == .original) ? leftCol : rightCol
        }

        if targetCol.isHidden {
            setDisplayMode(2)
            view.layoutSubtreeIfNeeded()
        }
        pushJumpRecord(from: targetCol, label: "笔记跳转前")
        if targetCol.contentSource != .pdf(id: targetPDFId) {
            setColumnSource(targetCol, source: .pdf(id: targetPDFId))
            view.layoutSubtreeIfNeeded()
        }
        if let doc = targetCol.pdfView.document,
           annot.pageIndex >= 0, annot.pageIndex < doc.pageCount,
           let page = doc.page(at: annot.pageIndex) {
            navigate(in: targetCol) {
                if let firstRect = annot.rects.first?.cgRect {
                    let dest = PDFDestination(page: page, at: NSPoint(x: firstRect.minX, y: firstRect.maxY + 40))
                    targetCol.pdfView.go(to: dest)
                } else {
                    targetCol.pdfView.go(to: page)
                }
            }
        }
    }

    // MARK: - 10. In-PDF Search & Match Navigation
    func controlTextDidChange(_ obj: Notification) {
        performInPDFSearch()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closeSearchAction()
            return true
        }
        return false
    }

    private func performInPDFSearch() {
        invalidateSearch()
        let generation = searchGeneration
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchMatches.removeAll()
        currentSearchMatchIndex = 0
        for column in [leftCol, rightCol] { column.pdfView.highlightedSelections = nil }
        searchNavSeg.isHidden = true
        searchMatchLabel.isHidden = query.isEmpty
        guard !query.isEmpty else { return }
        searchMatchLabel.stringValue = "搜索中…"
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isClosed, self.searchGeneration == generation,
                  !self.searchContainer.isHidden else { return }
            let visibleColumns = [self.leftCol, self.rightCol].filter { !$0.isHidden }
            let columns: [CleanPDFColumnView]
            if let target = self.searchTargetColumn, visibleColumns.contains(where: { $0 === target }) {
                columns = [target]
            } else {
                columns = visibleColumns
            }
            self.searchController.search(query, columns: columns) { [weak self] matches in
                guard let self = self, !self.isClosed, self.searchGeneration == generation,
                      self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                self.currentSearchMatches = matches
                self.searchNavSeg.isHidden = matches.isEmpty
                if matches.isEmpty { self.searchMatchLabel.stringValue = "无匹配" }
                else { self.jumpToSearchMatch(at: 0) }
            }
        }
        searchTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    @objc private func searchFieldReturnPressed() {
        guard !currentSearchMatches.isEmpty else { return }
        let next = (currentSearchMatchIndex + 1) % currentSearchMatches.count
        jumpToSearchMatch(at: next)
    }

    @objc private func searchNavClicked() {
        guard !currentSearchMatches.isEmpty else { return }
        if searchNavSeg.selectedSegment == 0 {
            let prev = (currentSearchMatchIndex - 1 + currentSearchMatches.count) % currentSearchMatches.count
            jumpToSearchMatch(at: prev)
        } else {
            let next = (currentSearchMatchIndex + 1) % currentSearchMatches.count
            jumpToSearchMatch(at: next)
        }
    }

    private func jumpToSearchMatch(at index: Int) {
        finishPendingLayout()
        guard index >= 0, index < currentSearchMatches.count else { return }
        currentSearchMatchIndex = index
        let item = currentSearchMatches[index]
        guard !item.col.isHidden, item.selection.pages.allSatisfy({ $0.document === item.col.pdfView.document }) else {
            performInPDFSearch()
            return
        }
        searchMatchLabel.stringValue = "\(index + 1)/\(currentSearchMatches.count)"
        let otherCol = (item.col === leftCol) ? rightCol : leftCol
        otherCol.pdfView.clearSelection()
        navigate(in: item.col) {
            item.col.pdfView.go(to: item.selection)
            item.col.pdfView.setCurrentSelection(item.selection, animate: false)
        }
    }

    private func invalidateSearch() {
        searchGeneration = UUID()
        searchTask?.cancel()
        searchTask = nil
        searchController.cancel()
        currentSearchMatches.removeAll()
        for column in [leftCol, rightCol] { column.pdfView.highlightedSelections = nil }
    }
}

// MARK: - Outline TableView DataSource & Delegate
extension ReaderTabViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return outlineItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = outlineItems[row]
        let cell = NSTableCellView()

        let leadIndent = CGFloat(min(item.depth, 4)) * 12.0 + 8.0
        let titleLbl = NSTextField(labelWithString: item.title)
        titleLbl.font = .systemFont(ofSize: 13.5, weight: item.depth == 0 ? .medium : .regular)
        titleLbl.textColor = .labelColor
        titleLbl.lineBreakMode = .byTruncatingTail
        titleLbl.translatesAutoresizingMaskIntoConstraints = false

        let pageBadge = NSTextField(labelWithString: "P.\(item.pageIndex + 1)")
        pageBadge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pageBadge.textColor = .secondaryLabelColor
        pageBadge.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(titleLbl)
        cell.addSubview(pageBadge)

        NSLayoutConstraint.activate([
            titleLbl.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leadIndent),
            titleLbl.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: pageBadge.leadingAnchor, constant: -6),

            pageBadge.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            pageBadge.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func outlineRowClicked() {
        guard !isUpdatingOutlineSelection else { return }
        let row = outlineTableView.clickedRow >= 0 ? outlineTableView.clickedRow : outlineTableView.selectedRow
        guard row >= 0, row < outlineItems.count else { return }
        let pageIdx = outlineItems[row].pageIndex
        guard let source = outlineSourceColumn else { return }
        goToColumnPageIndex(source, pageIndex: pageIdx, recordHistory: true)
    }
}

// MARK: - NSSplitViewDelegate (Keep Master / Child Split In Proportional Balance & Allow Free Dragging)
extension ReaderTabViewController: NSSplitViewDelegate {
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let split = notification.object as? NSSplitView else { return }
        if split === self.splitView, self.splitView.isTrackingDivider, !isRestoringLayout,
           !leftCol.isHidden, !rightCol.isHidden {
            let total = max(1, split.bounds.width - split.dividerThickness)
            columnSplitRatio = min(0.95, max(0.05, (split.subviews.first?.frame.width ?? total / 2) / total))
        }
        if split === masterSplitView {
            updateDrawerVisibility()
            if isDrawerOpen, !masterSplitView.isTrackingDivider, rightDrawer.frame.width < 280,
               masterSplitView.bounds.width >= 720 {
                masterSplitView.setPosition(masterSplitView.bounds.width - 280 - masterSplitView.dividerThickness, ofDividerAt: 0)
            }
            if !isRestoringLayout { applyColumnSplitRatio() }
        }
        scheduleLayoutCompletion()
    }

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        if splitView === self.splitView {
            return leftCol.isHidden || rightCol.isHidden
        }
        return false
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        if splitView === masterSplitView && subview === rightDrawer {
            return true
        }
        return false
    }

    func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        return false
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === masterSplitView {
            if isDrawerOpen {
                return max(440, masterSplitView.bounds.width - 620)
            } else {
                return masterSplitView.bounds.width
            }
        } else if splitView === self.splitView {
            let visibleCount = self.splitView.subviews.filter { !$0.isHidden }.count
            if visibleCount <= 1 {
                return 0
            }
            let total = splitView.bounds.width - splitView.dividerThickness
            return max(0, total * 0.05)
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === masterSplitView {
            if isDrawerOpen {
                return masterSplitView.bounds.width - 280
            } else {
                return masterSplitView.bounds.width
            }
        } else if splitView === self.splitView {
            let visibleCount = self.splitView.subviews.filter { !$0.isHidden }.count
            if visibleCount <= 1 {
                return splitView.bounds.width
            }
            let total = splitView.bounds.width - splitView.dividerThickness
            return max(0, total * 0.95)
        }
        return proposedMaximumPosition
    }
}
