import Foundation
import PDFKit
import Darwin

/// Owns disk operations; callers publish changes only after the metadata commits.
struct LibraryFileStorage {
    let rootDirectory: URL
    private let fileManager = FileManager.default

    func folderURL(for paperId: String) -> URL {
        rootDirectory.appendingPathComponent(paperId, isDirectory: true)
    }

    func writeMetadata(_ paper: PaperItem) throws {
        try writeMetadata([paper])
    }

    /// Rolls back earlier writes if any member of a related-paper update fails.
    func writeMetadata(_ papers: [PaperItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var originals: [(url: URL, data: Data?)] = []
        do {
            for paper in papers {
                let folder = folderURL(for: paper.id)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("meta.json")
                let previous = fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
                let data = try encoder.encode(paper)
                try data.write(to: url, options: .atomic)
                originals.append((url, previous))
            }
        } catch {
            for original in originals.reversed() {
                if let data = original.data {
                    try data.write(to: original.url, options: .atomic)
                } else {
                    try fileManager.removeItem(at: original.url)
                }
            }
            throw error
        }
    }

    /// Stage beside the destination so rename stays atomic on the same volume.
    func replacePDF(from source: URL, at destination: URL, commit: () throws -> Void) throws {
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard PDFDocument(url: source) != nil else {
            throw StorageError.invalidPDF(source.lastPathComponent)
        }
        if source == destination {
            try commit()
            return
        }

        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent(".import-\(UUID().uuidString).pdf")
        let backup = folder.appendingPathComponent(".backup-\(UUID().uuidString).pdf")
        var preserveBackup = false
        defer {
            try? fileManager.removeItem(at: staged)
            if !preserveBackup { try? fileManager.removeItem(at: backup) }
        }
        try fileManager.copyItem(at: source, to: staged)
        guard PDFDocument(url: staged) != nil else {
            throw StorageError.invalidPDF(source.lastPathComponent)
        }
        let hadOriginal = fileManager.fileExists(atPath: destination.path)
        if hadOriginal { try fileManager.copyItem(at: destination, to: backup) }
        try atomicRename(staged, to: destination)
        do {
            try commit()
        } catch {
            if hadOriginal {
                do { try atomicRename(backup, to: destination) }
                catch {
                    preserveBackup = true
                    throw NSError(domain: "DualPDF.Storage", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "PDF 恢复失败，旧文件备份保留在：\(backup.path)"
                    ])
                }
            } else {
                try fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    func copyAttachment(from source: URL, for paperId: String) throws -> URL {
        let folder = folderURL(for: paperId).appendingPathComponent("attachments", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Each resource owns its file, even when different sources share a basename.
        let resourceFolder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: resourceFolder, withIntermediateDirectories: false)
        let destination = resourceFolder.appendingPathComponent(source.lastPathComponent)
        do {
            try fileManager.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: resourceFolder)
            throw error
        }
    }

    private func atomicRename(_ source: URL, to destination: URL) throws {
        guard Darwin.rename(source.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    enum StorageError: LocalizedError {
        case invalidPDF(String)
        var errorDescription: String? {
            switch self {
            case .invalidPDF(let name): return "无法读取 PDF：\(name)。请确认文件存在且格式有效。"
            }
        }
    }
}
