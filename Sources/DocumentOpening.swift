import Cocoa
import PDFKit
import UniformTypeIdentifiers

enum OpenOrigin {
    case systemOpen
    case openPanel
    case openRecent
    case windowDrop
}

enum DocumentOpenCopy {
    static func cannotOpenTitle(_ name: String) -> String { "无法打开“\(name)”" }
    static let onlyPDF = "DualPDF 只能打开 PDF 文件。"
    static func passwordTitle(_ name: String) -> String { "“\(name)”受密码保护" }
    static let passwordPrompt = "输入密码以打开此文档。"
    static let passwordRetry = "密码不正确，请重试。"
    static let corruptBody = "文件可能已损坏或不是有效的 PDF。"
    static func noPermissionTitle(_ name: String) -> String { "没有权限读取“\(name)”" }
    static let noPermissionBody = "请在 Finder 中检查此文件的访问权限后重试。"
    static func missingTitle(_ name: String) -> String { "找不到“\(name)”" }
    static let missingBody = "文件可能已被移动或删除。"
    static func ignoredNonPDF(_ count: Int) -> String { "已忽略 \(count) 个非 PDF 文件。" }
    static func columnOnlyOne(_ name: String) -> String { "此栏只能放一份 PDF，已打开“\(name)”。" }
    static let tabLimit = "一次最多打开 10 个文件，其余已忽略。"
    static func multiFailTitle(_ count: Int) -> String { "有 \(count) 个文件无法打开" }
    static func iCloudDownloading(_ name: String) -> String { "正在从 iCloud 下载“\(name)”…" }
    static func iCloudDownloadingMany(_ count: Int) -> String { "正在下载 \(count) 个文件" }
    static func iCloudFailed(_ name: String) -> String { "无法从 iCloud 下载“\(name)”。请检查网络后重试。" }
    static let iCloudRetry = "重试"
    static let dropOnColumnHint = "松开以在此栏打开"
    static let dropToOpenHint = "松开以打开"
    static let encryptedNotImported = "已临时打开加密 PDF（未写入文献库，明文不落盘）。"
}

enum DocumentValidation {
    enum Outcome {
        case ok(URL)
        case nonPDF(URL)
        case missing(URL)
        case unreadable(URL)
        case corrupt(URL)
        case locked(URL, PDFDocument)
        case iCloudPending(URL)
        case failure(URL, reason: String)
    }

    static func isPDF(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) { return true }
        }
        return url.pathExtension.lowercased() == "pdf"
    }

    static func classify(_ url: URL) -> Outcome {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isReadableKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                return .missing(url)
            }
            return .unreadable(url)
        }

        if values.isUbiquitousItem == true,
           let status = values.ubiquitousItemDownloadingStatus,
           status != .current {
            return .iCloudPending(url)
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            return .missing(url)
        }
        if values.isReadable == false || !FileManager.default.isReadableFile(atPath: url.path) {
            return .unreadable(url)
        }
        if !isPDF(url) {
            return .nonPDF(url)
        }
        guard let doc = PDFDocument(url: url) else {
            return .corrupt(url)
        }
        if doc.isLocked {
            return .locked(url, doc)
        }
        if doc.pageCount == 0 {
            return .corrupt(url)
        }
        return .ok(url)
    }
}

enum DocumentOpenAlerts {
    @discardableResult
    static func presentPassword(for url: URL, document: PDFDocument, window: NSWindow?) -> String? {
        let name = url.lastPathComponent
        var informative = DocumentOpenCopy.passwordPrompt
        while true {
            let alert = NSAlert()
            alert.messageText = DocumentOpenCopy.passwordTitle(name)
            alert.informativeText = informative
            alert.addButton(withTitle: "打开")
            alert.addButton(withTitle: "取消")
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            alert.accessoryView = field
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return nil }
            let password = field.stringValue
            if document.unlock(withPassword: password) {
                return password
            }
            informative = DocumentOpenCopy.passwordRetry
        }
    }

    static func presentSimple(title: String, body: String, revealURL: URL?, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "好")
        if revealURL != nil {
            alert.addButton(withTitle: "在 Finder 中显示")
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn, let revealURL {
            NSWorkspace.shared.activateFileViewerSelecting([revealURL])
        }
        _ = window
    }

    static func presentMissingRecent(name: String) -> Bool {
        // Returns true if user chose 「从列表中移除」
        let alert = NSAlert()
        alert.messageText = DocumentOpenCopy.missingTitle(name)
        alert.informativeText = DocumentOpenCopy.missingBody
        alert.addButton(withTitle: "从列表中移除")
        alert.addButton(withTitle: "好")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func presentCombinedFailures(_ items: [(name: String, reason: String)]) {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = DocumentOpenCopy.multiFailTitle(items.count)
        alert.informativeText = items.map { "\($0.name) — \($0.reason)" }.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

/// Lightweight bottom banner hosted on a window content view.
/// Supports an optional retry action and sticky multi-download summaries.
final class WindowStatusBannerController {
    private weak var host: NSView?
    private var banner: NSView?
    private var hideWork: DispatchWorkItem?
    private var retryHandler: (() -> Void)?

    init(host: NSView?) {
        self.host = host
    }

    func show(_ text: String, duration: TimeInterval? = 4, retry: (() -> Void)? = nil) {
        guard let host else { return }
        hideWork?.cancel()
        banner?.removeFromSuperview()
        retryHandler = retry

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(label)

        if retry != nil {
            let button = NSButton(title: DocumentOpenCopy.iCloudRetry, target: self, action: #selector(retryTapped))
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(button)
        }

        box.addSubview(row)
        host.addSubview(box)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            box.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            box.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -18),
            box.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -40)
        ])
        banner = box

        if let duration {
            let work = DispatchWorkItem { [weak self] in
                self?.banner?.removeFromSuperview()
                self?.banner = nil
                self?.retryHandler = nil
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func dismiss() {
        hideWork?.cancel()
        banner?.removeFromSuperview()
        banner = nil
        retryHandler = nil
    }

    @objc private func retryTapped() {
        let handler = retryHandler
        dismiss()
        handler?()
    }
}
