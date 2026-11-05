import Cocoa
import PDFKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Drag-Aware Modern WebView for Library Workspace
final class LibraryWorkspaceWebView: WKWebView {
    var onPDFsDroppedIntoLibrary: (([URL], String?) -> Void)?
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }

    /// Synced from DOM getBoundingClientRect() in top-left (flipped) coordinates
    var areInspectorPDFSlotsActive: Bool = true
    var origSlotDOMRect: NSRect = .zero
    var transSlotDOMRect: NSRect = .zero

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pdfs = extractPDFURLs(from: sender)
        guard !pdfs.isEmpty else { return [] }
        let pt = topLeftPoint(from: sender)
        let zone = detectDropTargetZone(atTopLeftPoint: pt)
        evaluateJavaScript("window.updateNativeDragHover ? window.updateNativeDragHover(\(pt.x), \(pt.y)) : (window.setNativeDragState && window.setNativeDragState(true, '\(zone)'));", completionHandler: nil)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pdfs = extractPDFURLs(from: sender)
        guard !pdfs.isEmpty else { return [] }
        let pt = topLeftPoint(from: sender)
        let zone = detectDropTargetZone(atTopLeftPoint: pt)
        evaluateJavaScript("window.updateNativeDragHover ? window.updateNativeDragHover(\(pt.x), \(pt.y)) : (window.setNativeDragState && window.setNativeDragState(true, '\(zone)'));", completionHandler: nil)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        evaluateJavaScript("window.setNativeDragState && window.setNativeDragState(false, '');", completionHandler: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        evaluateJavaScript("window.setNativeDragState && window.setNativeDragState(false, '');", completionHandler: nil)
        let pdfs = extractPDFURLs(from: sender)
        guard !pdfs.isEmpty else { return false }
        let pt = topLeftPoint(from: sender)
        let fallbackZone = detectDropTargetZone(atTopLeftPoint: pt)
        evaluateJavaScript("window.resolveNativeDropZone ? window.resolveNativeDropZone(\(pt.x), \(pt.y)) : '\(fallbackZone)'") { [weak self] res, _ in
            let resolved = (res as? String) ?? fallbackZone
            self?.onPDFsDroppedIntoLibrary?(pdfs, resolved)
        }
        return true
    }

    private func topLeftPoint(from sender: NSDraggingInfo) -> NSPoint {
        let pt = convert(sender.draggingLocation, from: nil)
        let yFromTop = isFlipped ? pt.y : (bounds.height - pt.y)
        return NSPoint(x: pt.x, y: yFromTop)
    }

    func detectDropTargetZone(atTopLeftPoint pt: NSPoint) -> String {
        guard areInspectorPDFSlotsActive else { return "library" }
        if !origSlotDOMRect.isEmpty && origSlotDOMRect.contains(pt) {
            return "original"
        }
        if !transSlotDOMRect.isEmpty && transSlotDOMRect.contains(pt) {
            return "translated"
        }
        // Fallback before initial DOM rect sync if inspector is open on Tab 0
        if origSlotDOMRect.isEmpty && transSlotDOMRect.isEmpty && bounds.width - pt.x <= 366 {
            let inspectorX = pt.x - (bounds.width - 366)
            if pt.y >= 175 && pt.y <= 290 {
                return inspectorX < 183 ? "original" : "translated"
            }
        }
        return "library"
    }

    private func extractPDFURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "pdf" }
    }
}

// MARK: - Modern Koodo Reader + Zotero 7 Library View Controller
final class LibraryViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var onOpenPaperInTab: ((String, PaperAnnotation?) -> Void)?
    var onOpenPaperNotesSidebar: ((String) -> Void)?
    var onOpenPaperAndJumpURL: ((String, String) -> Void)?
    var onEditAnnotationInTab: ((String, PaperAnnotation) -> Void)?

    private(set) var webView: LibraryWorkspaceWebView!
    private(set) var isWebViewLoaded = false
    private var pendingStateJSON: String?
    private var pendingOpenCreateModal = false
    private var pendingFocusSearch = false
    private var refreshTask: DispatchWorkItem?

    private(set) var selectedPaperId: String?
    private var pendingModalOrigURL: URL?
    private var pendingModalTransURL: URL?

    deinit {
        refreshTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "libraryBridge")
    }

    // MARK: - Codable State DTOs for Instant WebView Sync
    private struct AnnotationDTO: Codable {
        let id: String
        let paperId: String
        let paperTitle: String
        let sideRaw: String
        let sideBadge: String
        let pageNumber: Int
        let colorHex: String
        let selectedText: String
        let markdownNote: String
        let linkedURL: String?
        let linkedTitle: String?
        let createdTimestamp: Double
    }

    private struct RelatedDTO: Codable {
        let targetPaperId: String
        let targetTitle: String
        let targetYear: String
        let relationNote: String
    }

    private struct ResourceDTO: Codable {
        let id: String
        let title: String
        let urlOrPath: String
        let isLocalFile: Bool
    }

    private struct AdditionalPDFDTO: Codable {
        let id: String
        let title: String
        let filename: String
    }

    private struct NoteDocDTO: Codable {
        let id: String
        let title: String
        let markdownContent: String
        let updatedTimestamp: Double
    }

    private struct PaperDTO: Codable {
        let id: String
        let title: String
        let authors: String
        let year: String
        let venue: String
        let category: String
        let tags: [String]
        let isFavorite: Bool
        let statusRaw: String
        let statusDisplay: String
        let hasOriginal: Bool
        let hasTranslated: Bool
        let hasBothPDFs: Bool
        let origPages: Int
        let origSizeKB: Int
        let origThumb: String?
        let transPages: Int
        let transSizeKB: Int
        let transThumb: String?
        let lastReadPage: Int
        let addedTimestamp: Double
        let lastOpenedTimestamp: Double
        let addedDateString: String
        let customSortIndex: Int?
        let arxivId: String?
        let citationCount: Int?
        let additionalPDFs: [AdditionalPDFDTO]
        let noteDocuments: [NoteDocDTO]
        let annotations: [AnnotationDTO]
        let relatedPapers: [RelatedDTO]
        let resources: [ResourceDTO]
    }

    private struct LibraryStatePayload: Codable {
        let selectedPaperId: String?
        let vaultPath: String
        let categories: [String]
        let tags: [String]
        let papers: [PaperDTO]
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 840))
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root

        selectedPaperId = LibraryStore.shared.papers.first?.id
        setupModernWorkspaceWebView(in: root)
        refreshAllUI()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLibraryDidChange),
            name: LibraryStore.libraryDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleRefresh),
            name: LibraryStore.pdfSummaryDidChangeNotification, object: LibraryStore.shared)
        NotificationCenter.default.addObserver(self, selector: #selector(injectSystemAccentCSSVariables),
            name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    /// 将系统强调色 / 星标橙色注入 WebView 的 CSS 变量（CSS 中保留蓝色回退值）
    @objc private func injectSystemAccentCSSVariables() {
        guard let webView = webView, isWebViewLoaded else { return }
        let appearance = webView.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var vars: [String: String] = [:]
        appearance.performAsCurrentDrawingAppearance {
            let base = NSColor.controlAccentColor
            // hover：浅色略深（向黑 15%），深色略浅（向白 20%）
            let hover = base.blended(withFraction: isDark ? 0.20 : 0.15, of: isDark ? .white : .black) ?? base
            vars["--accent"] = cssColorString(from: base)
            vars["--accent-hover"] = cssColorString(from: hover)
            vars["--accent-soft"] = cssColorString(from: base, alpha: isDark ? 0.16 : 0.10)
            vars["--accent-border"] = cssColorString(from: base, alpha: isDark ? 0.42 : 0.35)
            vars["--semantic-favorite"] = cssColorString(from: .systemOrange)
        }
        let js = vars.map { "document.documentElement.style.setProperty('\($0.key)','\($0.value)');" }.joined()
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func cssColorString(from color: NSColor, alpha: CGFloat? = nil) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        if let alpha = alpha {
            return "rgba(\(r), \(g), \(b), \(alpha))"
        }
        return "rgb(\(r), \(g), \(b))"
    }

    private func setupModernWorkspaceWebView(in root: NSView) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakScriptMessageHandler(self), name: "libraryBridge")

        webView = LibraryWorkspaceWebView(frame: root.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.registerForDraggedTypes([.fileURL])
        webView.translatesAutoresizingMaskIntoConstraints = false

        webView.onPDFsDroppedIntoLibrary = { [weak self] urls, zone in
            self?.handleDroppedPDFs(urls, targetZone: zone)
        }
        webView.onEffectiveAppearanceChange = { [weak self] in
            self?.injectSystemAccentCSSVariables()
        }

        root.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let initialJSON = buildLibraryStateJSON()
        let html = LibraryWorkspacePage.html(initialStateJSON: initialJSON)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isWebViewLoaded = true
        injectSystemAccentCSSVariables()
        if let pending = pendingStateJSON {
            pendingStateJSON = nil
            pushStateToWebView(pending)
        }
        if pendingOpenCreateModal {
            pendingOpenCreateModal = false
            webView.evaluateJavaScript("window.openCreatePaperModal && window.openCreatePaperModal();", completionHandler: nil)
        }
        if pendingFocusSearch {
            pendingFocusSearch = false
            webView.evaluateJavaScript("window.focusLibrarySearch && window.focusLibrarySearch();", completionHandler: nil)
        }
    }

    @objc private func handleLibraryDidChange() {
        if selectedPaperId == nil || LibraryStore.shared.paper(withId: selectedPaperId!) == nil {
            selectedPaperId = LibraryStore.shared.papers.first?.id
        }
        scheduleRefresh()
    }

    @objc private func scheduleRefresh() {
        guard isViewLoaded, !view.isHidden else { return }
        refreshTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.refreshAllUI() }
        refreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
    }

    // MARK: - Public API (Used by MultiTabMainWindowController & Menu Bar)
    func refreshAllUI() {
        refreshTask?.cancel()
        refreshTask = nil
        if selectedPaperId == nil || LibraryStore.shared.paper(withId: selectedPaperId!) == nil {
            selectedPaperId = LibraryStore.shared.papers.first?.id
        }
        let stateJSON = buildLibraryStateJSON()
        if isWebViewLoaded {
            pushStateToWebView(stateJSON)
        } else {
            pendingStateJSON = stateJSON
        }
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(webView)
        if isWebViewLoaded {
            webView?.evaluateJavaScript("window.focusLibrarySearch && window.focusLibrarySearch();", completionHandler: nil)
        } else {
            pendingFocusSearch = true
        }
    }

    @objc func presentCreatePaperModal() {
        pendingModalOrigURL = nil
        pendingModalTransURL = nil
        view.window?.makeFirstResponder(webView)
        if isWebViewLoaded {
            webView?.evaluateJavaScript("window.openCreatePaperModal && window.openCreatePaperModal();", completionHandler: nil)
        } else {
            pendingOpenCreateModal = true
        }
    }

    // MARK: - Build State JSON with Cached Cover Thumbnails
    private func buildLibraryStateJSON() -> String {
        let store = LibraryStore.shared
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let paperDTOs: [PaperDTO] = store.papers.map { p in
            let originalURL = store.pdfURL(for: p, side: .original)
            let translatedURL = store.pdfURL(for: p, side: .translated)
            var origPages = 0
            var origSizeKB = 0
            var origThumb: String? = nil
            if let origURL = originalURL {
                let summary = p.id == selectedPaperId ? store.requestPDFSummary(for: origURL) : store.knownPDFSummary(for: origURL)
                origPages = summary.pageCount
                origSizeKB = summary.sizeKB
                origThumb = summary.thumbnailDataURL
            }

            var transPages = 0
            var transSizeKB = 0
            var transThumb: String? = nil
            if let transURL = translatedURL {
                let summary = p.id == selectedPaperId ? store.requestPDFSummary(for: transURL) : store.knownPDFSummary(for: transURL)
                transPages = summary.pageCount
                transSizeKB = summary.sizeKB
                transThumb = summary.thumbnailDataURL
            }

            let sortedAnnots = p.annotations.sorted {
                if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
                return $0.createdAt < $1.createdAt
            }
            let annotDTOs: [AnnotationDTO] = sortedAnnots.map { a in
                AnnotationDTO(
                    id: a.id,
                    paperId: p.id,
                    paperTitle: p.title,
                    sideRaw: a.effectivePDFId,
                    sideBadge: a.shortSourceBadge(in: p),
                    pageNumber: a.pageIndex + 1,
                    colorHex: a.color.hexString,
                    selectedText: a.selectedText,
                    markdownNote: a.markdownNote,
                    linkedURL: a.linkedURL,
                    linkedTitle: a.linkedTitle,
                    createdTimestamp: a.createdAt.timeIntervalSince1970
                )
            }

            let relatedDTOs: [RelatedDTO] = p.relatedPapers.map { rel in
                let target = store.paper(withId: rel.targetPaperId)
                return RelatedDTO(
                    targetPaperId: rel.targetPaperId,
                    targetTitle: target?.title ?? rel.targetPaperId,
                    targetYear: target?.year ?? "",
                    relationNote: rel.relationNote
                )
            }

            let resDTOs: [ResourceDTO] = p.resources.map { r in
                ResourceDTO(id: r.id, title: r.title, urlOrPath: r.urlOrPath, isLocalFile: r.isLocalFile)
            }

            let extraPDFs: [AdditionalPDFDTO] = (p.additionalPDFs ?? []).map {
                AdditionalPDFDTO(id: $0.id, title: $0.title, filename: $0.filename)
            }

            let noteDocs: [NoteDocDTO] = (p.noteDocuments ?? []).filter { !$0.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
                NoteDocDTO(id: $0.id, title: $0.title, markdownContent: $0.markdownContent, updatedTimestamp: $0.updatedAt.timeIntervalSince1970)
            }

            return PaperDTO(
                id: p.id,
                title: p.title,
                authors: p.authors,
                year: p.year,
                venue: p.venue,
                category: p.category,
                tags: p.tags,
                isFavorite: p.isFavorite,
                statusRaw: p.status.rawValue,
                statusDisplay: p.status.displayName,
                hasOriginal: originalURL != nil,
                hasTranslated: translatedURL != nil,
                hasBothPDFs: originalURL != nil && translatedURL != nil,
                origPages: origPages,
                origSizeKB: origSizeKB,
                origThumb: origThumb,
                transPages: transPages,
                transSizeKB: transSizeKB,
                transThumb: transThumb,
                lastReadPage: p.lastReadPage,
                addedTimestamp: p.addedAt.timeIntervalSince1970,
                lastOpenedTimestamp: (p.lastOpenedAt ?? p.addedAt).timeIntervalSince1970,
                addedDateString: dateFormatter.string(from: p.addedAt),
                customSortIndex: p.customSortIndex,
                arxivId: p.arxivId,
                citationCount: p.citationCount,
                additionalPDFs: extraPDFs,
                noteDocuments: noteDocs,
                annotations: annotDTOs,
                relatedPapers: relatedDTOs,
                resources: resDTOs
            )
        }

        let payload = LibraryStatePayload(
            selectedPaperId: selectedPaperId,
            vaultPath: store.rootDirectory.path,
            categories: store.allCategories(),
            tags: store.allTags(),
            papers: paperDTOs
        )

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(payload), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    func evaluateJavaScript(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func pushStateToWebView(_ jsonString: String) {
        webView?.evaluateJavaScript("window.updateLibraryState && window.updateLibraryState(\(jsonString));", completionHandler: nil)
    }

    // MARK: - Drag & Drop Handler
    private func handleDroppedPDFs(_ urls: [URL], targetZone: String?) {
        if let zone = targetZone, (zone == "original" || zone == "translated"),
           let pid = selectedPaperId, let firstURL = urls.first {
            let side: PDFSide = (zone == "original") ? .original : .translated
            LibraryStore.shared.importPDF(for: pid, side: side, from: firstURL)
            return
        }

        let defaultCat = LibraryStore.shared.allCategories().first ?? "大模型架构 (LLM)"
        if let created = LibraryStore.shared.smartCreatePaperFromPDFs(urls, category: defaultCat) {
            selectedPaperId = created.id
            onOpenPaperInTab?(created.id, nil)
        }
    }

    static func metadataTags(from value: Any?) -> [String]? {
        let values: [String]
        if let tags = value as? [String] { values = tags }
        else if let tags = value as? String { values = [tags] }
        else { return nil }
        return values.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^#", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func presentCreateCategoryDialog(moving paperId: String?) {
        let store = LibraryStore.shared
        if let paperId = paperId, store.paper(withId: paperId) == nil { return }
        let alert = NSAlert()
        alert.messageText = "新建分类"
        alert.informativeText = paperId == nil ? "输入分类名称；空分类也会保存在当前文献库中。" : "输入分类名称，并将当前论文移动到该分类。"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "分类名称"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let category = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.createCategory(category) else { return }
        if let paperId = paperId, var paper = store.paper(withId: paperId) {
            paper.category = category
            guard store.savePaper(paper, notify: true) else {
                refreshAllUI()
                return
            }
        }
        refreshAllUI()
        if paperId == nil, let data = try? JSONEncoder().encode(category),
           let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.onCategoryCreated && window.onCategoryCreated(\(json));", completionHandler: nil)
        }
    }

    // MARK: - JavaScript Bridge Message Handler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "libraryBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        let store = LibraryStore.shared

        switch action {
        case "selectPaper":
            if let pid = body["paperId"] as? String {
                selectedPaperId = pid
            }

        case "openPaper":
            if let pid = body["paperId"] as? String {
                selectedPaperId = pid
                onOpenPaperInTab?(pid, nil)
            }

        case "openPaperNotesSidebar":
            if let pid = body["paperId"] as? String {
                selectedPaperId = pid
                if let handler = onOpenPaperNotesSidebar {
                    handler(pid)
                } else {
                    onOpenPaperInTab?(pid, nil)
                }
            }

        case "reorderPapers":
            if let orderedIds = body["orderedIds"] as? [String], !orderedIds.isEmpty {
                store.reorderPapers(orderedIds: orderedIds)
            }

        case "addAdditionalPDF":
            guard let pid = body["paperId"] as? String else { return }
            let panel = NSOpenPanel()
            panel.title = "向本论文集添加额外 PDF 文件（如补充材料、附录或另一版本）"
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let url = panel.url {
                _ = store.addAdditionalPDF(to: pid, from: url)
            }

        case "removeAdditionalPDF":
            guard let pid = body["paperId"] as? String,
                  let pdfId = body["pdfId"] as? String else { return }
            store.removeAdditionalPDF(from: pid, pdfId: pdfId)

        case "noteJumpLink":
            guard let urlStr = body["url"] as? String else { return }
            let pid = (body["paperId"] as? String) ?? selectedPaperId
            if let pid = pid {
                selectedPaperId = pid
                if let jumpHandler = onOpenPaperAndJumpURL {
                    jumpHandler(pid, urlStr)
                } else {
                    onOpenPaperInTab?(pid, nil)
                }
            }

        case "toggleStar":
            if let pid = body["paperId"] as? String, var paper = store.paper(withId: pid) {
                paper.isFavorite.toggle()
                store.savePaper(paper, notify: true)
            }

        case "updateStatus":
            if let pid = body["paperId"] as? String,
               let stRaw = body["status"] as? String,
               let st = ReadingStatus(rawValue: stRaw),
               var paper = store.paper(withId: pid) {
                paper.status = st
                store.savePaper(paper, notify: true)
            }

        case "saveMetadata":
            guard let pid = body["paperId"] as? String, var paper = store.paper(withId: pid) else { return }
            if let title = body["title"] as? String {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { paper.title = trimmed }
            }
            if let authors = body["authors"] as? String {
                paper.authors = authors.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let year = body["year"] as? String {
                paper.year = year.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let venue = body["venue"] as? String {
                paper.venue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let category = body["category"] as? String {
                let c = category.trimmingCharacters(in: .whitespacesAndNewlines)
                paper.category = c.isEmpty ? "默认分类" : c
            }
            if let tags = Self.metadataTags(from: body["tags"]) { paper.tags = tags }
            if let aid = body["arxivId"] as? String {
                let cleanAid = aid.trimmingCharacters(in: .whitespacesAndNewlines)
                paper.arxivId = cleanAid.isEmpty ? nil : cleanAid
            }
            store.savePaper(paper, notify: true)

        case "autoExtractMetadata":
            guard let pid = body["paperId"] as? String,
                  var paper = store.paper(withId: pid),
                  let pdfURL = store.pdfURL(for: paper, side: .original) ?? store.pdfURL(for: paper, side: .translated) else { return }
            let meta = store.extractMetadata(from: pdfURL)
            if !meta.title.isEmpty && meta.title != "未命名论文" { paper.title = meta.title }
            if !meta.authors.isEmpty { paper.authors = meta.authors }
            if !meta.year.isEmpty { paper.year = meta.year }
            store.savePaper(paper, notify: true)

        case "importOrReplacePDF":
            guard let pid = body["paperId"] as? String,
                  let sideStr = body["side"] as? String else { return }
            let side: PDFSide = (sideStr == "translated") ? .translated : .original
            let panel = NSOpenPanel()
            panel.title = (side == .original) ? "选择英文原版 PDF (Original EN)" : "选择中文译版 PDF (Translated ZH)"
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let url = panel.url {
                store.importPDF(for: pid, side: side, from: url)
            }

        case "pickModalPDFs":
            let mode = (body["mode"] as? String) ?? "both"
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.pdf]
            if mode == "both" {
                panel.title = "选择 1 个或 2 个 PDF 文件（支持按住 ⌘ 同时选中原版与中文译版）"
                panel.allowsMultipleSelection = true
            } else if mode == "original" {
                panel.title = "选择原版 PDF (Original EN)"
                panel.allowsMultipleSelection = false
            } else {
                panel.title = "选择中文译版 PDF (Translated ZH)"
                panel.allowsMultipleSelection = false
            }

            if panel.runModal() == .OK, !panel.urls.isEmpty {
                if mode == "both" {
                    let classified = store.classifyPDFPair(panel.urls)
                    if let o = classified.original { pendingModalOrigURL = o }
                    if let t = classified.translated { pendingModalTransURL = t }
                } else if mode == "original" {
                    pendingModalOrigURL = panel.url
                } else {
                    pendingModalTransURL = panel.url
                }

                let primary = pendingModalOrigURL ?? pendingModalTransURL
                let meta = primary.map { store.extractMetadata(from: $0) }
                let resp: [String: String] = [
                    "origName": pendingModalOrigURL?.lastPathComponent ?? "",
                    "transName": pendingModalTransURL?.lastPathComponent ?? "",
                    "title": meta?.title ?? "",
                    "authors": meta?.authors ?? "",
                    "year": meta?.year ?? String(Calendar.current.component(.year, from: Date())),
                    "arxivId": meta?.arxivId ?? ""
                ]
                if let data = try? JSONEncoder().encode(resp), let json = String(data: data, encoding: .utf8) {
                    webView.evaluateJavaScript("window.onModalPDFsPicked && window.onModalPDFsPicked(\(json));", completionHandler: nil)
                }
            }

        case "confirmCreatePaper":
            let rawTitle = (body["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawAuthors = (body["authors"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawYear = (body["year"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawVenue = (body["venue"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "arXiv"
            let rawCategory = (body["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "大模型架构 (LLM)"
            let rawTags = (body["tags"] as? String) ?? ""

            let primary = pendingModalOrigURL ?? pendingModalTransURL
            let extracted = primary.map { store.extractMetadata(from: $0) }
            let finalTitle = rawTitle.isEmpty ? (extracted?.title ?? "新导入论文") : rawTitle
            let finalAuthors = rawAuthors.isEmpty ? (extracted?.authors ?? "") : rawAuthors
            let finalYear = rawYear.isEmpty ? (extracted?.year ?? String(Calendar.current.component(.year, from: Date()))) : rawYear
            let tags = rawTags
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^#", with: "", options: .regularExpression) }
                .filter { !$0.isEmpty }

            guard let created = store.createPaper(
                title: finalTitle,
                authors: finalAuthors,
                year: finalYear,
                venue: rawVenue.isEmpty ? "arXiv" : rawVenue,
                category: rawCategory.isEmpty ? "默认分类" : rawCategory,
                tags: tags,
                arxivId: (body["arxivId"] as? String).flatMap { ArxivMetadataService.normalizeArxivId($0) } ?? extracted?.arxivId,
                originalSourceURL: pendingModalOrigURL,
                translatedSourceURL: pendingModalTransURL
            ) else { return }
            pendingModalOrigURL = nil
            pendingModalTransURL = nil
            selectedPaperId = created.id
            if let arxivId = created.cleanArxivId {
                store.refreshPaperArxivMetadata(paperId: created.id, arxivId: arxivId, completion: nil)
            }
            onOpenPaperInTab?(created.id, nil)

        case "revealFolder":
            if let pid = body["paperId"] as? String {
                NSWorkspace.shared.open(store.folderURL(for: pid))
            } else {
                NSWorkspace.shared.open(store.rootDirectory)
            }

        case "revealMarkdown":
            if let pid = body["paperId"] as? String {
                let url = store.markdownNotesURL(for: pid)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

        case "deletePaper":
            guard let pid = body["paperId"] as? String,
                  let paper = store.paper(withId: pid) else { return }
            let alert = NSAlert()
            alert.messageText = "确认从文献库移除《\(paper.title)》吗？"
            alert.informativeText = "该论文文件夹下的 PDF 与笔记将被移出当前文献库。"
            alert.addButton(withTitle: "确认移除")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                store.deletePaper(id: pid)
            }

        case "noteJump":
            guard let annotId = body["annotId"] as? String else { return }
            for p in store.papers {
                if let annot = p.annotations.first(where: { $0.id == annotId }) {
                    selectedPaperId = p.id
                    onOpenPaperInTab?(p.id, annot)
                    break
                }
            }

        case "noteEdit":
            guard let annotId = body["annotId"] as? String else { return }
            for p in store.papers {
                if let annot = p.annotations.first(where: { $0.id == annotId }) {
                    selectedPaperId = p.id
                    if let editHandler = onEditAnnotationInTab {
                        editHandler(p.id, annot)
                    } else {
                        onOpenPaperInTab?(p.id, annot)
                    }
                    break
                }
            }

        case "noteDelete":
            guard let annotId = body["annotId"] as? String else { return }
            for var p in store.papers {
                if p.annotations.contains(where: { $0.id == annotId }) {
                    p.annotations.removeAll { $0.id == annotId }
                    store.savePaper(p, notify: true)
                    break
                }
            }

        case "noteOpenLink":
            guard let annotId = body["annotId"] as? String else { return }
            for p in store.papers {
                if let annot = p.annotations.first(where: { $0.id == annotId }),
                   let link = annot.linkedURL {
                    openLinkOrPath(link)
                    break
                }
            }

        case "linkRelatedPaper":
            guard let pid = body["paperId"] as? String,
                  let targetId = body["targetPaperId"] as? String else { return }
            let note = (body["relationNote"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            store.linkRelatedPapers(paperAId: pid, paperBId: targetId, note: note)

        case "unlinkRelatedPaper":
            guard let pid = body["paperId"] as? String,
                  let targetId = body["targetPaperId"] as? String else { return }
            store.unlinkRelatedPapers(paperAId: pid, paperBId: targetId)

        case "addWebResource":
            guard let pid = body["paperId"] as? String,
                  let urlStr = (body["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlStr.isEmpty,
                  var paper = store.paper(withId: pid) else { return }
            let titleStr = (body["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            paper.resources.append(ExternalResource(title: titleStr.isEmpty ? urlStr : titleStr, urlOrPath: urlStr, isLocalFile: false))
            store.savePaper(paper, notify: true)

        case "addLocalAttachment":
            guard let pid = body["paperId"] as? String else { return }
            let panel = NSOpenPanel()
            panel.title = "选择要挂载到该论文的本地附件或代码文件"
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                _ = store.addLocalAttachment(to: pid, fileURL: url)
            }

        case "openResource":
            if let pathOrURL = body["urlOrPath"] as? String {
                openLinkOrPath(pathOrURL)
            }

        case "deleteResource":
            guard let pid = body["paperId"] as? String,
                  let resId = body["resourceId"] as? String,
                  var paper = store.paper(withId: pid) else { return }
            paper.resources.removeAll { $0.id == resId }
            store.savePaper(paper, notify: true)

        case "restoreSamples":
            store.restoreSamplePapers()

        case "syncDropSlotRects":
            let active = (body["active"] as? Bool) ?? false
            webView.areInspectorPDFSlotsActive = active
            if active,
               let oArr = body["origRect"] as? [Double], oArr.count == 4,
               let tArr = body["transRect"] as? [Double], tArr.count == 4 {
                webView.origSlotDOMRect = NSRect(x: oArr[0], y: oArr[1], width: oArr[2], height: oArr[3])
                webView.transSlotDOMRect = NSRect(x: tArr[0], y: tArr[1], width: tArr[2], height: tArr[3])
            } else {
                webView.origSlotDOMRect = .zero
                webView.transSlotDOMRect = .zero
            }

        case "createFromArxivId":
            guard let arxivInput = (body["arxivId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !arxivInput.isEmpty else { return }
            let category = (body["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "大模型架构 (LLM)"
            store.createPaperFromArxivId(arxivId: arxivInput, category: category.isEmpty ? "大模型架构 (LLM)" : category) { [weak self] created in
                DispatchQueue.main.async {
                    if let paper = created {
                        self?.selectedPaperId = paper.id
                        self?.onOpenPaperInTab?(paper.id, nil)
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "无法获取或下载该 arXiv 论文"
                        alert.informativeText = "请检查输入的 arXiv ID 或论文链接是否有效，以及网络连接是否正常。"
                        alert.runModal()
                    }
                }
            }

        case "refreshArxivMetadata":
            guard let pid = body["paperId"] as? String else { return }
            store.refreshPaperArxivMetadata(paperId: pid)

        case "importTranslatedPDF":
            guard let pid = body["paperId"] as? String else { return }
            let panel = NSOpenPanel()
            panel.title = "导入中文译版 PDF"
            panel.allowedContentTypes = [.pdf]
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                store.importTranslatedPDF(for: pid, from: url)
            }

        case "importAttachment":
            guard let pid = body["paperId"] as? String else { return }
            let panel = NSOpenPanel()
            panel.title = "导入附件文件"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                _ = store.importAttachmentFile(for: pid, from: url)
            }

        case "openInNewWindow":
            guard let pid = body["paperId"] as? String else { return }
            StandaloneReaderWindowManager.shared.openWindow(for: pid)

        case "createCategory":
            presentCreateCategoryDialog(moving: body["paperId"] as? String)

        case "setPaperCategory":
            guard let pid = body["paperId"] as? String,
                  let cat = body["category"] as? String,
                  var paper = store.paper(withId: pid) else { return }
            paper.category = cat.trimmingCharacters(in: .whitespacesAndNewlines)
            store.savePaper(paper, notify: true)

        case "openArxivURL":
            guard let pid = body["paperId"] as? String,
                  let paper = store.paper(withId: pid),
                  let aid = paper.cleanArxivId,
                  let url = URL(string: "https://arxiv.org/abs/\(aid)") else { return }
            NSWorkspace.shared.open(url)

        case "openHjfyURL":
            guard let pid = body["paperId"] as? String,
                  let paper = store.paper(withId: pid),
                  let aid = paper.cleanArxivId,
                  let url = URL(string: "https://hjfy.top/arxiv/\(aid)") else { return }
            NSWorkspace.shared.open(url)

        default:
            break
        }
    }

    private func openLinkOrPath(_ link: String) {
        if link.hasPrefix("paper://") {
            let targetId = String(link.dropFirst("paper://".count))
            selectedPaperId = targetId
            onOpenPaperInTab?(targetId, nil)
        } else if (link.hasPrefix("http://") || link.hasPrefix("https://")), let u = URL(string: link) {
            NSWorkspace.shared.open(u)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: link))
        }
    }
}

