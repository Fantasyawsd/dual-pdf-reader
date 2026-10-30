import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MultiTabMainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        mainWindowController = MultiTabMainWindowController()
        mainWindowController?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        LibraryStore.shared.flushReadingState() ? .terminateNow : .terminateCancel
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. 应用主菜单
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

        // 2. 文件菜单
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "新建 / 导入论文条目…", action: #selector(MultiTabMainWindowController.newPaperShortcutAction), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "快速选择 PDF 双栏打开…", action: #selector(MultiTabMainWindowController.quickOpenPDFShortcutAction), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        let revealItem = NSMenuItem(title: "在 Finder 中显示文献库", action: #selector(MultiTabMainWindowController.revealVaultInFinderShortcut), keyEquivalent: "R")
        revealItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(revealItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "关闭当前阅读标签页", action: #selector(MultiTabMainWindowController.closeActiveTabShortcut), keyEquivalent: "w")

        // 3. 编辑菜单
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

        // 4. 阅读与视图菜单
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

        let mNote = NSMenuItem(title: "左栏论文 + 右栏精读笔记", action: #selector(MultiTabMainWindowController.readerModeLeftPDFRightNoteShortcut), keyEquivalent: "4")
        mNote.keyEquivalentModifierMask = [.control]
        viewMenu.addItem(mNote)

        viewMenu.addItem(NSMenuItem.separator())
        let swapItem = NSMenuItem(title: "左右两栏互换", action: #selector(MultiTabMainWindowController.readerSwapColumnsShortcut), keyEquivalent: "X")
        swapItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(swapItem)

        let resetAlignItem = NSMenuItem(title: "重置双栏对齐微调偏移", action: #selector(MultiTabMainWindowController.readerResetAlignmentShortcut), keyEquivalent: "0")
        resetAlignItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(resetAlignItem)

        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "放大页面", action: #selector(MultiTabMainWindowController.readerZoomInShortcut), keyEquivalent: "=")
        viewMenu.addItem(withTitle: "缩小页面", action: #selector(MultiTabMainWindowController.readerZoomOutShortcut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "自适应页面宽度", action: #selector(MultiTabMainWindowController.readerZoomFitShortcut), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "展开/收起右侧目录与笔记抽屉", action: #selector(MultiTabMainWindowController.readerToggleDrawerShortcut), keyEquivalent: "i")

        // 5. 标签页与窗口菜单
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

