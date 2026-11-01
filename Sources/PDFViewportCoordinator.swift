import Cocoa
import PDFKit

/// Owns viewport transactions. Layout, document loading and user navigation all use
/// the same gate so PDFKit notifications cannot turn a restore into another input.
final class PDFViewportCoordinator {
    enum Phase { case ready, loading, layout, restoring, closed }

    private(set) var phase: Phase = .ready
    private(set) var revision = 0
    private var updateDepth = 0
    private var completion: DispatchWorkItem?
    private var observedBounds: [String: NSRect] = [:]
    private var restoredBounds: [String: NSRect] = [:]
    private var history: [String: [String: PDFColumnReadingState]] = [:]
    private struct DocumentPair: Hashable {
        let left: String
        let right: String
    }
    private var alignments: [DocumentPair: Double] = [:]
    var states: [String: PDFColumnReadingState] = [:]
    var isActive = true
    var layoutViews: (() -> Void)?
    var didFinishLayout: (() -> Void)?
    var isTrackingGeometry: (() -> Bool)?
    private var columns: [CleanPDFColumnView]

    init(columns: [CleanPDFColumnView]) { self.columns = columns }

    private var documentPair: DocumentPair? {
        guard columns.count == 2 else { return nil }
        return DocumentPair(left: columns[0].activePDFDocumentId, right: columns[1].activePDFDocumentId)
    }

    var alignmentOffset: Double { documentPair.flatMap { alignments[$0] } ?? 0 }

    var savedAlignments: [PDFSyncAlignment] {
        alignments.map { PDFSyncAlignment(leftPDFId: $0.key.left, rightPDFId: $0.key.right, pageOffset: $0.value) }
            .sorted { ($0.leftPDFId, $0.rightPDFId) < ($1.leftPDFId, $1.rightPDFId) }
    }

    func restoreAlignments(_ saved: [PDFSyncAlignment], legacyOffset: Double) {
        alignments.removeAll()
        for item in saved where item.pageOffset.isFinite {
            alignments[DocumentPair(left: item.leftPDFId, right: item.rightPDFId)] = item.pageOffset
        }
        if let pair = documentPair, alignments[pair] == nil { setAlignment(legacyOffset) }
    }

    func setAlignment(_ offset: Double) {
        guard offset.isFinite, let pair = documentPair else { return }
        alignments[pair] = offset
    }

    var isChangingLayout: Bool { phase == .layout || phase == .restoring }
    var acceptsEvents: Bool { phase == .ready && updateDepth == 0 && isActive }
    func performUpdate(_ body: () -> Void) {
        updateDepth += 1
        defer { updateDepth -= 1 }
        body()
    }

    func capture(_ column: CleanPDFColumnView) {
        guard isActive, !column.isHiddenOrHasHiddenAncestor,
              var state = PDFScrollSynchronizer.capture(in: column) else { return }
        let slot = column.side.rawValue
        let bounds = column.internalScrollView()?.contentView.bounds
        if let restored = restoredBounds[slot], let bounds = bounds, sameBounds(restored, bounds),
           let desired = states[slot], desired.pdfDocumentId == state.pdfDocumentId {
            // A resized viewport can clamp against a page/document edge. Keep
            // the requested anchor so expanding it again does not accumulate drift.
            state.continuousPage = desired.continuousPage
            state.horizontalScrollFraction = desired.horizontalScrollFraction
        } else {
            restoredBounds[slot] = nil
        }
        states[slot] = state
        history[slot, default: [:]][state.pdfDocumentId] = state
        observedBounds[slot] = bounds
    }

    func captureVisible() { columns.forEach(capture) }

    /// A column keeps separate positions when switching among the paper's PDFs.
    func selectDocument(_ id: String, in column: CleanPDFColumnView, initialPage: Double = 0) {
        let slot = column.side.rawValue
        if let previous = states[slot] { history[slot, default: [:]][previous.pdfDocumentId] = previous }
        if states[slot]?.pdfDocumentId != id {
            states[slot] = history[slot]?[id] ?? PDFColumnReadingState(pdfDocumentId: id, continuousPage: initialPage)
        }
        observedBounds[slot] = nil
        restoredBounds[slot] = nil
    }

    func beginLayout(capture: Bool = true) {
        guard phase == .ready else { return }
        if capture { captureVisible() }
        phase = .layout
        invalidateCompletion()
    }

    func beginLoading() {
        guard phase != .closed else { return }
        if phase == .ready { captureVisible() }
        invalidateCompletion()
        phase = .loading
    }

    func documentsInstalled() {
        guard phase == .loading else { return }
        phase = .layout
        scheduleCompletion()
    }

    /// Returns true only for a changed scroll origin at a stable viewport size.
    /// Delayed bounds echoes from restoration are consumed without synchronizing.
    func receivedScroll(in column: CleanPDFColumnView) -> Bool {
        guard acceptsEvents, !column.isHiddenOrHasHiddenAncestor,
              let bounds = column.internalScrollView()?.contentView.bounds else { return false }
        let old = observedBounds[column.side.rawValue]
        observedBounds[column.side.rawValue] = bounds
        if let old = old, abs(old.width - bounds.width) > 0.001 || abs(old.height - bounds.height) > 0.001 {
            // PDFKit expresses zoom by changing the clip view's bounds size.
            // Root/split geometry hooks bracket resizing; scale notifications
            // adopt native zoom. Neither should be mistaken for a scroll input.
            return false
        }
        guard let old = old else { return true }
        return abs(old.minX - bounds.minX) > 0.000_001 || abs(old.minY - bounds.minY) > 0.000_001
    }

    func setZoom(in column: CleanPDFColumnView, autoScales: Bool, scaleFactor: CGFloat? = nil) {
        let slot = column.side.rawValue
        guard var state = states[slot], state.pdfDocumentId == column.activePDFDocumentId else { return }
        state.autoScales = autoScales
        if let scale = scaleFactor, scale.isFinite { state.scaleFactor = Double(min(5, max(0.25, scale))) }
        states[slot] = state
    }

    func restore() {
        guard phase == .layout else { return }
        phase = .restoring
        defer { phase = .layout }
        performUpdate {
            layoutViews?()
            for column in columns where !column.isHidden && column.pdfView.bounds.width > 0 {
                guard let state = states[column.side.rawValue], state.pdfDocumentId == column.activePDFDocumentId else { continue }
                if PDFScrollSynchronizer.restore(state, in: column) {
                    restoredBounds[column.side.rawValue] = column.internalScrollView()?.contentView.bounds
                }
            }
        }
    }

    func scheduleCompletion() {
        guard phase == .layout, isTrackingGeometry?() != true else { return }
        invalidateCompletion()
        let ticket = revision
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.phase == .layout, self.revision == ticket else { return }
            self.restore()
            // Let PDFKit's document layout settle while keeping notification input gated.
            let final = DispatchWorkItem { [weak self] in
                guard let self = self, self.phase == .layout, self.revision == ticket else { return }
                self.finishLayout()
            }
            self.completion = final
            DispatchQueue.main.async(execute: final)
        }
        completion = work
        DispatchQueue.main.async(execute: work)
    }

    func finishLayout() {
        guard phase == .layout, isTrackingGeometry?() != true else { return }
        invalidateCompletion()
        restore()
        phase = .ready
        captureVisible()
        didFinishLayout?()
    }

    func close() {
        invalidateCompletion()
        phase = .closed
        layoutViews = nil
        didFinishLayout = nil
        isTrackingGeometry = nil
        columns.removeAll()
    }

    private func invalidateCompletion() {
        completion?.cancel()
        completion = nil
        revision &+= 1
    }

    private func sameBounds(_ left: NSRect, _ right: NSRect) -> Bool {
        abs(left.minX - right.minX) < 0.000_001 && abs(left.minY - right.minY) < 0.000_001 &&
            abs(left.width - right.width) < 0.001 && abs(left.height - right.height) < 0.001
    }

    deinit { completion?.cancel() }
}
