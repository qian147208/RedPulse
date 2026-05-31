//
//  GenerateContracts.swift
//  RedPulse
//
//  Request / response value types and the GeneratorProtocol abstraction.
//  Concrete implementations: MockGenerator (first release) and a future
//  HTTP-backed client.
//

import Foundation

struct GenerateRequest {
    let recordId: UUID
    let keyword: String
    let adType: AdType
    let keywordHint: String?
    let product: Product?
    let images: [Data]       // ≤3 张产品图
    let styleImages: [Data]  // ≤3 张风格图
}

struct GenerateResponse {
    let hotScore: Int          // 后台监控字段, UI 不展示
    let suggestion: String     // 独立卡片展示
    /// 可被标题小模型的输出覆盖（在 LLMTextGenerator.generate 中并行调用后写入）。
    var noteTitle: String
    let content: String
    let tags: [String]
    let imageSuggestion: String
    let imagePrompt: String    // 不展示给用户
    let videoPrompt: String    // 图生视频提示词
    let easterEgg: String

    // 调试用：完整提示词
    var debugTextPrompt: String = ""
}

struct ImageGenResult {
    let imageUrls: [String]
}

struct VideoGenResult {
    let videoUrl: String
}

@MainActor
protocol GeneratorProtocol {
    /// Full generation. Used by G1/G7 (new + 换一批).
    func generate(_ req: GenerateRequest) async throws -> GenerateResponse

    /// 即梦文生图。使用 imagePrompt 生成配图。
    func generateImage(prompt: String, reqKey: String, accessKey: String, secretKey: String) async throws -> ImageGenResult

    /// 即梦文生视频。使用 videoPrompt (或 imagePrompt) 生成短视频。
    func generateVideo(prompt: String, reqKey: String, accessKey: String, secretKey: String) async throws -> VideoGenResult

    /// G8 single-field regenerate (title).
    func regenerateTitle(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?
    ) async throws -> String

    /// G8 single-field regenerate (body).
    func regenerateBody(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?,
        existingTitle: String,
        existingTags: [String]
    ) async throws -> String

    /// G8 single-field regenerate (tags).
    func regenerateTags(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?,
        existingTitle: String,
        existingContent: String
    ) async throws -> [String]

    /// 划词 AI 动作：对选中的文字执行指定操作（润色/改写/扩写/缩写/换风格）。
    func transformText(command: String, selectedText: String, context: String) async throws -> String
}
