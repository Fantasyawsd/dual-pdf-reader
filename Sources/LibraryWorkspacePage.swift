import Foundation

enum LibraryWorkspacePage {
    private static let resources: Result<(html: String, css: String, js: String), Error> = Result {
        return try (AppResources.text(named: "LibraryWorkspace.html"),
                    AppResources.text(named: "LibraryWorkspace.css"),
                    AppResources.text(named: "LibraryWorkspace.js"))
    }

    static func html(initialStateJSON: String) -> String {
        switch resources {
        case .success(let page):
            // Replace template tokens before inserting user data to keep text literal.
            let script = page.js.replacingOccurrences(of: "__SHARED_RENDERER_JS__", with: MarkdownMathRenderer.sharedLatexAndMarkdownJS)
            return page.html
                .replacingOccurrences(of: "__WORKSPACE_CSS__", with: page.css)
                .replacingOccurrences(of: "__WORKSPACE_JS__", with: script)
                .replacingOccurrences(of: "__INITIAL_STATE_JSON__", with: initialStateJSON)
        case .failure(let error):
            let escaped = error.localizedDescription.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            return "<meta charset='utf-8'><p>无法加载文献库界面资源：\(escaped)</p>"
        }
    }
}
