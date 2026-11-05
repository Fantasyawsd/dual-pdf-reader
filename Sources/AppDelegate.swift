import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MultiTabMainWindowController?
    /// True once we know launch/open should show documents instead of the library.
    private var didReceiveOpenURLs = false
    /// URLs that arrived via application(_:open:) before the window controller existed.
    private var pendingOpenURLs: [URL] = []
    private var recentMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        b1Log("[DualPDF][B1] applicationDidFinishLaunching")
        setupMainMenu()
        let wc = MultiTabMainWindowController()
        mainWindowController = wc
        wc.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)

        if !pendingOpenURLs.isEmpty {
            didReceiveOpenURLs = true
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            b1Log("[DualPDF][B1] flushing \(urls.count) pending open URL(s) after window ready")
            wc.openDocuments(urls, origin: .systemOpen)
        }

        // Cold start: application(_:open:) may arrive before or after didFinishLaunching.
        // Only fall back to the library when nothing is pending and no open arrived.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.didReceiveOpenURLs && self.pendingOpenURLs.isEmpty {
                self.mainWindowController?.switchToTab(id: "__LIBRARY__")
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        b1Log("[DualPDF][B1] application(_:open:) count=\(urls.count) wcReady=\(mainWindowController == nil ? 0 : 1)")
        didReceiveOpenURLs = true
        if let wc = mainWindowController {
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            wc.openDocuments(urls, origin: .systemOpen)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
            b1Log("[DualPDF][B1] queued \(urls.count) URL(s); pending total=\(pendingOpenURLs.count)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// Test seam for the quit-time session-markup alert. `true` = 退出, `false` = 取消; `nil` = show NSAlert.
    var testingQuitDiscardSessionMarkupResponse: Bool? = nil
    /// Test seam: extra main-window controllers to inspect (tests don't go through applicationDidFinishLaunching).
    var testingMainWindowControllers: [MultiTabMainWindowController] = []
    /// Test seam: replaces LibraryStore.flushReadingState() so tests can observe when it runs.
    var testingFlushReadingState: (() -> Bool)? = nil

    /// Number of open reader tabs (all main windows + standalone reader windows) whose
    /// DualPDF_Markup edits are still unpersisted and would be lost on quit.
    func unpersistedSessionMarkupTabCount() -> Int {
        var seen = Set<ObjectIdentifier>()
        var controllers: [MultiTabMainWindowController] = []
        let candidates = [mainWindowController].compactMap { $0 }
            + NSApp.windows.compactMap { $0.windowController as? MultiTabMainWindowController }
            + testingMainWindowControllers
        for wc in candidates where seen.insert(ObjectIdentifier(wc)).inserted {
            controllers.append(wc)
        }
        return controllers.reduce(0) { $0 + $1.unpersistedSessionMarkupTabCount() }
            + StandaloneReaderWindowManager.shared.unpersistedSessionMarkupWindowCount()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = unpersistedSessionMarkupTabCount()
        if count > 0 {
            let quit: Bool
            if let forced = testingQuitDiscardSessionMarkupResponse {
                quit = forced
            } else {
                let alert = NSAlert()
                alert.messageText = "\(count) 个 PDF 上的批注仅本次有效，退出后将丢失。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "退出")
                alert.addButton(withTitle: "取消")
                quit = (alert.runModal() == .alertFirstButtonReturn)
            }
            guard quit else { return .terminateCancel }
        }
        let flushed = testingFlushReadingState?() ?? LibraryStore.shared.flushReadingState()
        return flushed ? .terminateNow : .terminateCancel
    }

    @objc func openRecentDocumentAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        mainWindowController?.openDocuments([url], origin: .openRecent)
    }

    @objc func clearRecentDocumentsAction(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
        rebuildRecentMenu()
    }

    @objc func rebuildRecentMenu() {
        guard let recentMenu else { return }
        recentMenu.removeAllItems()
        let urls = Array(NSDocumentController.shared.recentDocumentURLs.prefix(10))
        if urls.isEmpty {
            let empty = NSMenuItem(title: "无记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        } else {
            for url in urls {
                let item = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(openRecentDocumentAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = url
                item.toolTip = url.path
                recentMenu.addItem(item)
            }
        }
        recentMenu.addItem(NSMenuItem.separator())
        let clear = NSMenuItem(
            title: "清除菜单",
            action: #selector(clearRecentDocumentsAction(_:)),
            keyEquivalent: ""
        )
        clear.target = self
        clear.isEnabled = !urls.isEmpty
        recentMenu.addItem(clear)
    }


    private func b1Log(_ message: String) {
        NSLog("%@", message)
    }


    func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 DualPDF 双栏文献阅读器", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "切换本地文献库文件夹…", action: #selector(MultiTabMainWindowController.switchLibraryRootAction), keyEquivalent: "")
        appMenu.addItem(withTitle: "配置 AI 划词翻译接口 (LLM)…", action: #selector(MultiTabMainWindowController.configureLLMTranslationShortcut), keyEquivalent: ",")
        appMenu.addItem(withTitle: "恢复内置示例论文 (DeepSeek-V3 & MoE)", action: #selector(MultiTabMainWindowController.restoreSamplePapersAction), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 DualPDF", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 DualPDF", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "新建 / 导入论文条目…", action: #selector(MultiTabMainWindowController.newPaperShortcutAction), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "快速选择 PDF 双栏打开…", action: #selector(MultiTabMainWindowController.quickOpenPDFShortcutAction), keyEquivalent: "o")

        let recentRoot = NSMenuItem(title: "打开最近使用", action: nil, keyEquivalent: "")
        let recentSub = NSMenu(title: "打开最近使用")
        recentRoot.submenu = recentSub
        recentMenu = recentSub
        fileMenu.addItem(recentRoot)
        rebuildRecentMenu()
        fileMenu.delegate = RecentMenuRefreshDelegate.shared
        RecentMenuRefreshDelegate.shared.appDelegate = self

        fileMenu.addItem(NSMenuItem.separator())
        let saveLib = NSMenuItem(title: "存入文献库…", action: #selector(MultiTabMainWindowController.saveToLibraryShortcutAction), keyEquivalent: "s")
        fileMenu.addItem(saveLib)
        let showInLib = NSMenuItem(title: "在文献库中显示", action: #selector(MultiTabMainWindowController.revealInLibraryShortcutAction), keyEquivalent: "l")
        showInLib.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(showInLib)
        fileMenu.addItem(NSMenuItem.separator())
        let revealItem = NSMenuItem(title: "在 Finder 中显示文献库", action: #selector(MultiTabMainWindowController.revealVaultInFinderShortcut), keyEquivalent: "R")
        revealItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(revealItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "关闭当前阅读标签页", action: #selector(MultiTabMainWindowController.closeActiveTabShortcut), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "查找…", action: #selector(MultiTabMainWindowController.focusSearchShortcut), keyEquivalent: "f")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "视图与阅读")
        viewMenuItem.submenu = viewMenu

        let mDual = NSMenuItem(title: "双栏对照模式", action: #selector(MultiTabMainWindowController.readerModeDualShortcut), keyEquivalent: "1")
        mDual.keyEquivalentModifierMask = [.control]
        viewMenu.addItem(mDual)

        let mOrig = NSMenuItem(title: "仅看原版 PDF", action: #selector(MultiTabMainWindowController.readerModeOrigShortcut), keyEquivalent: "2")
        mOrig.keyEquivalentModifierMask = [.control]
        viewMenu.addItem(mOrig)

        let mTrans = NSMenuItem(title: "仅看中文译版 PDF", action: #selector(MultiTabMainWindowController.readerModeTransShortcut), keyEquivalent: "3")
        mTrans.keyEquivalentModifierMask = [.control]
        viewMenu.addItem(mTrans)

        let mSplit = NSMenuItem(title: "分屏", action: #selector(MultiTabMainWindowController.readerModeSplitShortcut), keyEquivalent: "3")
        mSplit.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(mSplit)

        viewMenu.addItem(NSMenuItem.separator())
        let swapItem = NSMenuItem(title: "左右两栏互换", action: #selector(MultiTabMainWindowController.readerSwapColumnsShortcut), keyEquivalent: "X")
        swapItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(swapItem)

        let resetAlignItem = NSMenuItem(title: "重置双栏对齐微调偏移", action: #selector(MultiTabMainWindowController.readerResetAlignmentShortcut), keyEquivalent: "0")
        resetAlignItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(resetAlignItem)

        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "放大当前栏页面", action: #selector(MultiTabMainWindowController.readerZoomInShortcut), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "缩小当前栏页面", action: #selector(MultiTabMainWindowController.readerZoomOutShortcut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "当前栏自适应宽度", action: #selector(MultiTabMainWindowController.readerZoomFitShortcut), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "展开/收起右侧目录与笔记抽屉", action: #selector(MultiTabMainWindowController.readerToggleDrawerShortcut), keyEquivalent: "i")
        let readerBarItem = NSMenuItem(title: "隐藏/显示阅读器顶栏", action: #selector(MultiTabMainWindowController.readerToggleTopBarShortcut), keyEquivalent: "t")
        readerBarItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(readerBarItem)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "标签页与窗口")
        windowMenuItem.submenu = windowMenu

        let libTabItem = NSMenuItem(title: "切换到「我的文献库」", action: #selector(MultiTabMainWindowController.switchToLibraryTabShortcut), keyEquivalent: "L")
        libTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(libTabItem)

        let prevTabItem = NSMenuItem(title: "上一个标签页", action: #selector(MultiTabMainWindowController.selectPreviousTabShortcut), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(prevTabItem)

        let nextTabItem = NSMenuItem(title: "下一个标签页", action: #selector(MultiTabMainWindowController.selectNextTabShortcut), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(nextTabItem)

        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "最小化窗口", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        NSApp.mainMenu = mainMenu
    }
}

private final class RecentMenuRefreshDelegate: NSObject, NSMenuDelegate {
    static let shared = RecentMenuRefreshDelegate()
    weak var appDelegate: AppDelegate?

    func menuWillOpen(_ menu: NSMenu) {
        appDelegate?.rebuildRecentMenu()
    }
}
