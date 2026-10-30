import Cocoa
import PDFKit
import JavaScriptCore
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

final class NonDraggableStackView: NSStackView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performTitleBarDoubleClickAction()
            return
        }
        super.mouseDown(with: event)
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
final class ZoteroTabItemView: NSControl {
    let tabId: String
    var isActiveTab: Bool {
        didSet {
            guard oldValue != isActiveTab else { return }
            titleLabel.textColor = isActiveTab ? .labelColor : .secondaryLabelColor
            titleLabel.font = isActiveTab ? .systemFont(ofSize: 13.5, weight: .semibold) : .systemFont(ofSize: 13.5, weight: .regular)
            updateCloseButtonAppearance()
            needsDisplay = true
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
    private let activeIndicator = NonDraggableView()
    private var isHovered = false {
        didSet {
            updateCloseButtonAppearance()
            needsDisplay = true
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
        wantsLayer = true

        setupSubviews(title: title, symbol: symbol, symbolTint: symbolTint)
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
        closeButton.isHidden = false
        closeButton.alphaValue = isActiveTab ? 0.88 : (isHovered ? 0.95 : 0.52)
        closeButton.contentTintColor = (isActiveTab || isHovered) ? .labelColor : .secondaryLabelColor
    }

    private func setupSubviews(title: String, symbol: String, symbolTint: NSColor) {
        activeIndicator.wantsLayer = true
        activeIndicator.layer?.cornerRadius = 1.5
        activeIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        activeIndicator.isHidden = true
        activeIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activeIndicator)

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.contentTintColor = symbolTint
        iconView.symbolConfiguration = .init(pointSize: 14.5, weight: .medium)
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
            widthAnchor.constraint(greaterThanOrEqualToConstant: isClosable ? 156 : 196),
            widthAnchor.constraint(lessThanOrEqualToConstant: isClosable ? 270 : 216),

            activeIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            activeIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activeIndicator.widthAnchor.constraint(equalToConstant: 18),
            activeIndicator.heightAnchor.constraint(equalToConstant: 2.5),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if isClosable {
            closeButton.bezelStyle = .inline
            closeButton.isBordered = false
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")
            closeButton.symbolConfiguration = .init(pointSize: 10, weight: .bold)
            closeButton.toolTip = "关闭标签页 (⌘W / 中键点击)"
            closeButton.target = self
            closeButton.action = #selector(closeBtnClicked)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(closeButton)
            updateCloseButtonAppearance()

            NSLayoutConstraint.activate([
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 22),
                closeButton.heightAnchor.constraint(equalToConstant: 22)
            ])
        } else {
            closeButton.isHidden = true
            NSLayoutConstraint.activate([
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
            ])
        }
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

    override func updateLayer() {
        guard let layer = self.layer else { return }
        layer.cornerRadius = 6
        if isActiveTab {
            layer.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer.borderWidth = 0.8
            layer.borderColor = NSColor.separatorColor.cgColor
        } else if isHovered {
            layer.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
            layer.borderWidth = 0.5
            layer.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        } else {
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 0
            layer.borderColor = nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
        onSelect?(tabId)
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
}

// MARK: - Zotero 7 Style Unified Tab Bar Window Controller
