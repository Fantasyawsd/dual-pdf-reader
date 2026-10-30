import Cocoa
import PDFKit
import WebKit
import JavaScriptCore

var passed = 0
var failed = 0
func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    do {
        if try condition() { passed += 1; print("PASS: \(name)") }
        else { failed += 1; print("FAIL: \(name)") }
    } catch { failed += 1; print("FAIL: \(name): \(error)") }
}
func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 4) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return condition()
}
func writePDF(_ url: URL, pages: Int, text: String = "alpha beta gamma") throws {
    var box = CGRect(x: 0, y: 0, width: 500, height: 700)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
    for page in 0..<pages {
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let lines = text.components(separatedBy: .newlines)
        if lines.count > 1 {
            var y: CGFloat = 640
            for line in lines {
                (line as NSString).draw(at: NSPoint(x: 36, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
                y -= 20
            }
        } else {
            ("\(text) page \(page)" as NSString).draw(at: NSPoint(x: 40, y: 450), withAttributes: [.font: NSFont.systemFont(ofSize: 16)])
        }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
}
func fixture(id: String = UUID().uuidString) -> PaperItem {
    PaperItem(id: id, title: "Fixture", authors: "Test Author", year: "2026", venue: "Test", category: "Tests", tags: [], isFavorite: false, status: .unread, originalFilename: nil, translatedFilename: nil, lastReadPage: 0, lastReadScrollProgress: 0, syncOffsetDelta: 0, annotations: [], resources: [], relatedPapers: [], addedAt: Date(), lastOpenedAt: nil)
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("DualPDF-Regression-\(UUID().uuidString)")
let fm = FileManager.default
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
// Any singleton accidentally touched by a test stays isolated too.
UserDefaults.standard.setVolatileDomain(["DualPDF_LibraryRootPath": root.path], forName: UserDefaults.argumentDomain)
let app = NSApplication.shared
var errors: [String] = []
let store = LibraryStore(rootDirectory: root) { errors.append($0) }
let original = root.appendingPathComponent("source.pdf")
let replacement = root.appendingPathComponent("replacement.pdf")
try writePDF(original, pages: 2)
try writePDF(replacement, pages: 3, text: "new replacement content")
let invalid = root.appendingPathComponent("invalid.pdf")
try Data("invalid".utf8).write(to: invalid)

let paper = store.createPaper(title: "Original", originalSourceURL: original)!
let destination = store.pdfURL(for: paper, side: .original)!
let originalBytes = try Data(contentsOf: destination)
check(store.importPDF(for: paper.id, side: .original, from: root.appendingPathComponent("missing.pdf")) == false,
      "Missing import reports failure")
check(try Data(contentsOf: destination) == originalBytes, "Failed import preserves old PDF bytes")
check(store.importPDF(for: paper.id, side: .original, from: invalid) == false, "Invalid PDF is rejected")
check(try Data(contentsOf: destination) == originalBytes, "Invalid PDF cannot replace old content")
check(store.importPDF(for: paper.id, side: .original, from: destination), "Importing existing file into itself is safe")
check(store.importPDF(for: paper.id, side: .original, from: replacement), "Valid replacement commits")
check(PDFDocument(url: destination)?.pageCount == 3, "Replacement PDF has new content")

let storage = LibraryFileStorage(rootDirectory: root)
let beforeRollback = try Data(contentsOf: destination)
do {
    try storage.replacePDF(from: original, at: destination) { throw CocoaError(.fileWriteNoPermission) }
    check(false, "Metadata failure rolls back replacement")
} catch {
    check(try Data(contentsOf: destination) == beforeRollback, "Metadata failure restores previous PDF")
}
let leftovers = try fm.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
check(!leftovers.contains(where: { $0.hasPrefix(".backup-") || $0.hasPrefix(".import-") }), "Import transaction cleans staging files")

let metadata = store.folderURL(for: paper.id).appendingPathComponent("meta.json")
let metadataBytes = try Data(contentsOf: metadata)
try fm.removeItem(at: metadata)
try fm.createDirectory(at: metadata, withIntermediateDirectories: false)
var changed = store.paper(withId: paper.id)!
changed.title = "Should not publish"
check(!store.savePaper(changed), "Metadata write failure is returned")
check(store.paper(withId: paper.id)?.title == paper.title, "Failed save leaves committed memory unchanged")
check(!store.importPDF(for: paper.id, side: .original, from: original), "Import fails when metadata cannot commit")
check(try Data(contentsOf: destination) == beforeRollback, "Import failure from metadata preserves old PDF")
try fm.removeItem(at: metadata)
try metadataBytes.write(to: metadata, options: .atomic)
check(!errors.isEmpty, "Storage failures reach error handler")

let aFolder = root.appendingPathComponent("sourceA")
let bFolder = root.appendingPathComponent("sourceB")
try fm.createDirectory(at: aFolder, withIntermediateDirectories: true)
try fm.createDirectory(at: bFolder, withIntermediateDirectories: true)
let aURL = aFolder.appendingPathComponent("same.txt")
let bURL = bFolder.appendingPathComponent("same.txt")
try Data("first".utf8).write(to: aURL)
try Data("second".utf8).write(to: bURL)
let attachmentA = store.addLocalAttachment(to: paper.id, fileURL: aURL)!
let attachmentB = store.addLocalAttachment(to: paper.id, fileURL: bURL)!
check(attachmentA.urlOrPath != attachmentB.urlOrPath, "Same-name attachments have unique paths")
check(try String(contentsOfFile: attachmentA.urlOrPath) == "first", "First attachment content survives second import")
check(try String(contentsOfFile: attachmentB.urlOrPath) == "second", "Second attachment content is correct")
check(store.addLocalAttachment(to: paper.id, fileURL: root.appendingPathComponent("missing.txt")) == nil,
      "Missing attachment creates no resource")
let beforeFailedCreate = Set(try fm.contentsOfDirectory(atPath: root.path))
check(store.createPaper(title: "Failed", originalSourceURL: original, translatedSourceURL: invalid) == nil,
      "New paper import is all-or-nothing")
check(Set(try fm.contentsOfDirectory(atPath: root.path)) == beforeFailedCreate, "Failed creation cleans partial paper folder")

let secondPaper = store.createPaper(title: "Second")!
store.linkRelatedPapers(paperAId: paper.id, paperBId: secondPaper.id, note: "test")
check(store.paper(withId: paper.id)!.relatedPapers.count == 1 && store.paper(withId: secondPaper.id)!.relatedPapers.count == 1,
      "Related papers commit in both directions")
let secondMetadata = store.folderURL(for: secondPaper.id).appendingPathComponent("meta.json")
let secondMetadataBytes = try Data(contentsOf: secondMetadata)
let beforeLinkRollback = try Data(contentsOf: metadata)
try fm.removeItem(at: secondMetadata)
try fm.createDirectory(at: secondMetadata, withIntermediateDirectories: false)
store.unlinkRelatedPapers(paperAId: paper.id, paperBId: secondPaper.id)
check(try Data(contentsOf: metadata) == beforeLinkRollback, "Related-paper transaction restores first metadata on second failure")
check(store.paper(withId: paper.id)!.relatedPapers.count == 1, "Failed relation update keeps memory unchanged")
try fm.removeItem(at: secondMetadata)
try secondMetadataBytes.write(to: secondMetadata)
store.unlinkRelatedPapers(paperAId: paper.id, paperBId: secondPaper.id)
check(store.paper(withId: paper.id)!.relatedPapers.isEmpty && store.paper(withId: secondPaper.id)!.relatedPapers.isEmpty,
      "Related papers unlink in both directions")

let notes = store.markdownNotesURL(for: paper.id)
let marker = "external note preserved during reading"
try marker.write(to: notes, atomically: true, encoding: .utf8)
let beforeProgress = try Data(contentsOf: metadata)
var progressNotifications = 0
let progressObserver = NotificationCenter.default.addObserver(forName: LibraryStore.libraryDidChangeNotification, object: store, queue: nil) { _ in progressNotifications += 1 }
for index in 0..<1000 {
    store.updateReadingState(for: paper.id) {
        $0.lastReadPage = index
        $0.readingPosition = ReadingPosition(side: .translated, continuousPage: Double(index) + 0.25)
    }
}
check(try Data(contentsOf: metadata) == beforeProgress, "1000 reading events do not write before flush")
check(store.flushReadingState(), "Reading state flush succeeds")
check(progressNotifications == 1, "1000 reading events publish one committed update")
NotificationCenter.default.removeObserver(progressObserver)
check(try String(contentsOf: notes) == marker, "Reading updates do not rewrite notes.md")
let reloaded = LibraryStore(rootDirectory: root)
check(reloaded.paper(withId: paper.id)?.lastReadPage == 999, "Coalesced reading state survives reload")
check(reloaded.paper(withId: paper.id)?.readingPosition?.continuousPage == 999.25, "Exact page position survives reload")

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
var legacy = try JSONSerialization.jsonObject(with: encoder.encode(fixture())) as! [String: Any]
legacy.removeValue(forKey: "readingPosition")
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let oldPaper = try decoder.decode(PaperItem.self, from: JSONSerialization.data(withJSONObject: legacy))
check(oldPaper.readingPosition == nil, "Existing metadata decodes without new reading position")

let document = PDFDocument(url: original)!
let firstPage = document.page(at: 0)!
let lastPage = document.page(at: 1)!
let combined = firstPage.selection(for: NSRange(location: 0, length: firstPage.numberOfCharacters))!
combined.add(lastPage.selection(for: NSRange(location: 0, length: lastPage.numberOfCharacters))!)
let annotation = PDFSelectionAnnotationFactory.make(selection: combined, document: document, side: .original,
    color: .yellow, note: "note", linkedURL: nil, linkedTitle: nil)!
check(annotation.pageRegions.map(\.pageIndex) == [0, 1], "Cross-page selection preserves all page regions")
let decodedAnnotation = try decoder.decode(PaperAnnotation.self, from: encoder.encode(annotation))
check(decodedAnnotation.pageRegions == annotation.pageRegions, "Cross-page geometry round-trips")
var legacyAnnotation = try JSONSerialization.jsonObject(with: encoder.encode(annotation)) as! [String: Any]
legacyAnnotation.removeValue(forKey: "additionalPageRegions")
let oldAnnotation = try decoder.decode(PaperAnnotation.self, from: JSONSerialization.data(withJSONObject: legacyAnnotation))
check(oldAnnotation.pageRegions.count == 1, "Existing annotations decode without new page regions")
let column = CleanPDFColumnView(side: .original)
column.pdfView.document = document
let renderer = PDFAnnotationRenderer()
renderer.apply([annotation], to: column)
let count = document.page(at: 0)!.annotations.count + document.page(at: 1)!.annotations.count
check(document.page(at: 1)!.annotations.contains { $0.userName == "DualPDF_CustomAnnot" }, "Second page receives highlight")
let existingHighlight = document.page(at: 0)!.annotations.first { $0.userName == "DualPDF_CustomAnnot" }
renderer.apply([annotation], to: column)
check(document.page(at: 0)!.annotations.contains { $0 === existingHighlight }, "Unchanged annotation retains PDFKit object")
check(document.page(at: 0)!.annotations.count + document.page(at: 1)!.annotations.count == count, "Repeated apply never duplicates highlights")
renderer.apply([], to: column)
check(document.page(at: 0)!.annotations.allSatisfy { $0.userName != "DualPDF_CustomAnnot" } &&
      document.page(at: 1)!.annotations.allSatisfy { $0.userName != "DualPDF_CustomAnnot" }, "Removing annotation clears every page region")

let search = PDFSearchController()
var searchResults: [PDFSearchController.Match]?
search.search("alpha", columns: [column]) { searchResults = $0 }
check(waitUntil { searchResults != nil }, "Asynchronous PDF search completes")
check(searchResults?.count == 2, "Asynchronous PDF search returns all pages")
var staleSearchCompleted = false
search.search("alpha", columns: [column]) { _ in staleSearchCompleted = true }
search.search("gamma", columns: [column]) { searchResults = $0 }
searchResults = nil
check(waitUntil { searchResults != nil }, "Replacement search completes after cancelling previous query")
check(!staleSearchCompleted && searchResults?.count == 2, "Cancelled search cannot publish stale results")
search.cancel()

let cache = PDFSummaryCache()
var ready = false
cache.onSummaryReady = { ready = true }
_ = cache.summary(for: original, loadIfNeeded: false)
_ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
check(!ready, "Reading cached metadata never schedules off-screen cover work")
let placeholder = cache.summary(for: original)
check(placeholder.thumbnailDataURL == nil, "Thumbnail cache returns immediately with placeholder")
check(waitUntil { ready }, "Thumbnail is generated asynchronously")
let summary = cache.summary(for: original)
check(summary.pageCount == 2 && summary.thumbnailDataURL?.hasPrefix("data:image/png;base64,") == true, "Cached summary includes page count and PNG")
ready = false
try writePDF(original, pages: 1, text: "replacement")
_ = cache.summary(for: original)
check(waitUntil { ready }, "Changed PDF invalidates cached summary")
check(cache.summary(for: original).pageCount == 1, "Changed PDF receives fresh page count")
cache.removeAll()

final class Handler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}
let userContent = WKUserContentController()
weak var weakHandler: Handler?
autoreleasepool {
    let handler = Handler()
    weakHandler = handler
    userContent.add(WeakScriptMessageHandler(handler), name: "test")
}
check(weakHandler == nil, "WebKit message bridge does not retain owner")
userContent.removeScriptMessageHandler(forName: "test")

weak var releasedReader: ReaderTabViewController?
weak var releasedColumn: CleanPDFColumnView?
autoreleasepool {
    let reader = ReaderTabViewController(paperId: paper.id)
    _ = reader.view
    releasedReader = reader
    releasedColumn = reader.leftCol
    reader.prepareForClose()
}
check(waitUntil { releasedReader == nil }, "Closed reader controller is released")
check(waitUntil { releasedColumn == nil }, "Closed reader releases PDF columns and their callback closures")

let context = JSContext()!
context.evaluateScript(MarkdownMathRenderer.sharedLatexAndMarkdownJS)
check(context.exception == nil, "Markdown renderer JavaScript parses")
let render = context.objectForKeyedSubscript("renderMarkdownWithMath")!
func markdown(_ input: String) -> String { render.call(withArguments: [input])?.toString() ?? "" }
check(markdown("**bold** $\\frac{a}{b}$").contains("class=\"frac\""), "Markdown still renders fractions")
let code = markdown("```swift\nlet text = \"$x$ **bold**\"\n```")
check(!code.contains("math-inline") && !code.contains("<strong>") && code.contains("$x$ **bold**"), "Code fences preserve math and emphasis literally")
check(markdown("`$x$` $y$").components(separatedBy: "math-inline").count == 2, "Inline code is opaque while adjacent math renders")
check(markdown("\\$10").contains("$10"), "Escaped dollar sign remains literal")
check(markdown("@@MD_SLOT_0@@ $x$").contains("@@MD_SLOT_0@@"), "User text cannot collide with renderer placeholders")
check(markdown("<img src=x onerror=alert(1)>").contains("&lt;img"), "Renderer escapes raw HTML")
let complex = markdown("$$\\frac{1}{\\sqrt{1+\\frac{a}{b}}} \\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$")
check(complex.contains("math-matrix") && complex.contains("frac"), "Nested fractions and matrices still render")

let pageHTML = LibraryWorkspacePage.html(initialStateJSON: "{\"papers\":[]}")
check(!pageHTML.contains("__WORKSPACE_") && !pageHTML.contains("__INITIAL_STATE_JSON__") && !pageHTML.contains("__SHARED_RENDERER_JS__"), "Workspace resource template resolves all slots")
check(pageHTML.contains("window.updateLibraryState") && pageHTML.contains("<style>"), "Workspace resources assemble into self-contained page")

// Use a small DOM stub to exercise the metadata snapshot bug without browser automation.
let workspaceJS = try AppResources.text(named: "LibraryWorkspace.js")
let syntaxContext = JSContext()!
let completeJS = workspaceJS.replacingOccurrences(of: "__SHARED_RENDERER_JS__", with: MarkdownMathRenderer.sharedLatexAndMarkdownJS)
    .replacingOccurrences(of: "__INITIAL_STATE_JSON__", with: "{\"papers\":[]}")
let functionConstructor = syntaxContext.objectForKeyedSubscript("Function")!
_ = functionConstructor.construct(withArguments: [completeJS])
check(syntaxContext.exception == nil, "Extracted workspace JavaScript passes full syntax check")
let begin = workspaceJS.range(of: "function readInspectorMetadata")!.lowerBound
let end = workspaceJS.range(of: "function renderNoteCardHTML")!.lowerBound
let metadataJS = String(workspaceJS[begin..<end])
let metadataContext = JSContext()!
metadataContext.evaluateScript("""
var state = { selectedPaperId: 'A' };
var values = {inspTitle: 'Title A', inspAuthors:'Author A', inspYear:'2026', inspVenue:'Test', inspCategory:'A', inspTags:''};
var document = { getElementById: function(id) { return { value: values[id] }; } };
var metaSaveTimer = null, pendingMetadata = null, sent = [];
function setTimeout(fn) { return 1; }
function clearTimeout() {}
function sendBridge(payload) { sent.push(payload); }
\(metadataJS)
scheduleSaveInspMeta('A');
state.selectedPaperId = 'B'; values.inspTitle = 'Title B';
flushPendingMetadata();
""")
check(metadataContext.exception == nil && metadataContext.evaluateScript("sent[0].paperId === 'A' && sent[0].title === 'Title A'")?.toBool() == true,
      "Metadata debounce keeps captured paper and values together")

let sampleRoot = root.appendingPathComponent("Samples")
let sampleStore = LibraryStore(rootDirectory: sampleRoot, seedIfEmpty: true)
var sample = sampleStore.paper(withId: "2024_DeepSeek_V3")!
sample.title = "Edited sample"
check(sampleStore.savePaper(sample), "Sample can be edited")
sampleStore.restoreSamplePapers()
check(sampleStore.paper(withId: sample.id)?.title == "Edited sample", "Restoring samples preserves existing edits")

// --- New Feature Tests: 1. Sorting (支持排序) ---
let sortIds = sampleStore.papers.map(\.id)
if sortIds.count >= 2 {
    let reversedIds = Array(sortIds.reversed())
    check(sampleStore.reorderPapers(orderedIds: reversedIds), "Custom paper sort order commits")
    let reloadedSortStore = LibraryStore(rootDirectory: sampleRoot)
    check(reloadedSortStore.paper(withId: reversedIds[0])?.customSortIndex == 0 &&
          reloadedSortStore.paper(withId: reversedIds[1])?.customSortIndex == 1,
          "Custom sort indices persist across store reload")
}

let sortFnStart = workspaceJS.range(of: "function getFilteredPapers")!.lowerBound
let sortFnEnd = workspaceJS.range(of: "function renderSidebar")!.lowerBound
let sortFnJS = String(workspaceJS[sortFnStart..<sortFnEnd])
let sortJSContext = JSContext()!
sortJSContext.evaluateScript("""
var state = {
    papers: [
        { id: 'p1', title: 'Beta Paper', authors: 'Zeta', year: '2023', venue: 'ICLR', category: 'LLM', tags: [], isFavorite: false, statusRaw: 'completed', addedTimestamp: 100, lastOpenedTimestamp: 200, customSortIndex: 1, annotations: [1, 2], noteDocuments: [] },
        { id: 'p2', title: 'Alpha Paper', authors: 'Adams', year: '2025', venue: 'NeurIPS', category: 'LLM', tags: [], isFavorite: true, statusRaw: 'unread', addedTimestamp: 300, lastOpenedTimestamp: 150, customSortIndex: 0, annotations: [], noteDocuments: [] }
    ]
};
var ui = { filterKind: 'all', activeTag: null, searchQuery: '', sortOrder: 'title', sortAscending: true };
\(sortFnJS)
""")
check(sortJSContext.evaluateScript("getFilteredPapers()[0].id === 'p2'")?.toBool() == true, "Sorting by title ascending places Alpha first")
check(sortJSContext.evaluateScript("ui.sortAscending = false; getFilteredPapers()[0].id === 'p1'")?.toBool() == true, "Toggling sort direction reverses order")
check(sortJSContext.evaluateScript("ui.sortOrder = 'authors'; ui.sortAscending = true; getFilteredPapers()[0].id === 'p2'")?.toBool() == true, "Sorting by authors ascending places Adams first")
check(sortJSContext.evaluateScript("ui.sortOrder = 'notes'; ui.sortAscending = false; getFilteredPapers()[0].id === 'p1'")?.toBool() == true, "Sorting by notes descending places paper with more notes first")
check(sortJSContext.evaluateScript("ui.sortOrder = 'status'; ui.sortAscending = true; getFilteredPapers()[0].id === 'p2'")?.toBool() == true, "Sorting by status places unread before completed")
check(sortJSContext.evaluateScript("ui.sortOrder = 'custom'; ui.sortAscending = true; getFilteredPapers()[0].id === 'p2'")?.toBool() == true, "Sorting by customSortIndex respects user custom ordering")

// --- New Feature Tests: 2. Paper Collection PDFs, Left-PDF Right-Note Mode, & Selection Jumpable Link ---
_ = LibraryStore.shared.switchLibraryRoot(to: sampleRoot)
let extraPDFURL = root.appendingPathComponent("appendix.pdf")
try writePDF(extraPDFURL, pages: 2, text: "Appendix Proofs and Ablation Table")
let addedExtra = LibraryStore.shared.addAdditionalPDF(to: sample.id, from: extraPDFURL, title: "附录 Supplementary")
check(addedExtra != nil, "Paper collection accepts additional PDF documents")
check(LibraryStore.shared.paper(withId: sample.id)?.allPDFDescriptors.count == 3, "Paper collection exposes original, translated, and additional PDFs")

let createdNote = LibraryStore.shared.createNoteDocument(for: sample.id, title: "精读推导笔记", initialContent: "# 初始笔记")
check(createdNote != nil, "Paper collection creates standalone Markdown note document")

autoreleasepool {
    let reader = ReaderTabViewController(paperId: sample.id)
    reader.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    reader.view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))

    // 默认打开中英双栏对照
    check(reader.leftCol.contentSource == .pdf(id: "original") && reader.rightCol.contentSource == .pdf(id: "translated"),
          "Opening paper defaults to Original EN (left) + Translated ZH (right)")

    // 可为每栏设置本论文集内的不同 PDF，且不允许跨论文打开其他论文的 PDF
    if let extraId = addedExtra?.id {
        reader.setColumnSource(reader.rightCol, source: .pdf(id: extraId))
        check(reader.rightCol.contentSource == .pdf(id: extraId) && reader.rightCol.pdfView.document?.pageCount == 2,
              "Column can switch to additional PDF within the same paper collection")
    }
    reader.setColumnSource(reader.leftCol, source: .pdf(id: "foreign_paper_pdf_id"))
    check(reader.leftCol.contentSource == .pdf(id: "original"),
          "Column rejects foreign PDF IDs outside the current paper collection")

    // 切换为左栏论文 + 右栏笔记
    reader.setDisplayMode(3)
    check(reader.leftCol.contentSource.isPDF && reader.rightCol.contentSource.isNote,
          "Display mode 3 switches to Left-PDF + Right-Note layout")

    // 在左栏 PDF 第 2 页选中文本，直接在右栏笔记中创建可跳转链接
    if let doc = reader.leftCol.pdfView.document,
       let page1 = doc.page(at: 1),
       let sel = doc.selection(from: page1, atCharacterIndex: 0, to: page1, atCharacterIndex: min(25, (page1.string?.count ?? 1) - 1)) {
        let quoteRes = reader.quoteSelectionToPaperNote(from: reader.leftCol.pdfView, selection: sel)
        check(quoteRes != nil, "Selecting PDF text directly creates jumpable link in paper note")
        let linkMD = quoteRes?.linkMarkdown ?? ""
        check(linkMD.contains("dualpdf://jump?annot=") && linkMD.contains("&pdf=original&page=1"),
              "Generated Markdown link encodes annotation ID, PDF ID, and page index")
        let renderedHTML = markdown(linkMD)
        check(renderedHTML.contains("class=\"pdf-jump-link\"") && renderedHTML.contains("data-jump-url=\"dualpdf://jump"),
              "Markdown renderer transforms dualpdf://jump link into interactive jump pill")

        // 先回到第 1 页，再模拟点击右栏笔记中的跳转链接，验证左栏跳转到第 2 页并在左栏显示“返回”按钮
        if let page0 = doc.page(at: 0) {
            reader.leftCol.pdfView.go(to: page0)
        }
        if let annotId = quoteRes?.annotation.id {
            let jumpURL = "dualpdf://jump?annot=\(annotId)&pdf=original&page=1"
            reader.handleNoteJumpURL(jumpURL, fromNoteCol: reader.rightCol)
            let currentLeftPage = reader.leftCol.pdfView.currentPage.map { doc.index(for: $0) } ?? -1
            check(currentLeftPage == 1, "Clicking jump link in right-column note scrolls left PDF column to target page")
            check(reader.leftCol.backJumpBanner.isHidden == false && reader.leftCol.backJumpButton.title == "返回",
                  "Jumping from note to left PDF column shows '返回' button on left column")
        }
    }

    // 连续跳转只保留最近一次起点，返回后不可继续回溯；两栏分别验证。
    reader.setColumnSource(reader.rightCol, source: .pdf(id: "translated"))
    reader.syncScrollBtn.state = .off
    reader.toggleSyncScrollAction()
    reader.view.layoutSubtreeIfNeeded()
    for column in [reader.leftCol, reader.rightCol] {
        guard let scrollView = column.internalScrollView(),
              let document = column.pdfView.document,
              let firstPage = document.page(at: 0) else {
            check(false, "Jump-back regression has a loaded PDF and scroll view")
            continue
        }
        let side = column.side.rawValue
        let otherColumn = column === reader.leftCol ? reader.rightCol : reader.leftCol
        column.pdfView.go(to: firstPage)
        var latestOrigin = scrollView.contentView.bounds.origin.y
        for pageIndex in [1, 0, 1, 0] {
            latestOrigin = scrollView.contentView.bounds.origin.y
            reader.handleNoteJumpURL("dualpdf://jump?pdf=\(column.activePDFDocumentId)&page=\(pageIndex)", fromNoteCol: otherColumn)
        }
        check(abs(scrollView.contentView.bounds.origin.y - latestOrigin) > 1,
              "\(side) consecutive jumps reach a different scroll position")
        column.backJumpButton.performClick(nil)
        check(abs(scrollView.contentView.bounds.origin.y - latestOrigin) < 1,
              "\(side) back returns to the latest jump origin")
        check(column.backJumpBanner.isHidden && column.backJumpButton.keyEquivalent.isEmpty,
              "\(side) back consumes the only return point and clears its shortcut")
        let returnedOrigin = scrollView.contentView.bounds.origin.y
        reader.popBackJumpAction(for: column)
        check(abs(scrollView.contentView.bounds.origin.y - returnedOrigin) < 1 && column.backJumpBanner.isHidden,
              "\(side) repeated back cannot reach an older jump")
        reader.handleNoteJumpURL("dualpdf://jump?pdf=\(column.activePDFDocumentId)&page=0", fromNoteCol: otherColumn)
        check(!column.backJumpBanner.isHidden, "\(side) a new jump enables back again")
        reader.popBackJumpAction()
        check(abs(scrollView.contentView.bounds.origin.y - returnedOrigin) < 1 && column.backJumpBanner.isHidden,
              "\(side) keyboard back consumes a newly recorded return point")
    }

    reader.pushJumpRecord(from: reader.leftCol)
    reader.pushJumpRecord(from: reader.rightCol)
    reader.popBackJumpAction()
    check(reader.rightCol.backJumpBanner.isHidden && !reader.leftCol.backJumpBanner.isHidden &&
          reader.leftCol.backJumpButton.keyEquivalent == "[",
          "Returning the latest column preserves the other column return point and shortcut")
    reader.popBackJumpAction()
    check(reader.leftCol.backJumpBanner.isHidden && reader.rightCol.backJumpBanner.isHidden &&
          reader.leftCol.backJumpButton.keyEquivalent.isEmpty && reader.rightCol.backJumpButton.keyEquivalent.isEmpty,
          "Each column has exactly one independent return point")

    if let extraId = addedExtra?.id, let scrollView = reader.leftCol.internalScrollView() {
        let originalOrigin = scrollView.contentView.bounds.origin.y
        reader.handleNoteJumpURL("dualpdf://jump?pdf=\(extraId)&page=1", fromNoteCol: reader.rightCol)
        check(reader.leftCol.contentSource == .pdf(id: extraId), "Jump can target another PDF in the same paper")
        reader.popBackJumpAction(for: reader.leftCol)
        check(reader.leftCol.contentSource == .pdf(id: "original") && reader.leftCol.backJumpBanner.isHidden,
              "Single-step back restores the original PDF and consumes its return point")
        check(abs((reader.leftCol.internalScrollView()?.contentView.bounds.origin.y ?? -1) - originalOrigin) < 1,
              "Single-step back restores the original PDF scroll position")
    }

    reader.pushJumpRecord(from: reader.leftCol)
    reader.pushJumpRecord(from: reader.rightCol)
    reader.loadPaperDocuments()
    reader.popBackJumpAction()
    check(reader.leftCol.backJumpBanner.isHidden && reader.rightCol.backJumpBanner.isHidden &&
          reader.leftCol.backJumpButton.keyEquivalent.isEmpty && reader.rightCol.backJumpButton.keyEquivalent.isEmpty,
          "Reloading documents clears both single-step return points and shortcuts")

    reader.prepareForClose()
}

// --- New Feature Tests: 3. Selection LLM Translation (划词支持 LLM 翻译) ---
var translatedOutput: LLMTranslationResult?
LLMTranslationService.shared.translate(
    text: "We propose Multi-head Latent Attention (MLA) and an auxiliary-loss-free strategy for load balancing in Mixture-of-Experts (MoE).",
    mode: .academicChinese,
    pairedPageText: "我们提出了多头潜在注意力机制（MLA）以及用于混合专家（MoE）负载均衡的无辅助损失策略。"
) { res in
    translatedOutput = res
}
check(waitUntil { translatedOutput != nil }, "Selection LLM translation service completes")
check((translatedOutput?.translatedMarkdown.contains("多头潜在注意力") == true) &&
      (translatedOutput?.translatedMarkdown.contains("无辅助损失") == true),
      "Selection LLM translation accurately translates academic terms and incorporates paired context")

// --- 4. PDF Metadata Extraction (跳过版权免责页眉并提取真实标题与多行作者) ---
let attentionPDF = root.appendingPathComponent("attention_test.pdf")
try writePDF(attentionPDF, pages: 1, text: """
Provided proper attribution is provided, Google hereby grants permission to
reproduce the tables and figures in this paper solely for use in journalistic or
scholarly works.
Attention Is All You Need
Ashish Vaswani∗
Google Brain
avaswani@google.com
Noam Shazeer∗
Google Brain
noam@google.com
Abstract
The dominant sequence transduction models are based on complex recurrent neural networks.
""")
let extractedMeta = PDFMetadataExtractor.extractMetadata(from: attentionPDF)
check(extractedMeta.title == "Attention Is All You Need", "PDFMetadataExtractor skips copyright attribution header and finds true title")
check(extractedMeta.authors.contains("Ashish Vaswani") && extractedMeta.authors.contains("Noam Shazeer") && !extractedMeta.authors.contains("Google Brain"),
      "PDFMetadataExtractor joins multi-line authors while skipping affiliations and emails")

// --- 5. Window Title Bar Double Click Zoom & Window Moving Support ---
let testWin = NSWindow(
    contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
    styleMask: [.titled, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
let titleBarView = DraggableTitleBarView(frame: NSRect(x: 0, y: 360, width: 600, height: 40))
let tabScroll = HorizontalTabScrollView(frame: NSRect(x: 80, y: 0, width: 400, height: 40))
let docView = DraggableTabDocumentView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
tabScroll.documentView = docView
titleBarView.addSubview(tabScroll)
testWin.contentView?.addSubview(titleBarView)

check(titleBarView.mouseDownCanMoveWindow && tabScroll.mouseDownCanMoveWindow && docView.mouseDownCanMoveWindow,
      "Title bar and tab scroll view permit window movement on drag")

check(TabOrder.moving("B", toInsertionIndex: 0, in: ["A", "B", "C"]) == ["B", "A", "C"],
      "Tab order moves a tab to the leading edge")
check(TabOrder.moving("A", toInsertionIndex: 3, in: ["A", "B", "C"]) == ["B", "C", "A"],
      "Tab order moves a tab to the trailing edge")
check(TabOrder.moving("C", toInsertionIndex: 2, in: ["A", "B", "C"]) == ["A", "B", "C"],
      "Dropping a tab before itself preserves order")
check(TabOrder.insertionIndex(
    forX: 95,
    tabFrames: [
        NSRect(x: 0, y: 0, width: 100, height: 32),
        NSRect(x: 106, y: 0, width: 100, height: 32)
    ]
) == 1, "Tab insertion index follows the nearest tab midpoint")

let dragStack = NonDraggableStackView(frame: NSRect(x: 0, y: 0, width: 400, height: 34))
dragStack.draggingExited(nil)
check(!dragStack.isHidden, "Finishing a drag outside the tab strip does not invoke an unavailable superclass callback")

let activeTabItem = ZoteroTabItemView(tabId: "active", title: "Active", symbol: "doc.richtext.fill", symbolTint: .systemRed, isActive: true, closable: true)
let inactiveTabItem = ZoteroTabItemView(tabId: "inactive", title: "Inactive", symbol: "doc.richtext.fill", symbolTint: .systemRed, isActive: false, closable: true)
check(!activeTabItem.closeButton.isHidden && inactiveTabItem.closeButton.isHidden,
      "Obsidian-style tabs show close controls on the active tab and only reveal inactive controls on hover")

let initialFrame = testWin.frame
let dummyEvent = NSEvent.mouseEvent(
    with: .leftMouseDown,
    location: NSPoint(x: 10, y: 10),
    modifierFlags: [],
    timestamp: 0,
    windowNumber: testWin.windowNumber,
    context: nil,
    eventNumber: 1,
    clickCount: 2,
    pressure: 1.0
)!
titleBarView.mouseDown(with: dummyEvent)
check(testWin.frame != initialFrame || testWin.isZoomed,
      "Double clicking title bar triggers window zoom and resizes window")

// --- 6. Item-Centric Architecture, ArXiv Resolution, Overlay Left Sidebar & Standalone Window ---

// (A) ArXiv ID normalization
check(ArxivMetadataService.normalizeArxivId("1706.03762v7") == "1706.03762v7", "Normalize raw arXiv ID with version")
check(ArxivMetadataService.normalizeArxivId("https://arxiv.org/abs/1706.03762v7") == "1706.03762v7", "Normalize arXiv abs URL")
check(ArxivMetadataService.normalizeArxivId("https://hjfy.top/arxiv/1706.03762v7") == "1706.03762v7", "Normalize Hjfy translation URL")
check(ArxivMetadataService.normalizeArxivId("arXiv: 2412.19437") == "2412.19437", "Normalize arXiv: prefix with whitespace")

// (B) Fast arXiv ID scanning in PDF
let testArxivPDF = root.appendingPathComponent("arxiv_test.pdf")
try writePDF(testArxivPDF, pages: 1, text: "arXiv:1706.03762v7 [cs.CL] 12 Jun 2017\nAttention Is All You Need")
check(PDFMetadataExtractor.fastScanArxivId(from: testArxivPDF) == "1706.03762v7", "Fast scan detects arXiv ID from PDF header")

// (C) Item creation named after primary PDF
let primarySamplePDF = root.appendingPathComponent("Attention_Is_All_You_Need.pdf")
try writePDF(primarySamplePDF, pages: 2, text: "Attention Is All You Need\nAshish Vaswani")
let createdItem = store.createPaper(title: "Attention Is All You Need", originalSourceURL: primarySamplePDF)!
check(createdItem.id == "Attention_Is_All_You_Need", "Item ID matches primary PDF filename")
check(createdItem.originalFilename == "Attention_Is_All_You_Need.pdf", "Primary PDF stored with original file naming")

// (D) Import translated PDF and attachment
let transSamplePDF = root.appendingPathComponent("Attention_zh.pdf")
try writePDF(transSamplePDF, pages: 2, text: "注意力机制详解")
check(store.importTranslatedPDF(for: createdItem.id, from: transSamplePDF), "Import translated PDF commits successfully")
let reloadedItem = store.paper(withId: createdItem.id)!
check(reloadedItem.translatedFilename == "Attention_Is_All_You_Need_zh.pdf", "Translated PDF named with item suffix")

let dummyAttachment = root.appendingPathComponent("supplement.zip")
try Data("test_bytes".utf8).write(to: dummyAttachment)
let res = store.importAttachmentFile(for: createdItem.id, from: dummyAttachment)
check(res != nil && res?.isLocalFile == true, "Import attachment stores file in attachments directory")
let expectedAttachPath = store.folderURL(for: createdItem.id).appendingPathComponent("attachments/supplement.zip")
check(FileManager.default.fileExists(atPath: expectedAttachPath.path), "Attachment file exists in item attachments directory")

// (E) Left overlay sidebar (0 volume collision) & right Zotero 7 workbench
let testReader = ReaderTabViewController(paperId: createdItem.id)
_ = testReader.view
testReader.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
testReader.view.layoutSubtreeIfNeeded()
let splitWidthBefore = testReader.leftCol.frame.width
testReader.toggleLeftSidebarAction()
testReader.view.layoutSubtreeIfNeeded()
let splitWidthAfter = testReader.leftCol.frame.width
check(abs(splitWidthBefore - splitWidthAfter) < 0.01 && splitWidthBefore > 100, "Left sidebar is overlay with zero volume collision (left column width unchanged)")
testReader.toggleLeftSidebarAction()

// Verify right drawer is independent and dual PDF columns remain balanced 50/50
testReader.view.layoutSubtreeIfNeeded()
let dualLeftBefore = testReader.leftCol.frame.width
let dualRightBefore = testReader.rightCol.frame.width
check(abs(dualLeftBefore - dualRightBefore) <= 2.0 && dualLeftBefore > 100, "Dual PDF columns are equally balanced 50/50 when right drawer is closed")

testReader.toggleRightDrawerAction()
testReader.view.layoutSubtreeIfNeeded()
let dualLeftWithDrawer = testReader.leftCol.frame.width
let dualRightWithDrawer = testReader.rightCol.frame.width
check(abs(dualLeftWithDrawer - dualRightWithDrawer) <= 2.0 && dualLeftWithDrawer > 100, "Dual PDF columns remain equally balanced 50/50 when right drawer is opened")
check(dualLeftWithDrawer < dualLeftBefore, "Dual columns shrink equally to accommodate right sidebar")

testReader.toggleRightDrawerAction()
testReader.view.layoutSubtreeIfNeeded()
let dualLeftAfter = testReader.leftCol.frame.width
let dualRightAfter = testReader.rightCol.frame.width
check(abs(dualLeftAfter - dualRightAfter) <= 2.0 && abs(dualLeftAfter - dualLeftBefore) <= 2.0, "Dual PDF columns restore to full width 50/50 when right drawer is closed")

// (F) Standalone window controller
let standaloneCtrl = StandaloneReaderWindowController(paperId: createdItem.id, store: store)
check(standaloneCtrl.window != nil && standaloneCtrl.window?.title == createdItem.title, "Standalone reader window initializes with paper title")
standaloneCtrl.windowWillClose(Notification(name: NSWindow.willCloseNotification))

// (G) Workbench Functional Upgrades: Tags, External Links, Attachments & Translation
// 1. Tag management
check(store.addTag("Deep Learning", for: createdItem.id), "Add tag succeeds")
check(store.addTag("Transformer", for: createdItem.id), "Add second tag succeeds")
check(!store.addTag("Transformer", for: createdItem.id), "Duplicate tag is ignored")
let taggedPaper = store.paper(withId: createdItem.id)!
check(taggedPaper.tags.contains("Deep Learning") && taggedPaper.tags.contains("Transformer"), "Tags persisted in paper metadata")
check(store.allUniqueTags.contains("Deep Learning"), "allUniqueTags aggregates tags across library")
check(store.removeTag("Transformer", for: createdItem.id), "Remove tag succeeds")
let updatedTagPaper = store.paper(withId: createdItem.id)!
check(!updatedTagPaper.tags.contains("Transformer") && updatedTagPaper.tags.contains("Deep Learning"), "Tag successfully removed from paper")

// 2. Custom external links & resource deletion
let extLink = store.addExternalLink(for: createdItem.id, title: "Official Repo", url: "https://github.com/tensorflow/tensor2tensor")
check(extLink != nil && extLink?.isLocalFile == false, "Add external link succeeds")
let linkedPaper = store.paper(withId: createdItem.id)!
check(linkedPaper.resources.contains(where: { $0.urlOrPath == "https://github.com/tensorflow/tensor2tensor" }), "External link persisted in resources")

// Test local attachment deletion
if let attachRes = res {
    check(store.deleteExternalResource(for: createdItem.id, resourceId: attachRes.id), "Delete local attachment succeeds")
    let afterDelPaper = store.paper(withId: createdItem.id)!
    check(!afterDelPaper.resources.contains(where: { $0.id == attachRes.id }), "Attachment removed from resources")
    check(!FileManager.default.fileExists(atPath: expectedAttachPath.path), "Attachment file deleted from disk")
}

// 3. Translated PDF removal
check(store.removeTranslatedPDF(for: createdItem.id), "Remove translated PDF succeeds")
let afterTransDelPaper = store.paper(withId: createdItem.id)!
check(afterTransDelPaper.translatedFilename == nil, "Translated filename cleared in metadata")
let expectedTransPath = store.folderURL(for: createdItem.id).appendingPathComponent("Attention_Is_All_You_Need_zh.pdf")
check(!FileManager.default.fileExists(atPath: expectedTransPath.path), "Translated PDF file removed from disk")

// 4. Workbench tab switching & rendering integrity
testReader.toggleRightDrawerAction() // open drawer
testReader.switchWorkbenchTab(to: 2) // Translation
testReader.view.layoutSubtreeIfNeeded()
check(testReader.currentWorkbenchTab == 2, "Switched to Translation tab")
check(!testReader.tabTranslationContainer.isHidden, "Translation container is visible")

testReader.switchWorkbenchTab(to: 3) // Attachments
testReader.view.layoutSubtreeIfNeeded()
check(testReader.currentWorkbenchTab == 3, "Switched to Attachments tab")
check(!testReader.tabAttachmentsContainer.isHidden, "Attachments container is visible")

testReader.switchWorkbenchTab(to: 4) // Tags
testReader.view.layoutSubtreeIfNeeded()
check(testReader.currentWorkbenchTab == 4, "Switched to Tags tab")
check(!testReader.tabTagsContainer.isHidden, "Tags container is visible")

testReader.switchWorkbenchTab(to: 5) // Links
testReader.view.layoutSubtreeIfNeeded()
check(testReader.currentWorkbenchTab == 5, "Switched to Links tab")
check(!testReader.tabLinksContainer.isHidden, "Links container is visible")

print("\nRegression tests: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
