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
    var onMarkupCreate: (([PaperAnnotation]) -> Void)?
    var onMarkupUpdate: ((PaperAnnotation) -> Void)?
    var onMarkupDelete: (([String]) -> Void)?
    var onMarkupVisibilityChanged: ((Set<String>) -> Void)?
    var markupTool: PDFMarkupTool = .pointer {
        didSet {
            textMarkupPopover?.close()
            window?.invalidateCursorRects(for: self)
            if markupTool != .eraser { eraserCursorPoint = nil }
            markupOverlay?.needsDisplay = true
        }
    }
    var markupColor: NSColor = NSColor.systemYellow
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

    var storedAnnotations: [PaperAnnotation] = [] {
        didSet { markupOverlay?.needsDisplay = true }
    }
    private(set) var selectedMarkupId: String?

    private enum MarkupCommand {
        case create(PaperAnnotation)
        case delete([PaperAnnotation])
        case update(before: PaperAnnotation, after: PaperAnnotation)
    }

    private enum MarkupHandle {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        case startPoint, endPoint
    }

    private enum MarkupGestureOperation {
        case draw(PaperAnnotationKind)
        case move(id: String, before: PaperAnnotation)
        case resize(id: String, before: PaperAnnotation, handle: MarkupHandle)
        case endpoint(id: String, before: PaperAnnotation, isStart: Bool)
        case erase(Set<String>)
    }

    private struct MarkupGesture {
        var page: PDFPage
        var pageIndex: Int
        var start: PointCodable
        var current: PointCodable
        var startViewPoint: NSPoint
        var points: [PointCodable]
        var modifiers: NSEvent.ModifierFlags
        var operation: MarkupGestureOperation
        var didExceedDragThreshold = false
        var hiddenMarkupIDs = Set<String>()
    }

    private var markupUndoStack: [MarkupCommand] = []
    private var markupRedoStack: [MarkupCommand] = []
    private var markupGesture: MarkupGesture?
    private var markupOverlay: MarkupOverlayView?
    private var nativeTextMarkupTool: PDFMarkupTool?
    private var handDragStart: NSPoint?
    private var handDragOrigin: NSPoint?
    private var textMarkupPopover: NSPopover?
    private var textMarkupDraftPage: PDFPage?
    private var textMarkupDraftPoint: NSPoint?
    private var textMarkupDraftAnnotation: PaperAnnotation?
    private var contextMarkupId: String?
    private var contextMarkupPoint: NSPoint = .zero
    private var eraserCursorPoint: NSPoint?
    private var markupTrackingArea: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []

    var canUndoMarkup: Bool { !markupUndoStack.isEmpty }
    var canRedoMarkup: Bool { !markupRedoStack.isEmpty }
    var markupUndoCount: Int { markupUndoStack.count }
    var markupRedoCount: Int { markupRedoStack.count }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        installMarkupOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
        installMarkupOverlay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let markupOverlay {
            addSubview(markupOverlay, positioned: .above, relativeTo: nil)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
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
        // In pointer mode hitTest routes page hits to this view so markup
        // selection works. That also means wheel events no longer reach
        // PDFKit's internal PDFScrollView on their own; PDFView.super does not
        // scroll. Forward them explicitly or the reader becomes unscrollable.
        if let scroll = internalScrollView() {
            scroll.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
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
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            markupGesture = nil
            onMarkupVisibilityChanged?([])
            dismissTextMarkupEditor()
            markupOverlay?.needsDisplay = true
            selectMarkup(nil)
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if deleteSelectedMarkup() { return }
        }
        if [123, 124, 125, 126].contains(Int(event.keyCode)), nudgeSelectedMarkup(for: event) {
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
            addCursorRect(bounds, cursor: .arrow)
        case .text, .highlight, .underline, .strikethrough:
            addCursorRect(bounds, cursor: .iBeam)
        default:
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        guard markupTool == .pointer else {
            super.cursorUpdate(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let handle = selectedHandle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .topLeft, .bottomRight: NSCursor.resizeLeftRight.set()
            case .topRight, .bottomLeft: NSCursor.resizeUpDown.set()
            case .startPoint, .endPoint: NSCursor.pointingHand.set()
            }
        } else if markupHit(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let markupTrackingArea { removeTrackingArea(markupTrackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        markupTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        if markupTool == .eraser {
            eraserCursorPoint = convert(event.locationInWindow, from: nil)
            markupOverlay?.needsDisplay = true
        }
        if markupTool == .pointer { cursorUpdate(with: event) }
        else { super.mouseMoved(with: event) }
    }

    /// PDFKit installs private page views above the PDFView. When a markup
    /// tool is active those views would swallow mouse events before our
    /// gesture handlers run, so route page hits to this view. The pointer
    /// tool keeps PDFKit's native text-selection and link behavior.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if markupTool == .pointer {
            return page(for: local, nearest: false) == nil ? super.hitTest(point) : self
        }
        if markupTool == .hand { return self }
        guard page(for: local, nearest: false) != nil else { return super.hitTest(point) }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
        if markupTool == .hand {
            beginHandPan(with: event)
            return
        }
        if markupTool.isTextMarkup {
            nativeTextMarkupTool = markupTool
            super.mouseDown(with: event)
            commitNativeTextMarkupSelection()
            return
        }
        if markupTool != .pointer {
            beginMarkupGesture(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let page = page(for: viewPoint, nearest: false) {
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

            if handlePointerMouseDown(at: viewPoint, event: event) {
                return
            }
        }
        selectMarkup(nil)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if markupTool == .hand, handDragStart != nil {
            updateHandPan(with: event)
            return
        }
        if markupTool.isTextMarkup {
            super.mouseDragged(with: event)
            return
        }
        if markupTool == .pointer, markupGesture != nil {
            updateMarkupGesture(with: event)
            return
        }
        if markupTool != .pointer, markupTool != .hand, markupGesture != nil {
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
        if markupTool.isTextMarkup {
            super.mouseUp(with: event)
            commitNativeTextMarkupSelection()
            return
        }
        if markupGesture != nil {
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

    private func commitNativeTextMarkupSelection() {
        let tool = nativeTextMarkupTool
        nativeTextMarkupTool = nil
        guard let tool, let selection = currentSelection,
              let document,
              let annotation = PDFSelectionAnnotationFactory.make(
                  selection: selection, document: document, side: side,
                  pdfDocumentId: activePDFDocumentId, color: .nearest(to: markupColor),
                  note: "", linkedURL: nil, linkedTitle: nil,
                  kind: tool.annotationKind, colorHex: markupColor.hexString) else { return }
        commitCreate(annotation)
        setCurrentSelection(nil, animate: false)
    }

    // MARK: - Native macOS Context Menu
    override func menu(for event: NSEvent) -> NSMenu? {
        onInteraction?()
        let menu = NSMenu(title: "PDF Context Menu")
        let contextPoint = convert(event.locationInWindow, from: nil)
        if let annotation = markupHit(at: contextPoint) {
            contextMarkupId = annotation.id
            contextMarkupPoint = contextPoint
            let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteContextMarkupAction), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)

            let colorItem = NSMenuItem(title: "颜色", action: nil, keyEquivalent: "")
            let colorMenu = NSMenu(title: "颜色")
            for color in HighlightColor.allCases {
                let item = NSMenuItem(title: color.displayName, action: #selector(changeContextMarkupColorAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = color
                colorMenu.addItem(item)
            }
            colorItem.submenu = colorMenu
            menu.addItem(colorItem)

            let noteItem = NSMenuItem(title: "添加/编辑笔记", action: #selector(noteContextMarkupAction), keyEquivalent: "")
            noteItem.target = self
            menu.addItem(noteItem)
            menu.addItem(NSMenuItem.separator())
        } else {
            contextMarkupId = nil
        }

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

    @objc private func deleteContextMarkupAction() {
        guard let id = contextMarkupId else { return }
        commitDelete([id])
    }

    @objc private func changeContextMarkupColorAction(_ sender: NSMenuItem) {
        guard let id = contextMarkupId,
              let color = sender.representedObject as? HighlightColor,
              let annotation = storedAnnotations.first(where: { $0.id == id }) else { return }
        var updated = annotation
        updated.color = color
        updated.colorHex = color.solidColor.hexString
        commitUpdate(before: annotation, after: updated)
    }

    @objc private func noteContextMarkupAction() {
        guard let id = contextMarkupId,
              let annotation = storedAnnotations.first(where: { $0.id == id }) else { return }
        onAnnotationClicked?(annotation, contextMarkupPoint)
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


// MARK: - Hand tool, model-driven markup, and per-column undo history
extension InteractivePDFView {
    func installMarkupOverlay() {
        let overlay = MarkupOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.drawContent = { [weak self] in self?.drawMarkupOverlay() }
        addSubview(overlay, positioned: .above, relativeTo: nil)
        markupOverlay = overlay
        observeMarkupViewport()
    }

    private func observeMarkupViewport() {
        let center = NotificationCenter.default
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewPageChanged] {
            observers.append(center.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                self?.markupOverlay?.needsDisplay = true
            })
        }
        guard let clipView = internalScrollView()?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
            self?.markupOverlay?.needsDisplay = true
        })
    }

    func beginHandPan(with event: NSEvent) {
        handDragStart = convert(event.locationInWindow, from: nil)
        handDragOrigin = internalScrollView()?.contentView.bounds.origin
        NSCursor.closedHand.set()
    }

    func updateHandPan(with event: NSEvent) {
        guard let start = handDragStart, var origin = handDragOrigin,
              let scroll = internalScrollView() else { return }
        let point = convert(event.locationInWindow, from: nil)
        origin.x -= point.x - start.x
        origin.y -= point.y - start.y
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

    func markupHit(at viewPoint: NSPoint) -> PaperAnnotation? {
        guard let page = page(for: viewPoint, nearest: false), let document,
              scaleFactor > 0 else { return nil }
        let pageIndex = document.index(for: page)
        let pagePoint = convert(viewPoint, to: page)
        let tolerance: CGFloat = 6
        let candidates = storedAnnotations.enumerated()
            .filter { $0.element.effectivePDFId == activePDFDocumentId }
            .sorted {
                $0.element.createdAt == $1.element.createdAt
                    ? $0.offset > $1.offset
                    : $0.element.createdAt > $1.element.createdAt
            }
            .map(\.element)

        for annotation in candidates {
            if annotation.effectiveKind.isTextMarkup {
                let contains = annotation.pageRegions.contains { region in
                    region.pageIndex == pageIndex && region.rects.contains {
                        $0.cgRect.insetBy(dx: -tolerance / scaleFactor,
                                          dy: -tolerance / scaleFactor).contains(pagePoint)
                    }
                }
                if contains { return annotation }
                continue
            }
            guard annotation.pageIndex == pageIndex, let rect = annotation.rects.first?.cgRect else { continue }
            switch annotation.effectiveKind {
            case .line, .arrow:
                guard let start = annotation.startPoint?.cgPoint,
                      let end = annotation.endPoint?.cgPoint else { continue }
                let a = convert(start, from: page)
                let b = convert(end, from: page)
                if distance(viewPoint, toSegmentFrom: a, to: b) <=
                    max(tolerance, CGFloat(annotation.strokeWidth ?? 0) * scaleFactor + 3) {
                    return annotation
                }
            case .ink:
                let segmentTolerance = max(tolerance,
                                           CGFloat(annotation.strokeWidth ?? 2) * scaleFactor + 3)
                for path in annotation.inkPaths ?? [] {
                    let points = path.map { convert($0.cgPoint, from: page) }
                    if points.contains(where: { hypot($0.x - viewPoint.x, $0.y - viewPoint.y) <= segmentTolerance }) ||
                        zip(points, points.dropFirst()).contains(where: {
                            distance(viewPoint, toSegmentFrom: $0.0, to: $0.1) <= segmentTolerance
                        }) {
                        return annotation
                    }
                }
            case .rectangle, .ellipse, .text:
                if convert(rect, from: page).insetBy(dx: -tolerance, dy: -tolerance).contains(viewPoint) {
                    return annotation
                }
            case .highlight, .underline, .strikethrough:
                break
            }
        }
        return nil
    }

    private func handlePointerMouseDown(at viewPoint: NSPoint, event: NSEvent) -> Bool {
        guard let page = page(for: viewPoint, nearest: false), let document else { return false }
        let pageIndex = document.index(for: page)
        let pagePoint = PointCodable(convert(viewPoint, to: page))
        if let annotation = markupHit(at: viewPoint), annotation.effectiveKind.isTextMarkup {
            selectMarkup(annotation.id)
            onAnnotationClicked?(annotation, viewPoint)
            return true
        }
        if let handle = selectedHandle(at: viewPoint),
           let selected = selectedMarkupId,
           let annotation = storedAnnotations.first(where: { $0.id == selected }) {
            let operation: MarkupGestureOperation
            switch handle {
            case .startPoint: operation = .endpoint(id: selected, before: annotation, isStart: true)
            case .endPoint: operation = .endpoint(id: selected, before: annotation, isStart: false)
            default: operation = .resize(id: selected, before: annotation, handle: handle)
            }
            beginEditGesture(page: page, pageIndex: pageIndex, point: pagePoint,
                             viewPoint: viewPoint, operation: operation)
            return true
        }
        guard let annotation = markupHit(at: viewPoint) else { return false }
        selectMarkup(annotation.id)
        if annotation.effectiveKind == .text, event.clickCount > 1 {
            presentTextMarkupEditor(on: page, at: pagePoint.cgPoint, editing: annotation)
            return true
        }
        beginEditGesture(page: page, pageIndex: pageIndex, point: pagePoint,
                         viewPoint: viewPoint,
                         operation: .move(id: annotation.id, before: annotation))
        return true
    }

    private func beginEditGesture(page: PDFPage, pageIndex: Int, point: PointCodable,
                                 viewPoint: NSPoint, operation: MarkupGestureOperation) {
        window?.makeFirstResponder(self)
        markupGesture = MarkupGesture(page: page, pageIndex: pageIndex, start: point, current: point,
                                      startViewPoint: viewPoint, points: [], modifiers: [],
                                      operation: operation)
        markupOverlay?.needsDisplay = true
    }

    func beginMarkupGesture(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if markupTool == .eraser {
            eraserCursorPoint = viewPoint
            markupOverlay?.needsDisplay = true
        }
        guard let page = page(for: viewPoint, nearest: false),
              let document,
              document.index(for: page) != NSNotFound else { return }
        let pageIndex = document.index(for: page)
        let point = PointCodable(convert(viewPoint, to: page))
        window?.makeFirstResponder(self)
        switch markupTool {
        case .text:
            presentTextMarkupEditor(on: page, at: point.cgPoint)
        case .eraser:
            markupGesture = MarkupGesture(page: page, pageIndex: pageIndex, start: point, current: point,
                                          startViewPoint: viewPoint, points: [],
                                          modifiers: event.modifierFlags, operation: .erase([]))
            collectEraseHit(at: viewPoint)
        case .ink:
            markupGesture = MarkupGesture(page: page, pageIndex: pageIndex, start: point, current: point,
                                          startViewPoint: viewPoint, points: [point],
                                          modifiers: event.modifierFlags, operation: .draw(.ink))
        case .rectangle, .ellipse, .line, .arrow:
            markupGesture = MarkupGesture(page: page, pageIndex: pageIndex, start: point, current: point,
                                          startViewPoint: viewPoint, points: [], modifiers: event.modifierFlags,
                                          operation: .draw(markupTool.annotationKind))
        case .pointer, .hand, .highlight, .underline, .strikethrough:
            break
        }
        markupOverlay?.needsDisplay = true
    }

    func updateMarkupGesture(with event: NSEvent) {
        guard var gesture = markupGesture else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = PointCodable(convert(viewPoint, to: gesture.page))
        gesture.current = point
        gesture.modifiers = event.modifierFlags
        switch gesture.operation {
        case .draw(.ink):
            if let last = gesture.points.last,
               hypot(point.cgPoint.x - last.cgPoint.x, point.cgPoint.y - last.cgPoint.y) >= 0.75 {
                gesture.points.append(point)
            }
        case .erase(var ids):
            eraserCursorPoint = viewPoint
            if let hit = markupHit(at: viewPoint) { ids.insert(hit.id) }
            gesture.operation = .erase(ids)
            if ids != gesture.hiddenMarkupIDs {
                onMarkupVisibilityChanged?(ids)
                gesture.hiddenMarkupIDs = ids
            }
        case .move, .resize, .endpoint:
            updateEditDragThreshold(&gesture, at: viewPoint)
        default:
            break
        }
        markupGesture = gesture
        markupOverlay?.needsDisplay = true
    }

    func finishMarkupGesture(with event: NSEvent) {
        guard var gesture = markupGesture else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        gesture.current = PointCodable(convert(viewPoint, to: gesture.page))
        gesture.modifiers = event.modifierFlags
        updateEditDragThreshold(&gesture, at: viewPoint)
        markupGesture = gesture
        let shouldRestoreHiddenMarkup: Bool
        switch gesture.operation {
        case .move, .resize, .endpoint:
            shouldRestoreHiddenMarkup = gesture.didExceedDragThreshold
        case .erase(let ids):
            shouldRestoreHiddenMarkup = !ids.isEmpty
        case .draw:
            shouldRestoreHiddenMarkup = false
        }
        defer {
            markupGesture = nil
            if shouldRestoreHiddenMarkup { onMarkupVisibilityChanged?([]) }
            markupOverlay?.needsDisplay = true
        }

        switch gesture.operation {
        case .draw(let kind):
            if kind == .ink {
                if let last = gesture.points.last,
                   hypot(gesture.current.cgPoint.x - last.cgPoint.x,
                         gesture.current.cgPoint.y - last.cgPoint.y) >= 0.75 {
                    gesture.points.append(gesture.current)
                }
                guard let bounds = pointBounds(gesture.points), bounds.width >= 2 || bounds.height >= 2 else { return }
                var annotation = makeMarkup(kind: .ink, pageIndex: gesture.pageIndex,
                                            rect: bounds, selectedText: "")
                annotation.inkPaths = [gesture.points]
                annotation.strokeWidth = 2
                commitCreate(annotation)
            } else {
                let end = constrainedEnd(gesture.current.cgPoint, from: gesture.start.cgPoint,
                                         kind: kind, shift: gesture.modifiers.contains(.shift))
                let rect = CGRect(x: min(gesture.start.x, end.x), y: min(gesture.start.y, end.y),
                                  width: abs(end.x - gesture.start.x), height: abs(end.y - gesture.start.y))
                guard hypot(end.x - gesture.start.x, end.y - gesture.start.y) >= 3 else { return }
                var annotation = makeMarkup(kind: kind, pageIndex: gesture.pageIndex,
                                            rect: rect, selectedText: "")
                if kind == .line || kind == .arrow {
                    annotation.startPoint = gesture.start
                    annotation.endPoint = PointCodable(end)
                }
                commitCreate(annotation)
            }
        case .erase(let ids):
            if !ids.isEmpty { commitDelete(Array(ids)) }
        case .move(let id, let before):
            let after = translated(before, dx: gesture.current.x - gesture.start.x,
                                   dy: gesture.current.y - gesture.start.y)
            if gesture.didExceedDragThreshold, before != after {
                commitUpdate(before: before, after: after)
            } else {
                selectMarkup(id)
            }
        case .resize(let id, let before, let handle):
            let after = resized(before, handle: handle, to: gesture.current.cgPoint,
                                constrain: gesture.modifiers.contains(.shift))
            if gesture.didExceedDragThreshold, before != after {
                commitUpdate(before: before, after: after)
            } else {
                selectMarkup(id)
            }
        case .endpoint(let id, let before, let isStart):
            var after = before
            if isStart { after.startPoint = gesture.current } else { after.endPoint = gesture.current }
            if let start = after.startPoint?.cgPoint, let end = after.endPoint?.cgPoint {
                after.rects = [RectCodable(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                                width: abs(end.x - start.x), height: abs(end.y - start.y)))]
            }
            if gesture.didExceedDragThreshold, before != after {
                commitUpdate(before: before, after: after)
            } else {
                selectMarkup(id)
            }
        }
    }

    private func updateEditDragThreshold(_ gesture: inout MarkupGesture, at viewPoint: NSPoint) {
        guard !gesture.didExceedDragThreshold,
              hypot(viewPoint.x - gesture.startViewPoint.x,
                    viewPoint.y - gesture.startViewPoint.y) > 2 else { return }
        let id: String
        switch gesture.operation {
        case .move(let value, _), .resize(let value, _, _), .endpoint(let value, _, _):
            id = value
        case .draw, .erase:
            return
        }
        gesture.didExceedDragThreshold = true
        onMarkupVisibilityChanged?([id])
    }

    private func collectEraseHit(at viewPoint: NSPoint) {
        guard var gesture = markupGesture else { return }
        guard case .erase(var ids) = gesture.operation else { return }
        let previousIDs = ids
        if let hit = markupHit(at: viewPoint) { ids.insert(hit.id) }
        gesture.operation = .erase(ids)
        gesture.hiddenMarkupIDs = ids
        markupGesture = gesture
        if ids != previousIDs { onMarkupVisibilityChanged?(ids) }
    }

    private func makeMarkup(kind: PaperAnnotationKind, pageIndex: Int, rect: CGRect,
                            selectedText: String) -> PaperAnnotation {
        var annotation = PaperAnnotation(side: side, pageIndex: pageIndex, rects: [RectCodable(rect)],
                                         selectedText: selectedText, color: .nearest(to: markupColor),
                                         markdownNote: "", linkedURL: nil, linkedTitle: nil,
                                         pdfDocumentId: activePDFDocumentId)
        annotation.kind = kind
        annotation.colorHex = markupColor.hexString
        annotation.strokeWidth = kind == .ink ? 2 : 1.6
        return annotation
    }

    private func constrainedEnd(_ end: CGPoint, from start: CGPoint, kind: PaperAnnotationKind,
                                shift: Bool) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if shift, kind == .rectangle || kind == .ellipse {
            let length = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -length : length),
                           y: start.y + (dy < 0 ? -length : length))
        }
        if shift, kind == .line || kind == .arrow {
            let angle = atan2(dy, dx)
            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(snapped) * length, y: start.y + sin(snapped) * length)
        }
        return end
    }

    private func pointBounds(_ points: [PointCodable]) -> CGRect? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first.cgPoint, size: .zero)) {
            $0.union(CGRect(origin: $1.cgPoint, size: .zero))
        }
    }

    private func presentTextMarkupEditor(on page: PDFPage, at point: CGPoint,
                                         editing annotation: PaperAnnotation? = nil) {
        textMarkupPopover?.close()
        textMarkupDraftPage = page
        textMarkupDraftPoint = point
        textMarkupDraftAnnotation = annotation
        let controller = TextMarkupPopoverController(initialText: annotation?.selectedText ?? "",
                                                     isEditing: annotation != nil)
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
        if let before = textMarkupDraftAnnotation {
            var after = before
            after.selectedText = text
            after.rects = [RectCodable(measuredTextBounds(text, origin: before.rects.first?.cgRect.origin ?? point,
                                                         on: page))]
            commitUpdate(before: before, after: after)
        } else {
            let bounds = measuredTextBounds(text, origin: point, on: page)
            commitCreate(makeMarkup(kind: .text, pageIndex: document?.index(for: page) ?? 0,
                                    rect: bounds, selectedText: text))
        }
        dismissTextMarkupEditor()
    }

    private func measuredTextBounds(_ text: String, origin: CGPoint, on page: PDFPage) -> CGRect {
        let font = NSFont.systemFont(ofSize: 12)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: 232, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let width = min(240, max(12, ceil(measured.width) + 8))
        let height = max(18, ceil(measured.height)) + 8
        let pageBounds = page.bounds(for: displayBox).insetBy(dx: 4, dy: 4)
        let x = min(max(origin.x, pageBounds.minX), max(pageBounds.minX, pageBounds.maxX - width))
        let y = min(max(origin.y, pageBounds.minY), max(pageBounds.minY, pageBounds.maxY - height))
        return CGRect(x: x, y: y, width: min(width, pageBounds.width), height: min(height, pageBounds.height))
    }

    private func dismissTextMarkupEditor() {
        textMarkupPopover?.close()
        textMarkupPopover = nil
        textMarkupDraftPage = nil
        textMarkupDraftPoint = nil
        textMarkupDraftAnnotation = nil
    }

    func addTextMarkupForTesting(text: String, page: PDFPage, at point: NSPoint) {
        let bounds = measuredTextBounds(text, origin: point, on: page)
        commitCreate(makeMarkup(kind: .text, pageIndex: document?.index(for: page) ?? 0,
                                rect: bounds, selectedText: text))
    }

    func dismissTextMarkupPopover() {
        dismissTextMarkupEditor()
    }

    private func selectedHandle(at viewPoint: NSPoint) -> MarkupHandle? {
        guard let id = selectedMarkupId,
              let annotation = storedAnnotations.first(where: { $0.id == id }),
              !annotation.effectiveKind.isTextMarkup,
              let page = page(for: viewPoint, nearest: false),
              annotation.pageIndex == document?.index(for: page) else { return nil }
        if annotation.effectiveKind == .line || annotation.effectiveKind == .arrow {
            if let start = annotation.startPoint?.cgPoint,
               hypot(convert(start, from: page).x - viewPoint.x, convert(start, from: page).y - viewPoint.y) <= 7 {
                return .startPoint
            }
            if let end = annotation.endPoint?.cgPoint,
               hypot(convert(end, from: page).x - viewPoint.x, convert(end, from: page).y - viewPoint.y) <= 7 {
                return .endPoint
            }
            return nil
        }
        guard let rect = annotation.rects.first?.cgRect else { return nil }
        let viewRect = convert(rect, from: page)
        let xMid = viewRect.midX
        let yMid = viewRect.midY
        let handles: [(MarkupHandle, NSPoint)] = [
            (.topLeft, NSPoint(x: viewRect.minX, y: viewRect.maxY)),
            (.top, NSPoint(x: xMid, y: viewRect.maxY)),
            (.topRight, NSPoint(x: viewRect.maxX, y: viewRect.maxY)),
            (.right, NSPoint(x: viewRect.maxX, y: yMid)),
            (.bottomRight, NSPoint(x: viewRect.maxX, y: viewRect.minY)),
            (.bottom, NSPoint(x: xMid, y: viewRect.minY)),
            (.bottomLeft, NSPoint(x: viewRect.minX, y: viewRect.minY)),
            (.left, NSPoint(x: viewRect.minX, y: yMid))
        ]
        return handles.first { abs($0.1.x - viewPoint.x) <= 6 && abs($0.1.y - viewPoint.y) <= 6 }?.0
    }

    private func selectMarkup(_ id: String?) {
        selectedMarkupId = id
        markupOverlay?.needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func deleteSelectedMarkup() -> Bool {
        guard let id = selectedMarkupId else { return false }
        commitDelete([id])
        return true
    }

    private func nudgeSelectedMarkup(for event: NSEvent) -> Bool {
        guard let id = selectedMarkupId,
              let before = storedAnnotations.first(where: { $0.id == id }) else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let delta: CGPoint
        switch event.keyCode {
        case 123: delta = CGPoint(x: -step, y: 0)
        case 124: delta = CGPoint(x: step, y: 0)
        case 125: delta = CGPoint(x: 0, y: -step)
        case 126: delta = CGPoint(x: 0, y: step)
        default: return false
        }
        commitUpdate(before: before, after: translated(before, dx: Double(delta.x), dy: Double(delta.y)))
        return true
    }

    private func translated(_ annotation: PaperAnnotation, dx: Double, dy: Double) -> PaperAnnotation {
        var updated = annotation
        func move(_ point: PointCodable) -> PointCodable {
            PointCodable(CGPoint(x: CGFloat(point.x + dx), y: CGFloat(point.y + dy)))
        }
        func move(_ rect: RectCodable) -> RectCodable {
            RectCodable(CGRect(x: CGFloat(rect.x + dx), y: CGFloat(rect.y + dy),
                               width: CGFloat(rect.width), height: CGFloat(rect.height)))
        }
        updated.rects = annotation.rects.map(move)
        updated.additionalPageRegions = annotation.additionalPageRegions?.map { region in
            AnnotationPageRegion(pageIndex: region.pageIndex, rects: region.rects.map(move))
        }
        updated.inkPaths = annotation.inkPaths?.map { $0.map(move) }
        if let start = annotation.startPoint { updated.startPoint = move(start) }
        if let end = annotation.endPoint { updated.endPoint = move(end) }
        return updated
    }

    private func resized(_ annotation: PaperAnnotation, handle: MarkupHandle, to point: CGPoint,
                         constrain: Bool) -> PaperAnnotation {
        guard let old = annotation.rects.first?.cgRect else { return annotation }
        var minX = old.minX, maxX = old.maxX, minY = old.minY, maxY = old.maxY
        switch handle {
        case .topLeft: minX = point.x; maxY = point.y
        case .top: maxY = point.y
        case .topRight: maxX = point.x; maxY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; minY = point.y
        case .bottom: minY = point.y
        case .bottomLeft: minX = point.x; minY = point.y
        case .left: minX = point.x
        case .startPoint, .endPoint: return annotation
        }
        let isCorner = handle == .topLeft || handle == .topRight || handle == .bottomLeft || handle == .bottomRight
        if (constrain || annotation.effectiveKind == .ink), isCorner {
            let anchor = CGPoint(x: handle == .topLeft || handle == .bottomLeft ? old.maxX : old.minX,
                                 y: handle == .topLeft || handle == .topRight ? old.minY : old.maxY)
            let dx = point.x - anchor.x
            let dy = point.y - anchor.y
            let size = max(abs(dx), abs(dy))
            minX = dx < 0 ? anchor.x - size : anchor.x
            maxX = dx < 0 ? anchor.x : anchor.x + size
            minY = dy < 0 ? anchor.y - size : anchor.y
            maxY = dy < 0 ? anchor.y : anchor.y + size
        }
        let next = CGRect(x: min(minX, maxX), y: min(minY, maxY),
                          width: max(1, abs(maxX - minX)), height: max(1, abs(maxY - minY)))
        var updated = annotation
        updated.rects[0] = RectCodable(next)
        if annotation.effectiveKind == .ink,
           old.width > 0, old.height > 0 {
            updated.inkPaths = annotation.inkPaths?.map { path in
                path.map { point in
                    PointCodable(CGPoint(
                        x: next.minX + (CGFloat(point.x) - old.minX) * next.width / old.width,
                        y: next.minY + (CGFloat(point.y) - old.minY) * next.height / old.height))
                }
            }
        }
        return updated
    }

    private func commitCreate(_ annotation: PaperAnnotation) {
        onMarkupCreate?([annotation])
        markupUndoStack.append(.create(annotation))
        markupRedoStack.removeAll()
        selectMarkup(annotation.id)
        onMarkupStateChanged?()
    }

    private func commitUpdate(before: PaperAnnotation, after: PaperAnnotation) {
        guard before != after else { return }
        onMarkupUpdate?(after)
        markupUndoStack.append(.update(before: before, after: after))
        markupRedoStack.removeAll()
        selectMarkup(after.id)
        onMarkupStateChanged?()
    }

    private func commitDelete(_ ids: [String]) {
        let uniqueIDs = Array(Set(ids))
        let removed = uniqueIDs.compactMap { id in storedAnnotations.first(where: { $0.id == id }) }
        guard !removed.isEmpty else { return }
        onMarkupDelete?(removed.map(\.id))
        markupUndoStack.append(.delete(removed))
        markupRedoStack.removeAll()
        if removed.contains(where: { $0.id == selectedMarkupId }) { selectMarkup(nil) }
        onMarkupStateChanged?()
    }

    func updateSelectedMarkupColor(_ color: NSColor) {
        guard let id = selectedMarkupId,
              let before = storedAnnotations.first(where: { $0.id == id }) else { return }
        var after = before
        after.color = .nearest(to: color)
        after.colorHex = color.hexString
        commitUpdate(before: before, after: after)
    }

    func undoMarkup() {
        guard let command = markupUndoStack.popLast() else { return }
        switch command {
        case .create(let annotation):
            onMarkupDelete?([annotation.id])
            selectMarkup(nil)
        case .delete(let annotations):
            onMarkupCreate?(annotations)
            selectMarkup(annotations.first?.id)
        case .update(let before, _):
            onMarkupUpdate?(before)
            selectMarkup(before.id)
        }
        markupRedoStack.append(command)
        onMarkupStateChanged?()
    }

    func redoMarkup() {
        guard let command = markupRedoStack.popLast() else { return }
        switch command {
        case .create(let annotation):
            onMarkupCreate?([annotation])
            selectMarkup(annotation.id)
        case .delete(let annotations):
            onMarkupDelete?(annotations.map(\.id))
            selectMarkup(nil)
        case .update(_, let after):
            onMarkupUpdate?(after)
            selectMarkup(after.id)
        }
        markupUndoStack.append(command)
        onMarkupStateChanged?()
    }

    func resetMarkupHistory() {
        markupUndoStack.removeAll()
        markupRedoStack.removeAll()
        markupGesture = nil
        selectMarkup(nil)
        onMarkupVisibilityChanged?([])
        onMarkupStateChanged?()
    }

    func clearSelectedMarkupIfMissing() {
        guard let selectedMarkupId,
              storedAnnotations.contains(where: { $0.id == selectedMarkupId }) else {
            selectMarkup(nil)
            return
        }
    }

    private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    private func drawMarkupOverlay() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if markupTool == .eraser, let cursorPoint = eraserCursorPoint {
            let cursorRect = CGRect(x: cursorPoint.x - 8, y: cursorPoint.y - 8, width: 16, height: 16)
            context.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: cursorRect)
        }
        guard let document else { return }
        if let gesture = markupGesture {
            switch gesture.operation {
            case .draw(let kind):
                if let model = previewMarkup(for: gesture, kind: kind) {
                    draw(model, pageIndex: gesture.pageIndex, selected: false)
                }
            case .move(_, let before), .resize(_, let before, _), .endpoint(_, let before, _):
                if gesture.didExceedDragThreshold {
                    let preview: PaperAnnotation
                    switch gesture.operation {
                    case .move: preview = translated(before, dx: gesture.current.x - gesture.start.x, dy: gesture.current.y - gesture.start.y)
                    case .resize(_, _, let handle): preview = resized(before, handle: handle, to: gesture.current.cgPoint, constrain: gesture.modifiers.contains(.shift))
                    case .endpoint(_, _, let isStart):
                        var value = before
                        if isStart { value.startPoint = gesture.current } else { value.endPoint = gesture.current }
                        preview = value
                    default: preview = before
                    }
                    draw(preview, pageIndex: gesture.pageIndex, selected: true)
                } else {
                    draw(before, pageIndex: gesture.pageIndex, selected: true)
                }
            case .erase:
                break
            }
        } else if let selectedMarkupId,
                  let selected = storedAnnotations.first(where: { $0.id == selectedMarkupId }) {
            draw(selected, pageIndex: selected.pageIndex, selected: true)
        }
        _ = document
    }

    private func previewMarkup(for gesture: MarkupGesture, kind: PaperAnnotationKind) -> PaperAnnotation? {
        if kind == .ink {
            guard let bounds = pointBounds(gesture.points) else { return nil }
            var model = makeMarkup(kind: .ink, pageIndex: gesture.pageIndex, rect: bounds, selectedText: "")
            model.inkPaths = [gesture.points]
            return model
        }
        let end = constrainedEnd(gesture.current.cgPoint, from: gesture.start.cgPoint, kind: kind,
                                 shift: gesture.modifiers.contains(.shift))
        let rect = CGRect(x: min(gesture.start.x, end.x), y: min(gesture.start.y, end.y),
                          width: abs(end.x - gesture.start.x), height: abs(end.y - gesture.start.y))
        var model = makeMarkup(kind: kind, pageIndex: gesture.pageIndex, rect: rect, selectedText: "")
        if kind == .line || kind == .arrow {
            model.startPoint = gesture.start
            model.endPoint = PointCodable(end)
        }
        return model
    }

    private func draw(_ annotation: PaperAnnotation, pageIndex: Int, selected: Bool) {
        guard let page = document?.page(at: pageIndex) else { return }
        let color = annotation.displayColor
        if annotation.effectiveKind.isTextMarkup {
            for region in annotation.pageRegions where region.pageIndex == pageIndex {
                for rect in region.rects {
                    let viewRect = convert(rect.cgRect, from: page)
                    (selected ? NSColor.controlAccentColor : color.withAlphaComponent(0.18)).setStroke()
                    let outline = NSBezierPath(rect: viewRect)
                    outline.lineWidth = selected ? 1.5 : 1
                    outline.stroke()
                }
            }
            return
        }
        if annotation.effectiveKind == .ink, let paths = annotation.inkPaths {
            for points in paths where !points.isEmpty {
                let path = NSBezierPath()
                path.lineWidth = CGFloat(annotation.strokeWidth ?? 2)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: convert(points[0].cgPoint, from: page))
                for point in points.dropFirst() { path.line(to: convert(point.cgPoint, from: page)) }
                color.setStroke()
                path.stroke()
            }
        } else if annotation.effectiveKind == .line || annotation.effectiveKind == .arrow {
            if let start = annotation.startPoint?.cgPoint, let end = annotation.endPoint?.cgPoint {
                let path = NSBezierPath()
                path.lineWidth = CGFloat(annotation.strokeWidth ?? 1.6)
                path.move(to: convert(start, from: page))
                path.line(to: convert(end, from: page))
                color.setStroke()
                path.stroke()
            }
        } else if let rect = annotation.rects.first?.cgRect {
            let bounds = convert(rect, from: page)
            if annotation.effectiveKind == .text {
                color.setStroke()
                NSBezierPath(rect: bounds).stroke()
            } else {
                color.setStroke()
                (annotation.effectiveKind == .ellipse ? NSBezierPath(ovalIn: bounds) : NSBezierPath(rect: bounds)).stroke()
            }
        }
        guard selected, let rect = annotation.rects.first?.cgRect else { return }
        let bounds = convert(rect, from: page)
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: bounds)
        outline.lineWidth = 1
        outline.stroke()
        if annotation.effectiveKind == .line || annotation.effectiveKind == .arrow {
            for point in [annotation.startPoint, annotation.endPoint].compactMap({ $0 }) {
                fillMarkupHandle(at: convert(point.cgPoint, from: page))
            }
        } else if !annotation.effectiveKind.isTextMarkup {
            let positions = [
                NSPoint(x: bounds.minX, y: bounds.maxY), NSPoint(x: bounds.midX, y: bounds.maxY),
                NSPoint(x: bounds.maxX, y: bounds.maxY), NSPoint(x: bounds.maxX, y: bounds.midY),
                NSPoint(x: bounds.maxX, y: bounds.minY), NSPoint(x: bounds.midX, y: bounds.minY),
                NSPoint(x: bounds.minX, y: bounds.minY), NSPoint(x: bounds.minX, y: bounds.midY)
            ]
            positions.forEach(fillMarkupHandle(at:))
        }
    }

    private func fillMarkupHandle(at point: NSPoint) {
        let rect = NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.white.setStroke()
        NSBezierPath(rect: rect).stroke()
    }
}

final class MarkupOverlayView: NSView {
    var drawContent: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        drawContent?()
    }
}


// MARK: - Text annotation editor

final class TextMarkupPopoverController: NSViewController, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private let textField = NSTextField()
    private let initialText: String
    private let isEditing: Bool

    init(initialText: String = "", isEditing: Bool = false) {
        self.initialText = initialText
        self.isEditing = isEditing
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        initialText = ""
        isEditing = false
        super.init(coder: coder)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 96))
        let title = NSTextField(labelWithString: isEditing ? "编辑文本批注" : "添加文本批注")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        textField.placeholderString = "输入文本内容"
        textField.stringValue = initialText
        textField.font = .systemFont(ofSize: 13)
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: isEditing ? "保存" : "添加", target: self, action: #selector(commitAction))
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
        textMarkupDraftAnnotation = nil
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
    var onMarkupStateChanged: (() -> Void)?
    private var capsuleHideTicket = 0
    private var capsuleHotspotTrackingArea: NSTrackingArea?

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
            self.onMarkupStateChanged?()
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
