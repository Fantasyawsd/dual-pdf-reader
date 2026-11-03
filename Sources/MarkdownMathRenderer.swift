import Cocoa
import WebKit

enum MarkdownMathRenderer {
    struct NoteDTO: Codable {
        let id: String
        let paperId: String
        let paperTitle: String?
        let sideBadge: String
        let sideRaw: String
        let pageNumber: Int
        let colorHex: String
        let selectedText: String
        let markdownNote: String
        let linkedURL: String?
        let linkedTitle: String?
    }

    /// 将单篇论文的笔记列表渲染为自包含 HTML（内置离线 LaTeX 数学公式排版 + Markdown 渲染）
    static func buildNotesFeedHTML(
        paper: PaperItem,
        annotations: [PaperAnnotation],
        interactive: Bool = true
    ) -> String {
        let dtos: [NoteDTO] = annotations
            .sorted {
                if $0.pageIndex != $1.pageIndex { return $0.pageIndex < $1.pageIndex }
                return $0.createdAt < $1.createdAt
            }
            .map { ann in
                NoteDTO(
                    id: ann.id,
                    paperId: paper.id,
                    paperTitle: nil,
                    sideBadge: ann.shortSourceBadge(in: paper),
                    sideRaw: ann.effectivePDFId,
                    pageNumber: ann.pageIndex + 1,
                    colorHex: ann.colorHex ?? ann.color.hexString,
                    selectedText: ann.displayText,
                    markdownNote: ann.markdownNote,
                    linkedURL: ann.linkedURL,
                    linkedTitle: ann.linkedTitle
                )
            }
        return renderFeedHTML(dtos: dtos, emptyHint: "暂无高亮或笔记<br><br>在阅读器中用鼠标<b>划选任意文字</b>，即可在弹出的浮动工具条中添加多色高亮、编写支持 <b>LaTeX 公式</b> 的 Markdown 笔记，或挂接网页与本地文件。")
    }

    /// 用于笔记编辑器与高亮气泡的实时单条 Markdown + LaTeX 预览 HTML
    static func buildSinglePreviewHTML(markdown: String, emptyPlaceholder: String = "在此实时预览 Markdown 与 LaTeX 数学公式排版效果…") -> String {
        let encoder = JSONEncoder()
        let rawJSON: String
        if let data = try? encoder.encode(markdown), let str = String(data: data, encoding: .utf8) {
            rawJSON = str
        } else {
            rawJSON = "\"\""
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            \(sharedStylesheet)
            body {
                margin: 0;
                padding: 10px 12px;
                font-size: 14px;
            }
            .placeholder {
                color: var(--text-sub);
                font-size: 13px;
                font-style: italic;
            }
        </style>
        </head>
        <body>
        <div id="preview" class="md-body"></div>
        <script>
        \(sharedLatexAndMarkdownJS)
        const raw = \(rawJSON);
        const box = document.getElementById('preview');
        if (!raw || !raw.trim()) {
            box.innerHTML = `<span class="placeholder">\(emptyPlaceholder)</span>`;
        } else {
            box.innerHTML = renderMarkdownWithMath(raw);
        }
        window.updatePreview = function(newMd) {
            if (!newMd || !newMd.trim()) {
                box.innerHTML = `<span class="placeholder">\(emptyPlaceholder)</span>`;
            } else {
                box.innerHTML = renderMarkdownWithMath(newMd);
            }
        };
        </script>
        </body>
        </html>
        """
    }

    private static func renderFeedHTML(dtos: [NoteDTO], emptyHint: String) -> String {
        let encoder = JSONEncoder()
        let jsonString: String
        if let data = try? encoder.encode(dtos), let str = String(data: data, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "[]"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            \(sharedStylesheet)
        </style>
        </head>
        <body>
        <div id="container"></div>
        <script>
        const notes = \(jsonString);
        \(sharedLatexAndMarkdownJS)

        function postAction(action, id, extra) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.noteAction) {
                window.webkit.messageHandlers.noteAction.postMessage({ action, id, extra: extra || '' });
            }
        }

        const container = document.getElementById('container');
        if (notes.length === 0) {
            container.innerHTML = `<div class="empty-state">\(emptyHint)</div>`;
        } else {
            container.innerHTML = notes.map(n => {
                const bodyHTML = renderMarkdownWithMath(n.markdownNote);
                const paperBadgeHTML = n.paperTitle ? `
                    <div class="paper-source-badge" onclick="postAction('jump', '${n.id}')">
                        📄 ${escapeHTML(n.paperTitle)}
                    </div>
                ` : '';
                const linkHTML = n.linkedURL ? `
                    <div class="link-row">
                        <span class="link-pill" onclick="postAction('openLink', '${n.id}')">
                            <svg width="11" height="11" viewBox="0 0 16 16" fill="currentColor"><path d="M6.354 5.5H4a3 3 0 0 0 0 6h3a3 3 0 0 0 2.83-4H9c-.086 0-.17.01-.25.031A2 2 0 0 1 7 9.5H4a2 2 0 1 1 0-4h1.535c.218-.376.495-.714.82-1z"/><path d="M9 5.5a3 3 0 0 0-2.83 4h1.098A2 2 0 0 1 9 6.5h3a2 2 0 1 1 0 4h-1.535a4.02 4.02 0 0 1-.82 1H12a3 3 0 1 0 0-6H9z"/></svg>
                            ${escapeHTML(n.linkedTitle || n.linkedURL)}
                        </span>
                    </div>
                ` : '';

                return `
                <div class="note-card">
                    ${paperBadgeHTML}
                    <div class="card-header">
                        <div class="badge-group" onclick="postAction('jump', '${n.id}')" title="点击跳转到 PDF 对应页面位置">
                            <span class="color-dot" style="background:${n.colorHex}"></span>
                            <span class="page-pill">${n.sideBadge} · P.${n.pageNumber}</span>
                        </div>
                        <div class="actions">
                            <button class="btn-mini" onclick="postAction('edit', '${n.id}')">编辑</button>
                            <button class="btn-mini btn-danger" onclick="postAction('delete', '${n.id}')">删除</button>
                        </div>
                    </div>
                    <div class="excerpt" style="border-left-color:${n.colorHex}" onclick="postAction('jump', '${n.id}')" title="点击定位到原文高亮处">
                        “${escapeHTML(n.selectedText)}”
                    </div>
                    ${bodyHTML ? `<div class="md-body">${bodyHTML}</div>` : ''}
                    ${linkHTML}
                </div>
                `;
            }).join('');
        }
        </script>
        </body>
        </html>
        """
    }

    private static let sharedStylesheet: String = (try? AppResources.text(named: "MarkdownMathRenderer.css")) ?? ""
    static let sharedLatexAndMarkdownJS: String = (try? AppResources.text(named: "MarkdownMathRenderer.js"))
        ?? "function renderMarkdownWithMath() { return '无法加载 Markdown 渲染资源'; }"
}
