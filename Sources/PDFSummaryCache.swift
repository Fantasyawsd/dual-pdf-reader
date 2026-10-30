import Cocoa
import PDFKit

struct PDFSummary {
    let pageCount: Int
    let sizeKB: Int
    let thumbnailDataURL: String?
}

/// UI access is main-thread confined; each worker owns its own PDFDocument.
final class PDFSummaryCache {
    private struct Signature: Equatable {
        let modificationDate: Date?
        let size: Int
    }
    private final class Entry {
        let signature: Signature
        let summary: PDFSummary
        init(signature: Signature, summary: PDFSummary) {
            self.signature = signature
            self.summary = summary
        }
    }

    private let cache = NSCache<NSString, Entry>()
    private let queue = OperationQueue()
    private var pending: [String: UUID] = [:]
    private var metadata: [String: (signature: Signature, pageCount: Int, sizeKB: Int)] = [:]
    var onSummaryReady: (() -> Void)?

    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 24 * 1024 * 1024
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        queue.name = "DualPDF.PDFSummaries"
    }

    func summary(for url: URL, loadIfNeeded: Bool = true) -> PDFSummary {
        let path = url.standardizedFileURL.path
        let signature = signatureForFile(url)
        if let entry = cache.object(forKey: path as NSString), entry.signature == signature {
            return entry.summary
        }
        if loadIfNeeded && pending[path] == nil {
            let requestID = UUID()
            pending[path] = requestID
            queue.addOperation { [weak self] in
                let rendered = autoreleasepool { Self.render(url, sizeKB: signature.size / 1024) }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.pending[path] == requestID else { return }
                    self.pending.removeValue(forKey: path)
                    // Discard results generated while the underlying file was replaced.
                    guard self.signatureForFile(url) == signature else {
                        self.onSummaryReady?()
                        return
                    }
                    self.cache.setObject(Entry(signature: signature, summary: rendered), forKey: path as NSString,
                                         cost: rendered.thumbnailDataURL?.utf8.count ?? 128)
                    self.metadata[path] = (signature, rendered.pageCount, rendered.sizeKB)
                    self.onSummaryReady?()
                }
            }
        }
        let pages = metadata[path].flatMap { $0.signature == signature ? $0.pageCount : nil } ?? 0
        return PDFSummary(pageCount: pages, sizeKB: signature.size / 1024, thumbnailDataURL: nil)
    }

    func invalidate(_ url: URL) {
        let path = url.standardizedFileURL.path
        cache.removeObject(forKey: path as NSString)
        pending.removeValue(forKey: path)
        metadata.removeValue(forKey: path)
    }

    func removeAll() {
        pending.removeAll()
        metadata.removeAll()
        queue.cancelAllOperations()
        cache.removeAllObjects()
    }

    private func signatureForFile(_ url: URL) -> Signature {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return Signature(modificationDate: attributes?[.modificationDate] as? Date,
                         size: attributes?[.size] as? Int ?? 0)
    }

    static func render(_ url: URL, sizeKB: Int = 0) -> PDFSummary {
        guard let document = PDFDocument(url: url) else {
            return PDFSummary(pageCount: 0, sizeKB: sizeKB, thumbnailDataURL: nil)
        }
        var dataURL: String?
        if let image = document.page(at: 0)?.thumbnail(of: NSSize(width: 160, height: 224), for: .mediaBox),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            dataURL = "data:image/png;base64," + png.base64EncodedString()
        }
        return PDFSummary(pageCount: document.pageCount, sizeKB: sizeKB, thumbnailDataURL: dataURL)
    }
}
