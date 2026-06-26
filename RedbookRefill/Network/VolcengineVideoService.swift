//
//  VolcengineVideoService.swift
//  RedbookRefill
//
//  豆包（方舟 Ark）Seedance 视频生成服务。
//  完整流程：提交任务 → 轮询 → 下载到本地（视频 URL 24h 过期，必须落盘）。
//
//  端点：
//   - 创建：POST  {baseURL}/api/v3/contents/generations/tasks
//   - 查询：GET   {baseURL}/api/v3/contents/generations/tasks/{task_id}
//
//  鉴权：Bearer Token（API Key）
//  官方文档：https://www.volcengine.com/docs/82379/1520757
//
//  任务状态机（来自查询接口）：
//   queued → running → succeeded（拿到 video_url）
//                          ↘ failed / expired
//

import Foundation

@MainActor
@Observable
final class VolcengineVideoService {

    // MARK: - State（UI 可观察）

    var isGenerating: Bool = false
    var phase: String = ""          // "提交任务" / "生成中（第 N 次轮询）" / "下载到本地" / "完成"
    var error: String?
    /// **本地文件 URL**（带 `file://` 前缀，可直接喂给 AVPlayer）— 视频已下载到本地 Documents 目录
    /// - iOS：`file:///.../Documents/videos/{taskId}.mp4` — AVPlayer 直接播
    /// - macOS：`URL.safeURL` 解析通过，AVPlayer 也认
    var localVideoURL: String?

    // MARK: - Config

    /// 端点路径（**不带** `/api/v3` 前缀 — baseURL 已经包含）
    /// 真实端点（按 CSDN 实战代码确认）：`POST {baseURL}/contents/generations/tasks`
    /// 错误示例：`/api/v3/contents/generations/tasks` 会被拼成 `.../api/v3/api/v3/...` → 404
    private static let submitPath = "/contents/generations/tasks"
    private static let queryPathPrefix = "/contents/generations/tasks"

    /// 轮询间隔（秒）— 用户体感优先
    private static let pollIntervalSeconds: TimeInterval = 5
    /// 单次提交超时（秒）— 冷启动可能慢
    private static let submitTimeoutSeconds: TimeInterval = 60
    /// 单次轮询超时（秒）
    private static let pollTimeoutSeconds: TimeInterval = 15
    /// 任务总等待上限（秒）— 10 分钟
    private static let maxWaitSeconds: TimeInterval = 600

    // MARK: - Public API

    /// 生成视频（完整流程：提交 → 轮询 → 下载本地）
    func generateVideo(prompt: String) async {
        guard !isGenerating else { return }
        isGenerating = true
        error = nil
        localVideoURL = nil
        phase = "提交任务"

        let cfg = LLMConfigStore.config(for: .video)
        guard cfg.isValid else {
            error = "请先在「大模型配置」填写 API Key"
            isGenerating = false
            phase = ""
            return
        }

        do {
            // 1) 提交任务
            let taskId = try await submit(
                baseURL: cfg.baseURL,
                apiKey: cfg.apiKey,
                model: cfg.model,
                prompt: prompt
            )
            DebugLog.shared.info(.volc, "video task submitted", details: "task_id=\(taskId), model=\(cfg.model)")

            // 2) 轮询直到 succeeded
            let remoteURL = try await pollUntilDone(
                baseURL: cfg.baseURL,
                apiKey: cfg.apiKey,
                taskId: taskId
            )
            DebugLog.shared.info(.volc, "video task succeeded", details: "remote_url=\(remoteURL)")

            // 3) **关键**：下载到本地（远程 URL 24h 过期）
            phase = "下载到本地"
            let localPath = try await downloadToLocal(
                remoteURL: remoteURL,
                taskId: taskId
            )
            DebugLog.shared.info(.volc, "video downloaded to local", details: "path=\(localPath)")

            localVideoURL = localPath
            phase = "完成"
        } catch {
            self.error = error.localizedDescription
            DebugLog.shared.error(.volc, "video generate failed", details: error.localizedDescription)
        }
        isGenerating = false
    }

    // MARK: - Step 1: Submit

    private struct SubmitResponse: Decodable {
        let id: String
        // 部分返回结构用 task_id 字段名
        let task_id: String?

        var taskId: String { task_id ?? id }
    }

    private func submit(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String
    ) async throws -> String {
        // 真实端点：{baseURL}/contents/generations/tasks（baseURL 已含 /api/v3）
        let urlStr = baseURL + Self.submitPath
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
            throw VolcVideoError.invalidURL(urlStr)
        }

        // 新方式（推荐）：在 request body 的 parameters 字段直接传生成参数
        let body: [String: Any] = [
            "model": model,
            "content": [[
                "type": "text",
                "text": prompt
            ]],
            "parameters": [
                "generateAudio": true,
                "durationSeconds": 5,
                // 9:16 竖屏全屏（小红书/抖音主流），比 3:4 更沉浸
                "aspectRatio": "9:16",
                "resolution": "720p",
                "sampleCount": 1
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.submitTimeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw VolcVideoError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw VolcVideoError.submitFailed(statusCode: http.statusCode, body: snippet)
        }

        // 解析响应：id 字段（部分版本用 task_id）
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VolcVideoError.invalidResponse
        }
        // 兼容字段名
        if let id = json["id"] as? String, !id.isEmpty {
            return id
        }
        if let tid = json["task_id"] as? String, !tid.isEmpty {
            return tid
        }
        // data 嵌套
        if let data = json["data"] as? [String: Any] {
            if let id = data["id"] as? String { return id }
            if let tid = data["task_id"] as? String { return tid }
        }
        throw VolcVideoError.invalidResponse
    }

    // MARK: - Step 2: Poll

    private func pollUntilDone(
        baseURL: String,
        apiKey: String,
        taskId: String
    ) async throws -> String {
        let urlStr = baseURL + Self.queryPathPrefix + "/\(taskId)"
        guard let url = URL(string: urlStr) else {
            throw VolcVideoError.invalidURL(urlStr)
        }

        let start = Date()
        var attempts = 0

        while Date().timeIntervalSince(start) < Self.maxWaitSeconds {
            attempts += 1
            phase = "生成中（第 \(attempts) 次查询）"

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = Self.pollTimeoutSeconds
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw VolcVideoError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
                throw VolcVideoError.pollFailed(statusCode: http.statusCode, body: snippet)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VolcVideoError.invalidResponse
            }

            let status = (json["status"] as? String ?? "").lowercased()
            DebugLog.shared.info(.volc, "video poll",
                details: "task_id=\(taskId), status=\(status), attempt=\(attempts)")

            switch status {
            case "succeeded", "success":
                // 拿 content.video_url（注意：content 是 object，里面有 video_url 字段）
                guard let content = json["content"] as? [String: Any] else {
                    throw VolcVideoError.invalidResponse
                }
                // video_url 可能是字符串或 object
                if let s = content["video_url"] as? String, !s.isEmpty {
                    return s
                }
                if let obj = content["video_url"] as? [String: Any],
                   let s = obj["url"] as? String, !s.isEmpty {
                    return s
                }
                throw VolcVideoError.noVideoURL

            case "failed", "error":
                let err = (json["error"] as? [String: Any])?["message"] as? String
                    ?? (json["message"] as? String)
                    ?? "视频生成失败"
                throw VolcVideoError.taskFailed(err)

            case "expired":
                throw VolcVideoError.taskExpired

            case "queued", "running", "pending", "in_progress":
                // 继续轮询
                try await Task.sleep(nanoseconds: UInt64(Self.pollIntervalSeconds * 1_000_000_000))
                continue

            default:
                // 未知状态 → 等一下再试
                try await Task.sleep(nanoseconds: UInt64(Self.pollIntervalSeconds * 1_000_000_000))
                continue
            }
        }
        throw VolcVideoError.timeout
    }

    // MARK: - Step 3: Download to local（关键：24h 过期问题）

    /// 把视频从远程 URL 下载到本地 Documents/videos/ 目录，返回本地文件绝对路径。
    /// 远程 URL 24 小时后失效，所以**必须在生成成功时立即下载保存**。
    private func downloadToLocal(
        remoteURL: String,
        taskId: String
    ) async throws -> String {
        guard let url = URL(string: remoteURL) else {
            throw VolcVideoError.invalidURL(remoteURL)
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VolcVideoError.downloadFailed
        }

        // 存到 Documents/videos/{taskId}.mp4
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDir = docs.appendingPathComponent("videos", isDirectory: true)
        if !fm.fileExists(atPath: videosDir.path) {
            try fm.createDirectory(at: videosDir, withIntermediateDirectories: true)
        }
        // 文件名用 taskId（方舟任务 ID），确保唯一且可追溯
        let fileURL = videosDir.appendingPathComponent("\(taskId).mp4")
        try data.write(to: fileURL, options: .atomic)

        // 返回带 file:// 前缀的字符串，AVPlayer + URL.safeURL 都认
        return fileURL.absoluteString
    }

    // MARK: - Reset

    func reset() {
        isGenerating = false
        phase = ""
        error = nil
        localVideoURL = nil
    }
}

// MARK: - Errors

enum VolcVideoError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case submitFailed(statusCode: Int, body: String)
    case pollFailed(statusCode: Int, body: String)
    case taskFailed(String)
    case taskExpired
    case timeout
    case noVideoURL
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s):   return "API URL 无效：\(s)"
        case .invalidResponse:     return "返回数据格式异常"
        case .submitFailed(let c, let b): return "提交失败 HTTP \(c)：\(b.prefix(200))"
        case .pollFailed(let c, let b):   return "轮询失败 HTTP \(c)：\(b.prefix(200))"
        case .taskFailed(let m):    return "视频生成失败：\(m)"
        case .taskExpired:         return "任务已过期，请重新生成"
        case .timeout:              return "视频生成超时（10 分钟）"
        case .noVideoURL:           return "成功但未返回 video_url"
        case .downloadFailed:       return "视频下载失败（24h 过期前请重试）"
        }
    }
}
