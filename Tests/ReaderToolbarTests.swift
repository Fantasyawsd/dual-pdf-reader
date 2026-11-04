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

    UserDefaults.standard.removeObject(forKey: "ReaderUnifiedMarkupHidden")
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

    // Per-column reading controls; markup tools live in the shared top bar.
    for column in [reader.leftCol, reader.rightCol] {
        let toolbar = column.columnToolbar
        check(toolbar.modeControlsHiddenForTesting,
              "\(column.side.rawValue) hides its per-column 阅读/批注/形状 controls")
        check(toolbar.visibleToolTips.contains("大纲目录") &&
              toolbar.visibleToolTips.contains("单页/连续滚动") &&
              toolbar.visibleToolTips.contains("自适应宽度") &&
              toolbar.visibleToolTips.contains("抓手漫游") &&
              toolbar.visibleToolTips.contains("指针选择") &&
              toolbar.visibleToolTips.contains("页内搜索") &&
              toolbar.visibleToolTips.contains("随手笔记"),
              "\(column.side.rawValue) primary toolbar exposes the required reading controls")
        let visibleToolbarButtons = descendants(toolbar).compactMap { $0 as? NSButton }.filter { !$0.isHiddenOrHasHiddenAncestor }
        check(!visibleToolbarButtons.isEmpty && visibleToolbarButtons.allSatisfy { !($0.toolTip ?? "").isEmpty },
              "every visible per-column toolbar control exposes a hover tooltip")
        check(toolbar.secondaryHeightForTesting == 0 && !toolbar.hasSecondaryRow,
              "\(column.side.rawValue) keeps the secondary markup row collapsed")
    }

    if reader.isTopBarHiddenForTesting {
        reader.markupToolbarToggleForTesting.performClick(nil)
        settle(0.2)
    }
    let unifiedTips = Set(reader.unifiedMarkupToolbar.toolTipsForTesting)
    check(unifiedTips.isSuperset(of: ["指针选择", "高亮", "下划线", "删除线", "画笔", "橡皮擦", "文本",
                                      "矩形", "椭圆", "直线", "箭头", "选择颜色", "撤销", "重做"]),
          "Unified toolbar exposes annotation, shape, palette and history tools")
    check(unifiedTips.filter { $0 == "选择颜色" }.count == 1,
          "Unified toolbar uses a single palette control")
    check(!unifiedTips.contains("琥珀黄") && !unifiedTips.contains("翠竹绿"),
          "Unified toolbar does not flatten color swatches into the toolbar")

    let unifiedButtons = descendants(reader.unifiedMarkupToolbar).compactMap { $0 as? NSButton }
    if let rectangle = unifiedButtons.first(where: { $0.toolTip == "矩形" }) {
        rectangle.performClick(nil)
        settle(0.15)
        check(reader.leftCol.pdfView.markupTool == .rectangle && reader.rightCol.pdfView.markupTool == .rectangle,
              "Choosing a shape in the unified toolbar activates it in both columns")
    } else {
        check(false, "Unified toolbar provides a rectangle button")
    }
    if let pointer = unifiedButtons.first(where: { $0.toolTip == "指针选择" }) {
        pointer.performClick(nil)
        settle(0.15)
        check(reader.leftCol.pdfView.markupTool == .pointer && reader.rightCol.pdfView.markupTool == .pointer,
              "Pointer mode in the unified toolbar applies to both columns")
    } else {
        check(false, "Unified toolbar provides a pointer button")
    }

    if reader.isTopBarHiddenForTesting {
        reader.topBarShowButtonForTesting.performClick(nil)
        settle(0.2)
    }
    reader.markupToolbarToggleForTesting.performClick(nil)
    settle(0.2)
    reader.view.layoutSubtreeIfNeeded()
    check(reader.isTopBarHiddenForTesting && reader.isTopBarShowButtonVisibleForTesting &&
          reader.topBarShowButtonForTesting.frame.width >= 20,
          "The whole top bar can be hidden with a visible restore handle")
    reader.topBarShowButtonForTesting.performClick(nil)
    settle(0.2)
    check(!reader.isTopBarHiddenForTesting, "The top bar can be shown again")
    UserDefaults.standard.removeObject(forKey: "ReaderUnifiedMarkupHidden")

    for column in [reader.leftCol, reader.rightCol] {
        let expectedPDFHeight = column.bounds.height - column.columnToolbar.frame.height
        check(abs(column.pdfView.frame.height - expectedPDFHeight) < 2 && column.pdfView.scaleFactor > 0.01,
              "(column.side.rawValue) PDF view keeps the correct height below its toolbar")
    }

    let narrowToolbar = ColumnToolbarView(frame: NSRect(x: 0, y: 0, width: 180, height: 36))
    narrowToolbar.layout()
    let narrowTitles = ["大纲目录", "单页/连续滚动", "自适应宽度", "抓手漫游", "指针选择"]
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
        let paperAfterShape = store.paper(withId: paper.id)
        let originalShape = paperAfterShape?.annotations.first { $0.effectiveKind == .rectangle }
        check(originalShape != nil,
              "A shape gesture in the actual reader window persists a rectangle model")
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

    // Synced scrolling must refresh both capsules; moving the target column
    // happens inside a suppressed viewport update, so it cannot rely on
    // PDFKit's own bounds notification.
    reader.setDisplayMode(2)
    settle(0.3)
    PDFScrollSynchronizer.scroll(to: 4.0, in: reader.leftCol)
    if let clip = reader.leftCol.internalScrollView()?.contentView {
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
    }
    settle(0.5)
    let syncedPage = Int(reader.leftCol.pageCapsule.pageField.stringValue) ?? 0
    check(reader.leftCol.pageCapsule.pageField.stringValue ==
          reader.rightCol.pageCapsule.pageField.stringValue && syncedPage > 1,
          "Synced scrolling refreshes the page number in both columns")

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

    // Real gesture pass: annotation tools persist PaperAnnotation models and
    // push column-local command history.
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
    let probePaper = store.createPaper(title: "Markup edit \(UUID().uuidString)", originalSourceURL: source)!
    let probeColumn = CleanPDFColumnView(side: .original)
    probeColumn.pdfView.document = probeView.document
    let probeRenderer = PDFAnnotationRenderer()
    var savePaperCallCount = 0
    var probeModels: [String: PaperAnnotation] = [:]
    var deleteBatches: [[String]] = []
    var createBatches: [[PaperAnnotation]] = []
    var markupUpdateCount = 0
    var visibilityChanges: [Set<String>] = []
    var nextMarkupEventNumber = 1
    func mutateProbePaper(_ mutation: (inout PaperItem) -> Void) {
        guard var stored = store.paper(withId: probePaper.id) else { return }
        mutation(&stored)
        savePaperCallCount += 1
        _ = store.savePaper(stored, notify: false)
    }
    probeView.onMarkupCreate = { models in
        createBatches.append(models)
        models.forEach { probeModels[$0.id] = $0 }
        mutateProbePaper { stored in
            for source in models {
                var model = source
                model.side = probeColumn.side
                model.pdfDocumentId = probeColumn.activePDFDocumentId
                if let index = stored.annotations.firstIndex(where: { $0.id == model.id }) {
                    stored.annotations[index] = model
                } else {
                    stored.annotations.append(model)
                }
            }
        }
        probeView.storedAnnotations = Array(probeModels.values)
        probeRenderer.apply(Array(probeModels.values), to: probeColumn)
    }
    probeView.onMarkupUpdate = { model in
        markupUpdateCount += 1
        probeModels[model.id] = model
        probeView.storedAnnotations = Array(probeModels.values)
        mutateProbePaper { stored in
            if let index = stored.annotations.firstIndex(where: { $0.id == model.id }) {
                stored.annotations[index] = model
            }
        }
        probeRenderer.apply(Array(probeModels.values), to: probeColumn)
    }
    probeView.onMarkupDelete = { ids in
        deleteBatches.append(ids)
        ids.forEach { probeModels.removeValue(forKey: $0) }
        probeView.storedAnnotations = Array(probeModels.values)
        mutateProbePaper { stored in
            let idSet = Set(ids)
            stored.annotations.removeAll { idSet.contains($0.id) }
        }
        probeRenderer.apply(Array(probeModels.values), to: probeColumn)
    }
    probeView.onMarkupVisibilityChanged = { ids in
        visibilityChanges.append(ids)
        probeRenderer.setHidden(ids, in: probeColumn)
    }
    func windowPoint(_ pagePoint: NSPoint) -> NSPoint {
        let viewPoint = probeView.convert(pagePoint, from: probePage)
        return probeView.convert(viewPoint, to: nil)
    }
    func dragGesture(from start: NSPoint, to end: NSPoint, tool: PDFMarkupTool,
                     modifiers: NSEvent.ModifierFlags = []) {
        probeView.markupTool = tool
        probeView.markupColor = .systemYellow
        let a = windowPoint(start)
        let b = windowPoint(end)
        let downNumber = nextMarkupEventNumber
        let moveNumber = downNumber + 1
        let upNumber = downNumber + 2
        nextMarkupEventNumber += 3
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: a, modifierFlags: modifiers, timestamp: timestamp,
                                            windowNumber: probeWindow.windowNumber, context: nil, eventNumber: downNumber,
                                            clickCount: 1, pressure: 1),
              let move = NSEvent.mouseEvent(with: .leftMouseDragged, location: b, modifierFlags: modifiers, timestamp: timestamp + 0.001,
                                            windowNumber: probeWindow.windowNumber, context: nil, eventNumber: moveNumber,
                                            clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: b, modifierFlags: modifiers, timestamp: timestamp + 0.002,
                                          windowNumber: probeWindow.windowNumber, context: nil, eventNumber: upNumber,
                                          clickCount: 1, pressure: 0) else { return }
        if tool.isTextMarkup {
            // PDFKit's native text-selection handler tracks the gesture
            // synchronously from mouseDown, so queue the remaining events.
            NSApp.postEvent(move, atStart: false)
            NSApp.postEvent(up, atStart: false)
            probeWindow.sendEvent(down)
        } else {
            probeWindow.sendEvent(down)
            probeWindow.sendEvent(move)
            probeWindow.sendEvent(up)
        }
        settle(0.12)
    }
    func clickGesture(at point: NSPoint, tool: PDFMarkupTool) {
        probeView.markupTool = tool
        let p = windowPoint(point)
        let downNumber = nextMarkupEventNumber
        let upNumber = downNumber + 1
        nextMarkupEventNumber += 2
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: timestamp,
                                            windowNumber: probeWindow.windowNumber, context: nil, eventNumber: downNumber,
                                            clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: timestamp + 0.001,
                                          windowNumber: probeWindow.windowNumber, context: nil, eventNumber: upNumber,
                                          clickCount: 1, pressure: 0) else { return }
        if tool.isTextMarkup {
            NSApp.postEvent(up, atStart: false)
            probeWindow.sendEvent(down)
        } else {
            probeWindow.sendEvent(down)
            probeWindow.sendEvent(up)
        }
        settle(0.12)
    }
    func markupCount(_ kind: PaperAnnotationKind) -> Int {
        probeModels.values.filter { $0.effectiveKind == kind }.count
    }

    // Pointer mode routes page hits to InteractivePDFView for markup
    // selection. Wheel events must still reach PDFKit's internal scroll view,
    // otherwise the entire reader becomes unscrollable.
    if let scroll = descendants(probeView).compactMap({ $0 as? NSScrollView }).first,
       let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                        wheel1: -80, wheel2: 0, wheel3: 0),
       let wheel = NSEvent(cgEvent: cg) {
        probeView.markupTool = .pointer
        let before = scroll.contentView.bounds.origin.y
        probeView.scrollWheel(with: wheel)
        settle(0.25)
        let after = scroll.contentView.bounds.origin.y
        check(after > before + 1, "Pointer mode keeps the PDF scrollable with the wheel")
    } else {
        check(false, "Scroll fixture exposes an NSScrollView and wheel event")
    }

    dragGesture(from: NSPoint(x: 40, y: 450), to: NSPoint(x: 240, y: 468), tool: .highlight)
    check(markupCount(.highlight) == 1, "高亮 tool creates a persisted highlight model")
    check(probeView.canUndoMarkup, "Markup action enables this column's undo stack")
    let highlightID = probeModels.values.first(where: { $0.effectiveKind == .highlight })?.id
    probeView.undo(nil)
    check(markupCount(.highlight) == 0 && probeView.canRedoMarkup, "Undo deletes the persisted markup model")
    probeView.redo(nil)
    check(markupCount(.highlight) == 1 && probeModels[highlightID ?? ""]?.id == highlightID,
          "Redo restores a highlight model with the same ID")
    if let highlightID, let highlight = probeModels[highlightID],
       let rect = highlight.pageRegions.first?.rects.first?.cgRect {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let beforeUpdates = markupUpdateCount
        let beforeUndo = probeView.markupUndoCount
        let beforeVisibility = visibilityChanges.count
        var annotationClickCount = 0
        probeView.onAnnotationClicked = { _, _ in annotationClickCount += 1 }
        dragGesture(from: center, to: NSPoint(x: center.x + 8, y: center.y + 4), tool: .pointer)
        let after = probeModels[highlightID]
        check(probeView.selectedMarkupId == highlightID &&
              after?.rects == highlight.rects && after?.pageRegions == highlight.pageRegions,
              "Pointer click-drag selects a highlight without moving its text-anchored geometry")
        check(markupUpdateCount == beforeUpdates && probeView.markupUndoCount == beforeUndo &&
              visibilityChanges.count == beforeVisibility && annotationClickCount == 1,
              "Pointer click-drag on a highlight only routes its click callback")
    } else {
        check(false, "Highlight exposes text-markup geometry for pointer selection")
    }

    dragGesture(from: NSPoint(x: 60, y: 300), to: NSPoint(x: 200, y: 380), tool: .rectangle)
    check(markupCount(.rectangle) == 1, "矩形 tool creates a rectangle model")
    dragGesture(from: NSPoint(x: 260, y: 150), to: NSPoint(x: 300, y: 180),
                tool: .rectangle, modifiers: [.shift])
    let constrainedShape = probeModels.values.first {
        $0.effectiveKind == .rectangle &&
            abs(($0.rects.first?.cgRect.minX ?? 0) - 260) < 2
    }?.rects.first?.cgRect
    check(constrainedShape != nil && abs(constrainedShape!.width - constrainedShape!.height) < 0.1,
          "Shift-drawing a rectangle constrains it to a square")
    let rectangleID = probeModels.values.first(where: {
        $0.effectiveKind == .rectangle && ($0.rects.first?.cgRect.minX ?? 1000) < 200
    })?.id
    guard let initialRectangle = rectangleID.flatMap({ probeModels[$0] })?.rects.first?.cgRect else {
        check(false, "Rectangle model stores its geometry")
        return
    }
    let center = NSPoint(x: initialRectangle.midX, y: initialRectangle.midY)
    if let rectangleID, let rectangle = probeModels[rectangleID] {
        let beforeUpdates = markupUpdateCount
        let beforeUndo = probeView.markupUndoCount
        let beforeVisibility = visibilityChanges.count
        let beforeSaveCalls = savePaperCallCount
        let annotationsBeforeClick = store.paper(withId: probePaper.id)?.annotations
        let renderedRectangle = probePage.annotations.first {
            $0.userName == "DualPDF_CustomAnnot" && $0.type == "Square"
        }
        check(renderedRectangle != nil, "Created rectangle has a rendered PDFAnnotation")
        check(createBatches.last?.count == 1, "A single markup create is delivered as a one-item batch")
        clickGesture(at: center, tool: .pointer)
        check(probeView.selectedMarkupId == rectangleID && probeModels[rectangleID] == rectangle &&
              store.paper(withId: probePaper.id)?.annotations == annotationsBeforeClick &&
              markupUpdateCount == beforeUpdates && probeView.markupUndoCount == beforeUndo &&
              visibilityChanges.count == beforeVisibility && savePaperCallCount == beforeSaveCalls,
              "Pointer click selects a rectangle without hiding, updating, saving, or recording undo")
        check(renderedRectangle.map { value in probePage.annotations.contains { $0 === value } } == true,
              "Pointer click leaves the rendered rectangle on its PDF page after mouse-up")
    }
    dragGesture(from: center, to: NSPoint(x: center.x + 14, y: center.y + 9), tool: .pointer)
    let movedRectangle = rectangleID.flatMap { probeModels[$0] }
    // Page/view coordinate round-trips introduce tiny float error; compare
    // with a sub-point tolerance instead of exact equality.
    check(abs((movedRectangle?.rects.first?.cgRect.minX ?? -999) - (initialRectangle.minX + 14)) < 0.01 &&
          movedRectangle?.id == rectangleID, "Pointer selection moves a rectangle model without changing its ID")
    if let movedRect = movedRectangle?.rects.first?.cgRect {
        let corner = NSPoint(x: movedRect.maxX, y: movedRect.minY)
        dragGesture(from: corner, to: NSPoint(x: corner.x + 18, y: corner.y - 7),
                    tool: .pointer, modifiers: [.shift])
    }
    let resizedRectangle = rectangleID.flatMap { probeModels[$0] }?.rects.first?.cgRect
    check(resizedRectangle != nil && abs(resizedRectangle!.width - resizedRectangle!.height) < 0.1,
          "Shift-resizing a rectangle preserves its square aspect ratio")
    let paletteUndoCount = probeView.markupUndoCount
    probeView.updateSelectedMarkupColor(.systemRed)
    check(probeView.markupUndoCount == paletteUndoCount + 1 &&
          rectangleID.flatMap({ probeModels[$0] })?.colorHex != nil,
          "Changing selected markup color is one model undo command")
    probeView.undoMarkup()
    check(rectangleID.flatMap({ probeModels[$0] })?.color == .nearest(to: .systemYellow),
          "Undo restores the previous markup color")

    let beforeDeleteID = rectangleID
    let deleteEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: 0, windowNumber: probeWindow.windowNumber, context: nil,
                                       characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
                                       isARepeat: false, keyCode: 51)
    if let deleteEvent { probeView.keyDown(with: deleteEvent) }
    check(beforeDeleteID != nil && beforeDeleteID.flatMap { probeModels[$0] } == nil,
          "Delete removes the selected model")
    probeView.undoMarkup()
    check(beforeDeleteID.flatMap { probeModels[$0] }?.id == beforeDeleteID,
          "Undo recreates a deleted markup with the same ID")

    clickGesture(at: NSPoint(x: 130, y: 340), tool: .eraser)
    check(markupCount(.rectangle) == 1, "橡皮擦 removes the markup under the pointer")
    probeView.undoMarkup()
    check(markupCount(.rectangle) == 2, "Undo restores an erased model")

    probeView.addTextMarkupForTesting(text: "测试文本", page: probePage, at: NSPoint(x: 70, y: 250))
    let textModel = probeModels.values.first { $0.effectiveKind == .text }
    check(markupCount(.text) == 1 && textModel?.selectedText == "测试文本",
          "文本 tool persists editable text in a model")
    dragGesture(from: NSPoint(x: 60, y: 200), to: NSPoint(x: 170, y: 240), tool: .ink)
    check(markupCount(.ink) == 1, "画笔 tool creates an ink model")
    if let ink = probeModels.values.first(where: { $0.effectiveKind == .ink }),
       let path = ink.inkPaths?.first {
        let midpoint = NSPoint(x: (path[0].x + path[1].x) / 2, y: (path[0].y + path[1].y) / 2)
        clickGesture(at: midpoint, tool: .pointer)
        check(probeView.selectedMarkupId == ink.id, "Ink is selectable by its rendered stroke geometry")
    } else {
        check(false, "Ink model persists sampled path points")
    }
    dragGesture(from: NSPoint(x: 270, y: 150), to: NSPoint(x: 340, y: 180), tool: .arrow)
    let arrowBefore = probeModels.values.first { $0.effectiveKind == .arrow }
    if let arrow = arrowBefore, let end = arrow.endPoint?.cgPoint {
        dragGesture(from: end, to: NSPoint(x: end.x + 12, y: end.y + 8), tool: .pointer)
        let arrowAfter = probeModels[arrow.id]
        check(arrowAfter?.endPoint != arrow.endPoint && arrowAfter?.startPoint == arrow.startPoint,
              "Arrow endpoint handles update the model endpoint")
    } else {
        check(false, "Arrow tool persists both endpoints")
    }

    dragGesture(from: NSPoint(x: 360, y: 300), to: NSPoint(x: 400, y: 340), tool: .rectangle)
    dragGesture(from: NSPoint(x: 420, y: 300), to: NSPoint(x: 460, y: 340), tool: .rectangle)
    let batchesBeforeErase = deleteBatches.count
    let undoBeforeErase = probeView.markupUndoCount
    let erasedModelIDs = Set(probeModels.values.filter {
        guard $0.effectiveKind == .rectangle, let rect = $0.rects.first?.cgRect else { return false }
        return abs(rect.minX - 360) < 1 || abs(rect.minX - 420) < 1
    }.map(\.id))
    let eraseSaveCallsBefore = savePaperCallCount
    dragGesture(from: NSPoint(x: 380, y: 320), to: NSPoint(x: 440, y: 320), tool: .eraser)
    check(deleteBatches.count == batchesBeforeErase + 1 && deleteBatches.last?.count == 2 &&
          erasedModelIDs.count == 2 && probeView.markupUndoCount == undoBeforeErase + 1 &&
          savePaperCallCount == eraseSaveCallsBefore + 1 &&
          erasedModelIDs.allSatisfy { id in store.paper(withId: probePaper.id)?.annotations.contains { $0.id == id } == false },
          "A drag eraser deletes multiple hit models in one batch")
    let undoSaveCallsBefore = savePaperCallCount
    let createBatchCountBeforeUndo = createBatches.count
    probeView.undoMarkup()
    check(probeModels.values.filter { $0.effectiveKind == .rectangle }.count >= 2 &&
          createBatches.count == createBatchCountBeforeUndo + 1 &&
          Set(createBatches.last?.map(\.id) ?? []) == erasedModelIDs &&
          erasedModelIDs.allSatisfy { probeModels[$0] != nil } &&
          savePaperCallCount == undoSaveCallsBefore + 1 &&
          Set(store.paper(withId: probePaper.id)?.annotations
              .filter { erasedModelIDs.contains($0.id) }.map(\.id) ?? []) == erasedModelIDs,
          "One undo restores every erased model together with its original IDs")

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
    probeModels = [stored.id: stored]
    probeView.storedAnnotations = [stored]
    probeView.onAnnotationClicked = { annotation, _ in clickedStoredAnnotation = annotation }
    clickGesture(at: NSPoint(x: 140, y: 459), tool: .pointer)
    check(clickedStoredAnnotation == stored,
          "Clicking a persisted highlight routes to the existing-note handler")

    probeWindow.orderOut(nil)
    probeView.document = nil
}
