import Cocoa
import PDFKit

extension LibraryStore {
    func restoreSamplePapers() {
        seedDefaultSampleLibrary()
        reloadAllPapers()
        notifyChange()
    }

    // MARK: - Seed Rich Sample Library (with Clickable Internal Reference Links!)
    func seedDefaultSampleLibrary() {
        let id1 = "2024_DeepSeek_V3"
        let id2 = "2024_DeepSeekMoE"

        let folder1 = folderURL(for: id1)
        let folder2 = folderURL(for: id2)
        try? FileManager.default.createDirectory(at: folder1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)

        // 生成第 1 篇论文的双语 PDF（带可点击跳转到第 3 页 References 的内部链接！）
        let p1Orig = folder1.appendingPathComponent("original.pdf")
        let p1Trans = folder1.appendingPathComponent("translated_zh.pdf")
        let hasFirst = FileManager.default.fileExists(atPath: folder1.appendingPathComponent("meta.json").path)
        if !hasFirst {
            SamplePaperPDFBuilder.generateDeepSeekV3PDF(isChinese: false, outputURL: p1Orig)
            SamplePaperPDFBuilder.generateDeepSeekV3PDF(isChinese: true, outputURL: p1Trans)
        }

        // 生成第 2 篇关联论文的双语 PDF
        let p2Orig = folder2.appendingPathComponent("original.pdf")
        let p2Trans = folder2.appendingPathComponent("translated_zh.pdf")
        let hasSecond = FileManager.default.fileExists(atPath: folder2.appendingPathComponent("meta.json").path)
        if !hasSecond {
            SamplePaperPDFBuilder.generateDeepSeekMoEPDF(isChinese: false, outputURL: p2Orig)
            SamplePaperPDFBuilder.generateDeepSeekMoEPDF(isChinese: true, outputURL: p2Trans)
        }

        let sampleAnnotations1: [PaperAnnotation] = [
            PaperAnnotation(
                side: .original,
                pageIndex: 0,
                rects: [RectCodable(CGRect(x: 64, y: 530, width: 460, height: 28))],
                selectedText: "We present DeepSeek-V3, a strong Mixture-of-Experts (MoE) language model with 671B total parameters with 37B activated for each token.",
                color: .yellow,
                markdownNote: "**核心参数规模**：总参数量 $671\\text{B}$，每个 Token 仅激活 $37\\text{B}$ 专家参数，稀疏激活比例约为 $\\frac{37}{671} \\approx 5.5\\%$，兼顾大容量与高推理吞吐。",
                linkedURL: "https://github.com/deepseek-ai/DeepSeek-V3",
                linkedTitle: "DeepSeek-V3 GitHub 官方仓库"
            ),
            PaperAnnotation(
                side: .translated,
                pageIndex: 1,
                rects: [RectCodable(CGRect(x: 56, y: 310, width: 480, height: 36))],
                selectedText: "1.3 多词元预测目标 (Multi-Token Prediction, MTP)：我们在训练时让模型在每个位置同时预测未来多个连续词元。",
                color: .green,
                markdownNote: "MTP 的总训练损失由主模型交叉熵与未来 $D$ 个深度的预测损失加权求和构成：\n$$\\mathcal{L}_{MTP} = \\frac{\\lambda}{D} \\sum_{k=1}^{D} \\mathcal{L}_{CE}\\left(P_i^{(k)}, t_{i+1+k}\\right)$$\n既提升了表征密度，又能在推理时直接用于 Speculative Decoding。",
                linkedURL: "paper://\(id2)",
                linkedTitle: "关联论文：DeepSeekMoE 架构详解"
            )
        ]

        let paper1 = PaperItem(
            id: id1,
            title: "DeepSeek-V3 Technical Report",
            authors: "DeepSeek-AI (Aixin Liu, Bei Feng, Bing Xue, et al.)",
            year: "2024",
            venue: "arXiv:2412.19437",
            category: "大模型架构 (LLM)",
            tags: ["MoE", "MLA", "FP8训练", "MTP"],
            isFavorite: true,
            status: .reading,
            originalFilename: "original.pdf",
            translatedFilename: "translated_zh.pdf",
            lastReadPage: 0,
            lastReadScrollProgress: 0.0,
            syncOffsetDelta: 0.0,
            annotations: sampleAnnotations1,
            resources: [
                ExternalResource(title: "GitHub: deepseek-ai/DeepSeek-V3", urlOrPath: "https://github.com/deepseek-ai/DeepSeek-V3", isLocalFile: false),
                ExternalResource(title: "arXiv 原文主页 (2412.19437)", urlOrPath: "https://arxiv.org/abs/2412.19437", isLocalFile: false)
            ],
            relatedPapers: [
                RelatedPaperLink(targetPaperId: id2, relationNote: "核心 MoE 路由架构基础")
            ],
            addedAt: Date(),
            lastOpenedAt: Date()
        )

        let paper2 = PaperItem(
            id: id2,
            title: "DeepSeekMoE: Towards Ultimate Expert Specialization in Mixture-of-Experts",
            authors: "Damai Dai, Chengqi Deng,uxin Zhao, et al.",
            year: "2024",
            venue: "ACL 2024 / arXiv:2401.06066",
            category: "大模型架构 (LLM)",
            tags: ["MoE", "细粒度专家", "共享专家隔离"],
            isFavorite: false,
            status: .unread,
            originalFilename: "original.pdf",
            translatedFilename: "translated_zh.pdf",
            lastReadPage: 0,
            lastReadScrollProgress: 0.0,
            syncOffsetDelta: 0.0,
            annotations: [
                PaperAnnotation(
                    side: .translated,
                    pageIndex: 0,
                    rects: [RectCodable(CGRect(x: 64, y: 470, width: 460, height: 32))],
                    selectedText: "通过细粒度专家分割（Fine-Grained Expert Segmentation）与共享专家隔离（Shared Expert Isolation），显著提升专家特化度。",
                    color: .blue,
                    markdownNote: "第 $l$ 层 MoE 的输出可表示为共享专家与路由专家的组合：\n$$h_t^l = u_t^l + \\sum_{i=1}^{N_s} \\text{FFN}_i^{(s)}(u_t^l) + \\sum_{i=1}^{N_r} g_{i,t} \\text{FFN}_i^{(r)}(u_t^l)$$",
                    linkedURL: nil,
                    linkedTitle: nil
                )
            ],
            resources: [
                ExternalResource(title: "arXiv:2401.06066 主页", urlOrPath: "https://arxiv.org/abs/2401.06066", isLocalFile: false)
            ],
            relatedPapers: [
                RelatedPaperLink(targetPaperId: id1, relationNote: "后续演进：DeepSeek-V3 无辅助损失负载均衡")
            ],
            addedAt: Date().addingTimeInterval(-3600),
            lastOpenedAt: nil
        )

        if !hasFirst { savePaper(paper1, notify: false) }
        if !hasSecond { savePaper(paper2, notify: false) }
    }
}

