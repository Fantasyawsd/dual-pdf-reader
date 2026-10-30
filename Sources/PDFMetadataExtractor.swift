import Foundation
import PDFKit

enum PDFMetadataExtractor {
    /// 极速秒级扫描 PDF 首页文本与页眉中的 arXiv ID
    static func fastScanArxivId(from pdfURL: URL) -> String? {
        let rawFilename = pdfURL.deletingPathExtension().lastPathComponent
        if let fromName = ArxivMetadataService.normalizeArxivId(rawFilename) {
            return fromName
        }
        guard let doc = PDFDocument(url: pdfURL), let firstPage = doc.page(at: 0) else { return nil }
        guard let text = firstPage.string else { return nil }
        let headPrefix = String(text.prefix(2500))
        if let match = headPrefix.range(of: "(?i)arxiv:\\s*([0-9]{4}\\.[0-9]{4,5}(?:v[0-9]+)?)", options: .regularExpression) {
            let sub = String(headPrefix[match])
            return ArxivMetadataService.normalizeArxivId(sub)
        }
        if let match = headPrefix.range(of: "(?i)arxiv.org/(?:abs|pdf)/([0-9]{4}\\.[0-9]{4,5}(?:v[0-9]+)?)", options: .regularExpression) {
            let sub = String(headPrefix[match])
            return ArxivMetadataService.normalizeArxivId(sub)
        }
        return nil
    }

    /// 从 PDF 文件自动提取标题、作者、年份与 arXiv ID 启发式元数据
    static func extractMetadata(from pdfURL: URL) -> (title: String, authors: String, year: String, arxivId: String?) {
        let rawFilename = pdfURL.deletingPathExtension().lastPathComponent
        let parentDirName = pdfURL.deletingLastPathComponent().lastPathComponent
        let cleanedFilename = rawFilename
            .replacingOccurrences(of: "(?i)[_\\-\\s]*(zh|cn|translated|trans|chs|中文版|中文|译文)$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var detectedTitle = cleanedFilename.isEmpty ? rawFilename : cleanedFilename
        var detectedAuthors = ""
        var detectedYear = String(Calendar.current.component(.year, from: Date()))
        let detectedArxivId = fastScanArxivId(from: pdfURL)
        var foundExplicitYear = false

        func parseYearOrArxiv(from text: String) -> String? {
            if let arxivRange = text.range(of: "(?:^|[^0-9])(\\d{2})(0[1-9]|1[0-2])[._]\\d{4,5}", options: .regularExpression) {
                let sub = String(text[arxivRange])
                let digits = sub.filter { $0.isNumber }
                if digits.count >= 6, let yy = Int(digits.prefix(2)), yy >= 7 && yy <= 35 {
                    return String(format: "20%02d", yy)
                }
            }
            if let yearRange = text.range(of: "(19[89]\\d|20[0-3]\\d)", options: .regularExpression) {
                return String(text[yearRange])
            }
            return nil
        }

        if let y = parseYearOrArxiv(from: cleanedFilename) ?? parseYearOrArxiv(from: parentDirName) {
            detectedYear = y
            foundExplicitYear = true
        }

        if let doc = PDFDocument(url: pdfURL) {
            if let attrs = doc.documentAttributes {
                if let attrTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String {
                    let trimmed = attrTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 4,
                       !trimmed.lowercased().hasPrefix("untitled"),
                       !trimmed.lowercased().hasSuffix(".pdf"),
                       !trimmed.lowercased().hasSuffix(".tex"),
                       !trimmed.lowercased().contains("arxiv:") {
                        detectedTitle = trimmed
                    }
                }
                if let attrAuthor = attrs[PDFDocumentAttribute.authorAttribute] as? String {
                    let trimmed = attrAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        detectedAuthors = trimmed
                    }
                }
                if !foundExplicitYear,
                   let creationDate = (attrs[PDFDocumentAttribute.creationDateAttribute] as? Date)
                    ?? (attrs[PDFDocumentAttribute.modificationDateAttribute] as? Date) {
                    let y = Calendar.current.component(.year, from: creationDate)
                    if y >= 1990 && y <= 2035 {
                        detectedYear = String(y)
                    }
                }
            }

            if let firstPageText = doc.page(at: 0)?.string {
                if !foundExplicitYear, let y = parseYearOrArxiv(from: String(firstPageText.prefix(600))) {
                    detectedYear = y
                }

                let rawLines = firstPageText
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                let candidateLines = rawLines.filter { line in
                    guard line.count >= 3 && line.count <= 140 else { return false }
                    return !isBoilerplateHeaderLine(line)
                }

                let isPlaceholderFilename = (detectedTitle == cleanedFilename)
                    || detectedTitle == "original"
                    || detectedTitle == "translated_zh"
                    || detectedTitle.range(of: "^[0-9._\\-vV]+$", options: .regularExpression) != nil

                if isPlaceholderFilename,
                   let titleIdx = candidateLines.firstIndex(where: { $0.count >= 4 }) {
                    detectedTitle = candidateLines[titleIdx]
                    if detectedAuthors.isEmpty {
                        detectedAuthors = extractAuthors(from: candidateLines, afterTitleIndex: titleIdx)
                    }
                } else if detectedAuthors.isEmpty,
                          let titleIdx = candidateLines.firstIndex(of: detectedTitle) {
                    detectedAuthors = extractAuthors(from: candidateLines, afterTitleIndex: titleIdx)
                }
            }
        }
        return (detectedTitle, detectedAuthors, detectedYear, detectedArxivId)
    }

    static func isBoilerplateHeaderLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("arxiv:") || lower.hasPrefix("page ") || lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
            return true
        }
        if line.contains("🐳") || lower.contains("hjfy.top") {
            return true
        }
        let boilerplatePhrases = [
            "proper attribution is provided",
            "hereby grants permission",
            "reproduce the tables and figures",
            "solely for use in journalistic",
            "scholarly works.",
            "published as a conference paper",
            "under review as a conference paper",
            "preprint. under review",
            "all rights reserved",
            "proceedings of the",
            "只要提供适当的署名",
            "谷歌在此授予许可",
            "复制本文中的表格和图表"
        ]
        for phrase in boilerplatePhrases where lower.contains(phrase) {
            return true
        }
        return false
    }

    private static func extractAuthors(from lines: [String], afterTitleIndex titleIdx: Int) -> String {
        guard titleIdx + 1 < lines.count else { return "" }
        let maxIdx = min(lines.count, titleIdx + 26)
        var collected: [String] = []

        let affiliationKeywords = [
            "university", "institute", "department", "research", "google brain", "google",
            "laboratory", "college", "school of", "academy", "faculty", "center for",
            "centre for", "corp", "inc.", "limited", "hospital", "stanford", "berkeley",
            "toronto", "tsinghua", "peking", "大学", "学院", "研究院", "研究所", "实验室", "中心"
        ]

        for idx in (titleIdx + 1)..<maxIdx {
            let line = lines[idx]
            let lower = line.lowercased()

            // Stop at Abstract or Section 1
            if lower == "abstract" || lower.hasPrefix("abstract ") || lower.hasPrefix("abstract—") || lower.hasPrefix("abstract:")
                || line.hasPrefix("摘要") || lower.hasPrefix("1 introduction") || lower.hasPrefix("1. introduction")
                || line.hasPrefix("1 引言") || lower.hasPrefix("keywords") || line.hasPrefix("关键词") {
                break
            }
            if line.count > 110 {
                break
            }
            // Skip emails, URLs, and pure numbers
            if lower.contains("@") || lower.hasPrefix("http") || lower.hasPrefix("www.") {
                continue
            }
            // Skip affiliation lines unless they clearly contain a single org author like "DeepSeek-AI"
            if affiliationKeywords.contains(where: { lower.contains($0) }) {
                continue
            }

            let cleaned = line
                .replacingOccurrences(of: "[∗*†‡§¶¹²³⁴⁵⁶⁷⁸⁹⁰]+", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;·")))

            guard cleaned.count >= 2 && cleaned.count <= 85 else { continue }
            if !collected.contains(cleaned) {
                collected.append(cleaned)
            }
            // If the first author line already contains multiple comma/and-separated authors, one line is enough
            if cleaned.contains(",") || cleaned.contains(" and ") || cleaned.contains("、") {
                if collected.count >= 1 { break }
            }
            if collected.count >= 8 {
                break
            }
        }

        return collected.joined(separator: ", ")
    }

    /// 智能识别 1 个或 2 个 PDF 文件中的英文原版与中文译版（词边界匹配 + 前 3 页 CJK 字符密度对比）
    static func classifyPDFPair(_ urls: [URL]) -> (original: URL?, translated: URL?) {
        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return (nil, nil) }

        func hasExplicitChineseFilename(_ url: URL) -> Bool {
            let name = url.deletingPathExtension().lastPathComponent
            if name.range(of: "[\\u4e00-\\u9fa5]", options: .regularExpression) != nil {
                return true
            }
            return name.range(
                of: "(?i)(^|[_\\-\\s\\.])(zh|cn|chs|cht|translated|translation)([_\\-\\s\\.]|$)",
                options: .regularExpression
            ) != nil
        }

        func hasExplicitEnglishFilename(_ url: URL) -> Bool {
            let name = url.deletingPathExtension().lastPathComponent
            return name.range(
                of: "(?i)(^|[_\\-\\s\\.])(en|eng|orig|original)([_\\-\\s\\.]|$)",
                options: .regularExpression
            ) != nil
        }

        func cjkCharacterCount(in url: URL) -> Int {
            guard let doc = PDFDocument(url: url) else { return 0 }
            let pagesToScan = min(doc.pageCount, 3)
            var totalCJK = 0
            for i in 0..<pagesToScan {
                if let pageText = doc.page(at: i)?.string {
                    let sample = String(pageText.prefix(1500))
                    totalCJK += sample.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
                }
            }
            return totalCJK
        }

        if pdfURLs.count == 1 {
            let only = pdfURLs[0]
            if hasExplicitEnglishFilename(only) {
                return (only, nil)
            }
            if hasExplicitChineseFilename(only) || cjkCharacterCount(in: only) > 35 {
                return (nil, only)
            }
            return (only, nil)
        } else {
            let first = pdfURLs[0]
            let second = pdfURLs[1]
            let firstZHName = hasExplicitChineseFilename(first)
            let secondZHName = hasExplicitChineseFilename(second)
            let firstENName = hasExplicitEnglishFilename(first)
            let secondENName = hasExplicitEnglishFilename(second)

            if secondZHName && !firstZHName {
                return (first, second)
            }
            if firstZHName && !secondZHName {
                return (second, first)
            }
            if firstENName && !secondENName {
                return (first, second)
            }
            if secondENName && !firstENName {
                return (second, first)
            }

            let cjkFirst = cjkCharacterCount(in: first)
            let cjkSecond = cjkCharacterCount(in: second)
            if cjkSecond > cjkFirst + 15 {
                return (first, second)
            } else if cjkFirst > cjkSecond + 15 {
                return (second, first)
            }
            return (first, second)
        }
    }

}
