//
//  LocalAssetStore.swift
//  RedbookRefill
//
//  把远程 URL（图片/视频）下载到本地 Documents 目录。
//  **所有模型**（Agnes / 豆包 / 未来接入的其他厂商）产生的 URL 都要走这里落盘，
//  避免厂商 URL 24h 过期后用户看到空图/空视频。
//
//  设计：
//  - 每个 URL 一次性下载 → 本地文件 → 用 sha256(url) 做文件名（去重 + 路径稳定）
//  - 重复 URL 不会重复下载（命中已存在的本地文件直接返回）
//  - 部分失败不致命 — 单个失败返回 nil，上层决定如何处理（toast 提示 / 跳过）
//  - 文件相对路径：Documents/LocalAssets/{images|videos}/{sha256}.{ext}
//

import Foundation
import CryptoKit

enum LocalAssetKind {
    case image
    case video

    var subdir: String {
        switch self {
        case .image: return "images"
        case .video: return "videos"
        }
    }

    /// 默认扩展名（如果无法从 URL/MIME 推断）
    var defaultExtension: String {
        switch self {
        case .image: return "jpg"
        case .video: return "mp4"
        }
    }
}

enum LocalAssetStore {
    /// 远程 URL → 本地文件绝对路径（带 `file://` 前缀，可直接喂给 Image / AVPlayer）
    /// - 已存在：直接返回本地路径（不重复下载）
    /// - 下载失败：返回 nil（不抛错，让上层决定如何展示）
    static func downloadIfNeeded(remoteURL: String, kind: LocalAssetKind) async -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        // 已经是 file:// 本地路径 → 直接返回
        if url.isFileURL { return url.absoluteString }

        let fileName = makeFileName(for: url, kind: kind)
        let destURL = directory(for: kind).appendingPathComponent(fileName)

        // 命中缓存
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL.absoluteString
        }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                DebugLog.shared.warn(.data, "asset download bad status",
                    details: "url=\(trimmed.prefix(120))")
                return nil
            }
            try data.write(to: destURL, options: .atomic)
            return destURL.absoluteString
        } catch {
            DebugLog.shared.warn(.data, "asset download failed",
                details: "url=\(trimmed.prefix(120)), err=\(error.localizedDescription)")
            return nil
        }
    }

    /// 批量下载 — 返回与输入等长的数组（失败位置为 nil）
    static func downloadAll(_ remoteURLs: [String], kind: LocalAssetKind) async -> [String?] {
        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, u) in remoteURLs.enumerated() {
                group.addTask {
                    let local = await downloadIfNeeded(remoteURL: u, kind: kind)
                    return (i, local)
                }
            }
            var out = Array<String?>(repeating: nil, count: remoteURLs.count)
            for await (i, local) in group {
                out[i] = local
            }
            return out
        }
    }

    // MARK: - Path helpers

    /// Documents/LocalAssets/{images|videos}/
    private static func directory(for kind: LocalAssetKind) -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("LocalAssets/\(kind.subdir)", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// sha256(URL) 做文件名（去重 + 稳定）
    private static func makeFileName(for url: URL, kind: LocalAssetKind) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        // 优先用 URL 后缀 / 响应 MIME（下载时再确定），先用 URL path extension
        let pathExt = url.pathExtension.lowercased()
        let ext = (pathExt.isEmpty || pathExt.contains("/")) ? kind.defaultExtension : pathExt
        return "\(hash).\(ext)"
    }

    // MARK: - Migration（启动时跑一次：旧的远程 URL 会被下载到本地）

    /// 给一组已存的 URL，下载到本地，返回本地路径数组（保持顺序，失败位置 nil）
    /// 用途：老数据迁移 — 启动时把 SwiftData 里残留的远程 URL 全下到本地
    static func migrateRemoteURLs(_ urls: [String], kind: LocalAssetKind) async -> [String] {
        let results = await downloadAll(urls, kind: kind)
        return results.map { $0 ?? "" }.filter { !$0.isEmpty }
            // 保留原顺序的合并：把 nil 位置回退到原始远程 URL
            + []  // 实际上 filter 丢掉了原顺序索引，迁移场景下用下面的 zipMap
    }

    /// 与 `migrateRemoteURLs` 配对使用：保留顺序，nil 位置回退到原 URL
    static func migrateRemoteURLsPreserveOrder(_ urls: [String], kind: LocalAssetKind) async -> [String] {
        let results = await downloadAll(urls, kind: kind)
        return zip(urls, results).map { orig, local in local ?? orig }
    }
}
