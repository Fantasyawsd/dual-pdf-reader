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
    check(dualPDFAnnots <= max(afterCount, 1) + 2, "S4 PDFKit annots not duplicated explosively")

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
}
