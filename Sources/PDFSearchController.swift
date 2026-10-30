import PDFKit

/// Uses PDFKit's asynchronous search, cancelling obsolete queries as the user types.
final class PDFSearchController {
    typealias Match = (col: CleanPDFColumnView, selection: PDFSelection)

    private final class Session: NSObject, PDFDocumentDelegate {
        weak var column: CleanPDFColumnView?
        let document: PDFDocument
        var matches: [PDFSelection] = []
        var isFinished = false
        var isCancelled = false
        var onFinish: (() -> Void)?

        init(column: CleanPDFColumnView, document: PDFDocument) {
            self.column = column
            self.document = document
        }

        func didMatchString(_ instance: PDFSelection) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isCancelled else { return }
                instance.color = .systemYellow
                self.matches.append(instance)
            }
        }

        func documentDidEndDocumentFind(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isCancelled else { return }
                self.isFinished = true
                self.onFinish?()
            }
        }

        func cancel() {
            isCancelled = true
            if document.delegate === self { document.delegate = nil }
            document.cancelFindString()
            onFinish = nil
        }
    }

    private var sessions: [Session] = []

    func cancel() {
        sessions.forEach { $0.cancel() }
        sessions.removeAll()
    }

    func search(_ query: String, columns: [CleanPDFColumnView], completion: @escaping ([Match]) -> Void) {
        cancel()
        sessions = columns.compactMap { column in
            column.pdfView.document.map { Session(column: column, document: $0) }
        }
        guard !sessions.isEmpty else { completion([]); return }
        for session in sessions {
            session.onFinish = { [weak self] in
                guard let self = self, self.sessions.allSatisfy(\.isFinished) else { return }
                let matches: [Match] = self.sessions.flatMap { session -> [Match] in
                    guard let column = session.column else { return [] }
                    column.pdfView.highlightedSelections = session.matches
                    return session.matches.map { (col: column, selection: $0) }
                }
                self.sessions.forEach { if $0.document.delegate === $0 { $0.document.delegate = nil } }
                self.sessions.removeAll()
                completion(matches)
            }
            session.document.delegate = session
        }
        for session in sessions { session.document.beginFindString(query, withOptions: .caseInsensitive) }
    }
}
