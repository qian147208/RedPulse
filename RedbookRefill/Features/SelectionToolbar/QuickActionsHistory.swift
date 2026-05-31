//
//  QuickActionsHistory.swift
//  RedPulse
//
//  Lightweight history store for AI quick actions performed via the
//  selection toolbar. Stored in UserDefaults (last 20 records).
//  No complex database — just a simple ring buffer in JSON.
//

import Foundation
import Observation

// MARK: - QuickAction enum

enum QuickAction: String, CaseIterable, Codable {
    case translate  // 翻译
    case explain    // 解释
    case summarize  // 总结
    case rewrite    // 改写
    case shorter    // 更短
    case longer     // 更详细
    case custom     // 自定义指令

    var displayName: String {
        switch self {
        case .translate: "翻译"
        case .explain:   "解释"
        case .summarize: "总结"
        case .rewrite:   "改写"
        case .shorter:   "更短"
        case .longer:    "更详细"
        case .custom:    "自定义"
        }
    }

    var icon: String {
        switch self {
        case .translate: "globe"
        case .explain:   "text.magnifyingglass"
        case .summarize: "text.alignleft"
        case .rewrite:   "sparkles"
        case .shorter:   "text.badge.minus"
        case .longer:    "text.badge.plus"
        case .custom:    "ellipsis.circle"
        }
    }

    /// The system prompt instruction fragment sent to the LLM for this action.
    var llmInstruction: String {
        switch self {
        case .translate: "请将以下文本翻译为中文，只输出译文："
        case .explain:   "请用通俗易懂的语言解释以下内容，让完全不了解的人也能听懂："
        case .summarize: "请用1-3句话总结以下内容的核心要点："
        case .rewrite:   "请改写以下文本，保持原意但让表达更流畅自然："
        case .shorter:   "请将以下文本压缩至原长度的一半左右，保留核心意思："
        case .longer:    "请将以下文本扩展得更详细，增加具体的细节和例子："
        case .custom:    "" // Custom instruction provided by user
        }
    }
}

// MARK: - History record

struct QuickActionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let action: QuickAction
    let originalText: String
    let resultText: String
    let timestamp: Date

    init(action: QuickAction, originalText: String, resultText: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.action = action
        self.originalText = originalText
        self.resultText = resultText
        self.timestamp = timestamp
    }
}

// MARK: - History store

@Observable
final class QuickActionsHistory {
    private static let maxRecords = 20
    private static let storageKey = "selection_toolbar.history"

    private(set) var records: [QuickActionRecord] = []

    init() {
        load()
    }

    func addRecord(_ record: QuickActionRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    /// Replay a previous action: returns the original text so the user can
    /// re-run the same action on it.
    func replay(_ record: QuickActionRecord) -> (action: QuickAction, text: String) {
        (record.action, record.originalText)
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([QuickActionRecord].self, from: data)
        else { return }
        records = decoded
    }
}

// MARK: - Intent Guesser

/// Simple heuristic to guess which quick action the user most likely wants.
enum IntentGuesser {
    /// Returns the recommended action for a given selected text.
    static func guess(for text: String) -> QuickAction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rewrite }

        // If text contains significant non-Chinese characters → translation
        let nonChineseCount = trimmed.unicodeScalars.filter { scalar in
            !(0x4E00...0x9FFF).contains(scalar.value)  // CJK Unified Ideographs
            && !(0x3400...0x4DBF).contains(scalar.value) // CJK Ext-A
            && !(0x3000...0x303F).contains(scalar.value) // CJK punctuation
            && scalar != " " && scalar != "\n"
        }.count
        let totalChars = trimmed.unicodeScalars.filter { $0 != " " && $0 != "\n" }.count

        if totalChars > 0 && Double(nonChineseCount) / Double(totalChars) > 0.4 {
            return .translate
        }

        // Very short (< 20 chars) → explain
        if trimmed.count < 20 {
            return .explain
        }

        // Long (> 200 chars) → summarize
        if trimmed.count > 200 {
            return .summarize
        }

        // Default → rewrite
        return .rewrite
    }
}
