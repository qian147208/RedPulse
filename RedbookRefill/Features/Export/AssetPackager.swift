//
//  AssetPackager.swift
//  灵芯
//
//  一键打包小红书笔记素材的 actor。纯 IO 逻辑，与 UI 无关。
//  三端复用：macOS 走 package(record:to:)，iOS/iPadOS 走 packageAsZip(record:)。
//

import Foundation
#if canImport(Compression)
import Compression
#endif

actor AssetPackager {

    // MARK: - Error

    enum PackageError: Error {
        case downloadFailed(url: String, underlying: Error?)
        case writeFailed(path: String, underlying: Error)
        case invalidURL(String)
        case zipFailed(underlying: Error?)
    }

    // MARK: - Public API

    /// 把 record 打包到 destDir/<folderName>/ 下；返回最终目录 URL。
    /// destDir 必须是已存在的目录（macOS 用户选的目录 / iOS app sandbox temp）。
    func package(record: GenerationRecord, to destDir: URL) async throws -> URL {
        let folderURL = try makeUniqueFolder(in: destDir, baseName: folderName(for: record))

        // 1. 写笔记.txt
        try writeNoteText(record: record, to: folderURL)

        // 2. 并发下载图片（保持顺序）
        await downloadImages(urls: record.imageUrls, to: folderURL)

        // 3. 下载视频
        if let videoUrl = record.videoUrl, !videoUrl.isEmpty {
            await downloadVideo(urlString: videoUrl, to: folderURL)
        }

        // 4. 写提示词.txt
        try writePromptsText(record: record, to: folderURL)

        return folderURL
    }

    /// 把 record 打成 zip 文件，返回临时 zip URL（iOS .fileExporter / UIActivityViewController 用）。
    func packageAsZip(record: GenerationRecord) async throws -> URL {
        // 1. 在 temp 下建一个临时父目录，避免污染 temp 根
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetPackager_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // 2. 把素材写到临时父目录
        let folderURL = try await package(record: record, to: parent)

        // 3. 用 NSFileCoordinator + .forUploading 生成 zip —— Apple 内置 API，三端通用
        let zipURL = try makeZip(from: folderURL)
        return zipURL
    }

    // MARK: - 文件夹命名

    /// 文件夹名：红书笔记_<标题前10字>_<yyyyMMdd_HHmm>
    private func folderName(for record: GenerationRecord) -> String {
        let rawTitle = record.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePart: String
        if rawTitle.isEmpty {
            titlePart = "未命名"
        } else {
            let prefix = String(rawTitle.prefix(10))
            titlePart = sanitizeFileName(prefix)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let timestamp = formatter.string(from: Date())

        return "红书笔记_\(titlePart)_\(timestamp)"
    }

    /// 替换路径非法字符：/ \ : * ? " < > |
    private func sanitizeFileName(_ name: String) -> String {
        let illegal: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
        let cleaned = String(name.map { illegal.contains($0) ? "_" : $0 })
        return cleaned.isEmpty ? "未命名" : cleaned
    }

    /// 在 destDir 下创建唯一目录；若存在加 _2、_3 ...
    private func makeUniqueFolder(in destDir: URL, baseName: String) throws -> URL {
        let fm = FileManager.default
        var candidate = destDir.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = destDir.appendingPathComponent("\(baseName)_\(suffix)", isDirectory: true)
            suffix += 1
        }
        do {
            try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            throw PackageError.writeFailed(path: candidate.path, underlying: error)
        }
        return candidate
    }

    // MARK: - 写文本

    private func writeNoteText(record: GenerationRecord, to folderURL: URL) throws {
        let tagsLine = record.tags
            .map { "#\($0)" }
            .joined(separator: " ")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let timestamp = isoFormatter.string(from: Date())

        let body = """
        === 标题 ===
        \(record.noteTitle)

        === 正文 ===
        \(record.content)

        === 标签 ===
        \(tagsLine)

        === 配图建议 ===
        \(record.imageSuggestion)

        === 优化建议 ===
        \(record.suggestion)


        === 广告类型 ===
        \(record.adType)

        —— 由 灵芯 生成 · \(timestamp) ——
        """

        let fileURL = folderURL.appendingPathComponent("笔记.txt")
        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw PackageError.writeFailed(path: fileURL.path, underlying: error)
        }
    }

    private func writePromptsText(record: GenerationRecord, to folderURL: URL) throws {
        let body = """
        === 图片提示词 ===
        \(record.imagePrompt)

        === 视频提示词 ===
        \(record.videoPrompt)
        """
        let fileURL = folderURL.appendingPathComponent("提示词.txt")
        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw PackageError.writeFailed(path: fileURL.path, underlying: error)
        }
    }

    // MARK: - 下载图片（并发 + 保序）

    /// 并发下载图片，保持 imageUrls 顺序命名 图片_01.jpg ... 失败跳过不抛错
    private func downloadImages(urls: [String], to folderURL: URL) async {
        guard !urls.isEmpty else { return }

        // (index, data, ext) — 失败的项不返回
        let results: [(Int, Data, String)] = await withTaskGroup(
            of: (Int, Data, String)?.self
        ) { group in
            for (index, urlString) in urls.enumerated() {
                group.addTask {
                    await Self.downloadImageData(urlString: urlString, index: index)
                }
            }
            var collected: [(Int, Data, String)] = []
            for await item in group {
                if let item = item {
                    collected.append(item)
                }
            }
            return collected
        }

        // 按原始顺序排序后写盘
        let sorted = results.sorted { $0.0 < $1.0 }
        for (i, entry) in sorted.enumerated() {
            // 序号按"成功下载顺序"递增；用 i+1 命名更连续
            let serial = String(format: "%02d", i + 1)
            let filename = "图片_\(serial).\(entry.2)"
            let fileURL = folderURL.appendingPathComponent(filename)
            do {
                try entry.1.write(to: fileURL)
            } catch {
                print("[AssetPackager] 写入图片失败 \(filename): \(error)")
            }
        }
    }

    /// 单图下载；失败返回 nil（仅打印日志）
    private static func downloadImageData(
        urlString: String,
        index: Int
    ) async -> (Int, Data, String)? {
        guard let url = URL.safeURL(from: urlString) else {
            print("[AssetPackager] 无效图片 URL: \(urlString)")
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let ext = inferImageExtension(from: response)
            return (index, data, ext)
        } catch {
            print("[AssetPackager] 图片下载失败 \(urlString): \(error)")
            return nil
        }
    }

    /// MIME → 扩展名；未知默认 jpg
    private static func inferImageExtension(from response: URLResponse) -> String {
        guard let mime = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() else {
            return "jpg"
        }
        if mime.contains("png") { return "png" }
        if mime.contains("webp") { return "webp" }
        if mime.contains("gif") { return "gif" }
        if mime.contains("heic") { return "heic" }
        return "jpg"
    }

    // MARK: - 下载视频

    private func downloadVideo(urlString: String, to folderURL: URL) async {
        guard let url = URL.safeURL(from: urlString) else {
            print("[AssetPackager] 无效视频 URL: \(urlString)")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fileURL = folderURL.appendingPathComponent("视频.mp4")
            try data.write(to: fileURL)
        } catch {
            print("[AssetPackager] 视频下载失败 \(urlString): \(error)")
        }
    }

    // MARK: - Zip 打包（NSFileCoordinator .forUploading 三端通用）

    private func makeZip(from folderURL: URL) throws -> URL {
        var coordError: NSError?
        var finalZipURL: URL?
        var copyError: Error?

        let folderName = folderURL.lastPathComponent
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(folderName).zip")

        // 若同名 zip 已存在，先清理
        try? FileManager.default.removeItem(at: destURL)

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: folderURL,
            options: [.forUploading],
            error: &coordError
        ) { tempZipURL in
            // tempZipURL 由系统在临时位置生成的 zip 文件
            do {
                try FileManager.default.copyItem(at: tempZipURL, to: destURL)
                finalZipURL = destURL
            } catch {
                copyError = error
            }
        }

        if let coordError = coordError {
            throw PackageError.zipFailed(underlying: coordError)
        }
        if let copyError = copyError {
            throw PackageError.zipFailed(underlying: copyError)
        }
        guard let zipURL = finalZipURL else {
            throw PackageError.zipFailed(underlying: nil)
        }
        return zipURL
    }
}
