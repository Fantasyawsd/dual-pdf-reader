import Cocoa

/// One shared markup toolbar for both PDF columns. Tool and color choices are
/// applied to both panes by the reader. Undo/redo live in the 编辑 menu and ⌘Z.
///
/// Only five controls are pinned (高亮、下划线、画笔、文本、调色盘); every other
/// tool lives in the「…」overflow menu. When the bar is narrower than the pinned
/// set, pinned controls collapse into the overflow menu from right to left.
final class UnifiedMarkupToolbarView: NSView {
    /// A control that can be pinned on the bar or collapsed into the overflow menu.
    enum Item: Equatable, Hashable {
        case tool(PDFMarkupTool)
        case palette

        var title: String {
            switch self {
            case .tool(let tool): return tool.displayName
            case .palette: return "选择颜色"
            }
        }
    }

    /// Pinned controls in display order (left → right). Collapse order is the reverse.
    static let pinnedItems: [Item] = [.tool(.highlight), .tool(.underline), .tool(.ink), .tool(.text), .palette]
    /// Tools that always live in the overflow menu, in menu order.
    static let overflowOnlyTools: [PDFMarkupTool] = [.pointer, .strikethrough, .eraser,
                                                     .rectangle, .ellipse, .line, .arrow]
    /// Every markup tool the bar exposes (pinned + overflow).
    static let allTools: [PDFMarkupTool] = [.pointer, .highlight, .underline, .strikethrough, .ink, .eraser,
                                            .text, .rectangle, .ellipse, .line, .arrow]

    static let buttonWidth: CGFloat = 26
    static let itemSpacing: CGFloat = 2

    var onToolChanged: ((PDFMarkupTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?

    private(set) var selectedTool: PDFMarkupTool = .pointer
    private(set) var selectedColor: NSColor = .systemYellow
    /// Number of pinned items (counted from the right) currently collapsed into the overflow menu.
    private(set) var collapsedPinnedCount = 0

    private let stack = NSStackView()
    private let paletteButton = ModernHoverButton()
    private let overflowButton = ModernHoverButton()
    private let paletteSeparator = NSBox()
    private var toolButtons: [PDFMarkupTool: ModernHoverButton] = [:]
    private var palettePopover: NSPopover?
    private var widthConstraint: NSLayoutConstraint?

    private static let symbols: [PDFMarkupTool: [String]] = [
        .pointer: ["cursorarrow"],
        .highlight: ["highlighter"],
        .underline: ["underline"],
        .strikethrough: ["strikethrough"],
        .ink: ["pencil.tip", "pencil"],
        .eraser: ["eraser", "eraser.fill"],
        .text: ["character.textbox", "textformat"],
        .rectangle: ["rectangle"],
        .ellipse: ["circle"],
        .line: ["line.diagonal", "minus"],
        .arrow: ["arrow.up.right", "arrow.right"]
    ]

    // MARK: Testing hooks

    /// Tooltips of the controls currently visible on the bar.
    var toolTipsForTesting: [String] {
        visiblePinnedItems.map(\.title) + [overflowButton.toolTip].compactMap { $0 }
    }
    var selectedToolForTesting: PDFMarkupTool { selectedTool }
    var overflowButtonForTesting: NSButton { overflowButton }
    /// Pinned items currently shown on the bar.
    var visiblePinnedItems: [Item] {
        Array(Self.pinnedItems.prefix(Self.pinnedItems.count - collapsedPinnedCount))
    }
    /// Pinned items currently collapsed into the overflow menu (display order).
    var collapsedPinnedItems: [Item] {
        Array(Self.pinnedItems.suffix(collapsedPinnedCount))
    }
    /// Tools reachable only through the overflow menu right now.
    var overflowToolsForTesting: [PDFMarkupTool] {
        overflowMenuEntries().compactMap { if case .tool(let t) = $0 { return t } else { return nil } }
    }
    var visibleToolsForTesting: [PDFMarkupTool] {
        visiblePinnedItems.compactMap { if case .tool(let t) = $0 { return t } else { return nil } }
    }
    func overflowMenuForTesting() -> NSMenu { buildOverflowMenu() }
    func chooseOverflowItemForTesting(_ item: Item) {
        guard let menuItem = buildOverflowMenu().items.first(where: { ($0.representedObject as? String) == key(for: item) })
        else { return }
        overflowMenuItemAction(menuItem)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Self.itemSpacing
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for tool in Self.allTools {
            let button = ModernHoverButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.pushOnPushOff)
            button.isToggleButton = true
            button.imagePosition = .imageOnly
            button.image = columnToolbarSymbol(Self.symbols[tool] ?? ["questionmark"], pointSize: 13, weight: .medium)
            button.toolTip = tool.displayName
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.target = self
            button.action = #selector(toolAction(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.buttonWidth),
                button.heightAnchor.constraint(equalToConstant: 26)
            ])
            toolButtons[tool] = button
        }
        for case .tool(let tool) in Self.pinnedItems {
            if let button = toolButtons[tool] { stack.addArrangedSubview(button) }
        }

        configureSeparator(paletteSeparator)
        stack.addArrangedSubview(paletteSeparator)
        paletteButton.bezelStyle = .inline
        paletteButton.isBordered = false
        paletteButton.setButtonType(.momentaryPushIn)
        paletteButton.imagePosition = .imageOnly
        paletteButton.image = columnToolbarSymbol(["paintpalette", "circle.grid.hex"], pointSize: 13, weight: .medium)
        paletteButton.toolTip = "选择颜色"
        paletteButton.target = self
        paletteButton.action = #selector(paletteAction)
        paletteButton.translatesAutoresizingMaskIntoConstraints = false
        paletteButton.widthAnchor.constraint(equalToConstant: Self.buttonWidth).isActive = true
        paletteButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(paletteButton)

        overflowButton.bezelStyle = .inline
        overflowButton.isBordered = false
        overflowButton.setButtonType(.pushOnPushOff)
        overflowButton.isToggleButton = true
        overflowButton.imagePosition = .imageOnly
        overflowButton.image = columnToolbarSymbol(["ellipsis.circle", "ellipsis"], pointSize: 13, weight: .medium)
        overflowButton.identifier = NSUserInterfaceItemIdentifier("markupOverflow")
        overflowButton.target = self
        overflowButton.action = #selector(overflowAction)
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.widthAnchor.constraint(equalToConstant: Self.buttonWidth).isActive = true
        overflowButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(overflowButton)

        let width = widthAnchor.constraint(equalToConstant: Self.width(collapsing: 0))
        widthConstraint = width
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 30),
            width
        ])
        setSelectedTool(.pointer)
    }

    private func configureSeparator(_ box: NSBox) {
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 15).isActive = true
    }

    // MARK: Width fitting

    /// Width the bar needs when `collapsing` pinned items (from the right) are in the overflow menu.
    static func width(collapsing: Int) -> CGFloat {
        let shown = pinnedItems.prefix(pinnedItems.count - max(0, min(collapsing, pinnedItems.count)))
        var widths: [CGFloat] = shown.map { _ in buttonWidth }
        if shown.contains(.palette) { widths.append(1) } // separator before the palette
        widths.append(buttonWidth)                        // overflow「…」button
        return widths.reduce(0, +) + CGFloat(widths.count - 1) * itemSpacing
    }

    static var minimumWidth: CGFloat { width(collapsing: pinnedItems.count) }
    static var fullWidth: CGFloat { width(collapsing: 0) }

    /// Collapse pinned items right-to-left until the bar fits in `availableWidth`.
    @discardableResult
    func fit(availableWidth: CGFloat) -> CGFloat {
        var collapse = 0
        while collapse < Self.pinnedItems.count && Self.width(collapsing: collapse) > availableWidth {
            collapse += 1
        }
        setCollapsedPinnedCount(collapse)
        return Self.width(collapsing: collapse)
    }

    private func setCollapsedPinnedCount(_ count: Int) {
        collapsedPinnedCount = count
        let visible = Set(visiblePinnedItems)
        for case .tool(let tool) in Self.pinnedItems {
            toolButtons[tool]?.isHidden = !visible.contains(.tool(tool))
        }
        paletteButton.isHidden = !visible.contains(.palette)
        paletteSeparator.isHidden = paletteButton.isHidden
        widthConstraint?.constant = Self.width(collapsing: count)
        updateOverflowIndicator()
    }

    // MARK: Overflow menu

    private func overflowMenuEntries() -> [Item] {
        let collapsedTools = collapsedPinnedItems.filter { $0 != .palette }
        var entries: [Item] = [.tool(.pointer)] + collapsedTools
        entries += Self.overflowOnlyTools.filter { $0 != .pointer }.map { .tool($0) }
        if collapsedPinnedItems.contains(.palette) { entries.append(.palette) }
        return entries
    }

    private func key(for item: Item) -> String {
        switch item {
        case .tool(let tool): return tool.rawValue
        case .palette: return "palette"
        }
    }

    private func buildOverflowMenu() -> NSMenu {
        let menu = NSMenu(title: "更多批注工具")
        menu.autoenablesItems = false
        var previousGroup: Int?
        for entry in overflowMenuEntries() {
            let group: Int
            switch entry {
            case .tool(.pointer): group = 0
            case .tool(.rectangle), .tool(.ellipse), .tool(.line), .tool(.arrow): group = 2
            case .palette: group = 3
            default: group = 1
            }
            if let previousGroup, previousGroup != group { menu.addItem(.separator()) }
            previousGroup = group
            let title = entry == .palette ? "选择颜色…" : entry.title
            let item = NSMenuItem(title: title, action: #selector(overflowMenuItemAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key(for: entry)
            if case .tool(let tool) = entry {
                item.image = columnToolbarSymbol(Self.symbols[tool] ?? [], pointSize: 13, weight: .regular)
                item.state = tool == selectedTool ? .on : .off
            } else {
                item.image = columnToolbarSymbol(["paintpalette"], pointSize: 13, weight: .regular)
            }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func overflowAction() {
        updateOverflowIndicator()
        let menu = buildOverflowMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowButton.bounds.height + 4), in: overflowButton)
        updateOverflowIndicator()
    }

    @objc private func overflowMenuItemAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if raw == "palette" {
            showPalette(relativeTo: overflowButton)
            return
        }
        guard let tool = PDFMarkupTool(rawValue: raw) else { return }
        setSelectedTool(tool)
        onToolChanged?(tool)
    }

    /// The「…」button lights up and names the tool when the active tool lives in the menu.
    private func updateOverflowIndicator() {
        let inOverflow = selectedTool != .pointer && overflowToolsForTesting.contains(selectedTool)
        overflowButton.state = inOverflow ? .on : .off
        overflowButton.toolTip = inOverflow ? "更多批注工具（当前：\(selectedTool.displayName)）" : "更多批注工具"
        overflowButton.image = inOverflow
            ? columnToolbarSymbol(Self.symbols[selectedTool] ?? ["ellipsis.circle"], pointSize: 13, weight: .semibold)
            : columnToolbarSymbol(["ellipsis.circle", "ellipsis"], pointSize: 13, weight: .medium)
    }

    func setSelectedTool(_ tool: PDFMarkupTool) {
        selectedTool = tool
        for (key, button) in toolButtons { button.state = key == tool ? .on : .off }
        updateOverflowIndicator()
    }

    func setColor(_ color: NSColor) {
        selectedColor = color.usingColorSpace(.deviceRGB) ?? color
        paletteButton.contentTintColor = selectedColor
    }

    @objc private func toolAction(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = PDFMarkupTool(rawValue: raw) else { return }
        // Clicking the active pinned tool again returns to the pointer.
        let next: PDFMarkupTool = (tool == selectedTool && tool != .pointer) ? .pointer : tool
        setSelectedTool(next)
        onToolChanged?(next)
    }

    @objc private func paletteAction() {
        showPalette(relativeTo: paletteButton)
    }

    private func showPalette(relativeTo anchor: NSView) {
        palettePopover?.close()
        let vc = NSViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 212, height: 104))
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        let colors: [NSColor] = [
            .systemYellow, .systemGreen, .systemBlue, .systemPink,
            .systemRed, .systemOrange, .systemPurple, .systemTeal
        ]
        let names = ["琥珀黄", "翠竹绿", "晴空蓝", "珊瑚粉", "朱砂红", "暖橙色", "薰衣紫", "青绿色"]
        for row in 0..<2 {
            var rowButtons: [ColumnColorSwatchButton] = []
            for column in 0..<4 {
                let color = colors[row * 4 + column]
                let swatch = ColumnColorSwatchButton(color: color)
                swatch.toolTip = names[row * 4 + column]
                swatch.isSelectedSwatch = colorsEqual(selectedColor, color)
                swatch.target = self
                swatch.action = #selector(swatchClicked(_:))
                rowButtons.append(swatch)
            }
            grid.addRow(with: rowButtons)
        }
        grid.rowSpacing = 6
        grid.columnSpacing = 4
        container.addSubview(grid)

        let more = NSButton(title: "更多颜色…", target: self, action: #selector(moreColorsAction))
        more.bezelStyle = .inline
        more.isBordered = false
        more.font = .systemFont(ofSize: 11.5)
        more.contentTintColor = .controlAccentColor
        more.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(more)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            more.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 6),
            more.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        vc.view = container
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = vc
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        palettePopover = popover
    }

    @objc private func swatchClicked(_ sender: ColumnColorSwatchButton) {
        setColor(sender.swatchColor)
        palettePopover?.close()
        palettePopover = nil
        onColorChanged?(selectedColor)
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
        setColor(sender.color)
        onColorChanged?(selectedColor)
    }

    private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let l = lhs.usingColorSpace(.deviceRGB), let r = rhs.usingColorSpace(.deviceRGB) else { return false }
        return abs(l.redComponent - r.redComponent) < 0.01 &&
            abs(l.greenComponent - r.greenComponent) < 0.01 &&
            abs(l.blueComponent - r.blueComponent) < 0.01
    }
}
