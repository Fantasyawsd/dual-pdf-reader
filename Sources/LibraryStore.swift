import Cocoa
import PDFKit

/// Main-thread owner of library state. Disk work and PDF rendering have separate services.
final class LibraryStore {
    static let libraryDidChangeNotification = Notification.Name("LibraryStoreDidChangeNotification")
    static let pdfSummaryDidChangeNotification = Notification.Name("LibraryStorePDFSummaryDidChange")
    static let shared: LibraryStore = {
        let store = LibraryStore(rootDirectory: defaultLibraryRoot(), seedIfEmpty: true) { message in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "文献库操作未完成"
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        return store
    }()

    private(set) var rootDirectory: URL
    private(set) var papers: [PaperItem] = []
    private var papersByID: [String: PaperItem] = [:]
    private var pendingReadingUpdates: [String: PaperItem] = [:]
    private var readingSaveTask: DispatchWorkItem?
    private let summaryCache = PDFSummaryCache()
    private let errorHandler: ((String) -> Void)?
    private var storage: LibraryFileStorage { LibraryFileStorage(rootDirectory: rootDirectory) }

    init(rootDirectory: URL, seedIfEmpty: Bool = false, errorHandler: ((String) -> Void)? = nil) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.errorHandler = errorHandler
        do {
            try FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
            reloadAllPapers()
            if seedIfEmpty && papers.isEmpty && isLibraryEmpty {
                seedDefaultSampleLibrary()
            }
        } catch { report(error) }
        summaryCache.onSummaryReady = { [weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: Self.pdfSummaryDidChangeNotification, object: self)
        }
    }

    private static func defaultLibraryRoot() -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let path = UserDefaults.standard.string(forKey: "DualPDF_LibraryRootPath") {
            candidates.append(URL(fileURLWithPath: path))
        }
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("PaperLibrary"))
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("PaperLibrary"))
        if let existing = candidates.first(where: {
            var directory: ObjCBool = false
            return fm.fileExists(atPath: $0.path, isDirectory: &directory) && directory.boolValue
        }) { return existing }
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualPDF_PaperLibrary", isDirectory: true)
    }

    private var isLibraryEmpty: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: rootDirectory.path).filter { !$0.hasPrefix(".") }.isEmpty) == true
    }

    @discardableResult
    func switchLibraryRoot(to newURL: URL) -> Bool {
        guard flushReadingState() else { return false }
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
            let loaded = try readPapers(at: newURL)
            rootDirectory = newURL.standardizedFileURL
            replacePapers(loaded)
            summaryCache.removeAll()
            UserDefaults.standard.set(rootDirectory.path, forKey: "DualPDF_LibraryRootPath")
            notifyChange()
            return true
        } catch { report(error); return false }
    }

    func folderURL(for paperId: String) -> URL { storage.folderURL(for: paperId) }

    func pdfURL(for paper: PaperItem, side: PDFSide) -> URL? {
        let name = side == .original ? paper.originalFilename : paper.translatedFilename
        guard let name = name else { return nil }
        let url = folderURL(for: paper.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func pdfURL(for paper: PaperItem, pdfId: String) -> URL? {
        if pdfId == PDFSide.original.rawValue {
            return pdfURL(for: paper, side: .original)
        }
        if pdfId == PDFSide.translated.rawValue {
            return pdfURL(for: paper, side: .translated)
        }
        guard let extra = paper.additionalPDFs?.first(where: { $0.id == pdfId }) else { return nil }
        let url = folderURL(for: paper.id).appendingPathComponent(extra.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func markdownNotesURL(for paperId: String) -> URL {
        folderURL(for: paperId).appendingPathComponent("notes.md")
    }

    func requestPDFSummary(for url: URL) -> PDFSummary { summaryCache.summary(for: url) }
    func knownPDFSummary(for url: URL) -> PDFSummary { summaryCache.summary(for: url, loadIfNeeded: false) }
    func invalidatePDFSummaryCache(for url: URL) { summaryCache.invalidate(url) }

    func reloadAllPapers() {
        guard flushReadingState() else { return }
        do { replacePapers(try readPapers(at: rootDirectory)) }
        catch { report(error) }
    }

    private func readPapers(at root: URL) throws -> [PaperItem] {
        let folders = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [PaperItem] = []
        var errors: [String] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let metadata = folder.appendingPathComponent("meta.json")
            guard FileManager.default.fileExists(atPath: metadata.path) else { continue }
            do {
                var paper = try decoder.decode(PaperItem.self, from: Data(contentsOf: metadata))
                guard paper.id == folder.lastPathComponent else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if paper.authors.lowercased().contains("reproduce the tables and figures")
                    || paper.title.lowercased().hasPrefix("provided proper attribution")
                    || (paper.id.contains("Provided_proper_attribution") && paper.title == "Attentionis") {
                    let origURL = paper.originalFilename.map { folder.appendingPathComponent($0) }
                    let transURL = paper.translatedFilename.map { folder.appendingPathComponent($0) }
                    if let pdfURL = origURL ?? transURL, FileManager.default.fileExists(atPath: pdfURL.path) {
                        let fixed = PDFMetadataExtractor.extractMetadata(from: pdfURL)
                        if !fixed.title.isEmpty && fixed.title != "original" {
                            paper.title = fixed.title
                        }
                        if !fixed.authors.isEmpty {
                            paper.authors = fixed.authors
                        }
                        try? LibraryFileStorage(rootDirectory: root).writeMetadata(paper)
                    }
                }
                result.append(paper)
            } catch { errors.append("\(folder.lastPathComponent)：\(error.localizedDescription)") }
        }
        if !errors.isEmpty { errorHandler?("以下论文元数据无法读取，文件已保留：\n" + errors.joined(separator: "\n")) }
        return result.sorted { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
    }

    private func replacePapers(_ items: [PaperItem]) {
        papers = items
        papersByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func paper(withId id: String) -> PaperItem? { pendingReadingUpdates[id] ?? papersByID[id] }

    @discardableResult
    func savePaper(_ paper: PaperItem, notify: Bool = true) -> Bool {
        commitPapers([paper], notify: notify)
    }

    @discardableResult
    private func commitPapers(_ updated: [PaperItem], notify: Bool, extraFields: LibraryChange.Fields = []) -> Bool {
        do {
            try storage.writeMetadata(updated)
            var fields = extraFields
            for paper in updated {
                let previous = papersByID[paper.id]
                fields.formUnion(changedFields(from: previous, to: paper))
                accept(paper)
                let markdown = MarkdownNotesExporter.render(paper)
                if previous == nil || markdown != MarkdownNotesExporter.render(previous!) {
                    do { try markdown.write(to: markdownNotesURL(for: paper.id), atomically: true, encoding: .utf8) }
                    catch { errorHandler?("论文已保存，但 notes.md 导出失败：\(error.localizedDescription)") }
                }
            }
            if notify && !fields.isEmpty { publish(ids: Set(updated.map(\.id)), fields: fields) }
            return true
        } catch { report(error); return false }
    }

    private func accept(_ paper: PaperItem) {
        pendingReadingUpdates.removeValue(forKey: paper.id)
        papersByID[paper.id] = paper
        if let index = papers.firstIndex(where: { $0.id == paper.id }) { papers[index] = paper }
        else { papers.insert(paper, at: 0) }
    }

    private func changedFields(from previous: PaperItem?, to paper: PaperItem) -> LibraryChange.Fields {
        guard let old = previous else { return .all }
        var fields: LibraryChange.Fields = []
        if old.title != paper.title || old.authors != paper.authors || old.year != paper.year || old.venue != paper.venue || old.category != paper.category || old.tags != paper.tags || old.isFavorite != paper.isFavorite || old.status != paper.status || old.customSortIndex != paper.customSortIndex {
            fields.insert(.metadata)
        }
        if old.originalFilename != paper.originalFilename || old.translatedFilename != paper.translatedFilename || old.additionalPDFs != paper.additionalPDFs { fields.insert(.pdf) }
        if old.annotations != paper.annotations || old.noteDocuments != paper.noteDocuments { fields.insert(.annotations) }
        if old.resources != paper.resources || old.relatedPapers != paper.relatedPapers { fields.insert(.resources) }
        if old.lastReadPage != paper.lastReadPage || old.lastOpenedAt != paper.lastOpenedAt || old.readingPosition != paper.readingPosition { fields.insert(.reading) }
        return fields
    }

    /// Coalesce scroll events and persist metadata only; notes.md stays untouched.
    func updateReadingState(for paperId: String, _ update: (inout PaperItem) -> Void) {
        guard var paper = paper(withId: paperId) else { return }
        update(&paper)
        guard paper != self.paper(withId: paperId) else { return }
        pendingReadingUpdates[paperId] = paper
        readingSaveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.flushReadingState() }
        readingSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    @discardableResult
    func flushReadingState() -> Bool {
        readingSaveTask?.cancel()
        readingSaveTask = nil
        let updates = Array(pendingReadingUpdates.values)
        guard !updates.isEmpty else { return true }
        do {
            try storage.writeMetadata(updates)
            var fields: LibraryChange.Fields = .reading
            for paper in updates { fields.formUnion(changedFields(from: papersByID[paper.id], to: paper)) }
            for paper in updates { accept(paper) }
            publish(ids: Set(updates.map(\.id)), fields: fields)
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    func deletePaper(id: String) -> Bool {
        do {
            // Finder Trash keeps an accidental removal recoverable.
            try FileManager.default.trashItem(at: folderURL(for: id), resultingItemURL: nil)
            pendingReadingUpdates.removeValue(forKey: id)
            papers.removeAll { $0.id == id }
            papersByID.removeValue(forKey: id)
            let related = papers.compactMap { paper -> PaperItem? in
                guard paper.relatedPapers.contains(where: { $0.targetPaperId == id }) else { return nil }
                var changed = paper
                changed.relatedPapers.removeAll { $0.targetPaperId == id }
                return changed
            }
            _ = commitPapers(related, notify: false)
            publish(ids: Set([id] + related.map(\.id)), fields: [.membership, .resources])
            return true
        } catch { report(error); return false }
    }

    /// 支持拖拽或选择 1 个或 2 个 PDF 文件创建论文条目（条目名与主 PDF 名一致）
    @discardableResult
    func smartCreatePaperFromPDFs(_ urls: [URL], category: String = "默认分类") -> PaperItem? {
        guard urls.filter({ $0.pathExtension.lowercased() == "pdf" }).count <= 2 else {
            errorHandler?("一次最多选择两份 PDF，用于原文与译文对照。")
            return nil
        }
        let classified = classifyPDFPair(urls)
        guard let primaryURL = classified.original ?? classified.translated else { return nil }
        let meta = extractMetadata(from: primaryURL)
        let item = createPaper(
            title: meta.title,
            authors: meta.authors,
            year: meta.year,
            venue: "arXiv",
            category: category,
            tags: [],
            arxivId: meta.arxivId,
            citationCount: nil,
            originalSourceURL: classified.original ?? primaryURL,
            translatedSourceURL: classified.translated
        )
        // 若识别到 arXiv ID，在后台异步自动获取官方元数据与引用数并静默更新
        if let created = item, let cleanArxiv = meta.arxivId {
            refreshPaperArxivMetadata(paperId: created.id, arxivId: cleanArxiv, completion: nil)
        }
        return item
    }

    /// 通过输入 arXiv ID 自动获取元数据、下载官方 PDF 并创建条目
    func createPaperFromArxivId(arxivId: String, category: String = "默认分类", completion: @escaping (PaperItem?) -> Void) {
        guard let cleanId = ArxivMetadataService.normalizeArxivId(arxivId) else {
            completion(nil)
            return
        }
        ArxivMetadataService.fetchMetadata(arxivId: cleanId) { [weak self] meta in
            guard let self = self, let meta = meta else {
                completion(nil)
                return
            }
            // 以标题为基准生成主 PDF 文件名与条目名
            let safeTitle = meta.title
                .replacingOccurrences(of: "[^a-zA-Z0-9\\u4e00-\\u9fa5_-]", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            let finalName = safeTitle.isEmpty ? cleanId : safeTitle
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempPDF = tempDir.appendingPathComponent("\(finalName).pdf")

            ArxivMetadataService.downloadArxivPDF(arxivId: cleanId, to: tempPDF) { success in
                guard success else {
                    try? FileManager.default.removeItem(at: tempDir)
                    completion(nil)
                    return
                }
                let created = self.createPaper(
                    title: meta.title,
                    authors: meta.authors,
                    year: meta.year,
                    venue: meta.venue,
                    category: category,
                    tags: [],
                    arxivId: cleanId,
                    citationCount: meta.citationCount,
                    originalSourceURL: tempPDF,
                    translatedSourceURL: nil,
                    customItemName: finalName
                )
                try? FileManager.default.removeItem(at: tempDir)
                completion(created)
            }
        }
    }

    /// 刷新条目的 arXiv 元数据与引用数
    func refreshPaperArxivMetadata(paperId: String, arxivId: String? = nil, completion: ((Bool) -> Void)? = nil) {
        guard let item = paper(withId: paperId) else {
            completion?(false)
            return
        }
        let targetId = arxivId ?? item.cleanArxivId
        guard let cleanId = targetId, !cleanId.isEmpty else {
            completion?(false)
            return
        }
        ArxivMetadataService.fetchMetadata(arxivId: cleanId) { [weak self] freshMeta in
            guard let self = self, let freshMeta = freshMeta else {
                completion?(false)
                return
            }
            guard var current = self.paper(withId: paperId) else {
                completion?(false)
                return
            }
            if !freshMeta.title.isEmpty { current.title = freshMeta.title }
            if !freshMeta.authors.isEmpty { current.authors = freshMeta.authors }
            if !freshMeta.year.isEmpty { current.year = freshMeta.year }
            current.arxivId = freshMeta.arxivId
            if let citations = freshMeta.citationCount {
                current.citationCount = citations
            }
            self.savePaper(current, notify: true)
            completion?(true)
        }
    }

    @discardableResult
    func createPaper(
        title: String,
        authors: String = "",
        year: String = String(Calendar.current.component(.year, from: Date())),
        venue: String = "arXiv",
        category: String = "未分类",
        tags: [String] = [],
        arxivId: String? = nil,
        citationCount: Int? = nil,
        originalSourceURL: URL? = nil,
        translatedSourceURL: URL? = nil,
        customItemName: String? = nil
    ) -> PaperItem? {
        // 条目名与主 PDF 名一致
        let baseName: String
        if let custom = customItemName, !custom.isEmpty {
            baseName = custom
        } else if let origURL = originalSourceURL {
            let origName = origURL.deletingPathExtension().lastPathComponent
            let cleaned = origName
                .replacingOccurrences(of: "(?i)[_\\-\\s]*(zh|cn|translated|trans|chs|中文版|中文|译文)$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            baseName = cleaned.isEmpty ? origName : cleaned
        } else {
            let slug = title.replacingOccurrences(of: "[^a-zA-Z0-9\\u4e00-\\u9fa5_-]", with: "_", options: .regularExpression).prefix(32)
            baseName = slug.isEmpty ? "Paper_\(UUID().uuidString.prefix(6))" : String(slug)
        }

        var id = baseName
        var candidateFolder = folderURL(for: id)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidateFolder.path) {
            id = "\(baseName)_\(counter)"
            candidateFolder = folderURL(for: id)
            counter += 1
        }

        var item = PaperItem(
            id: id,
            title: title.isEmpty ? baseName : title,
            authors: authors,
            year: year,
            venue: venue,
            category: category,
            tags: tags,
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
            lastOpenedAt: nil,
            arxivId: arxivId,
            citationCount: citationCount
        )

        let folder = candidateFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let original = originalSourceURL {
                let origFileName = "\(id).pdf"
                try storage.replacePDF(from: original, at: folder.appendingPathComponent(origFileName)) {}
                item.originalFilename = origFileName
            }
            if let translated = translatedSourceURL {
                let transFileName = "\(id)_zh.pdf"
                try storage.replacePDF(from: translated, at: folder.appendingPathComponent(transFileName)) {}
                item.translatedFilename = transFileName
            }
            guard savePaper(item) else { try? FileManager.default.removeItem(at: folder); return nil }
            return item
        } catch {
            try? FileManager.default.removeItem(at: folder)
            report(error)
            return nil
        }
    }

    /// 为指定条目导入中文译本 PDF
    @discardableResult
    func importTranslatedPDF(for paperId: String, from sourceURL: URL) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        let transFileName = "\(item.id)_zh.pdf"
        let destination = folderURL(for: paperId).appendingPathComponent(transFileName)
        item.translatedFilename = transFileName
        do {
            try storage.replacePDF(from: sourceURL, at: destination) { try storage.writeMetadata(item) }
            accept(item)
            summaryCache.invalidate(destination)
            publish(ids: [paperId], fields: .pdf)
            return true
        } catch { report(error); return false }
    }

    /// 向条目导入附件文件并存放到条目 attachments/ 目录下
    @discardableResult
    func importAttachmentFile(for paperId: String, from sourceURL: URL) -> ExternalResource? {
        guard var item = paper(withId: paperId) else { return nil }
        let attachmentsDir = folderURL(for: paperId).appendingPathComponent("attachments")
        try? FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        let filename = sourceURL.lastPathComponent
        let destination = attachmentsDir.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            let res = ExternalResource(title: filename, urlOrPath: destination.path, isLocalFile: true)
            item.resources.append(res)
            savePaper(item, notify: true)
            return res
        } catch {
            report(error)
            return nil
        }
    }

    /// 删除指定条目的附加资源或文件
    @discardableResult
    func deleteExternalResource(for paperId: String, resourceId: String) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        guard let idx = item.resources.firstIndex(where: { $0.id == resourceId }) else { return false }
        let res = item.resources[idx]
        if res.isLocalFile {
            try? FileManager.default.removeItem(atPath: res.urlOrPath)
        }
        item.resources.remove(at: idx)
        return savePaper(item, notify: true)
    }

    /// 向条目添加自定义外部链接
    @discardableResult
    func addExternalLink(for paperId: String, title: String, url: String) -> ExternalResource? {
        guard var item = paper(withId: paperId) else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty else { return nil }
        let res = ExternalResource(title: cleanTitle.isEmpty ? cleanUrl : cleanTitle, urlOrPath: cleanUrl, isLocalFile: false)
        item.resources.append(res)
        if savePaper(item, notify: true) {
            return res
        }
        return nil
    }

    /// 移除条目的中文翻译版 PDF
    @discardableResult
    func removeTranslatedPDF(for paperId: String) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        if let fn = item.translatedFilename {
            let path = folderURL(for: paperId).appendingPathComponent(fn)
            try? FileManager.default.removeItem(at: path)
            summaryCache.invalidate(path)
        }
        item.translatedFilename = nil
        return savePaper(item, notify: true)
    }

    /// 为条目添加标签
    @discardableResult
    func addTag(_ tag: String, for paperId: String) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !item.tags.contains(clean) else { return false }
        item.tags.append(clean)
        return savePaper(item, notify: true)
    }

    /// 从条目中移除标签
    @discardableResult
    func removeTag(_ tag: String, for paperId: String) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        guard let idx = item.tags.firstIndex(of: tag) else { return false }
        item.tags.remove(at: idx)
        return savePaper(item, notify: true)
    }

    /// 获取整个文库中所有已使用过的独立标签集合
    var allUniqueTags: [String] {
        var set = Set<String>()
        for p in papers {
            for t in p.tags {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { set.insert(trimmed) }
            }
        }
        return set.sorted()
    }

    @discardableResult
    func importPDF(for paperId: String, side: PDFSide, from sourceURL: URL) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        let existingName = side == .original ? item.originalFilename : item.translatedFilename
        let defaultName = side == .original ? "\(item.id).pdf" : "\(item.id)_zh.pdf"
        let name = existingName ?? defaultName
        let destination = folderURL(for: paperId).appendingPathComponent(name)
        if side == .original { item.originalFilename = name } else { item.translatedFilename = name }
        do {
            try storage.replacePDF(from: sourceURL, at: destination) { try storage.writeMetadata(item) }
            accept(item)
            summaryCache.invalidate(destination)
            publish(ids: [paperId], fields: .pdf)
            return true
        } catch { report(error); return false }
    }

    /// 向当前论文（论文集）中添加新的 PDF 文档，或替换已有的附加 PDF
    @discardableResult
    func addAdditionalPDF(to paperId: String, from sourceURL: URL, title: String? = nil, replacingId: String? = nil) -> PaperPDFDocument? {
        guard var item = paper(withId: paperId) else { return nil }
        let docId = replacingId ?? UUID().uuidString
        let cleanTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? sourceURL.deletingPathExtension().lastPathComponent
        let filename = "extra_\(docId.prefix(8)).pdf"
        let destination = folderURL(for: paperId).appendingPathComponent(filename)
        var extras = item.additionalPDFs ?? []
        let pdfDoc = PaperPDFDocument(id: docId, title: cleanTitle, filename: filename, addedAt: Date())
        if let idx = extras.firstIndex(where: { $0.id == docId }) {
            extras[idx] = pdfDoc
        } else {
            extras.append(pdfDoc)
        }
        item.additionalPDFs = extras
        do {
            try storage.replacePDF(from: sourceURL, at: destination) { try storage.writeMetadata(item) }
            accept(item)
            summaryCache.invalidate(destination)
            publish(ids: [paperId], fields: .pdf)
            return pdfDoc
        } catch {
            report(error)
            return nil
        }
    }

    @discardableResult
    func removeAdditionalPDF(from paperId: String, pdfId: String) -> Bool {
        guard var item = paper(withId: paperId),
              var extras = item.additionalPDFs,
              let target = extras.first(where: { $0.id == pdfId }) else { return false }
        extras.removeAll { $0.id == pdfId }
        item.additionalPDFs = extras.isEmpty ? nil : extras
        guard savePaper(item, notify: true) else { return false }
        let fileURL = folderURL(for: paperId).appendingPathComponent(target.filename)
        try? FileManager.default.removeItem(at: fileURL)
        return true
    }

    // MARK: - Paper Note Documents Management (论文笔记与可跳转引用)
    @discardableResult
    func saveNoteDocument(for paperId: String, note: PaperNoteDocument, notify: Bool = true) -> Bool {
        guard var item = paper(withId: paperId) else { return false }
        var docs = item.effectiveNoteDocuments
        var updatedNote = note
        updatedNote.updatedAt = Date()
        if let idx = docs.firstIndex(where: { $0.id == note.id }) {
            docs[idx] = updatedNote
        } else {
            docs.append(updatedNote)
        }
        item.noteDocuments = docs
        return savePaper(item, notify: notify)
    }

    @discardableResult
    func createNoteDocument(for paperId: String, title: String, initialContent: String = "") -> PaperNoteDocument? {
        guard var item = paper(withId: paperId) else { return nil }
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
        guard var item = paper(withId: paperId) else { return false }
        var docs = item.effectiveNoteDocuments
        guard docs.count > 1 else { return false }
        docs.removeAll { $0.id == noteId }
        item.noteDocuments = docs
        return savePaper(item, notify: true)
    }

    @discardableResult
    func appendContentToNote(for paperId: String, noteId: String? = nil, markdownSnippet: String) -> PaperNoteDocument? {
        guard var item = paper(withId: paperId) else { return nil }
        var docs = item.effectiveNoteDocuments
        let targetIdx = noteId.flatMap { id in docs.firstIndex(where: { $0.id == id }) } ?? 0
        guard targetIdx >= 0 && targetIdx < docs.count else { return nil }
        var doc = docs[targetIdx]
        let existing = doc.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            doc.markdownContent = markdownSnippet
        } else {
            doc.markdownContent = doc.markdownContent + (doc.markdownContent.hasSuffix("\n\n") ? "" : (doc.markdownContent.hasSuffix("\n") ? "\n" : "\n\n")) + markdownSnippet
        }
        doc.updatedAt = Date()
        docs[targetIdx] = doc
        item.noteDocuments = docs
        guard savePaper(item, notify: true) else { return nil }
        return doc
    }

    @discardableResult
    func reorderPapers(orderedIds: [String]) -> Bool {
        var updated: [PaperItem] = []
        for (idx, pid) in orderedIds.enumerated() {
            guard var p = paper(withId: pid) else { continue }
            if p.customSortIndex != idx {
                p.customSortIndex = idx
                updated.append(p)
            }
        }
        guard !updated.isEmpty else { return true }
        return commitPapers(updated, notify: true, extraFields: .metadata)
    }

    func addLocalAttachment(to paperId: String, fileURL: URL, customTitle: String? = nil) -> ExternalResource? {
        guard var item = paper(withId: paperId) else { return nil }
        do {
            let destination = try storage.copyAttachment(from: fileURL, for: paperId)
            let resource = ExternalResource(title: customTitle ?? fileURL.lastPathComponent, urlOrPath: destination.path, isLocalFile: true)
            item.resources.append(resource)
            guard savePaper(item) else {
                try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                return nil
            }
            return resource
        } catch { report(error); return nil }
    }

    func linkRelatedPapers(paperAId: String, paperBId: String, note: String) {
        guard paperAId != paperBId, var a = paper(withId: paperAId), var b = paper(withId: paperBId) else { return }
        if !a.relatedPapers.contains(where: { $0.targetPaperId == paperBId }) { a.relatedPapers.append(RelatedPaperLink(targetPaperId: paperBId, relationNote: note)) }
        if !b.relatedPapers.contains(where: { $0.targetPaperId == paperAId }) { b.relatedPapers.append(RelatedPaperLink(targetPaperId: paperAId, relationNote: note.isEmpty ? "关联论文" : "关联：\(note)")) }
        _ = commitPapers([a, b], notify: true)
    }

    func unlinkRelatedPapers(paperAId: String, paperBId: String) {
        let updated = [(paperAId, paperBId), (paperBId, paperAId)].compactMap { id, target -> PaperItem? in
            guard var item = paper(withId: id) else { return nil }
            item.relatedPapers.removeAll { $0.targetPaperId == target }
            return item
        }
        _ = commitPapers(updated, notify: true)
    }

    func allCategories() -> [String] { Array(Set(papers.map(\.category).filter { !$0.isEmpty })).sorted() }
    func allTags() -> [String] { Array(Set(papers.flatMap(\.tags).filter { !$0.isEmpty })).sorted() }
    func extractMetadata(from url: URL) -> (title: String, authors: String, year: String, arxivId: String?) { PDFMetadataExtractor.extractMetadata(from: url) }
    func classifyPDFPair(_ urls: [URL]) -> (original: URL?, translated: URL?) { PDFMetadataExtractor.classifyPDFPair(urls) }

    func notifyChange() {
        publish(ids: [], fields: .all, resetsLibrary: true)
    }

    private func publish(ids: Set<String>, fields: LibraryChange.Fields, resetsLibrary: Bool = false) {
        let change = LibraryChange(paperIDs: ids, fields: fields, resetsLibrary: resetsLibrary)
        NotificationCenter.default.post(name: Self.libraryDidChangeNotification, object: self, userInfo: ["change": change])
    }

    private func report(_ error: Error) { errorHandler?(error.localizedDescription) }
}
