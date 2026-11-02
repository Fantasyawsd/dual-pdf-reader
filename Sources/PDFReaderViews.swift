import Cocoa
import PDFKit
import WebKit
import UniformTypeIdentifiers
import QuartzCore

// MARK: - Modern macOS Native Hover Button
class ModernHoverButton: NSButton {
    var hoverBgColor: NSColor = NSColor.textColor.withAlphaComponent(0.08)
    var normalBgColor: NSColor = .clear
    var activeBgColor: NSColor = NSColor.controlAccentColor.withAlphaComponent(0.14)
    var hoverTintColor: NSColor?
    var normalTintColor: NSColor? = .secondaryLabelColor
    var activeTintColor: NSColor = .controlAccentColor
    var cornerRadius: CGFloat = 6.0
    var isPill: Bool = false
    var showsPointingHand: Bool = true
    var isToggleButton: Bool = false

    var isSelectedTab: Bool = false {
        didSet { updateColors() }
    }

    override var state: NSControl.StateValue {
        didSet { updateColors() }
    }

    private(set) var isHovered: Bool = false
    private var hoverTrackingArea: NSTrackingArea?

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    convenience init(
        title: String = "",
        image: NSImage? = nil,
        target: AnyObject? = nil,
        action: Selector? = nil,
        cornerRadius: CGFloat = 6.0,
        isPill: Bool = false
    ) {
        self.init(frame: .zero)
        self.title = title
        self.image = image
        self.target = target
        self.action = action
        self.cornerRadius = cornerRadius
        self.isPill = isPill
        setup()
    }

    private func setup() {
        wantsLayer = true
        isBordered = false
        bezelStyle = .inline
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        updateColors()
    }

    override func updateLayer() {
        super.updateLayer()
        updateColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard isEnabled else { return }
        isHovered = true
        updateColors()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateColors()
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if showsPointingHand && isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    func setHoveredForTest(_ h: Bool) {
        isHovered = h
        updateColors()
    }

    func updateColors() {
        guard wantsLayer else { return }
        layer?.cornerRadius = isPill ? bounds.height / 2.0 : cornerRadius

        let isActive = isSelectedTab || (isToggleButton && state == .on)
        if isActive {
            layer?.backgroundColor = activeBgColor.cgColor
            contentTintColor = activeTintColor
        } else if isHovered && isEnabled {
            layer?.backgroundColor = hoverBgColor.cgColor
            contentTintColor = hoverTintColor ?? (contentTintColor == .secondaryLabelColor ? .labelColor : contentTintColor)
        } else {
            layer?.backgroundColor = normalBgColor.cgColor
            if let nTint = normalTintColor {
                contentTintColor = nTint
            }
        }
    }
}

final class ToolbarCapsuleView: NSView {
    private let stackView = NSStackView()

    override var wantsUpdateLayer: Bool { true }

    init(views: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        stackView.orientation = .horizontal
        stackView.spacing = 0
        stackView.alignment = .centerY
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        views.forEach { stackView.addArrangedSubview($0) }
        addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
        }
    }
}

// MARK: - Custom Native Circular Color Swatch Button (Replaces Emoji Circles)
final class HighlightSwatchButton: NSButton {
    let highlightColor: HighlightColor
    var isSelectedSwatch: Bool = false {
        didSet { needsDisplay = true }
    }
    private var isHovered: Bool = false {
        didSet { needsDisplay = true }
    }
    private var hoverTrackingArea: NSTrackingArea?

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

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
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
    var onInteraction: (() -> Void)?
    var onMagnificationWillChange: (() -> Void)?
    var onMagnificationDidChange: (() -> Void)?
    var onPageStep: ((Int) -> Void)?
    var onZoomCommand: ((Bool, CGFloat?) -> Void)?
    var onCommandScrollZoom: ((CGFloat) -> Void)?
    var onMarkupStateChanged: (() -> Void)?
    var markupTool: PDFMarkupTool = .pointer {
        didSet {
            textMarkupPopover?.close()
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    var markupColor: NSColor = NSColor.systemYellow
    var side: PDFSide = .original
    var activePDFDocumentId: String = PDFSide.original.rawValue
    var onTextSelectedForPopover: ((PDFSelection, NSRect) -> Void)?
    var onAnnotationClicked: ((PaperAnnotation, NSPoint) -> Void)?
    var onBeforeInternalLinkJump: ((PDFPage, NSPoint, Bool) -> Bool)?
    var onFileDropped: ((URL) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onOptionScrollPerformed: (() -> Void)?
    var onContextMenuTranslate: ((String) -> Void)?
    var onContextMenuHighlight: ((PDFSelection, HighlightColor) -> Void)?
    var onContextMenuAddNote: ((PDFSelection) -> Void)?
    var onContextMenuSwapColumns: (() -> Void)?
    var onContextMenuResetSync: (() -> Void)?

    var storedAnnotations: [PaperAnnotation] = []

    // Column-local markup undo history. Each PDF view owns its own stack so
    // undo/redo in one pane never touches the other pane.
    private struct MarkupEdit {
        let page: PDFPage
        let annotation: PDFAnnotation
        let isAddition: Bool
    }
    private var markupUndoStack: [MarkupEdit] = []
    private var markupRedoStack: [MarkupEdit] = []
    private var gestureStartPagePoint: NSPoint?
    private var gesturePage: PDFPage?
    private var gestureAnnotation: PDFAnnotation?
    private var gestureInkPath: NSBezierPath?
    private var erasedAnnotationIDs: Set<ObjectIdentifier> = []
    private var handDragStart: NSPoint?
    private var handDragOrigin: NSPoint?
    private var textMarkupPopover: NSPopover?
    private var textMarkupDraftPage: PDFPage?
    private var textMarkupDraftPoint: NSPoint?

    var canUndoMarkup: Bool { !markupUndoStack.isEmpty }
    var canRedoMarkup: Bool { !markupRedoStack.isEmpty }
    var markupUndoCount: Int { markupUndoStack.count }
    var markupRedoCount: Int { markupRedoStack.count }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func scrollWheel(with event: NSEvent) {
        onInteraction?()
        if event.modifierFlags.contains(.command) {
            // Command + wheel is reserved exclusively for this column's zoom.
            // Never forward it to PDFKit, otherwise the page would also scroll.
            let step = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * 0.012
                : event.scrollingDeltaY * 0.08
            guard step.isFinite, abs(step) > 0.0001 else { return }
            let proposed = scaleFactor * CGFloat(exp(step))
            let clamped = min(5.0, max(0.25, proposed))
            if abs(clamped - scaleFactor) > 0.0001 {
                onCommandScrollZoom?(clamped)
            }
            return
        }
        let isOptionHeld = event.modifierFlags.contains(.option)
        super.scrollWheel(with: event)
        if isOptionHeld {
            onOptionScrollPerformed?()
        }
    }

    override func magnify(with event: NSEvent) {
        onInteraction?()
        onMagnificationWillChange?()
        super.magnify(with: event)
        // Trackpad pinch uses the same per-column 0.25x...5.0x ceiling.
        let clamped = min(5.0, max(0.25, scaleFactor))
        if abs(clamped - scaleFactor) > 0.0001 {
            scaleFactor = clamped
        }
        onMagnificationDidChange?()
    }

    override func keyDown(with event: NSEvent) {
        onInteraction?()
        if event.modifierFlags.contains(.command),
           let characters = event.charactersIgnoringModifiers?.lowercased(), characters == "z" {
            if event.modifierFlags.contains(.shift) { redoMarkup() } else { undoMarkup() }
            return
        }
        super.keyDown(with: event)
    }

    @objc func undo(_ sender: Any?) {
        undoMarkup()
    }

    @objc func redo(_ sender: Any?) {
        redoMarkup()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        switch markupTool {
        case .hand:
            addCursorRect(bounds, cursor: .openHand)
        case .pointer:
            break
        default:
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        if markupTool == .hand {
            beginHandPan(with: event)
            return
        }
        if markupTool.usesDrawingGesture {
            beginMarkupGesture(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let page = page(for: viewPoint, nearest: false),
           let doc = document {
            let pagePoint = convert(viewPoint, to: page)

            // 1. 检测是否点击了 PDF 原生内部跳转链接 (References / TOC / Figure Links) 或外部链接 (URL)
            if let hitAnnot = page.annotation(at: pagePoint),
               (hitAnnot.type == "Link" || hitAnnot.type == "/Link") {
                let zeroBorder = PDFBorder()
                zeroBorder.lineWidth = 0
                hitAnnot.border = zeroBorder
                hitAnnot.color = .clear
                hitAnnot.setValue("/N", forAnnotationKey: PDFAnnotationKey(rawValue: "H"))

                var targetDest: PDFDestination?
                if let goTo = hitAnnot.action as? PDFActionGoTo {
                    targetDest = goTo.destination
                } else if let dest = hitAnnot.destination {
                    targetDest = dest
                }
                if let dest = targetDest {
                    let isCmdPressed = event.modifierFlags.contains(.command)
                    let handled = (dest.page != nil) ? (onBeforeInternalLinkJump?(dest.page!, dest.point, isCmdPressed) ?? false) : false
                    if !handled {
                        self.go(to: dest)
                    }
                    return
                }
                if let actionURL = (hitAnnot.action as? PDFActionURL)?.url ?? hitAnnot.url {
                    NSWorkspace.shared.open(actionURL)
                    return
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

    override func mouseDragged(with event: NSEvent) {
        if markupTool == .hand, handDragStart != nil {
            updateHandPan(with: event)
            return
        }
        if markupTool.usesDrawingGesture, gestureStartPagePoint != nil {
            updateMarkupGesture(with: event)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if markupTool == .hand, handDragStart != nil {
            endHandPan()
            return
        }
        if markupTool.usesDrawingGesture, gestureStartPagePoint != nil {
            finishMarkupGesture(with: event)
            return
        }
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
        let pdfs = extractPDFURLs(from: sender)
        guard !pdfs.isEmpty else { return super.performDragOperation(sender) }
        if let onFilesDropped {
            onFilesDropped(pdfs)
        } else {
            onFileDropped?(pdfs[0])
        }
        return true
    }

    private func extractPDFURL(from sender: NSDraggingInfo) -> URL? {
        extractPDFURLs(from: sender).first
    }

    private func extractPDFURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "pdf" }
    }

    // MARK: - Native macOS Context Menu
    override func menu(for event: NSEvent) -> NSMenu? {
        onInteraction?()
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
        if let action = onPageStep { action(-1) } else { goToPreviousPage(nil) }
    }

    @objc private func contextMenuNextPageAction() {
        if let action = onPageStep { action(1) } else { goToNextPage(nil) }
    }

    @objc private func contextMenuFitPageAction() {
        if let action = onZoomCommand { action(true, nil) } else { autoScales = true }
    }

    @objc private func contextMenuActualSizeAction() {
        if let action = onZoomCommand { action(false, 1) }
        else { autoScales = false; scaleFactor = 1 }
    }

    @objc private func contextMenuZoomInAction() {
        if let action = onZoomCommand { action(false, scaleFactor * 1.15) } else { zoomIn(nil) }
    }

    @objc private func contextMenuZoomOutAction() {
        if let action = onZoomCommand { action(false, scaleFactor / 1.15) } else { zoomOut(nil) }
    }

    @objc private func contextMenuSwapAction() {
        onContextMenuSwapColumns?()
    }

    @objc private func contextMenuResetSyncAction() {
        onContextMenuResetSync?()
    }
}


// MARK: - Hand tool, markup gestures, and per-column undo history
extension InteractivePDFView {
    private static let markupUserName = "DualPDF_Markup"

    // MARK: Hand tool

    func beginHandPan(with event: NSEvent) {
        handDragStart = convert(event.locationInWindow, from: nil)
        handDragOrigin = internalScrollView()?.contentView.bounds.origin
        NSCursor.closedHand.set()
    }

    func updateHandPan(with event: NSEvent) {
        guard let start = handDragStart, var origin = handDragOrigin,
              let scroll = internalScrollView() else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = NSPoint(x: point.x - start.x, y: point.y - start.y)
        origin.x -= delta.x
        origin.y -= delta.y
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func endHandPan() {
        handDragStart = nil
        handDragOrigin = nil
        NSCursor.openHand.set()
        window?.invalidateCursorRects(for: self)
    }

    private func internalScrollView() -> NSScrollView? {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews {
                if let scroll = find(child) { return scroll }
            }
            return nil
        }
        return find(self)
    }

    // MARK: Markup gestures

    func beginMarkupGesture(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return }
        let start = convert(viewPoint, to: page)
        gestureStartPagePoint = start
        gesturePage = page
        gestureAnnotation = nil
        gestureInkPath = nil
        erasedAnnotationIDs.removeAll()
        window?.makeFirstResponder(self)

        switch markupTool {
        case .pointer, .hand:
            break
        case .highlight, .underline, .strikethrough:
            let selection = page.selection(from: start, to: start)
            setCurrentSelection(selection, animate: false)
        case .eraser:
            eraseMarkup(at: start, on: page)
        case .text:
            break
        case .ink:
            let path = NSBezierPath()
            path.move(to: start)
            gestureInkPath = path
            let annotation = PDFAnnotation(bounds: page.bounds(for: displayBox), forType: .ink, withProperties: nil)
            annotation.color = markupColor
            annotation.userName = Self.markupUserName
            let border = PDFBorder()
            border.lineWidth = 2.0
            annotation.border = border
            annotation.add(path)
            page.addAnnotation(annotation)
            gestureAnnotation = annotation
        case .rectangle, .ellipse, .line, .arrow:
            let annotation = makeShapeAnnotation(tool: markupTool, start: start, end: start, on: page)
            if let annotation {
                page.addAnnotation(annotation)
                gestureAnnotation = annotation
            }
        }
    }

    func updateMarkupGesture(with event: NSEvent) {
        guard let start = gestureStartPagePoint, let page = gesturePage else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let current = convert(viewPoint, to: page)

        switch markupTool {
        case .highlight, .underline, .strikethrough:
            let selection = page.selection(from: start, to: current)
            setCurrentSelection(selection, animate: false)
        case .eraser:
            eraseMarkup(at: current, on: page)
        case .ink:
            guard let path = gestureInkPath else { return }
            path.line(to: current)
            if let annotation = gestureAnnotation {
                annotation.remove(path)
                annotation.add(path)
            }
            needsDisplay = true
        case .rectangle, .ellipse, .line, .arrow:
            guard let annotation = gestureAnnotation else { return }
            applyShapeGeometry(annotation, tool: markupTool, start: start, end: current)
            needsDisplay = true
        case .pointer, .hand, .text:
            break
        }
    }

    func finishMarkupGesture(with event: NSEvent) {
        defer {
            gestureStartPagePoint = nil
            gesturePage = nil
            gestureAnnotation = nil
            gestureInkPath = nil
            erasedAnnotationIDs.removeAll()
            needsDisplay = true
        }
        guard let start = gestureStartPagePoint, let page = gesturePage else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let current = convert(viewPoint, to: page)

        switch markupTool {
        case .highlight, .underline, .strikethrough:
            defer { setCurrentSelection(nil, animate: false) }
            guard let selection = page.selection(from: start, to: current),
                  let annotation = makeTextMarkupAnnotation(tool: markupTool, selection: selection, on: page) else { return }
            page.addAnnotation(annotation)
            recordMarkupEdit(MarkupEdit(page: page, annotation: annotation, isAddition: true))
        case .eraser:
            break
        case .ink:
            guard let annotation = gestureAnnotation, let path = gestureInkPath else { return }
            if path.bounds.width < 1.0 && path.bounds.height < 1.0 {
                page.removeAnnotation(annotation)
            } else {
                // Keep the page-sized bounds: PDFKit resolves ink paths in
                // annotation space, so shrinking bounds moves and clips the
                // stroke instead of merely tightening its hit area.
                annotation.remove(path)
                annotation.add(path)
                recordMarkupEdit(MarkupEdit(page: page, annotation: annotation, isAddition: true))
            }
        case .text:
            presentTextMarkupEditor(on: page, at: start)
        case .rectangle, .ellipse, .line, .arrow:
            guard let annotation = gestureAnnotation else { return }
            applyShapeGeometry(annotation, tool: markupTool, start: start, end: current)
            let distance = sqrt(pow(current.x - start.x, 2) + pow(current.y - start.y, 2))
            if distance < 2 {
                page.removeAnnotation(annotation)
            } else {
                recordMarkupEdit(MarkupEdit(page: page, annotation: annotation, isAddition: true))
            }
        case .pointer, .hand:
            break
        }
    }

    private func makeTextMarkupAnnotation(tool: PDFMarkupTool, selection: PDFSelection, on page: PDFPage) -> PDFAnnotation? {
        let lines = selection.selectionsByLine().filter { $0.pages.contains(page) }
        let rects = lines.map { $0.bounds(for: page) }.filter { $0.width > 1 || $0.height > 1 }
        guard let first = rects.first, let subtype = tool.annotationSubtype else { return nil }
        var union = first
        for rect in rects.dropFirst() { union = union.union(rect) }
        let annotation = PDFAnnotation(bounds: union, forType: subtype, withProperties: nil)
        var quadPoints: [NSValue] = []
        // PDFKit expects quadrilateral points in annotation space (relative to
        // the annotation bounds origin), not page space.
        for rect in rects {
            let local = NSRect(x: rect.minX - union.minX, y: rect.minY - union.minY, width: rect.width, height: rect.height)
            quadPoints.append(NSValue(point: NSPoint(x: local.minX, y: local.maxY)))
            quadPoints.append(NSValue(point: NSPoint(x: local.maxX, y: local.maxY)))
            quadPoints.append(NSValue(point: NSPoint(x: local.minX, y: local.minY)))
            quadPoints.append(NSValue(point: NSPoint(x: local.maxX, y: local.minY)))
        }
        annotation.quadrilateralPoints = quadPoints
        annotation.color = markupColor.withAlphaComponent(tool.colorAlpha)
        annotation.userName = Self.markupUserName
        return annotation
    }

    private func makeShapeAnnotation(tool: PDFMarkupTool, start: NSPoint, end: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        guard let subtype = tool.annotationSubtype else { return nil }
        let annotation = PDFAnnotation(bounds: shapeBounds(start: start, end: end, tool: tool),
                                       forType: subtype, withProperties: nil)
        annotation.color = markupColor
        let border = PDFBorder()
        border.lineWidth = 1.6
        annotation.border = border
        annotation.userName = Self.markupUserName
        if tool == .rectangle || tool == .ellipse {
            annotation.interiorColor = markupColor.withAlphaComponent(0.06)
        }
        applyShapeGeometry(annotation, tool: tool, start: start, end: end)
        return annotation
    }

    private func shapeBounds(start: NSPoint, end: NSPoint, tool: PDFMarkupTool) -> NSRect {
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        if tool == .line || tool == .arrow {
            return rect.insetBy(dx: -2, dy: -2)
        }
        return rect
    }

    private func applyShapeGeometry(_ annotation: PDFAnnotation, tool: PDFMarkupTool, start: NSPoint, end: NSPoint) {
        let bounds = shapeBounds(start: start, end: end, tool: tool)
        annotation.bounds = bounds
        if tool == .line || tool == .arrow {
            annotation.startPoint = NSPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
            annotation.endPoint = NSPoint(x: end.x - bounds.minX, y: end.y - bounds.minY)
            annotation.startLineStyle = .none
            annotation.endLineStyle = tool == .arrow ? .closedArrow : .none
        }
    }

    // MARK: Text annotation editor

    private func presentTextMarkupEditor(on page: PDFPage, at point: NSPoint) {
        textMarkupPopover?.close()
        textMarkupDraftPage = page
        textMarkupDraftPoint = point
        let controller = TextMarkupPopoverController()
        controller.onCommit = { [weak self] text in self?.commitTextMarkup(text) }
        controller.onCancel = { [weak self] in self?.dismissTextMarkupEditor() }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        let anchor = convert(NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2), from: page)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        textMarkupPopover = popover
    }

    private func commitTextMarkup(_ text: String) {
        guard let page = textMarkupDraftPage, let point = textMarkupDraftPoint else { return }
        let annotation = makeTextAnnotation(text: text, page: page, point: point)
        page.addAnnotation(annotation)
        recordMarkupEdit(MarkupEdit(page: page, annotation: annotation, isAddition: true))
        dismissTextMarkupEditor()
    }

    private func dismissTextMarkupEditor() {
        textMarkupPopover?.close()
        textMarkupPopover = nil
        textMarkupDraftPage = nil
        textMarkupDraftPoint = nil
    }

    private func makeTextAnnotation(text: String, page: PDFPage, point: NSPoint) -> PDFAnnotation {
        let pageBounds = page.bounds(for: displayBox)
        let width: CGFloat = 180
        let height: CGFloat = 34
        let maxX = max(pageBounds.minX + 4, pageBounds.maxX - width - 4)
        let maxY = max(pageBounds.minY + 4, pageBounds.maxY - height - 4)
        let x = min(max(point.x, pageBounds.minX + 4), maxX)
        let y = min(max(point.y - height / 2, pageBounds.minY + 4), maxY)
        let rect = NSRect(x: x, y: y, width: width, height: height)
        let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = .systemFont(ofSize: 12)
        annotation.fontColor = markupColor
        annotation.color = .clear
        annotation.alignment = .left
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.userName = Self.markupUserName
        return annotation
    }

    func addTextMarkupForTesting(text: String, page: PDFPage, at point: NSPoint) {
        let annotation = makeTextAnnotation(text: text, page: page, point: point)
        page.addAnnotation(annotation)
        recordMarkupEdit(MarkupEdit(page: page, annotation: annotation, isAddition: true))
    }

    func dismissTextMarkupPopover() {
        dismissTextMarkupEditor()
    }

    private func eraseMarkup(at point: NSPoint, on page: PDFPage) {
        let hits = page.annotations.filter { annotation in
            guard annotation.userName == Self.markupUserName else { return false }
            if annotation.type == "Ink" || annotation.type == "/Ink" {
                if let paths = annotation.paths, !paths.isEmpty {
                    return paths.contains { path in
                        path.bounds.insetBy(dx: -6, dy: -6).contains(point)
                    }
                }
            }
            return annotation.bounds.insetBy(dx: -3, dy: -3).contains(point)
        }
        for annotation in hits {
            let id = ObjectIdentifier(annotation)
            guard !erasedAnnotationIDs.contains(id) else { continue }
            erasedAnnotationIDs.insert(id)
            page.removeAnnotation(annotation)
            recordMarkupEdit(MarkupEdit(page: page, annotation: annotation, isAddition: false), updateState: false)
        }
        if !hits.isEmpty { onMarkupStateChanged?() }
        needsDisplay = true
    }

    // MARK: Undo / redo

    func undoMarkup() {
        guard let edit = markupUndoStack.popLast() else { return }
        if edit.isAddition {
            edit.page.removeAnnotation(edit.annotation)
        } else {
            edit.page.addAnnotation(edit.annotation)
        }
        markupRedoStack.append(edit)
        needsDisplay = true
        onMarkupStateChanged?()
    }

    func redoMarkup() {
        guard let edit = markupRedoStack.popLast() else { return }
        if edit.isAddition {
            edit.page.addAnnotation(edit.annotation)
        } else {
            edit.page.removeAnnotation(edit.annotation)
        }
        markupUndoStack.append(edit)
        needsDisplay = true
        onMarkupStateChanged?()
    }

    func resetMarkupHistory() {
        markupUndoStack.removeAll()
        markupRedoStack.removeAll()
        gestureStartPagePoint = nil
        gesturePage = nil
        gestureAnnotation = nil
        gestureInkPath = nil
        onMarkupStateChanged?()
    }

    private func recordMarkupEdit(_ edit: MarkupEdit, updateState: Bool = true) {
        markupUndoStack.append(edit)
        markupRedoStack.removeAll()
        if updateState { onMarkupStateChanged?() }
    }
}


// MARK: - Text annotation editor

final class TextMarkupPopoverController: NSViewController, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private let textField = NSTextField()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 96))
        let title = NSTextField(labelWithString: "添加文本批注")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        textField.placeholderString = "输入文本内容"
        textField.font = .systemFont(ofSize: 13)
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: "添加", target: self, action: #selector(commitAction))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelAction))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let buttons = NSStackView(views: [cancelButton, addButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(title)
        container.addSubview(textField)
        container.addSubview(buttons)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            textField.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            buttons.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 10),
            buttons.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14)
        ])
        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textField)
    }

    @objc private func commitAction() {
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onCommit?(text.isEmpty ? "文本" : text)
    }

    @objc private func cancelAction() {
        onCancel?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitAction()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelAction()
            return true
        }
        return false
    }
}

extension InteractivePDFView: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        textMarkupPopover = nil
        textMarkupDraftPage = nil
        textMarkupDraftPoint = nil
    }
}

extension InteractivePDFView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return canUndoMarkup }
        if item.action == #selector(redo(_:)) { return canRedoMarkup }
        return true
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
    let viewportLayout = PDFViewportLayout()
    private let emptyPlaceholder = NSView()
    private let dropCard = ModernSurfaceCardView()
    private let cornerBadge = NSVisualEffectView()
    let cornerButton = NSButton()
    private let emptyTitleLabel = NSTextField(labelWithString: "")
    private let emptyBindButton = NSButton()

    // 浮动“返回”胶囊按钮（跳转时显示，左栏发起的在左侧，右栏发起的在右侧，仅直接显示“返回”）
    let backJumpBanner = NSVisualEffectView()
    let backJumpButton = ModernHoverButton()
    var onBackJumpClicked: (() -> Void)?
    private var bannerHorizontalConstraint: NSLayoutConstraint?

    let columnToolbar = ColumnToolbarView()
    let pageCapsule = ColumnPageCapsuleView()
    var onPageCapsuleCommit: ((Int) -> Void)?
    var onPageCapsuleStep: ((Int) -> Void)?
    var onToolbarLayoutChanged: (() -> Void)?
    private var capsuleHideTicket = 0
    private var capsuleHotspotTrackingArea: NSTrackingArea?

    var currentPaperProvider: (() -> PaperItem?)?
    var onSelectColumnSource: ((ColumnContentSource) -> Void)?
    var onAddAdditionalPDFRequested: (() -> Void)?
    var onRemoveAdditionalPDFRequested: ((String) -> Void)?

    var onBindPDFRequested: ((PDFSide) -> Void)?
    var onRevealPDFInFinder: ((PDFSide) -> Void)?
    var onFileDropped: ((URL) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
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
        pdfView.autoScales = false
        pdfView.minScaleFactor = 0.001
        pdfView.maxScaleFactor = 64
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

        // 每栏独立工具栏：一级主工具条常驻，二级工具条随“批注/形状”模式展开。
        columnToolbar.translatesAutoresizingMaskIntoConstraints = false
        columnToolbar.onLayoutChanged = { [weak self] in self?.onToolbarLayoutChanged?() }
        pdfView.onMarkupStateChanged = { [weak self] in
            guard let self else { return }
            self.columnToolbar.setUndoRedoEnabled(canUndo: self.pdfView.canUndoMarkup,
                                                  canRedo: self.pdfView.canRedoMarkup)
        }
        addSubview(columnToolbar)

        // 底部浮动页码胶囊
        pageCapsule.previousButton.target = self
        pageCapsule.previousButton.action = #selector(capsulePreviousAction)
        pageCapsule.nextButton.target = self
        pageCapsule.nextButton.action = #selector(capsuleNextAction)
        pageCapsule.onCommit = { [weak self] page in self?.onPageCapsuleCommit?(page) }
        pageCapsule.onHoverChanged = { [weak self] hovering in self?.capsuleHoverChanged(hovering) }
        addSubview(pageCapsule)

        columnToolbar.setViewMode(pdfView.displayMode)
        columnToolbar.setUndoRedoEnabled(canUndo: false, canRedo: false)

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
            columnToolbar.topAnchor.constraint(equalTo: topAnchor),
            columnToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            columnToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),

            pdfView.topAnchor.constraint(equalTo: columnToolbar.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cornerBadge.topAnchor.constraint(equalTo: columnToolbar.bottomAnchor, constant: 8),
            cornerBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            cornerButton.topAnchor.constraint(equalTo: cornerBadge.topAnchor, constant: 3),
            cornerButton.bottomAnchor.constraint(equalTo: cornerBadge.bottomAnchor, constant: -3),
            cornerButton.leadingAnchor.constraint(equalTo: cornerBadge.leadingAnchor, constant: 8),
            cornerButton.trailingAnchor.constraint(equalTo: cornerBadge.trailingAnchor, constant: -8),

            backJumpButton.topAnchor.constraint(equalTo: backJumpBanner.topAnchor, constant: 5),
            backJumpButton.bottomAnchor.constraint(equalTo: backJumpBanner.bottomAnchor, constant: -5),
            backJumpButton.leadingAnchor.constraint(equalTo: backJumpBanner.leadingAnchor, constant: 14),
            backJumpButton.trailingAnchor.constraint(equalTo: backJumpBanner.trailingAnchor, constant: -14),
            backJumpBanner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -56),

            emptyPlaceholder.topAnchor.constraint(equalTo: columnToolbar.bottomAnchor),
            emptyPlaceholder.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyPlaceholder.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyPlaceholder.bottomAnchor.constraint(equalTo: bottomAnchor),

            pageCapsule.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageCapsule.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

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

    private lazy var columnDropOverlay: DropHoverOverlayView = {
        let v = DropHoverOverlayView(message: DocumentOpenCopy.dropOnColumnHint)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private func ensureColumnDropOverlay() {
        guard columnDropOverlay.superview == nil else { return }
        addSubview(columnDropOverlay)
        NSLayoutConstraint.activate([
            columnDropOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            columnDropOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            columnDropOverlay.topAnchor.constraint(equalTo: topAnchor),
            columnDropOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !extractPDFURLs(from: sender).isEmpty {
            dropCard.isEmphasizedCard = true
            ensureColumnDropOverlay()
            columnDropOverlay.isHidden = false
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropCard.isEmphasizedCard = false
        columnDropOverlay.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropCard.isEmphasizedCard = false
        columnDropOverlay.isHidden = true
        let pdfs = extractPDFURLs(from: sender)
        guard !pdfs.isEmpty else { return false }
        if let onFilesDropped {
            onFilesDropped(pdfs)
        } else {
            onFileDropped?(pdfs[0])
        }
        return true
    }

    private func extractPDFURL(from sender: NSDraggingInfo) -> URL? {
        extractPDFURLs(from: sender).first
    }

    private func extractPDFURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "pdf" || ((try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true) }
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let capsuleHotspotTrackingArea { removeTrackingArea(capsuleHotspotTrackingArea) }
        let height = min(64, max(0, bounds.height))
        let area = NSTrackingArea(rect: NSRect(x: 0, y: 0, width: bounds.width, height: height),
                                  options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        capsuleHotspotTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.y <= 64 { revealPageCapsule() }
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
        found?.contentView.postsBoundsChangedNotifications = true
        cachedScrollView = found
        return found
    }
}

extension CleanPDFColumnView {
    func toggleSpreadMode() {
        let current = pdfView.displayMode
        let continuous = current == .singlePageContinuous || current == .twoUpContinuous
        let twoUp = current == .twoUp || current == .twoUpContinuous
        let target: PDFDisplayMode
        if twoUp {
            target = continuous ? .singlePageContinuous : .singlePage
        } else {
            target = continuous ? .twoUpContinuous : .twoUp
        }
        applyDisplayModeToPDF(target)
    }

    func toggleContinuousMode() {
        switch pdfView.displayMode {
        case .singlePage: pdfView.displayMode = .singlePageContinuous
        case .singlePageContinuous: pdfView.displayMode = .singlePage
        case .twoUp: pdfView.displayMode = .twoUpContinuous
        case .twoUpContinuous: pdfView.displayMode = .twoUp
        default: pdfView.displayMode = .singlePageContinuous
        }
        columnToolbar.setViewMode(pdfView.displayMode)
        onToolbarLayoutChanged?()
    }

    private func applyDisplayModeToPDF(_ mode: PDFDisplayMode) {
        pdfView.displayMode = mode
        columnToolbar.setViewMode(mode)
        onToolbarLayoutChanged?()
    }

    func refreshPageCapsuleFromCurrentPage() {
        guard let document = pdfView.document, document.pageCount > 0 else {
            pageCapsule.update(page: 1, total: 1)
            return
        }
        let index = pdfView.currentPage.map { document.index(for: $0) } ?? 0
        pageCapsule.update(page: index + 1, total: document.pageCount)
    }

    func revealPageCapsule(hideAfter delay: TimeInterval = 2.0) {
        guard pdfView.document != nil, !isHidden else { return }
        // The reader updates both capsules from the precise continuous
        // position before calling this method; refreshing from currentPage
        // here would overwrite it with a value that can lag during scrolling.
        capsuleHideTicket += 1
        let ticket = capsuleHideTicket
        let alreadyVisible = !pageCapsule.isHidden && pageCapsule.alphaValue > 0.98
        pageCapsule.isHidden = false
        if alreadyVisible {
            pageCapsule.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.pageCapsule.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.capsuleHideTicket == ticket else { return }
            guard !self.pageCapsule.isHoveredForCapsule else { return }
            self.hidePageCapsuleAfterIdle()
        }
    }

    func expireHideForTesting() {
        capsuleHideTicket += 1
        guard !pageCapsule.isHoveredForCapsule else { return }
        pageCapsule.alphaValue = 0
        pageCapsule.isHidden = true
    }

    func capsuleHoverChanged(_ hovering: Bool) {
        pageCapsule.isHoveredForCapsule = hovering
        if hovering {
            capsuleHideTicket += 1
            pageCapsule.isHidden = false
            pageCapsule.alphaValue = 1
        } else {
            revealPageCapsule()
        }
    }

    private func hidePageCapsuleAfterIdle() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.pageCapsule.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.pageCapsule.isHoveredForCapsule, self.pageCapsule.alphaValue < 0.01 else { return }
            self.pageCapsule.isHidden = true
        })
    }

    @objc func capsulePreviousAction() {
        onPageCapsuleStep?(-1)
        revealPageCapsule()
    }

    @objc func capsuleNextAction() {
        onPageCapsuleStep?(1)
        revealPageCapsule()
    }
}
