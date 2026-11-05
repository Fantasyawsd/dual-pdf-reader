import Foundation

/// Stable identity for deduplicating PDF opens across symlinks / alternate paths.
struct FileIdentity: Hashable, Equatable {
    private enum Payload: Hashable {
        case resourceID(Data)
        case path(String)
    }

    private let payload: Payload

    init?(url: URL) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        var values = URLResourceValues()
        do {
            values = try resolved.resourceValues(forKeys: [.fileResourceIdentifierKey])
        } catch {
            values = URLResourceValues()
        }
        if let id = values.fileResourceIdentifier as? Data {
            payload = .resourceID(id)
            return
        }
        // Fallback: compare canonical paths (covers soft links when resource id unavailable).
        let path = resolved.path
        guard !path.isEmpty else { return nil }
        payload = .path(path)
    }

    static func sameFile(_ a: URL, _ b: URL) -> Bool {
        guard let left = FileIdentity(url: a), let right = FileIdentity(url: b) else {
            return a.resolvingSymlinksInPath().standardizedFileURL.path
                == b.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return left == right
    }
}

enum DocumentOpenPlanner {
    /// Groups validated PDF URLs into tab batches: first two as a dual tab when ≥2, then singles.
    /// Caps total files consumed at `maxFiles` (default 10).
    static func tabBatches(from urls: [URL], maxFiles: Int = 10) -> (batches: [[URL]], ignoredCount: Int) {
        let capped = Array(urls.prefix(maxFiles))
        let ignored = max(0, urls.count - capped.count)
        guard !capped.isEmpty else { return ([], ignored) }
        if capped.count == 1 {
            return ([[capped[0]]], ignored)
        }
        var batches: [[URL]] = [Array(capped[0..<2])]
        if capped.count > 2 {
            batches.append(contentsOf: capped[2...].map { [$0] })
        }
        return (batches, ignored)
    }
}

