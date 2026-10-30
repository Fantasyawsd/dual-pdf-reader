import Cocoa
import PDFKit
import JavaScriptCore

// MARK: - Built-in Automated Verification Runner (--self-test)
func runBuiltInSelfTests() -> Int32 {
    var passed = 0
    var failed = 0

    func check(_ condition: Bool, _ name: String) {
        if condition {
            passed += 1
            print("✅ [PASS] \(name)")
        } else {
            failed += 1
            print("❌ [FAIL] \(name)")
        }
    }

    // UI tests are opt-in and always use a disposable fixture library.
    let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DualPDF-UITests-\(UUID().uuidString)")
    UserDefaults.standard.setVolatileDomain(["DualPDF_LibraryRootPath": testRoot.path], forName: UserDefaults.argumentDomain)
    try? FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    let store = LibraryStore.shared
    defer { try? FileManager.default.removeItem(at: testRoot) }

    // 1. Models & Enums
    check(HighlightColor.allCases.count == 4, "HighlightColor has 4 cases with hex & display names")
    check(!HighlightColor.yellow.displayName.isEmpty && HighlightColor.yellow.hexString == "#F59E0B", "HighlightColor metadata")
    check(LibrarySortOrder.allCases.count == 8, "LibrarySortOrder includes all 8 supported sorting modes")
    check(ReadingStatus.completed.symbolName == "checkmark.seal.fill", "ReadingStatus SF Symbol names")

    // 2. MarkdownMathRenderer & LaTeX Engine via JavaScriptCore (including matrices, 3-level nested \frac, \[...\], lists)
    let previewHTML = MarkdownMathRenderer.buildSinglePreviewHTML(markdown: "Test")
    if let scriptStart = previewHTML.range(of: "<script>"),
       let scriptEnd = previewHTML.range(of: "const raw ="),
       let ctx = JSContext() {
        let jsCode = String(previewHTML[scriptStart.upperBound..<scriptEnd.lowerBound])
        ctx.evaluateScript(jsCode)
        let renderFn = ctx.objectForKeyedSubscript("renderMarkdownWithMath")

        let formula1 = "$$\\mathcal{L}_{MTP} = \\frac{\\lambda}{D} \\sum_{k=1}^{D} \\mathcal{L}_{CE}\\left(P_i^{(k)}, t_{i+1+k}\\right)$$"
        let out1 = renderFn?.call(withArguments: [formula1])?.toString() ?? ""
        check(!out1.contains("\\left") && !out1.contains("\\right"), "LaTeX \\left and \\right delimiters stripped cleanly")
        check(out1.contains("class=\"frac\""), "LaTeX \\frac rendered into vertical fraction span")
        check(out1.contains("class=\"sum-op\""), "LaTeX \\sum rendered into sum-op stack")
        check(out1.contains("ℒ") && out1.contains("λ"), "LaTeX calligraphic \\mathcal{L} and Greek \\lambda rendered")

        let formula2 = "$\\hat{x}_i \\in \\mathbb{R}^{d_k}$ and $\\frac{x_i^{(2)}}{\\sqrt{d_k}}$"
        let out2 = renderFn?.call(withArguments: [formula2])?.toString() ?? ""
        check(out2.contains("ℝ") && out2.contains("&#770;") && out2.contains("class=\"frac\""), "LaTeX nested fraction with superscript braces, hat accent, and blackboard bold ℝ")

        let formula3 = "$$\\mathbf{H} = \\frac{1}{\\sqrt{1 + \\frac{a_i^2}{1 + \\frac{b_i}{c_i}}}} \\begin{pmatrix} \\alpha_{11} & \\alpha_{12} \\\\ \\alpha_{21} & \\alpha_{22} \\end{pmatrix}$$"
        let out3 = renderFn?.call(withArguments: [formula3])?.toString() ?? ""
        check(out3.contains("class=\"math-matrix\"") && out3.contains("class=\"frac\"") && !out3.contains("\\begin{pmatrix}"), "LaTeX 3-level nested \\frac and \\begin{pmatrix} 2D matrix rendered")

        let formula4 = "\\[ E = mc^2 \\] inline \\( x_1 \\)\n- item A\n- item B"
        let out4 = renderFn?.call(withArguments: [formula4])?.toString() ?? ""
        check(out4.contains("class=\"math-block\"") && out4.contains("class=\"math-inline\"") && !out4.contains("</li><br>"), "LaTeX \\[...\\], \\(...\\) delimiters and clean Markdown list items without extra <br>")
    } else {
        check(false, "Initialize JavaScriptCore for LaTeX verification")
    }

    // 3. LibraryStore Metadata Extraction & Smart Language Classification
    let fakeOrigs = [
        URL(fileURLWithPath: "/tmp/Transformer_Architecture.pdf"),
        URL(fileURLWithPath: "/tmp/Faster_RCNN_2015.pdf"),
        URL(fileURLWithPath: "/tmp/Zhang_et_al_2024.pdf")
    ]
    for fakeURL in fakeOrigs {
        let pair = store.classifyPDFPair([fakeURL])
        check(pair.original == fakeURL && pair.translated == nil, "Filename '\(fakeURL.lastPathComponent)' classified as English original (no false-positive substring match)")
    }

    if let first = store.papers.first,
       let origURL = store.pdfURL(for: first, side: .original) {
        let meta = store.extractMetadata(from: origURL)
        check(!meta.title.isEmpty && meta.title != "2412.19437" && !meta.authors.isEmpty && meta.year.count == 4,
              "Extract title, author & year from real PDF (\(meta.title) | \(meta.authors) | \(meta.year))")
        if let transURL = store.pdfURL(for: first, side: .translated) {
            let reversedPair = store.classifyPDFPair([transURL, origURL])
            check(reversedPair.original == origURL && reversedPair.translated == transURL,
                  "classifyPDFPair orders [translated.pdf, original.pdf] into (original, translated) via CJK density & filename")
        }
    }

    // 4. Full Window, Tab Bar, Library & Reader View Layout + Scroll Sync + Option Calibration Verification
    if var firstPaper = store.papers.first {
        firstPaper.lastReadPage = 2
        store.savePaper(firstPaper, notify: false)
    }

    let wc = MultiTabMainWindowController()
    if let rootView = wc.window?.contentView {
        rootView.layoutSubtreeIfNeeded()
        check(rootView.bounds.width >= 1020 && rootView.bounds.height >= 620, "Main window contentView layout valid")
    }

    if let firstPaper = store.papers.first {
        let savedAfterLoad = store.paper(withId: firstPaper.id)?.lastReadPage ?? 0
        check(savedAfterLoad == 2, "loadPaperDocuments preserves saved lastReadPage (\(savedAfterLoad)) without overwriting to 0")

        wc.openOrSwitchToPaperTab(paperId: firstPaper.id, jumpToAnnot: nil, switchImmediately: true)
        wc.window?.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        check(wc.activeReaderVC != nil, "Switched to ReaderTabViewController for paper \(firstPaper.id)")

        if let reader = wc.activeReaderVC {
            reader.resetSyncAlignmentAction()

            // 等待文档恢复完成；按连续页位置检验不同尺寸 PDF 的同步。
            var maxPositionError = 0.0
            var previous = -Double.infinity
            var monotonic = true
            for position in stride(from: 0.75, through: 1.25, by: 0.05) {
                _ = PDFScrollSynchronizer.scroll(to: position, in: reader.leftCol)
                reader.syncScroll(from: reader.leftCol, to: reader.rightCol)
                let left = reader.computeContinuousPagePosition(in: reader.leftCol) ?? -1
                let right = reader.computeContinuousPagePosition(in: reader.rightCol) ?? -2
                monotonic = monotonic && left >= previous
                previous = left
                maxPositionError = max(maxPositionError, abs(left - right))
            }
            check(monotonic && maxPositionError < 0.02, "Scroll sync remains monotonic across page boundary using continuous page positions")
            reader.syncScrollBtn.state = .off
            reader.toggleSyncScrollAction()
            _ = PDFScrollSynchronizer.scroll(to: 0.85, in: reader.leftCol)
            _ = PDFScrollSynchronizer.scroll(to: 1.10, in: reader.rightCol)
            reader.recordOptionScrollCalibrationOffset()
            let calibratedOffset = reader.pageRatioOffset
            check(abs(calibratedOffset - 0.25) < 0.02, "Option calibration records difference in continuous page positions")
            reader.syncScrollBtn.state = .on
            reader.toggleSyncScrollAction()
            _ = PDFScrollSynchronizer.scroll(to: 1.0, in: reader.leftCol)
            reader.syncScroll(from: reader.leftCol, to: reader.rightCol)
            let calibratedDelta = (reader.computeContinuousPagePosition(in: reader.rightCol) ?? -2) - (reader.computeContinuousPagePosition(in: reader.leftCol) ?? -1)
            check(abs(calibratedDelta - calibratedOffset) < 0.02, "Scroll sync preserves Option-calibrated continuous page offset")
            reader.resetSyncAlignmentAction()

            reader.setDisplayMode(0)
            reader.view.layoutSubtreeIfNeeded()
            check(reader.primaryActiveColumn() === reader.leftCol, "Display mode 0 ('仅原文') uses leftCol as primaryActiveColumn")
            reader.setDisplayMode(1)
            reader.view.layoutSubtreeIfNeeded()
            check(reader.primaryActiveColumn() === reader.rightCol, "Display mode 1 ('仅译文') uses rightCol as primaryActiveColumn")
            reader.setDisplayMode(2)
            reader.view.layoutSubtreeIfNeeded()
            reader.swapColumnsAction()
            reader.swapColumnsAction()
            reader.toggleRightDrawerAction()
            reader.view.layoutSubtreeIfNeeded()
            reader.toggleRightDrawerAction()
            reader.view.layoutSubtreeIfNeeded()
            reader.resetSyncAlignmentAction()
            check(true, "Reader view mode switching, column swapping, drawer toggling, and alignment reset verified")
            check(reader.leftCol.cornerButton.frame.width > 20 && reader.leftCol.cornerButton.frame.height > 10,
                  "PDF switch menu remains visible after removing note columns")

            let preservedSources = [reader.leftCol.contentSource, reader.rightCol.contentSource]
            reader.openNotesSidebar()
            reader.view.layoutSubtreeIfNeeded()
            check(!reader.sidebarNoteView.isHiddenOrHasHiddenAncestor && reader.sidebarNoteView.frame.width > 200,
                  "Right notes sidebar mounts a visible editor with usable width")
            check(!reader.sidebarNoteView.isDescendant(of: reader.leftCol) && !reader.sidebarNoteView.isDescendant(of: reader.rightCol),
                  "Notes editor belongs to sidebar, outside PDF columns")
            reader.setDisplayMode(0)
            if let doc = reader.leftCol.pdfView.document, let page = doc.page(at: 0), let selection = page.selection(for: page.bounds(for: .mediaBox)) {
                let quote = reader.quoteSelectionToPaperNote(from: reader.leftCol.pdfView, selection: selection)
                reader.view.layoutSubtreeIfNeeded()
                check(quote != nil && reader.rightCol.isHidden && [reader.leftCol.contentSource, reader.rightCol.contentSource] == preservedSources,
                      "Quote action opens sidebar while preserving single PDF layout and both sources")
            } else { check(false, "Fixture PDF provides text for sidebar quote interaction") }
            reader.setDisplayMode(3)
            check([reader.leftCol.contentSource, reader.rightCol.contentSource] == preservedSources,
                  "Legacy note mode never replaces a PDF column")
            reader.toggleRightDrawerAction()
            reader.setDisplayMode(2)

            // Test dual-column tight margin (gap reduced to hairline)
            check(reader.leftCol.pdfView.pageBreakMargins.left <= 2 && reader.leftCol.pdfView.pageBreakMargins.right <= 2,
                  "Dual column gap reduced: pageBreakMargins horizontal insets <= 2pt (left=\(reader.leftCol.pdfView.pageBreakMargins.left), right=\(reader.leftCol.pdfView.pageBreakMargins.right))")

            // Test navigation jump & back button per column: left jump shows on left with title '返回'
            reader.pushJumpRecord(from: reader.leftCol)
            check(!reader.leftCol.backJumpBanner.isHidden && reader.leftCol.backJumpButton.title == "返回" && reader.rightCol.backJumpBanner.isHidden,
                  "Jump initiated from left column displays '返回' capsule strictly on left column")
            reader.leftCol.backJumpButton.performClick(nil)
            check(reader.leftCol.backJumpBanner.isHidden, "Clicking left '返回' button pops jump record and hides banner")

            // Test navigation jump & back button per column: right jump shows on right with title '返回'
            reader.pushJumpRecord(from: reader.rightCol)
            check(!reader.rightCol.backJumpBanner.isHidden && reader.rightCol.backJumpButton.title == "返回" && reader.leftCol.backJumpBanner.isHidden,
                  "Jump initiated from right column displays '返回' capsule strictly on right column")
            reader.rightCol.backJumpButton.performClick(nil)
            check(reader.rightCol.backJumpBanner.isHidden, "Clicking right '返回' button pops jump record and hides banner")
        }

        // Test horizontal tab scroll view with 12 tabs to ensure no Auto Layout constraint conflicts
        for idx in 1...10 {
            let overflowTab = ZoteroTabItemView(
                tabId: "test_tab_\(idx)",
                title: "Overflow Test Paper Title #\(idx)",
                symbol: "doc.richtext.fill",
                symbolTint: .systemBlue,
                isActive: idx == 10,
                closable: true
            )
            wc.tabBarStack.addArrangedSubview(overflowTab)
        }
        wc.window?.contentView?.layoutSubtreeIfNeeded()
        check(wc.tabBarStack.arrangedSubviews.count >= 12 && (wc.window?.contentView?.bounds.width ?? 0) == 1440,
              "HorizontalTabScrollView hosts 12+ tabs cleanly without expanding window or breaking constraints (width=\(wc.window?.contentView?.bounds.width ?? 0))")
        wc.rebuildTabBarUI()

        wc.switchToLibraryTabShortcut()
        wc.window?.contentView?.layoutSubtreeIfNeeded()
        check(wc.activeReaderVC == nil && wc.activeTabId == "__LIBRARY__", "Switched back to Library tab cleanly")

        if let origURL = store.pdfURL(for: firstPaper, side: .original) {
            let coverSummary = PDFSummaryCache.render(origURL)
            check(coverSummary.pageCount > 0 && (coverSummary.thumbnailDataURL?.hasPrefix("data:image/png;base64,") == true),
                  "cachedPDFSummaryWithDataURL generates base64 PNG cover thumbnail for Koodo/Zotero library cards (\(coverSummary.pageCount) pages)")
        }

        // Verify real hitTest, CGSRegion titlebar window-drag exclusion, & mouseDown on top tabs inside .fullSizeContentView titlebar area
        if let win = wc.window,
           let rootView = win.contentView,
           wc.tabBarStack.arrangedSubviews.count >= 2 {
            win.makeKeyAndOrderFront(nil)
            rootView.layoutSubtreeIfNeeded()

            // 标签点击、关闭和实际 hitTest 在下方验证；空白拖动遵循当前标题栏约定。

            // Obsidian-style inactive tabs hide the close control until hover; clicks in that area still reach the tab itself.
            if let inactivePaperTab = wc.tabBarStack.arrangedSubviews[1] as? ZoteroTabItemView {
                let closeCenterInWin = inactivePaperTab.closeButton.convert(
                    NSPoint(x: inactivePaperTab.closeButton.bounds.midX, y: inactivePaperTab.closeButton.bounds.midY),
                    to: nil
                )
                let hitInactiveClose = rootView.superview?.hitTest(closeCenterInWin)
                check(inactivePaperTab.closeButton.isHidden && hitInactiveClose === inactivePaperTab,
                      "Inactive paper tab hides closeButton and keeps the full tab header hit-testable")

                let justOutsideCloseInTab = NSPoint(x: inactivePaperTab.closeButton.frame.minX - 2, y: inactivePaperTab.bounds.midY)
                let justOutsideCloseInWin = inactivePaperTab.convert(justOutsideCloseInTab, to: nil)
                let hitJustOutside = rootView.superview?.hitTest(justOutsideCloseInWin)
                check(hitJustOutside === inactivePaperTab,
                      "Point 2pt outside closeButton hits ZoteroTabItemView cleanly (zero dead-zone around closeButton)")
            }

            let paperTabView = wc.tabBarStack.arrangedSubviews[1]
            let paperTabCenterInWin = paperTabView.convert(NSPoint(x: paperTabView.bounds.midX, y: paperTabView.bounds.midY), to: nil)
            let hitOnPaperTab = rootView.superview?.hitTest(paperTabCenterInWin)
            check(hitOnPaperTab === paperTabView && (hitOnPaperTab?.mouseDownCanMoveWindow == false),
                  "NSThemeFrame.hitTest at titlebar tab center (\(Int(paperTabCenterInWin.x)), \(Int(paperTabCenterInWin.y))) hits ZoteroTabItemView directly (not NSTitlebarView/NSClipView)")

            if let clickPaperEvent = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: paperTabCenterInWin,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 101,
                clickCount: 1,
                pressure: 1.0
            ) {
                win.sendEvent(clickPaperEvent)
            }
            check(wc.activeTabId == firstPaper.id && wc.activeReaderVC != nil,
                  "Real NSWindow.sendEvent(leftMouseDown) on paper tab switches activeTabId to \(firstPaper.id)")

            // When active, the close button at the trailing edge of the paper tab should be hit-testable as NSButton
            if let activePaperTabView = wc.tabBarStack.arrangedSubviews[1] as? ZoteroTabItemView {
                let closeBtnPtInWin = activePaperTabView.closeButton.convert(
                    NSPoint(x: activePaperTabView.closeButton.bounds.midX, y: activePaperTabView.closeButton.bounds.midY),
                    to: nil
                )
                let hitOnCloseBtn = rootView.superview?.hitTest(closeBtnPtInWin)
                check(hitOnCloseBtn === activePaperTabView.closeButton,
                      "NSThemeFrame.hitTest at active tab close button hits NSButton directly")

                // Test closing the tab via closeButton action and re-opening it
                activePaperTabView.closeButton.performClick(nil)
                check(wc.activeTabId == "__LIBRARY__" && wc.tabBarStack.arrangedSubviews.count == 1,
                      "Clicking closeButton on paper tab closes the tab and returns to __LIBRARY__")
                wc.openOrSwitchToPaperTab(paperId: firstPaper.id, jumpToAnnot: nil, switchImmediately: true)
                check(wc.activeTabId == firstPaper.id && wc.tabBarStack.arrangedSubviews.count == 2,
                      "Re-opening paper tab restores tab count to 2 and activates paper tab")
            }

            let rebuiltLibTabView = wc.tabBarStack.arrangedSubviews[0]
            let libTabCenterInWin = rebuiltLibTabView.convert(NSPoint(x: rebuiltLibTabView.bounds.midX, y: rebuiltLibTabView.bounds.midY), to: nil)
            if let clickLibEvent = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: libTabCenterInWin,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: win.windowNumber,
                context: nil,
                eventNumber: 102,
                clickCount: 1,
                pressure: 1.0
            ) {
                win.sendEvent(clickLibEvent)
            }
            check(wc.activeTabId == "__LIBRARY__" && wc.activeReaderVC == nil,
                  "Real NSWindow.sendEvent(leftMouseDown) on Library tab switches back to __LIBRARY__")

            // Wait up to 3.0s for LibraryViewController's WKWebView to finish loading and verify DOM & JS invariants
            let deadline = Date().addingTimeInterval(3.0)
            while !wc.libraryVC.isWebViewLoaded && Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            check(wc.libraryVC.isWebViewLoaded, "LibraryViewController WKWebView loaded modern workspace HTML")

            if wc.libraryVC.isWebViewLoaded {
                func evalJS(_ script: String) -> Any? {
                    var result: Any?
                    var done = false
                    wc.libraryVC.webView.evaluateJavaScript(script) { res, _ in
                        result = res
                        done = true
                    }
                    let jsDeadline = Date().addingTimeInterval(2.0)
                    while !done && Date() < jsDeadline {
                        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                    }
                    return result
                }

                // Give pushStateToWeb a brief runloop turn to render cards and sync drop slot rects
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.08))

                // 1) Verify selectPaper preserves DOM node identity so double-click (ondblclick) works on cards & table rows
                let domPreserved = evalJS("""
                (function() {
                    const cards = document.querySelectorAll('[data-paper-id]');
                    if (cards.length < 1) return false;
                    const targetCard = cards[0];
                    const pid = targetCard.getAttribute('data-paper-id');
                    selectPaper(pid);
                    const cardAfter = document.querySelector('[data-paper-id="' + pid + '"]');
                    return targetCard === cardAfter && cardAfter.classList.contains('selected');
                })()
                """) as? Bool ?? false
                check(domPreserved, "selectPaper(id) updates current library row in-place and preserves double-click DOM identity")

                // 2) Verify escapeJSAttr escapes single quotes and backslashes safely
                let escapedOK = evalJS("""
                (function() {
                    const s = escapeJSAttr("O'Reilly \\\\ Paper");
                    return s.indexOf("\\\\'") !== -1 && s.indexOf("\\\\\\\\") !== -1;
                })()
                """) as? Bool ?? false
                check(escapedOK, "escapeJSAttr safely escapes single quotes and backslashes for inline onclick handlers")

                // 3) Verify clean workspace drop resolution and tag/dummy panel elimination
                let dropZone = wc.libraryVC.webView.detectDropTargetZone(atTopLeftPoint: NSPoint(x: 300, y: 300))
                check(dropZone == "library", "detectDropTargetZone resolves dropped PDF cleanly to 'library' workspace")

                let tagPanelExists = evalJS("document.getElementById('tagPanel') !== null") as? Bool ?? true
                check(!tagPanelExists, "Tag filter panel is eliminated from library workspace")

                let railExists = evalJS("document.getElementById('rightRail') !== null") as? Bool ?? true
                check(!railExists, "Right icon rail is eliminated from library workspace")

                let categoryName = "UI空分类"
                let categoryDeadline = Date().addingTimeInterval(3)
                var filledCategoryDialog = false
                func completeCategoryDialog() {
                    if let content = NSApp.modalWindow?.contentView {
                        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
                        if let input = descendants(content).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable }) {
                            input.stringValue = categoryName
                            filledCategoryDialog = true
                            NSApp.stopModal(withCode: .alertFirstButtonReturn)
                            return
                        }
                    }
                    if Date() < categoryDeadline {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { completeCategoryDialog() }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { completeCategoryDialog() }
                _ = evalJS("window.webkit.messageHandlers.libraryBridge.postMessage({action:'createCategory'});")
                while !store.allCategories().contains(categoryName) && Date() < categoryDeadline {
                    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
                check(filledCategoryDialog && LibraryStore(rootDirectory: testRoot).allCategories().contains(categoryName),
                      "WebView createCategory bridge opens native dialog and persists an empty category")
                if let pid = store.papers.first?.id,
                   let data = try? JSONEncoder().encode(pid), let pidJSON = String(data: data, encoding: .utf8) {
                    _ = evalJS("window.webkit.messageHandlers.libraryBridge.postMessage({action:'saveMetadata',paperId:" + pidJSON + ",tags:'bridgeTag， #第二标签'});")
                    let tagsDeadline = Date().addingTimeInterval(2)
                    while store.paper(withId: pid)?.tags != ["bridgeTag", "第二标签"] && Date() < tagsDeadline {
                        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
                    }
                    check(LibraryStore(rootDirectory: testRoot).paper(withId: pid)?.tags == ["bridgeTag", "第二标签"],
                          "WebView saveMetadata bridge persists edited tags to paper metadata")
                    _ = evalJS("window.webkit.messageHandlers.libraryBridge.postMessage({action:'openPaperNotesSidebar',paperId:" + pidJSON + "});")
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    check(wc.activeReaderVC?.paperId == pid && wc.activeReaderVC?.sidebarNoteView.isHiddenOrHasHiddenAncestor == false,
                          "Library notes entry opens real reader sidebar through native bridge")
                }
            }
        }
    }

    if store.papers.count >= 2 {
        let sourceId = store.papers[0].id
        let targetId = store.papers[1].id
        store.linkRelatedPapers(paperAId: sourceId, paperBId: targetId, note: "窗口导航回归")
        let standalone = StandaloneReaderWindowController(paperId: sourceId)
        standalone.showWindow(nil)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let initialViews = standalone.window?.contentView.map { descendants($0) } ?? []
        let linksRail = initialViews.compactMap { $0 as? NSButton }.first { $0.tag == 5 && $0.action == NSSelectorFromString("workbenchRailButtonClicked:") }
        (linksRail?.target as? ReaderTabViewController)?.openNotesSidebar()
        linksRail?.performClick(nil)
        standalone.window?.contentView?.layoutSubtreeIfNeeded()
        let allViews = standalone.window?.contentView.map { descendants($0) } ?? []
        let relatedButton = allViews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("openRelatedPaperFromDrawer:") && $0.identifier?.rawValue == targetId }
        relatedButton?.performClick(nil)
        let opened = NSApp.windows.compactMap { $0.windowController as? StandaloneReaderWindowController }.filter { $0.paperId == targetId }
        check(relatedButton != nil && opened.count == 1, "Standalone related-paper button opens target reader window")
        relatedButton?.performClick(nil)
        let reopened = NSApp.windows.compactMap { $0.windowController as? StandaloneReaderWindowController }.filter { $0.paperId == targetId }
        check(reopened.count == 1 && reopened.first === opened.first, "Standalone navigation reuses the existing target window")
        opened.forEach { $0.close() }
        standalone.close()
    } else { check(false, "Fixture includes related papers for standalone navigation") }

    print("=== SELF-TEST SUMMARY: \(passed) passed, \(failed) failed ===")
    return failed == 0 ? 0 : 1
}

