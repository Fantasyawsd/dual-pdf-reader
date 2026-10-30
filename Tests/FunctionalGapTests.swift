import Cocoa

func runFunctionalGapTests() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("DualPDF-FunctionalGaps-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    // Use independent stores; successful switchLibraryRoot also persists the user's default root.
    let rootA = tempRoot.appendingPathComponent("library-a", isDirectory: true)
    let rootB = tempRoot.appendingPathComponent("library-b", isDirectory: true)
    var categoryErrors: [String] = []
    let storeA = LibraryStore(rootDirectory: rootA) { categoryErrors.append($0) }
    let storeB = LibraryStore(rootDirectory: rootB)
    var categoryChanges: [LibraryChange] = []
    let categoryObserver = NotificationCenter.default.addObserver(
        forName: LibraryStore.libraryDidChangeNotification, object: nil, queue: nil
    ) { notification in
        guard let sender = notification.object as? LibraryStore, sender === storeA,
              let change = notification.userInfo?["change"] as? LibraryChange else { return }
        categoryChanges.append(change)
    }
    defer { NotificationCenter.default.removeObserver(categoryObserver) }

    check(storeA.papers.isEmpty && storeA.allCategories().isEmpty, "Functional gaps: new library starts without papers or categories")
    check(storeA.createCategory("  Empty A \n"), "Functional gaps: create an empty category")
    check(storeA.papers.isEmpty && storeA.allCategories() == ["Empty A"],
          "Functional gaps: trimmed empty category does not create a placeholder paper")
    check(categoryChanges.count == 1 && categoryChanges.last?.fields == .metadata &&
          categoryChanges.last?.paperIDs.isEmpty == true && categoryChanges.last?.resetsLibrary == false,
          "Functional gaps: category commit publishes one metadata change without paper IDs")
    let categoriesURL = rootA.appendingPathComponent("categories.json")
    check(try JSONDecoder().decode([String].self, from: Data(contentsOf: categoriesURL)) == ["Empty A"],
          "Functional gaps: empty category is persisted independently of papers")
    let rebuiltA = LibraryStore(rootDirectory: rootA)
    check(rebuiltA.papers.isEmpty && rebuiltA.allCategories() == ["Empty A"],
          "Functional gaps: empty category survives store reconstruction")
    check(storeA.createCategory("Empty A") && categoryChanges.count == 1,
          "Functional gaps: duplicate category is idempotent and does not notify")
    check(!storeA.createCategory(" \t\n") && storeA.allCategories() == ["Empty A"] && categoryChanges.count == 1,
          "Functional gaps: blank category is rejected without publishing or changing state")
    check(rebuiltA.createCategory("Reloaded A"), "Functional gaps: second store can persist another empty category")
    storeA.reloadAllPapers()
    check(storeA.allCategories() == ["Empty A", "Reloaded A"],
          "Functional gaps: reload reads empty categories written by another store")
    check(storeB.createCategory("Empty B"), "Functional gaps: another library can create its own category")
    var paperA = fixture(id: "category-paper-a")
    paperA.category = "Assigned A"
    var paperB = fixture(id: "category-paper-b")
    paperB.category = "Assigned B"
    check(storeA.savePaper(paperA) && storeB.savePaper(paperB), "Functional gaps: independent library fixtures are persisted")
    check(storeA.allCategories() == ["Assigned A", "Empty A", "Reloaded A"] &&
          storeB.allCategories() == ["Assigned B", "Empty B"] &&
          storeA.paper(withId: paperB.id) == nil && storeB.paper(withId: paperA.id) == nil,
          "Functional gaps: categories and papers remain isolated between library roots")
    check(LibraryStore(rootDirectory: rootA).allCategories() == ["Assigned A", "Empty A", "Reloaded A"] &&
          LibraryStore(rootDirectory: rootB).allCategories() == ["Assigned B", "Empty B"],
          "Functional gaps: reopening either root restores only its own categories")

    let committedCategories = storeA.allCategories()
    let committedPaperIDs = Set(storeA.papers.map(\.id))
    let categoryBytes = try Data(contentsOf: categoriesURL)
    categoryChanges.removeAll()
    let errorsBeforeWrite = categoryErrors.count
    // A directory at the destination forces failure even when the test process can write as root.
    try fileManager.removeItem(at: categoriesURL)
    try fileManager.createDirectory(at: categoriesURL, withIntermediateDirectories: false)
    check(!storeA.createCategory("Uncommitted category"), "Functional gaps: category storage failure is returned")
    check(storeA.allCategories() == committedCategories && Set(storeA.papers.map(\.id)) == committedPaperIDs &&
          categoryChanges.isEmpty && categoryErrors.count > errorsBeforeWrite,
          "Functional gaps: failed category write reports error without notifying or polluting memory")
    try fileManager.removeItem(at: categoriesURL)

    try Data("not category JSON".utf8).write(to: categoriesURL, options: .atomic)
    let errorsBeforeReload = categoryErrors.count
    storeA.reloadAllPapers()
    check(storeA.allCategories() == committedCategories && Set(storeA.papers.map(\.id)) == committedPaperIDs &&
          categoryChanges.isEmpty && categoryErrors.count > errorsBeforeReload,
          "Functional gaps: corrupt category reload preserves committed state without notification")
    try categoryBytes.write(to: categoriesURL, options: .atomic)

    let invalidRoot = tempRoot.appendingPathComponent("invalid-library", isDirectory: true)
    let invalidStore = LibraryStore(rootDirectory: invalidRoot)
    check(invalidStore.savePaper(fixture(id: "must-not-leak"), notify: false),
          "Functional gaps: failed-switch destination contains a distinct paper")
    try Data("{}".utf8).write(to: invalidRoot.appendingPathComponent("categories.json"), options: .atomic)
    let errorsBeforeSwitch = categoryErrors.count
    check(!storeA.switchLibraryRoot(to: invalidRoot), "Functional gaps: switching to corrupt category storage fails")
    check(storeA.rootDirectory == rootA.standardizedFileURL && storeA.allCategories() == committedCategories &&
          Set(storeA.papers.map(\.id)) == committedPaperIDs && storeA.paper(withId: "must-not-leak") == nil &&
          categoryChanges.isEmpty && categoryErrors.count > errorsBeforeSwitch,
          "Functional gaps: failed switch preserves root, categories and papers without notification")

    check(LibraryViewController.metadataTags(from: [" #machine learning ", "#推理， #优化", "", "  "]) ==
          ["machine learning", "推理", "优化"], "Functional gaps: metadata tags accept an array and normalize separators and prefixes")
    check(LibraryViewController.metadataTags(from: " #alpha, #beta，#中文 ") == ["alpha", "beta", "中文"],
          "Functional gaps: metadata tags accept the inspector string format")
    check(LibraryViewController.metadataTags(from: [String]()) == [] &&
          LibraryViewController.metadataTags(from: " ,， # \n") == [],
          "Functional gaps: empty tag arrays and strings explicitly clear tags")
    let invalidTagValues: [Any?] = [nil, NSNull(), 42, ["tag": "value"], ["valid", 42] as [Any]]
    for (index, value) in invalidTagValues.enumerated() {
        check(LibraryViewController.metadataTags(from: value) == nil,
              "Functional gaps: invalid metadata tag value \(index) cannot clear or replace tags")
    }

    let metadataRoot = tempRoot.appendingPathComponent("metadata-library", isDirectory: true)
    let metadataStore = LibraryStore(rootDirectory: metadataRoot)
    var metadataPaper = fixture(id: "metadata-only")
    check(metadataStore.savePaper(metadataPaper, notify: false), "Functional gaps: metadata fixture commits")
    var metadataChanges: [LibraryChange] = []
    let metadataObserver = NotificationCenter.default.addObserver(
        forName: LibraryStore.libraryDidChangeNotification, object: nil, queue: nil
    ) { notification in
        guard let sender = notification.object as? LibraryStore, sender === metadataStore,
              let change = notification.userInfo?["change"] as? LibraryChange else { return }
        metadataChanges.append(change)
    }
    defer { NotificationCenter.default.removeObserver(metadataObserver) }
    metadataPaper.arxivId = "2601.01234v2"
    check(metadataStore.savePaper(metadataPaper), "Functional gaps: arXiv-only update commits")
    check(metadataChanges.count == 1 && metadataChanges.last?.fields == .metadata &&
          metadataChanges.last?.paperIDs == Set([metadataPaper.id]) && metadataChanges.last?.resetsLibrary == false,
          "Functional gaps: arXiv-only update publishes exactly the affected paper's metadata")
    metadataPaper.citationCount = 17
    check(metadataStore.savePaper(metadataPaper), "Functional gaps: citation-only update commits")
    check(metadataChanges.count == 2 && metadataChanges.last?.fields == .metadata &&
          metadataChanges.last?.paperIDs == Set([metadataPaper.id]) && metadataChanges.last?.resetsLibrary == false,
          "Functional gaps: citation-only update publishes exactly the affected paper's metadata")
    let restoredMetadata = LibraryStore(rootDirectory: metadataRoot).paper(withId: metadataPaper.id)
    check(restoredMetadata?.arxivId == "2601.01234v2" && restoredMetadata?.citationCount == 17,
          "Functional gaps: arXiv ID and citation count survive reconstruction")
    check(metadataStore.savePaper(metadataPaper) && metadataChanges.count == 2,
          "Functional gaps: unchanged academic metadata does not publish another change")

    // Call the deterministic offline entry directly: never alter defaults or consult shared configuration.
    let service = LLMTranslationService()
    let selectedText = "A selected fragment with unknown terminology."
    let pairedSentinel = "PAIR_SENTINEL_这是一整页无关译文，不能作为选区译文。"
    for mode in [LLMTranslationMode.academicChinese, .englishPolish] {
        let offline = service.translateLocally(text: "  \(selectedText)\n", mode: mode, pairedPageText: pairedSentinel)
        let withoutPair = service.translateLocally(text: selectedText, mode: mode)
        check(!offline.isSuccess && !offline.isRemoteLLM && offline.mode == mode && offline.sourceText == selectedText &&
              offline.providerLabel.contains("远程"), "Functional gaps: offline \(mode.rawValue) reports unavailable translation or polishing")
        check(offline.translatedMarkdown == withoutPair.translatedMarkdown && !offline.translatedMarkdown.contains(pairedSentinel),
              "Functional gaps: offline \(mode.rawValue) cannot substitute paired page text")
    }
    for mode in LLMTranslationMode.allCases {
        let empty = service.translateLocally(text: " \t\n", mode: mode, pairedPageText: pairedSentinel)
        check(!empty.isSuccess && !empty.isRemoteLLM && !empty.translatedMarkdown.contains(pairedSentinel),
              "Functional gaps: empty selection is unsuccessful in \(mode.rawValue)")
    }

    let summaryText = "Attention reaches 3.14 units. It keeps $x_1$ intact! Final evidence? This sentence is excluded."
    check(service.extractSummarySentences(from: summaryText) ==
          ["Attention reaches 3.14 units.", "It keeps $x_1$ intact!", "Final evidence?"],
          "Functional gaps: excerpts preserve decimals, formulas, sentence order and the three-sentence limit")
    check(service.extractSummarySentences(from: "第一句。第二句！第三句？第四句。", limit: 2) == ["第一句。", "第二句！"],
          "Functional gaps: excerpts recognize Chinese sentence boundaries")
    check(service.extractSummarySentences(from: "Only one sentence.", limit: 10) == ["Only one sentence."] &&
          service.extractSummarySentences(from: " \n").isEmpty &&
          service.extractSummarySentences(from: summaryText, limit: 0).isEmpty &&
          service.extractSummarySentences(from: summaryText, limit: -1).isEmpty,
          "Functional gaps: excerpts handle short input, whitespace and nonpositive limits")
    let summary = service.translateLocally(text: summaryText, mode: .conciseSummary, pairedPageText: pairedSentinel)
    check(summary.isSuccess && !summary.isRemoteLLM && summary.providerLabel.contains("原文摘录") &&
          summary.translatedMarkdown.contains("Attention reaches 3.14 units.") &&
          summary.translatedMarkdown.contains("It keeps $x_1$ intact!") && summary.translatedMarkdown.contains("Final evidence?") &&
          !summary.translatedMarkdown.contains("This sentence is excluded.") && !summary.translatedMarkdown.contains(pairedSentinel),
          "Functional gaps: offline summary is labeled original excerpts without rewriting or paired context")

    let dictionary = service.translateLocally(text: "TRANSFORMER, KV\ncache; self-attention.", mode: .explainAndFormula)
    check(dictionary.isSuccess && !dictionary.isRemoteLLM && dictionary.providerLabel.contains("词典") &&
          dictionary.translatedMarkdown.contains("`transformer`") && dictionary.translatedMarkdown.contains("`KV cache`") &&
          dictionary.translatedMarkdown.contains("`self-attention`"),
          "Functional gaps: offline dictionary recognizes case, punctuation and line-wrapped terms")
    let repeatedTerm = service.translateLocally(text: "attention Attention ATTENTION", mode: .explainAndFormula)
    check(repeatedTerm.isSuccess && repeatedTerm.translatedMarkdown.components(separatedBy: "`attention`").count == 2,
          "Functional gaps: repeated dictionary terms produce one entry")
    for text in ["preattention attentional attention2 _attention transformerish rerouting",
                 "αattention attentionβ 中attention attention中", "$u = mv$ is an unfamiliar symbol."] {
        let miss = service.translateLocally(text: text, mode: .explainAndFormula, pairedPageText: "attention")
        check(!miss.isSuccess && !miss.isRemoteLLM && !miss.translatedMarkdown.contains("`attention`"),
              "Functional gaps: dictionary does not invent a match for \(text) or use paired context")
    }

    let responseURL = URL(string: "https://example.invalid/v1/chat/completions")!
    func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }
    let remoteText = "REMOTE_RESULT: actual model content with $E=mc^2$."
    let successData = try JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": " \n\(remoteText)\n "]]]
    ])
    for mode in LLMTranslationMode.allCases {
        let result = service.resultFromRemoteResponse(text: selectedText, mode: mode, modelName: "fixture-model",
                                                      data: successData, response: httpResponse(200), error: nil)
        check(result.isSuccess && result.isRemoteLLM && result.translatedMarkdown == remoteText &&
              result.sourceText == selectedText && result.mode == mode && result.providerLabel.contains("fixture-model"),
              "Functional gaps: synthetic remote success returns model content in \(mode.rawValue)")
    }
    let whitespaceData = try JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": " \n\t "]]]
    ])
    let errorData = try JSONSerialization.data(withJSONObject: ["error": ["message": "synthetic API error"]])
    let transportError = NSError(domain: "FunctionalGapTests", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "synthetic transport failure"])
    let failureCases: [(name: String, data: Data?, response: URLResponse?, error: Error?, reason: String?)] = [
        ("HTTP 401 with plausible content", successData, httpResponse(401), nil, "401"),
        ("HTTP 500 with plausible content", successData, httpResponse(500), nil, "500"),
        ("transport error with plausible content", successData, httpResponse(200), transportError, "synthetic transport failure"),
        ("missing HTTP response", successData, nil, nil, nil),
        ("missing response body", nil, httpResponse(200), nil, nil),
        ("empty response bytes", Data(), httpResponse(200), nil, nil),
        ("blank model content", whitespaceData, httpResponse(200), nil, nil),
        ("malformed JSON", Data("not JSON".utf8), httpResponse(200), nil, nil),
        ("API error payload", errorData, httpResponse(200), nil, nil)
    ]
    for mode in LLMTranslationMode.allCases {
        for failureCase in failureCases {
            let failure = service.resultFromRemoteResponse(text: "attention improves latency.", mode: mode, modelName: "fixture-model",
                                                           data: failureCase.data, response: failureCase.response, error: failureCase.error)
            check(!failure.isSuccess && !failure.isRemoteLLM && failure.mode == mode &&
                  failure.sourceText == "attention improves latency." && failure.providerLabel.contains("远程") &&
                  failure.providerLabel.contains("失败") && !failure.translatedMarkdown.isEmpty &&
                  !failure.translatedMarkdown.contains(remoteText) &&
                  (failureCase.reason.map { failure.translatedMarkdown.contains($0) } ?? true),
                  "Functional gaps: \(failureCase.name) stays a failure without offline fallback in \(mode.rawValue)")
        }
    }
}
