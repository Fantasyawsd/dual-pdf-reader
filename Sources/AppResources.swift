import Foundation

enum AppResources {
    static func text(named name: String) throws -> String {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(name)
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources").appendingPathComponent(name)
        let url = [bundled, development].compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? development
        return try String(contentsOf: url, encoding: .utf8)
    }
}
