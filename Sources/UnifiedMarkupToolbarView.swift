import Cocoa

/// One shared markup toolbar for both PDF columns. Tool and color choices are
/// applied to both panes by the reader; undo/redo target the active pane.
final class UnifiedMarkupToolbarView: NSView {
    var onToolChanged: ((PDFMarkupTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?

    private(set) var selectedTool: PDFMarkupTool = .pointer
    private(set) var selectedColor: NSColor = .systemYellow

    private let stack = NSStackView()
    private let paletteButton = ModernHoverButton()
    private var toolButtons: [PDFMarkupTool: ModernHoverButton] = [:]
    private var undoButton: ModernHoverButton?
    private var redoButton: ModernHoverButton?
    private var palettePopover: NSPopover?
    private var contentViews: [NSView] = []

    var toolTipsForTesting: [String] {
        toolButtons.values.compactMap { $0.toolTip } +
            [paletteButton.toolTip, undoButton?.toolTip, redoButton?.toolTip].compactMap { $0 }
    }
    var selectedToolForTesting: PDFMarkupTool { selectedTool }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let tools: [(PDFMarkupTool, [String])] = [
            (.pointer, ["cursorarrow"]),
            (.highlight, ["highlighter"]),
            (.underline, ["underline"]),
            (.strikethrough, ["strikethrough"]),
            (.ink, ["pencil.tip", "pencil"]),
            (.eraser, ["eraser", "eraser.fill"]),
            (.text, ["character.textbox", "textformat"]),
            (.rectangle, ["rectangle"]),
            (.ellipse, ["circle"]),
            (.line, ["line.diagonal", "minus"]),
            (.arrow, ["arrow.up.right", "arrow.right"])
        ]
        for (index, item) in tools.enumerated() {
            let (tool, symbols) = item
            if index == 1 || index == 7 {
                contentViews.append(makeSeparator())
            }
            let button = ModernHoverButton()
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.pushOnPushOff)
            button.isToggleButton = true
            button.imagePosition = .imageOnly
            button.image = columnToolbarSymbol(symbols, pointSize: 13, weight: .medium)
            button.toolTip = tool.displayName
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            button.target = self
            button.action = #selector(toolAction(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 26),
                button.heightAnchor.constraint(equalToConstant: 26)
            ])
            toolButtons[tool] = button
            contentViews.append(button)
        }

        contentViews.append(makeSeparator())
        paletteButton.bezelStyle = .inline
        paletteButton.isBordered = false
        paletteButton.setButtonType(.momentaryPushIn)
        paletteButton.imagePosition = .imageOnly
        paletteButton.image = columnToolbarSymbol(["paintpalette", "circle.grid.hex"], pointSize: 13, weight: .medium)
        paletteButton.toolTip = "选择颜色"
        paletteButton.target = self
        paletteButton.action = #selector(paletteAction)
        paletteButton.translatesAutoresizingMaskIntoConstraints = false
        paletteButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        paletteButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        contentViews.append(paletteButton)

        let undo = makeIconButton(symbols: ["arrow.uturn.backward"], tip: "撤销", action: #selector(undoAction))
        let redo = makeIconButton(symbols: ["arrow.uturn.forward"], tip: "重做", action: #selector(redoAction))
        undoButton = undo
        redoButton = redo
        contentViews.append(undo)
        contentViews.append(redo)

        for view in contentViews { stack.addArrangedSubview(view) }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 30)
        ])
        setSelectedTool(.pointer)
        setUndoRedoEnabled(canUndo: false, canRedo: false)
    }

    private func makeIconButton(symbols: [String], tip: String, action: Selector) -> ModernHoverButton {
        let button = ModernHoverButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.image = columnToolbarSymbol(symbols, pointSize: 13, weight: .medium)
        button.toolTip = tip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 15).isActive = true
        return box
    }

    func setSelectedTool(_ tool: PDFMarkupTool) {
        selectedTool = tool
        for (key, button) in toolButtons { button.state = key == tool ? .on : .off }
    }

    func setColor(_ color: NSColor) {
        selectedColor = color.usingColorSpace(.deviceRGB) ?? color
        paletteButton.contentTintColor = selectedColor
    }

    func setUndoRedoEnabled(canUndo: Bool, canRedo: Bool) {
        undoButton?.isEnabled = canUndo
        redoButton?.isEnabled = canRedo
        undoButton?.alphaValue = canUndo ? 1 : 0.38
        redoButton?.alphaValue = canRedo ? 1 : 0.38
    }

    @objc private func toolAction(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = PDFMarkupTool(rawValue: raw) else { return }
        setSelectedTool(tool)
        onToolChanged?(tool)
    }

    @objc private func undoAction() { onUndo?() }
    @objc private func redoAction() { onRedo?() }

    @objc private func paletteAction() {
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
        popover.show(relativeTo: paletteButton.bounds, of: paletteButton, preferredEdge: .maxY)
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
