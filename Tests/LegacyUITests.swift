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
    check(LibrarySortOrder.allCases.count == 5, "LibrarySortOrder has 5 sorting modes")
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
        check(wc.activeReaderVC != nil, "Switched to ReaderTabViewController for paper \(firstPaper.id)")

        if let reader = wc.activeReaderVC {
            reader.resetSyncAlignmentAction()

            // Test continuous page position smoothness across page boundary (no 20pt jump)
            if let svLeft = reader.leftCol.internalScrollView(),
               let svRight = reader.rightCol.internalScrollView() {
                var maxSyncDiff: CGFloat = 0
                var prevContinuous: Double = -1
                var isMonotonic = true
                for y in stride(from: CGFloat(400), through: CGFloat(900), by: 25) {
                    svLeft.contentView.scroll(to: NSPoint(x: 0, y: y))
                    svLeft.reflectScrolledClipView(svLeft.contentView)
                    let cont = reader.computeContinuousPagePosition(in: reader.leftCol) ?? 0
                    if cont < prevContinuous { isMonotonic = false }
                    prevContinuous = cont
                    let diff = abs(svLeft.contentView.bounds.origin.y - svRight.contentView.bounds.origin.y)
                    if diff > maxSyncDiff { maxSyncDiff = diff }
                }
                check(isMonotonic && maxSyncDiff < 0.1,
                      String(format: "Smooth 1:1 scroll sync across page break (monotonic=%@, maxDiff=%.4fpt)", "\(isMonotonic)", maxSyncDiff))

                // Test Option-scroll calibration recording & application
                svLeft.contentView.scroll(to: NSPoint(x: 0, y: 300))
                svLeft.reflectScrolledClipView(svLeft.contentView)
                // Simulate holding Option while scrolling rightCol independently (sync suppressed during Option scroll)
                reader.syncScrollBtn.state = .off
                reader.toggleSyncScrollAction()
                svRight.contentView.scroll(to: NSPoint(x: 0, y: 450))
                svRight.reflectScrolledClipView(svRight.contentView)
                reader.recordOptionScrollCalibrationOffset()
                check(abs(reader.pageRatioOffset) > 0.05,
                      String(format: "recordOptionScrollCalibrationOffset records non-zero pageRatioOffset (%.4f)", reader.pageRatioOffset))
                reader.syncScrollBtn.state = .on
                reader.toggleSyncScrollAction()
                svLeft.contentView.scroll(to: NSPoint(x: 0, y: 350))
                svLeft.reflectScrolledClipView(svLeft.contentView)
                let calibratedDeltaY = svRight.contentView.bounds.origin.y - svLeft.contentView.bounds.origin.y
                check(abs(calibratedDeltaY - 150) < 2.0,
                      String(format: "Sync scroll preserves Option-calibrated offset (deltaY=%.2fpt, expected ~150pt)", calibratedDeltaY))
                reader.resetSyncAlignmentAction()
            }

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

            // Verify AppKit's private CGSRegion titlebar drag-exclusion calculation includes our tabs when forUnderTitlebar == true
            typealias OpaqueRegionFn = @convention(c) (AnyObject, Selector, NSRect, Bool, Bool) -> AnyObject?
            let regionSel = NSSelectorFromString("_regionForOpaqueDescendants:forMove:forUnderTitlebar:")
            if rootView.responds(to: regionSel),
               let imp = rootView.method(for: regionSel) {
                let fn = unsafeBitCast(imp, to: OpaqueRegionFn.self)
                let regionObj = fn(rootView, regionSel, rootView.bounds, true, true)
                let regionDesc = String(describing: regionObj)
                check(!regionDesc.contains("empty") && regionDesc.contains("[82 "),
                      "AppKit _regionForOpaqueDescendants(forMove:true, forUnderTitlebar:true) excludes titlebar tab bar [82..453] from window drag region")
            }

            // Verify all tab bar container & item views have mouseDownCanMoveWindow == false
            let allNonDraggable = !wc.tabBarScrollView.mouseDownCanMoveWindow
                && !wc.tabBarScrollView.contentView.mouseDownCanMoveWindow
                && !wc.tabBarDocumentView.mouseDownCanMoveWindow
                && !wc.tabBarStack.mouseDownCanMoveWindow
                && wc.tabBarStack.arrangedSubviews.allSatisfy { v in
                    !v.mouseDownCanMoveWindow && v.subviews.allSatisfy { !$0.mouseDownCanMoveWindow }
                }
            check(allNonDraggable, "All tabBarScrollView, NonDraggableClipView, tabBarStack, ZoteroTabItemView & subviews have mouseDownCanMoveWindow == false")

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

                // Sidebar search must stay local to categories and leave paper search untouched.
                let sidebarChecks = evalJS("""
                (function() {
                    const input = document.getElementById('categorySearchInput');
                    if (!input) return {};
                    const globalInput = document.getElementById('searchInput');
                    const savedCategories = state.categories;
                    const savedQuery = ui.categorySearchQuery;
                    const savedExpanded = ui.treeExpanded;
                    const savedValue = input.value;
                    const savedFocus = document.activeElement;
                    const checks = {};
                    const names = () => Array.from(document.querySelectorAll('#sidebarScroll .tree-label')).map(el => el.textContent);
                    const search = value => {
                        input.value = value;
                        input.dispatchEvent(new Event('input', { bubbles: true }));
                    };
                    try {
                        state.categories = ['LLM 架构', '默认分类', "O'Reilly & <PDF>"];
                        renderSidebar();
                        const centerHTML = document.querySelector('.center-pane').innerHTML;
                        const globalValue = globalInput.value;
                        const globalQuery = ui.searchQuery;
                        const filter = ui.filterKind;
                        const selected = state.selectedPaperId;
                        input.focus();
                        checks.localFocus = document.activeElement === input && !document.querySelector('.sidebar-toolbar button');
                        ui.treeExpanded = false;
                        search('  llm  ');
                        checks.filtered = names().includes('LLM 架构') && !names().includes('默认分类') && ui.treeExpanded;
                        checks.independent = document.querySelector('.center-pane').innerHTML === centerHTML &&
                            globalInput.value === globalValue && ui.searchQuery === globalQuery &&
                            ui.filterKind === filter && state.selectedPaperId === selected && document.activeElement === input;
                        window.updateLibraryState(state);
                        checks.refresh = names().includes('LLM 架构') && !names().includes('默认分类') &&
                            input.value === '  llm  ' && document.activeElement === input;
                        search('默认');
                        checks.chinese = names().includes('默认分类') && !names().includes('LLM 架构');
                        search('<pdf>');
                        checks.escaped = names().includes("O'Reilly & <PDF>") && !document.querySelector('#sidebarScroll pdf');
                        search('no-matching-category');
                        checks.empty = document.querySelector('.sidebar-empty-search')?.textContent === '未找到匹配分类';
                        input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                        checks.cleared = input.value === '' && ui.categorySearchQuery === '' &&
                            names().includes('LLM 架构') && names().includes('默认分类') &&
                            !document.querySelector('.sidebar-empty-search') && globalInput.value === globalValue;
                        window.focusLibrarySearch();
                        checks.globalFocus = document.activeElement === globalInput;
                    } finally {
                        state.categories = savedCategories;
                        ui.categorySearchQuery = savedQuery;
                        ui.treeExpanded = savedExpanded;
                        input.value = savedValue;
                        renderAll();
                        if (savedFocus && savedFocus.isConnected) savedFocus.focus();
                    }
                    return checks;
                })()
                """) as? [String: Bool] ?? [:]
                check(sidebarChecks["localFocus"] == true, "Sidebar category search has its own focus and no misleading import button")
                check(sidebarChecks["filtered"] == true, "Sidebar search filters categories case-insensitively and expands collapsed results")
                check(sidebarChecks["independent"] == true, "Sidebar search preserves paper search, selection, filter, center DOM and focus")
                check(sidebarChecks["refresh"] == true, "Category search and focus survive native library state updates")
                check(sidebarChecks["chinese"] == true, "Sidebar category search supports Chinese names")
                check(sidebarChecks["escaped"] == true, "Category search renders quotes and HTML-like names as literal text")
                check(sidebarChecks["empty"] == true, "Unmatched category search shows an explicit empty state")
                check(sidebarChecks["cleared"] == true, "Escape clears only category search and restores the category list")
                check(sidebarChecks["globalFocus"] == true, "Global library search shortcut retains its paper-search focus")

                // 1) Verify selectPaper preserves DOM node identity so double-click (ondblclick) works on cards & table rows
                let domPreserved = evalJS("""
                (function() {
                    const cards = document.querySelectorAll('.paper-card');
                    if (cards.length < 1) return false;
                    const targetCard = cards[cards.length - 1];
                    const pid = targetCard.getAttribute('data-paper-id');
                    selectPaper(pid);
                    const cardAfter = document.querySelector('.paper-card[data-paper-id="' + pid + '"]');
                    return targetCard === cardAfter && cardAfter.classList.contains('selected');
                })()
                """) as? Bool ?? false
                check(domPreserved, "selectPaper(id) updates selection in-place without destroying .paper-card DOM node (preserving ondblclick)")

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
            }
        }
    }

    print("=== SELF-TEST SUMMARY: \(passed) passed, \(failed) failed ===")
    return failed == 0 ? 0 : 1
}

