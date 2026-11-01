import Cocoa
import PDFKit

enum PDFScrollSynchronizer {
    static func capture(in column: CleanPDFColumnView) -> PDFColumnReadingState? {
        guard column.pdfView.bounds.width > 0, column.pdfView.bounds.height > 0,
              let position = continuousPosition(in: column), position.isFinite,
              let scroll = column.internalScrollView(), let documentView = scroll.documentView else { return nil }
        let maximumX = max(0, documentView.frame.width - scroll.contentView.bounds.width)
        let fraction = maximumX > 0 ? min(1, max(0, scroll.contentView.bounds.minX / maximumX)) : 0
        return PDFColumnReadingState(pdfDocumentId: column.activePDFDocumentId, continuousPage: position,
            autoScales: column.pdfView.autoScales, scaleFactor: Double(column.pdfView.scaleFactor),
            horizontalScrollFraction: Double(fraction))
    }

    @discardableResult
    static func restore(_ state: PDFColumnReadingState, in column: CleanPDFColumnView) -> Bool {
        guard state.pdfDocumentId == column.activePDFDocumentId, column.pdfView.document != nil,
              state.continuousPage.isFinite else { return false }
        column.pdfView.autoScales = state.autoScales
        if !state.autoScales, state.scaleFactor.isFinite {
            column.pdfView.scaleFactor = CGFloat(min(5, max(0.25, state.scaleFactor)))
        }
        column.pdfView.layoutDocumentView()
        let scroll = column.internalScrollView()
        let maximumX = max(0, (scroll?.documentView?.frame.width ?? 0) - (scroll?.contentView.bounds.width ?? 0))
        let x = state.horizontalScrollFraction.flatMap { $0.isFinite ? CGFloat(min(1, max(0, $0))) * maximumX : nil }
        return self.scroll(to: state.continuousPage, in: column, horizontalOffset: x)
    }

    private static func pageRectInDocView(_ pageIndex: Int, in col: CleanPDFColumnView) -> NSRect? {
        guard let sv = col.internalScrollView(),
              let docView = sv.documentView,
              let doc = col.pdfView.document,
              pageIndex >= 0, pageIndex < doc.pageCount,
              let page = doc.page(at: pageIndex) else { return nil }
        let rectInView = col.pdfView.convert(page.bounds(for: col.pdfView.displayBox), from: page)
        let rect = docView.convert(rectInView, from: col.pdfView)
        guard rect.minY.isFinite, rect.height.isFinite, rect.height > 0 else { return nil }
        return rect
    }

    private static func pageStepHeight(_ pageIndex: Int, in col: CleanPDFColumnView) -> CGFloat {
        guard let r = pageRectInDocView(pageIndex, in: col) else { return 1.0 }
        if let doc = col.pdfView.document, pageIndex + 1 < doc.pageCount,
           let nextR = pageRectInDocView(pageIndex + 1, in: col) {
            let stride = nextR.origin.y - r.origin.y
            if stride > 1.0 { return stride }
        }
        return max(1.0, r.height)
    }

    /// 计算视口中心点在连续页面坐标系中的精确位置（包含页间距步长，跨页滚动零跳变）
    static func continuousPosition(in col: CleanPDFColumnView) -> Double? {
        guard let sv = col.internalScrollView(),
              let doc = col.pdfView.document,
              doc.pageCount > 0, sv.contentView.bounds.height > 0 else { return nil }
        let midY = sv.contentView.bounds.midY
        guard midY.isFinite else { return nil }
        // Find by vertical geometry: currentPage / nearest page can lag behind a
        // scroll and can select the wrong page when the pointer is in a wide margin.
        var lower = 0
        var upper = doc.pageCount
        while lower + 1 < upper {
            let middle = lower + (upper - lower) / 2
            guard let rect = pageRectInDocView(middle, in: col) else { return nil }
            if rect.minY <= midY { lower = middle } else { upper = middle }
        }
        let pageIdx = lower
        guard let rectInDoc = pageRectInDocView(pageIdx, in: col) else { return Double(pageIdx) }
        let stepH = pageStepHeight(pageIdx, in: col)
        let ratioInPage = Double((midY - rectInDoc.origin.y) / stepH)
        return min(Double(doc.pageCount), max(0, Double(pageIdx) + ratioInPage))
    }


    @discardableResult
    static func scroll(to position: Double, in column: CleanPDFColumnView, horizontalOffset: CGFloat? = nil) -> Bool {
        guard position.isFinite, let document = column.pdfView.document, document.pageCount > 0,
              let scroll = column.internalScrollView(), let documentView = scroll.documentView,
              scroll.contentView.bounds.width > 0, scroll.contentView.bounds.height > 0 else { return false }
        let clamped = min(max(position, 0), Double(document.pageCount))
        let index = min(Int(floor(clamped)), document.pageCount - 1)
        guard let rect = pageRectInDocView(index, in: column) else { return false }
        let centerY = rect.origin.y + CGFloat(clamped - Double(index)) * pageStepHeight(index, in: column)
        let maximumY = max(0, documentView.frame.height - scroll.contentView.bounds.height)
        let y = min(max(centerY - scroll.contentView.bounds.height / 2, 0), maximumY)
        let maximumX = max(0, documentView.frame.width - scroll.contentView.bounds.width)
        let desiredX = horizontalOffset ?? scroll.contentView.bounds.origin.x
        let x = desiredX.isFinite ? min(maximumX, max(0, desiredX)) : 0
        guard x.isFinite, y.isFinite else { return false }
        scroll.contentView.scroll(to: NSPoint(x: x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }

    static func synchronize(from source: CleanPDFColumnView, to target: CleanPDFColumnView, offset: Double) {
        guard offset.isFinite, source !== target,
              (source.pdfView.document?.pageCount ?? 0) > 0, (target.pdfView.document?.pageCount ?? 0) > 0,
              let sourceScroll = source.internalScrollView(), let targetScroll = target.internalScrollView(),
              let sourceView = sourceScroll.documentView, let targetView = targetScroll.documentView else { return }
        let sourceBounds = sourceScroll.contentView.bounds
        let targetBounds = targetScroll.contentView.bounds
        let maximumSourceX = max(1, sourceView.frame.width - sourceBounds.width)
        let maximumTargetX = max(0, targetView.frame.width - targetBounds.width)
        let x = min(max(sourceBounds.origin.x / maximumSourceX * maximumTargetX, 0), maximumTargetX)
        if let position = continuousPosition(in: source),
           scroll(to: position + offset, in: target, horizontalOffset: x) { return }
        let maximumSourceY = sourceView.frame.height - sourceBounds.height
        let maximumTargetY = targetView.frame.height - targetBounds.height
        guard maximumSourceY > 0, maximumTargetY > 0 else { return }
        targetScroll.contentView.scroll(to: NSPoint(x: x, y: sourceBounds.origin.y / maximumSourceY * maximumTargetY))
        targetScroll.reflectScrolledClipView(targetScroll.contentView)
    }
}
