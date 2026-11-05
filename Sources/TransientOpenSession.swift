import Foundation
import PDFKit

/// In-memory-only open of an unlocked PDF. Never writes plaintext to disk.
final class TransientOpenSession {
    let id: String
    let sourceURL: URL
    let document: PDFDocument
    let title: String

    init(sourceURL: URL, document: PDFDocument) {
        self.id = "transient-\(UUID().uuidString)"
        self.sourceURL = sourceURL
        self.document = document
        self.title = sourceURL.deletingPathExtension().lastPathComponent
    }

    /// Synthetic paper used only to satisfy the reader UI; never persisted.
    func makeSyntheticPaper() -> PaperItem {
        PaperItem(
            id: id,
            title: title,
            authors: "",
            year: "",
            venue: "",
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
            lastOpenedAt: Date()
        )
    }
}
