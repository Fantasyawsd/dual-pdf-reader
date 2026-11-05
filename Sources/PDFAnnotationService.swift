import PDFKit

enum PDFSelectionAnnotationFactory {
    static func make(selection: PDFSelection, document: PDFDocument, side: PDFSide,
                     pdfDocumentId: String? = nil,
                     color: HighlightColor, note: String, linkedURL: String?, linkedTitle: String?,
                     kind: PaperAnnotationKind = .highlight, colorHex: String? = nil) -> PaperAnnotation? {
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
        annotation.kind = kind
        annotation.colorHex = colorHex
        if regions.count > 1 { annotation.additionalPageRegions = Array(regions.dropFirst()) }
        return annotation
    }
}

/// Updates only changed annotations, keeping PDFKit work proportional to the edit.
final class PDFAnnotationRenderer {
    private final class Rendered {
        weak var page: PDFPage?
        let annotation: PDFAnnotation

        init(page: PDFPage, annotation: PDFAnnotation) {
            self.page = page
            self.annotation = annotation
        }
    }

    private final class State {
        weak var document: PDFDocument?
        var models: [String: PaperAnnotation] = [:]
        var rendered: [String: [Rendered]] = [:]
        var hidden: Set<String> = []
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
            for rendered in state.rendered.removeValue(forKey: id) ?? [] {
                guard let page = rendered.page else { continue }
                page.removeAnnotation(rendered.annotation)
                column.pdfView.annotationsChanged(on: page)
            }
        }
        for (id, model) in models where state.models[id] != model {
            let rendered = render(model, in: document)
            if !state.hidden.contains(id) {
                for item in rendered {
                    guard let page = item.page else { continue }
                    page.addAnnotation(item.annotation)
                    column.pdfView.annotationsChanged(on: page)
                }
            }
            state.rendered[id] = rendered
        }
        state.models = models
        state.hidden.formIntersection(Set(models.keys))
        column.pdfView.needsDisplay = true
    }

    func setHidden(_ ids: Set<String>, in column: CleanPDFColumnView) {
        let key = ObjectIdentifier(column)
        guard let state = states[key], state.document === column.pdfView.document else { return }
        for id in ids where !state.hidden.contains(id) {
            state.hidden.insert(id)
            for item in state.rendered[id] ?? [] {
                guard let page = item.page else { continue }
                page.removeAnnotation(item.annotation)
                column.pdfView.annotationsChanged(on: page)
            }
        }
        for id in state.hidden.subtracting(ids) {
            state.hidden.remove(id)
            for item in state.rendered[id] ?? [] {
                guard let page = item.page,
                      !page.annotations.contains(where: { $0 === item.annotation }) else { continue }
                page.addAnnotation(item.annotation)
                column.pdfView.annotationsChanged(on: page)
            }
        }
        column.pdfView.needsDisplay = true
    }

    private func render(_ model: PaperAnnotation, in document: PDFDocument) -> [Rendered] {
        if model.effectiveKind.isTextMarkup {
            return model.pageRegions.compactMap { region in
                guard region.pageIndex >= 0, region.pageIndex < document.pageCount,
                      let page = document.page(at: region.pageIndex), !region.rects.isEmpty else { return nil }
                let rects = region.rects.map(\.cgRect)
                let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
                let subtype: PDFAnnotationSubtype
                switch model.effectiveKind {
                case .highlight: subtype = .highlight
                case .underline: subtype = .underline
                case .strikethrough: subtype = .strikeOut
                default: return nil
                }
                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.quadrilateralPoints = rects.flatMap { rect in
                    let local = NSRect(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY,
                                       width: rect.width, height: rect.height)
                    return [
                        NSValue(point: NSPoint(x: local.minX, y: local.maxY)),
                        NSValue(point: NSPoint(x: local.maxX, y: local.maxY)),
                        NSValue(point: NSPoint(x: local.minX, y: local.minY)),
                        NSValue(point: NSPoint(x: local.maxX, y: local.minY))
                    ]
                }
                let alpha: CGFloat = model.effectiveKind == .highlight ? 0.35 : 1
                annotation.color = model.displayColor.withAlphaComponent(alpha)
                annotation.contents = annotationContents(for: model)
                annotation.userName = "DualPDF_CustomAnnot"
                return Rendered(page: page, annotation: annotation)
            }
        }

        guard model.pageIndex >= 0, model.pageIndex < document.pageCount,
              let page = document.page(at: model.pageIndex),
              let rect = model.rects.first?.cgRect else { return [] }
        let annotation: PDFAnnotation
        switch model.effectiveKind {
        case .ink:
            guard let paths = model.inkPaths, !paths.isEmpty else { return [] }
            let points = paths.flatMap { $0.map(\.cgPoint) }
            guard let first = points.first else { return [] }
            let pathBounds = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
            let width = CGFloat(model.strokeWidth ?? 2)
            let bounds = pathBounds.insetBy(dx: -(width + 2), dy: -(width + 2))
            annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            for points in paths where !points.isEmpty {
                let path = NSBezierPath()
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = width
                path.move(to: CGPoint(x: points[0].x - Double(bounds.minX),
                                      y: points[0].y - Double(bounds.minY)))
                for point in points.dropFirst() {
                    path.line(to: CGPoint(x: point.x - Double(bounds.minX),
                                          y: point.y - Double(bounds.minY)))
                }
                annotation.add(path)
            }
            let border = PDFBorder()
            border.lineWidth = width
            annotation.border = border
            annotation.color = model.displayColor
        case .rectangle, .ellipse:
            annotation = PDFAnnotation(bounds: rect, forType: model.effectiveKind == .rectangle ? .square : .circle,
                                       withProperties: nil)
            let border = PDFBorder()
            border.lineWidth = CGFloat(model.strokeWidth ?? 1.6)
            annotation.border = border
            annotation.color = model.displayColor
            annotation.interiorColor = model.displayColor.withAlphaComponent(0.06)
        case .line, .arrow:
            guard let start = model.startPoint?.cgPoint, let end = model.endPoint?.cgPoint else { return [] }
            let width = CGFloat(model.strokeWidth ?? 1.6)
            let bounds = rect.insetBy(dx: -(width + 2), dy: -(width + 2))
            annotation = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            annotation.startPoint = NSPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
            annotation.endPoint = NSPoint(x: end.x - bounds.minX, y: end.y - bounds.minY)
            annotation.startLineStyle = .none
            annotation.endLineStyle = model.effectiveKind == .arrow ? .closedArrow : .none
            let border = PDFBorder()
            border.lineWidth = width
            annotation.border = border
            annotation.color = model.displayColor
        case .text:
            annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            annotation.contents = model.selectedText
            annotation.font = .systemFont(ofSize: 12)
            annotation.fontColor = readableTextColor(model.displayColor)
            annotation.color = .clear
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
        case .highlight, .underline, .strikethrough:
            return []
        }
        annotation.contents = model.effectiveKind == .text ? model.selectedText : annotationContents(for: model)
        annotation.userName = "DualPDF_CustomAnnot"
        return [Rendered(page: page, annotation: annotation)]
    }

    private func annotationContents(for model: PaperAnnotation) -> String {
        var contents = model.markdownNote
        if let link = model.linkedURL {
            contents += (contents.isEmpty ? "" : "\n") + "🔗 \(model.linkedTitle ?? link)"
        }
        return contents
    }

    func reset() { states.removeAll() }
}

func readableTextColor(_ color: NSColor) -> NSColor {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return .black }
    let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    guard luminance > 0.62 else { return rgb }
    let factor: CGFloat = 0.42
    return NSColor(calibratedRed: rgb.redComponent * factor,
                   green: rgb.greenComponent * factor,
                   blue: rgb.blueComponent * factor,
                   alpha: 1)
}
