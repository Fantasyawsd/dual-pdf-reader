import Cocoa

/// Brackets AppKit geometry changes before PDFKit receives a zero/narrow viewport.
final class ReaderRootView: NSView {
    var onGeometryWillChange: (() -> Void)?
    var onGeometryDidChange: (() -> Void)?
    var onLayout: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        if changed { onGeometryWillChange?() }
        super.setFrameSize(newSize)
        if changed { onGeometryDidChange?() }
    }

    override func layout() {
        onLayout?()
        super.layout()
    }
}

class ReaderGeometrySplitView: NSSplitView {
    var onGeometryWillChange: (() -> Void)?
    var onGeometryDidChange: (() -> Void)?
    var onDividerDragEnded: (() -> Void)?
    private(set) var isTrackingDivider = false

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        if changed { onGeometryWillChange?() }
        super.setFrameSize(newSize)
        if changed { onGeometryDidChange?() }
    }

    override func adjustSubviews() {
        onGeometryWillChange?()
        super.adjustSubviews()
        onGeometryDidChange?()
    }

    override func mouseDown(with event: NSEvent) {
        onGeometryWillChange?()
        isTrackingDivider = true
        super.mouseDown(with: event)
        isTrackingDivider = false
        onDividerDragEnded?()
        onGeometryDidChange?()
    }
}

final class DualPDFSplitView: ReaderGeometrySplitView {
    var onDividerDoubleClicked: (() -> Void)?
    var splitRatioProvider: (() -> CGFloat)?
    var onSplitRatioChanged: ((CGFloat) -> Void)?

    override var dividerThickness: CGFloat {
        let visibleCount = subviews.filter { !$0.isHidden }.count
        return visibleCount > 1 ? 1.0 : 0.0
    }

    override var dividerColor: NSColor {
        let visibleCount = subviews.filter { !$0.isHidden }.count
        return visibleCount > 1 ? super.dividerColor : .clear
    }

    override func drawDivider(in rect: NSRect) {
        let visibleCount = subviews.filter { !$0.isHidden }.count
        guard visibleCount > 1 else { return }
        super.drawDivider(in: rect)
    }

    override func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        guard dividerIndex == 0 else {
            super.setPosition(position, ofDividerAt: dividerIndex)
            return
        }
        guard position.isFinite, bounds.width > dividerThickness, subviews.filter({ !$0.isHidden }).count == 2 else { return }
        let total = bounds.width - dividerThickness
        let effectiveMinW = min(200, max(0, total / 2))
        let minRatio = effectiveMinW / total
        let maxRatio = (total - effectiveMinW) / total
        let ratio = max(minRatio, min(maxRatio, position / total))
        onSplitRatioChanged?(ratio)
        adjustSubviews()
    }

    override func adjustSubviews() {
        onGeometryWillChange?()
        defer { onGeometryDidChange?() }
        guard bounds.width > 0, bounds.height > 0 else {
            super.adjustSubviews()
            return
        }
        let visibleSubviews = subviews.filter { !$0.isHidden }
        if visibleSubviews.count == 1 {
            if subviews.count >= 2 {
                if subviews[0].isHidden {
                    subviews[0].frame = NSRect(x: 0, y: 0, width: 0, height: bounds.height)
                    subviews[1].frame = bounds
                } else {
                    subviews[0].frame = bounds
                    subviews[1].frame = NSRect(x: bounds.width, y: 0, width: 0, height: bounds.height)
                }
            } else if let singleView = visibleSubviews.first {
                singleView.frame = bounds
            }
            return
        }
        if subviews.count == 2 && !subviews[0].isHidden && !subviews[1].isHidden {
            let requestedRatio = splitRatioProvider?() ?? 0.5
            let ratio = requestedRatio.isFinite ? min(1, max(0, requestedRatio)) : 0.5
            let total = max(0, bounds.width - dividerThickness)
            let effectiveMinW = min(200, max(0, total / 2))
            let w0 = max(effectiveMinW, min(total - effectiveMinW, round(total * ratio)))
            let w1 = max(0, total - w0)
            subviews[0].frame = NSRect(x: 0, y: 0, width: w0, height: bounds.height)
            subviews[1].frame = NSRect(x: w0 + dividerThickness, y: 0, width: w1, height: bounds.height)
            return
        }
        super.adjustSubviews()
    }

    override func mouseDown(with event: NSEvent) {
        let visibleCount = subviews.filter { !$0.isHidden }.count
        guard visibleCount > 1 else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            if subviews.count >= 2 {
                let divX = subviews[0].frame.maxX
                let dividerHitZone = NSRect(
                    x: divX - 8,
                    y: 0,
                    width: max(dividerThickness, 6) + 16,
                    height: bounds.height
                )
                if dividerHitZone.contains(point) {
                    onDividerDoubleClicked?()
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}
