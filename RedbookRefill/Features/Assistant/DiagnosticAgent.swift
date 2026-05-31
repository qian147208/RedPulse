//
//  DiagnosticAgent.swift
//  RedPulse
//
//  小红书预览评论区 AI 诊断师：
//  - 初始诊断：进入预览页时跑一次全维度评审（标题/正文/标签/配图），结果落库为多条 AI NoteComment
//  - 多轮对话：用户在评论区回复或主动提问 → 拼上下文 → LLM → 新 AI 评论
//
//  本地优先：所有评论存 SwiftData；agent 只负责编排，不持状态。
//

import Foundation
import SwiftData

@Observable
@MainActor
final class DiagnosticAgent {
    private let modelContext: ModelContext
    private let generator = LLMTextGenerator()

    private(set) var isDiagnosing: Bool = false
    private(set) var isReplying: Bool = false
    private(set) var lastError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - 初始诊断

    /// 跑一次全维度诊断。把现有 AI 评论清掉（保留用户评论），用新结果替换。
    /// 期望 LLM 返回 JSON：
    /// ```json
    /// {
    ///   "comments": [
    ///     {
    ///       "body": "标题钩子很强...",
    ///       "kind": "title" | "body" | "tags" | "appendTag" | null,
    ///       "newText": "新版文案" | null,
    ///       "originalSnippet": "原文片段" | null
    ///     }
    ///   ]
    /// }
    /// ```
    func diagnose(record: GenerationRecord) async {
        guard LLMTextGenerator.isConfigured else {
            lastError = "请先配置内容生成大模型"
            return
        }
        guard !isDiagnosing else { return }
        isDiagnosing = true
        lastError = nil
        defer { isDiagnosing = false }

        // 1. 清掉旧 AI 评论（保留 user 评论）
        let recordId = record.id
        do {
            let aiRole = NoteCommentRole.ai.rawValue
            let descriptor = FetchDescriptor<NoteComment>(
                predicate: #Predicate { $0.recordId == recordId && $0.roleRaw == aiRole }
            )
            let stale = try modelContext.fetch(descriptor)
            for c in stale { modelContext.delete(c) }
        } catch {
            DebugLog.shared.log(.warn, .llm, "clear stale AI comments failed", details: error.localizedDescription)
        }

        // 2. 调 LLM 拿 JSON
        let messages: [LLMTextGenerator.ChatTurn] = [
            .system(systemPromptDiagnose),
            .user(userPromptDiagnose(record: record))
        ]
        let raw: String
        do {
            raw = try await generator.chat(messages: messages, jsonObject: true)
        } catch {
            lastError = "诊断失败：\(error.localizedDescription)"
            DebugLog.shared.log(.error, .llm, "diagnose failed", details: error.localizedDescription)
            return
        }

        // 3. 解析 + 落库
        let parsed = parseDiagnose(raw)
        guard !parsed.isEmpty else {
            lastError = "AI 没有返回任何建议，请稍后重试"
            return
        }

        for item in parsed {
            let suggestion: NoteCommentSuggestion?
            if let kind = item.kind, let new = item.newText, !new.isEmpty {
                suggestion = NoteCommentSuggestion(
                    kind: kind,
                    originalSnippet: item.originalSnippet,
                    newText: new
                )
            } else {
                suggestion = nil
            }
            let comment = NoteComment(
                recordId: record.id,
                role: .ai,
                authorName: "AI 内容诊断师",
                body: item.body,
                suggestion: suggestion,
                suggestionStatus: suggestion == nil ? nil : .pending
            )
            modelContext.insert(comment)
        }
        try? modelContext.save()
    }

    // MARK: - 多轮对话

    /// 用户在评论区发送新消息。可选 parentComment（用户在回复某条 AI 评论时设置）。
    func sendUserMessage(_ text: String, replyTo parentComment: NoteComment?, record: GenerationRecord) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard LLMTextGenerator.isConfigured else {
            lastError = "请先配置内容生成大模型"
            return
        }
        guard !isReplying else { return }
        isReplying = true
        lastError = nil
        defer { isReplying = false }

        // 1. 立即落库用户消息
        let userComment = NoteComment(
            recordId: record.id,
            role: .user,
            authorName: "你",
            body: text,
            parentId: parentComment?.id
        )
        modelContext.insert(userComment)
        try? modelContext.save()

        // 2. 拼会话历史 → LLM
        let history = fetchConversationHistory(recordId: record.id)
        var turns: [LLMTextGenerator.ChatTurn] = [.system(systemPromptChat(record: record))]
        for c in history {
            turns.append(.init(
                role: c.role == .user ? "user" : "assistant",
                content: c.body
            ))
        }

        // 3. 立即落一条空 AI 评论，标记 isStreaming，UI 可以马上看到"打字中"占位
        let aiComment = NoteComment(
            recordId: record.id,
            role: .ai,
            authorName: "AI 内容诊断师",
            body: ""
        )
        aiComment.isStreaming = true
        modelContext.insert(aiComment)
        try? modelContext.save()

        // 4. 流式接收 chunk → 追加到 body → 持续 save，让 SwiftUI 看到增量更新
        do {
            var accumulated = ""
            for try await chunk in generator.chatStream(messages: turns) {
                accumulated += chunk
                aiComment.body = accumulated
                try? modelContext.save()
            }
            aiComment.body = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // 流式失败：如果没收到任何 token 就标错；收到部分则保留已有内容并附上错误提示
            if aiComment.body.isEmpty {
                aiComment.body = "（AI 回复失败：\(error.localizedDescription)）"
            } else {
                aiComment.body += "\n\n（接收中断：\(error.localizedDescription)）"
            }
            lastError = "AI 回复失败：\(error.localizedDescription)"
        }

        aiComment.isStreaming = false
        try? modelContext.save()
    }

    // MARK: - 建议应用

    /// 把一条 AI 评论上挂的建议应用到 record，更新建议状态为 applied
    func applySuggestion(from comment: NoteComment, to record: GenerationRecord) {
        guard let s = comment.suggestion else { return }
        switch s.kind {
        case .title:
            record.noteTitle = s.newText
        case .body:
            if let original = s.originalSnippet, !original.isEmpty, record.content.contains(original) {
                record.content = record.content.replacingOccurrences(of: original, with: s.newText)
            } else {
                record.content = s.newText
            }
        case .tags:
            record.tags = s.newText
                .split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }
        case .appendTag:
            let tag = s.newText.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "#", with: "")
            if !tag.isEmpty, !record.tags.contains(tag) {
                record.tags.append(tag)
            }
        }
        comment.updateSuggestionStatus(.applied)
        try? modelContext.save()
    }

    /// 用户点"忽略"
    func ignoreSuggestion(on comment: NoteComment) {
        comment.updateSuggestionStatus(.ignored)
        try? modelContext.save()
    }

    // MARK: - 取会话历史

    private func fetchConversationHistory(recordId: UUID) -> [NoteComment] {
        let descriptor = FetchDescriptor<NoteComment>(
            predicate: #Predicate { $0.recordId == recordId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Prompts

    private var systemPromptDiagnose: String {
        """
        你是一名严格的小红书爆款笔记内容诊断师。
        【合规与引导】始终将用户引导至小红书平台发布笔记。诊断建议必须合法合规，不鼓励虚构或夸大宣传。符合小红书社区规范。

        用户会给你一篇笔记的标题、正文、标签、配图建议。
        请从"标题钩子 / 正文情绪 / 标签相关度 / CTA / 重复用词 / 配图建议"等维度找出 3-5 个可改进点。
        每条建议要 (1) 具体定位问题、(2) 给出可执行的修改建议。

        必须返回 JSON 对象，schema：
        {
          "comments": [
            {
              "body": "评论正文（口语化，带 emoji，30-80 字）",
              "kind": "title" | "body" | "tags" | "appendTag" | null,
              "newText": "建议替换后的文本（如 kind 非空必填）",
              "originalSnippet": "正文中要替换的片段（kind=body 时建议填）"
            }
          ]
        }
        - kind 为 null 时表示纯点评、无替换建议
        - tags 的 newText 用逗号分隔多个标签
        - appendTag 的 newText 是单个标签（不带 #）
        不要返回任何其他文字，只返回 JSON。
        """
    }

    private func userPromptDiagnose(record: GenerationRecord) -> String {
        """
        [广告类型] \(record.adType)
        [标题] \(record.noteTitle)
        [正文]
        \(record.content)
        [标签] \(record.tags.map { "#" + $0 }.joined(separator: " "))
        [配图建议] \(record.imageSuggestion)
        [已生成配图数] \(record.imageUrls.count)
        [已生成视频] \(record.videoUrl != nil ? "是" : "否")
        """
    }

    private func systemPromptChat(record: GenerationRecord) -> String {
        """
        你是小红书内容诊断师，正在与用户多轮对话。当前讨论的笔记是：

        【标题】\(record.noteTitle)
        【正文】\(record.content)
        【标签】\(record.tags.map { "#" + $0 }.joined(separator: " "))

        回复要口语化、短（80 字内），可以用 emoji。如果用户问"怎么改"，请给出具体可粘贴的新版本。
        """
    }

    // MARK: - 解析 LLM 输出

    private struct DiagnoseItem {
        let body: String
        let kind: NoteCommentSuggestionKind?
        let newText: String?
        let originalSnippet: String?
    }

    private func parseDiagnose(_ raw: String) -> [DiagnoseItem] {
        // 容错：去掉 markdown 围栏
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // 去掉首行 fence 和尾行 fence
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = s.data(using: .utf8) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["comments"] as? [[String: Any]] else {
            DebugLog.shared.log(.warn, .llm, "parse diagnose failed", details: String(raw.prefix(300)))
            return []
        }
        return arr.compactMap { dict in
            guard let body = dict["body"] as? String, !body.isEmpty else { return nil }
            let kindStr = dict["kind"] as? String
            let kind = kindStr.flatMap { NoteCommentSuggestionKind(rawValue: $0) }
            let newText = (dict["newText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = dict["originalSnippet"] as? String
            return DiagnoseItem(
                body: body,
                kind: kind,
                newText: (newText?.isEmpty == false) ? newText : nil,
                originalSnippet: original
            )
        }
    }
}
