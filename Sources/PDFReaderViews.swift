import Cocoa
import PDFKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Custom Native Circular Color Swatch Button (Replaces Emoji Circles)
final class HighlightSwatchButton: NSButton {
    let highlightColor: HighlightColor
    var isSelectedSwatch: Bool = false {
        didSet { needsDisplay = true }
    }
    private var isHovered: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: HighlightColor, selected: Bool = false, target: AnyObject?, action: Selector?) {
        self.highlightColor = color
        self.isSelectedSwatch = selected
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        self.target = target
        self.action = action
        self.isBordered = false
        self.title = ""
        self.toolTip = "\(color.displayName)高亮"
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isHovered ? 2.0 : 3.0
        let circleRect = bounds.insetBy(dx: inset, dy: inset)

        if isSelectedSwatch || isHovered {
            let ringRect = bounds.insetBy(dx: 0.8, dy: 0.8)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = isSelectedSwatch ? 1.6 : 1.0
            (isSelectedSwatch ? highlightColor.solidColor : NSColor.secondaryLabelColor.withAlphaComponent(0.45)).setStroke()
            ringPath.stroke()
        }

        let fillPath = NSBezierPath(ovalIn: circleRect)
        highlightColor.solidColor.setFill()
        fillPath.fill()

        let innerBorder = NSBezierPath(ovalIn: circleRect)
        innerBorder.lineWidth = 0.6
        NSColor.black.withAlphaComponent(0.15).setStroke()
        innerBorder.stroke()

        if isSelectedSwatch {
            let check = NSBezierPath()
            let cx = bounds.midX
            let cy = bounds.midY
            check.move(to: NSPoint(x: cx - 3.5, y: cy))
            check.line(to: NSPoint(x: cx - 1.0, y: cy - 2.8))
            check.line(to: NSPoint(x: cx + 4.0, y: cy + 3.0))
            check.lineWidth = 1.6
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        }
    }
}

// MARK: - Appearance-Aware Modern Card View
final class ModernSurfaceCardView: NSView {
    var cornerRadius: CGFloat = 8 { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 0.8 { didSet { needsDisplay = true } }
    var isEmphasizedCard: Bool = false { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        guard let layer = self.layer else { return }
        layer.cornerRadius = cornerRadius
        layer.borderWidth = borderWidth
        layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer.borderColor = (isEmphasizedCard ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Custom PDFView with Selection Popover, Link Jump Interception & Drag-Drop
final class InteractivePDFView: PDFView {
    var side: PDFSide = .original
    var activePDFDocumentId: String = PDFSide.original.rawValue
    var onTextSelectedForPopover: ((PDFSelection, NSRect) -> Void)?
    var onAnnotationClicked: ((PaperAnnotation, NSPoint) -> Void)?
    var onBeforeInternalLinkJump: ((PDFPage, NSPoint, Bool) -> Bool)?
    var onFileDropped: ((URL) -> Void)?
    var onOptionScrollPerformed: (() -> Void)?

    var storedAnnotations: [PaperAnnotation] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func scrollWheel(with event: NSEvent) {
        let isOptionHeld = event.modifierFlags.contains(.option)
        super.scrollWheel(with: event)
        if isOptionHeld {
            onOptionScrollPerformed?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let page = page(for: viewPoint, nearest: false),
           let doc = document {
            let pagePoint = convert(viewPoint, to: page)

            // 1. 检测是否点击了 PDF 原生内部跳转链接 (References / TOC / Figure Links)
            if let hitAnnot = page.annotation(at: pagePoint),
               (hitAnnot.type == "Link" || hitAnnot.type == "/Link") {
                var targetDest: PDFDestination?
                if let goTo = hitAnnot.action as? PDFActionGoTo {
                    targetDest = goTo.destination
                } else if let dest = hitAnnot.destination {
                    targetDest = dest
                }
                if let dest = targetDest, let destPage = dest.page {
                    let isCmdPressed = event.modifierFlags.contains(.command)
                    let handled = onBeforeInternalLinkJump?(destPage, dest.point, isCmdPressed) ?? false
                    if handled {
                        return
                    }
                }
            }

            // 2. 检测是否点击了自定义 PaperAnnotation 高亮/笔记/挂载链接区域
            let pageIdx = doc.index(for: page)
            if let hitCustom = storedAnnotations.first(where: { ann in
                ann.effectivePDFId == self.activePDFDocumentId && ann.pageRegions.contains(where: { region in
                    region.pageIndex == pageIdx && region.rects.contains(where: {
                        $0.cgRect.insetBy(dx: -2, dy: -2).contains(pagePoint)
                    })
                })
            }) {
                super.mouseDown(with: event)
                if currentSelection == nil || (currentSelection?.string?.isEmpty ?? true) {
                    onAnnotationClicked?(hitCustom, viewPoint)
                    return
                }
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard let sel = currentSelection,
              let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let firstPage = sel.pages.first else {
            return
        }
        let boundsOnPage = sel.bounds(for: firstPage)
        let rectInView = convert(boundsOnPage, from: firstPage)
        onTextSelectedForPopover?(sel, rectInView)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractPDFURL(from: sender) != nil { return .copy }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = extractPDFURL(from: sender) {
            onFileDropped?(url)
            return true
        }
        return super.performDragOperation(sender)
    }

    private func extractPDFURL(from sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return nil }
        return urls.first(where: { $0.pathExtension.lowercased() == "pdf" })
    }
}

// MARK: - Single Column Wrapper (Supports Any PDF or Note Document in the Current Paper Collection)
final class CleanPDFColumnView: NSView {
    let side: PDFSide
    var contentSource: ColumnContentSource
    var activePDFDocumentId: String {
        contentSource.pdfId ?? side.rawValue
    }

    let pdfView = InteractivePDFView()
    let noteColumnView = PaperNoteColumnView()
    private let emptyPlaceholder = NSView()
    private let dropCard = ModernSurfaceCardView()
    private let cornerBadge = NSVisualEffectView()
    let cornerButton = NSButton()
    private let emptyTitleLabel = NSTextField(labelWithString: "")
    private let emptyBindButton = NSButton()

    // 浮动“返回”胶囊按钮（跳转时显示，左栏发起的在左侧，右栏发起的在右侧，仅直接显示“返回”）
    let backJumpBanner = NSVisualEffectView()
    let backJumpButton = NSButton()
    var onBackJumpClicked: (() -> Void)?
    private var bannerHorizontalConstraint: NSLayoutConstraint?

    var currentPaperProvider: (() -> PaperItem?)?
    var onSelectColumnSource: ((ColumnContentSource) -> Void)?
    var onAddAdditionalPDFRequested: (() -> Void)?
    var onRemoveAdditionalPDFRequested: ((String) -> Void)?
    var onCreateNoteRequested: (() -> Void)?

    var onBindPDFRequested: ((PDFSide) -> Void)?
    var onRevealPDFInFinder: ((PDFSide) -> Void)?
    var onFileDropped: ((URL) -> Void)?
    private weak var cachedScrollView: NSScrollView?

    init(side: PDFSide) {
        self.side = side
        self.contentSource = .pdf(id: side.rawValue)
        self.pdfView.side = side
        self.pdfView.activePDFDocumentId = side.rawValue
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        // 极窄双栏间距设计：大幅缩减左右边距，消除双栏间过大空隙，使左右栏排版紧凑舒适
        pdfView.pageBreakMargins = NSEdgeInsets(top: 8, left: 1, bottom: 8, right: 1)
        pdfView.pageShadowsEnabled = true
        pdfView.backgroundColor = NSColor.underPageBackgroundColor
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)

        // 左上角极简半透明栏标识胶囊（点击可切换此栏显示的论文集 PDF 或笔记）
        cornerBadge.material = .menu
        cornerBadge.blendingMode = .withinWindow
        cornerBadge.wantsLayer = true
        cornerBadge.layer?.cornerRadius = 7
        cornerBadge.layer?.borderWidth = 0.6
        cornerBadge.layer?.borderColor = NSColor.separatorColor.cgColor
        cornerBadge.layer?.masksToBounds = true
        cornerBadge.alphaValue = 0.92
        cornerBadge.translatesAutoresizingMaskIntoConstraints = false

        cornerButton.bezelStyle = .inline
        cornerButton.isBordered = false
        cornerButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        cornerButton.contentTintColor = .labelColor
        cornerButton.title = side == .original ? "原文 EN ▾" : "译文 ZH ▾"
        cornerButton.toolTip = "点击切换此栏 PDF 或论文笔记"
        cornerButton.target = self
        cornerButton.action = #selector(cornerBadgeClicked(_:))
        cornerButton.translatesAutoresizingMaskIntoConstraints = false
        cornerBadge.addSubview(cornerButton)
        addSubview(cornerBadge)

        // 浮动“返回”胶囊按钮（直接显示“返回”，无多余文字提示）
        backJumpBanner.material = .hudWindow
        backJumpBanner.blendingMode = .withinWindow
        backJumpBanner.state = .active
        backJumpBanner.wantsLayer = true
        backJumpBanner.layer?.cornerRadius = 15
        backJumpBanner.layer?.masksToBounds = true
        backJumpBanner.translatesAutoresizingMaskIntoConstraints = false
        backJumpBanner.isHidden = true

        backJumpButton.bezelStyle = .texturedRounded
        backJumpButton.isBordered = false
        backJumpButton.font = .systemFont(ofSize: 13, weight: .semibold)
        backJumpButton.contentTintColor = .controlAccentColor
        backJumpButton.title = "返回"
        backJumpButton.toolTip = "返回跳转前位置 (⌘[)"
        backJumpButton.target = self
        backJumpButton.action = #selector(backJumpButtonClicked)
        backJumpButton.translatesAutoresizingMaskIntoConstraints = false

        backJumpBanner.addSubview(backJumpButton)
        addSubview(backJumpBanner)

        // 空状态占位（当该论文尚未导入该侧 PDF 时显示）
        emptyPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        emptyPlaceholder.wantsLayer = true

        dropCard.cornerRadius = 12
        dropCard.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView(image: NSImage(systemSymbolName: side == .original ? "doc.text.viewfinder" : "character.book.closed.fill.zh", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)!)
        iconView.symbolConfiguration = .init(pointSize: 38, weight: .light)
        iconView.contentTintColor = .secondaryLabelColor

        emptyTitleLabel.stringValue = side == .original ? "尚未绑定原版 PDF" : "尚未绑定中文译版 PDF"
        emptyTitleLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
        emptyTitleLabel.textColor = .labelColor

        let subLbl = NSTextField(labelWithString: "将 PDF 文件直接拖入此处，或点击下方按钮选择文件")
        subLbl.font = .systemFont(ofSize: 13)
        subLbl.textColor = .secondaryLabelColor

        emptyBindButton.title = side == .original ? "选择原版 PDF 文件…" : "选择中文版 PDF 文件…"
        emptyBindButton.target = self
        emptyBindButton.action = #selector(bindBtnClicked)
        emptyBindButton.bezelStyle = .rounded
        emptyBindButton.controlSize = .regular

        let switchToNoteBtn = NSButton(title: "📝 在此栏打开论文笔记", target: self, action: #selector(quickSwitchToNoteClicked))
        switchToNoteBtn.bezelStyle = .rounded
        switchToNoteBtn.controlSize = .small

        let stack = NSStackView(views: [iconView, emptyTitleLabel, subLbl, emptyBindButton, switchToNoteBtn])
        stack.orientation = .vertical
        stack.spacing = 9
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        dropCard.addSubview(stack)
        emptyPlaceholder.addSubview(dropCard)

        addSubview(emptyPlaceholder)

        // 嵌入式论文精读笔记视图（当此栏切换为笔记模式时显示）
        noteColumnView.isHidden = true
        noteColumnView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteColumnView)

        // 确保左上角切换胶囊与返回胶囊始终位于最上层
        addSubview(cornerBadge)
        addSubview(backJumpBanner)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),

            noteColumnView.topAnchor.constraint(equalTo: topAnchor),
            noteColumnView.leadingAnchor.constraint(equalTo: leadingAnchor),
            noteColumnView.trailingAnchor.constraint(equalTo: trailingAnchor),
            noteColumnView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cornerBadge.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            cornerBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            cornerButton.topAnchor.constraint(equalTo: cornerBadge.topAnchor, constant: 3),
            cornerButton.bottomAnchor.constraint(equalTo: cornerBadge.bottomAnchor, constant: -3),
            cornerButton.leadingAnchor.constraint(equalTo: cornerBadge.leadingAnchor, constant: 8),
            cornerButton.trailingAnchor.constraint(equalTo: cornerBadge.trailingAnchor, constant: -8),

            backJumpButton.topAnchor.constraint(equalTo: backJumpBanner.topAnchor, constant: 5),
            backJumpButton.bottomAnchor.constraint(equalTo: backJumpBanner.bottomAnchor, constant: -5),
            backJumpButton.leadingAnchor.constraint(equalTo: backJumpBanner.leadingAnchor, constant: 14),
            backJumpButton.trailingAnchor.constraint(equalTo: backJumpBanner.trailingAnchor, constant: -14),
            backJumpBanner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            emptyPlaceholder.topAnchor.constraint(equalTo: topAnchor),
            emptyPlaceholder.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyPlaceholder.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyPlaceholder.bottomAnchor.constraint(equalTo: bottomAnchor),

            dropCard.centerXAnchor.constraint(equalTo: emptyPlaceholder.centerXAnchor),
            dropCard.centerYAnchor.constraint(equalTo: emptyPlaceholder.centerYAnchor),
            dropCard.widthAnchor.constraint(equalToConstant: 320),
            dropCard.heightAnchor.constraint(equalToConstant: 215),

            stack.centerXAnchor.constraint(equalTo: dropCard.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: dropCard.centerYAnchor)
        ])

        updateBannerPosition(isRightAligned: side == .translated)
    }

    func updateBannerPosition(isRightAligned: Bool) {
        bannerHorizontalConstraint?.isActive = false
        if isRightAligned {
            bannerHorizontalConstraint = backJumpBanner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        } else {
            bannerHorizontalConstraint = backJumpBanner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        }
        bannerHorizontalConstraint?.isActive = true
    }

    @objc private func backJumpButtonClicked() {
        onBackJumpClicked?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if extractPDFURL(from: sender) != nil {
            dropCard.isEmphasizedCard = true
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropCard.isEmphasizedCard = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropCard.isEmphasizedCard = false
        if let url = extractPDFURL(from: sender) {
            onFileDropped?(url)
            return true
        }
        return false
    }

    private func extractPDFURL(from sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return nil }
        return urls.first(where: { $0.pathExtension.lowercased() == "pdf" })
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        emptyPlaceholder.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    func updateEmptyState(hasDocument: Bool) {
        let paper = currentPaperProvider?()
        applyContentSource(contentSource, paper: paper, hasPDFDocument: hasDocument)
    }

    func applyContentSource(_ source: ColumnContentSource, paper: PaperItem?, hasPDFDocument: Bool) {
        self.contentSource = source
        cornerBadge.isHidden = false
        emptyPlaceholder.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        switch source {
        case .pdf(let pdfId):
            pdfView.activePDFDocumentId = pdfId
            noteColumnView.isHidden = true
            pdfView.isHidden = !hasPDFDocument
            emptyPlaceholder.isHidden = hasPDFDocument
            let title = paper?.pdfTitle(for: pdfId) ?? (side == .original ? "原文 EN" : "译文 ZH")
            cornerButton.title = "\(title) ▾"
            cornerButton.toolTip = "点击切换此栏显示的论文集 PDF 或论文笔记"
            emptyTitleLabel.stringValue = "尚未绑定 \(title)"
            emptyBindButton.title = "选择 \(title) 文件…"

        case .note(let noteId):
            pdfView.isHidden = true
            emptyPlaceholder.isHidden = true
            backJumpBanner.isHidden = true
            noteColumnView.isHidden = false
            let notes = paper?.effectiveNoteDocuments ?? []
            let activeNote = notes.first(where: { $0.id == noteId }) ?? notes.first
            if let activeNote = activeNote {
                noteColumnView.loadNote(activeNote, allNotes: notes)
                cornerButton.title = "📝 \(activeNote.title) ▾"
            } else {
                cornerButton.title = "📝 精读笔记 ▾"
            }
            cornerButton.toolTip = "点击切换此栏显示的论文笔记或本论文集 PDF"
        }
    }

    @objc private func bindBtnClicked() {
        onBindPDFRequested?(side)
    }

    @objc private func quickSwitchToNoteClicked() {
        let firstNoteId = currentPaperProvider?()?.effectiveNoteDocuments.first?.id ?? "main"
        onSelectColumnSource?(.note(id: firstNoteId))
    }

    @objc private func cornerBadgeClicked(_ sender: NSButton) {
        let menu = NSMenu()
        let paper = currentPaperProvider?()

        // 1. 本论文集内的 PDF 列表（严格限定在同一篇论文集内）
        let pdfHeader = NSMenuItem(title: "本论文集 PDF 文档", action: nil, keyEquivalent: "")
        pdfHeader.isEnabled = false
        menu.addItem(pdfHeader)

        let descriptors = paper?.allPDFDescriptors ?? [
            PaperPDFDescriptor(id: PDFSide.original.rawValue, title: "原文 EN", filename: nil, builtInSide: .original),
            PaperPDFDescriptor(id: PDFSide.translated.rawValue, title: "译文 ZH", filename: nil, builtInSide: .translated)
        ]
        for desc in descriptors {
            let statusSuffix = (desc.filename != nil) ? "" : " (待导入)"
            let item = NSMenuItem(title: "📄 \(desc.title)\(statusSuffix)", action: #selector(selectPDFMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = desc.id
            if case .pdf(let curId) = contentSource, curId == desc.id {
                item.state = .on
            }
            menu.addItem(item)
        }

        let addPDFItem = NSMenuItem(title: "＋ 添加新 PDF 到本论文集…", action: #selector(addExtraPDFMenuItemClicked), keyEquivalent: "")
        addPDFItem.target = self
        menu.addItem(addPDFItem)

        menu.addItem(.separator())

        // 2. 本论文的精读笔记列表
        let noteHeader = NSMenuItem(title: "本论文精读笔记 (支持可跳转引用)", action: nil, keyEquivalent: "")
        noteHeader.isEnabled = false
        menu.addItem(noteHeader)

        let notes = paper?.effectiveNoteDocuments ?? []
        for noteDoc in notes {
            let item = NSMenuItem(title: "📝 \(noteDoc.title)", action: #selector(selectNoteMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = noteDoc.id
            if case .note(let curNoteId) = contentSource, curNoteId == noteDoc.id {
                item.state = .on
            }
            menu.addItem(item)
        }

        let addNoteItem = NSMenuItem(title: "＋ 新建本论文笔记…", action: #selector(createNoteMenuItemClicked), keyEquivalent: "")
        addNoteItem.target = self
        menu.addItem(addNoteItem)

        // 3. 当前 PDF 文件管理操作
        if case .pdf(let curPDFId) = contentSource {
            menu.addItem(.separator())
            let replaceItem = NSMenuItem(title: "替换此栏 PDF 文件…", action: #selector(bindBtnClicked), keyEquivalent: "")
            replaceItem.target = self
            menu.addItem(replaceItem)

            let revealItem = NSMenuItem(title: "在 Finder 中显示此 PDF", action: #selector(revealClicked), keyEquivalent: "")
            revealItem.target = self
            menu.addItem(revealItem)

            if curPDFId != PDFSide.original.rawValue && curPDFId != PDFSide.translated.rawValue {
                let removeExtraItem = NSMenuItem(title: "从本论文集移除此附加 PDF", action: #selector(removeExtraPDFMenuItemClicked(_:)), keyEquivalent: "")
                removeExtraItem.target = self
                removeExtraItem.representedObject = curPDFId
                menu.addItem(removeExtraItem)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func selectPDFMenuItem(_ sender: NSMenuItem) {
        guard let pdfId = sender.representedObject as? String else { return }
        onSelectColumnSource?(.pdf(id: pdfId))
    }

    @objc private func selectNoteMenuItem(_ sender: NSMenuItem) {
        guard let noteId = sender.representedObject as? String else { return }
        onSelectColumnSource?(.note(id: noteId))
    }

    @objc private func addExtraPDFMenuItemClicked() {
        onAddAdditionalPDFRequested?()
    }

    @objc private func createNoteMenuItemClicked() {
        onCreateNoteRequested?()
    }

    @objc private func removeExtraPDFMenuItemClicked(_ sender: NSMenuItem) {
        guard let pdfId = sender.representedObject as? String else { return }
        onRemoveAdditionalPDFRequested?(pdfId)
    }

    @objc private func revealClicked() {
        onRevealPDFInFinder?(side)
    }

    func internalScrollView() -> NSScrollView? {
        if let cached = cachedScrollView, cached.isDescendant(of: pdfView) { return cached }
        func findSV(in v: NSView) -> NSScrollView? {
            if let sv = v as? NSScrollView { return sv }
            for sub in v.subviews {
                if let f = findSV(in: sub) { return f }
            }
            return nil
        }
        let found = findSV(in: pdfView)
        cachedScrollView = found
        return found
    }
}

