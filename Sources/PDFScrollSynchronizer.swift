import Cocoa
import PDFKit

enum PDFScrollSynchronizer {
    static func capture(in column: CleanPDFColumnView) -> PDFColumnReadingState? {
        guard column.pdfView.bounds.width > 0, column.pdfView.bounds.height > 0,
              let position = continuousPosition(in: column), position.isFinite,
              column.internalScrollView()?.documentView != nil else { return nil }
        return PDFColumnReadingState(pdfDocumentId: column.activePDFDocumentId, continuousPage: position,
            autoScales: column.viewportLayout.fitsWidth, scaleFactor: Double(column.pdfView.scaleFactor),
            horizontalScrollFraction: 0.5)
    }

    @discardableResult
    static func restore(_ state: PDFColumnReadingState, in column: CleanPDFColumnView) -> Bool {
        guard state.pdfDocumentId == column.activePDFDocumentId, column.pdfView.document != nil,
              state.continuousPage.isFinite else { return false }
        column.viewportLayout.apply(state, in: column)
        return self.scroll(to: state.continuousPage, in: column)
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
    static func scroll(to position: Double, in column: CleanPDFColumnView) -> Bool {
        guard position.isFinite, let document = column.pdfView.document, document.pageCount > 0,
              let scroll = column.internalScrollView(), let documentView = scroll.documentView,
              scroll.contentView.bounds.width > 0, scroll.contentView.bounds.height > 0 else { return false }
        let clamped = min(max(position, 0), Double(document.pageCount))
        let index = min(Int(floor(clamped)), document.pageCount - 1)
        guard let rect = pageRectInDocView(index, in: column) else { return false }
        let centerY = rect.origin.y + CGFloat(clamped - Double(index)) * pageStepHeight(index, in: column)
        let availableY = documentView.frame.height - scroll.contentView.bounds.height
        let y = availableY > 0 ? min(max(centerY - scroll.contentView.bounds.height / 2, 0), availableY) : availableY / 2
        let x = PDFViewportLayout.centeredX(in: column) ?? 0
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
        let maximumSourceY = sourceView.frame.height - sourceBounds.height
        let maximumTargetY = targetView.frame.height - targetBounds.height
        if let position = continuousPosition(in: source) {
            let proposed = position + offset
            // Short docs clamp continuous coords well before scroll Y hits the
            // document end (centering pageCount still leaves margin below the
            // last page). If the target implies a source position outside
            // [0, pageCount], do not drag the longer column backward/forward.
            if let targetCurrent = continuousPosition(in: target) {
                let sourceCount = Double(source.pdfView.document?.pageCount ?? 0)
                let idealSource = targetCurrent - offset
                let y = sourceBounds.origin.y
                let continuousClampedEnd = idealSource > sourceCount - 0.01
                let continuousClampedStart = idealSource < 0.01
                let scrollClampedEnd = maximumSourceY > 1 && y >= maximumSourceY - 1
                let scrollClampedStart = maximumSourceY > 1 && y <= 1
                if (continuousClampedEnd || scrollClampedEnd) && targetCurrent > proposed + 0.05 { return }
                if (continuousClampedStart || scrollClampedStart) && targetCurrent < proposed - 0.05 { return }
            }
            if scroll(to: proposed, in: target) { return }
        }
        guard maximumSourceY > 0, maximumTargetY > 0 else { return }
        targetScroll.contentView.scroll(to: NSPoint(x: PDFViewportLayout.centeredX(in: target) ?? 0,
            y: min(1, max(0, sourceBounds.origin.y / maximumSourceY)) * maximumTargetY))
        targetScroll.reflectScrolledClipView(targetScroll.contentView)
    }


}
