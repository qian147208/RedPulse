//
//  InspirationItem.swift
//  RedPulse
//
//  灵感板数据模型：收藏笔记片段、关键词、风格提示，供生成时复用。
//

import Foundation
import SwiftData

/// 灵感条目类型
enum InspirationType: String, CaseIterable, Identifiable {
    case snippet = "snippet"   // 笔记片段（标题/正文/标签）
    case keyword = "keyword"   // 关键词
    case style   = "style"     // 风格提示

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .snippet: "片段"
        case .keyword: "关键词"
        case .style:   "风格"
        }
    }

    var icon: String {
        switch self {
        case .snippet: "doc.text"
        case .keyword: "text.magnifyingglass"
        case .style:   "paintbrush"
        }
    }
}

@Model
final class InspirationItem {
    var id: UUID
    var type: String          // InspirationType.rawValue
    var title: String         // 显示标题（content 前 20 字）
    var content: String       // 实际内容
    var source: String?       // 来源标记（如 "历史记录:xxx"）
    var createdAt: Date

    init(type: InspirationType, content: String, source: String? = nil) {
        self.id = UUID()
        self.type = type.rawValue
        self.content = content
        self.title = String(content.prefix(20))
        self.source = source
        self.createdAt = Date()
    }

    /// 类型枚举值
    var inspirationType: InspirationType? {
        InspirationType(rawValue: type)
    }
}
