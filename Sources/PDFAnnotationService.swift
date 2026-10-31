import PDFKit

/// 采用 CoreGraphics 正片叠底 (Multiply) 模式绘制的高亮标注。
/// 彻底解决普通 Alpha 混合模式下黑色文字发灰发暗、对比度受损、遮挡文字的缺陷。
/// 在正片叠底模式下：黑色文字 (0.0) 乘以任何高亮色结果恒为 0.0（保持 100% 绝对纯黑锐利），
/// 白色纸面 (1.0) 呈现饱和通透的荧光底色。
final class MultiplyHighlightAnnotation: PDFAnnotation {
    var hasCommentBadge: Bool = false
    var badgeColor: NSColor = .systemYellow

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()

        // 1. 正片叠底模式绘制高亮色块
        context.setBlendMode(.multiply)
        context.setFillColor(color.cgColor)

        let cornerRadius: CGFloat = min(2.0, bounds.height * 0.15)
        let highlightPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        context.addPath(highlightPath)
        context.fillPath()

        // 2. 若有随手笔记或外链，在末端绘制非侵入式微型便签角标，绝不横向划破文字
        if hasCommentBadge {
            context.setBlendMode(.normal)
            let badgeSize: CGFloat = 8.0
            let badgeRect = CGRect(
                x: bounds.maxX - badgeSize * 0.7,
                y: bounds.maxY - badgeSize * 0.7,
                width: badgeSize,
                height: badgeSize
            )

            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: badgeRect)

            context.setFillColor(badgeColor.cgColor)
            context.fillEllipse(in: badgeRect.insetBy(dx: 1.0, dy: 1.0))
        }

        context.restoreGState()
    }
}

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
            let hasNoteOrLink = !model.markdownNote.isEmpty || model.linkedURL != nil
            let allRegions = model.pageRegions
            for (regionIdx, region) in allRegions.enumerated() {
                guard region.pageIndex >= 0, region.pageIndex < document.pageCount,
                      let page = document.page(at: region.pageIndex) else { continue }
                for (rectIdx, rect) in region.rects.enumerated() {
                    let isLast = (regionIdx == allRegions.count - 1 && rectIdx == region.rects.count - 1)
                    let highlight = MultiplyHighlightAnnotation(bounds: rect.cgRect, forType: .highlight, withProperties: nil)
                    highlight.color = model.color.nsColor
                    highlight.userName = "DualPDF_CustomAnnot"
                    highlight.hasCommentBadge = isLast && hasNoteOrLink
                    highlight.badgeColor = model.color.solidColor

                    var tooltip = model.markdownNote
                    if let link = model.linkedURL { tooltip += (tooltip.isEmpty ? "" : "\n") + "🔗 \(model.linkedTitle ?? link)" }
                    highlight.contents = tooltip
                    page.addAnnotation(highlight)
                    rendered.append(highlight)
                }
            }
            state.rendered[id] = rendered
        }
        state.models = models
        column.pdfView.needsDisplay = true
    }

    func reset() { states.removeAll() }
}
