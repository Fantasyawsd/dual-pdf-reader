import Cocoa
import UniformTypeIdentifiers

final class MultiTabMainWindowController: NSWindowController {
    let tabBarScrollView = HorizontalTabScrollView()
    let tabBarDocumentView = DraggableTabDocumentView()
    let tabBarStack = NonDraggableStackView()
    private let contentHostView = NSView()

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
        switchToTab(id: "__LIBRARY__")
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
        if panel.runModal() == .OK,
           let created = LibraryStore.shared.smartCreatePaperFromPDFs(panel.urls) {
            openOrSwitchToPaperTab(paperId: created.id, jumpToAnnot: nil, switchImmediately: true)
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
    @objc func readerZoomInShortcut() { activeReaderVC?.zoomInActiveColumnAction() }
    @objc func readerZoomOutShortcut() { activeReaderVC?.zoomOutActiveColumnAction() }
    @objc func readerZoomFitShortcut() { activeReaderVC?.zoomFitActiveColumnAction() }
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
