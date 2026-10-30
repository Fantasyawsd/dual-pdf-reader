import Foundation

struct LibraryChange {
    struct Fields: OptionSet {
        let rawValue: Int
        static let metadata = Fields(rawValue: 1 << 0)
        static let pdf = Fields(rawValue: 1 << 1)
        static let annotations = Fields(rawValue: 1 << 2)
        static let resources = Fields(rawValue: 1 << 3)
        static let membership = Fields(rawValue: 1 << 4)
        static let reading = Fields(rawValue: 1 << 5)
        static let all: Fields = [.metadata, .pdf, .annotations, .resources, .membership, .reading]
    }

    let paperIDs: Set<String>
    let fields: Fields
    let resetsLibrary: Bool

    func affects(_ paperId: String) -> Bool {
        resetsLibrary || paperIDs.contains(paperId)
    }
}
