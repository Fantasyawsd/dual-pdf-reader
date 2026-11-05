import Cocoa
import CryptoKit
import PDFKit

/// P0-2 temporary documents: bookmark + state.json only — never copies PDF bytes.
final class TransientStore {
    static let didChangeNotification = Notification.Name("TransientStoreDidChangeNotification")
    private static let defaultShared = TransientStore()
    private static var sharedOverride: TransientStore?
    static var shared: TransientStore { sharedOverride ?? defaultShared }

    /// Test-only: point `shared` at an isolated root. Pass nil to restore.
    static func useTestRoot(_ root: URL?) {
        if let root {
            sharedOverride = TransientStore(testRoot: root)
        } else {
            sharedOverride = nil
        }
    }

    private(set) var papers: [PaperItem] = []
    private var papersByID: [String: PaperItem] = [:]
    /// In-memory unlocked PDFDocuments for encrypted sources (never written to disk).
    private var unlockedDocuments: [String: PDFDocument] = [:]
    private var accessingURLs: [String: URL] = [:]
    private var pendingReadingUpdates: [String: PaperItem] = [:]
    private var readingSaveTask: DispatchWorkItem?
    private let persistQueue = DispatchQueue(label: "com.dualpdf.transient.persist", qos: .utility)
    /// Test seam: count of disk writes from reading-state flush.
    private(set) var readingPersistCountForTests = 0
    /// Test seam: force the next savePaper inside promoteToLibrary to fail.
    static var testingPromoteSavePaperResult: Bool? = nil
    private let rootDirectory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DualPDF", isDirectory: true)
                .appendingPathComponent("Transient", isDirectory: true)
            self.rootDirectory = base
        }
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        reloadAll()
        pruneStale()
    }

    /// Test seam.
    convenience init(testRoot: URL) {
        self.init(rootDirectory: testRoot)
    }

    var allPapers: [PaperItem] { papers }

    func contains(_ id: String) -> Bool { papersByID[id] != nil }

    func paper(withId id: String) -> PaperItem? { papersByID[id] }

    func folderURL(for id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func stateURL(for id: String) -> URL {
        folderURL(for: id).appendingPathComponent("state.json")
    }

    // MARK: - Open / create

    /// Create or refresh a transient paper for one or two PDF URLs. Does not copy file bytes.
    @discardableResult
    func openPDFs(_ urls: [URL], unlockedDocument: PDFDocument? = nil) -> PaperItem? {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard let primary = pdfs.first else { return nil }
        let classified = PDFMetadataExtractor.classifyPDFPair(pdfs)
        let originalURL = classified.original ?? primary
        let translatedURL = classified.translated

        let key = FileIdentity.docKey(for: originalURL)
        LibraryStore.shared.registerTransientPaper(id: key)

        if let unlockedDocument {
            unlockedDocuments[key] = unlockedDocument
        }

        var item: PaperItem
        if let existing = papersByID[key] {
            item = existing
        } else {
            let meta: (title: String, authors: String, year: String, arxivId: String?)
            if unlockedDocument != nil {
                // Avoid forcing PDFKit to re-read a still-encrypted file for metadata.
                let name = originalURL.deletingPathExtension().lastPathComponent
                meta = (name, "", "", PDFMetadataExtractor.fastScanArxivId(from: originalURL))
            } else {
                meta = PDFMetadataExtractor.extractMetadata(from: originalURL)
            }
            let title = meta.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? originalURL.deletingPathExtension().lastPathComponent
                : meta.title
            item = PaperItem(
                id: key,
                title: title,
                authors: meta.authors,
                year: meta.year,
                venue: meta.arxivId != nil ? "arXiv" : "",
                category: "临时打开",
                tags: [],
                isFavorite: false,
                status: .unread,
                originalFilename: nil,
                translatedFilename: nil,
                lastReadPage: 0,
                lastReadScrollProgress: 0,
                syncOffsetDelta: 0,
                annotations: [],
                resources: [],
                relatedPapers: [],
                addedAt: Date(),
                lastOpenedAt: Date(),
                arxivId: meta.arxivId,
                isTransient: true
            )
        }

        item.isTransient = true
        item.originalFilename = Self.bookmarkString(for: originalURL)
        if let translatedURL {
            item.translatedFilename = Self.bookmarkString(for: translatedURL)
        }
        item.lastOpenedAt = Date()
        // Transient docs must not hit the network (spec §2.3).
        guard persist(item) else { return nil }
        return item
    }

    func setUnlockedDocument(_ document: PDFDocument?, for id: String) {
        if let document {
            unlockedDocuments[id] = document
        } else {
            unlockedDocuments.removeValue(forKey: id)
        }
    }

    func unlockedDocument(for id: String) -> PDFDocument? { unlockedDocuments[id] }

    // MARK: - PDF access

    func pdfURL(for paper: PaperItem, side: PDFSide) -> URL? {
        let stored = side == .original ? paper.originalFilename : paper.translatedFilename
        guard let stored else { return nil }
        return resolveBookmark(stored, accessKey: "\(paper.id)-\(side.rawValue)")
    }

    func pdfURL(for paper: PaperItem, pdfId: String) -> URL? {
        if pdfId == PDFSide.original.rawValue { return pdfURL(for: paper, side: .original) }
        if pdfId == PDFSide.translated.rawValue { return pdfURL(for: paper, side: .translated) }
        return nil
    }

    func sourceURL(for paperId: String, side: PDFSide = .original) -> URL? {
        guard let paper = papersByID[paperId] else { return nil }
        return pdfURL(for: paper, side: side)
    }

    // MARK: - Writes (same surface as LibraryStore subset)

    @discardableResult
    func savePaper(_ paper: PaperItem, notify: Bool = true) -> Bool {
        var item = paper
        item.isTransient = true
        // Merge any coalesced reading-state so annotation saves keep the latest
        // scroll/zoom, and so a later flush cannot rewrite a stale whole-paper snapshot.
        if let pending = pendingReadingUpdates[item.id] {
            item.applyReadingFields(from: pending)
        }
        guard persist(item) else { return false }
        pendingReadingUpdates.removeValue(forKey: item.id)
        if pendingReadingUpdates.isEmpty {
            readingSaveTask?.cancel()
            readingSaveTask = nil
        }
        if notify { publish(ids: [item.id]) }
        return true
    }

    func updateReadingState(for paperId: String, _ update: (inout PaperItem) -> Void) {
        guard var paper = pendingReadingUpdates[paperId] ?? papersByID[paperId] else { return }
        update(&paper)
        paper.isTransient = true
        pendingReadingUpdates[paperId] = paper
        papersByID[paperId] = paper
        if let idx = papers.firstIndex(where: { $0.id == paperId }) {
            papers[idx] = paper
        }
        readingSaveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            _ = self?.flushReadingState()
        }
        readingSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: task)
    }

    /// Persist coalesced reading-state updates. Memory is updated on the caller thread;
    /// atomic disk writes run off-main and are waited on so terminate/close see durable state.
    @discardableResult
    func flushReadingState() -> Bool {
        readingSaveTask?.cancel()
        readingSaveTask = nil
        let updates = pendingReadingUpdates
        pendingReadingUpdates.removeAll()
        guard !updates.isEmpty else { return true }

        var payloads: [(id: String, url: URL, data: Data)] = []
        for (id, pending) in updates {
            // Only overlay reading fields onto the current in-memory paper so a
            // deferred flush cannot clobber annotations saved after the scroll.
            var item = papersByID[id] ?? pending
            item.applyReadingFields(from: pending)
            item.isTransient = true
            papersByID[item.id] = item
            if let idx = papers.firstIndex(where: { $0.id == item.id }) {
                papers[idx] = item
            } else {
                papers.insert(item, at: 0)
            }
            LibraryStore.shared.registerTransientPaper(id: item.id)
            do {
                let dir = folderURL(for: item.id)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try encoder.encode(item)
                payloads.append((item.id, stateURL(for: item.id), data))
            } catch {
                NSLog("[DualPDF][P0-2] TransientStore encode failed: %@", error.localizedDescription)
                return false
            }
        }

        var ok = true
        let group = DispatchGroup()
        group.enter()
        persistQueue.async {
            for payload in payloads {
                do {
                    try payload.data.write(to: payload.url, options: .atomic)
                } catch {
                    NSLog("[DualPDF][P0-2] TransientStore flush write failed: %@", error.localizedDescription)
                    ok = false
                }
            }
            self.readingPersistCountForTests += 1
            group.leave()
        }
        group.wait()
        return ok
    }

    @discardableResult
    func addTag(_ tag: String, for paperId: String) -> Bool {
        guard var item = papersByID[paperId] else { return false }
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !item.tags.contains(clean) else { return false }
        item.tags.append(clean)
        return savePaper(item, notify: true)
    }

    @discardableResult
    func removeTag(_ tag: String, for paperId: String) -> Bool {
        guard var item = papersByID[paperId] else { return false }
        guard let idx = item.tags.firstIndex(of: tag) else { return false }
        item.tags.remove(at: idx)
        return savePaper(item, notify: true)
    }

    @discardableResult
    func addExternalLink(for paperId: String, title: String, url: String) -> ExternalResource? {
        guard var item = papersByID[paperId] else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty else { return nil }
        let res = ExternalResource(title: cleanTitle.isEmpty ? cleanUrl : cleanTitle, urlOrPath: cleanUrl, isLocalFile: false)
        item.resources.append(res)
        guard savePaper(item, notify: true) else { return nil }
        return res
    }

    @discardableResult
    func saveNoteDocument(for paperId: String, note: PaperNoteDocument, notify: Bool = true) -> Bool {
        guard var item = papersByID[paperId] else { return false }
        var docs = item.effectiveNoteDocuments
        var updated = note
        updated.updatedAt = Date()
        if let idx = docs.firstIndex(where: { $0.id == note.id }) {
            docs[idx] = updated
        } else {
            docs.append(updated)
        }
        item.noteDocuments = docs
        return savePaper(item, notify: notify)
    }

    @discardableResult
    func createNoteDocument(for paperId: String, title: String, initialContent: String = "") -> PaperNoteDocument? {
        guard var item = papersByID[paperId] else { return nil }
        var docs = item.effectiveNoteDocuments
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNote = PaperNoteDocument(
            id: UUID().uuidString,
            title: cleanTitle.isEmpty ? "笔记 \(docs.count + 1)" : cleanTitle,
            markdownContent: initialContent,
            createdAt: Date(),
            updatedAt: Date()
        )
        docs.append(newNote)
        item.noteDocuments = docs
        guard savePaper(item, notify: true) else { return nil }
        return newNote
    }

    @discardableResult
    func deleteNoteDocument(for paperId: String, noteId: String) -> Bool {
        guard var item = papersByID[paperId] else { return false }
        var docs = item.effectiveNoteDocuments
        guard docs.count > 1 else { return false }
        docs.removeAll { $0.id == noteId }
        item.noteDocuments = docs
        return savePaper(item, notify: true)
    }

    @discardableResult
    func appendContentToNote(for paperId: String, noteId: String? = nil, markdownSnippet: String) -> PaperNoteDocument? {
        guard var item = papersByID[paperId] else { return nil }
        var docs = item.effectiveNoteDocuments
        let targetIdx = noteId.flatMap { id in docs.firstIndex(where: { $0.id == id }) } ?? 0
        guard targetIdx >= 0 && targetIdx < docs.count else { return nil }
        var doc = docs[targetIdx]
        let existing = doc.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            doc.markdownContent = markdownSnippet
        } else {
            doc.markdownContent = doc.markdownContent
                + (doc.markdownContent.hasSuffix("\n\n") ? "" : (doc.markdownContent.hasSuffix("\n") ? "\n" : "\n\n"))
                + markdownSnippet
        }
        doc.updatedAt = Date()
        docs[targetIdx] = doc
        item.noteDocuments = docs
        guard savePaper(item, notify: true) else { return nil }
        return doc
    }

    /// Attachments / extra PDFs are not supported on transient docs (would require copying).
    func addLocalAttachment(to paperId: String, fileURL: URL, customTitle: String? = nil) -> ExternalResource? {
        NSLog("[DualPDF][P0-2] addLocalAttachment ignored for transient id=%@", paperId)
        return nil
    }

    func addAdditionalPDF(to paperId: String, from sourceURL: URL, title: String? = nil, replacingId: String? = nil) -> PaperPDFDocument? {
        NSLog("[DualPDF][P0-2] addAdditionalPDF ignored for transient id=%@", paperId)
        return nil
    }

    // MARK: - Promote to library

    struct PromoteFields {
        var title: String
        var authors: String
        var year: String
        var venue: String
        var category: String
    }

    /// Copy original PDFs into the library, migrate annotations/notes/reader state, delete transient.
    func promoteToLibrary(id: String, fields: PromoteFields) -> Result<PaperItem, Error> {
        guard let transient = papersByID[id] else {
            return .failure(PromoteError.missing)
        }
        guard let originalURL = pdfURL(for: transient, side: .original) else {
            return .failure(PromoteError.unreadable)
        }
        let translatedURL = pdfURL(for: transient, side: .translated)

        guard let created = LibraryStore.shared.createPaper(
            title: fields.title,
            authors: fields.authors,
            year: fields.year,
            venue: fields.venue,
            category: fields.category,
            tags: transient.tags,
            arxivId: transient.arxivId,
            citationCount: transient.citationCount,
            originalSourceURL: originalURL,
            translatedSourceURL: translatedURL
        ) else {
            return .failure(PromoteError.writeFailed("无法创建文献库条目。"))
        }

        var migrated = created
        migrated.annotations = transient.annotations
        migrated.noteDocuments = transient.noteDocuments
        migrated.readerState = transient.readerState
        migrated.readingPosition = transient.readingPosition
        migrated.syncOffsetDelta = transient.syncOffsetDelta
        migrated.lastReadPage = transient.lastReadPage
        migrated.lastReadScrollProgress = transient.lastReadScrollProgress
        migrated.lastOpenedAt = Date()
        migrated.resources = transient.resources.filter { !$0.isLocalFile }
        migrated.isTransient = false

        _ = flushReadingState()

        let saveOK: Bool
        if let forced = Self.testingPromoteSavePaperResult {
            Self.testingPromoteSavePaperResult = nil
            saveOK = forced
        } else {
            saveOK = LibraryStore.shared.savePaper(migrated, notify: true)
        }
        guard saveOK else {
            // C1: roll back the half-created library entry (PDF copy + folder).
            _ = LibraryStore.shared.deletePaper(id: created.id)
            return .failure(PromoteError.writeFailed("条目已创建，但笔记迁移失败。"))
        }

        // Optional arXiv refresh only after promote (spec §2.3).
        if let arxiv = migrated.cleanArxivId {
            LibraryStore.shared.refreshPaperArxivMetadata(paperId: migrated.id, arxivId: arxiv, completion: nil)
        }

        // C3: keep the in-memory unlocked PDFDocument under the new library id.
        if let unlocked = unlockedDocuments.removeValue(forKey: id) {
            unlockedDocuments[created.id] = unlocked
        }

        deleteTransient(id: id, clearUnlocked: false)
        return .success(migrated)
    }

    func transferUnlockedDocument(from oldId: String, to newId: String) {
        if let doc = unlockedDocuments.removeValue(forKey: oldId) {
            unlockedDocuments[newId] = doc
        }
    }

    func deleteTransient(id: String, clearUnlocked: Bool = true) {
        _ = flushReadingState()
        pendingReadingUpdates.removeValue(forKey: id)
        if clearUnlocked {
            unlockedDocuments.removeValue(forKey: id)
        }
        for key in accessingURLs.keys.filter({ $0.hasPrefix(id) }) {
            accessingURLs[key]?.stopAccessingSecurityScopedResource()
            accessingURLs.removeValue(forKey: key)
        }
        papersByID.removeValue(forKey: id)
        papers.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folderURL(for: id))
        LibraryStore.shared.unregisterTransientPaper(id: id)
        publish(ids: [id])
    }

    /// Soft-remove from 「最近」without deleting notes/state.
    @discardableResult
    func removeFromRecent(id: String) -> Bool {
        guard var item = papersByID[id] else { return false }
        item.lastOpenedAt = nil
        return savePaper(item, notify: true)
    }

    // MARK: - Recents helpers

    /// Papers for the center list when source 「最近」 is selected (transient + library), newest first, max 30.
    static func recentCombined(limit: Int = 30) -> [PaperItem] {
        let library = LibraryStore.shared.papers.filter { $0.lastOpenedAt != nil }
        let transient = TransientStore.shared.papers.filter { $0.lastOpenedAt != nil }
        let merged = (library + transient).sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }
        return Array(merged.prefix(limit))
    }

    // MARK: - Persistence

    private func persist(_ paper: PaperItem) -> Bool {
        do {
            let dir = folderURL(for: paper.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var item = paper
            item.isTransient = true
            let data = try encoder.encode(item)
            try data.write(to: stateURL(for: paper.id), options: .atomic)
            papersByID[item.id] = item
            if let idx = papers.firstIndex(where: { $0.id == item.id }) {
                papers[idx] = item
            } else {
                papers.insert(item, at: 0)
            }
            LibraryStore.shared.registerTransientPaper(id: item.id)
            return true
        } catch {
            NSLog("[DualPDF][P0-2] TransientStore persist failed: %@", error.localizedDescription)
            return false
        }
    }

    private func reloadAll() {
        papers = []
        papersByID = [:]
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let state = dir.appendingPathComponent("state.json")
            guard let data = try? Data(contentsOf: state),
                  var item = try? decoder.decode(PaperItem.self, from: data) else { continue }
            item.isTransient = true
            item.id = dir.lastPathComponent
            papersByID[item.id] = item
            papers.append(item)
            LibraryStore.shared.registerTransientPaper(id: item.id)
        }
        papers.sort { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
    }

    /// Drop entries unused for 90 days with no notes (spec §2.1).
    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let stale = papers.filter { item in
            guard !item.transientHasNotes else { return false }
            let last = item.lastOpenedAt ?? item.addedAt
            return last < cutoff
        }
        for item in stale {
            deleteTransient(id: item.id)
        }
    }

    private func publish(ids: Set<String>) {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: ["ids": Array(ids)]
        )
        // Also nudge library UI so "最近" refreshes.
        NotificationCenter.default.post(name: LibraryStore.libraryDidChangeNotification, object: LibraryStore.shared)
    }

    // MARK: - Bookmarks

    private static let bookmarkPrefix = "bm:"

    static func bookmarkString(for url: URL) -> String? {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return bookmarkPrefix + data.base64EncodedString()
        } catch {
            // Fallback: plain path (still not a PDF copy).
            NSLog("[DualPDF][P0-2] bookmark failed, storing path: %@", error.localizedDescription)
            return bookmarkPrefix + "path:" + url.path
        }
    }

    private func resolveBookmark(_ stored: String, accessKey: String) -> URL? {
        if let cached = accessingURLs[accessKey], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        if let previous = accessingURLs.removeValue(forKey: accessKey) {
            previous.stopAccessingSecurityScopedResource()
        }
        guard stored.hasPrefix(Self.bookmarkPrefix) else {
            let url = URL(fileURLWithPath: stored)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let payload = String(stored.dropFirst(Self.bookmarkPrefix.count))
        if payload.hasPrefix("path:") {
            let path = String(payload.dropFirst(5))
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        guard let data = Data(base64Encoded: payload) else { return nil }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            _ = url.startAccessingSecurityScopedResource()
            accessingURLs[accessKey] = url
            if stale, let refreshed = Self.bookmarkString(for: url),
               let paperId = accessKey.split(separator: "-").first.map(String.init),
               var paper = papersByID[paperId] {
                if accessKey.hasSuffix(PDFSide.original.rawValue) {
                    paper.originalFilename = refreshed
                } else if accessKey.hasSuffix(PDFSide.translated.rawValue) {
                    paper.translatedFilename = refreshed
                }
                _ = persist(paper)
            }
            return url
        } catch {
            NSLog("[DualPDF][P0-2] resolve bookmark failed: %@", error.localizedDescription)
            return nil
        }
    }

    enum PromoteError: LocalizedError {
        case missing
        case unreadable
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .missing: return "找不到临时文档。"
            case .unreadable: return "无法读取原始 PDF（文件可能已被移动或删除）。"
            case .writeFailed(let msg): return msg
            }
        }
    }
}
