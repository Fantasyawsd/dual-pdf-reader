import Cocoa
import PDFKit

func runReaderCoreTests(root: URL) throws {
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    func position(_ column: CleanPDFColumnView) -> Double { PDFScrollSynchronizer.continuousPosition(in: column) ?? -100 }
    func samePosition(_ column: CleanPDFColumnView, _ expected: Double) -> Bool { abs(position(column) - expected) < 0.025 }
    func sync(_ reader: ReaderTabViewController, _ enabled: Bool) {
        reader.syncScrollBtn.state = enabled ? .on : .off
        reader.toggleSyncScrollAction()
    }
    let original = root.appendingPathComponent("core-original.pdf")
    let translated = root.appendingPathComponent("core-translated.pdf")
    let extra = root.appendingPathComponent("core-extra.pdf")
    try writePDF(original, pages: 18)
    try writePDF(translated, pages: 23)
    try writePDF(extra, pages: 9, text: "appendix only")
    let store = LibraryStore.shared
    func makeReader(_ title: String) -> ReaderTabViewController {
        let paper = store.createPaper(title: title, originalSourceURL: original)!
        _ = store.importPDF(for: paper.id, side: .translated, from: translated)
        let reader = ReaderTabViewController(paperId: paper.id)
        reader.view.frame = NSRect(x: 0, y: 0, width: 1360, height: 820)
        reader.view.layoutSubtreeIfNeeded()
        settle()
        return reader
    }

    // A new generation invalidates queued restores; nested programmatic updates
    // never reopen the event gate early, and closing cannot run deferred layout.
    do {
        let coordinator = PDFViewportCoordinator(columns: [])
        var layouts = 0
        coordinator.layoutViews = { layouts += 1 }
        coordinator.performUpdate {
            check(!coordinator.acceptsEvents, "Viewport transaction gates PDFKit notifications")
            coordinator.performUpdate { check(!coordinator.acceptsEvents, "Nested viewport transaction keeps events gated") }
            check(!coordinator.acceptsEvents, "Nested transaction cannot release its outer gate")
        }
        check(coordinator.acceptsEvents, "Viewport transaction releases the event gate")
        coordinator.beginLayout()
        coordinator.scheduleCompletion()
        coordinator.beginLoading()
        settle()
        check(layouts == 0 && coordinator.phase == .loading, "New document generation rejects a queued layout restore")
        coordinator.documentsInstalled()
        coordinator.finishLayout()
        let finishedLayouts = layouts
        settle()
        check(layouts == finishedLayouts && coordinator.phase == .ready, "Explicit action consumes deferred restore exactly once")
        coordinator.beginLayout()
        coordinator.scheduleCompletion()
        coordinator.close()
        settle()
        check(layouts == finishedLayouts && !coordinator.acceptsEvents, "Closed viewport rejects deferred layout and input")
    }

    do {
        let split = DualPDFSplitView()
        split.isVertical = true
        split.addArrangedSubview(NSView())
        split.addArrangedSubview(NSView())
        var contained = true
        for ratio in [CGFloat(0), 0.15, 0.8, 1, .nan] {
            split.splitRatioProvider = { ratio }
            for width in [CGFloat(1), 40, 80, 120, 400] {
                split.frame = NSRect(x: 0, y: 0, width: width, height: 200)
                split.adjustSubviews()
                contained = contained && split.subviews.allSatisfy {
                    $0.frame.width.isFinite && $0.frame.width >= 0 && $0.frame.maxX <= width + 0.001
                }
            }
        }
        check(contained, "Transient narrow split sizes and invalid ratios never create overflowing panes")
    }

    // Reproduce divider -> blank click -> drawer -> zoom without waiting between
    // each action. Both viewports must keep their own pre-layout reading anchors.
    for synchronized in [false, true] {
        let reader = makeReader("Viewport combination \(synchronized)")
        defer { reader.prepareForClose() }
        sync(reader, false)
        PDFScrollSynchronizer.scroll(to: 4.35, in: reader.leftCol)
        PDFScrollSynchronizer.scroll(to: 7.65, in: reader.rightCol)
        reader.recordOptionScrollCalibrationOffset()
        if synchronized {
            sync(reader, true)
            reader.leftCol.pdfView.onInteraction?()
            PDFScrollSynchronizer.scroll(to: 4.55, in: reader.leftCol)
            settle()
            check(abs(position(reader.rightCol) - position(reader.leftCol) - reader.pageRatioOffset) < 0.025,
                "Bounds notifications synchronize actual scrolling despite floating-point size noise")
        }
        let left = position(reader.leftCol)
        let right = position(reader.rightCol)
        var stable = true
        for index in 0..<12 {
            reader.dualSplitView.setPosition(reader.dualSplitView.bounds.width * (index % 2 == 0 ? 0.72 : 0.33), ofDividerAt: 0)
            reader.view.layoutSubtreeIfNeeded()
            reader.rightCol.pdfView.onInteraction?()
            reader.leftCol.pdfView.onInteraction?()
            reader.toggleRightDrawerAction()
            stable = stable && samePosition(reader.leftCol, left) && samePosition(reader.rightCol, right)
            reader.leftZoomInAction()
            stable = stable && samePosition(reader.leftCol, left) && samePosition(reader.rightCol, right)
            reader.leftZoomOutAction()
            reader.rightCol.pdfView.onInteraction?()
            stable = stable && samePosition(reader.leftCol, left) && samePosition(reader.rightCol, right)
        }
        settle()
        check(stable && samePosition(reader.leftCol, left) && samePosition(reader.rightCol, right),
            "Divider, blank click, drawer and zoom preserve both anchors (sync=\(synchronized))")
        let beforeClick = [position(reader.leftCol), position(reader.rightCol)]
        for _ in 0..<5 { reader.leftCol.pdfView.onInteraction?(); reader.rightCol.pdfView.onInteraction?() }
        settle()
        check(samePosition(reader.leftCol, beforeClick[0]) && samePosition(reader.rightCol, beforeClick[1]),
            "Focus-only clicks never realign either PDF (sync=\(synchronized))")

        // The native menu and trackpad paths use the same transaction as buttons.
        let otherScale = reader.rightCol.pdfView.scaleFactor
        let otherFitsWidth = reader.rightCol.viewportLayout.fitsWidth
        reader.leftCol.pdfView.onZoomCommand?(false, 1.6)
        check(abs(reader.leftCol.pdfView.scaleFactor - 1.6) < 0.001 && samePosition(reader.leftCol, left) &&
              abs(reader.rightCol.pdfView.scaleFactor - otherScale) < 0.001 &&
              reader.rightCol.viewportLayout.fitsWidth == otherFitsWidth && samePosition(reader.rightCol, right),
            "Context-menu zoom preserves both anchors and the other column's zoom (sync=\(synchronized))")
        reader.leftCol.pdfView.onMagnificationWillChange?()
        reader.leftCol.pdfView.autoScales = false
        reader.leftCol.pdfView.scaleFactor = 1.85
        reader.leftCol.pdfView.onMagnificationDidChange?()
        settle()
        check(abs(reader.leftCol.pdfView.scaleFactor - 1.85) < 0.001 &&
              abs(reader.rightCol.pdfView.scaleFactor - otherScale) < 0.001 &&
              reader.rightCol.viewportLayout.fitsWidth == otherFitsWidth &&
              samePosition(reader.leftCol, left) && samePosition(reader.rightCol, right),
            "Trackpad zoom preserves both anchors and the other column's zoom (sync=\(synchronized))")
        reader.leftCol.pdfView.scaleFactor = 1.7
        settle()
        check(abs(reader.leftCol.pdfView.scaleFactor - 1.7) < 0.001 &&
              abs(reader.rightCol.pdfView.scaleFactor - otherScale) < 0.001 &&
              samePosition(reader.leftCol, left) && samePosition(reader.rightCol, right),
            "Native PDFKit scale notifications remain local to their column (sync=\(synchronized))")

        // Layout cannot move an unsynchronized reference pane, even with sync on.
        sync(reader, true)
        let source = position(reader.leftCol)
        let oppositePage = reader.leftCol.pdfView.document!.page(at: 11)!
        _ = reader.leftCol.pdfView.onBeforeInternalLinkJump?(oppositePage, .zero, true)
        let reference = position(reader.rightCol)
        reader.toggleRightDrawerAction()
        reader.dualSplitView.setPosition(reader.dualSplitView.bounds.width * 0.6, ofDividerAt: 0)
        reader.leftCol.pdfView.onInteraction?()
        settle()
        check(samePosition(reader.leftCol, source) && samePosition(reader.rightCol, reference),
            "Layout preserves an independent Command-click reference jump")
    }

    do {
        let reader = makeReader("Document replacement and activation")
        defer { reader.prepareForClose() }
        sync(reader, false)
        reader.leftCol.pdfView.onZoomCommand?(false, 1.45)
        PDFScrollSynchronizer.scroll(to: 5.25, in: reader.leftCol)
        let extraID = store.addAdditionalPDF(to: reader.paperId, from: extra, title: "Appendix")!.id
        reader.setColumnSource(reader.leftCol, source: .pdf(id: extraID))
        reader.leftCol.pdfView.onZoomCommand?(false, 1.8)
        PDFScrollSynchronizer.scroll(to: 3.6, in: reader.leftCol)
        reader.setColumnSource(reader.leftCol, source: .pdf(id: "original"))
        check(samePosition(reader.leftCol, 5.25) && abs(reader.leftCol.pdfView.scaleFactor - 1.45) < 0.001,
            "Switching back to a PDF restores that document's position and zoom")
        let document = reader.leftCol.pdfView.document
        reader.setColumnSource(reader.leftCol, source: .pdf(id: "original"))
        check(reader.leftCol.pdfView.document === document && samePosition(reader.leftCol, 5.25),
            "Reselecting the current PDF keeps its document and viewport")
        reader.setColumnSource(reader.leftCol, source: .pdf(id: extraID))
        check(samePosition(reader.leftCol, 3.6) && abs(reader.leftCol.pdfView.scaleFactor - 1.8) < 0.001,
            "Additional PDFs retain separate viewport history in a pane")

        reader.loadPaperDocuments()
        reader.leftZoomInAction()
        reader.handleNoteJumpURL("dualpdf://jump?pdf=\(extraID)&page=5")
        let afterCommand = position(reader.leftCol)
        let zoom = reader.leftCol.pdfView.scaleFactor
        settle()
        check(samePosition(reader.leftCol, afterCommand) && abs(reader.leftCol.pdfView.scaleFactor - zoom) < 0.001,
            "Actions issued during document loading survive delayed layout callbacks")

        reader.didResignActiveTab()
        reader.view.isHidden = true
        PDFScrollSynchronizer.scroll(to: 1.5, in: reader.leftCol)
        reader.view.isHidden = false
        reader.didBecomeActiveTab()
        settle()
        check(samePosition(reader.leftCol, afterCommand), "Inactive tab notifications cannot overwrite saved viewport state")
    }

    // Calibration belongs to an ordered document pair, independent of visual swapping.
    do {
        let reader = makeReader("Document pair calibration")
        sync(reader, false)
        PDFScrollSynchronizer.scroll(to: 3.2, in: reader.leftCol)
        PDFScrollSynchronizer.scroll(to: 5.2, in: reader.rightCol)
        reader.recordOptionScrollCalibrationOffset()
        let originalOffset = reader.pageRatioOffset
        let extraID = store.addAdditionalPDF(to: reader.paperId, from: extra, title: "Other pair")!.id
        reader.setColumnSource(reader.rightCol, source: .pdf(id: extraID))
        check(reader.pageRatioOffset == 0, "A different PDF pair starts without the previous pair's calibration")
        PDFScrollSynchronizer.scroll(to: 4.2, in: reader.leftCol)
        PDFScrollSynchronizer.scroll(to: 1.4, in: reader.rightCol)
        reader.recordOptionScrollCalibrationOffset()
        let extraOffset = reader.pageRatioOffset
        reader.setColumnSource(reader.rightCol, source: .pdf(id: "translated"))
        check(abs(reader.pageRatioOffset - originalOffset) < 0.001, "Returning to a PDF pair restores its own calibration")
        reader.swapColumnsAction()
        check(abs(reader.pageRatioOffset - originalOffset) < 0.001, "Visual pane swap preserves document-pair calibration direction")
        reader.prepareForClose()
        let reopened = ReaderTabViewController(paperId: reader.paperId)
        reopened.view.frame = NSRect(x: 0, y: 0, width: 1360, height: 820)
        reopened.view.layoutSubtreeIfNeeded()
        settle()
        check(abs(reopened.pageRatioOffset - originalOffset) < 0.001, "Document-pair calibration survives closing and reopening")
        reopened.setColumnSource(reopened.rightCol, source: .pdf(id: extraID))
        check(abs(reopened.pageRatioOffset - extraOffset) < 0.001, "Additional document-pair calibration persists independently")
        reopened.prepareForClose()
    }

    // A short target PDF reaching an edge must not bounce the source back.
    do {
        let reader = makeReader("Asymmetric document boundaries")
        defer { reader.prepareForClose() }
        let extraID = store.addAdditionalPDF(to: reader.paperId, from: extra, title: "Short PDF")!.id
        reader.setColumnSource(reader.rightCol, source: .pdf(id: extraID))
        reader.leftCol.pdfView.onInteraction?()
        PDFScrollSynchronizer.scroll(to: 14.3, in: reader.leftCol)
        reader.syncScroll(from: reader.leftCol, to: reader.rightCol)
        settle()
        check(samePosition(reader.leftCol, 14.3), "Short target PDF cannot push the source back from its reading position")
        let before = [position(reader.leftCol), position(reader.rightCol)]
        reader.toggleRightDrawerAction()
        let targetAfterLayout = position(reader.rightCol)
        reader.rightCol.pdfView.onInteraction?()
        reader.leftCol.pdfView.onInteraction?()
        settle()
        // A larger viewport can clamp the target center away from the last page
        // edge. Focus must keep that feasible position and leave the source alone.
        check(samePosition(reader.leftCol, before[0]) && samePosition(reader.rightCol, targetAfterLayout),
            "Clamped sync target cannot become a scroll source during layout or focus changes")
        reader.toggleRightDrawerAction()
        settle()
        check(samePosition(reader.rightCol, before[1]), "Expanding a clamped viewport restores its desired page anchor")
        let origin = reader.leftCol.internalScrollView()!.contentView.bounds.origin
        check(!PDFScrollSynchronizer.scroll(to: .nan, in: reader.leftCol)
                && reader.leftCol.internalScrollView()!.contentView.bounds.origin == origin,
            "Non-finite positions are rejected without moving the viewport")
    }
}
