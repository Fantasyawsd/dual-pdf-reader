import Cocoa
import PDFKit

/// The reader owns zoom and horizontal placement. PDFKit renders the pages with
/// an explicit scale; its fit-page heuristic does not participate in resizing.
final class PDFViewportLayout {
    static let horizontalInset: CGFloat = 8
    private weak var measuredDocument: PDFDocument?
    private var measuredBox: PDFDisplayBox?
    private var pageWidth: CGFloat = 0
    private(set) var fitsWidth = true

    func fittingScale(in view: PDFView) -> CGFloat? {
        guard let document = view.document, document.pageCount > 0, view.bounds.width > 0 else { return nil }
        if measuredDocument !== document || measuredBox != view.displayBox {
            measuredDocument = document
            measuredBox = view.displayBox
            pageWidth = 0
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: view.displayBox)
                let rotation = ((page.rotation % 360) + 360) % 360
                let width = rotation == 90 || rotation == 270 ? bounds.height : bounds.width
                if width.isFinite { pageWidth = max(pageWidth, width) }
            }
        }
        guard pageWidth > 0 else { return nil }
        let viewportWidth = view.internalPDFScrollView?.contentView.frame.width ?? view.bounds.width
        let inset = min(Self.horizontalInset, viewportWidth * 0.1)
        return max(0.001, (viewportWidth - 2 * inset) / pageWidth)
    }

    func apply(_ state: PDFColumnReadingState, in column: CleanPDFColumnView) {
        let view = column.pdfView
        fitsWidth = state.autoScales
        view.autoScales = false
        view.minScaleFactor = 0.001
        view.maxScaleFactor = 64
        if state.autoScales, let scale = fittingScale(in: view) {
            view.scaleFactor = scale
        } else if state.scaleFactor.isFinite, state.scaleFactor > 0 {
            view.scaleFactor = CGFloat(min(64, max(0.001, state.scaleFactor)))
        }
        view.layoutDocumentView()
    }

    /// Clip bounds are in unscaled document coordinates. Centering a small PDF
    /// requires a negative x origin; clamping x to zero left-aligns the page.
    static func centeredX(in column: CleanPDFColumnView) -> CGFloat? {
        guard let scroll = column.internalScrollView(), let documentView = scroll.documentView,
              let page = column.pdfView.document?.page(at: 0) else { return nil }
        let pageRect = documentView.convert(column.pdfView.convert(page.bounds(for: column.pdfView.displayBox), from: page), from: column.pdfView)
        let x = pageRect.midX - scroll.contentView.bounds.width / 2
        return x.isFinite ? x : nil
    }

    @discardableResult
    static func centerHorizontally(in column: CleanPDFColumnView) -> Bool {
        guard let scroll = column.internalScrollView(), let x = centeredX(in: column),
              abs(scroll.contentView.bounds.minX - x) > 0.000_001 else { return false }
        scroll.contentView.scroll(to: NSPoint(x: x, y: scroll.contentView.bounds.minY))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }
}

private extension PDFView {
    var internalPDFScrollView: NSScrollView? {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews { if let scroll = find(child) { return scroll } }
            return nil
        }
        return find(self)
    }
}
