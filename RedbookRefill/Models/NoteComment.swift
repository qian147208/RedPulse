//
//  NoteComment.swift
//  灵芯
//
//  小红书预览页评论区数据模型。AI 内容诊断师和用户的多轮对话都落这里。
//  本地优先 · SwiftData 存储 · 绑定到 GenerationRecord。
//

import Foundation
import SwiftData

/// 评论角色
enum NoteCommentRole: String {
    case ai
    case user
}

/// 建议应用状态
enum NoteCommentSuggestionStatus: String {
    case pending   // 待用户选择
    case applied   // 已被采纳应用
    case ignored   // 用户忽略
}

/// AI 建议要替换的字段类型
enum NoteCommentSuggestionKind: String, Codable {
    case title     // 替换 record.noteTitle
    case body      // 替换 record.content
    case tags      // 替换 record.tags（newText 是逗号分隔字符串）
    case appendTag // 追加到 record.tags（newText 是单个标签）
}

/// 建议 payload（序列化为 suggestionJSON 字段）
nonisolated struct NoteCommentSuggestion: Codable {
    var kind: NoteCommentSuggestionKind
    /// 原文片段（可选，用于行内 Diff 高亮，无则全文替换）
    var originalSnippet: String?
    /// 新文（按 kind 不同语义不同）
    var newText: String
}

@Model
final class NoteComment {
    @Attribute(.unique) var id: UUID
    /// 绑定到 GenerationRecord.id
    var recordId: UUID
    /// "ai" | "user"
    var roleRaw: String
    /// 显示名（"AI 内容诊断师" / "你" / 用户自定义昵称）
    var authorName: String
    var body: String
    var createdAt: Date
    /// JSON 序列化的 NoteCommentSuggestion；无建议则 nil
    var suggestionJSON: String?
    /// 建议处理状态：pending / applied / ignored；无建议则 nil
    var suggestionStatusRaw: String?
    /// 多轮对话父评论 ID（用户回复某条 AI 评论时设置）
    var parentId: UUID?

    /// UI-only：标记此评论正在流式接收中（显示打字光标动画）。不持久化。
    @Transient var isStreaming: Bool = false

    init(
        id: UUID = UUID(),
        recordId: UUID,
        role: NoteCommentRole,
        authorName: String,
        body: String,
        createdAt: Date = Date(),
        suggestion: NoteCommentSuggestion? = nil,
        suggestionStatus: NoteCommentSuggestionStatus? = nil,
        parentId: UUID? = nil
    ) {
        self.id = id
        self.recordId = recordId
        self.roleRaw = role.rawValue
        self.authorName = authorName
        self.body = body
        self.createdAt = createdAt
        if let suggestion {
            self.suggestionJSON = (try? JSONEncoder().encode(suggestion))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        self.suggestionStatusRaw = suggestionStatus?.rawValue
        self.parentId = parentId
    }

    // MARK: - Convenience accessors

    var role: NoteCommentRole { NoteCommentRole(rawValue: roleRaw) ?? .ai }

    var suggestion: NoteCommentSuggestion? {
        guard let json = suggestionJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NoteCommentSuggestion.self, from: data)
    }

    var suggestionStatus: NoteCommentSuggestionStatus? {
        guard let raw = suggestionStatusRaw else { return nil }
        return NoteCommentSuggestionStatus(rawValue: raw)
    }

    /// 在评论上写入新的建议状态
    func updateSuggestionStatus(_ status: NoteCommentSuggestionStatus) {
        suggestionStatusRaw = status.rawValue
    }
}
