import Cocoa

enum LLMTranslationMode: String, CaseIterable {
    case academicChinese = "academic_zh"
    case explainAndFormula = "explain_formula"
    case conciseSummary = "summary"
    case englishPolish = "academic_en"

    var displayName: String {
        switch self {
        case .academicChinese:   return "学术中文精译"
        case .explainAndFormula: return "术语与公式解析"
        case .conciseSummary:    return "核心要点提炼"
        case .englishPolish:     return "英文学术译写"
        }
    }
}

struct LLMTranslationResult {
    let sourceText: String
    let mode: LLMTranslationMode
    let translatedMarkdown: String
    let providerLabel: String
    let isRemoteLLM: Bool
    /// false 表示只有提示或错误，界面不应启用复制译文、插入笔记等结果动作。
    let isSuccess: Bool

    init(sourceText: String, mode: LLMTranslationMode, translatedMarkdown: String,
         providerLabel: String, isRemoteLLM: Bool, isSuccess: Bool = true) {
        self.sourceText = sourceText
        self.mode = mode
        self.translatedMarkdown = translatedMarkdown
        self.providerLabel = providerLabel
        self.isRemoteLLM = isRemoteLLM
        self.isSuccess = isSuccess
    }
}

final class LLMTranslationService {
    static let shared = LLMTranslationService()

    private let endpointKey = "DualPDF_LLM_Endpoint"
    private let apiKeyKey = "DualPDF_LLM_APIKey"
    private let modelKey = "DualPDF_LLM_Model"

    var endpointURLString: String {
        get {
            let saved = UserDefaults.standard.string(forKey: endpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !saved.isEmpty { return saved }
            if let envURL = ProcessInfo.processInfo.environment["LLM_BASE_URL"], !envURL.isEmpty {
                return envURL
            }
            if ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] != nil {
                return "https://api.deepseek.com/chat/completions"
            }
            return "https://api.openai.com/v1/chat/completions"
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: endpointKey)
        }
    }

    var apiKey: String {
        get {
            let saved = UserDefaults.standard.string(forKey: apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !saved.isEmpty { return saved }
            let env = ProcessInfo.processInfo.environment
            return env["LLM_API_KEY"] ?? env["DEEPSEEK_API_KEY"] ?? env["OPENAI_API_KEY"] ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyKey)
        }
    }

    var modelName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !saved.isEmpty { return saved }
            if let envModel = ProcessInfo.processInfo.environment["LLM_MODEL"], !envModel.isEmpty {
                return envModel
            }
            if endpointURLString.contains("deepseek") {
                return "deepseek-chat"
            }
            return "gpt-4o-mini"
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey)
        }
    }

    var isRemoteConfigured: Bool {
        let ep = endpointURLString.lowercased()
        let isLocalHost = ep.contains("localhost") || ep.contains("127.0.0.1")
        return !apiKey.isEmpty || isLocalHost
    }

    /// 已配置时调用 OpenAI 兼容接口；离线仅提供明确标识的原文摘录与词典查询。
    @discardableResult
    func translate(
        text: String,
        mode: LLMTranslationMode = .academicChinese,
        pairedPageText: String? = nil,
        completion: @escaping (LLMTranslationResult) -> Void
    ) -> URLSessionDataTask? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            completion(translateLocally(text: text, mode: mode))
            return nil
        }

        guard isRemoteConfigured else {
            let localResult = translateLocally(text: cleanText, mode: mode, pairedPageText: pairedPageText)
            DispatchQueue.main.async { completion(localResult) }
            return nil
        }
        guard let url = URL(string: endpointURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            let failure = remoteFailureResult(text: cleanText, mode: mode, modelName: modelName,
                                              reason: "API Endpoint 无效，请使用完整的 HTTP 或 HTTPS 接口地址。")
            DispatchQueue.main.async { completion(failure) }
            return nil
        }

        let systemPrompt = buildSystemPrompt(for: mode)
        var userPrompt = "请处理以下论文划选片段：\n\n\(cleanText)"
        if let paired = pairedPageText?.trimmingCharacters(in: .whitespacesAndNewlines), !paired.isEmpty {
            let snippet = String(paired.prefix(1200))
            userPrompt += "\n\n（参考同页对照文本片段：\n\(snippet)\n）"
        }

        let currentModel = modelName
        let payload: [String: Any] = [
            "model": currentModel,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            let failure = remoteFailureResult(text: cleanText, mode: mode, modelName: currentModel,
                                              reason: "无法编码远程请求。")
            DispatchQueue.main.async { completion(failure) }
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let result = self.resultFromRemoteResponse(text: cleanText, mode: mode, modelName: currentModel,
                                                       data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    /// 纯响应处理入口，便于用合成响应验证成功与失败路径，无需发起网络请求。
    func resultFromRemoteResponse(
        text: String,
        mode: LLMTranslationMode,
        modelName: String,
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> LLMTranslationResult {
        if let error = error {
            return remoteFailureResult(text: text, mode: mode, modelName: modelName,
                                       reason: error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            return remoteFailureResult(text: text, mode: mode, modelName: modelName,
                                       reason: "未收到有效的 HTTP 响应。")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            return remoteFailureResult(text: text, mode: mode, modelName: modelName,
                                       reason: "接口返回 HTTP \(httpResponse.statusCode)。")
        }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return remoteFailureResult(text: text, mode: mode, modelName: modelName,
                                       reason: "接口响应未包含有效的文本内容。")
        }
        return LLMTranslationResult(
            sourceText: text,
            mode: mode,
            translatedMarkdown: content,
            providerLabel: "远程 LLM (\(modelName))",
            isRemoteLLM: true
        )
    }

    private func remoteFailureResult(text: String, mode: LLMTranslationMode, modelName: String,
                                     reason: String) -> LLMTranslationResult {
        return LLMTranslationResult(
            sourceText: text,
            mode: mode,
            translatedMarkdown: "### 远程 LLM 请求失败\n\n\(reason)\n\n未生成处理结果。请检查接口地址、模型及 API Key 后重试。离线仅支持原文摘录摘要和内置词典查询。",
            providerLabel: "远程 LLM 请求失败 (\(modelName))",
            isRemoteLLM: false,
            isSuccess: false
        )
    }

    private func buildSystemPrompt(for mode: LLMTranslationMode) -> String {
        switch mode {
        case .academicChinese:
            return "你是一位精通人工智能、计算机科学与数学的资深学术论文翻译专家。请将用户划选的论文片段准确、流畅地翻译为符合中文学术规范的译文。保留所有数学变量与 LaTeX 公式（行内公式用 $...$，独立公式用 $$...$$），专业术语首次出现时可在括号内保留英文原词。直接输出译文，不要寒暄。"
        case .explainAndFormula:
            return "你是一位学术论文精读导师。请先给出划选片段的准确中文翻译，然后用简洁的 Markdown 列表解析其中的核心学术术语、符号含义或数学公式推导逻辑（使用 $...$ 或 $$...$$ 排版公式）。"
        case .conciseSummary:
            return "你是一位学术研究助手。请用中文提炼该段论文文本的核心结论与关键设计要点（使用 Markdown 要点列表，保留关键数学符号 $...$）。"
        case .englishPolish:
            return "You are an academic writing expert. Translate or polish the selected text into clear, publication-ready academic English while preserving all mathematical notations ($...$)."
        }
    }

    /// 离线仅提供原文摘录和内置词典查询，不生成通用译文或公式解析。
    /// pairedPageText 为兼容现有调用保留；离线不将同页片段冒充已对齐译文。
    func translateLocally(
        text: String,
        mode: LLMTranslationMode,
        pairedPageText: String? = nil
    ) -> LLMTranslationResult {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return LLMTranslationResult(sourceText: text, mode: mode,
                                        translatedMarkdown: "未检测到有效划选文本。",
                                        providerLabel: "未处理（空文本）", isRemoteLLM: false, isSuccess: false)
        }

        let output: String
        let provider: String
        let isSuccess: Bool
        switch mode {
        case .academicChinese, .englishPolish:
            output = "### 需要配置远程 LLM\n\n\(mode.displayName)需要可用的远程 LLM 服务。离线模式不提供通用翻译或润色；请在 AI 翻译设置中配置接口、模型及所需的 API Key 后重试。"
            provider = "未生成译文或译写（需配置远程 LLM）"
            isSuccess = false

        case .conciseSummary:
            let sentences = extractSummarySentences(from: cleanText)
            let excerpts = sentences.map { sentence in
                sentence.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
            }.joined(separator: "\n\n")
            output = sentences.isEmpty
                ? "### 离线原文摘录\n\n未识别到可摘录的原文句子，请调整选区后重试。"
                : "### 离线提取式摘要（原文摘录）\n\n按原文顺序摘取前 \(sentences.count) 句，保留原文语言；未翻译、改写或推断。\n\n" + excerpts
            provider = "离线提取式摘要（原文摘录，非翻译）"
            isSuccess = !sentences.isEmpty

        case .explainAndFormula:
            let detectedTerms = matchAcademicGlossary(in: cleanText)
            let entries = detectedTerms.map { "- **\($0.zh)** (`\($0.en)`)：\($0.explanation)" }
            let glossaryText = entries.isEmpty ? "未命中内置术语词典。离线无法解析此选段。" : entries.joined(separator: "\n")
            output = "### 离线术语查询（内置词典）\n\n以下仅为命中术语的固定词典释义，不是对当前论文的上下文解析。\n\n\(glossaryText)\n\n通用翻译、符号含义与公式推导需配置远程 LLM 服务后重试。"
            provider = "离线词典查询（公式解析需远程 LLM）"
            isSuccess = !detectedTerms.isEmpty
        }

        return LLMTranslationResult(sourceText: cleanText, mode: mode, translatedMarkdown: output,
                                    providerLabel: provider, isRemoteLLM: false, isSuccess: isSuccess)
    }

    /// 提取原文前若干句，保持句内文本不变，不做翻译、替换或语义生成。
    func extractSummarySentences(from text: String, limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, stop in
            guard let sentence = sentence?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sentence.isEmpty else { return }
            sentences.append(sentence)
            if sentences.count >= limit { stop = true }
        }
        return sentences
    }

    private struct GlossaryEntry {
        let en: String
        let zh: String
        let explanation: String
    }

    private static let glossary: [GlossaryEntry] = [
        GlossaryEntry(en: "Multi-head Latent Attention", zh: "多头潜在注意力机制 (MLA)", explanation: "通过对键值 (Key-Value) 进行低秩联合压缩，大幅降低推理阶段的 KV 缓存显存开销。"),
        GlossaryEntry(en: "Mixture-of-Experts", zh: "混合专家模型 (MoE)", explanation: "在前馈网络层采用稀疏激活的多个专家子网络，实现总参数量扩展而单令牌计算量恒定。"),
        GlossaryEntry(en: "auxiliary-loss-free", zh: "无辅助损失 (Auxiliary-Loss-Free)", explanation: "通过动态调节专家偏置项实现负载均衡，避免传统辅助损失对主任务训练目标产生干扰。"),
        GlossaryEntry(en: "load balancing", zh: "负载均衡", explanation: "确保不同专家网络之间分配到的词元数量均衡，防止路由坍缩与算力空转。"),
        GlossaryEntry(en: "Multi-Token Prediction", zh: "多词元预测 (MTP)", explanation: "在每个位置同时预测未来多个连续词元，增密训练信号并支持推理投机解码加速。"),
        GlossaryEntry(en: "KV cache", zh: "键值缓存 (KV Cache)", explanation: "自回归推理中缓存历史词元的键向量与值向量以避免重复计算。"),
        GlossaryEntry(en: "low-rank", zh: "低秩压缩", explanation: "将高维矩阵分解为低维潜在向量投影，显著减少参数量或缓存占用。"),
        GlossaryEntry(en: "routing", zh: "专家路由机制", explanation: "根据门控亲和度得分将输入特征分配至 Top-K 个激活专家。"),
        GlossaryEntry(en: "routed experts", zh: "路由专家", explanation: "由门控网络动态按需激活的稀疏专家模块。"),
        GlossaryEntry(en: "shared experts", zh: "共享专家", explanation: "对所有输入词元始终激活的专家模块，用于捕获跨领域的通用基础表征。"),
        GlossaryEntry(en: "transformer", zh: "Transformer 架构", explanation: "基于自注意力机制与前馈网络的现代序列建模骨干架构。"),
        GlossaryEntry(en: "self-attention", zh: "自注意力机制", explanation: "通过计算查询 ($Q$)、键 ($K$)、值 ($V$) 的缩放点积注意力捕获长程依赖。"),
        GlossaryEntry(en: "attention", zh: "注意力机制", explanation: "动态加权聚合上下文特征的核心计算模块。"),
        GlossaryEntry(en: "pre-training", zh: "预训练", explanation: "在大规模无标注语料上进行自监督语言建模训练。"),
        GlossaryEntry(en: "post-training", zh: "后训练", explanation: "包含监督微调 (SFT) 与强化学习对齐 (RL) 的模型能力精炼阶段。"),
        GlossaryEntry(en: "reinforcement learning", zh: "强化学习 (RL)", explanation: "通过奖励信号优化策略网络以提升推理与对齐能力。"),
        GlossaryEntry(en: "fine-tuning", zh: "微调", explanation: "在特定任务或指令数据集上进一步调整预训练模型参数。"),
        GlossaryEntry(en: "inference", zh: "推理阶段", explanation: "使用训练完成的模型进行前向生成与预测。"),
        GlossaryEntry(en: "throughput", zh: "吞吐量", explanation: "单位时间内系统能够处理的词元或请求数量。"),
        GlossaryEntry(en: "latency", zh: "延迟", explanation: "单次推理请求从输入到生成响应所需的时间。"),
        GlossaryEntry(en: "gradient", zh: "梯度", explanation: "损失函数相对于模型参数的偏导数向量 $\\nabla_\\theta \\mathcal{L}$。"),
        GlossaryEntry(en: "objective", zh: "目标函数", explanation: "模型优化过程中需要最小化或最大化的数学指标。"),
        GlossaryEntry(en: "convergence", zh: "收敛性", explanation: "迭代优化算法逼近局部或全局最优解的性质。")
    ]

    private func matchAcademicGlossary(in text: String) -> [GlossaryEntry] {
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return Self.glossary.filter { item in
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: item.en) + "(?![\\p{L}\\p{N}_])"
            return normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - Native LLM API Configuration Dialog
    func presentSettingsModal(from window: NSWindow?, onSaved: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = "配置划词 AI 翻译 (OpenAI / DeepSeek / Ollama 兼容接口)"
        alert.informativeText = "支持 OpenAI Chat Completions 兼容接口（DeepSeek、OpenAI、Qwen、Kimi 或本地 Ollama）。API Key 留空时读取环境变量；localhost/127.0.0.1 接口可免密钥。未配置服务时仅提供原文摘录摘要和内置词典查询，通用翻译、译写与公式解析需配置可用服务；请求失败会显示错误。"
        alert.addButton(withTitle: "保存设置")
        alert.addButton(withTitle: "填充 DeepSeek 预设")
        alert.addButton(withTitle: "取消")

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 126))

        let epLabel = NSTextField(labelWithString: "API Endpoint:")
        epLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        epLabel.frame = NSRect(x: 0, y: 96, width: 95, height: 20)
        let epField = NSTextField(frame: NSRect(x: 98, y: 94, width: 342, height: 24))
        epField.placeholderString = "https://api.deepseek.com/chat/completions"
        epField.stringValue = endpointURLString

        let keyLabel = NSTextField(labelWithString: "API Key:")
        keyLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        keyLabel.frame = NSRect(x: 0, y: 56, width: 95, height: 20)
        let keyField = NSSecureTextField(frame: NSRect(x: 98, y: 54, width: 342, height: 24))
        keyField.placeholderString = "sk-...（留空读取环境变量；本地接口可免密钥）"
        keyField.stringValue = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""

        let modelLabel = NSTextField(labelWithString: "模型名称:")
        modelLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        modelLabel.frame = NSRect(x: 0, y: 16, width: 95, height: 20)
        let modelField = NSTextField(frame: NSRect(x: 98, y: 14, width: 342, height: 24))
        modelField.placeholderString = "deepseek-chat / gpt-4o-mini / qwen-plus"
        modelField.stringValue = modelName

        box.addSubview(epLabel)
        box.addSubview(epField)
        box.addSubview(keyLabel)
        box.addSubview(keyField)
        box.addSubview(modelLabel)
        box.addSubview(modelField)
        alert.accessoryView = box

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            endpointURLString = epField.stringValue
            apiKey = keyField.stringValue
            modelName = modelField.stringValue
            onSaved?()
        } else if resp == .alertSecondButtonReturn {
            endpointURLString = "https://api.deepseek.com/chat/completions"
            modelName = "deepseek-chat"
            if !keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apiKey = keyField.stringValue
            }
            onSaved?()
        }
    }
}
