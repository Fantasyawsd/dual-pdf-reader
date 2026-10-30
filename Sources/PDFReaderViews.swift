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
    var onContextMenuTranslate: ((String) -> Void)?
    var onContextMenuHighlight: ((PDFSelection, HighlightColor) -> Void)?
    var onContextMenuAddNote: ((PDFSelection) -> Void)?
    var onContextMenuSwapColumns: (() -> Void)?
    var onContextMenuResetSync: (() -> Void)?

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

    // MARK: - Native macOS Context Menu
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "PDF Context Menu")

        if let sel = currentSelection,
           let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            let copyItem = NSMenuItem(title: "拷贝", action: #selector(copySelectedTextAction), keyEquivalent: "c")
            copyItem.target = self
            menu.addItem(copyItem)

            let transItem = NSMenuItem(title: "划词翻译", action: #selector(contextMenuTranslateAction), keyEquivalent: "t")
            transItem.target = self
            transItem.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
            menu.addItem(transItem)

            let highlightItem = NSMenuItem(title: "高亮标注", action: nil, keyEquivalent: "")
            highlightItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
            let highlightSubmenu = NSMenu(title: "高亮标注")
            for c in HighlightColor.allCases {
                let colorItem = NSMenuItem(title: c.displayName, action: #selector(contextMenuHighlightAction(_:)), keyEquivalent: "")
                colorItem.target = self
                colorItem.representedObject = c
                let swatchImg = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                    c.solidColor.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
                colorItem.image = swatchImg
                highlightSubmenu.addItem(colorItem)
            }
            highlightItem.submenu = highlightSubmenu
            menu.addItem(highlightItem)

            let noteItem = NSMenuItem(title: "引用至笔记", action: #selector(contextMenuNoteAction), keyEquivalent: "n")
            noteItem.target = self
            noteItem.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
            menu.addItem(noteItem)

            let scholarItem = NSMenuItem(title: "在 Google 学术中搜索", action: #selector(contextMenuScholarAction), keyEquivalent: "")
            scholarItem.target = self
            scholarItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            menu.addItem(scholarItem)

            menu.addItem(NSMenuItem.separator())
        }

        let prevItem = NSMenuItem(title: "上一页", action: #selector(contextMenuPrevPageAction), keyEquivalent: "")
        prevItem.target = self
        prevItem.isEnabled = canGoToPreviousPage
        menu.addItem(prevItem)

        let nextItem = NSMenuItem(title: "下一页", action: #selector(contextMenuNextPageAction), keyEquivalent: "")
        nextItem.target = self
        nextItem.isEnabled = canGoToNextPage
        menu.addItem(nextItem)

        menu.addItem(NSMenuItem.separator())

        let autoZoomItem = NSMenuItem(title: "自适应页面", action: #selector(contextMenuFitPageAction), keyEquivalent: "")
        autoZoomItem.target = self
        menu.addItem(autoZoomItem)

        let actualSizeItem = NSMenuItem(title: "实际大小 (100%)", action: #selector(contextMenuActualSizeAction), keyEquivalent: "")
        actualSizeItem.target = self
        menu.addItem(actualSizeItem)

        let zoomInItem = NSMenuItem(title: "放大", action: #selector(contextMenuZoomInAction), keyEquivalent: "=")
        zoomInItem.target = self
        menu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "缩小", action: #selector(contextMenuZoomOutAction), keyEquivalent: "-")
        zoomOutItem.target = self
        menu.addItem(zoomOutItem)

        menu.addItem(NSMenuItem.separator())

        let swapItem = NSMenuItem(title: "左右栏互换", action: #selector(contextMenuSwapAction), keyEquivalent: "")
        swapItem.target = self
        swapItem.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)
        menu.addItem(swapItem)

        let resetSyncItem = NSMenuItem(title: "重置对齐", action: #selector(contextMenuResetSyncAction), keyEquivalent: "")
        resetSyncItem.target = self
        resetSyncItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(resetSyncItem)

        return menu
    }

    @objc private func copySelectedTextAction() {
        copy(self)
    }

    @objc private func contextMenuTranslateAction() {
        guard let sel = currentSelection,
              let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        onContextMenuTranslate?(text)
    }

    @objc private func contextMenuHighlightAction(_ sender: NSMenuItem) {
        guard let sel = currentSelection,
              let color = sender.representedObject as? HighlightColor else { return }
        onContextMenuHighlight?(sel, color)
    }

    @objc private func contextMenuNoteAction() {
        guard let sel = currentSelection else { return }
        onContextMenuAddNote?(sel)
    }

    @objc private func contextMenuScholarAction() {
        guard let sel = currentSelection,
              let text = sel.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://scholar.google.com/scholar?q=\(encoded)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func contextMenuPrevPageAction() {
        goToPreviousPage(nil)
    }

    @objc private func contextMenuNextPageAction() {
        goToNextPage(nil)
    }

    @objc private func contextMenuFitPageAction() {
        autoScales = true
    }

    @objc private func contextMenuActualSizeAction() {
        autoScales = false
        scaleFactor = 1.0
    }

    @objc private func contextMenuZoomInAction() {
        zoomIn(nil)
    }

    @objc private func contextMenuZoomOutAction() {
        zoomOut(nil)
    }

    @objc private func contextMenuSwapAction() {
        onContextMenuSwapColumns?()
    }

    @objc private func contextMenuResetSyncAction() {
        onContextMenuResetSync?()
    }
}

// MARK: - Single Column Wrapper (Supports Any PDF in the Current Paper Collection)
final class CleanPDFColumnView: NSView {
    let side: PDFSide
    var contentSource: ColumnContentSource
    var activePDFDocumentId: String {
        contentSource.pdfId ?? side.rawValue
    }

    let pdfView = InteractivePDFView()
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

        // 左上角极简半透明栏标识胶囊（点击可切换此栏显示的论文集 PDF）
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
        cornerButton.toolTip = "点击切换此栏 PDF"
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

        let stack = NSStackView(views: [iconView, emptyTitleLabel, subLbl, emptyBindButton])
        stack.orientation = .vertical
        stack.spacing = 9
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        dropCard.addSubview(stack)
        emptyPlaceholder.addSubview(dropCard)

        addSubview(emptyPlaceholder)

        // 确保左上角切换胶囊与返回胶囊始终位于最上层
        addSubview(cornerBadge)
        addSubview(backJumpBanner)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),

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
            pdfView.isHidden = !hasPDFDocument
            emptyPlaceholder.isHidden = hasPDFDocument
            let title = paper?.pdfTitle(for: pdfId) ?? (side == .original ? "原文 EN" : "译文 ZH")
            cornerButton.title = "\(title) ▾"
            cornerButton.toolTip = "点击切换此栏显示的论文集 PDF"
            emptyTitleLabel.stringValue = "尚未绑定 \(title)"
            emptyBindButton.title = "选择 \(title) 文件…"

        }
    }

    @objc private func bindBtnClicked() {
        onBindPDFRequested?(side)
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

    @objc private func addExtraPDFMenuItemClicked() {
        onAddAdditionalPDFRequested?()
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

