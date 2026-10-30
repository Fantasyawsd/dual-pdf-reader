import Foundation

struct ArxivPaperMetadata {
    let arxivId: String
    let title: String
    let authors: String
    let year: String
    let venue: String
    let citationCount: Int?
    let pdfURL: URL?
    let summary: String?
}

enum ArxivMetadataService {
    /// 规范化清洗 arXiv ID（例如将 "arXiv:1706.03762v7" 或链接转化为 "1706.03762v7"）
    static func normalizeArxivId(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // 匹配 URL 或纯 ID 中的 arXiv 标识
        if let match = trimmed.range(of: "([0-9]{4}\\.[0-9]{4,5}(?:v[0-9]+)?)", options: .regularExpression) {
            return String(trimmed[match])
        }
        // 匹配旧版形如 hep-th/9901001 的格式
        if let match = trimmed.range(of: "([a-zA-Z\\-]+/[0-9]{7}(?:v[0-9]+)?)", options: .regularExpression) {
            return String(trimmed[match])
        }
        return nil
    }

    /// 联网获取指定 arXiv ID 的论文元数据与引用数
    static func fetchMetadata(arxivId: String, completion: @escaping (ArxivPaperMetadata?) -> Void) {
        guard let cleanId = normalizeArxivId(arxivId) else {
            completion(nil)
            return
        }

        // 优先使用 Semantic Scholar Graph API 获取引用数与标准化元数据
        let semScholarURLStr = "https://api.semanticscholar.org/graph/v1/paper/ARXIV:\(cleanId)?fields=title,authors,year,citationCount,venue"
        if let url = URL(string: semScholarURLStr) {
            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
            request.setValue("DualPDFReader/2.0", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { data, resp, err in
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String, !title.isEmpty {
                    let yearInt = (json["year"] as? Int) ?? Calendar.current.component(.year, from: Date())
                    let citations = json["citationCount"] as? Int
                    let venue = (json["venue"] as? String) ?? "arXiv"

                    var authorsStr = ""
                    if let authArr = json["authors"] as? [[String: Any]] {
                        let names = authArr.compactMap { $0["name"] as? String }
                        authorsStr = names.joined(separator: ", ")
                    }

                    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let pdfURL = URL(string: "https://arxiv.org/pdf/\(cleanId).pdf")
                    let meta = ArxivPaperMetadata(
                        arxivId: cleanId,
                        title: cleanTitle,
                        authors: authorsStr,
                        year: String(yearInt),
                        venue: venue.isEmpty ? "arXiv" : venue,
                        citationCount: citations,
                        pdfURL: pdfURL,
                        summary: nil
                    )
                    DispatchQueue.main.async { completion(meta) }
                    return
                }

                // Fallback: 官方 arXiv Atom API
                fetchFromArxivOfficialAPI(cleanId: cleanId, completion: completion)
            }.resume()
        } else {
            fetchFromArxivOfficialAPI(cleanId: cleanId, completion: completion)
        }
    }

    private static func fetchFromArxivOfficialAPI(cleanId: String, completion: @escaping (ArxivPaperMetadata?) -> Void) {
        let rawId = cleanId.replacingOccurrences(of: "v[0-9]+$", with: "", options: .regularExpression)
        guard let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(rawId)") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 8.0)
        request.setValue("DualPDFReader/2.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 基础正则解析 Atom XML 中的 title, published, authors
            guard let entryRange = xml.range(of: "<entry>[\\s\\S]*?</entry>", options: .regularExpression) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let entry = String(xml[entryRange])
            var title = ""
            if let tRange = entry.range(of: "<title>([\\s\\S]*?)</title>", options: .regularExpression) {
                let rawT = String(entry[tRange])
                    .replacingOccurrences(of: "<title>", with: "")
                    .replacingOccurrences(of: "</title>", with: "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                title = rawT
            }

            var year = String(Calendar.current.component(.year, from: Date()))
            if let pRange = entry.range(of: "<published>([0-9]{4})", options: .regularExpression) {
                let match = String(entry[pRange])
                year = String(match.suffix(4))
            }

            var authors: [String] = []
            let authorRegex = try? NSRegularExpression(pattern: "<name>(.*?)</name>")
            if let matches = authorRegex?.matches(in: entry, range: NSRange(entry.startIndex..., in: entry)) {
                for m in matches {
                    if let r = Range(m.range(at: 1), in: entry) {
                        authors.append(String(entry[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }

            if title.isEmpty {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let meta = ArxivPaperMetadata(
                arxivId: cleanId,
                title: title,
                authors: authors.joined(separator: ", "),
                year: year,
                venue: "arXiv",
                citationCount: nil,
                pdfURL: URL(string: "https://arxiv.org/pdf/\(cleanId).pdf"),
                summary: nil
            )
            DispatchQueue.main.async { completion(meta) }
        }.resume()
    }

    /// 下载 arXiv 官方 PDF 到本地目标路径
    static func downloadArxivPDF(arxivId: String, to destinationURL: URL, completion: @escaping (Bool) -> Void) {
        guard let cleanId = normalizeArxivId(arxivId),
              let url = URL(string: "https://arxiv.org/pdf/\(cleanId).pdf") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.setValue("DualPDFReader/2.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: request) { tempURL, resp, err in
            guard let tempURL = tempURL, err == nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                DispatchQueue.main.async { completion(true) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
}
