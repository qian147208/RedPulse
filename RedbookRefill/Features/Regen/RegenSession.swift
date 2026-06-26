//
//  RegenSession.swift
//  灵芯
//
//  跨 view 生命周期持有"重新生成"任务（文本/图片/视频）：
//  - 任务在 app 顶层注入的 session 实例里跑，view 销毁 task 不丢
//  - 用户在历史/结果页点"重新生成" → 切到别的 tab → 任务在后台继续跑
//  - 完成时把结果写回 SwiftData (record.imageUrls / record.videoUrl / record.noteTitle 等) → 切回时显示
//
//  跟 GenerationSession 的区别：
//  - GenerationSession 处理"从 0 开始的笔记生成"
//  - RegenSession 处理"针对已有 record 的字段/图片/视频重新生成"
//  - 共用 modelContext + 同一份 record 状态
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class RegenSession {
    // MARK: - 配置

    /// 顶层 ModelContainer 的 mainContext — 跨 view 持久，用于 task 内 fetch record 并 save
    let mainContext: ModelContext

    init(mainContext: ModelContext) {
        self.mainContext = mainContext
    }

    // MARK: - 状态（按 recordId 追踪）

    /// 正在重新生成文本的 recordId 集合
    var textJobs: Set<UUID> = []
    /// 正在重新生成图片的 recordId 集合
    var imageJobs: Set<UUID> = []
    /// 正在准备图片 prompts 的 recordId 集合（生成前先扩 prompt）
    var imagePreparingJobs: Set<UUID> = []
    /// 正在重新生成视频的 recordId 集合
    var videoJobs: Set<UUID> = []

    // MARK: - 内部

    /// recordId → Task 句柄（用于取消 / 引用保持）
    private var tasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - 文本重新生成

    /// 启动文本（标题/正文/标签）的重新生成。
    /// - Parameters:
    ///   - recordId: 目标 record id
    ///   - operation: 在闭包里执行实际 LLM 调用 + 写回 record + save（闭包内应自行处理错误）
    func startText(recordId: UUID, operation: @escaping () async -> Void) {
        cancelJob(recordId: recordId)
        textJobs.insert(recordId)
        let task = Task { [weak self] in
            await operation()
            await MainActor.run {
                self?.textJobs.remove(recordId)
                self?.tasks.removeValue(forKey: recordId)
            }
        }
        tasks[recordId] = task
    }

    // MARK: - 图片重新生成

    /// 启动图片重新生成。
    /// - Parameters:
    ///   - recordId: 目标 record id
    ///   - operation: 在闭包里执行扩 prompt + 调图片 API + 写回 record.imageUrls + save
    ///   - preparing: 闭包内如果先扩 prompt，可以调 setPreparing(true/false) 切换"扩 prompt 中"状态
    func startImage(recordId: UUID, operation: @escaping () async -> Void) {
        cancelJob(recordId: recordId)
        imageJobs.insert(recordId)
        let task = Task { [weak self] in
            await operation()
            await MainActor.run {
                self?.imageJobs.remove(recordId)
                self?.imagePreparingJobs.remove(recordId)
                self?.tasks.removeValue(forKey: recordId)
            }
        }
        tasks[recordId] = task
    }

    /// 切换"正在为多张图扩 prompt"状态（不取消 task）
    func setImagePreparing(recordId: UUID, isPreparing: Bool) {
        if isPreparing {
            imagePreparingJobs.insert(recordId)
        } else {
            imagePreparingJobs.remove(recordId)
        }
    }

    // MARK: - 视频重新生成

    /// 启动视频重新生成。
    /// - Parameters:
    ///   - recordId: 目标 record id
    ///   - operation: 闭包内执行视频 API + 写回 record.videoUrl + save
    func startVideo(recordId: UUID, operation: @escaping () async -> Void) {
        cancelJob(recordId: recordId)
        videoJobs.insert(recordId)
        let task = Task { [weak self] in
            await operation()
            await MainActor.run {
                self?.videoJobs.remove(recordId)
                self?.tasks.removeValue(forKey: recordId)
            }
        }
        tasks[recordId] = task
    }

    // MARK: - 取消 / 查询

    /// 取消指定 record 的所有任务
    func cancelJob(recordId: UUID) {
        tasks[recordId]?.cancel()
        tasks.removeValue(forKey: recordId)
        textJobs.remove(recordId)
        imageJobs.remove(recordId)
        imagePreparingJobs.remove(recordId)
        videoJobs.remove(recordId)
    }

    /// 当前是否有任何任务跑着（用于 tab badge 等全局提示）
    var hasAnyJob: Bool {
        !textJobs.isEmpty || !imageJobs.isEmpty || !videoJobs.isEmpty
    }

    func isTextRunning(recordId: UUID) -> Bool { textJobs.contains(recordId) }
    func isImageRunning(recordId: UUID) -> Bool { imageJobs.contains(recordId) }
    func isImagePreparing(recordId: UUID) -> Bool { imagePreparingJobs.contains(recordId) }
    func isVideoRunning(recordId: UUID) -> Bool { videoJobs.contains(recordId) }

    /// 通过 recordId 重新 fetch record（任务闭包内使用，绕过 view-scoped state）
    func fetchRecord(id: UUID) -> GenerationRecord? {
        let descriptor = FetchDescriptor<GenerationRecord>(predicate: #Predicate { $0.id == id })
        return (try? mainContext.fetch(descriptor))?.first
    }
}
