import Cocoa
import PDFKit

func runP0CompareModeTests(root: URL) throws {
    func settle(_ seconds: TimeInterval = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    func waitReady(_ reader: ReaderTabViewController, timeout: TimeInterval = 4) -> Bool {
        waitUntil({ reader.leftCol.pdfView.document != nil }, timeout: timeout)
    }

    let store = LibraryStore.shared

    // --- S1: single PDF defaults ---
    let singleURL = root.appendingPathComponent("p0-3-single.pdf")
    try writePDF(singleURL, pages: 4, text: "p0-3 single alpha")
    let single = store.createPaper(title: "P0-3 single \(UUID().uuidString)", originalSourceURL: singleURL)!
    let reader1 = ReaderTabViewController(paperId: single.id)
    defer { reader1.prepareForClose() }
    reader1.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
    reader1.view.layoutSubtreeIfNeeded()
    settle(0.3)
    check(waitReady(reader1), "S1 loads single PDF")
    settle(0.2)
    check(reader1.isModeSegVisibleForTesting == false, "S1 hides modeSeg")
    check(reader1.isAddCompareButtonVisibleForTesting, "S1 shows 添加对照 PDF")
    check(reader1.addCompareButtonTitleForTesting == "添加对照 PDF", "S1 button title exact")
    check(reader1.leftCol.isHidden == false && reader1.rightCol.isHidden, "S1 shows only left column")

    // --- S2 empty state copy ---
    reader1.enterCompareEmptyStateForTesting()
    settle(0.25)
    check(reader1.isAwaitingCompareForTesting, "S2 awaiting compare")
    check(reader1.rightCol.isHidden == false, "S2 shows right empty pane")
    check(reader1.rightCol.emptyStateTitleForTesting == "添加一份 PDF 进行对照", "S2 title exact")
    check(reader1.rightCol.emptyStateSubtitleForTesting == "拖入 PDF 到此处，或从文件中选择。", "S2 subtitle exact")
    check(reader1.rightCol.emptyStatePrimaryTitleForTesting == "选择 PDF…", "S2 primary exact")
    check(reader1.rightCol.emptyStateSecondaryTitleForTesting == "在右栏打开同一文档", "S2 secondary exact")
    check(reader1.rightCol.emptyStateCloseTitleForTesting == "返回单栏", "S2 close exact")

    // Esc / return -> S1
    reader1.returnToSingleColumnFromCompareForTesting()
    settle(0.2)
    check(!reader1.isAwaitingCompareForTesting, "return clears S2")
    check(reader1.rightCol.isHidden, "return hides right column")
    check(reader1.isAddCompareButtonVisibleForTesting, "return restores addCompare")

    // --- S4 same document ---
    reader1.enterCompareEmptyStateForTesting()
    settle(0.15)
    reader1.openSameDocumentInRightColumnForTesting()
    settle(0.3)
    check(reader1.isSameDocumentDualViewForTesting, "S4 flag set")
    check(reader1.leftCol.pdfView.document != nil && reader1.rightCol.pdfView.document != nil, "S4 both have docs")
    check(reader1.leftCol.pdfView.document === reader1.rightCol.pdfView.document, "S4 shares PDFDocument instance")
    check(reader1.syncScrollBtn.state == .off, "S4 sync off")
    check(reader1.rightCol.cornerButton.title.contains("同一文档"), "S4 badge 同一文档")

    // Unified undo must target the column that last edited (right), not only primary/left.
    var rightAnn = PaperAnnotation(
        side: .original, pageIndex: 0, rects: [RectCodable(NSRect(x: 20, y: 40, width: 50, height: 14))],
        selectedText: "p0-3-right-mark", color: .yellow, markdownNote: "", linkedURL: nil, linkedTitle: nil,
        pdfDocumentId: reader1.leftCol.activePDFDocumentId)
    rightAnn.kind = .highlight
    let rightUndoBefore = reader1.rightCol.pdfView.markupUndoCount
    reader1.rightCol.pdfView.seedMarkupCreateForTesting(rightAnn)
    settle(0.15)
    check(reader1.rightCol.pdfView.markupUndoCount == rightUndoBefore + 1, "S4 right column owns its undo entry")
    check(reader1.leftCol.pdfView.canUndoMarkup == false || reader1.leftCol.pdfView.markupUndoCount == 0
          || reader1.leftCol.pdfView.markupUndoCount == rightUndoBefore,
          "S4 left undo stack unchanged by right edit")
    let annotsAfterRightEdit = store.paper(withId: single.id)?.annotations.count ?? 0
    reader1.performUnifiedMarkupUndoForTesting()
    settle(0.15)
    let annotsAfterUnifiedUndo = store.paper(withId: single.id)?.annotations.count ?? 0
    check(annotsAfterUnifiedUndo == annotsAfterRightEdit - 1,
          "S4 unified undo clears right-column markup (before=\(annotsAfterRightEdit) after=\(annotsAfterUnifiedUndo))")
    check(!reader1.rightCol.pdfView.canUndoMarkup, "S4 right undo stack empty after unified undo")

    // User turns sync on while in S4 — restore must keep it (not force off).
    reader1.setScrollSyncEnabledForTesting(true)
    settle(0.1)
    check(reader1.isScrollSyncEnabledForTesting, "S4 user enabled sync")

    let beforeCount = store.paper(withId: single.id)?.annotations.count ?? 0
    var ann = PaperAnnotation(
        side: .original, pageIndex: 0, rects: [RectCodable(NSRect(x: 10, y: 10, width: 40, height: 12))],
        selectedText: "p0-3-mark", color: .yellow, markdownNote: "", linkedURL: nil, linkedTitle: nil,
        pdfDocumentId: reader1.leftCol.activePDFDocumentId)
    ann.kind = .highlight
    guard var paperSnap = store.paper(withId: single.id) else {
        check(false, "S4 paper snapshot available")
        return
    }
    paperSnap.annotations.append(ann)
    check(store.savePaper(paperSnap), "S4 annotation savePaper")
    reader1.didBecomeActiveTab()
    settle(0.3)
    let afterCount = store.paper(withId: single.id)?.annotations.count ?? 0
    check(afterCount == beforeCount + 1, "S4 annotation stored once")
    let sharedDoc = reader1.leftCol.pdfView.document!
    let page0 = sharedDoc.page(at: 0)!
    let dualPDFAnnots = page0.annotations.filter { $0.userName == "DualPDF_CustomAnnot" }.count
    check(dualPDFAnnots == 1, "S4 PDFKit annots exact once on shared page (got \(dualPDFAnnots))")

    // Persist S4 and reopen
    reader1.prepareForClose()
    let reopened = ReaderTabViewController(paperId: single.id)
    defer { reopened.prepareForClose() }
    reopened.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
    reopened.view.layoutSubtreeIfNeeded()
    settle(0.35)
    check(waitReady(reopened), "S4 reopen loads")
    settle(0.25)
    check(reopened.isSameDocumentDualViewForTesting, "S4 restored")
    check(reopened.leftCol.pdfView.document === reopened.rightCol.pdfView.document, "S4 restored shared doc")
    check(reopened.isScrollSyncEnabledForTesting, "S4 restore keeps user sync on")

    // --- S2 does not persist ---
    let single2URL = root.appendingPathComponent("p0-3-single2.pdf")
    try writePDF(single2URL, pages: 3, text: "p0-3 single2")
    let single2 = store.createPaper(title: "P0-3 single2 \(UUID().uuidString)", originalSourceURL: single2URL)!
    let r2 = ReaderTabViewController(paperId: single2.id)
    r2.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    r2.view.layoutSubtreeIfNeeded()
    settle(0.3)
    check(waitReady(r2), "S2 persist fixture loads")
    r2.enterCompareEmptyStateForTesting()
    settle(0.2)
    r2.prepareForClose()
    let r2b = ReaderTabViewController(paperId: single2.id)
    defer { r2b.prepareForClose() }
    r2b.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    r2b.view.layoutSubtreeIfNeeded()
    settle(0.35)
    check(waitReady(r2b), "S2 reopen loads")
    settle(0.2)
    check(!r2b.isAwaitingCompareForTesting, "S2 reopens as not awaiting")
    check(r2b.rightCol.isHidden, "S2 reopens as S1 (right hidden)")

    // --- Dual non built-in pair labels 左栏/右栏/分屏 ---
    let a = root.appendingPathComponent("p0-3-a.pdf")
    let b = root.appendingPathComponent("p0-3-b.pdf")
    try writePDF(a, pages: 3, text: "p0-3 a")
    try writePDF(b, pages: 3, text: "p0-3 b")
    let pair = store.createPaper(title: "P0-3 pair \(UUID().uuidString)", originalSourceURL: a)!
    _ = store.importPDF(for: pair.id, side: .translated, from: b)
    // Force titles away from built-in? Built-in original+translated still uses 原文/译文.
    // Spec: 任意两份非原文/译文 -> 左栏/右栏/分屏. Use additional PDFs only.
    let c = root.appendingPathComponent("p0-3-c.pdf")
    let d = root.appendingPathComponent("p0-3-d.pdf")
    try writePDF(c, pages: 2, text: "p0-3 c")
    try writePDF(d, pages: 2, text: "p0-3 d")
    let custom = store.createPaper(title: "P0-3 custom \(UUID().uuidString)", originalSourceURL: c)!
    // Add second as additional, clear translated if any
    _ = store.addAdditionalPDF(to: custom.id, from: d, title: "附录对照")
    // Make sure translated empty so not built-in pair — only original + additional => still not isBuiltInOriginalTranslatedPair
    check(store.paper(withId: custom.id)?.isBuiltInOriginalTranslatedPair == false, "custom is not built-in pair")
    let rc = ReaderTabViewController(paperId: custom.id)
    defer { rc.prepareForClose() }
    rc.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
    rc.view.layoutSubtreeIfNeeded()
    settle(0.35)
    // Open additional on right
    if let extraId = store.paper(withId: custom.id)?.additionalPDFs?.first?.id {
        rc.setColumnSource(rc.rightCol, source: .pdf(id: extraId))
    }
    rc.setDisplayMode(2)
    settle(0.25)
    check(rc.modeSegmentLabels == ["左栏", "右栏", "分屏"], "non built-in labels 左栏/右栏/分屏: \(rc.modeSegmentLabels)")

    // Built-in pair keeps 原文/译文/分屏
    let rp = ReaderTabViewController(paperId: pair.id)
    defer { rp.prepareForClose() }
    rp.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
    rp.view.layoutSubtreeIfNeeded()
    settle(0.35)
    check(waitUntil({ rp.leftCol.pdfView.document != nil && rp.rightCol.pdfView.document != nil }, timeout: 4), "built-in pair loads")
    settle(0.2)
    rp.setDisplayMode(2)
    settle(0.15)
    check(rp.modeSegmentLabels == ["原文", "译文", "分屏"], "built-in labels 原文/译文/分屏")

    // S3 -> S5 -> S3
    rp.setDisplayMode(0)
    settle(0.15)
    check(rp.rightCol.isHidden, "S5 left-only hides right")
    rp.setDisplayMode(2)
    settle(0.15)
    check(!rp.leftCol.isHidden && !rp.rightCol.isHidden, "S3 dual restored")

    // --- S1 right-third drop → S3 compare (must not replace left doc) ---
    let dropBase = root.appendingPathComponent("p0-3-drop-base.pdf")
    let dropCompare = root.appendingPathComponent("p0-3-drop-compare.pdf")
    let dropReplace = root.appendingPathComponent("p0-3-drop-replace.pdf")
    try writePDF(dropBase, pages: 2, text: "p0-3 drop base UNIQUE_BASE")
    try writePDF(dropCompare, pages: 2, text: "p0-3 drop compare UNIQUE_COMPARE")
    try writePDF(dropReplace, pages: 2, text: "p0-3 drop replace UNIQUE_REPLACE")
    let dropPaper = store.createPaper(title: "P0-3 drop \(UUID().uuidString)", originalSourceURL: dropBase)!
    let dropReader = ReaderTabViewController(paperId: dropPaper.id)
    defer { dropReader.prepareForClose() }
    dropReader.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    dropReader.view.layoutSubtreeIfNeeded()
    settle(0.35)
    check(waitReady(dropReader), "drop fixture loads")
    settle(0.15)
    check(dropReader.rightCol.isHidden, "drop fixture starts S1")
    let leftPDFIdBefore = dropReader.leftCol.activePDFDocumentId
    let originalFilenameBefore = store.paper(withId: dropPaper.id)?.originalFilename
    let rightThird = NSPoint(x: dropReader.view.bounds.width * 0.85, y: dropReader.view.bounds.height * 0.5)
    let routedCompare = dropReader.routeColumnPDFDropForTesting(
        urls: [dropCompare], atLocationInReader: rightThird, column: dropReader.leftCol)
    settle(0.35)
    check(routedCompare, "right-third drop routes")
    check(!dropReader.rightCol.isHidden && dropReader.rightCol.pdfView.document != nil,
          "right-third drop enters S3 with right PDF")
    check(dropReader.leftCol.activePDFDocumentId == leftPDFIdBefore,
          "right-third drop keeps left column on the original PDF id")
    check(store.paper(withId: dropPaper.id)?.originalFilename == originalFilenameBefore,
          "right-third drop does not replace the paper's original PDF file")
    check((store.paper(withId: dropPaper.id)?.boundPDFCount ?? 0) >= 2,
          "right-third drop binds a second PDF")

    // Fresh S1 for left-two-thirds replace behavior
    let dropPaper2 = store.createPaper(title: "P0-3 drop2 \(UUID().uuidString)", originalSourceURL: dropBase)!
    let dropReader2 = ReaderTabViewController(paperId: dropPaper2.id)
    defer { dropReader2.prepareForClose() }
    dropReader2.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    dropReader2.view.layoutSubtreeIfNeeded()
    settle(0.35)
    check(waitReady(dropReader2), "left-two-thirds fixture loads")
    let beforeReplaceDoc = dropReader2.leftCol.pdfView.document
    let leftTwoThirds = NSPoint(x: dropReader2.view.bounds.width * 0.2, y: dropReader2.view.bounds.height * 0.5)
    let routedReplace = dropReader2.routeColumnPDFDropForTesting(
        urls: [dropReplace], atLocationInReader: leftTwoThirds, column: dropReader2.leftCol)
    settle(0.35)
    check(routedReplace, "left-two-thirds drop routes")
    check(dropReader2.rightCol.isHidden, "left-two-thirds drop stays S1 (no compare)")
    check(dropReader2.leftCol.pdfView.document !== nil, "left-two-thirds drop keeps a left document")
    check(dropReader2.leftCol.pdfView.document !== beforeReplaceDoc,
          "left-two-thirds drop replaces the left PDFDocument instance")
    check((store.paper(withId: dropPaper2.id)?.boundPDFCount ?? 0) == 1,
          "left-two-thirds drop does not add a compare PDF")

    // Esc from S2
    dropReader2.enterCompareEmptyStateForTesting()
    settle(0.15)
    check(dropReader2.isAwaitingCompareForTesting, "⌘3/S2 via enterCompare")
    dropReader2.handleCompareEscapeKey()
    settle(0.15)
    check(!dropReader2.isAwaitingCompareForTesting && dropReader2.rightCol.isHidden, "Esc returns S2→S1")

    // ⌘3 path = setDisplayMode(2) while single → S2
    dropReader2.setDisplayMode(2)
    settle(0.15)
    check(dropReader2.isAwaitingCompareForTesting, "⌘3/setDisplayMode(2) enters S2")
    check(dropReader2.rightCol.emptyStateTitleForTesting == "添加一份 PDF 进行对照", "⌘3 S2 title")

    // removeRightComparePDF removes additional from paper
    let addA = root.appendingPathComponent("p0-3-rm-a.pdf")
    let addB = root.appendingPathComponent("p0-3-rm-b.pdf")
    try writePDF(addA, pages: 1, text: "rm-a")
    try writePDF(addB, pages: 1, text: "rm-b")
    let rmPaper = store.createPaper(title: "P0-3 rm \(UUID().uuidString)", originalSourceURL: addA)!
    let added = store.addAdditionalPDF(to: rmPaper.id, from: addB, title: "附录B")!
    let rmReader = ReaderTabViewController(paperId: rmPaper.id)
    defer { rmReader.prepareForClose() }
    rmReader.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    rmReader.view.layoutSubtreeIfNeeded()
    settle(0.3)
    rmReader.setColumnSource(rmReader.rightCol, source: .pdf(id: added.id))
    rmReader.setDisplayMode(2)
    settle(0.2)
    check((store.paper(withId: rmPaper.id)?.additionalPDFs?.contains { $0.id == added.id }) == true,
          "additional present before remove")
    rmReader.removeRightComparePDFGoingToSingleForTesting()
    settle(0.25)
    check(rmReader.rightCol.isHidden, "remove compare returns S1")
    check((store.paper(withId: rmPaper.id)?.additionalPDFs ?? []).isEmpty,
          "移除此 PDF deletes additional from paper")
    check((store.paper(withId: rmPaper.id)?.boundPDFCount ?? 0) == 1, "bound count back to 1")
}
