import Cocoa
import PDFKit
import WebKit

// 阅读器组合回归：同时检查用户操作结果及 AppKit/PDFKit 的布局状态。
var failures = 0
var checks = 0
func check(_ condition: Bool, _ id: String, _ detail: String) {
    checks += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") [\(id)] \(detail)")
}
func settle(_ seconds: TimeInterval = 0.06) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}
func send(_ selector: String, to target: AnyObject) {
    _ = NSApp.sendAction(NSSelectorFromString(selector), to: target, from: nil)
}
func writePDF(_ url: URL, pages: Int, text: String, width: CGFloat = 600, height: CGFloat = 900) throws {
    var box = CGRect(x: 0, y: 0, width: width, height: height)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    for index in 0..<pages {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("\(text) page \(index)" as NSString).draw(at: NSPoint(x: 45, y: height - 120),
            withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
}
func pageIndex(_ col: CleanPDFColumnView) -> Int {
    guard let doc = col.pdfView.document, let page = col.pdfView.currentPage else { return -1 }
    return doc.index(for: page)
}
func position(_ col: CleanPDFColumnView) -> Double {
    PDFScrollSynchronizer.continuousPosition(in: col) ?? -100
}
func isWidthFitted(_ column: CleanPDFColumnView) -> Bool {
    guard let document = column.pdfView.document, let clip = column.internalScrollView()?.contentView else { return false }
    let viewport = clip.convert(clip.bounds, to: column.pdfView)
    let rects = (0..<document.pageCount).compactMap { index -> NSRect? in
        guard let page = document.page(at: index) else { return nil }
        return column.pdfView.convert(page.bounds(for: column.pdfView.displayBox), from: page)
    }
    let expectedWidth = viewport.width - 2 * min(8, viewport.width * 0.1)
    return column.viewportLayout.fitsWidth && abs((rects.map(\.width).max() ?? 0) - expectedWidth) < 1 &&
        rects.allSatisfy { abs($0.midX - viewport.midX) < 0.75 }
}
func setSync(_ reader: ReaderTabViewController, _ enabled: Bool) {
    reader.syncScrollBtn.state = enabled ? .on : .off
    reader.toggleSyncScrollAction()
}
func go(_ reader: ReaderTabViewController, _ col: CleanPDFColumnView, _ pos: Double) {
    _ = PDFScrollSynchronizer.scroll(to: pos, in: col)
    settle()
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("DualPDF-BugAudit-\(UUID().uuidString)")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
UserDefaults.standard.setVolatileDomain(["DualPDF_LibraryRootPath": root.path], forName: UserDefaults.argumentDomain)
let app = NSApplication.shared
let store = LibraryStore.shared
let orig = root.appendingPathComponent("audit-original.pdf")
let trans = root.appendingPathComponent("audit-translated.pdf")
let extra = root.appendingPathComponent("audit-extra.pdf")
try writePDF(orig, pages: 12, text: "alpha original")
try writePDF(trans, pages: 16, text: "alpha translated")
try writePDF(extra, pages: 9, text: "appendix only")

func newPaper(_ name: String) -> PaperItem {
    let paper = store.createPaper(title: name, originalSourceURL: orig)!
    _ = store.importPDF(for: paper.id, side: .translated, from: trans)
    return store.paper(withId: paper.id)!
}
func readerFor(_ paper: PaperItem) -> ReaderTabViewController {
    let reader = ReaderTabViewController(paperId: paper.id)
    reader.view.frame = NSRect(x: 0, y: 0, width: 1360, height: 820)
    reader.view.layoutSubtreeIfNeeded()
    settle()
    return reader
}

// 缩放独立于滚动同步，按钮和快捷键只影响目标栏。
do {
    let reader = readerFor(newPaper("zoom"))
    defer { reader.prepareForClose() }
    setSync(reader, false)
    for col in [reader.leftCol, reader.rightCol] {
        col.pdfView.onZoomCommand?(false, 1)
    }
    setSync(reader, true)
    let leftBaseline = reader.leftCol.pdfView.scaleFactor
    let rightBaseline = reader.rightCol.pdfView.scaleFactor
    reader.leftZoomInAction()
    check(abs(reader.leftCol.pdfView.scaleFactor / leftBaseline - 1.15) < 0.001 && abs(reader.rightCol.pdfView.scaleFactor - rightBaseline) < 0.001,
        "A01", "左栏倍率乘1.15，右栏保持原倍率；实际 L=\(reader.leftCol.pdfView.scaleFactor), R=\(reader.rightCol.pdfView.scaleFactor)")
    setSync(reader, false)
    for col in [reader.leftCol, reader.rightCol] { col.pdfView.onZoomCommand?(false, 1) }
    setSync(reader, true)
    let keyboardLeftBaseline = reader.leftCol.pdfView.scaleFactor
    let keyboardRightBaseline = reader.rightCol.pdfView.scaleFactor
    reader.leftCol.pdfView.onInteraction?()
    reader.zoomInActiveColumnAction()
    check(abs(reader.leftCol.pdfView.scaleFactor / keyboardLeftBaseline - 1.15) < 0.001 &&
        abs(reader.rightCol.pdfView.scaleFactor - keyboardRightBaseline) < 0.001,
        "A01-keyboard", "快捷键只放大当前左栏，右栏倍率不变")
    reader.zoomOutActiveColumnAction()
    check(abs(reader.leftCol.pdfView.scaleFactor - keyboardLeftBaseline) < 0.001 && abs(reader.rightCol.pdfView.scaleFactor - keyboardRightBaseline) < 0.001,
        "A01-out", "放大后缩小恢复各栏原倍率；实际 L=\(reader.leftCol.pdfView.scaleFactor) R=\(reader.rightCol.pdfView.scaleFactor)")
}

// 校准后，下一页必须以被点击栏的页号为依据。
do {
    let reader = readerFor(newPaper("page-source"))
    defer { reader.prepareForClose() }
    setSync(reader, false)
    reader.leftCol.pdfView.go(to: reader.leftCol.pdfView.document!.page(at: 2)!)
    reader.rightCol.pdfView.go(to: reader.rightCol.pdfView.document!.page(at: 4)!)
    reader.recordOptionScrollCalibrationOffset()
    setSync(reader, true)
    // 左栏最后产生真实滚动，故 primaryActiveColumn 为左栏。
    reader.leftCol.pdfView.go(to: reader.leftCol.pdfView.document!.page(at: 3)!)
    let before = pageIndex(reader.rightCol)
    let visiblePageBefore = Int(floor(position(reader.rightCol)))
    let leftBefore = pageIndex(reader.leftCol)
    let offset = reader.pageRatioOffset
    reader.rightNextPageAction()
    settle()
    // PDFKit 的 currentPage 可滞后；导航和工具栏使用视口实际所在页。
    check(Int(floor(position(reader.rightCol))) == visiblePageBefore + 1 && abs(position(reader.rightCol) - position(reader.leftCol) - offset) < 0.03,
        "A02", "offset=\(offset)，主栏=\(reader.primaryActiveColumn().side.rawValue)，右栏下一页前 L=\(leftBefore) R=\(before)，后 L=\(pageIndex(reader.leftCol)) R=\(pageIndex(reader.rightCol))")
}

// 左右互换后，左栏工具应操作视觉左侧 PDF。
do {
    let reader = readerFor(newPaper("swap-controls"))
    defer { reader.prepareForClose() }
    setSync(reader, false)
    reader.swapColumnsAction()
    let visualLeft = reader.dualSplitView.subviews.first as! CleanPDFColumnView
    let before = pageIndex(visualLeft)
    reader.leftNextPageAction()
    settle()
    check(pageIndex(visualLeft) == before + 1,
        "A03", "视觉左栏是 \(visualLeft.activePDFDocumentId)，左栏下一页前=\(before)，后=\(pageIndex(visualLeft))；原文页=\(pageIndex(reader.leftCol))")
    let scaleBefore = visualLeft.pdfView.scaleFactor
    reader.leftZoomInAction()
    check(visualLeft.pdfView.scaleFactor > scaleBefore + 0.01,
        "A03-zoom", "互换后左栏放大，视觉左栏倍率 \(scaleBefore)→\(visualLeft.pdfView.scaleFactor)，原文倍率=\(reader.leftCol.pdfView.scaleFactor)")
}

// 搜索关闭不能保留高亮，也不能在关闭后发布迟到的结果。
do {
    let reader = readerFor(newPaper("search-close"))
    defer { reader.prepareForClose() }
    send("toggleSearchFieldAction", to: reader)
    let field = descendants(reader.view).compactMap { $0 as? NSSearchField }.first!
    field.stringValue = "alpha"
    reader.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    settle(0.8)
    let before = reader.leftCol.pdfView.highlightedSelections?.count ?? 0
    send("closeSearchAction", to: reader)
    check(before > 0 && (reader.leftCol.pdfView.highlightedSelections?.isEmpty ?? true),
        "A04", "搜索关闭前左栏高亮=\(before)，关闭后=\(reader.leftCol.pdfView.highlightedSelections?.count ?? 0)")
    send("toggleSearchFieldAction", to: reader)
    field.stringValue = "alpha"
    reader.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    send("closeSearchAction", to: reader)
    settle(0.8)
    check(reader.leftCol.pdfView.highlightedSelections?.isEmpty ?? true,
        "A04-pending", "输入后立即关闭，等待后左栏高亮=\(reader.leftCol.pdfView.highlightedSelections?.count ?? 0)")
}

// 切换 PDF 应清理搜索结果，并把结果绑定到实际被搜索的文档。
do {
    let paper = newPaper("search-switch")
    let extraDoc = store.addAdditionalPDF(to: paper.id, from: extra, title: "附录")!
    let reader = readerFor(paper)
    defer { reader.prepareForClose() }
    send("toggleSearchFieldAction", to: reader)
    let field = descendants(reader.view).compactMap { $0 as? NSSearchField }.first!
    field.stringValue = "alpha"
    reader.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    settle(0.8)
    reader.setColumnSource(reader.leftCol, source: .pdf(id: extraDoc.id))
    settle(0.3)
    let stale = reader.leftCol.pdfView.highlightedSelections?.contains { selection in
        selection.pages.contains { $0.document !== reader.leftCol.pdfView.document }
    } ?? false
    check(!stale, "A05", "切换到无 alpha 的附录后，旧文档选区残留=\(stale)，高亮数=\(reader.leftCol.pdfView.highlightedSelections?.count ?? 0)")
}

// 阅读位置必须保存 PDF 身份，不能只保存物理侧别。
do {
    let paper = newPaper("restore-identity")
    let extraDoc = store.addAdditionalPDF(to: paper.id, from: extra, title: "附录")!
    let reader = readerFor(paper)
    setSync(reader, false)
    reader.setColumnSource(reader.rightCol, source: .pdf(id: extraDoc.id))
    go(reader, reader.rightCol, 5.4)
    reader.prepareForClose()
    let saved = store.paper(withId: paper.id)!
    let reopened = readerFor(saved)
    defer { reopened.prepareForClose() }
    check(reopened.rightCol.activePDFDocumentId == extraDoc.id,
        "A06", "关闭前阅读附录 p=5.4；保存 side=\(saved.readingPosition?.side.rawValue ?? "nil")，重开右栏=\(reopened.rightCol.activePDFDocumentId)，位置=\(position(reopened.rightCol))")
}

// 独立阅读后重新加载，应保留两栏各自位置。
do {
    let reader = readerFor(newPaper("independent-reload"))
    defer { reader.prepareForClose() }
    setSync(reader, false)
    go(reader, reader.leftCol, 2.4)
    go(reader, reader.rightCol, 7.4)
    let leftBefore = position(reader.leftCol)
    let rightBefore = position(reader.rightCol)
    reader.loadPaperDocuments()
    settle(0.2)
    check(abs(position(reader.leftCol) - leftBefore) < 0.03 && abs(position(reader.rightCol) - rightBefore) < 0.03,
        "A07", "独立模式刷新前 L=\(leftBefore) R=\(rightBefore)，后 L=\(position(reader.leftCol)) R=\(position(reader.rightCol))")
}

// 返回记录恢复视口起点；缩放后视口覆盖范围发生变化是正常行为。
do {
    let reader = readerFor(newPaper("back-after-zoom"))
    defer { reader.prepareForClose() }
    setSync(reader, false)
    go(reader, reader.leftCol, 3.4)
    let before = position(reader.leftCol)
    let originBefore = reader.leftCol.internalScrollView()!.contentView.bounds.origin.y
    reader.pushJumpRecord(from: reader.leftCol)
    go(reader, reader.leftCol, 8.4)
    reader.leftZoomInAction()
    reader.leftZoomInAction()
    reader.popBackJumpAction(for: reader.leftCol)
    settle()
    let originAfter = reader.leftCol.internalScrollView()!.contentView.bounds.origin.y
    check(abs(originAfter - originBefore) < 0.1,
        "A08-control", "返回前后视口起点 \(originBefore)→\(originAfter)；视口中心 \(before)→\(position(reader.leftCol))")
}

// 切换单栏模式时，缩略图应展示当前可见 PDF。
do {
    let reader = readerFor(newPaper("thumbnails"))
    defer { reader.prepareForClose() }
    reader.setDisplayMode(1)
    reader.toggleLeftSidebarAction()
    let thumbnails = descendants(reader.view).compactMap { $0 as? PDFThumbnailView }.first!
    check(thumbnails.pdfView === reader.rightCol.pdfView,
        "A09", "仅译文模式的缩略图仍绑定隐藏原文=\(thumbnails.pdfView === reader.leftCol.pdfView)")
    let table = descendants(reader.view).compactMap { $0 as? NSTableView }.first!
    check(table.numberOfRows == 16, "A10", "仅译文有16页；目录条目数=\(table.numberOfRows)，原文12页")
}

// 当前页随笔应绑定当前选中 PDF 的 ID。
do {
    let paper = newPaper("general-note")
    let extraDoc = store.addAdditionalPDF(to: paper.id, from: extra, title: "附录")!
    let reader = readerFor(paper)
    defer { reader.prepareForClose() }
    setSync(reader, false)
    reader.setColumnSource(reader.leftCol, source: .pdf(id: extraDoc.id))
    go(reader, reader.leftCol, 4.4)
    send("addGeneralPageNoteAction", to: reader)
    let note = store.paper(withId: paper.id)!.annotations.last!
    check(note.effectivePDFId == extraDoc.id,
        "A11", "附录随笔预期 pdf=\(extraDoc.id)，实际=\(note.effectivePDFId)，page=\(note.pageIndex)")
}

// 附加 PDF 被外部更新后，重新激活阅读标签应重新加载。
do {
    let paper = newPaper("extra-modification")
    let extraDoc = store.addAdditionalPDF(to: paper.id, from: extra, title: "附录")!
    let reader = readerFor(paper)
    defer { reader.prepareForClose() }
    reader.setColumnSource(reader.leftCol, source: .pdf(id: extraDoc.id))
    let url = store.pdfURL(for: store.paper(withId: paper.id)!, pdfId: extraDoc.id)!
    try writePDF(url, pages: 4, text: "changed appendix")
    reader.didBecomeActiveTab()
    settle()
    check(reader.leftCol.pdfView.document?.pageCount == 4,
        "A12", "附加 PDF 外部改成4页，激活后仍为 \(reader.leftCol.pdfView.document?.pageCount ?? -1) 页")
}

// 真实窗口中的布局组合：记录 PDFKit 的内部尺寸，并检查外层面板边界。
do {
    let paper = newPaper("layout-matrix")
    let controller = MultiTabMainWindowController()
    controller.openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil)
    let window = controller.window!
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    let reader = controller.activeReaderVC!
    defer {
        reader.prepareForClose()
        window.orderOut(nil)
        window.close()
    }
    func layout() {
        window.contentView?.layoutSubtreeIfNeeded()
        reader.view.layoutSubtreeIfNeeded()
        settle(0.05)
    }
    func snapshot(_ name: String, mode: Int) {
        layout()
        let split = reader.dualSplitView
        let visible = split.subviews.filter { !$0.isHidden }
        let width = visible.reduce(CGFloat(0)) { $0 + $1.frame.width } + split.dividerThickness
        var valid = abs(width - split.bounds.width) < 2
        for col in [reader.leftCol, reader.rightCol] where !col.isHidden {
            valid = valid && col.frame.width > 1 && abs(col.frame.height - split.bounds.height) < 2
            valid = valid && abs(col.pdfView.frame.width - col.bounds.width) < 2
            valid = valid && abs(col.pdfView.frame.height - (col.bounds.height - col.columnToolbar.frame.height)) < 2
            valid = valid && col.pdfView.scaleFactor.isFinite && col.pdfView.scaleFactor > 0.01
        }
        valid = valid && visible.count == (mode == 2 ? 2 : 1)
        let master = split.superview!.superview as! NSSplitView
        check(valid, "LAYOUT-\(name)", "mode=\(mode) root=\(reader.view.bounds.size) canvas=\(split.bounds.size) L=\(reader.leftCol.frame) R=\(reader.rightCol.frame) drawer=\(master.subviews.last!.frame)")
        for col in [reader.leftCol, reader.rightCol] {
            let scroll = col.internalScrollView()
            print("METRIC \(name) \(col.side.rawValue) hidden=\(col.isHidden) scale=\(col.pdfView.scaleFactor) auto=\(col.pdfView.autoScales) pdf=\(col.pdfView.frame.size) clip=\(scroll?.contentView.bounds ?? .zero) doc=\(scroll?.documentView?.frame ?? .zero) pos=\(position(col))")
        }
    }
    layout()
    snapshot("initial", mode: 2)
    setSync(reader, false)
    reader.leftCol.pdfView.autoScales = false
    reader.rightCol.pdfView.autoScales = false
    reader.leftCol.pdfView.scaleFactor = 1.6
    reader.rightCol.pdfView.scaleFactor = 1.3
    go(reader, reader.leftCol, 5.4)
    go(reader, reader.rightCol, 7.4)
    let originalPosition = position(reader.leftCol)
    let originalRightPosition = position(reader.rightCol)
    snapshot("manual-zoom", mode: 2)
    reader.setDisplayMode(0)
    snapshot("single-original", mode: 0)
    reader.leftZoomInAction()
    snapshot("single-zoom", mode: 0)
    reader.setDisplayMode(2)
    snapshot("dual-restored", mode: 2)
    check(abs(position(reader.leftCol) - originalPosition) < 0.03,
        "L01", "双→单→缩放→双，左栏页内位置前=\(originalPosition)，后=\(position(reader.leftCol))")
    check(abs(position(reader.rightCol) - originalRightPosition) < 0.03,
        "L06", "独立模式双→单→缩放→双，隐藏右栏页内位置前=\(originalRightPosition)，后=\(position(reader.rightCol))")
    check(isWidthFitted(reader.leftCol) && isWidthFitted(reader.rightCol),
        "L02", "单双栏切换后两栏按各自新宽度适配，并保持页面居中")
    // 非对称分栏和右侧栏开合、缩窗之间的组合。
    reader.setColumnSplitRatioForTesting(0.8)
    reader.applyColumnSplitRatio()
    snapshot("ratio-80", mode: 2)
    let ratioBefore = reader.dualSplitView.subviews[0].frame.width / (reader.dualSplitView.bounds.width - reader.dualSplitView.dividerThickness)
    reader.toggleRightDrawerAction()
    snapshot("drawer-open", mode: 2)
    window.setContentSize(NSSize(width: 1020, height: 620))
    snapshot("drawer-small-window", mode: 2)
    let master = reader.dualSplitView.superview!.superview as! NSSplitView
    check(master.subviews.last!.frame.width >= 280, "L07", "开右侧栏缩小到最小窗口后，侧栏宽=\(master.subviews.last!.frame.width)，约定最小280")
    reader.toggleRightDrawerAction()
    window.setContentSize(NSSize(width: 1440, height: 880))
    snapshot("drawer-close-large-window", mode: 2)
    let ratioAfter = reader.dualSplitView.subviews[0].frame.width / (reader.dualSplitView.bounds.width - reader.dualSplitView.dividerThickness)
    check(abs(ratioBefore - ratioAfter) < 0.01,
        "L03", "拖成80:20，开右侧栏→缩小窗口→关侧栏→放大窗口，比例前=\(ratioBefore)，后=\(ratioAfter)")
    // 互换、单栏、侧边栏与另一个单栏交替。
    reader.swapColumnsAction()
    reader.setDisplayMode(0)
    snapshot("swap-single-original", mode: 0)
    reader.toggleRightDrawerAction()
    snapshot("swap-single-drawer", mode: 0)
    reader.setDisplayMode(1)
    snapshot("swap-single-translated-before-zoom", mode: 1)
    let translatedFit = reader.rightCol.pdfView.scaleFactor
    reader.rightZoomInAction()
    snapshot("swap-single-translated", mode: 1)
    check(translatedFit > 1 && abs(reader.rightCol.pdfView.scaleFactor - translatedFit * 1.15) < 0.01,
        "L08", "等待布局后仅译文自适应倍率=\(translatedFit)，放大后=\(reader.rightCol.pdfView.scaleFactor)")
    reader.setDisplayMode(2)
    snapshot("swap-dual-drawer", mode: 2)
    reader.toggleLeftSidebarAction()
    snapshot("both-sidebars-open", mode: 2)
    reader.toggleLeftSidebarAction()
    reader.toggleRightDrawerAction()
    snapshot("all-sidebars-closed", mode: 2)
    // 重复交替，并在最小窗口下展开搜索。
    var modeFailures = 0
    for index in 0..<12 {
        reader.setDisplayMode(index % 3)
        reader.toggleRightDrawerAction()
        window.setContentSize(NSSize(width: index % 2 == 0 ? 1020 : 1440, height: index % 2 == 0 ? 620 : 880))
        layout()
        if reader.dualSplitView.subviews.filter({ !$0.isHidden }).contains(where: { $0.frame.width <= 1 || $0.frame.height <= 1 }) { modeFailures += 1 }
    }
    check(modeFailures == 0, "L04", "12次模式/侧栏/窗口尺寸交替，面板坍缩次数=\(modeFailures)")
    reader.setDisplayMode(2)
    window.setContentSize(NSSize(width: 1020, height: 620))
    layout()
    let frameBeforeSearch = window.frame
    check(window.frame.width <= 1021, "L05-minimum-window", "主窗口可以缩到声明的1020pt；实际宽度=\(window.frame.width)")
    send("toggleSearchFieldAction", to: reader)
    layout()
    print("METRIC toolbar-search windowBefore=\(frameBeforeSearch) windowAfter=\(window.frame) root=\(reader.view.bounds)")
    let visibleButtons = descendants(reader.view).compactMap { $0 as? NSButton }.filter {
        !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds, to: reader.view).minY > reader.view.bounds.height - 45
    }
    let compressed = visibleButtons.filter { $0.bounds.width < 12 }
    check(compressed.isEmpty, "L05", "最小窗口双栏打开搜索，宽度不足12pt的顶栏按钮=\(compressed.map { "\($0.toolTip ?? $0.title):\($0.bounds.width)" })")
    let primaryTitles = ["大纲目录", "单页/连续滚动", "自适应宽度", "抓手漫游", "指针选择"]
    let perColumnControlsFit = [reader.leftCol, reader.rightCol].allSatisfy { column -> Bool in
        let toolbar = column.columnToolbar
        let visibleButtons = descendants(toolbar).compactMap { $0 as? NSButton }.filter { button in
            !button.isHiddenOrHasHiddenAncestor && primaryTitles.contains(button.toolTip ?? "")
        }
        let overflowOK = !toolbar.overflowButtonForTesting.isHidden &&
            Set(toolbar.overflowMenuTitlesForTesting()).isSuperset(of: primaryTitles)
        let visibleFramesFit = visibleButtons.allSatisfy { button in
            let frame = button.convert(button.bounds, to: reader.view)
            return button.frame.width >= 24 &&
                frame.minX >= 0 && frame.maxX <= reader.view.bounds.width && frame.maxY <= reader.view.bounds.height
        }
        return (visibleButtons.count == primaryTitles.count || overflowOK) && visibleFramesFit
    }
    let unifiedButtons = descendants(reader.unifiedMarkupToolbar).compactMap { $0 as? NSButton }
        .filter { !$0.isHiddenOrHasHiddenAncestor }
    let unifiedOK = unifiedButtons.count >= 10 &&
        unifiedButtons.contains { $0.toolTip == "高亮" } &&
        unifiedButtons.contains { $0.toolTip == "矩形" }
    let capsulesFit = [reader.leftCol, reader.rightCol].allSatisfy { $0.pageCapsule.frame.width >= 140 }
    check(perColumnControlsFit && unifiedOK && capsulesFit, "L05-all-controls", "紧凑布局保留两栏视图/缩放入口、统一批注工具栏与页码胶囊，窄栏自动收进溢出菜单")
    send("closeSearchAction", to: reader)
    reader.focusSearchField()
    let field = descendants(reader.view).compactMap { $0 as? NSSearchField }.first!
    check(!field.isHiddenOrHasHiddenAncestor, "A13", "菜单调用 focusSearchField 后输入框仍隐藏=\(field.isHiddenOrHasHiddenAncestor)")

    // 同步模式下，分隔线、窗口与侧栏布局更新必须保持校准关系。
    window.setContentSize(NSSize(width: 1440, height: 880))
    reader.setColumnSplitRatioForTesting(0.5)
    reader.applyColumnSplitRatio()
    reader.setDisplayMode(2)
    layout()
    setSync(reader, false)
    go(reader, reader.leftCol, 4.4)
    go(reader, reader.rightCol, 6.4)
    reader.recordOptionScrollCalibrationOffset()
    setSync(reader, true)
    layout()
    func alignment(_ name: String) {
        layout()
        check(abs(position(reader.rightCol) - position(reader.leftCol) - reader.pageRatioOffset) < 0.03,
            "SYNC-\(name)", "L=\(position(reader.leftCol))，R=\(position(reader.rightCol))，offset=\(reader.pageRatioOffset)")
    }
    alignment("initial")
    reader.dualSplitView.setPosition(reader.dualSplitView.bounds.width * 0.7, ofDividerAt: 0)
    alignment("divider-70")
    reader.toggleRightDrawerAction()
    alignment("drawer-toggle")
    let beforeSingleOriginal = position(reader.leftCol)
    reader.setDisplayMode(0)
    snapshot("sync-single-original", mode: 0)
    check(abs(position(reader.leftCol) - beforeSingleOriginal) < 0.75,
        "L09-original", "同步时双→仅原文，位置前=\(beforeSingleOriginal)，后=\(position(reader.leftCol))")
    check(store.paper(withId: paper.id)?.readingPosition?.side == .original,
        "L10-original", "仅原文模式保存的阅读侧=\(store.paper(withId: paper.id)?.readingPosition?.side.rawValue ?? "nil")")
    reader.leftZoomInAction()
    snapshot("sync-single-original-zoom", mode: 0)
    reader.setDisplayMode(2)
    alignment("single-original-back")
    let beforeSingleTranslated = position(reader.rightCol)
    reader.setDisplayMode(1)
    snapshot("sync-single-translated", mode: 1)
    check(abs(position(reader.rightCol) - beforeSingleTranslated) < 0.75,
        "L09-translated", "同步时双→仅译文，位置前=\(beforeSingleTranslated)，后=\(position(reader.rightCol))")
    check(store.paper(withId: paper.id)?.readingPosition?.side == .translated,
        "L10-translated", "仅译文模式保存的阅读侧=\(store.paper(withId: paper.id)?.readingPosition?.side.rawValue ?? "nil")")
    reader.rightZoomInAction()
    snapshot("sync-single-translated-zoom", mode: 1)
    reader.setDisplayMode(2)
    alignment("single-translated-back")
    window.setContentSize(NSSize(width: 1020, height: 620))
    alignment("small-window")
    window.setContentSize(NSSize(width: 1440, height: 880))
    alignment("large-window")

    // 新交互要求：侧栏改变可用宽度后，恢复按栏宽适配和居中。
    setSync(reader, false)
    reader.setDisplayMode(2)
    layout()
    reader.leftCol.pdfView.autoScales = false
    reader.rightCol.pdfView.autoScales = false
    reader.leftCol.pdfView.scaleFactor = 1.6
    reader.rightCol.pdfView.scaleFactor = 1.3
    reader.toggleRightDrawerAction()
    layout()
    check(isWidthFitted(reader.leftCol) && isWidthFitted(reader.rightCol),
        "L11", "手动倍率 L=1.6 R=1.3，开关右侧栏后按新栏宽居中适配，L=\(reader.leftCol.pdfView.scaleFactor) R=\(reader.rightCol.pdfView.scaleFactor)")

    // 模拟 AppKit 的鼠标跟踪事件，覆盖 NSSplitView 的实际拖拽路径。
    func drainMouseTrackingEvents() {
        while NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: Date(), inMode: .eventTracking, dequeue: true) != nil {}
    }
    func drag(_ split: NSSplitView, delta: CGFloat) {
        drainMouseTrackingEvents()
        let start = split.convert(NSPoint(x: split.subviews[0].frame.maxX + split.dividerThickness / 2, y: split.bounds.midY), to: nil)
        let end = NSPoint(x: start.x + delta, y: start.y)
        let now = ProcessInfo.processInfo.systemUptime
        func event(_ type: NSEvent.EventType, _ point: NSPoint, _ time: TimeInterval) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        }
        NSApp.postEvent(event(.leftMouseDragged, end, now + 0.01), atStart: false)
        NSApp.postEvent(event(.leftMouseUp, end, now + 0.02), atStart: false)
        split.mouseDown(with: event(.leftMouseDown, start, now))
        layout()
    }
    func clickBlank(_ column: CleanPDFColumnView) {
        let point = column.pdfView.convert(NSPoint(x: column.pdfView.bounds.maxX - 4, y: 4), to: nil)
        let now = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: now,
            windowNumber: window.windowNumber, context: nil, eventNumber: 10, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: now + 0.01,
            windowNumber: window.windowNumber, context: nil, eventNumber: 11, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: false)
        column.pdfView.mouseDown(with: down)
        drainMouseTrackingEvents()
    }
    reader.setColumnSplitRatioForTesting(0.5)
    reader.applyColumnSplitRatio()
    layout()
    let dividerBefore = reader.dualSplitView.subviews[0].frame.width
    drag(reader.dualSplitView, delta: 100)
    let dividerAfter = reader.dualSplitView.subviews[0].frame.width
    check(abs(dividerAfter - dividerBefore - 100) < 3,
        "L12", "鼠标实际拖动内分隔线100pt，前=\(dividerBefore)，后=\(dividerAfter)")
    snapshot("actual-divider-drag", mode: 2)

    // 用户报告的路径：中间分隔线拖动后，空白点击、侧栏、缩放均不得移位。
    for synchronized in [false, true] {
        setSync(reader, false)
        go(reader, reader.leftCol, 4.35)
        go(reader, reader.rightCol, 7.65)
        reader.recordOptionScrollCalibrationOffset()
        setSync(reader, synchronized)
        let anchors = [position(reader.leftCol), position(reader.rightCol)]
        func anchorsUnchanged() -> Bool {
            abs(position(reader.leftCol) - anchors[0]) < 0.03 && abs(position(reader.rightCol) - anchors[1]) < 0.03
        }
        drag(reader.dualSplitView, delta: synchronized ? -65 : 65)
        var stable = anchorsUnchanged()
        for column in [reader.leftCol, reader.rightCol] {
            // The bottom-right margin contains no text or link in this fixture.
            clickBlank(column)
            stable = stable && anchorsUnchanged()
        }
        reader.toggleRightDrawerAction()
        stable = stable && anchorsUnchanged()
        reader.leftZoomInAction()
        stable = stable && anchorsUnchanged()
        reader.leftZoomOutAction()
        layout()
        check(stable && anchorsUnchanged(),
            "L14-interaction-\(synchronized)", "真实拖拽、空白点击、侧栏及缩放后，L \(anchors[0])→\(position(reader.leftCol))，R \(anchors[1])→\(position(reader.rightCol))")
    }
    reader.resetSyncAlignmentAction()
    reader.leftZoomFitAction()
    reader.rightZoomFitAction()
    setSync(reader, true)
    go(reader, reader.rightCol, 14.3) // 原文只有12页；译文16页。
    let longDocumentAnchor = position(reader.rightCol)
    drag(reader.dualSplitView, delta: -40)
    clickBlank(reader.leftCol)
    reader.toggleRightDrawerAction()
    layout()
    check(abs(position(reader.rightCol) - longDocumentAnchor) < 0.03,
        "L15-clamped-focus", "短栏到达页尾后，拖分隔线、点短栏空白、开侧栏：长栏 \(longDocumentAnchor)→\(position(reader.rightCol))")
    reader.setDisplayMode(0)
    snapshot("actual-divider-single", mode: 0)
    reader.leftZoomInAction()
    reader.setDisplayMode(2)
    snapshot("actual-divider-dual", mode: 2)

    // 外层侧栏分隔线的真实拖动，以及关闭状态与按钮动作是否一致。
    if master.subviews.last!.isHidden { reader.toggleRightDrawerAction(); layout() }
    let drawer = master.subviews.last!
    let drawerWidthBefore = drawer.frame.width
    drag(master, delta: -70)
    check(abs(drawer.frame.width - drawerWidthBefore - 70) < 3,
        "L13-drawer-drag", "侧栏分隔线左拖70pt，侧栏前=\(drawerWidthBefore)，后=\(drawer.frame.width)")
    drag(master, delta: 2000)
    let collapsed = master.isSubviewCollapsed(drawer) || drawer.frame.width < 1
    print("METRIC drawer-collapse collapsed=\(collapsed) hidden=\(drawer.isHidden) frame=\(drawer.frame)")
    if collapsed {
        reader.toggleRightDrawerAction()
        layout()
        check(!drawer.isHidden && drawer.frame.width >= 280,
            "L13-collapse-toggle", "拖动收起后点击侧栏按钮，hidden=\(drawer.isHidden)，width=\(drawer.frame.width)")
    }
}

// 用最短操作序列独立验证隐藏栏同步，不依赖先前的互换或多次缩放。
do {
    let paper = newPaper("minimal-hidden-sync")
    let controller = MultiTabMainWindowController()
    controller.openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil)
    let reader = controller.activeReaderVC!
    let window = controller.window!
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    defer { reader.prepareForClose(); window.orderOut(nil); window.close() }
    window.contentView?.layoutSubtreeIfNeeded()
    settle(0.15)
    go(reader, reader.leftCol, 4.4)
    let before = position(reader.leftCol)
    reader.setDisplayMode(0)
    window.contentView?.layoutSubtreeIfNeeded()
    settle(0.15)
    check(abs(position(reader.leftCol) - before) < 0.75,
        "L09-minimal", "默认同步，双栏→仅原文，原文位置 \(before)→\(position(reader.leftCol))，隐藏译文scale=\(reader.rightCol.pdfView.scaleFactor)")

    reader.setDisplayMode(2)
    window.contentView?.layoutSubtreeIfNeeded()
    settle(0.1)
    setSync(reader, false)
    go(reader, reader.leftCol, 2.4)
    go(reader, reader.rightCol, 4.4)
    reader.recordOptionScrollCalibrationOffset()
    setSync(reader, true)
    go(reader, reader.leftCol, 2.5)
    let rightBefore = position(reader.rightCol)
    let leftBefore = position(reader.leftCol)
    reader.rightNextPageAction()
    settle(0.1)
    check(abs(position(reader.rightCol) - rightBefore - 1) < 0.2,
        "A02-window", "真实窗口右栏下一页，前 L=\(leftBefore) R=\(rightBefore)，后 L=\(position(reader.leftCol)) R=\(position(reader.rightCol))，offset=\(reader.pageRatioOffset)")
}

// 从磁盘重开后，各栏和布局偏好保持独立，不依赖仍存活的 PDFView 实例。
do {
    let paper = newPaper("state-roundtrip")
    let appendix = store.addAdditionalPDF(to: paper.id, from: extra, title: "附录")!
    let reader = readerFor(paper)
    setSync(reader, false)
    reader.setColumnSource(reader.rightCol, source: .pdf(id: appendix.id))
    reader.leftCol.pdfView.autoScales = false
    reader.rightCol.pdfView.autoScales = false
    reader.leftCol.pdfView.scaleFactor = 1.8
    reader.rightCol.pdfView.scaleFactor = 1.4
    go(reader, reader.leftCol, 2.4)
    go(reader, reader.rightCol, 5.4)
    reader.setColumnSplitRatioForTesting(0.8)
    reader.applyColumnSplitRatio()
    settle()
    reader.swapColumnsAction()
    reader.setDisplayMode(1)
    settle()
    reader.prepareForClose()
    let reconstructed = LibraryStore(rootDirectory: store.rootDirectory)
    let saved = reconstructed.paper(withId: paper.id)!.readerState!
    check(!saved.syncEnabled && saved.swapped && saved.displayMode == 1 && abs(saved.splitRatio - 0.8) < 0.01,
        "R01-layout", "磁盘恢复同步开关、互换、单栏模式及80:20期望比例")
    let reopened = readerFor(store.paper(withId: paper.id)!)
    defer { reopened.prepareForClose() }
    check(reopened.leftCol.isHidden && reopened.rightCol.activePDFDocumentId == appendix.id &&
        isWidthFitted(reopened.rightCol) &&
        abs(position(reopened.rightCol) - 5.4) < 0.03,
        "R01-visible", "重开仅译文槽位恢复附录和阅读位置，并按当前宽度居中适配")
    reopened.setDisplayMode(2)
    settle()
    check(abs(position(reopened.leftCol) - 2.4) < 0.03 && isWidthFitted(reopened.leftCol),
        "R01-hidden", "重开后再显示双栏，原隐藏原文恢复独立位置并按新宽度适配")
}

// 缺少一侧 PDF、横向页与旋转页，覆盖相同面板操作的边界场景。
let landscape = root.appendingPathComponent("landscape.pdf")
try writePDF(landscape, pages: 12, text: "landscape pages", width: 1000, height: 600)
let rotated = root.appendingPathComponent("rotated.pdf")
let rotatedDocument = PDFDocument(url: orig)!
for index in 0..<rotatedDocument.pageCount where index % 2 == 1 { rotatedDocument.page(at: index)?.rotation = 90 }
_ = rotatedDocument.write(to: rotated)
for kind in ["missing-translated", "landscape-translated", "mixed-rotation"] {
    let paper = kind == "missing-translated"
        ? store.createPaper(title: kind, originalSourceURL: orig)!
        : newPaper(kind)
    if kind != "missing-translated" {
        _ = store.importPDF(for: paper.id, side: .translated, from: kind == "mixed-rotation" ? rotated : landscape)
    }
    let controller = MultiTabMainWindowController()
    controller.openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil)
    let reader = controller.activeReaderVC!
    let window = controller.window!
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    settle(0.1)
    var invalid = 0
    for (index, mode) in [2, 0, 2, 1, 2, 0, 1, 2].enumerated() {
        reader.setDisplayMode(mode)
        reader.toggleRightDrawerAction()
        window.setContentSize(NSSize(width: index % 2 == 0 ? 1440 : 1020, height: index % 2 == 0 ? 880 : 620))
        window.contentView?.layoutSubtreeIfNeeded()
        settle(0.06)
        for col in [reader.leftCol, reader.rightCol] where !col.isHidden {
            let split = reader.dualSplitView
            if col.frame.width < 1 || col.frame.height < 1 || !col.pdfView.scaleFactor.isFinite ||
                abs(col.pdfView.frame.width - col.frame.width) > 2 ||
                abs(col.pdfView.frame.height - (col.frame.height - col.columnToolbar.frame.height)) > 2 ||
                col.frame.minX < -1 || col.frame.maxX > split.bounds.width + 1 { invalid += 1 }
        }
    }
    window.zoom(nil)
    window.contentView?.layoutSubtreeIfNeeded()
    settle(0.06)
    let split = reader.dualSplitView
    let sum = split.subviews.filter { !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.frame.width } + split.dividerThickness
    check(invalid == 0 && abs(sum - split.bounds.width) < 2,
        "MATRIX-\(kind)", "8次单双栏/窗口/侧栏交替及最大化；坍缩或非法倍率=\(invalid)，总宽误差=\(abs(sum - split.bounds.width))")
    reader.prepareForClose()
    window.orderOut(nil)
    window.close()
}

print("Bug audit: \(checks) checks, \(failures) failed expectations")
exit(failures == 0 ? 0 : 1)
