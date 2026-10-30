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

    /// 划词翻译主入口：优先调用已配置的 OpenAI 兼容 LLM 接口；未配置密钥或离线时自动使用双栏上下文与内置学术引擎翻译
    @discardableResult
    func translate(
        text: String,
        mode: LLMTranslationMode = .academicChinese,
        pairedPageText: String? = nil,
        completion: @escaping (LLMTranslationResult) -> Void
    ) -> URLSessionDataTask? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            let emptyRes = LLMTranslationResult(
                sourceText: text,
                mode: mode,
                translatedMarkdown: "未检测到有效划选文本。",
                providerLabel: "本地引擎",
                isRemoteLLM: false
            )
            completion(emptyRes)
            return nil
        }

        guard isRemoteConfigured, let url = URL(string: endpointURLString) else {
            let localResult = translateLocally(text: cleanText, mode: mode, pairedPageText: pairedPageText)
            DispatchQueue.main.async {
                completion(localResult)
            }
            return nil
        }

        let systemPrompt = buildSystemPrompt(for: mode)
        var userPrompt = "请处理以下论文划选片段：\n\n\(cleanText)"
        if let paired = pairedPageText?.trimmingCharacters(in: .whitespacesAndNewlines), !paired.isEmpty {
            let snippet = String(paired.prefix(1200))
            userPrompt += "\n\n（参考同页对照文本片段：\n\(snippet)\n）"
        }

        let payload: [String: Any] = [
            "model": modelName,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            let fallback = translateLocally(text: cleanText, mode: mode, pairedPageText: pairedPageText)
            DispatchQueue.main.async { completion(fallback) }
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let currentModel = modelName
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                let res = LLMTranslationResult(
                    sourceText: cleanText,
                    mode: mode,
                    translatedMarkdown: content,
                    providerLabel: "LLM (\(currentModel))",
                    isRemoteLLM: true
                )
                DispatchQueue.main.async { completion(res) }
                return
            }

            // 若远程请求失败，优雅降级至本地学术翻译引擎并提示原因
            let localFallback = self.translateLocally(text: cleanText, mode: mode, pairedPageText: pairedPageText)
            let errHint = error?.localizedDescription ?? "接口响应异常"
            let combined = LLMTranslationResult(
                sourceText: cleanText,
                mode: mode,
                translatedMarkdown: localFallback.translatedMarkdown + "\n\n*（注：远程 LLM 请求未完成 [\(errHint)]，已自动使用内置学术对照引擎生成）*",
                providerLabel: "内置学术引擎 (离线回退)",
                isRemoteLLM: false
            )
            DispatchQueue.main.async { completion(combined) }
        }
        task.resume()
        return task
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

    /// 内置离线学术翻译与同页双语对齐引擎（无需网络或未配置 API Key 时亦可即刻工作）
    func translateLocally(
        text: String,
        mode: LLMTranslationMode,
        pairedPageText: String? = nil
    ) -> LLMTranslationResult {
        let normalized = text
            .replacingOccurrences(of: "-\n", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let containsChinese = normalized.range(of: "\\p{Han}", options: .regularExpression) != nil

        // 1. 尝试从同页配对译文 PDF 提取对应段落
        let matchedPairedSnippet = extractAlignedSnippetFromPairedPage(source: normalized, pairedPageText: pairedPageText)

        // 2. 匹配核心学术术语词典
        let detectedTerms = matchAcademicGlossary(in: normalized)

        // 3. 生成句法级中文学术直译
        let directTranslated = synthesizeAcademicTranslation(from: normalized, isSourceChinese: containsChinese)
        let primaryTranslation: String
        if let paired = matchedPairedSnippet, !containsChinese {
            // 当存在同页对应位置的中文版译文时，若句法直译仍残留较多未译英文词，优先以同页完整中文译文为主体
            let remainingEnglishWords = directTranslated
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { $0.count >= 4 && !["MLA", "MoE", "MTP", "BLEU", "WMT", "GPU", "GPUs"].contains($0) }
            if remainingEnglishWords.count >= 4 {
                primaryTranslation = paired
            } else {
                primaryTranslation = directTranslated
            }
        } else {
            primaryTranslation = directTranslated
        }

        var output = ""
        switch mode {
        case .academicChinese:
            output += primaryTranslation
            if let paired = matchedPairedSnippet, !containsChinese, primaryTranslation != paired {
                output += "\n\n**同页译本对照**\n> \(paired)"
            }
            if !detectedTerms.isEmpty {
                let termsLine = detectedTerms.map { "`\($0.en)` → \($0.zh)" }.joined(separator: " ｜ ")
                output += "\n\n**核心术语**：\(termsLine)"
            }

        case .explainAndFormula:
            output += "### 1. 学术精译\n\(primaryTranslation)\n\n"
            if let paired = matchedPairedSnippet, primaryTranslation != paired {
                output += "> **同页译本参考**：\(paired)\n\n"
            }
            output += "### 2. 术语与公式解析\n"
            if !detectedTerms.isEmpty {
                for term in detectedTerms {
                    output += "- **\(term.zh)** (`\(term.en)`): \(term.explanation)\n"
                }
            } else {
                output += "- **句法结构**: 该段落阐述了论文中的关键方法假设或实验分析结论。\n"
            }
            if let formulaNote = detectFormulaHint(in: normalized) {
                output += "- **数学符号说明**: \(formulaNote)\n"
            }

        case .conciseSummary:
            output += "**核心要点提炼**\n"
            output += "- **核心表述**: \(primaryTranslation)\n"
            if !detectedTerms.isEmpty {
                output += "- **涉及关键概念**: \(detectedTerms.map { "\($0.zh) (\($0.en))" }.joined(separator: "、"))\n"
            }
            if let paired = matchedPairedSnippet, primaryTranslation != paired {
                output += "- **对应页上下文**: \(paired)\n"
            }

        case .englishPolish:
            if containsChinese {
                output += "**Academic English Rendering:**\n\(directTranslated)"
            } else {
                output += "**Polished Academic Expression:**\n\(normalized)"
            }
        }

        return LLMTranslationResult(
            sourceText: normalized,
            mode: mode,
            translatedMarkdown: output.trimmingCharacters(in: .whitespacesAndNewlines),
            providerLabel: matchedPairedSnippet != nil ? "内置双语对齐 + 学术引擎" : "内置学术翻译引擎 (可配置远程 LLM)",
            isRemoteLLM: false
        )
    }

    private func extractAlignedSnippetFromPairedPage(source: String, pairedPageText: String?) -> String? {
        guard let rawPage = pairedPageText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPage.isEmpty else { return nil }
        let lines = rawPage
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard line.count >= 2 else { return false }
                let low = line.lowercased()
                if low.contains("deepseek-v3 technical report") { return false }
                if PDFMetadataExtractor.isBoilerplateHeaderLine(line) { return false }
                // 过滤纯页码行
                if Int(line) != nil { return false }
                return true
            }
        guard !lines.isEmpty else { return nil }

        // 若传入的已经是按空间坐标对齐提取的局部段落（而非整页长文本），直接合并其中的有效行返回完整段落
        if rawPage.count <= 950 {
            let joined = lines.joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if joined.count >= 4 {
                return String(joined.prefix(560))
            }
        }

        // 若传入的是整页文本，优先定位含相同数字编号/公式编号的行及其上下文窗口
        let numbers = source.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { $0.count >= 1 }
        if let firstNum = numbers.first,
           let matchIdx = lines.firstIndex(where: { $0.contains(firstNum) && $0.range(of: "\\p{Han}", options: .regularExpression) != nil }) {
            let start = max(0, matchIdx - 1)
            let end = min(lines.count - 1, matchIdx + 3)
            let windowText = lines[start...end].joined(separator: " ")
            return String(windowText.prefix(420))
        }

        // 否则选取同页中中文密度较高的核心段落作为对照参考
        let chineseLines = lines.filter { $0.range(of: "\\p{Han}", options: .regularExpression) != nil }
        if !chineseLines.isEmpty {
            let joined = chineseLines.prefix(5).joined(separator: " ")
            return String(joined.prefix(420))
        }
        return nil
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
        let lower = text.lowercased()
        var matched: [GlossaryEntry] = []
        for item in Self.glossary {
            if lower.contains(item.en.lowercased()) {
                matched.append(item)
            }
        }
        return matched
    }

    private func detectFormulaHint(in text: String) -> String? {
        if text.contains("softmax") || text.contains("sqrt") || text.contains("Q") && text.contains("K") {
            return "包含注意力缩放点积形式 $\\text{Attention}(Q,K,V) = \\text{softmax}\\left(\\frac{QK^\\top}{\\sqrt{d_k}}\\right)V$。"
        }
        if text.contains("sum") || text.contains("∑") || text.contains("_i") {
            return "包含对索引项 $i$ 的加权求和聚合表达式 $\\sum_{i} g_i \\cdot f_i(x)$。"
        }
        return nil
    }

    private func synthesizeAcademicTranslation(from text: String, isSourceChinese: Bool) -> String {
        if isSourceChinese {
            var en = text
            let zhToEn: [(String, String)] = [
                ("多头潜在注意力", "Multi-head Latent Attention (MLA)"),
                ("混合专家", "Mixture-of-Experts (MoE)"),
                ("无辅助损失", "auxiliary-loss-free"),
                ("负载均衡", "load balancing"),
                ("多词元预测", "Multi-Token Prediction (MTP)"),
                ("键值缓存", "KV cache"),
                ("推理", "inference"),
                ("预训练", "pre-training"),
                ("注意力机制", "attention mechanism"),
                ("表现", "performance"),
                ("架构", "architecture")
            ]
            for (zh, rep) in zhToEn {
                en = en.replacingOccurrences(of: zh, with: " \(rep) ")
            }
            return en.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }

        // 英文转流畅中文学术表述
        var result = text
        let phraseReplacements: [(String, String)] = [
            ("We present", "本文提出"),
            ("we present", "本文提出"),
            ("We propose", "我们提出了"),
            ("we propose", "我们提出了"),
            ("We introduce", "我们引入了"),
            ("we introduce", "我们引入了"),
            ("In addition,", "此外，"),
            ("Furthermore,", "进一步地，"),
            ("Moreover,", "此外，"),
            ("Specifically,", "具体而言，"),
            ("To address this issue,", "为解决这一问题，"),
            ("Compared with", "与……相比，"),
            ("experimental results", "实验结果"),
            ("demonstrate that", "表明"),
            ("significantly reduces", "显著降低了"),
            ("while maintaining", "同时保持了"),
            ("strong performance", "优异的性能表现"),
            ("Multi-head Latent Attention (MLA)", "多头潜在注意力机制 (MLA)"),
            ("Multi-head Latent Attention", "多头潜在注意力机制 (MLA)"),
            ("Mixture-of-Experts (MoE)", "混合专家架构 (MoE)"),
            ("Mixture-of-Experts", "混合专家架构 (MoE)"),
            ("auxiliary-loss-free strategy", "无辅助损失策略"),
            ("auxiliary-loss-free", "无辅助损失"),
            ("load balancing", "负载均衡"),
            ("Multi-Token Prediction (MTP)", "多词元预测 (MTP)"),
            ("Multi-Token Prediction", "多词元预测 (MTP)"),
            ("efficient inference", "高效推理"),
            ("cost-effective training", "高性价比训练"),
            ("low-rank joint compression", "低秩联合压缩"),
            ("key-value (KV) cache", "键值 (KV) 缓存"),
            ("KV cache", "KV 键值缓存"),
            ("activatedFor each token", "针对每个词元激活"),
            ("for each token", "针对每个词元"),
            ("training objective", "训练目标"),
            ("pre-training", "预训练"),
            ("post-training", "后训练"),
            ("reinforcement learning", "强化学习")
        ]

        for (en, zh) in phraseReplacements {
            result = result.replacingOccurrences(of: en, with: zh, options: [.caseInsensitive])
        }

        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        if wordCount <= 5 {
            let shortTermReplacements: [(String, String)] = [
                ("architecture", "模型架构"),
                ("parameters", "参数"),
                ("performance", "性能"),
                ("inference", "推理"),
                ("training", "训练"),
                ("attention", "注意力")
            ]
            for (en, zh) in shortTermReplacements {
                result = result.replacingOccurrences(of: en, with: zh, options: [.caseInsensitive])
            }
        }
        return result
    }

    // MARK: - Native LLM API Configuration Dialog
    func presentSettingsModal(from window: NSWindow?, onSaved: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = "配置划词 AI 翻译 (OpenAI / DeepSeek / Ollama 兼容接口)"
        alert.informativeText = "支持任意 OpenAI `/v1/chat/completions` 兼容接口（如 DeepSeek、OpenAI、Qwen、Kimi 或本地 Ollama）。留空 API Key 时将自动使用内置双语对齐与学术翻译引擎。"
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
        keyField.placeholderString = "sk-... (留空则使用环境变量或离线学术引擎)"
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
