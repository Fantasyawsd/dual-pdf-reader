import Foundation

enum MarkdownNotesExporter {
    static func render(_ paper: PaperItem) -> String {
        var md = "# \(paper.title)\n\n"
        md += "- **作者**: \(paper.authors.isEmpty ? "未知" : paper.authors)\n"
        md += "- **年份 / 会议**: \(paper.year) · \(paper.venue)\n"
        md += "- **分类**: \(paper.category)\n"
        if !paper.tags.isEmpty {
            md += "- **标签**: \(paper.tags.map { "`#\($0)`" }.joined(separator: " "))\n"
        }
        md += "\n---\n\n"

        if !paper.resources.isEmpty {
            md += "## 🔗 相关文件与外部链接\n\n"
            for res in paper.resources {
                md += "- [\(res.title)](\(res.urlOrPath))\n"
            }
            md += "\n"
        }

        let noteDocs = (paper.noteDocuments ?? []).filter { !$0.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !noteDocs.isEmpty {
            md += "## 📓 论文精读笔记文档 (\(noteDocs.count) 篇)\n\n"
            for doc in noteDocs {
                md += "### 📄 \(doc.title)\n\n"
                md += "\(doc.markdownContent.trimmingCharacters(in: .whitespacesAndNewlines))\n\n---\n\n"
            }
        }

        md += "## 📝 高亮摘录与精读笔记 (\(paper.annotations.count) 条)\n\n"
        let sorted = paper.annotations.sorted {
            if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
            return $0.createdAt < $1.createdAt
        }
        for ann in sorted {
            md += "### \(ann.color.emoji) [\(ann.shortSourceBadge(in: paper)) · 第 \(ann.pageIndex + 1) 页]\n\n"
            md += "> \(ann.displayText.replacingOccurrences(of: "\n", with: " "))\n\n"
            if !ann.markdownNote.isEmpty {
                md += "\(ann.markdownNote)\n\n"
            }
            if let link = ann.linkedURL {
                md += "- 🔗 关联链接: [\(ann.linkedTitle ?? link)](\(link))\n\n"
            }
            md += "---\n\n"
        }

        return md
    }
}
