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
