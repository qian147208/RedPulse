//
//  DebugLog.swift
//  RedPulse
//
//  全局调试日志收集器（开发者模式可见）。
//
//  设计：
//  - 单例 + @Observable，UI 可观察并实时刷新
//  - 内存 ring buffer，最多保留 500 条，避免长会话内存膨胀
//  - 多线程安全：所有写入都 hop 到 @MainActor
//  - 不写磁盘，App 重启后清空
//
//  用法：
//      DebugLog.shared.info(.llm, "chat completions start", details: "model=\(model)")
//      DebugLog.shared.error(.jimeng, "video failed", details: error.localizedDescription)
//

import Foundation
import Observation

enum DebugLogLevel: String, CaseIterable {
    case debug
    case info
    case warn
    case error

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info:  return "INFO"
        case .warn:  return "WARN"
        case .error: return "ERROR"
        }
    }
}

enum DebugLogCategory: String, CaseIterable {
    case llm        // LLMTextGenerator
    case jimeng     // JimengService / Ark / 火山
    case tester     // LLMTester
    case auth       // AuthStore
    case data       // SwiftData / Repository
    case ui         // UI 交互
    case other

    var label: String {
        switch self {
        case .llm:    return "LLM"
        case .jimeng: return "JIMENG"
        case .tester: return "TESTER"
        case .auth:   return "AUTH"
        case .data:   return "DATA"
        case .ui:     return "UI"
        case .other:  return "OTHER"
        }
    }
}

struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: DebugLogLevel
    let category: DebugLogCategory
    let message: String
    let details: String?

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

@Observable
@MainActor
final class DebugLog {
    static let shared = DebugLog()

    /// 倒序：最新的在 entries[0]。UI 直接遍历即可。
    private(set) var entries: [DebugLogEntry] = []

    /// 内存 buffer 上限。超出后丢最旧。
    private let maxEntries: Int = 500

    private init() {}

    // MARK: - Public API

    func debug(_ category: DebugLogCategory, _ message: String, details: String? = nil) {
        append(level: .debug, category: category, message: message, details: details)
    }

    func info(_ category: DebugLogCategory, _ message: String, details: String? = nil) {
        append(level: .info, category: category, message: message, details: details)
    }

    func warn(_ category: DebugLogCategory, _ message: String, details: String? = nil) {
        append(level: .warn, category: category, message: message, details: details)
    }

    func error(_ category: DebugLogCategory, _ message: String, details: String? = nil) {
        append(level: .error, category: category, message: message, details: details)
    }

    /// Cross-actor safe entry point. Use from non-MainActor contexts.
    nonisolated func log(
        _ level: DebugLogLevel,
        _ category: DebugLogCategory,
        _ message: String,
        details: String? = nil
    ) {
        Task { @MainActor in
            DebugLog.shared.append(level: level, category: category, message: message, details: details)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// 导出当前所有日志为多行文本，用于复制/分享。
    func exportText() -> String {
        // 反向输出（时间正序）方便人读
        let reversed = entries.reversed()
        return reversed.map { e in
            var line = "[\(e.formattedTime)] [\(e.level.label)] [\(e.category.label)] \(e.message)"
            if let d = e.details, !d.isEmpty {
                line += "\n    \(d.replacingOccurrences(of: "\n", with: "\n    "))"
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Private

    private func append(level: DebugLogLevel, category: DebugLogCategory, message: String, details: String?) {
        let entry = DebugLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            details: details
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        // 同步打到 Xcode 控制台
        if let d = details, !d.isEmpty {
            print("[\(entry.formattedTime)] [\(level.label)] [\(category.label)] \(message) | \(d)")
        } else {
            print("[\(entry.formattedTime)] [\(level.label)] [\(category.label)] \(message)")
        }
    }
}
