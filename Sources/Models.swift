import Cocoa

// MARK: - Core Enums
enum ReadingStatus: String, Codable, CaseIterable {
    case unread = "unread"
    case reading = "reading"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .unread: return "未读"
        case .reading: return "在读"
        case .completed: return "已精读"
        }
    }

    var symbolName: String {
        switch self {
        case .unread: return "circle.dashed"
        case .reading: return "book.pages.fill"
        case .completed: return "checkmark.seal.fill"
        }
    }

    var badgeColor: NSColor {
        switch self {
        case .unread: return .systemBlue
        case .reading: return .systemOrange
        case .completed: return .systemGreen
        }
    }
}

enum LibrarySortOrder: String, CaseIterable {
    case recentOpened = "recent"
    case dateAdded = "added"
    case yearDesc = "year"
    case titleAsc = "title"
    case authorsAsc = "authors"
    case notesCount = "notes"
    case statusOrder = "status"
    case customOrder = "custom"

    var displayName: String {
        switch self {
        case .recentOpened: return "按最近阅读"
        case .dateAdded:    return "按添加时间"
        case .yearDesc:     return "按发表年份"
        case .titleAsc:     return "按标题 A–Z"
        case .authorsAsc:   return "按作者 A–Z"
        case .notesCount:   return "按笔记数量"
        case .statusOrder:  return "按阅读状态"
        case .customOrder:  return "自定义排序"
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable {
    case yellow = "yellow"
    case green = "green"
    case blue = "blue"
    case pink = "pink"

    var displayName: String {
        switch self {
        case .yellow: return "琥珀黄"
        case .green:  return "翠竹绿"
        case .blue:   return "晴空蓝"
        case .pink:   return "珊瑚粉"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.0, alpha: 0.35)
        case .green:  return NSColor(calibratedRed: 0.37, green: 0.70, blue: 0.21, alpha: 0.35)
        case .blue:   return NSColor(calibratedRed: 0.18, green: 0.66, blue: 0.90, alpha: 0.35)
        case .pink:   return NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.40, alpha: 0.35)
        }
    }

    var solidColor: NSColor {
        switch self {
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.83, blue: 0.0, alpha: 1.0)
        case .green:  return NSColor(calibratedRed: 0.37, green: 0.70, blue: 0.21, alpha: 1.0)
        case .blue:   return NSColor(calibratedRed: 0.18, green: 0.66, blue: 0.90, alpha: 1.0)
        case .pink:   return NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.40, alpha: 1.0)
        }
    }

    var hexString: String {
        switch self {
        case .yellow: return "#F59E0B"
        case .green:  return "#10B981"
        case .blue:   return "#3B82F6"
        case .pink:   return "#EC4899"
        }
    }

    var emoji: String {
        switch self {
        case .yellow: return "🟡"
        case .green:  return "🟢"
        case .blue:   return "🔵"
        case .pink:   return "🔴"
        }
    }

    static func nearest(to color: NSColor) -> HighlightColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return .yellow }
        return allCases.min { lhs, rhs in
            let left = lhs.solidColor.usingColorSpace(.deviceRGB) ?? .yellow
            let right = rhs.solidColor.usingColorSpace(.deviceRGB) ?? .yellow
            return colorDistance(rgb, left) < colorDistance(rgb, right)
        } ?? .yellow
    }

    private static func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        pow(lhs.redComponent - rhs.redComponent, 2) +
            pow(lhs.greenComponent - rhs.greenComponent, 2) +
            pow(lhs.blueComponent - rhs.blueComponent, 2)
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let red = CGFloat((number >> (value.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((number >> (value.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((number >> (value.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = value.count == 8 ? CGFloat(number & 0xFF) / 255 : 1
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    var hexString: String {
        let color = usingColorSpace(.deviceRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }
}

enum PDFSide: String, Codable {
    case original = "original"
    case translated = "translated"

    var shortBadge: String {
        switch self {
        case .original: return "原文 EN"
        case .translated: return "译文 ZH"
        }
    }
}

// MARK: - Codable Geometry & Annotations
struct RectCodable: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct PointCodable: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

enum PaperAnnotationKind: String, Codable, CaseIterable {
    case highlight
    case underline
    case strikethrough
    case ink
    case text
    case rectangle
    case ellipse
    case line
    case arrow

    var displayName: String {
        switch self {
        case .highlight: return "高亮"
        case .underline: return "下划线"
        case .strikethrough: return "删除线"
        case .ink: return "画笔"
        case .text: return "文本"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .line: return "直线"
        case .arrow: return "箭头"
        }
    }

    var isTextMarkup: Bool {
        self == .highlight || self == .underline || self == .strikethrough
    }
}

struct PaperAnnotation: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var side: PDFSide
    var pageIndex: Int
    var rects: [RectCodable]
    var selectedText: String
    var color: HighlightColor
    var markdownNote: String
    var linkedURL: String?      // 网页 URL、本地文件 file:// 路径 或 paper://<id>
    var linkedTitle: String?    // 链接显示标题
    var createdAt: Date = Date()
    var additionalPageRegions: [AnnotationPageRegion]? = nil
    var pdfDocumentId: String? = nil // 所属本论文集内的 PDF 标识 ("original" / "translated" / 附加 PDF id)
    var kind: PaperAnnotationKind? = nil
    var colorHex: String? = nil
    var strokeWidth: Double? = nil
    var inkPaths: [[PointCodable]]? = nil
    var startPoint: PointCodable? = nil
    var endPoint: PointCodable? = nil

    var effectivePDFId: String {
        pdfDocumentId ?? side.rawValue
    }

    var effectiveKind: PaperAnnotationKind { kind ?? .highlight }

    var displayText: String {
        if !selectedText.isEmpty { return selectedText }
        return "[\(effectiveKind.displayName)]"
    }

    var displayColor: NSColor {
        colorHex.flatMap(NSColor.init(hexString:)) ?? color.nsColor
    }

    func shortSourceBadge(in paper: PaperItem? = nil) -> String {
        let pid = effectivePDFId
        if pid == PDFSide.original.rawValue { return PDFSide.original.shortBadge }
        if pid == PDFSide.translated.rawValue { return PDFSide.translated.shortBadge }
        if let custom = paper?.additionalPDFs?.first(where: { $0.id == pid }) {
            return custom.title
        }
        return side.shortBadge
    }

    var pageRegions: [AnnotationPageRegion] {
        [AnnotationPageRegion(pageIndex: pageIndex, rects: rects)] + (additionalPageRegions ?? [])
    }
}

struct AnnotationPageRegion: Codable, Equatable {
    var pageIndex: Int
    var rects: [RectCodable]
}

// MARK: - Paper Collection Documents (论文集内多 PDF 与多篇独立笔记文档)
struct PaperPDFDocument: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var filename: String
    var addedAt: Date = Date()
}

struct PaperPDFDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    let filename: String?
    let builtInSide: PDFSide?
}

struct PaperNoteDocument: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var markdownContent: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// PDF 栏仅支持当前论文的 PDF；笔记由右侧边栏管理。
enum ColumnContentSource: Equatable {
    case pdf(id: String)

    var isPDF: Bool { true }
    var pdfId: String? {
        if case .pdf(let id) = self { return id }
        return nil
    }
}

struct ExternalResource: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var urlOrPath: String
    var isLocalFile: Bool
}

struct RelatedPaperLink: Codable, Identifiable, Equatable {
    var id: String { targetPaperId }
    var targetPaperId: String
    var relationNote: String
}

// MARK: - Atomic Unit: Paper Item (以“条目”为最小单元管理本地 PDF 与笔记)
struct PaperItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var authors: String
    var year: String
    var venue: String
    var category: String
    var tags: [String]
    var isFavorite: Bool
    var status: ReadingStatus

    var originalFilename: String?
    var translatedFilename: String?

    var lastReadPage: Int
    var lastReadScrollProgress: Double
    var syncOffsetDelta: Double

    var annotations: [PaperAnnotation]
    var resources: [ExternalResource]
    var relatedPapers: [RelatedPaperLink]

    var addedAt: Date
    var lastOpenedAt: Date?

    // Academic Identification & Citations
    var arxivId: String? = nil
    var citationCount: Int? = nil
    var zoomFactor: Double? = nil

    // Optional for compatibility with existing meta.json files.
    var readingPosition: ReadingPosition? = nil
    var readerState: ReaderState? = nil
    var additionalPDFs: [PaperPDFDocument]? = nil
    var noteDocuments: [PaperNoteDocument]? = nil
    var customSortIndex: Int? = nil
    /// P0-2: temporary open that has not been saved into the library.
    var isTransient: Bool = false
    /// True when the transient document has notes/annotations worth emphasizing.
    var transientHasNotes: Bool {
        let hasAnnotNotes = annotations.contains { !$0.markdownNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.selectedText.isEmpty }
        let hasNoteDocs = (noteDocuments ?? []).contains { !$0.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasAnnotNotes || hasNoteDocs || !annotations.isEmpty
    }

    var hasBothPDFs: Bool {
        return originalFilename != nil && translatedFilename != nil
    }

    var cleanArxivId: String? {
        guard let raw = arxivId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "^arxiv:\\s*", with: "", options: [.regularExpression, .caseInsensitive])
    }

    var allPDFDescriptors: [PaperPDFDescriptor] {
        var list: [PaperPDFDescriptor] = [
            PaperPDFDescriptor(id: PDFSide.original.rawValue, title: "原文 EN", filename: originalFilename, builtInSide: .original),
            PaperPDFDescriptor(id: PDFSide.translated.rawValue, title: "译文 ZH", filename: translatedFilename, builtInSide: .translated)
        ]
        for extra in (additionalPDFs ?? []) {
            list.append(PaperPDFDescriptor(id: extra.id, title: extra.title, filename: extra.filename, builtInSide: nil))
        }
        return list
    }

    var effectiveNoteDocuments: [PaperNoteDocument] {
        if let docs = noteDocuments, !docs.isEmpty {
            return docs
        }
        return [
            PaperNoteDocument(
                id: "main",
                title: "精读主笔记",
                markdownContent: "",
                createdAt: addedAt,
                updatedAt: addedAt
            )
        ]
    }

    func pdfTitle(for pdfId: String) -> String {
        if pdfId == PDFSide.original.rawValue { return "原文 EN" }
        if pdfId == PDFSide.translated.rawValue { return "译文 ZH" }
        if let extra = additionalPDFs?.first(where: { $0.id == pdfId }) {
            return extra.title
        }
        return "论文 PDF"
    }

    /// Copy scroll / zoom / last-opened fields from another snapshot without touching annotations or notes.
    mutating func applyReadingFields(from other: PaperItem) {
        lastReadPage = other.lastReadPage
        lastReadScrollProgress = other.lastReadScrollProgress
        syncOffsetDelta = other.syncOffsetDelta
        lastOpenedAt = other.lastOpenedAt
        readingPosition = other.readingPosition
        readerState = other.readerState
        zoomFactor = other.zoomFactor
    }
}

struct ReadingPosition: Codable, Equatable {
    var side: PDFSide
    var continuousPage: Double
    var pdfDocumentId: String? = nil
}

struct PDFColumnReadingState: Codable, Equatable {
    var pdfDocumentId: String
    var continuousPage: Double
    // Persisted key retained for compatibility; true now means reader-owned width fit.
    var autoScales: Bool = true
    var scaleFactor: Double = 1
    // Legacy horizontal position; the reader now always centers pages in their pane.
    var horizontalScrollFraction: Double? = nil
}

struct PDFSyncAlignment: Codable, Equatable {
    var leftPDFId: String
    var rightPDFId: String
    var pageOffset: Double
}

/// Optional on PaperItem so metadata written by previous versions still decodes.
struct ReaderState: Codable, Equatable {
    var leftColumn: PDFColumnReadingState
    var rightColumn: PDFColumnReadingState
    var syncEnabled: Bool
    var displayMode: Int
    var swapped: Bool
    var splitRatio: Double
    var alignments: [PDFSyncAlignment]? = nil
}

// MARK: - Navigation History Entry (for Reference Jump & Back)
struct ReadingJumpRecord {
    let side: PDFSide
    let pdfDocumentId: String
    let pageIndex: Int
    let scrollOriginY: CGFloat
    let descriptionLabel: String

    init(side: PDFSide, pdfDocumentId: String? = nil, pageIndex: Int, scrollOriginY: CGFloat, descriptionLabel: String = "返回") {
        self.side = side
        self.pdfDocumentId = pdfDocumentId ?? side.rawValue
        self.pageIndex = pageIndex
        self.scrollOriginY = scrollOriginY
        self.descriptionLabel = descriptionLabel
    }
}
