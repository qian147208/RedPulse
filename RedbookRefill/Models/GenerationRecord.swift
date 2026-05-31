//
//  GenerationRecord.swift
//  RedPulse
//
//  SwiftData model for a single generation result. Fields match
//  requirements V3.2 §4.2. `hotScore` is retained as a backend monitoring
//  field and intentionally not surfaced in the UI.
//

import Foundation
import SwiftData

@Model
final class GenerationRecord: Hashable {
    static func == (lhs: GenerationRecord, rhs: GenerationRecord) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    var id: UUID
    var adType: String           // 广告类型 (AdType.rawValue)
    var inputKeyword: String     // 组合后的实际关键词
    var keywordHint: String?     // 关键词提示(选填, ≤30)
    var productId: UUID?         // 来自产品库时关联

    var noteTitle: String        // 笔记标题
    var content: String          // 正文
    var tags: [String]           // 标签数组
    var imageSuggestion: String  // 配图建议
    var imagePrompt: String      // 增强文生图提示词(英文), 存库但不展示
    var videoPrompt: String      // 图生视频提示词
    var imageUrls: [String]      // 即梦生成的图片 URL
    var videoUrl: String?        // 即梦生成的视频 URL
    var easterEggText: String    // 彩蛋金句
    var hotScore: Int            // 后台质量监控字段, UI 不展示
    var suggestion: String       // 优化建议(独立卡片, 不可编辑)

    var isEdited: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        adType: String,
        inputKeyword: String,
        keywordHint: String? = nil,
        productId: UUID? = nil,
        noteTitle: String,
        content: String,
        tags: [String],
        imageSuggestion: String,
        imagePrompt: String,
        videoPrompt: String = "",
        imageUrls: [String] = [],
        videoUrl: String? = nil,
        easterEggText: String,
        hotScore: Int,
        suggestion: String,
        isEdited: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.adType = adType
        self.inputKeyword = inputKeyword
        self.keywordHint = keywordHint
        self.productId = productId
        self.noteTitle = noteTitle
        self.content = content
        self.tags = tags
        self.imageSuggestion = imageSuggestion
        self.imagePrompt = imagePrompt
        self.videoPrompt = videoPrompt
        self.imageUrls = imageUrls
        self.videoUrl = videoUrl
        self.easterEggText = easterEggText
        self.hotScore = hotScore
        self.suggestion = suggestion
        self.isEdited = isEdited
        self.createdAt = createdAt
    }
}
