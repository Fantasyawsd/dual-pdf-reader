import Cocoa
import PDFKit

func runReaderToolbarTests(root: URL) throws {
    func settle(_ seconds: TimeInterval = 0.12) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    let source = root.appendingPathComponent("toolbar-original.pdf")
    let translated = root.appendingPathComponent("toolbar-translated.pdf")
    try writePDF(source, pages: 6, text: "toolbar alpha beta gamma")
    try writePDF(translated, pages: 8, text: "toolbar 译文 alpha beta")

    let store = LibraryStore.shared
    let paper = store.createPaper(title: "Column toolbar \(UUID().uuidString)", originalSourceURL: source)!
    _ = store.importPDF(for: paper.id, side: .translated, from: translated)
    let reader = ReaderTabViewController(paperId: paper.id)
    defer { reader.prepareForClose() }
    reader.view.frame = NSRect(x: 0, y: 0, width: 1360, height: 860)
    reader.view.layoutSubtreeIfNeeded()
    settle(0.25)
    check(waitUntil({ reader.leftCol.pdfView.document != nil && reader.rightCol.pdfView.document != nil }, timeout: 4),
          "Toolbar fixture loads both PDF columns")
    reader.view.layoutSubtreeIfNeeded()
    settle(0.25)

    // Top bar mode tabs and split-only icon controls
    check(reader.modeSegmentLabels == ["原文", "译文", "分屏"], "Top tabs read 原文 / 译文 / 分屏")
    reader.setDisplayMode(2)
    settle()
    check(!reader.isSwapButtonHidden && !reader.isSyncButtonHidden,
          "Split mode shows swap and sync controls")
    check(reader.syncButtonTitle.isEmpty && reader.syncScrollBtn.image != nil,
          "Sync control is icon-only without redundant Chinese text")
    reader.setDisplayMode(0)
    settle()
    check(reader.isSwapButtonHidden && reader.isSyncButtonHidden,
          "原文 mode hides swap and sync controls")
    reader.setDisplayMode(1)
    settle()
    check(reader.isSwapButtonHidden && reader.isSyncButtonHidden,
          "译文 mode hides swap and sync controls")
    reader.setDisplayMode(2)
    settle()

    // Per-column toolbars
    for column in [reader.leftCol, reader.rightCol] {
        let toolbar = column.columnToolbar
        check(toolbar.modeTitles == ["阅读", "批注", "形状"],
              "\(column.side.rawValue) column has 阅读 / 批注 / 形状 tabs")
        check(toolbar.visibleToolTips.contains("大纲目录") &&
              toolbar.visibleToolTips.contains("双页并排") &&
              toolbar.visibleToolTips.contains("单页/连续滚动") &&
              toolbar.visibleToolTips.contains("自适应宽度") &&
              toolbar.visibleToolTips.contains("抓手漫游") &&
              toolbar.visibleToolTips.contains("指针选择") &&
              toolbar.visibleToolTips.contains("页内搜索") &&
              toolbar.visibleToolTips.contains("随手笔记"),
              "\(column.side.rawValue) primary toolbar exposes the required controls")
        let visibleToolbarButtons = descendants(toolbar).compactMap { $0 as? NSButton }.filter { !$0.isHiddenOrHasHiddenAncestor }
        let visibleModeTabs = descendants(toolbar).compactMap { $0 as? ColumnModeTabView }
        check(!visibleToolbarButtons.isEmpty &&
              visibleToolbarButtons.allSatisfy { !($0.toolTip ?? "").isEmpty } &&
              visibleModeTabs.allSatisfy { !($0.toolTip ?? "").isEmpty },
              "every visible toolbar control exposes a hover tooltip")
        check(toolbar.secondaryHeightForTesting == 0 && !toolbar.hasSecondaryRow,
              "\(column.side.rawValue) 阅读 mode collapses the secondary toolbar to zero height")

        toolbar.applyMode(.annotate)
        settle(0.2)
        check(toolbar.secondaryHeightForTesting == 32 && toolbar.hasSecondaryRow,
              "\(column.side.rawValue) 批注 mode expands the secondary toolbar")
        check(column.pdfView.markupTool == .highlight,
              "\(column.side.rawValue) 批注 mode activates the highlight tool in the PDF view")
        let annotateTips = Set(toolbar.visibleToolTips)
        check(annotateTips.isSuperset(of: ["高亮", "下划线", "删除线", "画笔", "橡皮擦", "文本", "选择颜色", "撤销", "重做"]),
              "\(column.side.rawValue) 批注 mode exposes core tools, one palette, undo and redo")
        check(toolbar.visibleToolTips.filter { $0 == "选择颜色" }.count == 1,
              "\(column.side.rawValue) uses a single palette control instead of a color row")
        check(!toolbar.visibleToolTips.contains("琥珀黄") && !toolbar.visibleToolTips.contains("翠竹绿"),
              "\(column.side.rawValue) does not flatten color swatches into the toolbar")

        toolbar.applyMode(.shape)
        settle(0.2)
        check(column.pdfView.markupTool == .rectangle,
              "\(column.side.rawValue) 形状 mode activates the rectangle tool in the PDF view")
        let shapeTips = Set(toolbar.visibleToolTips)
        check(toolbar.secondaryHeightForTesting == 32 &&
              shapeTips.isSuperset(of: ["矩形", "椭圆", "直线", "箭头", "选择颜色", "撤销", "重做"]),
              "\(column.side.rawValue) 形状 mode exposes rectangle, ellipse, line, arrow, palette and history")

        toolbar.applyMode(.read)
        settle(0.2)
        check(toolbar.secondaryHeightForTesting == 0 && !toolbar.hasSecondaryRow,
              "\(column.side.rawValue) returning to 阅读 collapses the secondary row again")
    }

    reader.leftCol.columnToolbar.applyMode(.annotate)
    settle(0.25)
    reader.view.layoutSubtreeIfNeeded()
    check(reader.rightCol.columnToolbar.mode == .read && reader.rightCol.columnToolbar.secondaryHeightForTesting == 0,
          "Changing the left column mode leaves the right column in read mode")
    for column in [reader.leftCol, reader.rightCol] {
        let expectedPDFHeight = column.bounds.height - column.columnToolbar.frame.height
        check(abs(column.pdfView.frame.height - expectedPDFHeight) < 2 && column.pdfView.scaleFactor > 0.01,
              "(column.side.rawValue) PDF view keeps the correct height below its toolbar after mode changes")
    }

    reader.leftCol.columnToolbar.setUndoRedoEnabled(canUndo: true, canRedo: false)
    reader.leftCol.columnToolbar.applyMode(.shape)
    settle(0.2)
    check(reader.leftCol.columnToolbar.undoEnabledForTesting && !reader.leftCol.columnToolbar.redoEnabledForTesting,
          "Column undo state survives switching from 批注 to 形状")
    reader.leftCol.columnToolbar.applyMode(.read)
    settle(0.2)

    let narrowToolbar = ColumnToolbarView(frame: NSRect(x: 0, y: 0, width: 180, height: 36))
    narrowToolbar.layout()
    let narrowTitles = ["大纲目录", "双页并排", "单页/连续滚动", "自适应宽度", "抓手漫游", "指针选择"]
    check(!narrowToolbar.overflowButtonForTesting.isHidden &&
          !narrowToolbar.modeMenuButtonForTesting.isHidden &&
          Set(narrowToolbar.overflowMenuTitlesForTesting()).isSuperset(of: narrowTitles),
          "Narrow columns keep every primary tool reachable through the overflow menu")
    check(narrowToolbar.modeMenuButtonForTesting.title == "阅读",
          "Narrow columns replace the mode tabs with the current mode menu")
    narrowToolbar.applyMode(.annotate)
    narrowToolbar.layout()
    check(narrowToolbar.secondaryHeightForTesting == 32 && narrowToolbar.modeMenuButtonForTesting.title == "批注",
          "Narrow columns still expand annotation tools and update the mode menu")
    check(Set(narrowToolbar.overflowMenuTitlesForTesting()).isSuperset(of: ["撤销批注", "重做批注", "选择颜色…"]),
          "Narrow annotation mode keeps undo, redo and color reachable from the overflow menu")

    // Integration pass: the real reader window must route a shape gesture
    // through its column toolbar and PDF view (not just the isolated probe).
    let readerWindow = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1360, height: 860),
                                styleMask: [.titled], backing: .buffered, defer: false)
    readerWindow.contentViewController = reader
    readerWindow.makeKeyAndOrderFront(nil)
    settle(0.35)
    reader.view.layoutSubtreeIfNeeded()
    reader.leftCol.columnToolbar.applyMode(.shape)
    settle(0.35)
    reader.view.layoutSubtreeIfNeeded()
    if let page = reader.leftCol.pdfView.document?.page(at: 0) {
        let pdf = reader.leftCol.pdfView
        let pagePoint = pdf.convert(NSPoint(x: pdf.bounds.midX, y: pdf.bounds.midY), to: page)
        let endPage = NSPoint(x: pagePoint.x + 70, y: pagePoint.y + 35)
        let startWindow = pdf.convert(pdf.convert(pagePoint, from: page), to: nil)
        let endWindow = pdf.convert(pdf.convert(endPage, from: page), to: nil)
        func readerEvent(_ type: NSEvent.EventType, at p: NSPoint, pressure: Float) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                               windowNumber: readerWindow.windowNumber, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: pressure)
        }
        if let down = readerEvent(.leftMouseDown, at: startWindow, pressure: 1),
           let move = readerEvent(.leftMouseDragged, at: endWindow, pressure: 1),
           let up = readerEvent(.leftMouseUp, at: endWindow, pressure: 0) {
            readerWindow.sendEvent(down)
            readerWindow.sendEvent(move)
            readerWindow.sendEvent(up)
        }
        settle(0.25)
        check(page.annotations.contains { $0.type == "Square" && $0.userName == "DualPDF_Markup" },
              "A shape gesture in the actual reader window creates an annotation")
    } else {
        check(false, "Reader integration shape gesture has a document page")
    }
    reader.leftCol.columnToolbar.applyMode(.read)
    readerWindow.orderOut(nil)

    // Mode tabs: text-only underline on the selected mode only
    let leftTabs = descendants(reader.leftCol.columnToolbar).compactMap { $0 as? ColumnModeTabView }
    check(leftTabs.map(\.mode.title) == ["阅读", "批注", "形状"], "Left column renders three text-only mode tabs")
    check(leftTabs.first(where: { $0.mode == .read })?.isUnderlineVisibleForTesting == true &&
          leftTabs.first(where: { $0.mode == .annotate })?.isUnderlineVisibleForTesting == false,
          "Selected 阅读 tab owns the underline and unselected tabs have none")

    // Hand tool selection reaches the PDF view
    if let hand = descendants(reader.leftCol.columnToolbar).compactMap({ $0 as? NSButton }).first(where: { $0.toolTip == "抓手漫游" }) {
        hand.performClick(nil)
        check(reader.leftCol.pdfView.markupTool == .hand, "抓手漫游 button selects the hand tool for its own column")
    } else {
        check(false, "Left toolbar provides a hand tool button")
    }
    if let pointer = descendants(reader.leftCol.columnToolbar).compactMap({ $0 as? NSButton }).first(where: { $0.toolTip == "指针选择" }) {
        pointer.performClick(nil)
        check(reader.leftCol.pdfView.markupTool == .pointer, "指针选择 button restores the pointer tool")
    }

    // Page capsule fade, idle hide, and hover persistence
    let capsule = reader.leftCol.pageCapsule
    // The reader briefly reveals the capsule once after loading, so force the
    // idle state before testing the scroll-driven lifecycle.
    reader.leftCol.expireHideForTesting()
    reader.rightCol.expireHideForTesting()
    check(capsule.isHidden, "Page capsule starts hidden once the initial reveal expires")
    reader.leftCol.revealPageCapsule(hideAfter: 0.35)
    settle(0.25)
    check(!capsule.isHidden && capsule.alphaValue > 0.9, "Page capsule fades in when the column scrolls")
    check(waitUntil({ capsule.isHidden }, timeout: 2.0), "Page capsule hides after the idle interval")
    reader.leftCol.revealPageCapsule(hideAfter: 0.35)
    settle(0.2)
    reader.leftCol.capsuleHoverChanged(true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    check(!capsule.isHidden && capsule.alphaValue > 0.9, "Hovering the page capsule cancels the hide timer")
    reader.leftCol.capsuleHoverChanged(false)
    check(waitUntil({ capsule.isHidden }, timeout: 3.0), "Leaving the capsule restarts the idle hide timer")

    // Page capsule input commits a page jump
    reader.leftCol.pdfView.go(to: reader.leftCol.pdfView.document!.page(at: 0)!)
    settle()
    capsule.pageField.stringValue = "4"
    if let action = capsule.pageField.action {
        NSApp.sendAction(action, to: capsule.pageField.target, from: capsule.pageField)
    }
    settle(0.35)
    let currentPage = reader.leftCol.pdfView.document.map { doc in
        reader.leftCol.pdfView.currentPage.map { doc.index(for: $0) } ?? -1
    } ?? -1
    check(currentPage == 3, "Typing a page number and pressing Return jumps the owning column to that page")

    // Command + wheel zoom: target column only, clamped to 0.25x...5.0x
    let leftBefore = reader.leftCol.pdfView.scaleFactor
    let rightBefore = reader.rightCol.pdfView.scaleFactor
    reader.leftCol.pdfView.onCommandScrollZoom?(min(5.0, max(0.25, leftBefore * 1.25)))
    settle(0.25)
    check(abs(reader.leftCol.pdfView.scaleFactor - min(5.0, leftBefore * 1.25)) < 0.03,
          "Command zoom scales the hovered column")
    check(abs(reader.rightCol.pdfView.scaleFactor - rightBefore) < 0.002,
          "Command zoom leaves the other column untouched")
    reader.leftCol.pdfView.onCommandScrollZoom?(9.0)
    settle(0.2)
    check(reader.leftCol.pdfView.scaleFactor <= 5.001, "Command zoom is capped at 5.0x")
    reader.leftCol.pdfView.onCommandScrollZoom?(0.01)
    settle(0.2)
    check(reader.leftCol.pdfView.scaleFactor >= 0.249, "Command zoom is floored at 0.25x")

    // Real gesture pass: annotation tools must add native PDF annotations and
    // push column-local undo history.
    let probeWindow = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 700, height: 900),
                               styleMask: [.titled], backing: .buffered, defer: false)
    let probeView = InteractivePDFView(frame: NSRect(x: 0, y: 0, width: 700, height: 900))
    probeWindow.contentView = probeView
    probeView.document = PDFDocument(url: source)
    probeView.displayMode = .singlePageContinuous
    probeView.autoScales = false
    probeView.scaleFactor = 1.2
    probeWindow.makeKeyAndOrderFront(nil)
    settle(0.45)
    probeView.layoutSubtreeIfNeeded()
    guard let probePage = probeView.document?.page(at: 0) else {
        check(false, "Markup gesture probe page is available")
        return
    }
    func windowPoint(_ pagePoint: NSPoint) -> NSPoint {
        let viewPoint = probeView.convert(pagePoint, from: probePage)
        return probeView.convert(viewPoint, to: nil)
    }
    func dragGesture(from start: NSPoint, to end: NSPoint, tool: PDFMarkupTool) {
        probeView.markupTool = tool
        probeView.markupColor = .systemYellow
        let a = windowPoint(start)
        let b = windowPoint(end)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: a, modifierFlags: [], timestamp: 0,
                                            windowNumber: probeWindow.windowNumber, context: nil, eventNumber: 1,
                                            clickCount: 1, pressure: 1),
              let move = NSEvent.mouseEvent(with: .leftMouseDragged, location: b, modifierFlags: [], timestamp: 0,
                                            windowNumber: probeWindow.windowNumber, context: nil, eventNumber: 2,
                                            clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: b, modifierFlags: [], timestamp: 0,
                                          windowNumber: probeWindow.windowNumber, context: nil, eventNumber: 3,
                                          clickCount: 1, pressure: 0) else { return }
        // Deliver through the window so PDFKit's private page views get a
        // chance to swallow the event first. Calling the view directly hides
        // regressions in hit testing, which previously made every markup tool
        // inert in the real app.
        probeWindow.sendEvent(down)
        probeWindow.sendEvent(move)
        probeWindow.sendEvent(up)
        settle(0.12)
    }
    func clickGesture(at point: NSPoint, tool: PDFMarkupTool) {
        probeView.markupTool = tool
        let p = windowPoint(point)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0,
                                            windowNumber: probeWindow.windowNumber, context: nil, eventNumber: 1,
                                            clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: 0,
                                          windowNumber: probeWindow.windowNumber, context: nil, eventNumber: 2,
                                          clickCount: 1, pressure: 0) else { return }
        probeWindow.sendEvent(down)
        probeWindow.sendEvent(up)
        settle(0.12)
    }
    func markupCount(_ type: String) -> Int {
        probePage.annotations.filter { $0.type == type && $0.userName == "DualPDF_Markup" }.count
    }

    dragGesture(from: NSPoint(x: 40, y: 450), to: NSPoint(x: 240, y: 468), tool: .highlight)
    check(markupCount("Highlight") == 1, "高亮 tool creates a native PDF highlight annotation")
    check(probeView.canUndoMarkup, "Markup action enables this column's undo stack")
    probeView.undo(nil)
    check(markupCount("Highlight") == 0 && probeView.canRedoMarkup, "Standard undo removes the annotation and enables redo")
    probeView.redo(nil)
    check(markupCount("Highlight") == 1, "Standard redo restores the annotation")

    dragGesture(from: NSPoint(x: 60, y: 300), to: NSPoint(x: 200, y: 380), tool: .rectangle)
    check(markupCount("Square") == 1, "矩形 tool creates a rectangle annotation")
    clickGesture(at: NSPoint(x: 130, y: 340), tool: .eraser)
    check(markupCount("Square") == 0, "橡皮擦 removes the markup under the pointer")

    probeView.addTextMarkupForTesting(text: "测试文本", page: probePage, at: NSPoint(x: 70, y: 250))
    let freeText = probePage.annotations.first { $0.type == "FreeText" && $0.userName == "DualPDF_Markup" }
    check(markupCount("FreeText") == 1 && freeText?.contents == "测试文本",
          "文本 tool creates an editable free-text annotation with the entered content")
    if let color = freeText?.fontColor?.usingColorSpace(.deviceRGB) {
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        check(luminance < 0.6, "Text annotations darken bright highlight colors for readability on white paper")
    } else {
        check(false, "Text annotation exposes a readable font color")
    }
    dragGesture(from: NSPoint(x: 60, y: 200), to: NSPoint(x: 170, y: 240), tool: .ink)
    check(markupCount("Ink") == 1, "画笔 tool creates an ink annotation")
    dragGesture(from: NSPoint(x: 40, y: 450), to: NSPoint(x: 240, y: 468), tool: .underline)
    check(markupCount("Underline") == 1, "下划线 tool creates an underline annotation")
    dragGesture(from: NSPoint(x: 40, y: 450), to: NSPoint(x: 240, y: 468), tool: .strikethrough)
    check(markupCount("StrikeOut") == 1, "删除线 tool creates a strike-out annotation")

    // A persisted highlight is rendered by PDFKit, but its note popover is
    // owned by InteractivePDFView. PDFKit's page views must not swallow that
    // click before the app can show the existing-annotation popover.
    let stored = PaperAnnotation(side: .original, pageIndex: 0,
                                 rects: [RectCodable(NSRect(x: 40, y: 450, width: 200, height: 18))],
                                 selectedText: "toolbar alpha beta gamma", color: .yellow,
                                 markdownNote: "existing note", linkedURL: nil, linkedTitle: nil,
                                 pdfDocumentId: "original")
    var clickedStoredAnnotation: PaperAnnotation?
    probeView.markupTool = .pointer
    probeView.storedAnnotations = [stored]
    probeView.onAnnotationClicked = { annotation, _ in clickedStoredAnnotation = annotation }
    clickGesture(at: NSPoint(x: 140, y: 459), tool: .pointer)
    check(clickedStoredAnnotation == stored,
          "Clicking a persisted highlight routes to the existing-note handler")

    probeWindow.orderOut(nil)
    probeView.document = nil
}


/// Closing a paper tab warns when session DualPDF_Markup edits are still applied.
func runSessionMarkupCloseAlertTests(root: URL) throws {
    func settle(_ seconds: TimeInterval = 0.12) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    let source = root.appendingPathComponent("markup-close-original.pdf")
    try writePDF(source, pages: 2, text: "markup close fixture")
    let store = LibraryStore.shared
    let paper = store.createPaper(title: "Markup close \(UUID().uuidString)", originalSourceURL: source)!

    let wc = MultiTabMainWindowController()
    defer {
        wc.testingDiscardSessionMarkupResponse = true
        for pid in [paper.id] where wc.isPaperTabOpen(pid) {
            wc.closePaperTab(paperId: pid, force: true)
        }
        wc.close()
    }

    // --- No markup: close immediately ---
    wc.openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil, switchImmediately: true)
    settle(0.25)
    guard let readerNoMarkup = wc.activeReaderVC else {
        check(false, "Markup-close: opened reader without markup")
        return
    }
    _ = readerNoMarkup.view
    settle(0.2)
    check(waitUntil({ readerNoMarkup.leftCol.pdfView.document != nil }, timeout: 4),
          "Markup-close: PDF loads for no-markup case")
    check(!readerNoMarkup.hasUnpersistedColumnMarkup(),
          "Markup-close: fresh tab has no session markup")
    wc.testingDiscardSessionMarkupResponse = false // would cancel if prompted; should not prompt
    wc.closePaperTab(paperId: paper.id)
    check(!wc.isPaperTabOpen(paper.id),
          "Markup-close: tab without markup closes without needing confirm")

    // --- With markup: cancel keeps tab; confirm closes ---
    wc.openOrSwitchToPaperTab(paperId: paper.id, jumpToAnnot: nil, switchImmediately: true)
    settle(0.25)
    guard let reader = wc.activeReaderVC else {
        check(false, "Markup-close: reopened reader")
        return
    }
    _ = reader.view
    settle(0.2)
    check(waitUntil({ reader.leftCol.pdfView.document != nil }, timeout: 4),
          "Markup-close: PDF loads for markup case")
    guard let page = reader.leftCol.pdfView.document?.page(at: 0) else {
        check(false, "Markup-close: page 0 available")
        return
    }
    reader.leftCol.pdfView.addTextMarkupForTesting(text: "仅本次", page: page, at: NSPoint(x: 80, y: 200))
    settle()
    check(reader.hasUnpersistedColumnMarkup() && reader.leftCol.pdfView.canUndoMarkup,
          "Markup-close: session markup present after DualPDF_Markup edit")

    wc.testingDiscardSessionMarkupResponse = false
    wc.closePaperTab(paperId: paper.id)
    check(wc.isPaperTabOpen(paper.id),
          "Markup-close: choosing 取消 keeps the tab open")
    check(reader.hasUnpersistedColumnMarkup(),
          "Markup-close: session markup still present after cancel")

    // Quit path (⌘Q / last window closed → applicationShouldTerminate) must see the same markup.
    let app = AppDelegate()
    app.testingMainWindowControllers = [wc]
    var flushCount = 0
    app.testingFlushReadingState = { flushCount += 1; return true }
    check(app.unpersistedSessionMarkupTabCount() == 1,
          "Quit-markup: one tab with session markup is counted")
    app.testingQuitDiscardSessionMarkupResponse = false
    check(app.applicationShouldTerminate(NSApp) == .terminateCancel,
          "Quit-markup: choosing 取消 cancels termination")
    check(flushCount == 0 && wc.isPaperTabOpen(paper.id) && reader.hasUnpersistedColumnMarkup(),
          "Quit-markup: cancel does not flush and keeps markup")
    app.testingQuitDiscardSessionMarkupResponse = true
    check(app.applicationShouldTerminate(NSApp) == .terminateNow,
          "Quit-markup: choosing 退出 terminates")
    check(flushCount == 1, "Quit-markup: flushReadingState runs once after confirming quit")

    wc.testingDiscardSessionMarkupResponse = true
    wc.closePaperTab(paperId: paper.id)
    check(!wc.isPaperTabOpen(paper.id),
          "Markup-close: choosing 关闭 discards session markup and closes the tab")

    // No markup left: quit must not prompt (a forced 取消 would cancel if it did).
    app.testingQuitDiscardSessionMarkupResponse = false
    check(app.unpersistedSessionMarkupTabCount() == 0,
          "Quit-markup: no session markup counted after tab closed")
    check(app.applicationShouldTerminate(NSApp) == .terminateNow && flushCount == 2,
          "Quit-markup: without markup quit terminates without prompting and flushes")
}

