//
//  LocalAssetMigrator.swift
//  RedbookRefill
//
//  启动时一次性迁移：把 SwiftData 历史数据里的远程图片/视频 URL 下载到本地。
//  旧代码生成的 `record.imageUrls` / `record.videoUrl` 可能是裸的 https URL，
//  24h 后用户看到空图/空视频。启动时把它们都下到本地 → 写回 SwiftData。
//
//  通过 `@AppStorage("local_asset_migration_v2_done")` flag 防重复跑。
//  升级 schema 时把 flag 改成新 key（v1 → v2）即可强制重跑。
//

import Foundation
import SwiftData

@MainActor
enum LocalAssetMigrator {
    /// 是否是远程 URL（不是 file:// 也不是空）
    private static func isRemote(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = URL(string: trimmed) else { return false }
        return !u.isFileURL
    }

    private static let flagKey = "local_asset_migration_v2_done"

    /// App 启动时调用一次。已跑过 → 立即返回。
    static func runIfNeeded(modelContext: ModelContext) async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: flagKey) { return }

        DebugLog.shared.info(.data, "local asset migration: start")

        let descriptor = FetchDescriptor<GenerationRecord>()
        guard let records = try? modelContext.fetch(descriptor) else {
            DebugLog.shared.error(.data, "migration fetch failed")
            return
        }

        var totalImages = 0
        var totalVideos = 0
        var convertedImages = 0
        var convertedVideos = 0

        for record in records {
            // 图片
            let remoteImages = record.imageUrls.filter { isRemote($0) }
            if !remoteImages.isEmpty {
                totalImages += remoteImages.count
                let locals = await LocalAssetStore.downloadAll(remoteImages, kind: .image)
                let merged = zip(record.imageUrls, locals).map { orig, local in local ?? orig }
                let localCount = locals.compactMap { $0 }.count
                convertedImages += localCount
                record.imageUrls = merged
            }
            // 视频
            if let v = record.videoUrl, isRemote(v) {
                totalVideos += 1
                if let local = await LocalAssetStore.downloadIfNeeded(remoteURL: v, kind: .video) {
                    record.videoUrl = local
                    convertedVideos += 1
                }
            }
        }

        do {
            try modelContext.save()
            DebugLog.shared.info(.data, "local asset migration: done",
                details: "images=\(convertedImages)/\(totalImages), videos=\(convertedVideos)/\(totalVideos), records=\(records.count)")
        } catch {
            DebugLog.shared.error(.data, "migration save failed", details: error.localizedDescription)
        }

        defaults.set(true, forKey: flagKey)
    }
}
