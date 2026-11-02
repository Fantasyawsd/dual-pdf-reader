import Cocoa
import PDFKit

// MARK: - Column-local markup model

enum ColumnToolMode: Int, CaseIterable {
    case read = 0
    case annotate = 1
    case shape = 2

    var title: String {
        switch self {
        case .read: return "阅读"
        case .annotate: return "批注"
        case .shape: return "形状"
        }
    }
}

enum PDFMarkupTool: String, CaseIterable {
    case pointer
    case hand
    case highlight
    case underline
    case strikethrough
    case ink
    case eraser
    case text
    case rectangle
    case ellipse
    case line
    case arrow

    var usesDrawingGesture: Bool {
        switch self {
        case .pointer, .hand: return false
        default: return true
        }
    }

    var isTextMarkup: Bool {
        self == .highlight || self == .underline || self == .strikethrough
    }

    var displayName: String {
        switch self {
        case .pointer: return "指针选择"
        case .hand: return "抓手漫游"
        case .highlight: return "高亮"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .ink: return "画笔"
        case .eraser: return "橡皮擦"
        case .text: return "文本"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .line: return "直线"
        case .arrow: return "箭头"
        }
    }

    var annotationSubtype: PDFAnnotationSubtype? {
        switch self {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikethrough: return .strikeOut
        case .ink: return .ink
        case .text: return .freeText
        case .rectangle: return .square
        case .ellipse: return .circle
        case .line, .arrow: return .line
        default: return nil
        }
    }

    var colorAlpha: CGFloat {
        self == .highlight ? 0.35 : 1.0
    }
}

// MARK: - Small helpers

func columnToolbarSymbol(_ names: [String], pointSize: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    for name in names {
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return image.withSymbolConfiguration(configuration)
        }
    }
    return nil
}

// MARK: - Text-only mode tab with a black underline indicator

final class ColumnModeTabView: NSView {
    let mode: ColumnToolMode
    var onSelect: ((ColumnToolMode) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let underline = NSView()
    private var trackingAreaRef: NSTrackingArea?

    var isSelected: Bool = false {
        didSet { refreshAppearance() }
    }
    var isUnderlineVisibleForTesting: Bool { !underline.isHidden }

    override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 30) }

    init(mode: ColumnToolMode, onSelect: @escaping (ColumnToolMode) -> Void) {
        self.mode = mode
        self.onSelect = onSelect
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        label.stringValue = mode.title
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.alignment = .center
        label.isSelectable = false
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let tabToolTip = "切换到\(mode.title)模式"
        toolTip = tabToolTip
        label.toolTip = tabToolTip

        underline.wantsLayer = true
        underline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(underline)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            underline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            underline.heightAnchor.constraint(equalToConstant: 2)
        ])

        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refreshAppearance() {
        underline.layer?.cornerRadius = 1
        underline.layer?.backgroundColor = NSColor.labelColor.cgColor
        underline.isHidden = !isSelected
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.font = .systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .medium)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected { label.textColor = .labelColor }
    }

    override func mouseExited(with event: NSEvent) {
        refreshAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(mode)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Palette swatch used inside the popover only

final class ColumnColorSwatchButton: NSButton {
    let swatchColor: NSColor
    var isSelectedSwatch = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var hoverTrackingArea: NSTrackingArea?

    init(color: NSColor) {
        self.swatchColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        isBordered = false
        title = ""
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isHovered ? 4.0 : 5.0
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
        swatchColor.setFill()
        circle.fill()

        if isSelectedSwatch {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.6
            NSColor.labelColor.setStroke()
            ring.stroke()
        } else if isHovered {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2.5, dy: 2.5))
            ring.lineWidth = 1.0
            NSColor.secondaryLabelColor.setStroke()
            ring.stroke()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Floating page capsule

final class ColumnPageCapsuleView: NSVisualEffectView, NSTextFieldDelegate {
    let previousButton = ModernHoverButton()
    let nextButton = ModernHoverButton()
    let pageField = NSTextField()
    let totalLabel = NSTextField(labelWithString: "1")

    var onCommit: ((Int) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var isHoveredForCapsule = false
    private var totalPages = 1
    private var currentPage = 1
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        layer?.masksToBounds = true
        alphaValue = 0
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false

        previousButton.bezelStyle = .inline
        previousButton.isBordered = false
        previousButton.image = columnToolbarSymbol(["chevron.left"], pointSize: 10, weight: .semibold)
        previousButton.toolTip = "上一页"
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

        nextButton.bezelStyle = .inline
        nextButton.isBordered = false
        nextButton.image = columnToolbarSymbol(["chevron.right"], pointSize: 10, weight: .semibold)
        nextButton.toolTip = "下一页"
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

        pageField.stringValue = "1"
        pageField.alignment = .center
        pageField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        pageField.isBezeled = true
        pageField.bezelStyle = .roundedBezel
        pageField.controlSize = .small
        pageField.delegate = self
        pageField.target = self
        pageField.action = #selector(commitPageField)
        pageField.toolTip = "输入页码后按 Return 跳转"
        pageField.translatesAutoresizingMaskIntoConstraints = false
        pageField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        pageField.heightAnchor.constraint(equalToConstant: 21).isActive = true

        totalLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        totalLabel.textColor = .secondaryLabelColor
        totalLabel.alignment = .left
        totalLabel.toolTip = "总页数"
        totalLabel.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [previousButton, pageField, totalLabel, nextButton])
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 144),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(page: Int, total: Int) {
        totalPages = max(1, total)
        currentPage = min(max(1, page), totalPages)
        if window?.firstResponder !== pageField.currentEditor() {
            pageField.stringValue = "\(currentPage)"
        }
        totalLabel.stringValue = "\(totalPages)"
        previousButton.isEnabled = currentPage > 1
        nextButton.isEnabled = currentPage < totalPages
    }

    @objc private func commitPageField() {
        guard let value = Int(pageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            pageField.stringValue = "\(currentPage)"
            return
        }
        let page = min(max(1, value), totalPages)
        pageField.stringValue = "\(page)"
        currentPage = page
        onCommit?(page)
        window?.makeFirstResponder(nil)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if let value = Int(pageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            pageField.stringValue = "\(min(max(1, value), totalPages))"
        } else {
            pageField.stringValue = "\(currentPage)"
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHoveredForCapsule = true
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHoveredForCapsule = false
        onHoverChanged?(false)
    }
}

// MARK: - Per-column toolbar (primary row + collapsible secondary row)

final class ColumnToolbarView: NSVisualEffectView {
    var onOutline: (() -> Void)?
    var onSpread: (() -> Void)?
    var onContinuous: (() -> Void)?
    var onFitWidth: (() -> Void)?
    var onSearch: (() -> Void)?
    var onNotes: (() -> Void)?
    var onModeChanged: ((ColumnToolMode) -> Void)?
    var onToolChanged: ((PDFMarkupTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onLayoutChanged: (() -> Void)?

    private(set) var mode: ColumnToolMode = .read
    let outlineButton = ModernHoverButton()
    private let spreadButton = ModernHoverButton()
    private let continuousButton = ModernHoverButton()
    private let fitWidthButton = ModernHoverButton()
    private let handButton = ModernHoverButton()
    private let pointerButton = ModernHoverButton()
    private let searchButton = ModernHoverButton()
    private let notesButton = ModernHoverButton()
    private let overflowButton = ModernHoverButton()
    private let modeMenuButton = ModernHoverButton()
    private let paletteButton = ModernHoverButton()
    private var undoButton: ModernHoverButton?
    private var redoButton: ModernHoverButton?

    private let primaryRow = NSView()
    private let leftGroup = NSStackView()
    private let tabsGroup = NSStackView()
    private let rightGroup = NSStackView()
    private let secondaryRow = NSStackView()
    private var secondaryHeightConstraint: NSLayoutConstraint!
    private var tabsLeadingConstraint: NSLayoutConstraint?
    private var tabsCenterXConstraint: NSLayoutConstraint?
    private var rightLimitConstraint: NSLayoutConstraint?
    private var overflowTabsLimitConstraint: NSLayoutConstraint?
    private var modeMenuOverflowLimitConstraint: NSLayoutConstraint?
    private var tabs: [ColumnModeTabView] = []
    private var toolButtons: [PDFMarkupTool: ModernHoverButton] = [:]
    private var lastAnnotateTool: PDFMarkupTool = .highlight
    private var lastShapeTool: PDFMarkupTool = .rectangle
    private var selectedTool: PDFMarkupTool = .pointer
    private var selectedColor: NSColor = NSColor.systemYellow
    private var palettePopover: NSPopover?
    private var lastResponsiveWidth: CGFloat = 0
    private var isUpdatingMode = false
    private var canUndoMarkup = false
    private var canRedoMarkup = false

    var secondaryHeightForTesting: CGFloat { secondaryHeightConstraint.constant }
    var selectedToolForTesting: PDFMarkupTool { selectedTool }
    var modeTitles: [String] { tabs.map(\.mode.title) }
    var selectedModeTitle: String { mode.title }
    var visibleToolTips: [String] {
        func collect(_ view: NSView) -> [String] {
            var tips: [String] = []
            if let button = view as? NSButton, let tip = button.toolTip { tips.append(tip) }
            for child in view.subviews { tips.append(contentsOf: collect(child)) }
            return tips
        }
        return collect(self)
    }
    var hasPaletteButton: Bool { paletteButton.superview != nil }
    var hasSecondaryRow: Bool { !secondaryRow.isHidden }
    var overflowButtonForTesting: ModernHoverButton { overflowButton }
    var modeMenuButtonForTesting: ModernHoverButton { modeMenuButton }
    var modeTabsVisibleForTesting: Bool { !tabsGroup.isHidden }
    var undoEnabledForTesting: Bool { undoButton?.isEnabled ?? false }
    var redoEnabledForTesting: Bool { redoButton?.isEnabled ?? false }
    func overflowMenuTitlesForTesting() -> [String] {
        buildOverflowMenu().items.map { $0.title }.filter { !$0.isEmpty }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .headerView
        blendingMode = .withinWindow
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        primaryRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(primaryRow)

        let leftTools: [(ModernHoverButton, [String], String, Selector)] = [
            (outlineButton, ["list.bullet.indent", "list.bullet"], "大纲目录", #selector(outlineAction)),
            (spreadButton, ["rectangle.split.2x1", "book"], "双页并排", #selector(spreadAction)),
            (continuousButton, ["rectangle.stack", "doc.plaintext"], "单页/连续滚动", #selector(continuousAction)),
            (fitWidthButton, ["arrow.left.and.right", "arrow.left.and.right.square"], "自适应宽度", #selector(fitWidthAction)),
            (handButton, ["hand.raised", "hand.point.up.left"], "抓手漫游", #selector(handAction)),
            (pointerButton, ["cursorarrow", "cursorarrow.rays"], "指针选择", #selector(pointerAction))
        ]
        for (button, symbols, tip, action) in leftTools {
            configureIconButton(button, symbols: symbols, tip: tip, action: action)
            leftGroup.addArrangedSubview(button)
        }
        leftGroup.orientation = .horizontal
        leftGroup.spacing = 3
        leftGroup.alignment = .centerY
        leftGroup.detachesHiddenViews = true
        leftGroup.translatesAutoresizingMaskIntoConstraints = false
        primaryRow.addSubview(leftGroup)

        for toolMode in ColumnToolMode.allCases {
            let tab = ColumnModeTabView(mode: toolMode) { [weak self] selected in
                self?.applyMode(selected)
            }
            tabs.append(tab)
            tabsGroup.addArrangedSubview(tab)
        }
        tabsGroup.orientation = .horizontal
        tabsGroup.spacing = 2
        tabsGroup.alignment = .centerY
        tabsGroup.detachesHiddenViews = true
        tabsGroup.translatesAutoresizingMaskIntoConstraints = false
        primaryRow.addSubview(tabsGroup)

        configureIconButton(searchButton, symbols: ["magnifyingglass"], tip: "页内搜索", action: #selector(searchAction), isToggle: false)
        configureIconButton(notesButton, symbols: ["square.and.pencil"], tip: "随手笔记", action: #selector(notesAction), isToggle: false)
        rightGroup.addArrangedSubview(searchButton)
        rightGroup.addArrangedSubview(notesButton)
        rightGroup.orientation = .horizontal
        rightGroup.spacing = 3
        rightGroup.alignment = .centerY
        rightGroup.detachesHiddenViews = true
        rightGroup.translatesAutoresizingMaskIntoConstraints = false
        primaryRow.addSubview(rightGroup)

        configureIconButton(overflowButton, symbols: ["ellipsis", "ellipsis.circle"], tip: "更多工具",
                            action: #selector(overflowAction), isToggle: false)
        overflowButton.isHidden = true
        primaryRow.addSubview(overflowButton)

        modeMenuButton.bezelStyle = .inline
        modeMenuButton.isBordered = false
        modeMenuButton.setButtonType(.momentaryPushIn)
        modeMenuButton.image = columnToolbarSymbol(["chevron.down"], pointSize: 9, weight: .semibold)
        modeMenuButton.imagePosition = .imageTrailing
        modeMenuButton.font = .systemFont(ofSize: 12, weight: .medium)
        modeMenuButton.title = "阅读"
        modeMenuButton.toolTip = "切换阅读/批注/形状模式"
        modeMenuButton.target = self
        modeMenuButton.action = #selector(modeMenuAction)
        modeMenuButton.translatesAutoresizingMaskIntoConstraints = false
        modeMenuButton.isHidden = true
        primaryRow.addSubview(modeMenuButton)

        secondaryRow.orientation = .horizontal
        secondaryRow.alignment = .centerY
        secondaryRow.spacing = 3
        secondaryRow.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        secondaryRow.detachesHiddenViews = true
        secondaryRow.translatesAutoresizingMaskIntoConstraints = false
        secondaryRow.isHidden = true
        addSubview(secondaryRow)

        let bottomLine = NSView()
        bottomLine.wantsLayer = true
        bottomLine.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomLine)

        secondaryHeightConstraint = secondaryRow.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            primaryRow.topAnchor.constraint(equalTo: topAnchor),
            primaryRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            primaryRow.heightAnchor.constraint(equalToConstant: 34),

            leftGroup.leadingAnchor.constraint(equalTo: primaryRow.leadingAnchor, constant: 8),
            leftGroup.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            tabsGroup.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            rightGroup.trailingAnchor.constraint(equalTo: primaryRow.trailingAnchor, constant: -8),
            rightGroup.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            overflowButton.trailingAnchor.constraint(equalTo: primaryRow.trailingAnchor, constant: -8),
            overflowButton.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            modeMenuButton.leadingAnchor.constraint(equalTo: primaryRow.leadingAnchor, constant: 8),
            modeMenuButton.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            modeMenuButton.widthAnchor.constraint(equalToConstant: 62),
            modeMenuButton.heightAnchor.constraint(equalToConstant: 26),

            secondaryRow.topAnchor.constraint(equalTo: primaryRow.bottomAnchor),
            secondaryRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            secondaryRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            secondaryHeightConstraint,
            bottomLine.topAnchor.constraint(equalTo: secondaryRow.bottomAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Tabs stay centered when there is room. At narrower widths the
        // center constraint (750) yields and the tabs sit after the left
        // group instead of disappearing.
        let tabsCenter = tabsGroup.centerXAnchor.constraint(equalTo: primaryRow.centerXAnchor)
        tabsCenter.priority = .defaultHigh
        tabsCenter.isActive = true
        tabsCenterXConstraint = tabsCenter

        let tabsLeading = tabsGroup.leadingAnchor.constraint(greaterThanOrEqualTo: leftGroup.trailingAnchor, constant: 6)
        tabsLeading.isActive = true
        tabsLeadingConstraint = tabsLeading

        let rightLimit = tabsGroup.trailingAnchor.constraint(lessThanOrEqualTo: rightGroup.leadingAnchor, constant: -6)
        rightLimit.isActive = true
        rightLimitConstraint = rightLimit

        let overflowTabsLimit = tabsGroup.trailingAnchor.constraint(lessThanOrEqualTo: overflowButton.leadingAnchor, constant: -6)
        overflowTabsLimit.isActive = false
        overflowTabsLimitConstraint = overflowTabsLimit

        let modeMenuOverflowLimit = modeMenuButton.trailingAnchor.constraint(lessThanOrEqualTo: overflowButton.leadingAnchor, constant: -6)
        modeMenuOverflowLimit.isActive = false
        modeMenuOverflowLimitConstraint = modeMenuOverflowLimit

        configureIconButton(paletteButton, symbols: ["paintpalette", "circle.grid.hex"], tip: "选择颜色", action: #selector(paletteAction), isToggle: false)
        paletteButton.contentTintColor = selectedColor
        applyMode(.read)
        setActiveTool(.pointer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureIconButton(_ button: ModernHoverButton, symbols: [String], tip: String, action: Selector, isToggle: Bool = true) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(isToggle ? .pushOnPushOff : .momentaryPushIn)
        button.isToggleButton = isToggle
        button.imagePosition = .imageOnly
        button.image = columnToolbarSymbol(symbols, pointSize: 13, weight: .medium)
        button.toolTip = tip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        guard width > 0, abs(width - lastResponsiveWidth) > 0.5 else { return }
        lastResponsiveWidth = width
        updateResponsiveVisibility()
    }

    private func updateResponsiveVisibility() {
        let width = bounds.width
        guard width > 0 else { return }
        let showLeft = width >= 370
        let showRight = width >= 420
        let showTabs = width >= 240
        let showModeMenu = !showTabs
        let showOverflow = !showLeft || !showRight || !showTabs
        leftGroup.isHidden = !showLeft
        rightGroup.isHidden = !showRight
        tabsGroup.isHidden = !showTabs
        modeMenuButton.isHidden = !showModeMenu
        overflowButton.isHidden = !showOverflow
        tabsLeadingConstraint?.isActive = showLeft && showTabs
        rightLimitConstraint?.isActive = showRight
        overflowTabsLimitConstraint?.isActive = showOverflow && showTabs
        modeMenuOverflowLimitConstraint?.isActive = showOverflow && showModeMenu
        if let undoButton { undoButton.isHidden = width < 280 }
        if let redoButton { redoButton.isHidden = width < 280 }
        paletteButton.isHidden = width < 260
        applySecondaryDensity()
    }

    private func applySecondaryDensity() {
        let compact = mode != .read && bounds.width > 0 && bounds.width < 260
        for button in toolButtons.values {
            guard let widthConstraint = button.constraints.first(where: {
                $0.firstAttribute == .width && $0.firstItem === button
            }) else { continue }
            widthConstraint.constant = compact ? 22 : 26
        }
        secondaryRow.spacing = compact ? 1 : 3
        secondaryRow.edgeInsets = compact
            ? NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
            : NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    }

    func applyMode(_ newMode: ColumnToolMode) {
        guard !isUpdatingMode else { return }
        isUpdatingMode = true
        palettePopover?.close()
        palettePopover = nil
        mode = newMode
        modeMenuButton.title = newMode.title
        for tab in tabs { tab.isSelected = (tab.mode == newMode) }
        rebuildSecondaryRow()
        updateResponsiveVisibility()
        let targetTool: PDFMarkupTool
        switch newMode {
        case .read: targetTool = .pointer
        case .annotate: targetTool = lastAnnotateTool
        case .shape: targetTool = lastShapeTool
        }
        setActiveTool(targetTool)
        updateSecondaryHeight()
        onModeChanged?(newMode)
        onToolChanged?(targetTool)
        isUpdatingMode = false
    }

    func setActiveTool(_ tool: PDFMarkupTool) {
        selectedTool = tool
        if tool != .pointer && tool != .hand {
            if mode == .annotate { lastAnnotateTool = tool }
            if mode == .shape { lastShapeTool = tool }
        }
        pointerButton.state = tool == .pointer ? .on : .off
        handButton.state = tool == .hand ? .on : .off
        for (toolKey, button) in toolButtons {
            button.state = toolKey == tool ? .on : .off
        }
    }

    func setUndoRedoEnabled(canUndo: Bool, canRedo: Bool) {
        canUndoMarkup = canUndo
        canRedoMarkup = canRedo
        undoButton?.isEnabled = canUndo
        redoButton?.isEnabled = canRedo
        undoButton?.alphaValue = canUndo ? 1 : 0.38
        redoButton?.alphaValue = canRedo ? 1 : 0.38
    }

    func setViewMode(_ displayMode: PDFDisplayMode) {
        let twoUp = (displayMode == .twoUp || displayMode == .twoUpContinuous)
        let continuous = (displayMode == .singlePageContinuous || displayMode == .twoUpContinuous)
        spreadButton.state = twoUp ? .on : .off
        continuousButton.state = continuous ? .on : .off
        continuousButton.image = columnToolbarSymbol(continuous ? ["rectangle.stack", "doc.plaintext"] : ["rectangle.portrait", "doc"],
                                                      pointSize: 13, weight: .medium)
    }

    func setOutlineActive(_ active: Bool) {
        outlineButton.state = active ? .on : .off
    }

    private func rebuildSecondaryRow() {
        for view in secondaryRow.arrangedSubviews {
            secondaryRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        toolButtons.removeAll()
        undoButton = nil
        redoButton = nil
        guard mode != .read else { return }

        let tools: [(PDFMarkupTool, [String])]
        switch mode {
        case .read:
            tools = []
        case .annotate:
            tools = [
                (.highlight, ["highlighter"]),
                (.underline, ["underline"]),
                (.strikethrough, ["strikethrough"]),
                (.ink, ["pencil.tip", "pencil"]),
                (.eraser, ["eraser", "eraser.fill", "delete.left"]),
                (.text, ["character.textbox", "textformat", "textbox"])
            ]
        case .shape:
            tools = [
                (.rectangle, ["rectangle"]),
                (.ellipse, ["circle"]),
                (.line, ["line.diagonal", "minus"]),
                (.arrow, ["arrow.up.right", "arrow.right"])
            ]
        }

        for (tool, symbols) in tools {
            let button = ModernHoverButton()
            configureIconButton(button, symbols: symbols, tip: tool.displayName, action: #selector(toolAction(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.state = selectedTool == tool ? .on : .off
            toolButtons[tool] = button
            secondaryRow.addArrangedSubview(button)
        }

        secondaryRow.addArrangedSubview(paletteButton)
        paletteButton.state = .off
        paletteButton.contentTintColor = selectedColor

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        secondaryRow.addArrangedSubview(spacer)

        let undo = ModernHoverButton()
        configureIconButton(undo, symbols: ["arrow.uturn.backward"], tip: "撤销", action: #selector(undoAction), isToggle: false)
        undoButton = undo
        let redo = ModernHoverButton()
        configureIconButton(redo, symbols: ["arrow.uturn.forward"], tip: "重做", action: #selector(redoAction), isToggle: false)
        redoButton = redo
        secondaryRow.addArrangedSubview(undo)
        secondaryRow.addArrangedSubview(redo)
        // Preserve the column's existing history enablement when rebuilding
        // the secondary row after a mode switch.
        setUndoRedoEnabled(canUndo: canUndoMarkup, canRedo: canRedoMarkup)
    }

    private func updateSecondaryHeight() {
        let collapsed = mode == .read
        secondaryRow.isHidden = collapsed
        secondaryHeightConstraint.constant = collapsed ? 0 : 32
        needsLayout = true
        onLayoutChanged?()
    }

    @objc private func outlineAction() { onOutline?() }
    @objc private func spreadAction() { onSpread?() }
    @objc private func continuousAction() { onContinuous?() }
    @objc private func fitWidthAction() { onFitWidth?() }
    @objc private func searchAction() { onSearch?() }
    @objc private func notesAction() { onNotes?() }
    @objc private func undoAction() { onUndo?() }
    @objc private func redoAction() { onRedo?() }

    @objc private func overflowAction() {
        let menu = buildOverflowMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowButton.bounds.height + 4), in: overflowButton)
    }

    @objc private func modeMenuAction() {
        let menu = NSMenu(title: "阅读模式")
        for toolMode in ColumnToolMode.allCases {
            let item = NSMenuItem(title: toolMode.title, action: #selector(selectModeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = toolMode.rawValue
            item.state = toolMode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: modeMenuButton.bounds.height + 4), in: modeMenuButton)
    }

    @objc private func selectModeFromMenu(_ sender: NSMenuItem) {
        applyMode(ColumnToolMode(rawValue: sender.tag) ?? .read)
    }

    private func buildOverflowMenu() -> NSMenu {
        let menu = NSMenu(title: "更多工具")
        addOverflowItem(menu, title: "大纲目录", action: #selector(outlineAction), isOn: outlineButton.state == .on)
        addOverflowItem(menu, title: "双页并排", action: #selector(spreadAction), isOn: spreadButton.state == .on)
        addOverflowItem(menu, title: "单页/连续滚动", action: #selector(continuousAction), isOn: continuousButton.state == .on)
        addOverflowItem(menu, title: "自适应宽度", action: #selector(fitWidthAction))
        addOverflowItem(menu, title: "抓手漫游", action: #selector(handAction), isOn: handButton.state == .on)
        addOverflowItem(menu, title: "指针选择", action: #selector(pointerAction), isOn: pointerButton.state == .on)
        menu.addItem(.separator())
        addOverflowItem(menu, title: "页内搜索", action: #selector(searchAction))
        addOverflowItem(menu, title: "随手笔记", action: #selector(notesAction))
        if mode != .read {
            menu.addItem(.separator())
            addOverflowItem(menu, title: "撤销批注", action: #selector(undoAction), isEnabled: canUndoMarkup)
            addOverflowItem(menu, title: "重做批注", action: #selector(redoAction), isEnabled: canRedoMarkup)
            addOverflowItem(menu, title: "选择颜色…", action: #selector(moreColorsAction))
        }
        return menu
    }

    private func addOverflowItem(_ menu: NSMenu, title: String, action: Selector,
                                 isOn: Bool = false, isEnabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        item.isEnabled = isEnabled
        menu.addItem(item)
    }

    @objc private func handAction() {
        setActiveTool(.hand)
        onToolChanged?(.hand)
    }

    @objc private func pointerAction() {
        setActiveTool(.pointer)
        onToolChanged?(.pointer)
    }

    @objc private func toolAction(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = PDFMarkupTool(rawValue: raw) else { return }
        setActiveTool(tool)
        onToolChanged?(tool)
    }

    @objc private func paletteAction() {
        let vc = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 212, height: 104))
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        let colors: [NSColor] = [
            .systemYellow, .systemGreen, .systemBlue, .systemPink,
            .systemRed, .systemOrange, .systemPurple, .systemTeal
        ]
        let colorNames = ["琥珀黄", "翠竹绿", "晴空蓝", "珊瑚粉", "朱砂红", "暖橙色", "薰衣紫", "青绿色"]
        for row in 0..<2 {
            var rowButtons: [ColumnColorSwatchButton] = []
            for column in 0..<4 {
                let color = colors[row * 4 + column]
                let swatch = ColumnColorSwatchButton(color: color)
                swatch.toolTip = colorNames[row * 4 + column]
                swatch.isSelectedSwatch = colorsEqual(selectedColor, color)
                swatch.target = self
                swatch.action = #selector(paletteSwatchClicked(_:))
                rowButtons.append(swatch)
            }
            grid.addRow(with: rowButtons)
        }
        grid.rowSpacing = 6
        grid.columnSpacing = 4
        container.addSubview(grid)

        let moreButton = NSButton(title: "更多颜色…", target: self, action: #selector(moreColorsAction))
        moreButton.bezelStyle = .inline
        moreButton.isBordered = false
        moreButton.font = .systemFont(ofSize: 11.5)
        moreButton.contentTintColor = .controlAccentColor
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(moreButton)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            moreButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 6),
            moreButton.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        vc.view = container
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        popover.show(relativeTo: paletteButton.bounds, of: paletteButton, preferredEdge: .maxY)
        palettePopover = popover
    }

    @objc private func paletteSwatchClicked(_ sender: ColumnColorSwatchButton) {
        applyColor(sender.swatchColor)
        palettePopover?.close()
        palettePopover = nil
    }

    @objc private func moreColorsAction() {
        palettePopover?.close()
        palettePopover = nil
        let panel = NSColorPanel.shared
        panel.color = selectedColor
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        applyColor(sender.color)
    }

    private func applyColor(_ color: NSColor) {
        let normalized = color.usingColorSpace(.deviceRGB) ?? color
        selectedColor = normalized
        paletteButton.contentTintColor = normalized
        onColorChanged?(normalized)
    }

    private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let l = lhs.usingColorSpace(.deviceRGB)
        let r = rhs.usingColorSpace(.deviceRGB)
        guard let l, let r else { return false }
        return abs(l.redComponent - r.redComponent) < 0.01 &&
            abs(l.greenComponent - r.greenComponent) < 0.01 &&
            abs(l.blueComponent - r.blueComponent) < 0.01
    }
}
