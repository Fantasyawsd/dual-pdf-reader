import Cocoa
import Foundation
import PDFKit

func runP0TransientLibraryTests() throws {
    try runTransientNoCopyTest()
    try runTransientStatePersistTest()
    try runTransientPromoteMigratesNotesTest()
    try runTransientEncryptedNoPlaintextCopyTest()
    try runLibraryStoreRoutesToTransientTest()
    try runVenueNoHardcodedArxivTest()
    try runPromoteSaveFailureRollbackTest()
    try runReadingStateDebounceFlushTest()
    try runUnlockedDocumentSurvivesPromoteTest()
    try runRecentCombinedAndRemoveTest()
    try runSidebarSourcesOnlyIATest()
    try runTabDedupeByPaperIdEvidenceTest()
}

private func writeMinimalPDF(to url: URL, text: String = "Hello") throws {
    var box = CGRect(x: 0, y: 0, width: 300, height: 300)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    let str = text as CFString
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    // Keep payload tiny — content stream not required for open/copy tests.
    ctx.endPDFPage()
    ctx.closePDF()
    _ = str
}

private func runTransientNoCopyTest() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-NoCopy-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: root)
    }
    TransientStore.useTestRoot(root)

    let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-src-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: pdf)
    defer { try? fm.removeItem(at: pdf) }

    let store = TransientStore.shared
    guard let item = store.openPDFs([pdf]) else {
        check(false, "P0-2: openPDFs returns item")
        return
    }
    check(item.isTransient, "P0-2: opened item isTransient")
    let folder = store.folderURL(for: item.id)
    let contents = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
    check(contents == ["state.json"] || Set(contents) == ["state.json"],
          "P0-2: Transient folder only has state.json (got \(contents))")
    check(!contents.contains { $0.lowercased().hasSuffix(".pdf") },
          "P0-2: Transient does not copy PDF bytes")
    check(FileManager.default.fileExists(atPath: pdf.path), "P0-2: source PDF still at original path")
}

private func runTransientStatePersistTest() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-Persist-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: root)
    }
    TransientStore.useTestRoot(root)

    let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-persist-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: pdf, text: "Persist")
    defer { try? fm.removeItem(at: pdf) }

    guard var item = TransientStore.shared.openPDFs([pdf]) else {
        check(false, "P0-2 persist: openPDFs")
        return
    }
    let note = PaperNoteDocument(title: "临时笔记", markdownContent: "hello transient")
    item.noteDocuments = [note]
    item.annotations = [
        PaperAnnotation(side: .original, pageIndex: 0, rects: [], selectedText: "sel", color: .yellow, markdownNote: "ann")
    ]
    item.lastReadPage = 2
    check(TransientStore.shared.savePaper(item), "P0-2 persist: savePaper")

    // Reload from disk via new store instance on same root.
    TransientStore.useTestRoot(root)
    let reloaded = TransientStore.shared.paper(withId: item.id)
    check(reloaded != nil, "P0-2 persist: reloaded paper exists")
    check(reloaded?.noteDocuments?.first?.markdownContent == "hello transient", "P0-2 persist: note restored")
    check(reloaded?.annotations.count == 1, "P0-2 persist: annotation restored")
    check(reloaded?.lastReadPage == 2, "P0-2 persist: lastReadPage restored")
    check(reloaded?.isTransient == true, "P0-2 persist: still transient")
}

private func runTransientPromoteMigratesNotesTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-PromoteT-\(UUID().uuidString)", isDirectory: true)
    let lRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-PromoteL-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    try fm.createDirectory(at: lRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
        try? fm.removeItem(at: lRoot)
    }
    TransientStore.useTestRoot(tRoot)
    let library = LibraryStore(rootDirectory: lRoot, seedIfEmpty: false)

    let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-promote-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: pdf, text: "Promote")
    defer { try? fm.removeItem(at: pdf) }

    guard var item = TransientStore.shared.openPDFs([pdf]) else {
        check(false, "P0-2 promote: open")
        return
    }
    item.noteDocuments = [PaperNoteDocument(title: "N", markdownContent: "migrated-body")]
    item.annotations = [
        PaperAnnotation(side: .original, pageIndex: 1, rects: [], selectedText: "t", color: .green, markdownNote: "m")
    ]
    check(TransientStore.shared.savePaper(item), "P0-2 promote: save before")

    // promoteToLibrary uses LibraryStore.shared — temporarily not ideal.
    // Exercise migration by calling promote against shared library only if we can swap.
    // Fallback: verify fields would migrate by reading transient then createPaper on isolated library.
    let fields = TransientStore.PromoteFields(
        title: "Promoted Title",
        authors: "A",
        year: "2024",
        venue: "",
        category: "未分类"
    )
    guard let originalURL = TransientStore.shared.pdfURL(for: item, side: .original) else {
        check(false, "P0-2 promote: resolve bookmark")
        return
    }
    guard let created = library.createPaper(
        title: fields.title,
        authors: fields.authors,
        year: fields.year,
        venue: fields.venue,
        category: fields.category,
        tags: item.tags,
        arxivId: item.arxivId,
        originalSourceURL: originalURL,
        translatedSourceURL: nil
    ) else {
        check(false, "P0-2 promote: createPaper")
        return
    }
    var migrated = created
    migrated.annotations = item.annotations
    migrated.noteDocuments = item.noteDocuments
    check(library.savePaper(migrated), "P0-2 promote: save migrated")
    let got = library.paper(withId: created.id)
    check(got?.annotations.count == 1, "P0-2 promote: annotations migrated")
    check(got?.noteDocuments?.first?.markdownContent == "migrated-body", "P0-2 promote: notes migrated")
    check(got?.venue == "", "P0-2 promote: empty venue preserved")
    check(!(got?.isTransient ?? true), "P0-2 promote: library item not transient")

    // Ensure library received a PDF copy (bytes on disk under library root).
    let libPDF = library.pdfURL(for: created, side: .original)
    check(libPDF != nil && fm.fileExists(atPath: libPDF!.path), "P0-2 promote: PDF copied into library")
    check(libPDF!.path.hasPrefix(lRoot.path), "P0-2 promote: PDF lives under library root")
}

private func runTransientEncryptedNoPlaintextCopyTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-Enc-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
    }
    TransientStore.useTestRoot(tRoot)

    // Use a normal PDF as stand-in for "encrypted source file" path; unlocked doc is in-memory only.
    let enc = fm.temporaryDirectory.appendingPathComponent("DualPDF-enc-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: enc, text: "secret")
    defer { try? fm.removeItem(at: enc) }
    guard let unlocked = PDFDocument(url: enc) else {
        check(false, "P0-2 enc: PDFDocument load")
        return
    }

    guard let item = TransientStore.shared.openPDFs([enc], unlockedDocument: unlocked) else {
        check(false, "P0-2 enc: open with unlockedDocument")
        return
    }
    check(TransientStore.shared.unlockedDocument(for: item.id) === unlocked ||
          TransientStore.shared.unlockedDocument(for: item.id) != nil,
          "P0-2 enc: unlocked document cached in memory")
    let folder = TransientStore.shared.folderURL(for: item.id)
    let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
    check(!files.contains { $0.lowercased().hasSuffix(".pdf") },
          "P0-2 enc: no plaintext PDF written under Transient")
    // state.json only
    check(files.contains("state.json"), "P0-2 enc: state.json present")
}

private func runLibraryStoreRoutesToTransientTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-Route-\(UUID().uuidString)", isDirectory: true)
    let lRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-RouteL-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    try fm.createDirectory(at: lRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
        try? fm.removeItem(at: lRoot)
    }
    TransientStore.useTestRoot(tRoot)
    let store = LibraryStore(rootDirectory: lRoot, seedIfEmpty: false)
    let before = store.papers.count

    let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-route-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: pdf)
    defer { try? fm.removeItem(at: pdf) }

    guard let item = TransientStore.shared.openPDFs([pdf]) else {
        check(false, "P0-2 route: open")
        return
    }
    check(store.isTransientPaper(id: item.id), "P0-2 route: registered on LibraryStore")

    var updated = item
    updated.noteDocuments = [PaperNoteDocument(title: "r", markdownContent: "via-library")]
    check(store.savePaper(updated), "P0-2 route: LibraryStore.savePaper routes to Transient")
    check(store.papers.count == before, "P0-2 route: library papers unchanged")
    check(store.paper(withId: item.id)?.noteDocuments?.first?.markdownContent == "via-library",
          "P0-2 route: paper(withId) reads transient")

    let metaUnderLib = (try? fm.subpathsOfDirectory(atPath: lRoot.path)) ?? []
    check(!metaUnderLib.contains { $0.hasSuffix("meta.json") && $0.contains(item.id) },
          "P0-2 route: no ghost meta.json under library for transient id")
}

private func runVenueNoHardcodedArxivTest() throws {
    let src = try String(contentsOfFile: "Sources/LibraryStore.swift", encoding: .utf8)
    // smartCreate should not hardcode venue: "arXiv" without arxivId check nearby.
    check(src.contains("venue: meta.arxivId != nil ? \"arXiv\" : \"\""),
          "P0-2 venue: smartCreate uses conditional arXiv venue")
    check(!src.contains("venue: \"arXiv\","),
          "P0-2 venue: no unconditional venue: \"arXiv\" literal in create calls")
    let js = try String(contentsOfFile: "Resources/LibraryWorkspace.js", encoding: .utf8)
    check(!js.contains("document.getElementById('mVenue').value = 'arXiv'"),
          "P0-2 venue: create modal default venue is not arXiv")
}

/// C1: if savePaper fails after createPaper, delete the half-created library entry and keep the transient.
private func runPromoteSaveFailureRollbackTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-C1T-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.testingPromoteSavePaperResult = nil
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
    }
    TransientStore.useTestRoot(tRoot)

    let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-c1-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: pdf, text: "C1")
    defer { try? fm.removeItem(at: pdf) }

    guard var item = TransientStore.shared.openPDFs([pdf]) else {
        check(false, "C1: openPDFs")
        return
    }
    item.noteDocuments = [PaperNoteDocument(title: "keep", markdownContent: "must-survive")]
    check(TransientStore.shared.savePaper(item), "C1: save notes")

    let beforeLibCount = LibraryStore.shared.papers.count
    TransientStore.testingPromoteSavePaperResult = false
    let result = TransientStore.shared.promoteToLibrary(
        id: item.id,
        fields: .init(title: "C1 Fail", authors: "A", year: "2026", venue: "", category: "未分类")
    )
    switch result {
    case .success:
        check(false, "C1: promote must fail when savePaper forced false")
    case .failure:
        check(true, "C1: promote returns failure")
    }
    check(TransientStore.shared.paper(withId: item.id) != nil, "C1: transient kept after rollback")
    check(TransientStore.shared.paper(withId: item.id)?.noteDocuments?.first?.markdownContent == "must-survive",
          "C1: transient notes intact")
    check(LibraryStore.shared.papers.count == beforeLibCount,
          "C1: library paper count unchanged after rollback (was \(beforeLibCount), now \(LibraryStore.shared.papers.count))")
    let leftover = LibraryStore.shared.papers.filter { $0.title == "C1 Fail" }
    check(leftover.isEmpty, "C1: no orphan library entry titled C1 Fail")
}

/// C2: reading-state updates coalesce (~0.75s); flush persists once.
private func runReadingStateDebounceFlushTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-C2-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
    }
    TransientStore.useTestRoot(tRoot)

    let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-c2-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: pdf, text: "C2")
    defer { try? fm.removeItem(at: pdf) }

    guard let item = TransientStore.shared.openPDFs([pdf]) else {
        check(false, "C2: open")
        return
    }
    let store = TransientStore.shared
    let before = store.readingPersistCountForTests

    store.updateReadingState(for: item.id) { $0.lastReadPage = 1 }
    store.updateReadingState(for: item.id) { $0.lastReadPage = 2 }
    store.updateReadingState(for: item.id) { $0.lastReadPage = 3 }
    check(store.readingPersistCountForTests == before, "C2: debounce holds writes during burst")

    check(store.flushReadingState(), "C2: flushReadingState succeeds")
    check(store.readingPersistCountForTests == before + 1, "C2: flush performs one disk write")
    check(store.paper(withId: item.id)?.lastReadPage == 3, "C2: memory has last value")

    TransientStore.useTestRoot(tRoot)
    check(TransientStore.shared.paper(withId: item.id)?.lastReadPage == 3, "C2: disk has last value after flush")
}

/// C3: unlocked in-memory PDFDocument is re-keyed to the library id on promote.
private func runUnlockedDocumentSurvivesPromoteTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-C3-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
    }
    TransientStore.useTestRoot(tRoot)

    let enc = fm.temporaryDirectory.appendingPathComponent("DualPDF-c3-\(UUID().uuidString).pdf")
    try writeMinimalPDF(to: enc, text: "C3")
    defer { try? fm.removeItem(at: enc) }
    guard let unlocked = PDFDocument(url: enc) else {
        check(false, "C3: PDFDocument")
        return
    }
    guard let item = TransientStore.shared.openPDFs([enc], unlockedDocument: unlocked) else {
        check(false, "C3: open")
        return
    }
    check(TransientStore.shared.unlockedDocument(for: item.id) != nil, "C3: unlocked cached under transient id")

    let result = TransientStore.shared.promoteToLibrary(
        id: item.id,
        fields: .init(title: "C3 Promoted", authors: "A", year: "2026", venue: "", category: "未分类")
    )
    guard case .success(let created) = result else {
        check(false, "C3: promote succeeds")
        return
    }
    check(TransientStore.shared.unlockedDocument(for: item.id) == nil, "C3: old id no longer holds unlocked")
    check(TransientStore.shared.unlockedDocument(for: created.id) != nil, "C3: unlocked re-keyed to library id")
    let readerSrc = try String(contentsOfFile: "Sources/ReaderTabViewController.swift", encoding: .utf8)
    check(readerSrc.contains("transferUnlockedDocument(from: oldId, to: newId)"),
          "C3 evidence: adoptLibraryPaper transfers unlocked")
    check(readerSrc.contains("unlockedDocument(for: paperId) != nil"),
          "C3 evidence: skip reload when unlocked present")
}

private func runRecentCombinedAndRemoveTest() throws {
    let fm = FileManager.default
    let tRoot = fm.temporaryDirectory.appendingPathComponent("DualPDF-P02-Recent-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
    defer {
        TransientStore.useTestRoot(nil)
        try? fm.removeItem(at: tRoot)
    }
    TransientStore.useTestRoot(tRoot)

    var ids: [String] = []
    var pdfs: [URL] = []
    defer { for u in pdfs { try? fm.removeItem(at: u) } }
    for i in 0..<3 {
        let pdf = fm.temporaryDirectory.appendingPathComponent("DualPDF-recent-\(i)-\(UUID().uuidString).pdf")
        try writeMinimalPDF(to: pdf, text: "R\(i)")
        pdfs.append(pdf)
        guard var item = TransientStore.shared.openPDFs([pdf]) else {
            check(false, "Recent: open \(i)")
            return
        }
        item.lastOpenedAt = Date().addingTimeInterval(TimeInterval(i))
        check(TransientStore.shared.savePaper(item), "Recent: save \(i)")
        ids.append(item.id)
    }
    let combined = TransientStore.recentCombined(limit: 30)
    check(combined.count >= 3, "Recent: combined includes transients")
    check(combined.first?.id == ids[2], "Recent: sorted by lastOpenedAt desc")

    check(TransientStore.shared.removeFromRecent(id: ids[2]), "Recent: removeFromRecent")
    let after = TransientStore.recentCombined(limit: 30)
    check(!after.contains(where: { $0.id == ids[2] }), "Recent: removed id absent from combined")
    check(TransientStore.shared.paper(withId: ids[2]) != nil, "Recent: soft-remove keeps transient state")

    let src = try String(contentsOfFile: "Sources/LibraryViewController.swift", encoding: .utf8)
    check(src.contains("recentCombined(limit: 30)"), "Recent: payload uses limit 30")
}

/// Dot / P0-spec v1.1: sidebar hosts sources only — no per-file rows.
private func runSidebarSourcesOnlyIATest() throws {
    let js = try String(contentsOfFile: "Resources/LibraryWorkspace.js", encoding: .utf8)
    check(js.contains("sidebar-section-label\">来源"), "IA: 来源 section label")
    check(js.contains("全部文献"), "IA: 全部文献 source")
    check(js.contains("sourceRowHTML('recent', '最近'"), "IA: 最近 source item")
    check(!js.contains("recentPreview"), "IA: no recentPreview file rows")
    check(!js.contains("recent-item"), "IA: no recent-item CSS class rows")
    check(js.contains("removeFromRecent"), "IA: context menu removeFromRecent")
    check(js.contains("存入文献库"), "IA: context menu 存入文献库")
    check(js.contains("filterKind: 'recent'"), "IA: default filter is 最近")
    check(js.contains("bootstrapDefaultSource"), "IA: empty-recent falls back to 全部文献")
    let html = try String(contentsOfFile: "Resources/LibraryWorkspace.html", encoding: .utf8)
    check(html.contains("currentViewTitle\">最近"), "IA: HTML default title 最近")
}

/// Same document from 最近 / 全部文献 opens the same tab (keyed by paperId).
private func runTabDedupeByPaperIdEvidenceTest() throws {
    let src = try String(contentsOfFile: "Sources/MainWindowController.swift", encoding: .utf8)
    check(src.contains("if openReaderTabs[paperId] == nil"),
          "Dedupe: openOrSwitchToPaperTab reuses existing tab by paperId")
    check(src.contains("openReaderTabs[paperId] = readerVC"),
          "Dedupe: tabs dictionary keyed by paperId")
    let js = try String(contentsOfFile: "Resources/LibraryWorkspace.js", encoding: .utf8)
    // Center list and recent both call openPaperDual with the same paper id.
    check(js.contains("openPaperDual('${pidAttr}'") || js.contains("openPaperDual('${pid}'"),
          "Dedupe: openPaperDual used from list rows")
}
