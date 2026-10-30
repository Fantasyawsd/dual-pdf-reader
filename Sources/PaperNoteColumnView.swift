import Cocoa
import WebKit

/// 阅读器右侧边栏中的 Markdown + LaTeX 论文笔记编辑器。
final class PaperNoteColumnView: NSView, NSTextViewDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var onCreateNewNoteRequested: (() -> Void)?
    var onDeleteCurrentNoteRequested: ((String) -> Void)?
    var onNoteContentChanged: ((PaperNoteDocument) -> Void)?
    var onJumpLinkClicked: ((String) -> Void)?
    var onInsertCurrentPDFSelectionLinkRequested: (() -> Void)?

    private(set) var currentNote: PaperNoteDocument?
    private var allNotes: [PaperNoteDocument] = []

    private let headerBar = NSVisualEffectView()
    private let insertJumpLinkBtn = NSButton()
    private let newNoteBtn = NSButton()
    private let deleteNoteBtn = NSButton()
    private let layoutSeg = NSSegmentedControl(labels: ["上下", "预览", "编辑"], trackingMode: .selectOne, target: nil, action: nil)

    private let splitView = NSSplitView()
    private let editorContainer = NSView()
    private let editorScroll = NSScrollView()
    let editorTextView = NSTextView()

    private let previewContainer = NSView()
    private var previewWebView: WKWebView!
    private var isPreviewReady = false
    private var saveDebounceTask: DispatchWorkItem?
    private var isProgrammaticUpdate = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        saveDebounceTask?.cancel()
    }

    func cleanupForClose() {
        flushPendingSave()
        saveDebounceTask?.cancel()
        previewWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "columnNoteBridge")
    }

    private func setupUI() {
        // 两行工具栏适配右侧边栏宽度。
        headerBar.material = .headerView
        headerBar.blendingMode = .withinWindow
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        insertJumpLinkBtn.bezelStyle = .texturedRounded
        insertJumpLinkBtn.controlSize = .small
        insertJumpLinkBtn.image = NSImage(systemSymbolName: "link.badge.plus", accessibilityDescription: "引用选中")
        insertJumpLinkBtn.imagePosition = .imageLeading
        insertJumpLinkBtn.title = " 引用选中"
        insertJumpLinkBtn.contentTintColor = .controlAccentColor
        insertJumpLinkBtn.toolTip = "将当前 PDF 中选中的文字（或当前页码）作为可点击跳转链接插入笔记"
        insertJumpLinkBtn.target = self
        insertJumpLinkBtn.action = #selector(insertJumpLinkBtnClicked)

        var barViews: [NSView] = [insertJumpLinkBtn]
        var formattingViews: [NSView] = []
        let snippets: [(title: String, snippet: String)] = [
            ("H2", "\n## 章节笔记\n"),
            ("B", "**重点**"),
            ("$x$", "$x_i$"),
            ("$$", "\n$$\n\\mathcal{L} = \\frac{1}{N}\\sum_{i=1}^{N} x_i\n$$\n")
        ]
        for item in snippets {
            let b = NSButton(title: item.title, target: self, action: #selector(snippetBtnClicked(_:)))
            b.bezelStyle = .inline
            b.controlSize = .small
            b.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            b.identifier = NSUserInterfaceItemIdentifier(item.snippet)
            formattingViews.append(b)
        }

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        barViews.append(headerSpacer)

        newNoteBtn.bezelStyle = .texturedRounded
        newNoteBtn.controlSize = .small
        newNoteBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建笔记")
        newNoteBtn.toolTip = "在本论文下创建新的独立笔记文档"
        newNoteBtn.target = self
        newNoteBtn.action = #selector(newNoteBtnClicked)
        barViews.append(newNoteBtn)

        deleteNoteBtn.bezelStyle = .texturedRounded
        deleteNoteBtn.controlSize = .small
        deleteNoteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除此笔记")
        deleteNoteBtn.toolTip = "删除当前笔记文档（至少保留一篇主笔记）"
        deleteNoteBtn.target = self
        deleteNoteBtn.action = #selector(deleteNoteBtnClicked)
        barViews.append(deleteNoteBtn)

        layoutSeg.selectedSegment = 0
        layoutSeg.controlSize = .small
        layoutSeg.segmentDistribution = .fillEqually
        layoutSeg.target = self
        layoutSeg.action = #selector(layoutSegChanged)
        layoutSeg.translatesAutoresizingMaskIntoConstraints = false
        layoutSeg.widthAnchor.constraint(equalToConstant: 114).isActive = true
        formattingViews.append(layoutSeg)

        let actionsRow = NSStackView(views: barViews)
        actionsRow.spacing = 5
        let formattingRow = NSStackView(views: formattingViews)
        formattingRow.spacing = 5
        let headerStack = NSStackView(views: [actionsRow, formattingRow])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 5
        headerStack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerStack)

        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerSep)

        // 2. 上下分栏：上方 Markdown + LaTeX 编辑器，下方实时可点击渲染预览
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)

        editorContainer.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = true
        editorScroll.backgroundColor = .textBackgroundColor
        editorScroll.translatesAutoresizingMaskIntoConstraints = false

        editorTextView.isRichText = false
        editorTextView.allowsUndo = true
        editorTextView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editorTextView.textColor = .labelColor
        editorTextView.backgroundColor = .textBackgroundColor
        editorTextView.textContainerInset = NSSize(width: 14, height: 12)
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.autoresizingMask = [.width]
        editorTextView.textContainer?.widthTracksTextView = true
        editorTextView.delegate = self
        editorScroll.documentView = editorTextView
        editorContainer.addSubview(editorScroll)

        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController.add(WeakScriptMessageHandler(self), name: "columnNoteBridge")
        previewWebView = WKWebView(frame: .zero, configuration: webConfig)
        previewWebView.navigationDelegate = self
        previewWebView.setValue(false, forKey: "drawsBackground")
        previewWebView.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(previewWebView)

        splitView.addArrangedSubview(editorContainer)
        splitView.addArrangedSubview(previewContainer)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 42),

            headerStack.topAnchor.constraint(equalTo: headerBar.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerStack.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            headerSep.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            editorScroll.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            editorScroll.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            editorScroll.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            editorScroll.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),

            previewWebView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewWebView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewWebView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewWebView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            editorContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            previewContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        ])

        let initialHTML = MarkdownMathRenderer.buildSinglePreviewHTML(
            markdown: "",
            emptyPlaceholder: "在上方输入 Markdown / LaTeX 笔记，或在 PDF 栏划选文字点击「引用笔记」自动插入可跳转链接…"
        )
        previewWebView.loadHTMLString(initialHTML, baseURL: nil)
    }

    func loadNote(_ note: PaperNoteDocument, allNotes: [PaperNoteDocument]) {
        flushPendingSave()
        self.currentNote = note
        self.allNotes = allNotes
        deleteNoteBtn.isHidden = allNotes.count <= 1

        if editorTextView.string != note.markdownContent {
            isProgrammaticUpdate = true
            editorTextView.string = note.markdownContent
            isProgrammaticUpdate = false
        }
        refreshPreviewHTML()
    }

    func appendOrInsertMarkdownLink(_ markdownSnippet: String) {
        guard var note = currentNote else { return }
        let currentText = editorTextView.string
        let newText: String
        if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newText = markdownSnippet + "\n\n"
        } else {
            let suffix = currentText.hasSuffix("\n\n") ? "" : (currentText.hasSuffix("\n") ? "\n" : "\n\n")
            newText = currentText + suffix + markdownSnippet + "\n\n"
        }
        isProgrammaticUpdate = true
        editorTextView.string = newText
        isProgrammaticUpdate = false
        note.markdownContent = newText
        note.updatedAt = Date()
        currentNote = note
        onNoteContentChanged?(note)
        refreshPreviewHTML()
    }

    func flushPendingSave() {
        guard let task = saveDebounceTask else { return }
        task.cancel()
        saveDebounceTask = nil
        guard var note = currentNote else { return }
        note.markdownContent = editorTextView.string
        note.updatedAt = Date()
        currentNote = note
        onNoteContentChanged?(note)
    }

    func textDidChange(_ notification: Notification) {
        guard !isProgrammaticUpdate, var note = currentNote else { return }
        note.markdownContent = editorTextView.string
        note.updatedAt = Date()
        currentNote = note
        refreshPreviewHTML()

        saveDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, let latest = self.currentNote else { return }
            self.saveDebounceTask = nil
            self.onNoteContentChanged?(latest)
        }
        saveDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPreviewReady = true
        refreshPreviewHTML()
    }

    private func refreshPreviewHTML() {
        let md = currentNote?.markdownContent ?? editorTextView.string
        guard isPreviewReady else { return }
        if let data = try? JSONEncoder().encode(md),
           let jsonStr = String(data: data, encoding: .utf8) {
            previewWebView.evaluateJavaScript("window.updatePreview && window.updatePreview(\(jsonStr));", completionHandler: nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "columnNoteBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        if action == "jumpLink", let url = body["url"] as? String {
            onJumpLinkClicked?(url)
        }
    }

    @objc private func newNoteBtnClicked() {
        onCreateNewNoteRequested?()
    }

    @objc private func deleteNoteBtnClicked() {
        guard let cur = currentNote, allNotes.count > 1 else { return }
        onDeleteCurrentNoteRequested?(cur.id)
    }

    @objc private func layoutSegChanged() {
        switch layoutSeg.selectedSegment {
        case 1: // 仅预览
            editorContainer.isHidden = true
            previewContainer.isHidden = false
        case 2: // 仅编辑
            editorContainer.isHidden = false
            previewContainer.isHidden = true
        default: // 分栏
            editorContainer.isHidden = false
            previewContainer.isHidden = false
            splitView.setPosition(splitView.bounds.height * 0.48, ofDividerAt: 0)
        }
        splitView.adjustSubviews()
    }

    @objc private func insertJumpLinkBtnClicked() {
        onInsertCurrentPDFSelectionLinkRequested?()
    }

    @objc private func snippetBtnClicked(_ sender: NSButton) {
        guard let snippet = sender.identifier?.rawValue else { return }
        editorTextView.insertText(snippet, replacementRange: editorTextView.selectedRange())
    }
}
