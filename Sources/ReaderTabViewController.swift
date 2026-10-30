import Cocoa
import PDFKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Zotero 7 Native Theming & Flipped Views
enum ZoteroTheme {
    static let sidebarBg = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.18, alpha: 1.0)
            : NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.97, alpha: 1.0)
    }

    static let sidebarHeaderBg = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.165, green: 0.175, blue: 0.195, alpha: 1.0)
            : NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.955, alpha: 1.0)
    }

    static let dividerColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.25, alpha: 1.0)
            : NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.89, alpha: 1.0)
    }

    static let activeRailItemBg = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.25, green: 0.32, blue: 0.45, alpha: 0.45)
            : NSColor(calibratedRed: 0.85, green: 0.89, blue: 0.96, alpha: 1.0)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
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
    var onRequestOpenPaperTab: ((String) -> Void)?

    let leftCol = CleanPDFColumnView(side: .original)
    let rightCol = CleanPDFColumnView(side: .translated)
    private let splitView = NSSplitView()

    // 极简现代化顶栏控件
    private let topBar = NSVisualEffectView()
    private let leftSidebarToggleBtn = NSButton()
    private let modeSeg = NSSegmentedControl(labels: ["仅原文", "仅译文", "双栏对照"], trackingMode: .selectOne, target: nil, action: nil)
    let syncScrollBtn = NSButton()
    private let syncZoomBtn = NSButton()
    private let resetAlignBtn = NSButton()

    private let prevPageBtn = NSButton()
    private let pageJumpBtn = NSButton()
    private let nextPageBtn = NSButton()

    private let searchField = NSSearchField()
    private let searchMatchLabel = NSTextField(labelWithString: "")
    private let searchNavSeg = NSSegmentedControl()
    private let drawerToggleBtn = NSButton()

    // 左侧浮动覆盖式边栏（大纲目录与页面预览，无碰撞直接覆盖）
    private let leftOverlaySidebar = NSVisualEffectView()
    private let leftOverlaySeg = NSSegmentedControl(labels: ["📑 目录大纲", "🖼️ 页面预览"], trackingMode: .selectOne, target: nil, action: nil)
    private let leftOverlayCloseBtn = NSButton()
    private let thumbnailsContainer = NSView()
    private let pdfThumbnailView = PDFThumbnailView()
    private var isLeftOverlayOpen = false

    // 浮动“返回”胶囊按钮状态（左栏与右栏独立记录与显示）
    private var leftJumpStack: [ReadingJumpRecord] = []
    private var rightJumpStack: [ReadingJumpRecord] = []
    private weak var lastJumpCol: CleanPDFColumnView?

    // 双栏与侧边栏两级布局：外层 masterSplitView 分隔 PDF 绘图区与右侧边栏，内层 splitView 保持双栏 50%/50% 对等
    private let masterSplitView = NSSplitView()
    private let pdfCanvasContainer = NSView()

    // 右侧工作台分栏 (Zotero 7 原生排版：顶部论文标题、左侧信息/笔记/翻译面板、右侧垂直图标栏)
    private let rightDrawer = ZoteroRightDrawerView()
    private var isDrawerOpen = false
    private var currentWorkbenchTab: Int = 0 // 0: Info, 1: Notes, 2: Translation, 3: Attachments, 4: Tags, 5: Links
    private var notesNeedRefresh = true
    private var linksNeedRefresh = true

    private let sidebarHeaderView = ZoteroSidebarHeaderView()
    private let sidebarPaperTitleLabel = NSTextField(labelWithString: "")

    private let workbenchRailView = NSView()
    private var workbenchRailButtons: [NSButton] = []

    private let workbenchContentScrollView = NSScrollView()
    private let tabInfoContainer = FlippedStackView()
    private let tabNotesContainer = FlippedStackView()
    private let tabTranslationContainer = FlippedStackView()
    private let tabAttachmentsContainer = FlippedStackView()
    private let tabTagsContainer = FlippedStackView()
    private let tabLinksContainer = FlippedStackView()

    private let metadataFieldsStack = FlippedStackView()
    private let searchToggleBtn = NSButton()
    private let linksStackView = FlippedStackView()

    private let outlineContainer = NSView()
    private let outlineTableView = NSTableView()
    private var outlineItems: [(title: String, pageIndex: Int, depth: Int)] = []
    private var isUpdatingOutlineSelection = false
    private var notesWebView: WKWebView!

    // 同步滚动、对齐微调偏移与缩放状态
    private var isScrollSyncEnabled = true
    private var isZoomSyncEnabled = true
    private var isSyncingScroll = false
    private var isSyncingZoom = false
    private var isLoadingDocuments = false
    private var isClosed = false
    private var documentLoadID = UUID()
    private var pendingLibraryFields: LibraryChange.Fields = []
    private let annotationRenderer = PDFAnnotationRenderer()
    private let searchController = PDFSearchController()
    private var searchTask: DispatchWorkItem?
    private weak var lastReadingColumn: CleanPDFColumnView?
    private var isSwapped = false
    private var loadedHasOrig = false
    private var loadedHasTrans = false
    private var loadedOrigModDate: Date?
    private var loadedTransModDate: Date?
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

    init(paperId: String) {
        self.paperId = paperId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var currentPaper: PaperItem? {
        return LibraryStore.shared.paper(withId: paperId)
    }

    deinit {
        searchTask?.cancel()
        searchController.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func prepareForClose() {
        guard !isClosed else { return }
        leftCol.noteColumnView.cleanupForClose()
        rightCol.noteColumnView.cleanupForClose()
        LibraryStore.shared.flushReadingState()
        isClosed = true
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        searchTask?.cancel()
        searchController.cancel()
        NotificationCenter.default.removeObserver(self)
        notesWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "noteAction")
        selectionPopover.close()
        if let sheet = activeSheetWindow { sheet.sheetParent?.endSheet(sheet) }
        annotationRenderer.reset()
        currentSearchMatches.removeAll()
        leftCol.pdfView.document = nil
        rightCol.pdfView.document = nil
    }

    func didResignActiveTab() {
        leftCol.noteColumnView.flushPendingSave()
        rightCol.noteColumnView.flushPendingSave()
        LibraryStore.shared.flushReadingState()
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1360, height: 840))
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root

        pageRatioOffset = currentPaper?.syncOffsetDelta ?? 0.0

        setupMainCanvasAndDrawer(in: root)
        setupFloatingBackBanners()
        setupSyncAndCallbacks()
        loadPaperDocuments()

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

        leftSidebarToggleBtn.bezelStyle = .texturedRounded
        leftSidebarToggleBtn.controlSize = .small
        leftSidebarToggleBtn.setButtonType(.pushOnPushOff)
        leftSidebarToggleBtn.state = .off
        leftSidebarToggleBtn.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "展开大纲与页面缩略图")?.withSymbolConfiguration(barIconConfig)
        leftSidebarToggleBtn.toolTip = "展开/收起左侧大纲与页面缩略图 (⌘1)"
        leftSidebarToggleBtn.keyEquivalent = "1"
        leftSidebarToggleBtn.keyEquivalentModifierMask = [.command]
        leftSidebarToggleBtn.target = self
        leftSidebarToggleBtn.action = #selector(toggleLeftSidebarAction)

        modeSeg.selectedSegment = 2
        modeSeg.controlSize = .regular
        modeSeg.segmentDistribution = .fillProportionally
        modeSeg.toolTip = "切换阅读模式：仅原文 / 仅译文 / 双栏对照 (默认)"
        modeSeg.target = self
        modeSeg.action = #selector(modeChangedAction)
        modeSeg.translatesAutoresizingMaskIntoConstraints = false
        modeSeg.widthAnchor.constraint(equalToConstant: 226).isActive = true

        let swapBtn = NSButton()
        swapBtn.bezelStyle = .texturedRounded
        swapBtn.controlSize = .small
        swapBtn.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "左右互换")?.withSymbolConfiguration(barSubIconConfig)
        swapBtn.toolTip = "左右两栏位置互换 (⇧⌘X)"
        swapBtn.target = self
        swapBtn.action = #selector(swapColumnsAction)

        syncScrollBtn.bezelStyle = .texturedRounded
        syncScrollBtn.controlSize = .small
        syncScrollBtn.setButtonType(.pushOnPushOff)
        syncScrollBtn.state = .on
        syncScrollBtn.image = NSImage(systemSymbolName: "link", accessibilityDescription: "同步滚动")?.withSymbolConfiguration(barSubIconConfig)
        syncScrollBtn.title = " 同步"
        syncScrollBtn.imagePosition = .imageLeading
        syncScrollBtn.toolTip = "开启/关闭双栏同步滚动 (⇧⌘S)\n小技巧：按住 ⌥ Option 键滚动任意一栏可微调双栏段落对齐差"
        syncScrollBtn.target = self
        syncScrollBtn.action = #selector(toggleSyncScrollAction)

        syncZoomBtn.bezelStyle = .texturedRounded
        syncZoomBtn.controlSize = .small
        syncZoomBtn.setButtonType(.pushOnPushOff)
        syncZoomBtn.state = .on
        syncZoomBtn.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "同步缩放")?.withSymbolConfiguration(barSubIconConfig)
        syncZoomBtn.toolTip = "双栏同步缩放开关"
        syncZoomBtn.target = self
        syncZoomBtn.action = #selector(toggleSyncZoomAction)

        resetAlignBtn.bezelStyle = .inline
        resetAlignBtn.controlSize = .small
        resetAlignBtn.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        resetAlignBtn.contentTintColor = .controlAccentColor
        resetAlignBtn.title = "对齐已微调 ↺"
        resetAlignBtn.toolTip = "当前已通过 ⌥ Option 滚动微调了双栏对齐偏移，点击重置为 0"
        resetAlignBtn.target = self
        resetAlignBtn.action = #selector(resetSyncAlignmentAction)
        resetAlignBtn.isHidden = abs(pageRatioOffset) < 0.005

        // --- Group B (Center): 页码步进/跳转 & 缩放控制 ---
        prevPageBtn.bezelStyle = .texturedRounded
        prevPageBtn.controlSize = .small
        prevPageBtn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "上一页")?.withSymbolConfiguration(barSubIconConfig)
        prevPageBtn.toolTip = "上一页"
        prevPageBtn.target = self
        prevPageBtn.action = #selector(prevPageAction)

        pageJumpBtn.bezelStyle = .texturedRounded
        pageJumpBtn.controlSize = .small
        pageJumpBtn.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        pageJumpBtn.title = "1 / 1"
        pageJumpBtn.toolTip = "点击输入页码快速跳转"
        pageJumpBtn.target = self
        pageJumpBtn.action = #selector(promptPageJumpAction)

        nextPageBtn.bezelStyle = .texturedRounded
        nextPageBtn.controlSize = .small
        nextPageBtn.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "下一页")?.withSymbolConfiguration(barSubIconConfig)
        nextPageBtn.toolTip = "下一页"
        nextPageBtn.target = self
        nextPageBtn.action = #selector(nextPageAction)

        let zoomOutBtn = NSButton()
        zoomOutBtn.bezelStyle = .texturedRounded
        zoomOutBtn.controlSize = .small
        zoomOutBtn.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "缩小")?.withSymbolConfiguration(barSubIconConfig)
        zoomOutBtn.toolTip = "缩小页面 (⌘-)"
        zoomOutBtn.target = self
        zoomOutBtn.action = #selector(zoomOutBothAction)

        let zoomFitBtn = NSButton()
        zoomFitBtn.bezelStyle = .texturedRounded
        zoomFitBtn.controlSize = .small
        zoomFitBtn.title = "自适应"
        zoomFitBtn.toolTip = "自适应列宽 (⌘0)"
        zoomFitBtn.target = self
        zoomFitBtn.action = #selector(zoomFitBothAction)

        let zoomInBtn = NSButton()
        zoomInBtn.bezelStyle = .texturedRounded
        zoomInBtn.controlSize = .small
        zoomInBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "放大")?.withSymbolConfiguration(barSubIconConfig)
        zoomInBtn.toolTip = "放大页面 (⌘+)"
        zoomInBtn.target = self
        zoomInBtn.action = #selector(zoomInBothAction)

        // --- Group C (Right): Zotero 7 原生排版 (页内搜索图标 / 侧边栏图标) ---
        searchField.placeholderString = "页内查找 (⌘F)…"
        searchField.controlSize = .small
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldReturnPressed)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 140).isActive = true
        searchField.isHidden = true

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

        searchToggleBtn.bezelStyle = .texturedRounded
        searchToggleBtn.controlSize = .small
        searchToggleBtn.setButtonType(.pushOnPushOff)
        searchToggleBtn.state = .off
        searchToggleBtn.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "在文档中搜索")?.withSymbolConfiguration(barIconConfig)
        searchToggleBtn.toolTip = "在文档中搜索 (⌘F)"
        searchToggleBtn.keyEquivalent = "f"
        searchToggleBtn.keyEquivalentModifierMask = [.command]
        searchToggleBtn.target = self
        searchToggleBtn.action = #selector(toggleSearchFieldAction)

        drawerToggleBtn.bezelStyle = .texturedRounded
        drawerToggleBtn.controlSize = .small
        drawerToggleBtn.setButtonType(.pushOnPushOff)
        drawerToggleBtn.state = .off
        drawerToggleBtn.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "切换侧边栏")?.withSymbolConfiguration(barIconConfig)
        drawerToggleBtn.title = ""
        drawerToggleBtn.imagePosition = .imageOnly
        drawerToggleBtn.toolTip = "切换侧边栏 (⌘I)"
        drawerToggleBtn.keyEquivalent = "i"
        drawerToggleBtn.keyEquivalentModifierMask = [.command]
        drawerToggleBtn.target = self
        drawerToggleBtn.action = #selector(toggleRightDrawerAction)

        let leftSpacer = NSView()
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let rightSpacer = NSView()
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let barStack = NSStackView(views: [
            leftSidebarToggleBtn,
            makeToolbarSeparator(),
            modeSeg,
            swapBtn,
            makeToolbarSeparator(),
            syncScrollBtn,
            syncZoomBtn,
            resetAlignBtn,
            leftSpacer,
            prevPageBtn,
            pageJumpBtn,
            nextPageBtn,
            makeToolbarSeparator(),
            zoomOutBtn,
            zoomFitBtn,
            zoomInBtn,
            rightSpacer,
            searchMatchLabel,
            searchNavSeg,
            searchField,
            searchToggleBtn,
            drawerToggleBtn
        ])
        barStack.orientation = .horizontal
        barStack.spacing = 6
        barStack.alignment = .centerY
        barStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        barStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(barStack)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(sep)

        container.addSubview(topBar)

        let equalSpacerConstraint = leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor)
        equalSpacerConstraint.priority = NSLayoutConstraint.Priority(240)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: container.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 42),

            barStack.topAnchor.constraint(equalTo: topBar.topAnchor),
            barStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            barStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            barStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),

            sep.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            equalSpacerConstraint
        ])
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
            masterSplitView.topAnchor.constraint(equalTo: root.topAnchor),
            masterSplitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            masterSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            masterSplitView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            pdfCanvasContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 440),
            rightDrawer.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            rightDrawer.widthAnchor.constraint(lessThanOrEqualToConstant: 620)
        ])

        setupMinimalTopBar(in: pdfCanvasContainer)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(leftCol)
        splitView.addArrangedSubview(rightCol)
        pdfCanvasContainer.addSubview(splitView)

        let equalColWidths = leftCol.widthAnchor.constraint(equalTo: rightCol.widthAnchor)
        equalColWidths.priority = .defaultLow

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: pdfCanvasContainer.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: pdfCanvasContainer.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: pdfCanvasContainer.bottomAnchor),

            leftCol.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            rightCol.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            equalColWidths
        ])

        setupLeftOverlaySidebar(in: pdfCanvasContainer)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.splitView.setPosition(self.splitView.bounds.width / 2.0, ofDividerAt: 0)
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

        pdfThumbnailView.pdfView = leftCol.pdfView
        pdfThumbnailView.thumbnailSize = NSSize(width: 140, height: 180)
        pdfThumbnailView.backgroundColor = .clear
        pdfThumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailsContainer.addSubview(pdfThumbnailView)

        container.addSubview(leftOverlaySidebar)

        NSLayoutConstraint.activate([
            leftOverlaySidebar.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            leftOverlaySidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
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
        let shouldShow = searchField.isHidden
        searchField.isHidden = !shouldShow
        searchNavSeg.isHidden = !shouldShow
        searchMatchLabel.isHidden = !shouldShow || currentSearchMatches.isEmpty
        searchToggleBtn.state = shouldShow ? .on : .off
        if shouldShow {
            searchField.becomeFirstResponder()
        } else {
            currentSearchMatches.removeAll()
            leftCol.pdfView.clearSelection()
            rightCol.pdfView.clearSelection()
            searchField.stringValue = ""
        }
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

        sidebarPaperTitleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
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
            sidebarHeaderView.heightAnchor.constraint(equalToConstant: 42),

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
        railStack.spacing = 10
        railStack.edgeInsets = NSEdgeInsets(top: 10, left: 4, bottom: 10, right: 4)
        railStack.translatesAutoresizingMaskIntoConstraints = false
        workbenchRailView.addSubview(railStack)

        NSLayoutConstraint.activate([
            railStack.topAnchor.constraint(equalTo: workbenchRailView.topAnchor),
            railStack.leadingAnchor.constraint(equalTo: workbenchRailView.leadingAnchor),
            railStack.trailingAnchor.constraint(equalTo: workbenchRailView.trailingAnchor)
        ])

        let tabDefs: [(icon: String, tooltip: String, tag: Int)] = [
            ("doc.text", "条目信息 (元数据)", 0),
            ("square.and.pencil", "随手笔记与高亮", 1),
            ("character.book.closed", "划词翻译与学术解析", 2),
            ("paperclip", "PDF 附件与文档", 3),
            ("tag", "论文标签", 4),
            ("link", "相关条目与外部链接", 5)
        ]

        for def in tabDefs {
            let btn = NSButton()
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.image = NSImage(systemSymbolName: def.icon, accessibilityDescription: def.tooltip)?
                .withSymbolConfiguration(.init(pointSize: 19.0, weight: .medium))
            btn.contentTintColor = (def.tag == currentWorkbenchTab) ? .controlAccentColor : .secondaryLabelColor
            btn.toolTip = def.tooltip
            btn.tag = def.tag
            btn.target = self
            btn.action = #selector(workbenchRailButtonClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 34).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 34).isActive = true
            railStack.addArrangedSubview(btn)
            workbenchRailButtons.append(btn)
        }
    }

    @objc private func workbenchRailButtonClicked(_ sender: NSButton) {
        switchWorkbenchTab(to: sender.tag)
    }

    private func switchWorkbenchTab(to index: Int) {
        currentWorkbenchTab = index
        for btn in workbenchRailButtons {
            let isActive = (btn.tag == index)
            btn.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
            btn.wantsLayer = true
            btn.layer?.backgroundColor = isActive ? ZoteroTheme.activeRailItemBg.cgColor : NSColor.clear.cgColor
            btn.layer?.cornerRadius = 6
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
            notesNeedRefresh = true
            refreshNotesDrawerWebView()
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
        tabInfoContainer.spacing = 10
        tabInfoContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabInfoContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let docIcon = NSImageView()
        docIcon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
        docIcon.contentTintColor = .secondaryLabelColor
        docIcon.translatesAutoresizingMaskIntoConstraints = false
        docIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        docIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let secTitle = NSTextField(labelWithString: "信息")
        secTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        secTitle.textColor = .labelColor

        let chevronIcon = NSImageView()
        chevronIcon.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12.0, weight: .medium))
        chevronIcon.contentTintColor = .tertiaryLabelColor
        chevronIcon.translatesAutoresizingMaskIntoConstraints = false
        chevronIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        chevronIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let refreshBtn = NSButton()
        refreshBtn.bezelStyle = .inline
        refreshBtn.isBordered = false
        refreshBtn.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "刷新元数据与引用数")?
            .withSymbolConfiguration(.init(pointSize: 13.0, weight: .medium))
        refreshBtn.contentTintColor = .controlAccentColor
        refreshBtn.toolTip = "重新从 arXiv 与 Semantic Scholar 拉取官方元数据与引用数"
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshMetadataAndCitationsAction)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.widthAnchor.constraint(equalToConstant: 24).isActive = true
        refreshBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true

        secHeader.setViews([docIcon, secTitle, chevronIcon, spacer, refreshBtn], in: .leading)

        metadataFieldsStack.orientation = .vertical
        metadataFieldsStack.alignment = .leading
        metadataFieldsStack.spacing = 5
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

        let noteIcon = NSImageView()
        noteIcon.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
        noteIcon.contentTintColor = .secondaryLabelColor
        noteIcon.translatesAutoresizingMaskIntoConstraints = false
        noteIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        noteIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let secTitle = NSTextField(labelWithString: "随手笔记 (notes.md)")
        secTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        secTitle.textColor = .labelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let addSnippetBtn = NSButton(title: "＋ 引用选词", target: self, action: #selector(addGeneralPageNoteAction))
        addSnippetBtn.bezelStyle = .inline
        addSnippetBtn.controlSize = .small
        addSnippetBtn.font = .systemFont(ofSize: 11.5)

        let openMdBtn = NSButton(title: "定位", target: self, action: #selector(revealNotesMarkdownAction))
        openMdBtn.bezelStyle = .inline
        openMdBtn.controlSize = .small
        openMdBtn.font = .systemFont(ofSize: 11.5)

        secHeader.setViews([noteIcon, secTitle, spacer, addSnippetBtn, openMdBtn], in: .leading)

        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "noteAction")
        notesWebView = WKWebView(frame: .zero, configuration: config)
        notesWebView.setValue(false, forKey: "drawsBackground")
        notesWebView.translatesAutoresizingMaskIntoConstraints = false

        tabNotesContainer.addArrangedSubview(secHeader)
        tabNotesContainer.addArrangedSubview(notesWebView)

        NSLayoutConstraint.activate([
            tabNotesContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabNotesContainer.widthAnchor),
            notesWebView.widthAnchor.constraint(equalTo: tabNotesContainer.widthAnchor),
            notesWebView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])
    }

    private func setupTranslationTab(in parentStack: NSStackView) {
        tabTranslationContainer.orientation = .vertical
        tabTranslationContainer.alignment = .leading
        tabTranslationContainer.spacing = 12
        tabTranslationContainer.translatesAutoresizingMaskIntoConstraints = false
        parentStack.addArrangedSubview(tabTranslationContainer)

        let secHeader = NSStackView()
        secHeader.orientation = .horizontal
        secHeader.alignment = .centerY
        secHeader.spacing = 8
        secHeader.translatesAutoresizingMaskIntoConstraints = false

        let transIcon = NSImageView()
        transIcon.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
        transIcon.contentTintColor = .secondaryLabelColor
        transIcon.translatesAutoresizingMaskIntoConstraints = false
        transIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        transIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let secTitle = NSTextField(labelWithString: "划词翻译与学术解析")
        secTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        secTitle.textColor = .labelColor
        secHeader.setViews([transIcon, secTitle], in: .leading)

        let modeSegControl = NSSegmentedControl(labels: ["学术精读", "术语解析", "要点提炼"], trackingMode: .selectOne, target: self, action: #selector(sidebarTranslationModeChanged(_:)))
        modeSegControl.selectedSegment = 0
        modeSegControl.controlSize = .small
        modeSegControl.segmentDistribution = .fillEqually

        let statusLabel = NSTextField(labelWithString: "● LLM 翻译引擎: SiliconFlow / DeepSeek-V3 (已就绪)")
        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.textColor = NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.2, alpha: 1.0)

        let tipLabel = NSTextField(labelWithString: "在 PDF 任意页面中选中文本，即可浮动呼出 AI 术语精读翻译与段落解析。")
        tipLabel.font = .systemFont(ofSize: 12)
        tipLabel.textColor = .secondaryLabelColor
        tipLabel.maximumNumberOfLines = 3

        tabTranslationContainer.addArrangedSubview(secHeader)
        tabTranslationContainer.addArrangedSubview(modeSegControl)
        tabTranslationContainer.addArrangedSubview(statusLabel)
        tabTranslationContainer.addArrangedSubview(tipLabel)

        NSLayoutConstraint.activate([
            tabTranslationContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            modeSegControl.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor),
            tipLabel.widthAnchor.constraint(equalTo: tabTranslationContainer.widthAnchor)
        ])
    }

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

        let attachIcon = NSImageView()
        attachIcon.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
        attachIcon.contentTintColor = .secondaryLabelColor
        attachIcon.translatesAutoresizingMaskIntoConstraints = false
        attachIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        attachIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let secTitle = NSTextField(labelWithString: "PDF 附件与文档")
        secTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        secTitle.textColor = .labelColor
        secHeader.setViews([attachIcon, secTitle], in: .leading)

        let origBtn = NSButton(title: "📄 原版 PDF (Original EN)…", target: self, action: #selector(importOrigPDFFromSidebar))
        origBtn.bezelStyle = .texturedRounded
        origBtn.controlSize = .small

        let transBtn = NSButton(title: "📄 中文译版 (Translated ZH)…", target: self, action: #selector(importTransPDFFromSidebar))
        transBtn.bezelStyle = .texturedRounded
        transBtn.controlSize = .small

        let extraBtn = NSButton(title: "＋ 导入其它附加文件…", target: self, action: #selector(importAttachmentFromSidebar))
        extraBtn.bezelStyle = .texturedRounded
        extraBtn.controlSize = .small

        tabAttachmentsContainer.addArrangedSubview(secHeader)
        tabAttachmentsContainer.addArrangedSubview(origBtn)
        tabAttachmentsContainer.addArrangedSubview(transBtn)
        tabAttachmentsContainer.addArrangedSubview(extraBtn)

        NSLayoutConstraint.activate([
            tabAttachmentsContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabAttachmentsContainer.widthAnchor),
            origBtn.widthAnchor.constraint(equalTo: tabAttachmentsContainer.widthAnchor),
            transBtn.widthAnchor.constraint(equalTo: tabAttachmentsContainer.widthAnchor),
            extraBtn.widthAnchor.constraint(equalTo: tabAttachmentsContainer.widthAnchor)
        ])
    }

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

        let tagIcon = NSImageView()
        tagIcon.image = NSImage(systemSymbolName: "tag", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
        tagIcon.contentTintColor = .secondaryLabelColor
        tagIcon.translatesAutoresizingMaskIntoConstraints = false
        tagIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        tagIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let secTitle = NSTextField(labelWithString: "论文标签")
        secTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        secTitle.textColor = .labelColor
        secHeader.setViews([tagIcon, secTitle], in: .leading)

        let tagDesc = NSTextField(labelWithString: "用于分类检索与文献库聚合，可在文库中按标签进行多维过滤。")
        tagDesc.font = .systemFont(ofSize: 12)
        tagDesc.textColor = .secondaryLabelColor
        tagDesc.maximumNumberOfLines = 2

        tabTagsContainer.addArrangedSubview(secHeader)
        tabTagsContainer.addArrangedSubview(tagDesc)

        NSLayoutConstraint.activate([
            tabTagsContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabTagsContainer.widthAnchor),
            tagDesc.widthAnchor.constraint(equalTo: tabTagsContainer.widthAnchor)
        ])
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

        let linkIcon = NSImageView()
        linkIcon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15.0, weight: .medium))
        linkIcon.contentTintColor = .secondaryLabelColor
        linkIcon.translatesAutoresizingMaskIntoConstraints = false
        linkIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        linkIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let secTitle = NSTextField(labelWithString: "外部链接与文献引用")
        secTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        secTitle.textColor = .labelColor
        secHeader.setViews([linkIcon, secTitle], in: .leading)

        let arxivBtn = NSButton(title: "🌐 前往 arXiv 官方主页 ↗", target: self, action: #selector(openArxivLinkFromSidebar))
        arxivBtn.bezelStyle = .texturedRounded
        arxivBtn.controlSize = .small

        let hjfyBtn = NSButton(title: "🌐 前往幻觉翻译页面 ↗", target: self, action: #selector(openHjfyLinkFromSidebar))
        hjfyBtn.bezelStyle = .texturedRounded
        hjfyBtn.controlSize = .small

        linksStackView.orientation = .vertical
        linksStackView.alignment = .leading
        linksStackView.spacing = 6
        linksStackView.translatesAutoresizingMaskIntoConstraints = false

        tabLinksContainer.addArrangedSubview(secHeader)
        tabLinksContainer.addArrangedSubview(arxivBtn)
        tabLinksContainer.addArrangedSubview(hjfyBtn)
        tabLinksContainer.addArrangedSubview(linksStackView)

        NSLayoutConstraint.activate([
            tabLinksContainer.widthAnchor.constraint(equalTo: parentStack.widthAnchor, constant: -28),
            secHeader.widthAnchor.constraint(equalTo: tabLinksContainer.widthAnchor),
            arxivBtn.widthAnchor.constraint(equalTo: tabLinksContainer.widthAnchor),
            hjfyBtn.widthAnchor.constraint(equalTo: tabLinksContainer.widthAnchor),
            linksStackView.widthAnchor.constraint(equalTo: tabLinksContainer.widthAnchor)
        ])
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
            keyLabel.font = .systemFont(ofSize: 12.0, weight: .regular)
            keyLabel.textColor = .secondaryLabelColor
            keyLabel.alignment = .right
            keyLabel.translatesAutoresizingMaskIntoConstraints = false

            let valView: NSView
            if isLink {
                let btn = NSButton(title: value, target: self, action: linkAction ?? #selector(openArxivLinkFromSidebar))
                btn.bezelStyle = .inline
                btn.isBordered = false
                btn.contentTintColor = .controlAccentColor
                btn.font = .systemFont(ofSize: 12.5)
                btn.alignment = .left
                btn.translatesAutoresizingMaskIntoConstraints = false
                valView = btn
            } else {
                let valLabel = NSTextField(wrappingLabelWithString: value)
                valLabel.font = .systemFont(ofSize: 12.5)
                valLabel.textColor = .labelColor
                valLabel.isSelectable = true
                valLabel.translatesAutoresizingMaskIntoConstraints = false
                valView = valLabel
            }

            row.addSubview(keyLabel)
            row.addSubview(valView)

            NSLayoutConstraint.activate([
                keyLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                keyLabel.widthAnchor.constraint(equalToConstant: 68),
                keyLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 3),

                valView.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 10),
                valView.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
                valView.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
                valView.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -3)
            ])
            metadataFieldsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: metadataFieldsStack.widthAnchor).isActive = true
        }
        addRow(key: "条目类型", value: "预印本")
        addRow(key: "标题", value: p.title)

        let authorList = p.authors.components(separatedBy: CharacterSet(charactersIn: ";,，；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if authorList.isEmpty {
            addRow(key: "作者", value: "—")
        } else {
            let maxShow = 5
            for (idx, author) in authorList.prefix(maxShow).enumerated() {
                addRow(key: idx == 0 ? "作者" : "", value: author)
            }
            if authorList.count > maxShow {
                addRow(key: "", value: "还有 \(authorList.count - maxShow) 个…")
            }
        }

        addRow(key: "分类", value: p.category.isEmpty ? "—" : p.category)
        addRow(key: "仓库", value: p.venue.isEmpty ? "arXiv" : p.venue)

        let aid = p.cleanArxivId ?? ""
        addRow(key: "存档ID", value: aid.isEmpty ? "—" : "arXiv:\(aid)")
        addRow(key: "日期", value: p.year.isEmpty ? "—" : p.year)
        addRow(key: "DOI", value: aid.isEmpty ? "—" : "10.48550/arXiv.\(aid)")

        if !aid.isEmpty {
            addRow(key: "网址", value: "http://arxiv.org/abs/\(aid)", isLink: true, linkAction: #selector(openArxivLinkFromSidebar))
        } else {
            addRow(key: "网址", value: "—")
        }

        addRow(key: "语言", value: "en-US")

        if !aid.isEmpty {
            addRow(key: "其他", value: "arXiv:\(aid) [cs.CL]")
        }

        if let citations = p.citationCount {
            addRow(key: "引用数", value: "\(citations.formatted()) 次")
        }

        let dateStr = DateFormatter.localizedString(from: p.addedAt, dateStyle: .short, timeStyle: .medium)
        addRow(key: "添加日期", value: dateStr)
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
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = LibraryStore.shared.importAttachmentFile(for: p.id, from: url)
    }

    @objc private func openArxivLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId, let url = URL(string: "https://arxiv.org/abs/\(aid)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openHjfyLinkFromSidebar() {
        guard let aid = currentPaper?.cleanArxivId, let url = URL(string: "https://hjfy.top/arxiv/\(aid)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshMetadataAndCitationsAction() {
        guard let p = currentPaper else { return }
        LibraryStore.shared.refreshPaperArxivMetadata(paperId: p.id) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRightSidebarMetadataUI()
            }
        }
    }

    @objc private func sidebarTranslationModeChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: currentTranslationMode = .academicChinese
        case 1: currentTranslationMode = .explainAndFormula
        default: currentTranslationMode = .conciseSummary
        }
    }

    @objc func toggleLeftSidebarAction() {
        isLeftOverlayOpen.toggle()
        leftOverlaySidebar.isHidden = !isLeftOverlayOpen
        leftSidebarToggleBtn.state = isLeftOverlayOpen ? .on : .off
        if isLeftOverlayOpen {
            pdfThumbnailView.pdfView = leftCol.pdfView
        }
    }

    @objc private func leftOverlaySegChanged() {
        let isTOC = (leftOverlaySeg.selectedSegment == 0)
        outlineContainer.isHidden = !isTOC
        thumbnailsContainer.isHidden = isTOC
        if !isTOC {
            pdfThumbnailView.pdfView = leftCol.pdfView
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
            leftJumpStack.append(record)
            leftCol.backJumpBanner.isHidden = false
            leftCol.backJumpButton.keyEquivalent = "["
            leftCol.backJumpButton.keyEquivalentModifierMask = [.command]
            rightCol.backJumpButton.keyEquivalent = ""
        } else {
            rightJumpStack.append(record)
            rightCol.backJumpBanner.isHidden = false
            rightCol.backJumpButton.keyEquivalent = "["
            rightCol.backJumpButton.keyEquivalentModifierMask = [.command]
            leftCol.backJumpButton.keyEquivalent = ""
        }
    }

    func popBackJumpAction(for col: CleanPDFColumnView) {
        let isLeft = (col === leftCol)
        var stack = isLeft ? leftJumpStack : rightJumpStack
        guard let record = stack.popLast() else {
            col.backJumpBanner.isHidden = true
            col.backJumpButton.keyEquivalent = ""
            return
        }
        if isLeft {
            leftJumpStack = stack
        } else {
            rightJumpStack = stack
        }

        if col.contentSource != .pdf(id: record.pdfDocumentId) {
            setColumnSource(col, source: .pdf(id: record.pdfDocumentId))
            view.layoutSubtreeIfNeeded()
        }

        if let sv = col.internalScrollView() {
            sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: record.scrollOriginY))
            sv.reflectScrolledClipView(sv.contentView)
            if isScrollSyncEnabled {
                let opposite = (col === leftCol) ? rightCol : leftCol
                syncScroll(from: col, to: opposite)
            }
        }

        col.backJumpBanner.isHidden = stack.isEmpty
        if stack.isEmpty {
            col.backJumpButton.keyEquivalent = ""
            let otherCol = (col === leftCol) ? rightCol : leftCol
            let otherStack = (col === leftCol) ? rightJumpStack : leftJumpStack
            if !otherStack.isEmpty {
                otherCol.backJumpButton.keyEquivalent = "["
                otherCol.backJumpButton.keyEquivalentModifierMask = [.command]
                lastJumpCol = otherCol
            } else {
                lastJumpCol = nil
            }
        }
        updatePageIndicatorAndSaveProgress()
    }

    @objc func popBackJumpAction() {
        if let last = lastJumpCol {
            if last === leftCol && !leftJumpStack.isEmpty {
                popBackJumpAction(for: leftCol)
                return
            } else if last === rightCol && !rightJumpStack.isEmpty {
                popBackJumpAction(for: rightCol)
                return
            }
        }
        if !leftJumpStack.isEmpty {
            popBackJumpAction(for: leftCol)
        } else if !rightJumpStack.isEmpty {
            popBackJumpAction(for: rightCol)
        }
    }

    // MARK: - 4. Sync Engine + Option-Key Offset Calibration + Callbacks
    private func setupSyncAndCallbacks() {
        for col in [leftCol, rightCol] {
            if let sv = col.internalScrollView() {
                sv.contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(clipViewBoundsChanged(_:)),
                    name: NSView.boundsDidChangeNotification,
                    object: sv.contentView
                )
            }
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
            col.onCreateNoteRequested = { [weak self, weak col] in
                guard let self = self, let col = col else { return }
                self.promptToCreateNewNote(in: col)
            }

            col.noteColumnView.onSelectNoteId = { [weak self, weak col] noteId in
                guard let self = self, let col = col else { return }
                self.setColumnSource(col, source: .note(id: noteId))
            }
            col.noteColumnView.onCreateNewNoteRequested = { [weak self, weak col] in
                guard let self = self, let col = col else { return }
                self.promptToCreateNewNote(in: col)
            }
            col.noteColumnView.onDeleteCurrentNoteRequested = { [weak self, weak col] noteId in
                guard let self = self, let col = col else { return }
                if LibraryStore.shared.deleteNoteDocument(for: self.paperId, noteId: noteId),
                   let firstNote = self.currentPaper?.effectiveNoteDocuments.first {
                    self.setColumnSource(col, source: .note(id: firstNote.id))
                }
            }
            col.noteColumnView.onNoteContentChanged = { [weak self] updatedNote in
                guard let self = self else { return }
                LibraryStore.shared.saveNoteDocument(for: self.paperId, note: updatedNote, notify: true)
            }
            col.noteColumnView.onJumpLinkClicked = { [weak self, weak col] urlStr in
                guard let self = self else { return }
                self.handleNoteJumpURL(urlStr, fromNoteCol: col)
            }
            col.noteColumnView.onInsertCurrentPDFSelectionLinkRequested = { [weak self, weak col] in
                guard let self = self, let col = col else { return }
                let pdfCol = (col === self.leftCol) ? self.rightCol : self.leftCol
                self.insertJumpLinkFromPDFColumn(pdfCol, intoNoteColumn: col)
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
            col.onFileDropped = dropHandler
            col.pdfView.onFileDropped = dropHandler
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
            col.pdfView.onBeforeInternalLinkJump = { [weak self, weak col] destPage, destPoint, isCmdPressed in
                guard let self = self, let col = col else { return false }
                return self.handleReferenceJump(from: col, toPage: destPage, point: destPoint, inOppositePaneOnly: isCmdPressed)
            }
        }
    }

    func computeContinuousPagePosition(in col: CleanPDFColumnView) -> Double? {
        PDFScrollSynchronizer.continuousPosition(in: col)
    }

    /// 当用户按住 ⌥ Option 键单栏滚动微调时，计算并保存左右两栏的对齐偏移差
    func recordOptionScrollCalibrationOffset() {
        guard !isLoadingDocuments,
              let leftPos = computeContinuousPagePosition(in: leftCol),
              let rightPos = computeContinuousPagePosition(in: rightCol) else { return }
        pageRatioOffset = rightPos - leftPos
        resetAlignBtn.isHidden = abs(pageRatioOffset) < 0.005
        LibraryStore.shared.updateReadingState(for: paperId) { $0.syncOffsetDelta = pageRatioOffset }
    }

    private func handleReferenceJump(
        from sourceCol: CleanPDFColumnView,
        toPage destPage: PDFPage,
        point: NSPoint,
        inOppositePaneOnly: Bool
    ) -> Bool {
        guard let srcDoc = sourceCol.pdfView.document else { return false }
        let targetPageIndex = srcDoc.index(for: destPage)

        if inOppositePaneOnly {
            let oppositeCol = (sourceCol === leftCol) ? rightCol : leftCol
            pushJumpRecord(from: oppositeCol, label: "参考文献跳转前")
            if let oppDoc = oppositeCol.pdfView.document,
               targetPageIndex < oppDoc.pageCount,
               let oppPage = oppDoc.page(at: targetPageIndex) {
                isSyncingScroll = true
                oppositeCol.pdfView.go(to: oppPage)
                isSyncingScroll = false
            }
            return true
        } else {
            pushJumpRecord(from: sourceCol, label: "正文原位")
            return false
        }
    }

    @objc private func clipViewBoundsChanged(_ note: Notification) {
        guard !isLoadingDocuments, !isSyncingScroll, !isClosed,
              let clipView = note.object as? NSClipView else { return }
        if clipView === leftCol.internalScrollView()?.contentView {
            scheduleReadingPositionSave(from: leftCol)
            syncScroll(from: leftCol, to: rightCol)
        } else if clipView === rightCol.internalScrollView()?.contentView {
            scheduleReadingPositionSave(from: rightCol)
            syncScroll(from: rightCol, to: leftCol)
        }
    }

    func syncScroll(from source: CleanPDFColumnView, to target: CleanPDFColumnView) {
        guard !isLoadingDocuments, !isSyncingScroll, !isClosed else { return }
        if NSEvent.modifierFlags.contains(.option) {
            recordOptionScrollCalibrationOffset()
            return
        }
        guard isScrollSyncEnabled else { return }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        PDFScrollSynchronizer.synchronize(from: source, to: target,
            offset: source === leftCol ? pageRatioOffset : -pageRatioOffset)
    }

    @objc private func pdfScaleChanged(_ note: Notification) {
        guard isZoomSyncEnabled, !isSyncingZoom,
              let srcPDFView = note.object as? PDFView else { return }
        let dstPDFView = (srcPDFView === leftCol.pdfView) ? rightCol.pdfView : leftCol.pdfView
        guard abs(dstPDFView.scaleFactor - srcPDFView.scaleFactor) > 0.002 else { return }

        isSyncingZoom = true
        dstPDFView.autoScales = srcPDFView.autoScales
        if !srcPDFView.autoScales {
            dstPDFView.scaleFactor = srcPDFView.scaleFactor
        }
        isSyncingZoom = false
    }

    @objc private func pdfPageChanged(_ note: Notification) {
        guard !isLoadingDocuments, !isClosed else { return }
        updatePageIndicatorAndSaveProgress()
        stripVisibleLinkAnnotationBorders()
        if !isSyncingScroll, let pdf = note.object as? PDFView {
            scheduleReadingPositionSave(from: pdf === leftCol.pdfView ? leftCol : rightCol)
        }
    }

    func primaryActiveColumn() -> CleanPDFColumnView {
        if modeSeg.selectedSegment == 1, rightCol.pdfView.document != nil {
            return rightCol
        }
        if modeSeg.selectedSegment == 0, leftCol.pdfView.document != nil {
            return leftCol
        }
        if let column = lastReadingColumn, !column.isHidden, column.pdfView.document != nil { return column }
        return leftCol.pdfView.document != nil ? leftCol : rightCol
    }

    private func updatePageIndicatorAndSaveProgress() {
        let activePDF = primaryActiveColumn().pdfView
        guard let doc = activePDF.document else {
            pageJumpBtn.title = "0 / 0"
            prevPageBtn.isEnabled = false
            nextPageBtn.isEnabled = false
            return
        }
        let total = doc.pageCount
        let currentIdx = activePDF.currentPage.map { doc.index(for: $0) } ?? 0
        pageJumpBtn.title = "\(currentIdx + 1) / \(total) 页"
        prevPageBtn.isEnabled = (currentIdx > 0)
        nextPageBtn.isEnabled = (currentIdx + 1 < total)

        // 同步高亮右侧目录当前所在章节
        if let matchRow = outlineItems.lastIndex(where: { $0.pageIndex <= currentIdx }) {
            isUpdatingOutlineSelection = true
            outlineTableView.selectRowIndexes(IndexSet(integer: matchRow), byExtendingSelection: false)
            outlineTableView.scrollRowToVisible(matchRow)
            isUpdatingOutlineSelection = false
        }

    }

    private func scheduleReadingPositionSave(from column: CleanPDFColumnView) {
        guard !isLoadingDocuments, !isClosed, !view.isHidden,
              let document = column.pdfView.document,
              let position = computeContinuousPagePosition(in: column), position.isFinite else { return }
        lastReadingColumn = column
        let page = column.pdfView.currentPage.map { document.index(for: $0) } ?? 0
        LibraryStore.shared.updateReadingState(for: paperId) { paper in
            paper.lastReadPage = max(0, page)
            paper.readingPosition = ReadingPosition(side: column.side, continuousPage: position)
            if paper.status == .unread && page > 0 { paper.status = .reading }
        }
    }

    private func fileModificationDate(_ url: URL?) -> Date? {
        guard let url = url else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - 5. Load Paper PDFs, Restore Reading Page, Render Highlights & Build Outline
    func loadPaperDocuments() {
        guard let paper = currentPaper, !isClosed else { return }
        let savedPage = paper.lastReadPage
        pageRatioOffset = paper.syncOffsetDelta
        resetAlignBtn.isHidden = abs(pageRatioOffset) < 0.005

        isLoadingDocuments = true
        notesNeedRefresh = true
        linksNeedRefresh = true

        leftJumpStack.removeAll()
        rightJumpStack.removeAll()
        leftCol.backJumpBanner.isHidden = true
        rightCol.backJumpBanner.isHidden = true
        leftCol.backJumpButton.keyEquivalent = ""
        rightCol.backJumpButton.keyEquivalent = ""
        lastJumpCol = nil

        searchTask?.cancel()
        searchController.cancel()
        currentSearchMatches.removeAll()
        documentLoadID = UUID()
        let loadID = documentLoadID

        let origURL = LibraryStore.shared.pdfURL(for: paper, side: .original)
        let transURL = LibraryStore.shared.pdfURL(for: paper, side: .translated)
        loadedHasOrig = (origURL != nil)
        loadedHasTrans = (transURL != nil)
        loadedOrigModDate = fileModificationDate(origURL)
        loadedTransModDate = fileModificationDate(transURL)

        loadColumnContent(for: leftCol, source: leftCol.contentSource, in: paper)
        loadColumnContent(for: rightCol, source: rightCol.contentSource, in: paper)

        applyAnnotationsToPDFViews()
        rebuildOutlineData()
        refreshNotesDrawerWebView()
        refreshLinksDrawerView()
        updateDrawerBadgeTitles()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isClosed, self.documentLoadID == loadID else { return }
            self.view.layoutSubtreeIfNeeded()
            let column = paper.readingPosition?.side == .translated ? self.rightCol : self.leftCol
            if let position = paper.readingPosition, column.pdfView.document != nil {
                PDFScrollSynchronizer.scroll(to: position.continuousPage, in: column)
                if self.isScrollSyncEnabled {
                    PDFScrollSynchronizer.synchronize(from: column, to: column === self.leftCol ? self.rightCol : self.leftCol,
                        offset: column === self.leftCol ? self.pageRatioOffset : -self.pageRatioOffset)
                }
            } else {
                let total = self.primaryActiveColumn().pdfView.document?.pageCount ?? 0
                self.goToPageIndex(min(max(0, savedPage), max(0, total - 1)), recordHistory: false)
            }
            self.isLoadingDocuments = false
            self.updatePageIndicatorAndSaveProgress()
            self.stripVisibleLinkAnnotationBorders()
            if !self.searchField.stringValue.isEmpty { self.performInPDFSearch() }
        }
    }

    func didBecomeActiveTab() {
        guard !isClosed else { return }
        applyPendingLibraryChanges()
        if let paper = currentPaper {
            let original = LibraryStore.shared.pdfURL(for: paper, side: .original)
            let translated = LibraryStore.shared.pdfURL(for: paper, side: .translated)
            if (original != nil) != loadedHasOrig || (translated != nil) != loadedHasTrans ||
                fileModificationDate(original) != loadedOrigModDate || fileModificationDate(translated) != loadedTransModDate {
                loadPaperDocuments()
            }
        }
        LibraryStore.shared.updateReadingState(for: paperId) { $0.lastOpenedAt = Date() }
        updateRightSidebarMetadataUI()
        updateDrawerBadgeTitles()
        view.layoutSubtreeIfNeeded()
        if (modeSeg.selectedSegment == 2 || modeSeg.selectedSegment == 3) && splitView.bounds.width > 100 {
            let leftW = leftCol.frame.width
            let rightW = rightCol.frame.width
            if leftW < 50 || rightW < 50 {
                splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
            }
        }
        if leftCol.pdfView.autoScales {
            leftCol.pdfView.autoScales = true
        }
        if rightCol.pdfView.autoScales {
            rightCol.pdfView.autoScales = true
        }
    }

    private func stripVisibleLinkAnnotationBorders() {
        let border = PDFBorder()
        border.lineWidth = 0
        for column in [leftCol, rightCol] {
            for page in column.pdfView.visiblePages {
                for annotation in page.annotations where annotation.type == "Link" || annotation.type == "/Link" {
                    annotation.border = border
                    annotation.color = .clear
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

    /// 为单栏设置要展示的内容源（仅限当前论文集内的任意 PDF 或当前论文的笔记文档）
    func setColumnSource(_ col: CleanPDFColumnView, source: ColumnContentSource, syncModeSeg: Bool = true) {
        guard let paper = currentPaper, !isClosed else { return }
        col.noteColumnView.flushPendingSave()
        loadColumnContent(for: col, source: source, in: paper)
        annotationRenderer.apply(paper.annotations, to: col)
        rebuildOutlineData()
        updatePageIndicatorAndSaveProgress()

        if syncModeSeg, !leftCol.isHidden, !rightCol.isHidden {
            if leftCol.contentSource.isPDF && rightCol.contentSource.isNote {
                modeSeg.selectedSegment = 3
            } else if leftCol.contentSource.isPDF && rightCol.contentSource.isPDF {
                modeSeg.selectedSegment = 2
            }
        }
    }

    private func loadColumnContent(for col: CleanPDFColumnView, source: ColumnContentSource, in paper: PaperItem) {
        switch source {
        case .pdf(let requestedPDFId):
            let validPDFIds = Set(paper.allPDFDescriptors.map(\.id))
            let effectivePDFId = validPDFIds.contains(requestedPDFId) ? requestedPDFId : col.side.rawValue
            if let url = LibraryStore.shared.pdfURL(for: paper, pdfId: effectivePDFId),
               let doc = PDFDocument(url: url) {
                col.pdfView.document = doc
                col.pdfView.autoScales = true
                col.applyContentSource(.pdf(id: effectivePDFId), paper: paper, hasPDFDocument: true)
            } else {
                col.pdfView.document = nil
                col.applyContentSource(.pdf(id: effectivePDFId), paper: paper, hasPDFDocument: false)
            }

        case .note(let requestedNoteId):
            let notes = paper.effectiveNoteDocuments
            let effectiveNoteId = notes.contains(where: { $0.id == requestedNoteId }) ? requestedNoteId : (notes.first?.id ?? "main")
            col.applyContentSource(.note(id: effectiveNoteId), paper: paper, hasPDFDocument: false)
        }
    }

    private func applyPendingLibraryChanges() {
        let fields = pendingLibraryFields
        pendingLibraryFields = []
        guard !fields.isEmpty else { return }
        if fields.contains(.pdf) { loadPaperDocuments(); return }
        if fields.contains(.metadata) { updateRightSidebarMetadataUI() }
        if fields.contains(.annotations) {
            notesNeedRefresh = true
            applyAnnotationsToPDFViews()
            refreshNotesDrawerWebView()
            if let paper = currentPaper {
                for col in [leftCol, rightCol] where col.contentSource.isNote {
                    col.applyContentSource(col.contentSource, paper: paper, hasPDFDocument: false)
                }
            }
        }
        if fields.contains(.resources) { linksNeedRefresh = true }
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
        for column in [leftCol, rightCol] { annotationRenderer.apply(paper.annotations, to: column) }
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

        let quoteToNoteBtn = NSButton(title: " 引用笔记", image: NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: "引用笔记") ?? NSImage(), target: self, action: #selector(popoverQuoteToNoteClicked))
        quoteToNoteBtn.imagePosition = .imageLeading
        quoteToNoteBtn.bezelStyle = .texturedRounded
        quoteToNoteBtn.controlSize = .small
        quoteToNoteBtn.contentTintColor = .controlAccentColor
        quoteToNoteBtn.toolTip = "直接将选中文本创建为可点击跳转链接并插入到论文笔记栏中"
        container.addArrangedSubview(quoteToNoteBtn)

        let translateBtn = NSButton(title: " AI 翻译", image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 翻译") ?? NSImage(), target: self, action: #selector(popoverLLMTranslateClicked))
        translateBtn.imagePosition = .imageLeading
        translateBtn.bezelStyle = .texturedRounded
        translateBtn.controlSize = .small
        translateBtn.toolTip = "使用 LLM 或内置学术双语引擎翻译选中文本与公式"
        container.addArrangedSubview(translateBtn)

        let noteBtn = NSButton(title: " 批注", image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "批注") ?? NSImage(), target: self, action: #selector(popoverAddNoteClicked))
        noteBtn.imagePosition = .imageLeading
        noteBtn.bezelStyle = .texturedRounded
        noteBtn.controlSize = .small
        container.addArrangedSubview(noteBtn)

        let linkBtn = NSButton(title: " 链接", image: NSImage(systemSymbolName: "link", accessibilityDescription: "链接") ?? NSImage(), target: self, action: #selector(popoverAttachLinkClicked))
        linkBtn.imagePosition = .imageLeading
        linkBtn.bezelStyle = .texturedRounded
        linkBtn.controlSize = .small
        container.addArrangedSubview(linkBtn)

        let copyBtn = NSButton(title: " 复制", image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制") ?? NSImage(), target: self, action: #selector(popoverCopyClicked))
        copyBtn.imagePosition = .imageLeading
        copyBtn.bezelStyle = .texturedRounded
        copyBtn.controlSize = .small
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

        let sourceCol = (pdfView === rightCol.pdfView) ? rightCol : leftCol
        let oppositeCol = (sourceCol === leftCol) ? rightCol : leftCol

        let pdfBadge = annotation.shortSourceBadge(in: paper)
        let compactExcerpt = annotation.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shortLabelExcerpt = compactExcerpt.count > 36 ? String(compactExcerpt.prefix(36)) + "…" : compactExcerpt
        let jumpURL = "dualpdf://jump?annot=\(annotation.id)&pdf=\(annotation.effectivePDFId)&page=\(annotation.pageIndex)"
        var snippet = "- [📍 \(pdfBadge) · P.\(annotation.pageIndex + 1): “\(shortLabelExcerpt)”](\(jumpURL))\n  > \(compactExcerpt)"
        if let trans = customTranslation?.trimmingCharacters(in: .whitespacesAndNewlines), !trans.isEmpty {
            let formattedTrans = trans.replacingOccurrences(of: "\n", with: "\n  ")
            snippet += "\n  **AI 译注**：\(formattedTrans)"
        }

        // 确保有一栏正在展示笔记（若当前均未展示笔记，则自动在另一栏打开论文主笔记并开启双栏模式）
        let targetNoteCol: CleanPDFColumnView
        if oppositeCol.contentSource.isNote {
            targetNoteCol = oppositeCol
        } else if sourceCol.contentSource.isNote {
            targetNoteCol = sourceCol
        } else {
            targetNoteCol = oppositeCol
            let firstNoteId = currentPaper?.effectiveNoteDocuments.first?.id ?? "main"
            setColumnSource(targetNoteCol, source: .note(id: firstNoteId), syncModeSeg: true)
        }

        if leftCol.isHidden || rightCol.isHidden {
            leftCol.isHidden = false
            rightCol.isHidden = false
            if leftCol.contentSource.isPDF && rightCol.contentSource.isNote {
                modeSeg.selectedSegment = 3
            }
            splitView.adjustSubviews()
            splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
        }

        targetNoteCol.noteColumnView.appendOrInsertMarkdownLink(snippet)
        guard let updatedNote = targetNoteCol.noteColumnView.currentNote else { return nil }
        return (annotation, snippet, updatedNote)
    }

    private func insertJumpLinkFromPDFColumn(_ pdfCol: CleanPDFColumnView, intoNoteColumn noteCol: CleanPDFColumnView) {
        if let sel = pdfCol.pdfView.currentSelection,
           let str = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty {
            _ = quoteSelectionToPaperNote(from: pdfCol.pdfView, selection: sel)
            return
        }
        // 若另一栏当前未划选文字，则直接插入指向该栏当前阅读页码的可跳转书签链接
        guard let paper = currentPaper,
              let doc = pdfCol.pdfView.document else { return }
        let pageIdx = pdfCol.pdfView.currentPage.map { doc.index(for: $0) } ?? 0
        let pdfId = pdfCol.activePDFDocumentId
        let pdfTitle = paper.pdfTitle(for: pdfId)
        let jumpURL = "dualpdf://jump?pdf=\(pdfId)&page=\(pageIdx)"
        let snippet = "- [📍 \(pdfTitle) · 第 \(pageIdx + 1) 页书签](\(jumpURL))"
        noteCol.noteColumnView.appendOrInsertMarkdownLink(snippet)
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

        let actionRow = NSStackView(views: [insertNoteBtn, saveAnnotBtn, copyTransBtn])
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

        translationProviderLabel?.stringValue = "正在生成 \(currentTranslationMode.displayName)…"
        let loadingHTML = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: "*正在翻译划选段落与数学公式…*")
        translationPreviewWebView?.loadHTMLString(loadingHTML, baseURL: nil)

        activeTranslationTask?.cancel()
        activeTranslationTask = LLMTranslationService.shared.translate(
            text: rawText,
            mode: currentTranslationMode,
            pairedPageText: pairedPageText
        ) { [weak self] result in
            guard let self = self, !self.isClosed else { return }
            self.currentTranslatedMarkdown = result.translatedMarkdown
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
            linkedTitle: nil
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
            handleNoteJumpURL(urlOrPath, fromNoteCol: nil)
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
        if segment < modeSeg.segmentCount {
            modeSeg.selectedSegment = segment
        }
        applyDisplayMode(segment)
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    @objc func modeChangedAction() {
        applyDisplayMode(modeSeg.selectedSegment)
    }

    private func applyDisplayMode(_ segment: Int) {
        switch segment {
        case 0: // 仅原文
            if leftCol.contentSource.isNote {
                setColumnSource(leftCol, source: .pdf(id: PDFSide.original.rawValue), syncModeSeg: false)
            }
            leftCol.isHidden = false
            rightCol.isHidden = true
        case 1: // 仅译文
            if rightCol.contentSource.isNote {
                setColumnSource(rightCol, source: .pdf(id: PDFSide.translated.rawValue), syncModeSeg: false)
            }
            leftCol.isHidden = true
            rightCol.isHidden = false
        case 3: // 左文右记 (兼容测试与编程式调用)
            if leftCol.contentSource.isNote {
                setColumnSource(leftCol, source: .pdf(id: PDFSide.original.rawValue), syncModeSeg: false)
            }
            if !rightCol.contentSource.isNote {
                let firstNoteId = currentPaper?.effectiveNoteDocuments.first?.id ?? "main"
                setColumnSource(rightCol, source: .note(id: firstNoteId), syncModeSeg: false)
            }
            leftCol.isHidden = false
            rightCol.isHidden = false
            splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
        default: // 双栏对照 (默认左栏原文 EN + 右栏译文 ZH)
            if leftCol.contentSource.isNote {
                setColumnSource(leftCol, source: .pdf(id: PDFSide.original.rawValue), syncModeSeg: false)
            }
            if rightCol.contentSource.isNote {
                setColumnSource(rightCol, source: .pdf(id: PDFSide.translated.rawValue), syncModeSeg: false)
            }
            leftCol.isHidden = false
            rightCol.isHidden = false
            splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
        }
        splitView.adjustSubviews()
        updatePageIndicatorAndSaveProgress()
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            performInPDFSearch()
        }
    }

    @objc func swapColumnsAction() {
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
        splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
    }

    @objc func toggleSyncScrollAction() {
        isScrollSyncEnabled = (syncScrollBtn.state == .on)
        if isScrollSyncEnabled {
            let active = primaryActiveColumn()
            let opp = (active === leftCol) ? rightCol : leftCol
            syncScroll(from: active, to: opp)
        }
    }

    @objc func resetSyncAlignmentAction() {
        pageRatioOffset = 0.0
        resetAlignBtn.isHidden = true
        if var item = currentPaper {
            item.syncOffsetDelta = 0.0
            LibraryStore.shared.savePaper(item, notify: false)
        }
        let active = primaryActiveColumn()
        let opp = (active === leftCol) ? rightCol : leftCol
        syncScroll(from: active, to: opp)
    }

    @objc private func toggleSyncZoomAction() {
        isZoomSyncEnabled = (syncZoomBtn.state == .on)
    }

    @objc func prevPageAction() {
        let activePDF = primaryActiveColumn().pdfView
        guard let doc = activePDF.document else { return }
        let cur = activePDF.currentPage.map { doc.index(for: $0) } ?? 0
        if cur > 0 {
            goToPageIndex(cur - 1, recordHistory: false)
        }
    }

    @objc func nextPageAction() {
        let activePDF = primaryActiveColumn().pdfView
        guard let doc = activePDF.document else { return }
        let cur = activePDF.currentPage.map { doc.index(for: $0) } ?? 0
        if cur + 1 < doc.pageCount {
            goToPageIndex(cur + 1, recordHistory: false)
        }
    }

    @objc private func promptPageJumpAction() {
        let activePDF = primaryActiveColumn().pdfView
        guard let doc = activePDF.document, doc.pageCount > 0 else { return }
        let cur = (activePDF.currentPage.map { doc.index(for: $0) } ?? 0) + 1

        let alert = NSAlert()
        alert.messageText = "跳转到指定页码"
        alert.informativeText = "请输入目标页码 (1 – \(doc.pageCount))："
        alert.addButton(withTitle: "跳转")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        input.stringValue = "\(cur)"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn,
           let targetPage = Int(input.stringValue.trimmingCharacters(in: .whitespaces)),
           targetPage >= 1, targetPage <= doc.pageCount {
            goToPageIndex(targetPage - 1, recordHistory: true)
        }
    }

    private func goToPageIndex(_ pageIndex: Int, recordHistory: Bool) {
        let primaryCol = primaryActiveColumn()
        let oppositeCol = (primaryCol === leftCol) ? rightCol : leftCol
        if recordHistory {
            pushJumpRecord(from: primaryCol, label: "页码跳转前")
        }
        if let doc = primaryCol.pdfView.document, pageIndex >= 0, pageIndex < doc.pageCount, let p = doc.page(at: pageIndex) {
            primaryCol.pdfView.go(to: p)
            if isScrollSyncEnabled {
                if let oppDoc = oppositeCol.pdfView.document, pageIndex < oppDoc.pageCount, let oppP = oppDoc.page(at: pageIndex) {
                    isSyncingScroll = true
                    oppositeCol.pdfView.go(to: oppP)
                    isSyncingScroll = false
                }
                syncScroll(from: primaryCol, to: oppositeCol)
            }
        } else if let doc = oppositeCol.pdfView.document, pageIndex >= 0, pageIndex < doc.pageCount, let p = doc.page(at: pageIndex) {
            oppositeCol.pdfView.go(to: p)
        }
        updatePageIndicatorAndSaveProgress()
    }

    @objc func zoomInBothAction() {
        for col in [leftCol, rightCol] {
            col.pdfView.autoScales = false
            col.pdfView.scaleFactor = min(col.pdfView.scaleFactor * 1.15, 5.0)
        }
    }

    @objc func zoomOutBothAction() {
        for col in [leftCol, rightCol] {
            col.pdfView.autoScales = false
            col.pdfView.scaleFactor = max(col.pdfView.scaleFactor / 1.15, 0.25)
        }
    }

    @objc func zoomFitBothAction() {
        for col in [leftCol, rightCol] {
            col.pdfView.autoScales = true
        }
    }

    @objc func toggleRightDrawerAction() {
        isDrawerOpen.toggle()
        drawerToggleBtn.state = isDrawerOpen ? .on : .off
        rightDrawer.isHidden = !isDrawerOpen
        masterSplitView.adjustSubviews()
        if isDrawerOpen {
            let drawerWidth: CGFloat = 360
            let availableWidth = masterSplitView.bounds.width
            if availableWidth > drawerWidth + 300 {
                masterSplitView.setPosition(availableWidth - drawerWidth, ofDividerAt: 0)
            }
            notesNeedRefresh = true
            refreshNotesDrawerWebView()
            updateRightSidebarMetadataUI()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isClosed else { return }
            self.splitView.setPosition(self.splitView.bounds.width / 2.0, ofDividerAt: 0)
            self.leftCol.pdfView.autoScales = true
            self.rightCol.pdfView.autoScales = true
        }
    }

    private func promptToImportOrReplacePDF(in col: CleanPDFColumnView) {
        let activePDFId = col.activePDFDocumentId
        let panel = NSOpenPanel()
        panel.title = "选择要绑定或替换到此栏的 PDF 文件（仅限当前论文集）"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleDroppedPDFOnColumn(url, col: col, targetPDFId: activePDFId)
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

    private func promptToCreateNewNote(in col: CleanPDFColumnView) {
        let alert = NSAlert()
        alert.messageText = "新建本论文精读笔记"
        alert.informativeText = "每篇论文可包含多篇独立 Markdown + LaTeX 笔记，支持在左栏或右栏与任意 PDF 对照。"
        alert.addButton(withTitle: "创建并打开")
        alert.addButton(withTitle: "取消")

        let count = (currentPaper?.effectiveNoteDocuments.count ?? 1) + 1
        let titleField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        titleField.stringValue = "精读笔记 \(count)"
        alert.accessoryView = titleField

        if alert.runModal() == .alertFirstButtonReturn {
            if let created = LibraryStore.shared.createNoteDocument(for: paperId, title: titleField.stringValue) {
                setColumnSource(col, source: .note(id: created.id))
            }
        }
    }

    // MARK: - 9. Right Drawer Refresh (Outline / Notes WebView / Links & Related Papers)
    private func rebuildOutlineData() {
        outlineItems.removeAll()
        let docWithOutline = (leftCol.pdfView.document?.outlineRoot != nil)
            ? leftCol.pdfView.document
            : ((rightCol.pdfView.document?.outlineRoot != nil) ? rightCol.pdfView.document : (leftCol.pdfView.document ?? rightCol.pdfView.document))

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

    private func refreshLinksDrawerView() {
        guard isDrawerOpen, linksNeedRefresh else { return }
        linksNeedRefresh = false
        linksStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let paper = currentPaper else { return }

        // 1) 相关论文区块
        let relHeader = NSTextField(labelWithString: "相关联的论文 (\(paper.relatedPapers.count))")
        relHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
        relHeader.textColor = .secondaryLabelColor
        linksStackView.addArrangedSubview(relHeader)

        if paper.relatedPapers.isEmpty {
            let emptyRel = NSTextField(labelWithString: "暂无关联论文，可将基线或后续论文与此篇双向绑定。")
            emptyRel.font = .systemFont(ofSize: 11.5)
            emptyRel.textColor = .tertiaryLabelColor
            linksStackView.addArrangedSubview(emptyRel)
        } else {
            for rel in paper.relatedPapers {
                let targetTitle = LibraryStore.shared.paper(withId: rel.targetPaperId)?.title ?? rel.targetPaperId
                let card = makeDrawerResourceCard(
                    symbol: "doc.on.doc.fill",
                    title: targetTitle,
                    subtitle: rel.relationNote.isEmpty ? "点击在新标签页打开对照阅读" : rel.relationNote,
                    openId: rel.targetPaperId,
                    openAction: #selector(openRelatedPaperFromDrawer(_:)),
                    removeId: rel.targetPaperId,
                    removeAction: #selector(unlinkRelatedFromDrawer(_:))
                )
                linksStackView.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: linksStackView.widthAnchor, constant: -24).isActive = true
            }
        }

        let addRelBtn = NSButton(title: "＋ 关联库内其他论文…", target: self, action: #selector(addRelatedPaperInDrawer))
        addRelBtn.bezelStyle = .rounded
        addRelBtn.controlSize = .small
        linksStackView.addArrangedSubview(addRelBtn)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        linksStackView.addArrangedSubview(sep)
        sep.widthAnchor.constraint(equalTo: linksStackView.widthAnchor, constant: -24).isActive = true

        // 2) 相关文件与外部网页链接区块
        let resHeader = NSTextField(labelWithString: "相关网页与本地附件 (\(paper.resources.count))")
        resHeader.font = .systemFont(ofSize: 11.5, weight: .bold)
        resHeader.textColor = .secondaryLabelColor
        linksStackView.addArrangedSubview(resHeader)

        for res in paper.resources {
            let card = makeDrawerResourceCard(
                symbol: res.isLocalFile ? "folder.fill" : "globe",
                title: res.title,
                subtitle: res.urlOrPath,
                openId: res.urlOrPath,
                openAction: #selector(openResourceFromDrawer(_:)),
                removeId: res.id,
                removeAction: #selector(removeResourceFromDrawer(_:))
            )
            linksStackView.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: linksStackView.widthAnchor, constant: -24).isActive = true
        }

        let addWebBtn = NSButton(title: "＋ 网页链接", target: self, action: #selector(addWebResourceInDrawer))
        addWebBtn.bezelStyle = .rounded
        addWebBtn.controlSize = .small

        let addFileBtn = NSButton(title: "＋ 本地文件", target: self, action: #selector(addLocalFileInDrawer))
        addFileBtn.bezelStyle = .rounded
        addFileBtn.controlSize = .small

        let btnRow = NSStackView(views: [addWebBtn, addFileBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        linksStackView.addArrangedSubview(btnRow)
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
        let card = ModernSurfaceCardView()
        card.cornerRadius = 7
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)

        let titleBtn = NSButton(title: title, target: self, action: openAction)
        titleBtn.isBordered = false
        titleBtn.font = .systemFont(ofSize: 12, weight: .medium)
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

        let delBtn = NSButton(title: "✕", target: self, action: removeAction)
        delBtn.bezelStyle = .inline
        delBtn.isBordered = false
        delBtn.font = .systemFont(ofSize: 10.5)
        delBtn.contentTintColor = .tertiaryLabelColor
        delBtn.identifier = NSUserInterfaceItemIdentifier(removeId)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, vStack, spacer, delBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    @objc private func openRelatedPaperFromDrawer(_ sender: NSButton) {
        if let targetId = sender.identifier?.rawValue {
            onRequestOpenPaperTab?(targetId)
        }
    }

    @objc private func unlinkRelatedFromDrawer(_ sender: NSButton) {
        if let targetId = sender.identifier?.rawValue {
            LibraryStore.shared.unlinkRelatedPapers(paperAId: paperId, paperBId: targetId)
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
            }
        }
    }

    @objc private func openResourceFromDrawer(_ sender: NSButton) {
        if let pathOrURL = sender.identifier?.rawValue {
            openUniversalLink(pathOrURL)
        }
    }

    @objc private func removeResourceFromDrawer(_ sender: NSButton) {
        guard let resId = sender.identifier?.rawValue,
              var paper = currentPaper else { return }
        paper.resources.removeAll { $0.id == resId }
        LibraryStore.shared.savePaper(paper, notify: true)
    }

    @objc private func addWebResourceInDrawer() {
        let alert = NSAlert()
        alert.messageText = "添加论文相关网页链接"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 62))
        let nameF = NSTextField(frame: NSRect(x: 0, y: 34, width: 340, height: 24))
        nameF.placeholderString = "链接名称（如：GitHub 代码仓库 / 知乎解读）"
        let urlF = NSTextField(frame: NSRect(x: 0, y: 2, width: 340, height: 24))
        urlF.placeholderString = "https://..."
        box.addSubview(nameF)
        box.addSubview(urlF)
        alert.accessoryView = box

        if alert.runModal() == .alertFirstButtonReturn,
           var paper = currentPaper {
            let u = urlF.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !u.isEmpty else { return }
            let t = nameF.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            paper.resources.append(ExternalResource(title: t.isEmpty ? u : t, urlOrPath: u, isLocalFile: false))
            LibraryStore.shared.savePaper(paper, notify: true)
        }
    }

    @objc private func addLocalFileInDrawer() {
        let panel = NSOpenPanel()
        panel.title = "选择要挂载到本论文的本地文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            _ = LibraryStore.shared.addLocalAttachment(to: paperId, fileURL: url)
        }
    }

    // MARK: - WKScriptMessageHandler (Respond to clicks inside the LaTeX Notes WebView)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "noteAction",
              let dict = message.body as? [String: String],
              let action = dict["action"],
              var paper = currentPaper else { return }

        if action == "jumpLink", let url = dict["extra"], !url.isEmpty {
            handleNoteJumpURL(url, fromNoteCol: nil)
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

    func handleNoteJumpURL(_ urlString: String, fromNoteCol: CleanPDFColumnView? = nil) {
        guard !isClosed, let paper = currentPaper else { return }
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
            jumpToAnnotation(annot, preferredFromNoteCol: fromNoteCol)
            return
        }

        let targetPDFId = params["pdf"] ?? PDFSide.original.rawValue
        let targetPageIdx = params["page"].flatMap { Int($0) } ?? 0

        let targetCol: CleanPDFColumnView
        if let fromNoteCol = fromNoteCol {
            targetCol = (fromNoteCol === rightCol) ? leftCol : rightCol
        } else if leftCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = leftCol
        } else if rightCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = rightCol
        } else {
            targetCol = leftCol.contentSource.isPDF ? leftCol : rightCol
        }

        if targetCol.isHidden {
            targetCol.isHidden = false
            splitView.adjustSubviews()
        }
        pushJumpRecord(from: targetCol, label: "返回")
        if targetCol.contentSource != .pdf(id: targetPDFId) {
            setColumnSource(targetCol, source: .pdf(id: targetPDFId))
            view.layoutSubtreeIfNeeded()
        }
        if let doc = targetCol.pdfView.document,
           targetPageIdx >= 0, targetPageIdx < doc.pageCount,
           let page = doc.page(at: targetPageIdx) {
            targetCol.pdfView.go(to: page)
            let opposite = (targetCol === leftCol) ? rightCol : leftCol
            if opposite.contentSource.isPDF {
                syncScroll(from: targetCol, to: opposite)
            }
        }
        updatePageIndicatorAndSaveProgress()
    }

    func jumpToAnnotation(_ annot: PaperAnnotation, preferredFromNoteCol: CleanPDFColumnView? = nil) {
        guard !isClosed else { return }
        let targetPDFId = annot.effectivePDFId

        let targetCol: CleanPDFColumnView
        if let fromNoteCol = preferredFromNoteCol {
            targetCol = (fromNoteCol === rightCol) ? leftCol : rightCol
        } else if leftCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = leftCol
        } else if rightCol.contentSource == .pdf(id: targetPDFId) {
            targetCol = rightCol
        } else if rightCol.contentSource.isNote {
            targetCol = leftCol
        } else if leftCol.contentSource.isNote {
            targetCol = rightCol
        } else {
            targetCol = (annot.side == .original) ? leftCol : rightCol
        }

        if targetCol.isHidden {
            leftCol.isHidden = false
            rightCol.isHidden = false
            splitView.adjustSubviews()
            splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
        }
        pushJumpRecord(from: targetCol, label: "笔记跳转前")
        if targetCol.contentSource != .pdf(id: targetPDFId) {
            setColumnSource(targetCol, source: .pdf(id: targetPDFId))
            view.layoutSubtreeIfNeeded()
        }
        if let doc = targetCol.pdfView.document,
           annot.pageIndex >= 0, annot.pageIndex < doc.pageCount,
           let page = doc.page(at: annot.pageIndex) {
            if let firstRect = annot.rects.first?.cgRect {
                let dest = PDFDestination(page: page, at: NSPoint(x: firstRect.minX, y: firstRect.maxY + 40))
                targetCol.pdfView.go(to: dest)
            } else {
                targetCol.pdfView.go(to: page)
            }
            let opposite = (targetCol === leftCol) ? rightCol : leftCol
            if opposite.contentSource.isPDF {
                syncScroll(from: targetCol, to: opposite)
            }
        }
    }

    // MARK: - 10. In-PDF Search & Match Navigation
    func controlTextDidChange(_ obj: Notification) {
        performInPDFSearch()
    }

    private func performInPDFSearch() {
        searchTask?.cancel()
        searchController.cancel()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchMatches.removeAll()
        currentSearchMatchIndex = 0
        for column in [leftCol, rightCol] { column.pdfView.highlightedSelections = nil }
        searchNavSeg.isHidden = true
        searchMatchLabel.isHidden = query.isEmpty
        guard !query.isEmpty else { return }
        searchMatchLabel.stringValue = "搜索中…"
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isClosed else { return }
            let columns = [self.leftCol, self.rightCol].filter { !$0.isHidden }
            self.searchController.search(query, columns: columns) { [weak self] matches in
                guard let self = self, !self.isClosed,
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
        guard index >= 0, index < currentSearchMatches.count else { return }
        currentSearchMatchIndex = index
        let item = currentSearchMatches[index]
        searchMatchLabel.stringValue = "\(index + 1)/\(currentSearchMatches.count)"
        let otherCol = (item.col === leftCol) ? rightCol : leftCol
        otherCol.pdfView.clearSelection()
        item.col.pdfView.go(to: item.selection)
        item.col.pdfView.setCurrentSelection(item.selection, animate: true)
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
        goToPageIndex(pageIdx, recordHistory: true)
    }
}

// MARK: - NSSplitViewDelegate (Keep Master / Child Split In Perfect 50/50 Balance)
extension ReaderTabViewController: NSSplitViewDelegate {
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let sv = notification.object as? NSSplitView else { return }
        if sv === masterSplitView {
            if (modeSeg.selectedSegment == 2 || modeSeg.selectedSegment == 3) && !leftCol.isHidden && !rightCol.isHidden {
                splitView.setPosition(splitView.bounds.width / 2.0, ofDividerAt: 0)
            }
        }
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === masterSplitView {
            return max(440, masterSplitView.bounds.width - 620)
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView === masterSplitView {
            return masterSplitView.bounds.width - 280
        }
        return proposedMaximumPosition
    }
}
