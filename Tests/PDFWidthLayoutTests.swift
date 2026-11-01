import Cocoa
import PDFKit

func runPDFWidthLayoutTests(root: URL) throws {
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    func viewport(_ column: CleanPDFColumnView) -> NSRect {
        guard let clip = column.internalScrollView()?.contentView else { return .zero }
        return clip.convert(clip.bounds, to: column.pdfView)
    }
    func pages(_ column: CleanPDFColumnView) -> [NSRect] {
        guard let document = column.pdfView.document else { return [] }
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return column.pdfView.convert(page.bounds(for: column.pdfView.displayBox), from: page)
        }
    }
    func centered(_ column: CleanPDFColumnView) -> Bool {
        let center = viewport(column).midX
        return !pages(column).isEmpty && pages(column).allSatisfy { abs($0.midX - center) < 0.75 }
    }
    func fitted(_ column: CleanPDFColumnView) -> Bool {
        let width = viewport(column).width
        let expected = width - 2 * min(8, width * 0.1)
        let actual = pages(column).map(\.width).max() ?? 0
        return centered(column) && abs(actual - expected) < 1 && column.viewportLayout.fitsWidth
    }

    let source = root.appendingPathComponent("width-portrait.pdf")
    let landscape = root.appendingPathComponent("width-rotated.pdf")
    let mixed = root.appendingPathComponent("width-mixed.pdf")
    try writePDF(source, pages: 16)
    let rotated = PDFDocument(url: source)!
    for index in 0..<rotated.pageCount { rotated.page(at: index)?.rotation = 90 }
    check(rotated.write(to: landscape), "Width-layout rotated fixture writes")
    let varied = PDFDocument(url: source)!
    for index in 0..<varied.pageCount {
        if index % 2 == 0 { varied.page(at: index)?.rotation = 90 }
        else { varied.page(at: index)?.setBounds(NSRect(x: 25, y: 40, width: 430, height: 600), for: .cropBox) }
    }
    check(varied.write(to: mixed), "Width-layout mixed crop fixture writes")

    // A live resize must fit before mouse-up; a saved tiny manual zoom cannot
    // carry over into a newly sized pane. Measure rendered page edges directly.
    for (name, url) in [("portrait", source), ("landscape", landscape), ("mixed", mixed)] {
        let column = CleanPDFColumnView(side: .original)
        column.pdfView.displayBox = .cropBox
        column.pdfView.document = PDFDocument(url: url)
        column.frame = NSRect(x: 0, y: 0, width: 700, height: 820)
        column.layoutSubtreeIfNeeded()
        let coordinator = PDFViewportCoordinator(columns: [column])
        coordinator.layoutViews = { column.layoutSubtreeIfNeeded() }
        coordinator.states = ["original": PDFColumnReadingState(pdfDocumentId: "original", continuousPage: 4.5,
            autoScales: false, scaleFactor: 0.25, horizontalScrollFraction: 0)]
        coordinator.beginLayout(capture: false)
        coordinator.finishLayout()
        check(fitted(column), "\(name): reopening replaces stale zoom with a centered width fit")
        var tracking = true
        coordinator.isTrackingGeometry = { tracking }
        coordinator.beginLayout()
        var validDuringDrag = true
        for width in [CGFloat(1100), 420, 160, 55, 920, 380] {
            column.frame.size.width = width
            coordinator.scheduleCompletion()
            validDuringDrag = validDuringDrag && fitted(column) && coordinator.phase == .layout
        }
        check(validDuringDrag, "\(name): each intermediate drag width is fitted and centered before release")
        tracking = false
        coordinator.finishLayout()
        let centerBefore = viewport(column).midX
        let positionBefore = PDFScrollSynchronizer.continuousPosition(in: column)!
        PDFScrollSynchronizer.scroll(to: positionBefore, in: column)
        check(centered(column) && abs(viewport(column).midX - centerBefore) < 0.001,
            "\(name): restoring the reading position retains negative centering offsets")
        coordinator.close()
    }

    let store = LibraryStore.shared
    let paper = store.createPaper(title: "Width-fit reader integration", originalSourceURL: source)!
    _ = store.importPDF(for: paper.id, side: .translated, from: landscape)
    var saved = store.paper(withId: paper.id)!
    saved.readerState = ReaderState(
        leftColumn: PDFColumnReadingState(pdfDocumentId: "original", continuousPage: 4.5, autoScales: false, scaleFactor: 0.25),
        rightColumn: PDFColumnReadingState(pdfDocumentId: "translated", continuousPage: 6.5, autoScales: false, scaleFactor: 0.25),
        syncEnabled: false, displayMode: 2, swapped: false, splitRatio: 0.23)
    _ = store.savePaper(saved, notify: false)
    let reader = ReaderTabViewController(paperId: paper.id)
    defer { reader.prepareForClose() }
    reader.view.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    reader.view.layoutSubtreeIfNeeded()
    settle()
    check(fitted(reader.leftCol) && fitted(reader.rightCol), "Both asymmetric panes open at their own width fit")

    var allRatiosFit = true
    var sidebarKeepsRatio = true
    for ratio in [CGFloat(0.05), 0.15, 0.35, 0.8, 0.95, 0.5] {
        let split = reader.dualSplitView
        split.setPosition((split.bounds.width - split.dividerThickness) * ratio, ofDividerAt: 0)
        reader.leftCol.pdfView.onInteraction?()
        allRatiosFit = allRatiosFit && fitted(reader.leftCol) && fitted(reader.rightCol)
        let canvasBefore = split.convert(split.bounds, to: reader.view)
        reader.toggleRightDrawerAction()
        let canvasAfter = split.convert(split.bounds, to: reader.view)
        let actualRatio = split.subviews[0].frame.width / (split.bounds.width - split.dividerThickness)
        sidebarKeepsRatio = sidebarKeepsRatio && abs(actualRatio - ratio) < 0.002 &&
            abs(canvasAfter.minX - canvasBefore.minX) < 0.01 && canvasAfter.maxX < canvasBefore.maxX - 200
        allRatiosFit = allRatiosFit && fitted(reader.leftCol) && fitted(reader.rightCol)
        reader.toggleRightDrawerAction()
    }
    check(allRatiosFit, "5:95 through 95:5 ratios fit and center both PDFs before and after sidebar opening")
    check(sidebarKeepsRatio, "Sidebar compresses the entire PDF canvas and preserves the internal split ratio")

    reader.syncScrollBtn.state = .on
    reader.toggleSyncScrollAction()
    let leftFit = reader.leftCol.pdfView.scaleFactor
    let rightFit = reader.rightCol.pdfView.scaleFactor
    let rightPagesBeforeZoom = pages(reader.rightCol)
    reader.leftZoomInAction()
    check(abs(reader.leftCol.pdfView.scaleFactor / leftFit - 1.15) < 0.001 &&
          abs(reader.rightCol.pdfView.scaleFactor - rightFit) < 0.001 && fitted(reader.rightCol) &&
          zip(rightPagesBeforeZoom, pages(reader.rightCol)).allSatisfy { abs($0.minY - $1.minY) < 0.01 } &&
          centered(reader.leftCol) && centered(reader.rightCol),
        "Left zoom keeps the right PDF's scale, fit mode and position with scroll sync enabled")
    reader.rightZoomOutAction()
    check(abs(reader.rightCol.pdfView.scaleFactor * 1.15 - rightFit) < 0.001 &&
          abs(reader.leftCol.pdfView.scaleFactor / leftFit - 1.15) < 0.001 &&
          centered(reader.leftCol) && centered(reader.rightCol),
        "Right zoom remains independent and both PDFs stay centered")
    reader.leftZoomFitAction()
    check(fitted(reader.leftCol) && !reader.rightCol.viewportLayout.fitsWidth &&
          abs(reader.rightCol.pdfView.scaleFactor * 1.15 - rightFit) < 0.001,
        "Left fit preserves the right PDF's manual zoom")

    reader.syncScrollBtn.state = .off
    reader.toggleSyncScrollAction()
    reader.syncScrollBtn.state = .on
    reader.toggleSyncScrollAction()
    check(fitted(reader.leftCol) && !reader.rightCol.viewportLayout.fitsWidth &&
          abs(reader.rightCol.pdfView.scaleFactor * 1.15 - rightFit) < 0.001,
        "Enabling scroll sync preserves each column's zoom mode and scale")

    for synchronized in [false, true] {
        reader.syncScrollBtn.state = synchronized ? .on : .off
        reader.toggleSyncScrollAction()
        reader.leftZoomInAction()
        let leftScale = reader.leftCol.pdfView.scaleFactor
        let rightScale = reader.rightCol.pdfView.scaleFactor
        reader.rightCol.pdfView.onInteraction?()
        reader.zoomInActiveColumnAction()
        check(abs(reader.rightCol.pdfView.scaleFactor / rightScale - 1.15) < 0.001 &&
              abs(reader.leftCol.pdfView.scaleFactor - leftScale) < 0.001,
            "Keyboard zoom targets the focused right column (sync=\(synchronized))")
        reader.zoomOutActiveColumnAction()
        check(abs(reader.rightCol.pdfView.scaleFactor - rightScale) < 0.001 &&
              abs(reader.leftCol.pdfView.scaleFactor - leftScale) < 0.001,
            "Keyboard zoom out leaves the other column unchanged (sync=\(synchronized))")
        reader.zoomFitActiveColumnAction()
        check(fitted(reader.rightCol) && !reader.leftCol.viewportLayout.fitsWidth &&
              abs(reader.leftCol.pdfView.scaleFactor - leftScale) < 0.001,
            "Keyboard fit targets only the focused column (sync=\(synchronized))")
    }

    reader.swapColumnsAction()
    let swappedLeftScale = reader.rightCol.pdfView.scaleFactor
    let swappedRightScale = reader.leftCol.pdfView.scaleFactor
    reader.leftZoomInAction()
    check(abs(reader.rightCol.pdfView.scaleFactor / swappedLeftScale - 1.15) < 0.001 &&
          abs(reader.leftCol.pdfView.scaleFactor - swappedRightScale) < 0.001,
        "After swapping columns, the left toolbar zoom targets only the visually left PDF")
    reader.swapColumnsAction()
    reader.dualSplitView.setPosition(reader.dualSplitView.bounds.width * 0.7, ofDividerAt: 0)
    reader.rightCol.pdfView.onInteraction?()
    check(fitted(reader.leftCol) && fitted(reader.rightCol), "Divider resizing resumes width fit after manual zoom")
    reader.rightZoomInAction()
    reader.toggleRightDrawerAction()
    check(fitted(reader.leftCol) && fitted(reader.rightCol), "Sidebar opening resumes width fit after manual zoom")
    let beforeClick = pages(reader.rightCol)
    reader.rightCol.pdfView.onInteraction?()
    settle()
    check(centered(reader.rightCol) && zip(beforeClick, pages(reader.rightCol)).allSatisfy { abs($0.minX - $1.minX) < 0.001 },
        "Blank focus clicks cannot left-align centered PDF pages")
}
