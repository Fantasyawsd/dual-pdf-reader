import Cocoa
import PDFKit

enum PDFScrollSynchronizer {
    private static func pageRectInDocView(_ pageIndex: Int, in col: CleanPDFColumnView) -> NSRect? {
        guard let sv = col.internalScrollView(),
              let docView = sv.documentView,
              let doc = col.pdfView.document,
              pageIndex >= 0, pageIndex < doc.pageCount,
              let page = doc.page(at: pageIndex) else { return nil }
        let rectInView = col.pdfView.convert(page.bounds(for: col.pdfView.displayBox), from: page)
        return docView.convert(rectInView, from: col.pdfView)
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
              doc.pageCount > 0 else { return nil }
        let midY = sv.contentView.bounds.midY
        let midPt = NSPoint(x: col.pdfView.bounds.midX, y: col.pdfView.bounds.midY)
        var pageIdx = col.pdfView.page(for: midPt, nearest: true).map { doc.index(for: $0) } ?? 0

        if pageIdx > 0, let r = pageRectInDocView(pageIdx, in: col), midY < r.origin.y {
            pageIdx -= 1
        } else if pageIdx + 1 < doc.pageCount,
                  let r = pageRectInDocView(pageIdx, in: col),
                  midY >= r.origin.y + pageStepHeight(pageIdx, in: col) {
            pageIdx += 1
        }

        guard let rectInDoc = pageRectInDocView(pageIdx, in: col) else { return Double(pageIdx) }
        let stepH = pageStepHeight(pageIdx, in: col)
        let ratioInPage = Double((midY - rectInDoc.origin.y) / stepH)
        return Double(pageIdx) + ratioInPage
    }


    @discardableResult
    static func scroll(to position: Double, in column: CleanPDFColumnView, horizontalOffset: CGFloat? = nil) -> Bool {
        guard position.isFinite, let document = column.pdfView.document, document.pageCount > 0,
              let scroll = column.internalScrollView(), let documentView = scroll.documentView else { return false }
        let clamped = min(max(position, 0), Double(document.pageCount))
        let index = min(Int(floor(clamped)), document.pageCount - 1)
        guard let rect = pageRectInDocView(index, in: column) else { return false }
        let centerY = rect.origin.y + CGFloat(clamped - Double(index)) * pageStepHeight(index, in: column)
        let maximumY = max(0, documentView.frame.height - scroll.contentView.bounds.height)
        let y = min(max(centerY - scroll.contentView.bounds.height / 2, 0), maximumY)
        scroll.contentView.scroll(to: NSPoint(x: horizontalOffset ?? scroll.contentView.bounds.origin.x, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }

    static func synchronize(from source: CleanPDFColumnView, to target: CleanPDFColumnView, offset: Double) {
        guard let sourceScroll = source.internalScrollView(), let targetScroll = target.internalScrollView(),
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
