import Cocoa
import WebKit

// MARK: - Live Preview Note Editor Sheet Controller
final class NoteEditorSheetController: NSViewController, NSTextViewDelegate, WKNavigationDelegate {
    private let annotation: PaperAnnotation
    private let onSave: (HighlightColor, String) -> Bool

    private var selectedColor: HighlightColor
    private var swatchButtons: [HighlightSwatchButton] = []
    private let textView = NSTextView()
    private var previewWebView: WKWebView!
    private var previewIsReady = false

    init(annotation: PaperAnnotation, onSave: @escaping (HighlightColor, String) -> Bool) {
        self.annotation = annotation
        self.selectedColor = annotation.color
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 430))
        self.view = root

        let headerTitle = NSTextField(labelWithString: "编辑精读笔记 (支持 Markdown 与 LaTeX 数学公式)")
        headerTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        headerTitle.textColor = .labelColor

        // 顶部栏：高亮颜色选择 + 快捷公式片段按钮
        let topToolbar = NSStackView()
        topToolbar.orientation = .horizontal
        topToolbar.alignment = .centerY
        topToolbar.spacing = 8
        topToolbar.translatesAutoresizingMaskIntoConstraints = false

        let colorLabel = NSTextField(labelWithString: "颜色:")
        colorLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        colorLabel.textColor = .secondaryLabelColor
        topToolbar.addArrangedSubview(colorLabel)

        for c in HighlightColor.allCases {
            let sw = HighlightSwatchButton(color: c, selected: c == selectedColor, target: self, action: #selector(swatchClicked(_:)))
            swatchButtons.append(sw)
            topToolbar.addArrangedSubview(sw)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topToolbar.addArrangedSubview(spacer)

        let snippets: [(title: String, insert: String)] = [
            ("$行内公式$", "$x_i$"),
            ("$$块公式$$", "\n$$\n\\mathcal{L} = \\frac{1}{N} \\sum_{i=1}^{N} x_i\n$$\n"),
            ("\\frac 分式", "\\frac{a}{b}"),
            ("\\sum 求和", "\\sum_{i=1}^{N}"),
            ("**加粗**", "**重点**")
        ]
        for item in snippets {
            let btn = NSButton(title: item.title, target: self, action: #selector(insertSnippetClicked(_:)))
            btn.bezelStyle = .inline
            btn.controlSize = .small
            btn.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
            btn.identifier = NSUserInterfaceItemIdentifier(item.insert)
            topToolbar.addArrangedSubview(btn)
        }

        // 编辑区 (上半部分)
        let editorScroll = NSScrollView()
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = annotation.markdownNote
        textView.delegate = self
        editorScroll.documentView = textView

        // 实时预览区 (下半部分)
        let previewLabel = NSTextField(labelWithString: "实时排版预览 (LaTeX + Markdown)")
        previewLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        let previewCard = ModernSurfaceCardView()
        previewCard.cornerRadius = 8
        previewCard.translatesAutoresizingMaskIntoConstraints = false

        previewWebView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        previewWebView.navigationDelegate = self
        previewWebView.setValue(false, forKey: "drawsBackground")
        previewWebView.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(previewWebView)

        let html = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: annotation.markdownNote)
        previewWebView.loadHTMLString(html, baseURL: nil)

        // 底部保存/取消按钮
        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"

        let saveBtn = NSButton(title: "保存笔记 (⌘↩)", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.keyEquivalentModifierMask = [.command]
        saveBtn.contentTintColor = .controlAccentColor

        let footerStack = NSStackView(views: [NSView(), cancelBtn, saveBtn])
        footerStack.orientation = .horizontal
        footerStack.spacing = 10
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(headerTitle)
        root.addSubview(topToolbar)
        root.addSubview(editorScroll)
        root.addSubview(previewLabel)
        root.addSubview(previewCard)
        root.addSubview(footerStack)

        NSLayoutConstraint.activate([
            headerTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            headerTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),

            topToolbar.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 10),
            topToolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            topToolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),

            editorScroll.topAnchor.constraint(equalTo: topToolbar.bottomAnchor, constant: 8),
            editorScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            editorScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            editorScroll.heightAnchor.constraint(equalToConstant: 155),

            previewLabel.topAnchor.constraint(equalTo: editorScroll.bottomAnchor, constant: 10),
            previewLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),

            previewCard.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 5),
            previewCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            previewCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            previewCard.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            previewWebView.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 2),
            previewWebView.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 2),
            previewWebView.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -2),
            previewWebView.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -2),

            footerStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            footerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            footerStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) {
        updatePreview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        previewIsReady = true
        updatePreview()
    }

    private func updatePreview() {
        guard previewIsReady else { return }
        if let data = try? JSONEncoder().encode(textView.string),
           let jsonStr = String(data: data, encoding: .utf8) {
            previewWebView.evaluateJavaScript("window.updatePreview && window.updatePreview(\(jsonStr));", completionHandler: nil)
        }
    }

    @objc private func swatchClicked(_ sender: HighlightSwatchButton) {
        selectedColor = sender.highlightColor
        swatchButtons.forEach { $0.isSelectedSwatch = ($0.highlightColor == selectedColor) }
    }

    @objc private func insertSnippetClicked(_ sender: NSButton) {
        guard let snippet = sender.identifier?.rawValue else { return }
        textView.insertText(snippet, replacementRange: textView.selectedRange())
    }

    @objc private func cancelClicked() {
        if let sheetWin = view.window, let parent = sheetWin.sheetParent {
            parent.endSheet(sheetWin, returnCode: .cancel)
        } else {
            dismiss(nil)
        }
    }

    @objc private func saveClicked() {
        guard onSave(selectedColor, textView.string) else { return }
        if let sheetWin = view.window, let parent = sheetWin.sheetParent {
            parent.endSheet(sheetWin, returnCode: .OK)
        } else {
            dismiss(nil)
        }
    }
}

