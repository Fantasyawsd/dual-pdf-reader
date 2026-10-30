import Cocoa
import PDFKit
import JavaScriptCore
import QuartzCore
import UniformTypeIdentifiers

// MARK: - NSWindow Extension for Titlebar Double Click Action
extension NSWindow {
    func performTitleBarDoubleClickAction() {
        guard !styleMask.contains(.fullScreen) else { return }
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
        if let action = action {
            switch action {
            case "Minimize":
                miniaturize(nil)
            case "None":
                break
            case "Maximize", "Zoom":
                zoom(nil)
            default:
                zoom(nil)
            }
        } else {
            if UserDefaults.standard.bool(forKey: "AppleMiniaturizeOnDoubleClick") {
                miniaturize(nil)
            } else {
                zoom(nil)
            }
        }
    }
}

// MARK: - Draggable Unified Titlebar VisualEffectView
final class DraggableTitleBarView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performTitleBarDoubleClickAction()
            return
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Horizontal Scroll View for Unified Tab Bar (Prevents Constraint Overflow with Many Tabs)
final class HorizontalTabScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { true }

    @objc func _opaqueRectForWindowMoveWhenInTitlebar() -> NSRect {
        return bounds
    }

    @objc func _opaqueRect() -> NSRect {
        return bounds
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performTitleBarDoubleClickAction()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let docView = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        if abs(delta) > 0.01 {
            var origin = contentView.bounds.origin
            let maxOffset = max(0, docView.bounds.width - contentView.bounds.width)
            origin.x = max(0, min(maxOffset, origin.x - delta))
            origin.y = 0
            contentView.scroll(to: origin)
            reflectScrolledClipView(contentView)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

final class NonDraggableClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performTitleBarDoubleClickAction()
            return
        }
        super.mouseDown(with: event)
    }
}

final class DraggableTabDocumentView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performTitleBarDoubleClickAction()
            return
        }
        super.mouseDown(with: event)
    }
}

enum TabDragPasteboard {
    static let type = NSPasteboard.PasteboardType("com.local.DualPDFReader.tab-id")

    static func tabId(from pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: type)
    }
}

enum TabOrder {
    static func moving(_ tabId: String, toInsertionIndex insertionIndex: Int, in ids: [String]) -> [String] {
        guard let sourceIndex = ids.firstIndex(of: tabId) else { return ids }

        var reordered = ids
        reordered.remove(at: sourceIndex)
        let adjustedIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        let targetIndex = max(0, min(reordered.count, adjustedIndex))
        reordered.insert(tabId, at: targetIndex)
        return reordered
    }

    static func insertionIndex(forX x: CGFloat, tabFrames: [NSRect]) -> Int {
        var index = 0
        for frame in tabFrames {
            guard x >= frame.midX else { break }
            index += 1
        }
        return index
    }
}

final class TabDropIndicatorView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.controlAccentColor.cgColor
        layer.cornerRadius = 1.5
        layer.shadowColor = NSColor.controlAccentColor.cgColor
        layer.shadowOpacity = 0.42
        layer.shadowRadius = 4
        layer.shadowOffset = .zero
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class NonDraggableStackView: NSStackView {
    var onTabDrop: ((String, Int) -> Void)?

    private let dropIndicator = TabDropIndicatorView()
    private var autoScrollTimer: Timer?
    private var isDragInside = false
    private var activeDragTabId: String?

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTabDragging()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTabDragging()
    }

    deinit {
        autoScrollTimer?.invalidate()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performTitleBarDoubleClickAction()
            return
        }
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let tabId = draggedTabId(from: sender) else { return [] }
        activeDragTabId = tabId
        isDragInside = true
        startAutoScrolling()
        updateDropIndicator(for: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let tabId = draggedTabId(from: sender) else { return [] }
        activeDragTabId = tabId
        updateDropIndicator(for: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        stopDraggingFeedback()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedTabId(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let tabId = draggedTabId(from: sender),
              let insertionIndex = currentInsertionIndex(for: sender) else {
            stopDraggingFeedback()
            return false
        }

        stopDraggingFeedback()
        onTabDrop?(tabId, insertionIndex)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        stopDraggingFeedback()
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        stopDraggingFeedback()
    }

    private var tabViews: [ZoteroTabItemView] {
        arrangedSubviews.compactMap { $0 as? ZoteroTabItemView }
    }

    private func configureTabDragging() {
        registerForDraggedTypes([TabDragPasteboard.type])
        dropIndicator.wantsLayer = true
        dropIndicator.isHidden = true
        addSubview(dropIndicator, positioned: .above, relativeTo: nil)
    }

    private func draggedTabId(from sender: NSDraggingInfo) -> String? {
        guard let tabId = TabDragPasteboard.tabId(from: sender.draggingPasteboard),
              tabViews.contains(where: { $0.tabId == tabId }) else { return nil }
        return tabId
    }

    private func currentInsertionIndex(for sender: NSDraggingInfo) -> Int? {
        guard let tabId = draggedTabId(from: sender),
              tabViews.contains(where: { $0.tabId == tabId }) else { return nil }
        let location = convert(sender.draggingLocation, from: nil)
        return TabOrder.insertionIndex(forX: location.x, tabFrames: tabViews.map(\.frame))
    }

    private func updateDropIndicator(for sender: NSDraggingInfo) {
        guard let tabId = draggedTabId(from: sender),
              let sourceIndex = tabViews.firstIndex(where: { $0.tabId == tabId }) else {
            dropIndicator.isHidden = true
            return
        }

        let tabs = tabViews
        let location = convert(sender.draggingLocation, from: nil)
        let insertionIndex = TabOrder.insertionIndex(forX: location.x, tabFrames: tabs.map(\.frame))
        updateDropIndicator(tabId: tabId, sourceIndex: sourceIndex, insertionIndex: insertionIndex)
    }

    private func startAutoScrolling() {
        guard autoScrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.autoScrollTick()
        }
        autoScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDraggingFeedback() {
        isDragInside = false
        activeDragTabId = nil
        dropIndicator.isHidden = true
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func autoScrollTick() {
        guard isDragInside,
              let scrollView = enclosingScrollView,
              let window else { return }

        let clipView = scrollView.contentView
        let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let visibleRect = convert(clipView.bounds, from: clipView)
        let edgeWidth: CGFloat = 30
        var horizontalDelta: CGFloat = 0

        if pointer.x < visibleRect.minX + edgeWidth {
            let intensity = min(1, (visibleRect.minX + edgeWidth - pointer.x) / edgeWidth)
            horizontalDelta = -12 * max(0.2, intensity)
        } else if pointer.x > visibleRect.maxX - edgeWidth {
            let intensity = min(1, (pointer.x - visibleRect.maxX + edgeWidth) / edgeWidth)
            horizontalDelta = 12 * max(0.2, intensity)
        }

        if horizontalDelta != 0 {
            let maxOffset = max(0, (scrollView.documentView?.bounds.width ?? 0) - clipView.bounds.width)
            var origin = clipView.bounds.origin
            origin.x = max(0, min(maxOffset, origin.x + horizontalDelta))
            origin.y = 0
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        if let draggedId = activeDragTabId,
           let sourceIndex = tabViews.firstIndex(where: { $0.tabId == draggedId }) {
            let insertionIndex = TabOrder.insertionIndex(forX: pointer.x, tabFrames: tabViews.map(\.frame))
            updateDropIndicator(tabId: draggedId, sourceIndex: sourceIndex, insertionIndex: insertionIndex)
        }
    }

    private func updateDropIndicator(tabId: String, sourceIndex: Int, insertionIndex: Int) {
        let tabs = tabViews
        guard insertionIndex != sourceIndex, insertionIndex != sourceIndex + 1, tabs.count > 1 else {
            dropIndicator.isHidden = true
            return
        }

        let indicatorX: CGFloat
        if insertionIndex == 0 {
            indicatorX = tabs[0].frame.minX - 2
        } else if insertionIndex == tabs.count {
            indicatorX = tabs[tabs.count - 1].frame.maxX + 2
        } else {
            indicatorX = (tabs[insertionIndex - 1].frame.maxX + tabs[insertionIndex].frame.minX) / 2
        }

        dropIndicator.frame = NSRect(
            x: min(max(1, indicatorX - 1.5), max(1, bounds.width - 4.5)),
            y: bounds.midY - 11,
            width: 3,
            height: 22
        )
        dropIndicator.isHidden = false
    }
}

final class NonDraggableTextField: NSTextField {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class NonDraggableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - Modern macOS Unified Tab Item View (Subclasses NSControl so .fullSizeContentView Titlebar Excludes It from Window Drag Region)
final class ZoteroTabItemView: NSControl, NSDraggingSource {
    let tabId: String
    var isActiveTab: Bool {
        didSet {
            guard oldValue != isActiveTab else { return }
            titleLabel.textColor = isActiveTab ? .labelColor : .secondaryLabelColor
            titleLabel.font = isActiveTab ? .systemFont(ofSize: 13.5, weight: .medium) : .systemFont(ofSize: 13.5, weight: .regular)
            updateCloseButtonAppearance()
            updateTabBackground()
        }
    }
    let isClosable: Bool
    var onSelect: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    var onCloseOthers: ((String) -> Void)?
    var onRevealInFinder: ((String) -> Void)?

    private let iconView = NonDraggableImageView()
    private let titleLabel = NonDraggableTextField(labelWithString: "")
    let closeButton = NSButton()
    private let tabBackgroundLayer = CAShapeLayer()
    private let dividerLayer = CALayer()
    private var mouseDownLocation: NSPoint?
    private var isDraggingTab = false
    private var isHovered = false {
        didSet {
            updateCloseButtonAppearance()
            updateTabBackground()
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    @objc func _opaqueRectForWindowMoveWhenInTitlebar() -> NSRect {
        return bounds
    }

    @objc func _opaqueRect() -> NSRect {
        return bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if isClosable && !closeButton.isHidden {
            let btnPoint = closeButton.convert(local, from: self)
            if closeButton.bounds.contains(btnPoint) {
                return closeButton
            }
        }
        return self
    }

    init(
        tabId: String,
        title: String,
        symbol: String,
        symbolTint: NSColor,
        isActive: Bool,
        closable: Bool
    ) {
        self.tabId = tabId
        self.isActiveTab = isActive
        self.isClosable = closable
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(tabBackgroundLayer)
        layer?.addSublayer(dividerLayer)
        dividerLayer.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor

        setupSubviews(title: title, symbol: symbol, symbolTint: symbolTint)
        toolTip = "拖拽调整标签页位置"
        if closable {
            self.menu = buildTabContextMenu()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateCloseButtonAppearance() {
        guard isClosable else {
            closeButton.isHidden = true
            return
        }
        closeButton.isHidden = !(isActiveTab || isHovered)
        closeButton.alphaValue = isActiveTab ? 0.72 : 0.9
        closeButton.contentTintColor = isActiveTab ? .secondaryLabelColor : .labelColor
    }

    private func setupSubviews(title: String, symbol: String, symbolTint: NSColor) {
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.contentTintColor = symbolTint
        iconView.symbolConfiguration = .init(pointSize: 13.5, weight: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
        titleLabel.textColor = isActiveTab ? .labelColor : .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(greaterThanOrEqualToConstant: isClosable ? 104 : 150),
            widthAnchor.constraint(lessThanOrEqualToConstant: isClosable ? 250 : 190),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if isClosable {
            closeButton.bezelStyle = .inline
            closeButton.isBordered = false
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")
            closeButton.symbolConfiguration = .init(pointSize: 10, weight: .bold)
            closeButton.toolTip = "关闭标签页 (⌘W / 中键点击)"
            closeButton.focusRingType = .none
            closeButton.target = self
            closeButton.action = #selector(closeBtnClicked)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(closeButton)
            updateCloseButtonAppearance()

            NSLayoutConstraint.activate([
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -2),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
                closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 20),
                closeButton.heightAnchor.constraint(equalToConstant: 20)
            ])
        } else {
            closeButton.isHidden = true
            NSLayoutConstraint.activate([
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
            ])
        }

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateTabBackground()
    }

    private func buildTabContextMenu() -> NSMenu {
        let m = NSMenu()
        let closeItem = NSMenuItem(title: "关闭此标签页", action: #selector(closeBtnClicked), keyEquivalent: "")
        closeItem.target = self
        m.addItem(closeItem)

        let closeOthersItem = NSMenuItem(title: "关闭其他阅读标签页", action: #selector(closeOthersClicked), keyEquivalent: "")
        closeOthersItem.target = self
        m.addItem(closeOthersItem)

        m.addItem(NSMenuItem.separator())
        let revealItem = NSMenuItem(title: "在 Finder 中显示该论文文件夹", action: #selector(revealClicked), keyEquivalent: "")
        revealItem.target = self
        m.addItem(revealItem)
        return m
    }

    override func layout() {
        super.layout()
        updateTabBackground()
    }

    override func updateLayer() {
        updateTabBackground()
    }

    private func updateTabBackground() {
        guard let layer, bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer.backgroundColor = NSColor.clear.cgColor
        tabBackgroundLayer.frame = bounds

        let rect = bounds.insetBy(dx: 0.35, dy: 1)
        let radius: CGFloat = 7
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - radius * 0.45),
            control2: CGPoint(x: rect.minX + radius * 0.45, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            control1: CGPoint(x: rect.maxX - radius * 0.45, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - radius * 0.45)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()

        tabBackgroundLayer.path = path
        tabBackgroundLayer.lineWidth = 0
        if isActiveTab {
            tabBackgroundLayer.isHidden = false
            tabBackgroundLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.98).cgColor
            tabBackgroundLayer.strokeColor = NSColor.clear.cgColor
        } else if isHovered {
            tabBackgroundLayer.isHidden = false
            tabBackgroundLayer.fillColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.34).cgColor
            tabBackgroundLayer.strokeColor = NSColor.clear.cgColor
        } else {
            tabBackgroundLayer.isHidden = true
        }

        dividerLayer.frame = NSRect(x: bounds.maxX - 0.5, y: 8, width: 1, height: max(0, bounds.height - 16))
        dividerLayer.isHidden = isActiveTab || isHovered
        dividerLayer.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor

        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTabBackground()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if let win = window {
            let mouseInWin = win.mouseLocationOutsideOfEventStream
            let localPt = convert(mouseInWin, from: nil)
            let inside = bounds.contains(localPt)
            if inside {
                options.insert(.assumeInside)
            }
            if isHovered != inside {
                isHovered = inside
            }
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        onSelect?(tabId)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingTab, let mouseDownLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - mouseDownLocation.x
        let deltaY = location.y - mouseDownLocation.y
        guard sqrt(deltaX * deltaX + deltaY * deltaY) >= 4 else { return }

        self.mouseDownLocation = nil
        beginTabDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        super.mouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if isClosable && event.buttonNumber == 2 {
            onClose?(tabId)
        } else {
            super.otherMouseDown(with: event)
        }
    }

    @objc private func closeBtnClicked() {
        onClose?(tabId)
    }

    @objc private func closeOthersClicked() {
        onCloseOthers?(tabId)
    }

    @objc private func revealClicked() {
        onRevealInFinder?(tabId)
    }

    private func beginTabDrag(with event: NSEvent) {
        guard !isDraggingTab else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tabId, forType: TabDragPasteboard.type)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())

        isDraggingTab = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            animator().alphaValue = 0.5
        }

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    private func draggingImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else { return image }
        cacheDisplay(in: bounds, to: representation)
        image.addRepresentation(representation)
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingTab = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }
}

// MARK: - Zotero 7 Style Unified Tab Bar Window Controller
