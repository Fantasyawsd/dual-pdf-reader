import Cocoa
import PDFKit

// MARK: - Sample PDF Builder with Clickable Internal Reference Links
enum SamplePaperPDFBuilder {
    static func generateDeepSeekV3PDF(isChinese: Bool, outputURL: URL) {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        for pageIndex in 1...3 {
            ctx.beginPDFPage(nil)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            NSColor.white.setFill()
            pageRect.fill()

            drawHeader(pageIndex: pageIndex, isChinese: isChinese)
            if pageIndex == 1 {
                drawV3Page1(isChinese: isChinese)
            } else if pageIndex == 2 {
                drawV3Page2(isChinese: isChinese)
            } else {
                drawV3Page3References(isChinese: isChinese)
            }
            drawFooter(pageIndex: pageIndex, total: 3, isChinese: isChinese)

            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()

        // 使用 PDFKit 为生成的 PDF 添加无边框的内部引用跳转链接
        if let doc = PDFDocument(url: outputURL),
           let page1 = doc.page(at: 0),
           let page2 = doc.page(at: 1),
           let page3 = doc.page(at: 2) {

            let noBorder = PDFBorder()
            noBorder.lineWidth = 0

            let destRef1 = PDFDestination(page: page3, at: NSPoint(x: 56, y: 740))
            let link1 = PDFAnnotation(bounds: CGRect(x: 64, y: 342, width: 467, height: 22), forType: .link, withProperties: nil)
            link1.border = noBorder
            link1.color = .clear
            link1.action = PDFActionGoTo(destination: destRef1)
            page1.addAnnotation(link1)

            let link2 = PDFAnnotation(bounds: CGRect(x: 56, y: 90, width: 483, height: 22), forType: .link, withProperties: nil)
            link2.border = noBorder
            link2.color = .clear
            link2.action = PDFActionGoTo(destination: destRef1)
            page2.addAnnotation(link2)

            doc.write(to: outputURL)
        }
    }

    static func generateDeepSeekMoEPDF(isChinese: Bool, outputURL: URL) {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        for pageIndex in 1...2 {
            ctx.beginPDFPage(nil)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            NSColor.white.setFill()
            pageRect.fill()

            drawHeader(pageIndex: pageIndex, isChinese: isChinese)
            let centerPara = NSMutableParagraphStyle()
            centerPara.alignment = .center

            if pageIndex == 1 {
                let title = isChinese
                    ? "DeepSeekMoE：迈向混合专家模型的终极专家特化"
                    : "DeepSeekMoE: Towards Ultimate Expert Specialization in MoE"
                (title as NSString).draw(in: NSRect(x: 56, y: 690, width: 483, height: 34), withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: centerPara
                ])

                let bodyPara = NSMutableParagraphStyle()
                bodyPara.lineSpacing = 6
                let text = isChinese
                    ? """
                    摘要 (Abstract)

                    在混合专家（MoE）架构中，传统做法通常只设置少量（例如 8 个或 16 个）专家，这容易导致知识冗余和专家特化不足。本文提出 DeepSeekMoE 架构，通过细粒度专家分割（Fine-Grained Expert Segmentation）与共享专家隔离（Shared Expert Isolation），显著提升专家特化度。

                    1. 细粒度专家分割：在保持参数量与激活计算量不变的前提下，将每个标准 FFN 专家切分为 m 个更小的专家，并相应增加激活专家数，使组合灵活性呈指数级上升。

                    2. 共享专家隔离：单独固定一部分始终激活的“共享专家”用于捕获通用知识，从而释放其余路由专家专注于特定领域知识。
                    """
                    : """
                    Abstract

                    Conventional Mixture-of-Experts (MoE) architectures typically employ a small number of experts (e.g., 8 or 16), suffering from knowledge hybridity and redundancy. We introduce DeepSeekMoE, featuring Fine-Grained Expert Segmentation and Shared Expert Isolation to achieve ultimate expert specialization.

                    1. Fine-Grained Expert Segmentation: By splitting each intermediate FFN into smaller segments while activating proportionally more experts, combinatorial flexibility increases exponentially.

                    2. Shared Expert Isolation: Dedicating always-active shared experts to capture common knowledge across contexts frees routed experts to specialize without redundancy.
                    """
                (text as NSString).draw(in: NSRect(x: 64, y: 260, width: 467, height: 390), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: bodyPara
                ])
            } else {
                let text = isChinese
                    ? "2. 实验与消融分析\n\n在 2B、16B 及 145B 规模上的对比实验表明，DeepSeekMoE 仅需 40% 的计算量即可达到同规模稠密模型（Dense Model）相当的性能，并直接成为后续 DeepSeek-V2 与 DeepSeek-V3 的核心底座架构。"
                    : "2. Empirical Evaluations & Ablations\n\nExperiments across 2B, 16B, and 145B scales demonstrate that DeepSeekMoE matches dense model performance with only 40% computation, serving as the foundational backbone for DeepSeek-V2 and DeepSeek-V3."
                (text as NSString).draw(in: NSRect(x: 64, y: 460, width: 467, height: 240), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12)
                ])
            }

            drawFooter(pageIndex: pageIndex, total: 2, isChinese: isChinese)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    private static func drawHeader(pageIndex: Int, isChinese: Bool) {
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.38, blue: 0.95, alpha: 1.0)
        ]
        ("🐳 deepseek" as NSString).draw(at: NSPoint(x: 56, y: 778), withAttributes: brandAttrs)

        let line = NSBezierPath()
        line.move(to: NSPoint(x: 56, y: 766))
        line.line(to: NSPoint(x: 539, y: 766))
        line.lineWidth = 0.8
        NSColor.lightGray.setStroke()
        line.stroke()
    }

    private static func drawFooter(pageIndex: Int, total: Int, isChinese: Bool) {
        let footerText = isChinese
            ? "第 \(pageIndex) / \(total) 页  •  划选任意文字可添加高亮、LaTeX 公式笔记或挂载链接"
            : "Page \(pageIndex) of \(total)  •  Select any text to highlight, add Markdown+LaTeX notes, or attach links"
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        (footerText as NSString).draw(in: NSRect(x: 56, y: 24, width: 483, height: 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 9.5),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para
        ])
    }

    private static func drawV3Page1(isChinese: Bool) {
        let centerPara = NSMutableParagraphStyle()
        centerPara.alignment = .center

        let title = isChinese ? "DeepSeek-V3 技术报告" : "DeepSeek-V3 Technical Report"
        (title as NSString).draw(in: NSRect(x: 56, y: 695, width: 483, height: 34), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor.black,
            .paragraphStyle: centerPara
        ])

        ("DeepSeek-AI\nresearch@deepseek.com" as NSString).draw(in: NSRect(x: 56, y: 648, width: 483, height: 38), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: centerPara
        ])

        ("Abstract" as NSString).draw(in: NSRect(x: 56, y: 602, width: 483, height: 22), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.black,
            .paragraphStyle: centerPara
        ])

        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineSpacing = 5
        bodyPara.alignment = .justified

        let abstractText = isChinese
            ? """
            我们介绍了 DeepSeek-V3，一个强大的具有 671B 总参数的 Mixture-of-Experts (MoE) 语言模型，每个词元激活 37B 参数。为了实现高效的推理和具有成本效益的训练，DeepSeek-V3 采用了 Multi-head Latent Attention (MLA) [1] 和 DeepSeekMoE [2] 架构，这些架构在 DeepSeek-V2 中得到了充分验证。此外，DeepSeek-V3 开创了一种无辅助损失的负载均衡策略 [3]，并设定了多词元预测训练目标以获得更强的性能。我们在 14.8 万亿个多样化且高质量的词元上预训练 DeepSeek-V3，随后进行监督微调和强化学习阶段以充分发挥其能力。全面评估表明，DeepSeek-V3 优于其他开源模型，并达到了与领先闭源模型相当的性能。尽管其表现出色，但 DeepSeek-V3 仅需 2.788M H800 GPU 小时即可完成全部训练。
            """
            : """
            We present DeepSeek-V3, a strong Mixture-of-Experts (MoE) language model with 671B total parameters with 37B activated for each token. To achieve efficient inference and cost-effective training, DeepSeek-V3 adopts Multi-head Latent Attention (MLA) [1] and DeepSeekMoE [2] architectures, which were thoroughly validated in DeepSeek-V2. Furthermore, DeepSeek-V3 pioneers an auxiliary-loss-free strategy for load balancing [3] and sets a multi-token prediction training objective for stronger performance. We pre-train DeepSeek-V3 on 14.8 trillion diverse and high-quality tokens, followed by Supervised Fine-Tuning and Reinforcement Learning stages to fully harness its capabilities. Despite its excellent performance, DeepSeek-V3 requires only 2.788M H800 GPU hours for its full training.
            """

        (abstractText as NSString).draw(in: NSRect(x: 64, y: 376, width: 467, height: 215), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11.2),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
            .paragraphStyle: bodyPara
        ])

        let linkTip = isChinese
            ? "参见第 3 页参考文献：[1] DeepSeek-V2 (MLA)   [2] DeepSeekMoE   [3] Auxiliary-Loss-Free Routing"
            : "See References on Page 3: [1] DeepSeek-V2 (MLA)   [2] DeepSeekMoE   [3] Auxiliary-Loss-Free Routing"
        (linkTip as NSString).draw(in: NSRect(x: 64, y: 345, width: 467, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10.0, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.78, alpha: 1.0)
        ])

        drawBenchmarkChart(in: NSRect(x: 68, y: 78, width: 459, height: 245), isChinese: isChinese)
    }

    private static func drawBenchmarkChart(in rect: NSRect, isChinese: Bool) {
        NSColor(calibratedWhite: 0.97, alpha: 1.0).setFill()
        let bg = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        bg.fill()
        NSColor(calibratedWhite: 0.86, alpha: 1.0).setStroke()
        bg.stroke()

        let chartTitle = isChinese
            ? "图 1：DeepSeek-V3 与主流开源/闭源模型基准评测对比 (Accuracy / Percentile %)"
            : "Figure 1: Benchmark performance of DeepSeek-V3 and its counterparts (Accuracy %)"
        (chartTitle as NSString).draw(at: NSPoint(x: rect.minX + 16, y: rect.minY + 12), withAttributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor.darkGray
        ])

        let groups: [(String, [CGFloat])] = [
            ("MMLU-Pro", [75.9, 66.2, 71.6, 73.3, 78.0]),
            ("GPQA-Diamond", [59.1, 41.3, 49.0, 51.1, 65.0]),
            ("MATH 500", [90.2, 74.7, 80.0, 73.8, 78.3]),
            ("Codeforces", [51.6, 35.6, 24.8, 25.3, 23.6])
        ]
        let colors: [NSColor] = [
            NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.96, alpha: 1.0),
            NSColor(calibratedRed: 0.58, green: 0.72, blue: 0.98, alpha: 1.0),
            NSColor(calibratedWhite: 0.72, alpha: 1.0),
            NSColor(calibratedRed: 0.85, green: 0.80, blue: 0.72, alpha: 1.0),
            NSColor(calibratedRed: 0.92, green: 0.86, blue: 0.74, alpha: 1.0)
        ]

        let plotBottom = rect.minY + 46
        let plotHeight: CGFloat = 155
        let groupWidth: CGFloat = 104

        for (gIdx, group) in groups.enumerated() {
            let baseX = rect.minX + 26 + CGFloat(gIdx) * groupWidth
            for (bIdx, val) in group.1.enumerated() {
                let barH = (val / 100.0) * plotHeight
                let barX = baseX + CGFloat(bIdx) * 15
                let barRect = NSRect(x: barX, y: plotBottom, width: 12, height: barH)
                colors[bIdx].setFill()
                barRect.fill()

                if bIdx == 0 {
                    ("\(val)" as NSString).draw(at: NSPoint(x: barX - 2, y: plotBottom + barH + 3), withAttributes: [
                        .font: NSFont.boldSystemFont(ofSize: 7.5),
                        .foregroundColor: NSColor.black
                    ])
                }
            }
            (group.0 as NSString).draw(at: NSPoint(x: baseX + 8, y: plotBottom - 16), withAttributes: [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
                .foregroundColor: NSColor.darkGray
            ])
        }
    }

    private static func drawV3Page2(isChinese: Bool) {
        let heading = isChinese ? "1. 核心架构设计 (Architecture Design)" : "1. Architecture Design & Load Balancing"
        (heading as NSString).draw(at: NSPoint(x: 56, y: 710), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ])

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 6
        para.paragraphSpacing = 14
        para.alignment = .justified

        let content = isChinese
            ? """
            1.1 多头潜在注意力机制 (Multi-head Latent Attention, MLA) [1]
            在推理阶段，标准 Transformer 的键值缓存（KV Cache）往往成为显存瓶颈。DeepSeek-V3 采用低秩联合压缩（Low-Rank Joint Compression）对注意力键（Key）和值（Value）进行压缩，使得推理时只需缓存极小维度的潜在向量 c_t^{KV}，在保证性能不降的前提下显著减少显存占用。

            1.2 无辅助损失负载均衡 (Auxiliary-Loss-Free Load Balancing) [3]
            对于 MoE 模型而言，专家负载不均衡会导致路由崩溃（Routing Collapse）或计算效率下降。传统方案依赖辅助损失函数（Auxiliary Loss），但过强的辅助损失会损害模型性能。DeepSeek-V3 为每个专家引入了一个动态偏置项 b_i，仅在 Top-K 路由选择时加上该偏置 s_{i,t} + b_i，而在计算门控权重时仍使用原始亲和度得分 s_{i,t}，从而实现了零性能损耗的负载均衡。

            1.3 多词元预测目标 (Multi-Token Prediction, MTP)：我们在训练时让模型在每个位置同时预测未来多个连续词元。实验证明，MTP 不仅增强了主模型的综合表征能力，还可直接用于投机采样（Speculative Decoding），使推理生成速度提升约 1.8 倍。
            """
            : """
            1.1 Multi-head Latent Attention (MLA) [1]
            During inference, the Key-Value (KV) cache of standard Transformer architectures often becomes a critical memory bottleneck. DeepSeek-V3 utilizes low-rank joint compression for attention keys and values, caching only a compact latent vector c_t^{KV} during inference while preserving full modeling capacity.

            1.2 Auxiliary-Loss-Free Load Balancing [3]
            For Mixture-of-Experts (MoE) models, unbalanced expert load leads to routing collapse or degraded computational efficiency. Traditional methods rely on auxiliary loss, which often interferes with language modeling gradients. DeepSeek-V3 introduces a dynamic bias term b_i for each expert updated on the fly, achieving balanced routing without any interfering auxiliary loss.

            1.3 Multi-Token Prediction (MTP)
            To densify training signals and enable speculative decoding during inference, DeepSeek-V3 predicts multiple sequential future tokens at each causal position. Empirical evaluations confirm that MTP strengthens representations and accelerates decoding throughput by 1.8x.
            """

        (content as NSString).draw(in: NSRect(x: 56, y: 140, width: 483, height: 555), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
            .paragraphStyle: para
        ])

        let linkTip = isChinese
            ? "参见第 3 页参考文献：[1] Multi-head Latent Attention (MLA)   [3] 无辅助损失动态偏置路由"
            : "See References on Page 3: [1] Multi-head Latent Attention (MLA)   [3] Auxiliary-Loss-Free Routing"
        (linkTip as NSString).draw(in: NSRect(x: 56, y: 94, width: 465, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10.0, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.78, alpha: 1.0)
        ])
    }

    private static func drawV3Page3References(isChinese: Bool) {
        let heading = isChinese ? "参考文献 (References)" : "References"
        (heading as NSString).draw(at: NSPoint(x: 56, y: 710), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ])

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 6
        para.paragraphSpacing = 16

        let refs = isChinese
            ? """
            [1] DeepSeek-AI. (2024). DeepSeek-V2: A Strong, Economical, and Efficient Mixture-of-Experts Language Model. arXiv preprint arXiv:2405.04434. (提出 Multi-head Latent Attention 显存压缩机制)

            [2] Damai Dai, Chengqi Deng, et al. (2024). DeepSeekMoE: Towards Ultimate Expert Specialization in Mixture-of-Experts Language Models. In Proceedings of ACL 2024 / arXiv:2401.06066. (提出细粒度专家分割与共享专家隔离，已关联在本软件文献库中，可在右侧抽屉一键打开！)

            [3] Lean Wang, Huazuo Gao, Chenggang Zhao, Xu Sun, Damai Dai. (2024). Auxiliary-Loss-Free Load Balancing Strategy for Mixture-of-Experts. arXiv preprint arXiv:2408.15664. (提出动态偏置无辅助损失负载均衡算法)

            [4] Vaswani, A., Shazeer, N., Parmar, N., et al. (2017). Attention Is All You Need. In Advances in Neural Information Processing Systems (NeurIPS 2017).
            """
            : """
            [1] DeepSeek-AI. (2024). DeepSeek-V2: A Strong, Economical, and Efficient Mixture-of-Experts Language Model. arXiv preprint arXiv:2405.04434. (Introduced Multi-head Latent Attention for KV cache compression)

            [2] Damai Dai, Chengqi Deng, et al. (2024). DeepSeekMoE: Towards Ultimate Expert Specialization in Mixture-of-Experts Language Models. In Proceedings of ACL 2024 / arXiv:2401.06066. (Linked in your local Paper Library — click Related Papers in the right drawer to open!)

            [3] Lean Wang, Huazuo Gao, Chenggang Zhao, Xu Sun, Damai Dai. (2024). Auxiliary-Loss-Free Load Balancing Strategy for Mixture-of-Experts. arXiv preprint arXiv:2408.15664.

            [4] Vaswani, A., Shazeer, N., Parmar, N., et al. (2017). Attention Is All You Need. In Advances in Neural Information Processing Systems (NeurIPS 2017).
            """

        (refs as NSString).draw(in: NSRect(x: 56, y: 260, width: 483, height: 430), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
            .paragraphStyle: para
        ])
    }
}
