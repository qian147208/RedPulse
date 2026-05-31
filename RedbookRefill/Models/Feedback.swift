//
//  Feedback.swift
//  RedPulse
//
//  SwiftData model for user feedback entries. Fields match requirements
//  V3.2 §4.3.
//

import Foundation
import SwiftData

@Model
final class Feedback {
    var id: UUID
    var content: String          // 反馈文本(≤200 字)
    var imagePaths: [String]     // 反馈截图本地路径(≤3 张)
    var createdAt: Date
    var isSubmitted: Bool        // 是否已发送至后端(默认 false)

    init(
        id: UUID = UUID(),
        content: String,
        imagePaths: [String] = [],
        createdAt: Date = Date(),
        isSubmitted: Bool = false
    ) {
        self.id = id
        self.content = content
        self.imagePaths = imagePaths
        self.createdAt = createdAt
        self.isSubmitted = isSubmitted
    }
}
