import PDFKit

enum PDFSelectionAnnotationFactory {
    static func make(selection: PDFSelection, document: PDFDocument, side: PDFSide,
                     pdfDocumentId: String? = nil,
                     color: HighlightColor, note: String, linkedURL: String?, linkedTitle: String?) -> PaperAnnotation? {
        guard let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let lines = selection.selectionsByLine()
        let regions = selection.pages.compactMap { page -> AnnotationPageRegion? in
            let index = document.index(for: page)
            guard index != NSNotFound else { return nil }
            var rects = lines.filter { $0.pages.contains(page) }.map { RectCodable($0.bounds(for: page)) }
            if rects.isEmpty { rects = [RectCodable(selection.bounds(for: page))] }
            return AnnotationPageRegion(pageIndex: index, rects: rects)
        }.sorted { $0.pageIndex < $1.pageIndex }
        guard let first = regions.first else { return nil }
        var annotation = PaperAnnotation(side: side, pageIndex: first.pageIndex, rects: first.rects,
            selectedText: text, color: color, markdownNote: note, linkedURL: linkedURL, linkedTitle: linkedTitle,
            pdfDocumentId: pdfDocumentId ?? side.rawValue)
        if regions.count > 1 { annotation.additionalPageRegions = Array(regions.dropFirst()) }
        return annotation
    }
}

/// Updates only changed annotations, keeping PDFKit work proportional to the edit.
final class PDFAnnotationRenderer {
    private final class State {
        weak var document: PDFDocument?
        var models: [String: PaperAnnotation] = [:]
        var rendered: [String: [PDFAnnotation]] = [:]
        init(document: PDFDocument) { self.document = document }
    }
    private var states: [ObjectIdentifier: State] = [:]

    func apply(_ annotations: [PaperAnnotation], to column: CleanPDFColumnView) {
        let activePDFId = column.activePDFDocumentId
        let selected = annotations.filter { $0.effectivePDFId == activePDFId }
        column.pdfView.storedAnnotations = selected
        let colKey = ObjectIdentifier(column)
        guard column.contentSource.isPDF, let document = column.pdfView.document else {
            states.removeValue(forKey: colKey)
            return
        }
        let state: State
        if let existing = states[colKey], existing.document === document { state = existing }
        else { state = State(document: document); states[colKey] = state }
        let models = Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, old) in state.models where models[id] != old {
            for rendered in state.rendered.removeValue(forKey: id) ?? [] { rendered.page?.removeAnnotation(rendered) }
        }
        for (id, model) in models where state.models[id] != model {
            var rendered: [PDFAnnotation] = []
            let allRegions = model.pageRegions
            for region in allRegions {
                guard region.pageIndex >= 0, region.pageIndex < document.pageCount,
                      let page = document.page(at: region.pageIndex),
                      !region.rects.isEmpty else { continue }

                // 计算该页所有选区行的高亮总包围盒（Union Bounds）
                let allRects = region.rects.map(\.cgRect)
                var unionBounds = allRects[0]
                for r in allRects.dropFirst() {
                    unionBounds = unionBounds.union(r)
                }

                // 核心：构建 PDF 标准四边形点集（quadrilateralPoints）
                // 坐标以 unionBounds.origin 为基准（相对坐标），每个文本行对应 4 个点（Z字型顺序：左上、右上、左下、右下）
                // 这样多行选区仅生成一个统一的 PDFAnnotation 对象，彻底杜绝“每行单独标注”与视觉破碎；
                // 且带有 quadrilateralPoints 的 Highlight 会触发 PDFKit 原生正片叠底通道，黑色正文 100% 锐利保真！
                var quadPoints: [NSValue] = []
                for lineRect in allRects {
                    let rx = lineRect.origin.x - unionBounds.origin.x
                    let ry = lineRect.origin.y - unionBounds.origin.y
                    let w = lineRect.width
                    let h = lineRect.height

                    quadPoints.append(NSValue(point: NSPoint(x: rx, y: ry + h)))
                    quadPoints.append(NSValue(point: NSPoint(x: rx + w, y: ry + h)))
                    quadPoints.append(NSValue(point: NSPoint(x: rx, y: ry)))
                    quadPoints.append(NSValue(point: NSPoint(x: rx + w, y: ry)))
                }

                let highlight = PDFAnnotation(bounds: unionBounds, forType: .highlight, withProperties: nil)
                highlight.quadrilateralPoints = quadPoints
                highlight.color = model.color.nsColor
                highlight.userName = "DualPDF_CustomAnnot"

                var tooltip = model.markdownNote
                if let link = model.linkedURL {
                    tooltip += (tooltip.isEmpty ? "" : "\n") + "🔗 \(model.linkedTitle ?? link)"
                }
                highlight.contents = tooltip

                page.addAnnotation(highlight)
                rendered.append(highlight)
            }
            state.rendered[id] = rendered
        }
        state.models = models
        column.pdfView.needsDisplay = true
    }

    func reset() { states.removeAll() }
}
