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
    private(set) var activeTabId: String = "__LIBRARY__"
    private var cachedTabViews: [String: ZoteroTabItemView] = [:]

    private var orderedTabPaperIds: [String] {
        orderedTabIds.filter { $0 != "__LIBRARY__" }
    }

    var activeReaderVC: ReaderTabViewController? {
        return openReaderTabs[activeTabId]
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
        // 清理已被删除的论文标签页
        let removedIds = orderedTabPaperIds.filter { change?.resetsLibrary == true || LibraryStore.shared.paper(withId: $0) == nil }
        for rid in removedIds {
            closePaperTab(paperId: rid)
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

    func closePaperTab(paperId: String) {
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
            cachedTabViews.removeValue(forKey: pid)
            if let vc = openReaderTabs.removeValue(forKey: pid) {
                vc.prepareForClose()
                if vc.isViewLoaded { vc.view.removeFromSuperview() }
            }
        }
        orderedTabIds.removeAll { $0 != "__LIBRARY__" && $0 != paperId }
        switchToTab(id: paperId)
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
                guard let paper = LibraryStore.shared.paper(withId: tabId) else { continue }
                tabView = cachedTabViews[tabId] ?? ZoteroTabItemView(
                    tabId: tabId,
                    title: paper.title,
                    symbol: "doc.richtext.fill",
                    symbolTint: .systemRed,
                    isActive: isTabActive,
                    closable: true
                )
                tabView.onSelect = { [weak self] id in self?.switchToTab(id: id) }
                tabView.onClose = { [weak self] id in self?.closePaperTab(paperId: id) }
                tabView.onCloseOthers = { [weak self] id in self?.closeOtherPaperTabs(keeping: id) }
                tabView.onRevealInFinder = { pid in
                    NSWorkspace.shared.open(LibraryStore.shared.folderURL(for: pid))
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
    @objc func configureLLMTranslationShortcut() { LLMTranslationService.shared.presentSettingsModal(from: window) }
    @objc func readerSwapColumnsShortcut() { activeReaderVC?.swapColumnsAction() }
    @objc func readerResetAlignmentShortcut() { activeReaderVC?.resetSyncAlignmentAction() }
    @objc func readerZoomInShortcut() { activeReaderVC?.zoomInBothAction() }
    @objc func readerZoomOutShortcut() { activeReaderVC?.zoomOutBothAction() }
    @objc func readerZoomFitShortcut() { activeReaderVC?.zoomFitBothAction() }
    @objc func readerToggleDrawerShortcut() { activeReaderVC?.toggleRightDrawerAction() }

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
        guard hasPDF(sender) else { return [] }
        hoverOverlay.isHidden = false
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasPDF(sender) else {
            hoverOverlay.isHidden = true
            return []
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
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension MultiTabMainWindowController {
    fileprivate func setupWindowFileDrop() {
        contentHostView.onURLsDropped = { [weak self] urls in
            self?.openDocuments(urls, origin: .windowDrop)
        }
    }

    func showStatusBanner(_ text: String) {
        statusBanner?.show(text)
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
                    let remove = DocumentOpenAlerts.presentMissingRecent(name: url.lastPathComponent)
                    if remove { Self.removeRecentDocument(url) }
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
                if DocumentOpenAlerts.presentPassword(for: u, document: doc, window: window) != nil {
                    if let unlocked = Self.writeUnlockedTemporaryPDF(from: doc, named: u.lastPathComponent) {
                        ready.append(unlocked)
                    } else {
                        ready.append(u)
                    }
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
            beginiCloudOpen(cloudURL)
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
            // P0-2: replace import with TransientStore
            if let created = LibraryStore.shared.smartCreatePaperFromPDFs(batch) {
                openOrSwitchToPaperTab(paperId: created.id, jumpToAnnot: nil, switchImmediately: true)
                for u in batch {
                    NSDocumentController.shared.noteNewRecentDocumentURL(u)
                }
            } else {
                for u in batch {
                    failures.append((u.lastPathComponent, "无法导入到文献库"))
                }
            }
        }

        if !failures.isEmpty {
            if failures.count == 1, ready.isEmpty, batches.isEmpty, pendingiCloud.isEmpty {
                // already presented single-file alerts above when possible
            }
            DocumentOpenAlerts.presentCombinedFailures(failures)
        }

        if let app = NSApp.delegate as? AppDelegate {
            app.rebuildRecentMenu()
        }
        _ = origin
    }

    private func openTabId(containingFile url: URL) -> String? {
        for paperId in orderedTabPaperIds {
            guard let paper = LibraryStore.shared.paper(withId: paperId) else { continue }
            for descriptor in paper.allPDFDescriptors {
                guard let pdfURL = LibraryStore.shared.pdfURL(for: paper, pdfId: descriptor.id) else { continue }
                if FileIdentity.sameFile(pdfURL, url) { return paperId }
            }
        }
        return nil
    }

    private func beginiCloudOpen(_ url: URL) {
        showStatusBanner(DocumentOpenCopy.iCloudDownloading(url.lastPathComponent))
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            showStatusBanner(DocumentOpenCopy.iCloudFailed(url.lastPathComponent))
            return
        }
        let name = url.lastPathComponent
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] timer in
            attempts += 1
            let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus) ?? .notDownloaded
            if status == .current {
                timer.invalidate()
                self?.openDocuments([url], origin: .systemOpen)
            } else if attempts >= 45 {
                timer.invalidate()
                self?.showStatusBanner(DocumentOpenCopy.iCloudFailed(name))
            }
        }
    }


    private static func writeUnlockedTemporaryPDF(from document: PDFDocument, named name: String) -> URL? {
        guard let data = document.dataRepresentation() else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DualPDF-Unlocked", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

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
