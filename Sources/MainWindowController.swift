import Cocoa
import PDFKit
import UniformTypeIdentifiers

final class MultiTabMainWindowController: NSWindowController {
    let tabBarScrollView = HorizontalTabScrollView()
    let tabBarDocumentView = DraggableTabDocumentView()
    let tabBarStack = NonDraggableStackView()
    private let contentHostView = FileDropHostView()
    private var statusBanner: WindowStatusBannerController?

    let libraryVC = LibraryViewController()
    private var openReaderTabs: [String: ReaderTabViewController] = [:]
    private var orderedTabIds: [String] = ["__LIBRARY__"]
    /// Test seam for the session-markup discard alert. `true` = 关闭, `false` = 取消; `nil` = show NSAlert.
    var testingDiscardSessionMarkupResponse: Bool? = nil
    private(set) var activeTabId: String = "__LIBRARY__"
    private var cachedTabViews: [String: ZoteroTabItemView] = [:]

    private var orderedTabPaperIds: [String] {
        orderedTabIds.filter { $0 != "__LIBRARY__" }
    }

    var activeReaderVC: ReaderTabViewController? {
        return openReaderTabs[activeTabId]
    }

    func isPaperTabOpen(_ paperId: String) -> Bool {
        openReaderTabs[paperId] != nil
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "DualPDF — 双栏文献管理与对照阅读器"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.minSize = NSSize(width: 1020, height: 620)
        win.center()
        super.init(window: win)

        setupWindowUI()
        setupTabDragging()
        setupCallbacks()
        setupWindowFileDrop()
        statusBanner = WindowStatusBannerController(host: window?.contentView)
        // Library tab is selected by AppDelegate after launch unless opening documents.
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindowUI() {
        guard let root = window?.contentView else { return }

        let titleTabBar = DraggableTitleBarView()
        titleTabBar.material = .titlebar
        titleTabBar.blendingMode = .withinWindow
        titleTabBar.translatesAutoresizingMaskIntoConstraints = false
        titleTabBar.onURLsDropped = { [weak self] urls in
            self?.openDocuments(urls, origin: .windowDrop)
        }

        let nonDraggableClip = NonDraggableClipView()
        nonDraggableClip.drawsBackground = false
        nonDraggableClip.automaticallyAdjustsContentInsets = false
        nonDraggableClip.contentInsets = NSEdgeInsetsZero
        tabBarScrollView.contentView = nonDraggableClip

        tabBarScrollView.drawsBackground = false
        tabBarScrollView.borderType = .noBorder
        tabBarScrollView.hasHorizontalScroller = false
        tabBarScrollView.hasVerticalScroller = false
        // CRITICAL: Prevent NSScrollView in .fullSizeContentView window from adding a 28pt top contentInset that blocks hitTest!
        tabBarScrollView.automaticallyAdjustsContentInsets = false
        tabBarScrollView.contentInsets = NSEdgeInsetsZero
        tabBarScrollView.contentView.automaticallyAdjustsContentInsets = false
        tabBarScrollView.contentView.contentInsets = NSEdgeInsetsZero
        tabBarScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabBarDocumentView.translatesAutoresizingMaskIntoConstraints = false
        tabBarScrollView.documentView = tabBarDocumentView

        tabBarStack.orientation = .horizontal
        tabBarStack.spacing = 2
        tabBarStack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        tabBarStack.alignment = .centerY
        tabBarStack.translatesAutoresizingMaskIntoConstraints = false
        tabBarDocumentView.addSubview(tabBarStack)
        titleTabBar.addSubview(tabBarScrollView)

        let bottomSep = NSBox()
        bottomSep.boxType = .separator
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        titleTabBar.addSubview(bottomSep)

        contentHostView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleTabBar)
        root.addSubview(contentHostView)

        let matchScrollWidth = tabBarScrollView.widthAnchor.constraint(equalTo: tabBarDocumentView.widthAnchor)
        matchScrollWidth.priority = NSLayoutConstraint.Priority(490)

        NSLayoutConstraint.activate([
            titleTabBar.topAnchor.constraint(equalTo: root.topAnchor),
            titleTabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleTabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titleTabBar.heightAnchor.constraint(equalToConstant: 42),

            tabBarScrollView.leadingAnchor.constraint(equalTo: titleTabBar.leadingAnchor, constant: 80),
            tabBarScrollView.centerYAnchor.constraint(equalTo: titleTabBar.centerYAnchor),
            tabBarScrollView.heightAnchor.constraint(equalToConstant: 34),
            tabBarScrollView.trailingAnchor.constraint(lessThanOrEqualTo: titleTabBar.trailingAnchor, constant: -16),
            matchScrollWidth,

            tabBarDocumentView.topAnchor.constraint(equalTo: tabBarScrollView.contentView.topAnchor),
            tabBarDocumentView.bottomAnchor.constraint(equalTo: tabBarScrollView.contentView.bottomAnchor),
            tabBarDocumentView.leadingAnchor.constraint(equalTo: tabBarScrollView.contentView.leadingAnchor),
            tabBarDocumentView.heightAnchor.constraint(equalTo: tabBarScrollView.heightAnchor),

            tabBarStack.leadingAnchor.constraint(equalTo: tabBarDocumentView.leadingAnchor),
            tabBarStack.trailingAnchor.constraint(equalTo: tabBarDocumentView.trailingAnchor),
            tabBarStack.centerYAnchor.constraint(equalTo: tabBarDocumentView.centerYAnchor),

            bottomSep.bottomAnchor.constraint(equalTo: titleTabBar.bottomAnchor),
            bottomSep.leadingAnchor.constraint(equalTo: titleTabBar.leadingAnchor),
            bottomSep.trailingAnchor.constraint(equalTo: titleTabBar.trailingAnchor),

            contentHostView.topAnchor.constraint(equalTo: titleTabBar.bottomAnchor),
            contentHostView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentHostView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentHostView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        embedViewControllerView(libraryVC.view)
    }

    private func setupCallbacks() {
        libraryVC.onOpenPaperInTab = { [weak self] paperId, jumpAnnot in
            self?.openOrSwitchToPaperTab(paperId: paperId, jumpToAnnot: jumpAnnot, switchImmediately: true)
        }
        libraryVC.onOpenPaperNotesSidebar = { [weak self] paperId in
            guard let self = self else { return }
            self.openOrSwitchToPaperTab(paperId: paperId, jumpToAnnot: nil, switchImmediately: true)
            self.openReaderTabs[paperId]?.openNotesSidebar()
        }
        libraryVC.onOpenPaperAndJumpURL = { [weak self] paperId, jumpURL in
            guard let self = self else { return }
            self.openOrSwitchToPaperTab(paperId: paperId, jumpToAnnot: nil, switchImmediately: true)
            if let readerVC = self.openReaderTabs[paperId] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    readerVC.handleNoteJumpURL(jumpURL)
                }
            }
        }
        libraryVC.onEditAnnotationInTab = { [weak self] paperId, annot in
            guard let self = self else { return }
            self.openOrSwitchToPaperTab(paperId: paperId, jumpToAnnot: annot, switchImmediately: true)
            if let readerVC = self.openReaderTabs[paperId] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    readerVC.presentNoteEditorModal(for: annot)
                }
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreChanged(_:)),
            name: LibraryStore.libraryDidChangeNotification,
            object: nil
        )
    }

    private func setupTabDragging() {
        tabBarStack.onTabDrop = { [weak self] tabId, insertionIndex in
            self?.moveTab(id: tabId, toInsertionIndex: insertionIndex)
        }
    }

    @objc private func handleStoreChanged(_ notification: Notification) {
        let change = notification.userInfo?["change"] as? LibraryChange
        guard change?.resetsLibrary == true || change?.fields.contains(.membership) == true ||
              change?.fields.contains(.metadata) == true || change == nil else { return }
        // 清理已被删除的论文标签页（临时打开的加密文档不依赖文献库，勿误关）
        let removedIds = orderedTabPaperIds.filter { id in
            if openReaderTabs[id]?.isTransientOpen == true || LibraryStore.shared.isTransientPaper(id: id) {
                return false
            }
            return change?.resetsLibrary == true || LibraryStore.shared.paper(withId: id) == nil
        }
        for rid in removedIds {
            closePaperTab(paperId: rid, force: true)
        }
        rebuildTabBarUI()
    }

    func openOrSwitchToPaperTab(paperId: String, jumpToAnnot: PaperAnnotation?, switchImmediately: Bool = true) {
        guard LibraryStore.shared.paper(withId: paperId) != nil else { return }

        if openReaderTabs[paperId] == nil {
            let readerVC = ReaderTabViewController(paperId: paperId)
            readerVC.onRequestOpenPaperTab = { [weak self] targetId in
                self?.openOrSwitchToPaperTab(paperId: targetId, jumpToAnnot: nil, switchImmediately: true)
            }
            openReaderTabs[paperId] = readerVC
            orderedTabIds.append(paperId)
        }

        if switchImmediately {
            switchToTab(id: paperId)
            if let annot = jumpToAnnot, let readerVC = openReaderTabs[paperId] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    readerVC.jumpToAnnotation(annot)
                }
            }
        } else {
            rebuildTabBarUI()
        }
    }

    func switchToTab(id: String) {
        if id != activeTabId { activeReaderVC?.didResignActiveTab() }
        let prevId = activeTabId
        activeTabId = id
        libraryVC.view.isHidden = (id != "__LIBRARY__")
        if id == "__LIBRARY__" {
            libraryVC.refreshAllUI()
        }

        for (pid, vc) in openReaderTabs {
            let isTarget = (pid == id)
            guard vc.isViewLoaded || isTarget else { continue }
            if !vc.isViewLoaded { embedViewControllerView(vc.view) }
            vc.view.isHidden = !isTarget
            if isTarget {
                vc.didBecomeActiveTab()
            }
        }

        // 丝滑无重构切换：若标签视图已在树中，仅更新状态以防 DOM/View 闪烁并保留悬浮与平滑过渡
        if let prevTab = cachedTabViews[prevId], let nextTab = cachedTabViews[id] {
            prevTab.isActiveTab = false
            nextTab.isActiveTab = true
            scrollTabHorizontallyIntoView(nextTab)
        } else {
            rebuildTabBarUI()
        }
    }

    /// Open tabs whose session DualPDF_Markup edits would be lost if the app quit now.
    func unpersistedSessionMarkupTabCount() -> Int {
        openReaderTabs.values.filter { $0.hasUnpersistedColumnMarkup() }.count
    }

    func closePaperTab(paperId: String, force: Bool = false) {
        guard let vc = openReaderTabs[paperId] else { return }
        if !force && vc.hasUnpersistedColumnMarkup() {
            let discard: Bool
            if let forced = testingDiscardSessionMarkupResponse {
                discard = forced
            } else {
                let alert = NSAlert()
                alert.messageText = "此 PDF 上的批注仅本次有效，关闭后将丢失。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "关闭")
                alert.addButton(withTitle: "取消")
                discard = (alert.runModal() == .alertFirstButtonReturn)
            }
            guard discard else { return }
        }
        guard let vc = openReaderTabs.removeValue(forKey: paperId) else { return }
        vc.prepareForClose()
        if vc.isViewLoaded { vc.view.removeFromSuperview() }
        orderedTabIds.removeAll { $0 == paperId }
        cachedTabViews.removeValue(forKey: paperId)

        if activeTabId == paperId {
            let nextTab = orderedTabPaperIds.last ?? "__LIBRARY__"
            switchToTab(id: nextTab)
        } else {
            rebuildTabBarUI()
        }
    }

    func closeOtherPaperTabs(keeping paperId: String) {
        let toClose = orderedTabPaperIds.filter { $0 != paperId }
        for pid in toClose {
            closePaperTab(paperId: pid)
        }
        if openReaderTabs[paperId] != nil || paperId == "__LIBRARY__" {
            switchToTab(id: paperId)
        } else {
            rebuildTabBarUI()
        }
    }


    @objc func rebuildTabBarUI() {
        tabBarStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var activeTabView: ZoteroTabItemView?

        // 标签顺序是唯一的布局来源；文库标签和论文标签都可自由换位。
        for tabId in orderedTabIds {
            let isTabActive = (activeTabId == tabId)
            let tabView: ZoteroTabItemView

            if tabId == "__LIBRARY__" {
                tabView = cachedTabViews[tabId] ?? ZoteroTabItemView(
                    tabId: tabId,
                    title: "我的文库",
                    symbol: "building.columns",
                    symbolTint: NSColor(calibratedRed: 0.36, green: 0.45, blue: 0.82, alpha: 1.0),
                    isActive: isTabActive,
                    closable: false
                )
                tabView.onSelect = { [weak self] id in self?.switchToTab(id: id) }
            } else {
                let paper = openReaderTabs[tabId]?.currentPaper ?? LibraryStore.shared.paper(withId: tabId)
                guard let paper else { continue }
                let isTransient = paper.isTransient || LibraryStore.shared.isTransientPaper(id: paper.id)
                tabView = cachedTabViews[tabId] ?? ZoteroTabItemView(
                    tabId: tabId,
                    title: paper.title,
                    symbol: "doc.richtext.fill",
                    symbolTint: .systemRed,
                    isActive: isTabActive,
                    closable: true
                )
                tabView.titleText = paper.title
                tabView.badgeText = isTransient ? "未入库" : nil
                tabView.badgeUsesAccent = isTransient && paper.transientHasNotes
                tabView.onSelect = { [weak self] id in self?.switchToTab(id: id) }
                tabView.onClose = { [weak self] id in self?.closePaperTab(paperId: id) }
                tabView.onCloseOthers = { [weak self] id in self?.closeOtherPaperTabs(keeping: id) }
                tabView.onSaveToLibrary = isTransient ? { [weak self] pid in
                    self?.presentSaveToLibrary(for: pid)
                } : nil
                tabView.onRevealInFinder = { [weak self] pid in
                    if let source = self?.openReaderTabs[pid]?.transientSourceURL {
                        NSWorkspace.shared.activateFileViewerSelecting([source])
                    } else if LibraryStore.shared.isTransientPaper(id: pid),
                              let url = TransientStore.shared.sourceURL(for: pid) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.open(LibraryStore.shared.folderURL(for: pid))
                    }
                }
            }

            tabView.isActiveTab = isTabActive
            cachedTabViews[tabId] = tabView
            tabBarStack.addArrangedSubview(tabView)
            if isTabActive { activeTabView = tabView }
        }

        if let root = window?.contentView {
            root.layoutSubtreeIfNeeded()
        } else {
            tabBarScrollView.layoutSubtreeIfNeeded()
        }
        if let activeTabView {
            scrollTabHorizontallyIntoView(activeTabView)
        }
        window?.viewsNeedDisplay = true
    }

    private func moveTab(id: String, toInsertionIndex insertionIndex: Int) {
        let reordered = TabOrder.moving(id, toInsertionIndex: insertionIndex, in: orderedTabIds)
        guard reordered != orderedTabIds else { return }
        orderedTabIds = reordered
        // 等拖拽会话结束后直接换位，不播放交换动画。
        DispatchQueue.main.async { [weak self] in
            self?.rebuildTabBarUI()
        }
    }

    private func scrollTabHorizontallyIntoView(_ tabView: NSView) {
        let clipBounds = tabBarScrollView.contentView.bounds
        guard clipBounds.width > 0 else { return }
        let rectInDoc = tabView.convert(tabView.bounds, to: tabBarDocumentView).insetBy(dx: -8, dy: 0)
        var targetX = clipBounds.origin.x
        if rectInDoc.maxX > clipBounds.maxX {
            targetX = rectInDoc.maxX - clipBounds.width
        }
        if rectInDoc.minX < targetX {
            targetX = rectInDoc.minX
        }
        let maxOffset = max(0, tabBarDocumentView.bounds.width - clipBounds.width)
        targetX = max(0, min(maxOffset, targetX))
        tabBarScrollView.contentView.scroll(to: NSPoint(x: targetX, y: 0))
        tabBarScrollView.reflectScrolledClipView(tabBarScrollView.contentView)
    }

    // MARK: - Menu Bar Actions
    @objc func newPaperShortcutAction() {
        switchToTab(id: "__LIBRARY__")
        libraryVC.presentCreatePaperModal()
    }

    @objc func quickOpenPDFShortcutAction() {
        let panel = NSOpenPanel()
        panel.title = "快速选择 1 个或 2 个 PDF 文件创建双栏对照阅读"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            openDocuments(panel.urls, origin: .openPanel)
        }
    }

    @objc func switchLibraryRootAction() {
        let panel = NSOpenPanel()
        panel.title = "选择本地文献库根目录 (PaperLibrary)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            LibraryStore.shared.switchLibraryRoot(to: url)
            switchToTab(id: "__LIBRARY__")
        }
    }

    @objc func restoreSamplePapersAction() {
        LibraryStore.shared.restoreSamplePapers()
        switchToTab(id: "__LIBRARY__")
    }

    @objc func revealVaultInFinderShortcut() {
        NSWorkspace.shared.open(LibraryStore.shared.rootDirectory)
    }

    @objc func closeActiveTabShortcut() {
        if activeTabId != "__LIBRARY__" {
            closePaperTab(paperId: activeTabId)
        }
    }

    @objc func focusSearchShortcut() {
        if let reader = activeReaderVC {
            reader.focusSearchField()
        } else {
            libraryVC.focusSearchField()
        }
    }

    @objc func switchToLibraryTabShortcut() {
        switchToTab(id: "__LIBRARY__")
    }

    @objc func selectPreviousTabShortcut() {
        guard orderedTabIds.count > 1, let curIdx = orderedTabIds.firstIndex(of: activeTabId) else { return }
        let prevIdx = (curIdx - 1 + orderedTabIds.count) % orderedTabIds.count
        switchToTab(id: orderedTabIds[prevIdx])
    }

    @objc func selectNextTabShortcut() {
        guard orderedTabIds.count > 1, let curIdx = orderedTabIds.firstIndex(of: activeTabId) else { return }
        let nextIdx = (curIdx + 1) % orderedTabIds.count
        switchToTab(id: orderedTabIds[nextIdx])
    }

    @objc func readerModeDualShortcut() { activeReaderVC?.setDisplayMode(2) }
    @objc func readerModeOrigShortcut() { activeReaderVC?.setDisplayMode(0) }
    @objc func readerModeTransShortcut() { activeReaderVC?.setDisplayMode(1) }
    @objc func readerModeSplitShortcut() { activeReaderVC?.setDisplayMode(2) }
    @objc func configureLLMTranslationShortcut() { LLMTranslationService.shared.presentSettingsModal(from: window) }
    @objc func readerSwapColumnsShortcut() { activeReaderVC?.swapColumnsAction() }
    @objc func readerResetAlignmentShortcut() { activeReaderVC?.resetSyncAlignmentAction() }
    @objc func readerZoomInShortcut() { activeReaderVC?.zoomInActiveColumnAction() }
    @objc func readerZoomOutShortcut() { activeReaderVC?.zoomOutActiveColumnAction() }
    @objc func readerZoomFitShortcut() { activeReaderVC?.zoomFitActiveColumnAction() }
    @objc func readerToggleDrawerShortcut() { activeReaderVC?.toggleRightDrawerAction() }
    @objc func readerToggleTopBarShortcut() { activeReaderVC?.toggleReaderTopBarAction() }

    private func embedViewControllerView(_ subview: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            subview.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor)
        ])
    }
}

// MARK: - App Delegate


// MARK: - Window file drop host

final class FileDropHostView: NSView {
    var onURLsDropped: (([URL]) -> Void)?
    /// Return (message, handleAsSideBySideCompare) for the current drag location in view coords.
    var onDragHover: ((NSPoint) -> (message: String, sideBySideCompare: Bool))?
    private var pendingSideBySideCompare = false
    private let hoverOverlay = DropHoverOverlayView(message: DocumentOpenCopy.dropToOpenHint)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        hoverOverlay.isHidden = true
        hoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverOverlay)
        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return updateHover(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return updateHover(sender)
    }

    private func updateHover(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasPDF(sender) else {
            hoverOverlay.isHidden = true
            pendingSideBySideCompare = false
            return []
        }
        let point = convert(sender.draggingLocation, from: nil)
        if let hover = onDragHover?(point) {
            hoverOverlay.setMessage(hover.message)
            pendingSideBySideCompare = hover.sideBySideCompare
        } else {
            hoverOverlay.setMessage(DocumentOpenCopy.dropToOpenHint)
            pendingSideBySideCompare = false
        }
        hoverOverlay.isHidden = false
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoverOverlay.isHidden = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hasPDF(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hoverOverlay.isHidden = true
        let urls = readURLs(sender)
        guard !urls.isEmpty else { return false }
        let asCompare = pendingSideBySideCompare
        pendingSideBySideCompare = false
        if asCompare, let wc = window?.windowController as? MultiTabMainWindowController,
           wc.handleSideBySideCompareDropFromWindow(urls) {
            return true
        }
        onURLsDropped?(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        hoverOverlay.isHidden = true
    }

    private func hasPDF(_ sender: NSDraggingInfo) -> Bool { !readURLs(sender).isEmpty }

    private func readURLs(_ sender: NSDraggingInfo) -> [URL] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return [] }
        return urls
    }
}

final class DropHoverOverlayView: NSView {
    private let label = NSTextField(labelWithString: "")
    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        label.stringValue = message
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    func setMessage(_ message: String) { label.stringValue = message }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}


/// Shared in-flight iCloud downloads (cannot store in a class extension).
private enum iCloudDownloadRegistry {
    struct Job {
        let url: URL
        let origin: OpenOrigin
        let startedAt: Date
    }
    static var jobs: [String: Job] = [:]
    static let timeout: TimeInterval = 120
}

/// One-shot latch so either the coordinator callback or the timeout wins.
private final class iCloudCoordinateState: @unchecked Sendable {
    private var finished = false
    private let lock = NSLock()
    /// Returns true the first time it is called; false afterwards.
    func completeIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished { return false }
        finished = true
        return true
    }
}

extension MultiTabMainWindowController {
    fileprivate func setupWindowFileDrop() {
        contentHostView.onURLsDropped = { [weak self] urls in
            self?.openDocuments(urls, origin: .windowDrop)
        }
        contentHostView.onDragHover = { [weak self] pointInHost in
            guard let self, let reader = self.activeReaderVC else {
                return (DocumentOpenCopy.dropToOpenHint, false)
            }
            // Convert host point into reader view coordinates.
            let pointInReader = reader.view.convert(pointInHost, from: self.contentHostView)
            if reader.wantsSideBySideCompareDrop(atLocationInView: pointInReader) {
                return (DocumentOpenCopy.dropSideBySideCompareHint, true)
            }
            return (DocumentOpenCopy.dropToOpenHint, false)
        }
    }

    @discardableResult
    func handleSideBySideCompareDropFromWindow(_ urls: [URL]) -> Bool {
        activeReaderVC?.handleSideBySideCompareDrop(urls: urls) ?? false
    }

    func showStatusBanner(_ text: String, duration: TimeInterval? = 4, retry: (() -> Void)? = nil) {
        statusBanner?.show(text, duration: duration, retry: retry)
    }

    func flashTab(id: String) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        guard let tab = cachedTabViews[id] else { return }
        tab.flashFocusHighlight()
    }

    /// Unified document open entry (Finder / Dock / ⌘O / Recent / window drop).
    func openDocuments(_ urls: [URL], origin: OpenOrigin) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        var nonPDFCount = 0
        var ready: [URL] = []
        var failures: [(name: String, reason: String)] = []
        var pendingiCloud: [URL] = []
        var unlockedTransient: [(URL, PDFDocument)] = []

        for url in urls {
            switch DocumentValidation.classify(url) {
            case .ok(let u):
                ready.append(u)
            case .nonPDF:
                nonPDFCount += 1
                if urls.count == 1 {
                    DocumentOpenAlerts.presentSimple(
                        title: DocumentOpenCopy.cannotOpenTitle(url.lastPathComponent),
                        body: DocumentOpenCopy.onlyPDF,
                        revealURL: nil,
                        window: window
                    )
                    return
                }
            case .missing:
                if origin == .openRecent {
                    let key = FileIdentity.docKey(for: url)
                    if let transient = TransientStore.shared.paper(withId: key), transient.transientHasNotes {
                        let export = DocumentOpenAlerts.presentMissingTransientWithNotes(name: url.lastPathComponent)
                        if export {
                            libraryVC.exportTransientNotesPublic(transient)
                        }
                    } else {
                        let remove = DocumentOpenAlerts.presentMissingRecent(name: url.lastPathComponent)
                        if remove { Self.removeRecentDocument(url) }
                    }
                } else {
                    failures.append((url.lastPathComponent, "文件可能已被移动或删除。"))
                }
            case .unreadable:
                if urls.count == 1 {
                    DocumentOpenAlerts.presentSimple(
                        title: DocumentOpenCopy.noPermissionTitle(url.lastPathComponent),
                        body: DocumentOpenCopy.noPermissionBody,
                        revealURL: url,
                        window: window
                    )
                    return
                }
                failures.append((url.lastPathComponent, "没有权限读取"))
            case .corrupt:
                if urls.count == 1 {
                    DocumentOpenAlerts.presentSimple(
                        title: DocumentOpenCopy.cannotOpenTitle(url.lastPathComponent),
                        body: DocumentOpenCopy.corruptBody,
                        revealURL: url,
                        window: window
                    )
                    return
                }
                failures.append((url.lastPathComponent, "文件可能已损坏或不是有效的 PDF。"))
            case .locked(let u, let doc):
                // Unlock in memory only — never write plaintext to disk / library.
                if DocumentOpenAlerts.presentPassword(for: u, document: doc, window: window) != nil {
                    unlockedTransient.append((u, doc))
                } else {
                    failures.append((u.lastPathComponent, "未解锁受密码保护的文档"))
                }
            case .iCloudPending(let u):
                pendingiCloud.append(u)
            case .failure(_, let reason):
                failures.append((url.lastPathComponent, reason))
            }
        }

        if nonPDFCount > 0 && !ready.isEmpty {
            showStatusBanner(DocumentOpenCopy.ignoredNonPDF(nonPDFCount))
        }

        for cloudURL in pendingiCloud {
            beginiCloudOpen(cloudURL, origin: origin)
        }

        for (sourceURL, document) in unlockedTransient {
            openTransientUnlocked(sourceURL: sourceURL, document: document)
            NSDocumentController.shared.noteNewRecentDocumentURL(sourceURL)
        }

        // Dedup against open tabs / library papers first.
        var toCreate: [URL] = []
        for url in ready {
            if let openId = openTabId(containingFile: url) {
                switchToTab(id: openId)
                flashTab(id: openId)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                continue
            }
            if let paper = LibraryStore.shared.paperContainingFile(identicalTo: url) {
                openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil, switchImmediately: true)
                flashTab(id: paper.id)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                continue
            }
            toCreate.append(url)
        }

        let (batches, ignored) = DocumentOpenPlanner.tabBatches(from: toCreate, maxFiles: 10)
        if ignored > 0 {
            showStatusBanner(DocumentOpenCopy.tabLimit)
        }

        for batch in batches {
            if let created = TransientStore.shared.openPDFs(batch) {
                openOrSwitchToPaperTab(paperId: created.id, jumpToAnnot: nil, switchImmediately: true)
                for u in batch {
                    NSDocumentController.shared.noteNewRecentDocumentURL(u)
                }
            } else {
                for u in batch {
                    failures.append((u.lastPathComponent, "无法打开文档"))
                }
            }
        }

        if !failures.isEmpty {
            DocumentOpenAlerts.presentCombinedFailures(failures)
        }

        if let app = NSApp.delegate as? AppDelegate {
            app.rebuildRecentMenu()
        }
    }

    /// Open an already-unlocked PDFDocument without writing plaintext anywhere on disk.
    func openTransientUnlocked(sourceURL: URL, document: PDFDocument) {
        if let openId = openTabId(containingFile: sourceURL) {
            switchToTab(id: openId)
            flashTab(id: openId)
            return
        }
        if let paper = LibraryStore.shared.paperContainingFile(identicalTo: sourceURL) {
            openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil, switchImmediately: true)
            flashTab(id: paper.id)
            return
        }

        guard let created = TransientStore.shared.openPDFs([sourceURL], unlockedDocument: document) else {
            DocumentOpenAlerts.presentSimple(
                title: DocumentOpenCopy.cannotOpenTitle(sourceURL.lastPathComponent),
                body: "无法建立临时阅读会话。",
                revealURL: sourceURL,
                window: window
            )
            return
        }
        openOrSwitchToPaperTab(paperId: created.id, jumpToAnnot: nil, switchImmediately: true)
        showStatusBanner(DocumentOpenCopy.encryptedNotImported)
    }


    // MARK: - P0-2 Save to library

    @objc func saveToLibraryShortcutAction() {
        let id = activeTabId
        guard id != "__LIBRARY__" else { return }
        guard let paper = LibraryStore.shared.paper(withId: id), paper.isTransient || LibraryStore.shared.isTransientPaper(id: id) else {
            return
        }
        presentSaveToLibrary(for: id)
    }

    @objc func revealInLibraryShortcutAction() {
        let id = activeTabId
        guard id != "__LIBRARY__" else { return }
        guard let paper = LibraryStore.shared.paper(withId: id), !(paper.isTransient || LibraryStore.shared.isTransientPaper(id: id)) else { return }
        switchToTab(id: "__LIBRARY__")
        libraryVC.selectPaperInUI(id)
    }

    func presentSaveToLibrary(for paperId: String) {
        guard let paper = LibraryStore.shared.paper(withId: paperId),
              paper.isTransient || LibraryStore.shared.isTransientPaper(id: paperId) else { return }
        guard let win = window else { return }

        let cats = LibraryStore.shared.allCategories()
        let lastCat = UserDefaults.standard.string(forKey: "DualPDF_LastPromoteCategory")
        let preferred = (lastCat.flatMap { cats.contains($0) ? $0 : nil }) ?? cats.first ?? "未分类"
        let fields = TransientStore.PromoteFields(
            title: paper.title,
            authors: paper.authors,
            year: paper.year,
            venue: paper.venue,
            category: preferred
        )
        let sheet = SaveToLibrarySheetController(fields: fields, categories: cats.isEmpty ? [preferred] : cats)
        let sheetWin = NSWindow(contentViewController: sheet)
        sheetWin.title = "存入文献库"
        sheetWin.styleMask = [.titled]
        sheet.onCancel = { [weak win, weak sheetWin] in
            if let sheetWin { win?.endSheet(sheetWin, returnCode: .cancel) }
        }
        sheet.onSubmit = { [weak self, weak win, weak sheetWin] submitted in
            guard let self, let sheetWin else { return }
            win?.endSheet(sheetWin, returnCode: .OK)
            self.performPromote(paperId: paperId, fields: submitted)
        }
        win.beginSheet(sheetWin)
    }

    private func performPromote(paperId: String, fields: TransientStore.PromoteFields) {
        UserDefaults.standard.set(fields.category, forKey: "DualPDF_LastPromoteCategory")
        // Capture scroll before migration.
        openReaderTabs[paperId]?.prepareForPromoteSnapshot()
        switch TransientStore.shared.promoteToLibrary(id: paperId, fields: fields) {
        case .success(let created):
            adoptPromotedTab(from: paperId, to: created)
            libraryVC.refreshAllUI()
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "无法存入文献库"
            alert.informativeText = "\(error.localizedDescription)。你的笔记仍保存在本机，未丢失。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            if let win = window { alert.beginSheetModal(for: win) }
            else { alert.runModal() }
        }
    }

    private func adoptPromotedTab(from oldId: String, to created: PaperItem) {
        guard let vc = openReaderTabs.removeValue(forKey: oldId) else {
            openOrSwitchToPaperTab(paperId: created.id, jumpToAnnot: nil, switchImmediately: true)
            return
        }
        vc.adoptLibraryPaper(id: created.id)
        openReaderTabs[created.id] = vc
        if let idx = orderedTabIds.firstIndex(of: oldId) {
            orderedTabIds[idx] = created.id
        }
        if activeTabId == oldId { activeTabId = created.id }
        cachedTabViews.removeValue(forKey: oldId)
        rebuildTabBarUI()
        switchToTab(id: created.id)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let sel = menuItem.action
        let id = activeTabId
        let isReader = id != "__LIBRARY__"
        let transient = isReader && (
            LibraryStore.shared.isTransientPaper(id: id) ||
            (LibraryStore.shared.paper(withId: id)?.isTransient == true)
        )
        if sel == #selector(saveToLibraryShortcutAction) {
            return isReader && transient
        }
        if sel == #selector(revealInLibraryShortcutAction) {
            return isReader && !transient && LibraryStore.shared.paper(withId: id) != nil
        }
        return true
    }

    private func openTabId(containingFile url: URL) -> String? {
        for paperId in orderedTabPaperIds {
            if let source = openReaderTabs[paperId]?.transientSourceURL,
               FileIdentity.sameFile(source, url) {
                return paperId
            }
            guard let paper = LibraryStore.shared.paper(withId: paperId) else { continue }
            for descriptor in paper.allPDFDescriptors {
                guard let pdfURL = LibraryStore.shared.pdfURL(for: paper, pdfId: descriptor.id) else { continue }
                if FileIdentity.sameFile(pdfURL, url) { return paperId }
            }
        }
        return nil
    }

    // MARK: - iCloud coordinated download

    private func iCloudJobKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func beginiCloudOpen(_ url: URL, origin: OpenOrigin) {
        let key = iCloudJobKey(url)
        if iCloudDownloadRegistry.jobs[key] != nil {
            refreshiCloudBanner()
            return
        }
        iCloudDownloadRegistry.jobs[key] = .init(url: url, origin: origin, startedAt: Date())
        refreshiCloudBanner()

        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            // Still attempt coordinated read — some items need coordinator only.
            NSLog("[DualPDF][B3] startDownloadingUbiquitousItem failed: %@", error.localizedDescription)
        }

        let capturedURL = url
        let capturedOrigin = origin
        // coordinate(reading:) is synchronous and will wait for the ubiquitous download.
        // Race it against a ≥2 minute timeout on a parallel queue.
        let state = iCloudCoordinateState()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var coordError: NSError?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var preparedURL: URL?
            coordinator.coordinate(readingItemAt: capturedURL, options: [], error: &coordError) { newURL in
                if FileManager.default.isReadableFile(atPath: newURL.path) {
                    preparedURL = newURL
                }
            }
            let success = preparedURL != nil && coordError == nil
            DispatchQueue.main.async {
                guard let self else { return }
                guard state.completeIfNeeded() else { return } // timed out already
                iCloudDownloadRegistry.jobs.removeValue(forKey: key)
                if success, let preparedURL {
                    self.refreshiCloudBanner()
                    self.openDocuments([preparedURL], origin: capturedOrigin)
                } else {
                    NSLog("[DualPDF][B3] iCloud open failed for %@ err=%@", capturedURL.lastPathComponent, String(describing: coordError))
                    self.refreshiCloudBanner()
                    self.showStatusBanner(
                        DocumentOpenCopy.iCloudFailed(capturedURL.lastPathComponent),
                        duration: nil,
                        retry: { [weak self] in
                            self?.beginiCloudOpen(capturedURL, origin: capturedOrigin)
                        }
                    )
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + iCloudDownloadRegistry.timeout) { [weak self] in
            guard let self else { return }
            guard state.completeIfNeeded() else { return } // coordinator finished first
            iCloudDownloadRegistry.jobs.removeValue(forKey: key)
            NSLog("[DualPDF][B3] iCloud open timed out for %@", capturedURL.lastPathComponent)
            self.refreshiCloudBanner()
            self.showStatusBanner(
                DocumentOpenCopy.iCloudFailed(capturedURL.lastPathComponent),
                duration: nil,
                retry: { [weak self] in
                    self?.beginiCloudOpen(capturedURL, origin: capturedOrigin)
                }
            )
        }
    }

    private func refreshiCloudBanner() {
        let jobs = Array(iCloudDownloadRegistry.jobs.values)
        guard !jobs.isEmpty else {
            // Leave failure/retry banners alone; only clear when transitioning from downloading.
            return
        }
        if jobs.count == 1 {
            showStatusBanner(DocumentOpenCopy.iCloudDownloading(jobs[0].url.lastPathComponent), duration: nil)
        } else {
            showStatusBanner(DocumentOpenCopy.iCloudDownloadingMany(jobs.count), duration: nil)
        }
    }

    /// Remove a recent-document entry.
    /// Note: NSDocumentController has no public API to delete a single URL, so we clear
    /// the whole list and re-add the rest. That clears-then-re-adds sequence can reshuffle
    /// the Recent menu order relative to the system’s original ordering.
    static func removeRecentDocument(_ url: URL) {
        let remaining = NSDocumentController.shared.recentDocumentURLs.filter {
            !FileIdentity.sameFile($0, url) && $0.standardizedFileURL != url.standardizedFileURL
        }
        NSDocumentController.shared.clearRecentDocuments(nil)
        for item in remaining.reversed() {
            NSDocumentController.shared.noteNewRecentDocumentURL(item)
        }
        if let app = NSApp.delegate as? AppDelegate {
            app.rebuildRecentMenu()
        }
    }

}
