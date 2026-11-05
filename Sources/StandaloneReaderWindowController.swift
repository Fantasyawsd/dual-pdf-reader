import Cocoa

final class StandaloneReaderWindowController: NSWindowController, NSWindowDelegate {
    let paperId: String
    private let readerVC: ReaderTabViewController

    init(paperId: String, store: LibraryStore = .shared) {
        self.paperId = paperId
        self.readerVC = ReaderTabViewController(paperId: paperId)

        let title = store.paper(withId: paperId)?.title ?? "论文阅读"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 900, height: 600)
        window.center()

        super.init(window: window)
        window.delegate = self
        readerVC.onRequestOpenPaperTab = { targetId in
            StandaloneReaderWindowManager.shared.openWindow(for: targetId)
        }

        guard let contentView = window.contentView else { return }
        readerVC.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(readerVC.view)
        NSLayoutConstraint.activate([
            readerVC.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            readerVC.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            readerVC.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            readerVC.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Test seam for the close-window markup alert. `true` = 关闭, `false` = 取消; `nil` = show NSAlert.
    var testingDiscardSessionMarkupResponse: Bool? = nil

    var hasUnpersistedSessionMarkup: Bool { readerVC.hasUnpersistedColumnMarkup() }

    /// Closing a standalone reader window drops its tab, so warn here (quit won't see it afterwards,
    /// which also avoids a second prompt when this was the last window).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnpersistedSessionMarkup else { return true }
        if let forced = testingDiscardSessionMarkupResponse { return forced }
        let alert = NSAlert()
        alert.messageText = "此 PDF 上的批注仅本次有效，关闭后将丢失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        readerVC.prepareForClose()
        StandaloneReaderWindowManager.shared.windowDidClose(self)
    }
}

final class StandaloneReaderWindowManager {
    static let shared = StandaloneReaderWindowManager()
    private var openWindows: [String: StandaloneReaderWindowController] = [:]

    func openWindow(for paperId: String) {
        guard LibraryStore.shared.paper(withId: paperId) != nil else { return }

        if let existing = openWindows[paperId] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = StandaloneReaderWindowController(paperId: paperId)
        openWindows[paperId] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func unpersistedSessionMarkupWindowCount() -> Int {
        openWindows.values.filter { $0.hasUnpersistedSessionMarkup }.count
    }

    func windowDidClose(_ controller: StandaloneReaderWindowController) {
        openWindows.removeValue(forKey: controller.paperId)
    }
}
