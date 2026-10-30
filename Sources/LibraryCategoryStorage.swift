import Foundation

/// Stores collections independently of the papers currently assigned to them.
struct LibraryCategoryStorage {
    let rootDirectory: URL

    private var fileURL: URL { rootDirectory.appendingPathComponent("categories.json") }

    func readCategories() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return Self.normalized(try JSONDecoder().decode([String].self, from: Data(contentsOf: fileURL)))
    }

    func writeCategories(_ categories: [String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Self.normalized(categories))
        try data.write(to: fileURL, options: .atomic)
    }

    private static func normalized(_ categories: [String]) -> [String] {
        Array(Set(categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
}
