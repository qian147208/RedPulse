//
//  ChatSession.swift
//  RedPulse
//
//  全局 AI 助手的多会话模型。每个 ChatSession 代表一次独立对话；
//  实际消息复用 NoteComment 表 —— 把 session.id 当作 recordId 写入。
//
//  本地优先：SwiftData @Model，仅存设备本地。
//

import Foundation
import SwiftData

@Model
final class ChatSession {
    @Attribute(.unique) var id: UUID
    /// 默认 "新对话"；用户发出首条消息后取消息前 20 字
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "新对话",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
