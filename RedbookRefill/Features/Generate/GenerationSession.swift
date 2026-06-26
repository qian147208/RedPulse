//
//  GenerationSession.swift
//  灵芯
//
//  跨 view 生命周期持有"生成页"的所有状态：
//  - 表单 state（keyword / hintText / selectedProduct / 选中 chip 集合...）
//  - LLM 拉的 chip 列表（trendingKeywords / hintChips）
//  - 加载状态 / trigger / UI 临时状态（picker / 折叠 section）
//  - 任务状态（isGenerating / task / generatedRecord / error）
//
//  为什么需要 session？
//  旧设计：这些全是 @State，view-scoped。切到别的 tab → GenerateView 销毁
//  → 所有 @State 清空 → 切回来表单空空，任务引用丢失。
//
//  新设计：所有状态都搬到 @Observable 的 session 里，app 顶层注入。
//  切到任何 tab 都不丢，切回来表单完整、任务继续在后台跑。
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class GenerationSession {
    // MARK: - 表单状态（用户填的 + 用户选的）

    /// 选中的广告类型
    var selectedAdType: AdType = .feedAd
    /// 用户填的关键词（产品关键词）
    var keyword: String = ""
    /// 用户填的风格提示
    var hintText: String = ""
    /// 选中的产品
    var selectedProduct: Product? = nil
    /// 03 LLM chip 选中集合（精确 token 追踪）
    var selectedTrendingChips: Set<String> = []
    /// 04 LLM chip 选中集合
    var selectedHintChips: Set<String> = []
    /// 折叠的 section 集合
    var collapsedSections: Set<String> = []

    // MARK: - LLM 拉的 chip 列表（跨 view 持久 — 切 tab 不丢）

    /// 03 热门关键词列表（LLM 拉的 + 用户已选钉在最前）
    var trendingKeywords: [String] = []
    /// 04 风格 chip 列表
    var hintChips: [String] = [
        "测评向", "干货风", "轻松搞笑", "好物分享",
        "真实体验", "干货科普", "问号钩子", "避雷指南"
    ]

    // MARK: - 加载状态

    var isLoadingTrending: Bool = false
    var isLoadingHints: Bool = false

    // MARK: - 一次性 trigger（onChange 监听 +1 触发 LLM 拉取）

    var trendingKeywordsToken: Int = 0
    var refreshHintsToken: Int = 0

    // MARK: - UI 临时状态

    var showInspirationPicker: Bool = false
    var inspirationPickerType: InspirationType = .keyword

    // MARK: - 任务状态

    /// 是否正在生成（按钮 disabled 用）
    var isGenerating: Bool = false

    /// 进度文案
    var progressMessage: String = ""

    /// LLM 流式已收到的字符数（实时增长，让 UI 显示真实进度百分比）
    var receivedChars: Int = 0
    /// 目标字符数（用于计算百分比），根据 adType 估算
    var targetChars: Int = 1000
    /// 当前阶段（"调用标题模型" / "撰写正文" / "解析 JSON"）
    var currentStage: String = ""

    /// 当前生成完成的结果（赋值后 GenerateView 跳到 ResultView）
    var generatedRecord: GenerationRecord?

    /// 是否显示错误弹窗
    var showError: Bool = false

    /// 错误文案
    var errorMessage: String?

    // MARK: - 内部

    /// 真正的生成 task — 不暴露给外部，只用 startGeneration / cancel 控制
    private var task: Task<Void, Never>?

    // MARK: - 启动生成

    /// 启动一次新的生成任务。如果有未完成的任务先取消。
    /// - Parameters:
    ///   - request: 生成请求
    ///   - generator: 用哪个 generator（真实 LLM 或 Mock）
    ///   - modelContext: 写入 GenerationRecord 用的 SwiftData context
    func startGeneration(
        request: GenerateRequest,
        generator: GeneratorProtocol,
        modelContext: ModelContext
    ) {
        // 防止上一个任务没完成用户又点了一次 → 先取消
        cancel()

        isGenerating = true
        progressMessage = "正在生成..."
        receivedChars = 0
        currentStage = "准备中"
        showError = false
        errorMessage = nil

        // 在 task 闭包外捕获需要用到的值（避免 view 销毁后引用丢失）
        let capturedKeyword = request.keyword
        let capturedAdType = request.adType
        let capturedHint = request.keywordHint
        let capturedProductId = request.product?.id
        let usingReal = (generator is LLMTextGenerator)

        // 按 adType 估算目标字符数：种草向偏短 / 测评向偏长
        // 用于计算流式进度百分比（receivedChars / targetChars）
        targetChars = Self.estimateTargetChars(for: capturedAdType)

        DebugLog.shared.info(
            .llm,
            "startGeneration",
            details: """
            generator=\(usingReal ? "LLMTextGenerator" : "MockGenerator")
            adType=\(capturedAdType.displayName)
            keyword=\(capturedKeyword)
            hint=\(capturedHint ?? "(none)")
            product=\(request.product?.name ?? "(none)")
            targetChars=\(targetChars)
            """
        )

        task = Task { [weak self] in
            do {
                currentStage = "正在生成文案"
                progressMessage = "正在生成文案"
                let response = try await generator.generateStream(request) { [weak self] chars in
                    // LLM 流式回调：实时更新进度
                    self?.receivedChars = chars
                    self?.progressMessage = "撰写中…（\(chars)/\(self?.targetChars ?? 1000) 字）"
                }
                try Task.checkCancellation()
                currentStage = "解析结果"
                progressMessage = "解析结果"

                let record = GenerationRecord(
                    adType: capturedAdType.rawValue,
                    inputKeyword: capturedKeyword,
                    keywordHint: capturedHint,
                    productId: capturedProductId,
                    noteTitle: response.noteTitle,
                    content: response.content,
                    tags: response.tags,
                    imageSuggestion: response.imageSuggestion,
                    imagePrompt: response.imagePrompt,
                    videoPrompt: response.videoPrompt,
                    easterEggText: response.easterEgg,
                    hotScore: response.hotScore,
                    suggestion: response.suggestion
                )

                self?.finishWithSuccess(response: response, record: record, modelContext: modelContext)
            } catch is CancellationError {
                self?.finishWithCancel()
                DebugLog.shared.log(.warn, .llm, "generate cancelled by user")
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                self?.finishWithCancel()
                DebugLog.shared.log(.warn, .llm, "generate cancelled (URLSession)")
            } catch {
                let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DebugLog.shared.log(.error, .llm, "generate pipeline failed", details: raw)
                let friendly = GenerationHelpers.friendlyErrorMessage(raw: raw, error: error)
                self?.finishWithError(message: friendly)
            }
        }
    }

    // MARK: - 取消

    func cancel() {
        task?.cancel()
        task = nil
        isGenerating = false
        progressMessage = ""
    }

    // MARK: - 清除结果（用户从 ResultView 返回生成页时调用）

    func clearResult() {
        generatedRecord = nil
    }

    // MARK: - 私有完成回调（@MainActor 内更新 UI 状态）

    private func finishWithSuccess(
        response: GenerateResponse,
        record: GenerationRecord,
        modelContext: ModelContext
    ) {
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            DebugLog.shared.log(.error, .llm, "modelContext.save() failed", details: error.localizedDescription)
        }
        task = nil
        isGenerating = false
        progressMessage = ""
        generatedRecord = record
        DebugLog.shared.log(
            .info, .llm,
            "generation complete",
            details: "title=\(response.noteTitle) id=\(record.id)"
        )
    }

    private func finishWithCancel() {
        task = nil
        isGenerating = false
        progressMessage = ""
    }

    private func finishWithError(message: String) {
        task = nil
        isGenerating = false
        progressMessage = ""
        currentStage = ""
        receivedChars = 0
        errorMessage = message
        showError = true
    }

    // MARK: - 辅助

    /// 按广告类型估算目标字符数 ——
    /// - 真实 LLM 输出的是完整 JSON（含 title/content/tags/imagePrompt 等），典型 800-1500 字符
    /// - 不同 adType 的 content 长度差异不大，统一用 1000 作为分母
    /// - 真实进度 = receivedChars / 1000，最大 99%（完成时跳到 100%）
    private static func estimateTargetChars(for adType: AdType) -> Int {
        return 1000
    }
}
