//
//  AgnesService.swift
//  RedbookRefill
//
//  Agnes AI 图片/视频生成服务（OpenAI 兼容接口）。
//  单一 endpoint + 单一 API Key，三模型共用。
//
//  模型：
//  - 文案：agnes-2.0-flash （在 LLMTextGenerator 用）
//  - 图片：agnes-image-2.1-flash （OpenAI /v1/images/generations）
//  - 视频：agnes-video-v2.0 （自定义 /v1/videos/generations + 轮询）
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AgnesService {

    // MARK: - Configuration (from LLMConfigStore)
    //
    // 通过 LLMConfigStore 读：默认模式共享 baseURL+key，自定义模式可按能力独立。
    // 仍保留静态 model 字段以供外部（UI 展示、LLMConfigView 旧调用方）使用。

    private var apiBaseURL: String { LLMConfigStore.config(for: .image).baseURL }
    private var apiKey: String {
        // image 和 video 共用同一个 service 管，按使用方读
        let img = LLMConfigStore.config(for: .image).apiKey
        if !img.isEmpty { return img }
        return LLMConfigStore.config(for: .video).apiKey
    }

    /// 当前图片配置（baseURL + apiKey + model）。GenerateView 等可读这个判断/展示。
    var currentImageConfig: LLMConfig { LLMConfigStore.config(for: .image) }
    /// 当前视频配置
    var currentVideoConfig: LLMConfig { LLMConfigStore.config(for: .video) }

    nonisolated static let textModel = "agnes-2.0-flash"
    nonisolated static let imageModel = "agnes-image-2.1-flash"
    nonisolated static let videoModel = "agnes-video-v2.0"

    /// 提交任务的超时：图生图 / 图生视频的 body 含 base64 图片，1 张 1024px
    /// 压缩后 ~200-400KB，再加上 JSON 包装，60s 在网络抖动下容易超时。
    /// 官方文档推荐 60-360s → 取 180s 留够 buffer。
    nonisolated static let submitTimeoutSeconds: TimeInterval = 180

    /// 轮询单个请求的超时（视频用）
    nonisolated static let pollTimeoutSeconds: TimeInterval = 15

    /// 视频任务总等待上限
    nonisolated static let maxVideoWaitSeconds: TimeInterval = 600

    /// Agnes 查询视频结果端点（`/agnesapi`）不在 `/v1` 路径下，需要独立 host。
    /// 文档：https://apihub.agnes-ai.com/agnesapi?video_id=...
    nonisolated static let agnesAPIBase = "https://apihub.agnes-ai.com"

    /// 视频默认参数：720p 9:16 竖屏（小红书 / 抖音全屏主流） + 121 帧 @ 24fps ≈ 5 秒
    /// 之前 1152x768 是 3:2 横屏，跟小红书竖屏消费场景不匹配 → 改 9:16 竖屏全屏
    nonisolated static let videoDefaults: [String: Any] = [
        "width": 720,
        "height": 1280,
        "num_frames": 121,
        "frame_rate": 24
    ]

    // MARK: - State

    var isGeneratingImage = false
    var isGeneratingVideo = false
    var generatedImageURLs: [String] = []
    var generatedVideoURL: String?
    var imageError: String?
    var videoError: String?

    // 进度文案（UI 跟豆包 volcService.phase 用法保持一致）
    // - imagePhase:  "准备 N 个 prompt" → "生成中（X/N）" → "下载到本地" → "完成"
    // - videoPhase:  "提交任务"        → "生成中（第 N 次查询）" → "下载到本地" → "完成"
    var imagePhase: String = ""
    var videoPhase: String = ""
    /// Agnes 视频的官方 progress 字段（0-100），比 attempts 更准
    ///  - in_progress 时通常从 0 跳到 100（后端粒度问题）
    ///  - queued 时为 0
    ///  - completed 时为 100
    /// UI 可以用它画 ProgressView(value: 0...100)
    var videoProgress: Int = 0

    var isConfigValidForImage: Bool { !apiKey.isEmpty }
    var isConfigValidForVideo: Bool { !apiKey.isEmpty }

    // MARK: - Image Generation (OpenAI /v1/images/generations)

    func generateImage(prompt: String) async {
        await generateImages(prompts: [prompt], referenceImagesData: [])
    }

    /// 并行用 N 个 prompt 各生成一张图，结果累积到 generatedImageURLs。
    func generateImages(prompts: [String], referenceImagesData: [Data] = []) async {
        let cleanPrompts = prompts.filter { !$0.isEmpty }
        guard !cleanPrompts.isEmpty else {
            imageError = "没有可用的提示词"
            return
        }
        isGeneratingImage = true
        imageError = nil
        imagePhase = "准备 \(cleanPrompts.count) 个提示词"
        generatedImageURLs = []

        let cfg = LLMConfigStore.config(for: .image)
        guard cfg.isValid else {
            DebugLog.shared.error(.agnes, "image config missing")
            imageError = "请先在「大模型配置」填写 API Key"
            imagePhase = ""
            isGeneratingImage = false
            return
        }

        let key = cfg.apiKey
        let base = cfg.baseURL
        let model = cfg.model
        let count = cleanPrompts.count
        DebugLog.shared.info(.agnes, "image batch generate start", details: "count=\(count), model=\(model)")
        let started = Date()

        imagePhase = count > 1 ? "并行生成 \(count) 张配图" : "生成配图"

        var collected: [String] = []
        var failures: [String] = []
        await withTaskGroup(of: Result<[String], Error>.self) { group in
            for prompt in cleanPrompts {
                group.addTask {
                    do {
                        // 单张图片也走 withRetry — 网络抖动能自动恢复
                        let urls = try await withRetry {
                            try await Self.callImageAPI(
                                baseURL: base,
                                apiKey: key,
                                model: model,
                                prompt: prompt,
                                referenceImagesData: referenceImagesData
                            )
                        }
                        return .success(urls)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            // 边收边更新 phase：每回来一张把 "X/N 已完成" 推给 UI
            var done = 0
            for await result in group {
                done += 1
                imagePhase = "生成中（\(done)/\(count)）"
                switch result {
                case .success(let urls): collected.append(contentsOf: urls)
                case .failure(let err): failures.append(err.localizedDescription)
                }
            }
        }

        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

        // 关键：所有模型（Agnes / 豆包 / 未来其他）返回的远程 URL 都是 24h 过期
        // 必须在生成成功时立即下载到本地 Documents/LocalAssets/images/
        if !collected.isEmpty {
            imagePhase = "下载到本地（\(collected.count) 张）"
        }
        let localResults = await LocalAssetStore.downloadAll(collected, kind: .image)
        let localImageURLs = zip(collected, localResults).compactMap { _, local in local }
        let localFailCount = collected.count - localImageURLs.count
        if localFailCount > 0 {
            DebugLog.shared.warn(.data, "image local download partial fail",
                details: "downloaded=\(localImageURLs.count)/\(collected.count)")
        }
        generatedImageURLs = localImageURLs

        if localImageURLs.isEmpty {
            imageError = failures.first ?? "生成失败"
            imagePhase = ""
            DebugLog.shared.error(.agnes, "image batch failed", details: "elapsed=\(elapsedMs)ms, all \(count) tasks failed")
        } else {
            if !failures.isEmpty {
                imageError = "成功 \(localImageURLs.count)/\(count)，失败：\(failures.first ?? "")"
            }
            imagePhase = "完成"
            DebugLog.shared.info(.agnes, "image batch ok", details: "elapsed=\(elapsedMs)ms, ok=\(collected.count)")
        }
        isGeneratingImage = false
    }

    /// 根据 baseURL 选合适的图片 size（小红书 3:4 portrait）：
    /// - 豆包 Seedream 4.5/5.0 (Ark)：最小 3.7M 像素 → 1920x2560 (4.92M)
    /// - Agnes：1440x1920 (2.76M) OK
    nonisolated static func pickImageSize(forBaseURL base: String) -> String {
        if base.contains("volces.com") {
            return "1920x2560"  // 豆包 Ark Seedream 4.5+
        } else {
            return "1440x1920"  // Agnes / 其他 OpenAI 兼容
        }
    }

    /// OpenAI 兼容 /v1/images/generations 端点调用。
    /// - referenceImagesData: 有值时走图生图模式（把 Data 编码成 data URI 放进
    ///   `extra_body.image` 数组）。本地图片无公开 URL，必须用 data URI 形式。
    ///   官方文档：https://wiki.agnes-ai.com/llms.txt
    nonisolated static func callImageAPI(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        referenceImagesData: [Data] = []
    ) async throws -> [String] {
        let imageSize = pickImageSize(forBaseURL: baseURL)
        guard let endpoint = URL(string: "\(baseURL)/images/generations") else {
            throw AgnesError.invalidURL
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        // 文档推荐 60s-360s。图生图 body 含 1-2 张 base64 缩图（<1MB），
        // 60s 偏紧 → 180s 留 buffer（首字节返回前网络抖动 + 大模型调度冷启动）
        req.timeoutInterval = Self.submitTimeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            // 小红书手机端 3:4 portrait (1080×1440 等比)
            // - 豆包 Seedream 4.5 / 5.0 在 Ark：size 接受 WIDTHxHEIGHT 或 "2K"/"3K" 等级，
            //   最小 3.7M 像素 → 1920x2560 (4.92M) 满足
            // - Agnes：WIDTHxHEIGHT，1440x1920 (2.76M) OK
            "size": imageSize
        ]

        // 图生图：把参考图编码成 data URI 放进 extra_body.image 数组
        // 官方文档示例 3 / 4：图生图通过 extra_body.image 传入输入图片
        if !referenceImagesData.isEmpty {
            var extraBody: [String: Any] = [
                "response_format": "url"   // 明确要 URL 返回（不能放顶层）
            ]
            let dataURIs: [String] = referenceImagesData.map { data in
                "data:image/png;base64,\(data.base64EncodedString())"
            }
            extraBody["image"] = dataURIs
            body["extra_body"] = extraBody
        } else {
            // 文生图：也要明确 response_format=url，否则可能默认返回空
            // （安全做法：永远告诉后端要 URL 输出）
            body["extra_body"] = [
                "response_format": "url"
            ]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AgnesError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw AgnesError.httpError(statusCode: http.statusCode, body: snippet)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw AgnesError.invalidResponse
        }
        // 优先取 url（response_format=url 时）；fallback 到 b64_json（如果用户关了）
        return arr.compactMap { $0["url"] as? String }
    }

    // MARK: - Video Generation (Agnes 自定义 /v1/videos/generations + 轮询)

    /// 生成视频。
    /// - Parameter referenceImageURLs: 客户端已生成的本地/远程图片 URL。
    ///   - 空 → 文生视频（保持向后兼容）
    ///   - 有值 → 把第一张图作为首帧 i2v（图生视频），跟豆包 Seedance 行为对齐
    ///     —— 5 秒短视频，prompt 描述动作/场景，图片提供主体外观
    ///   字段命名按 OpenAI /v1/videos 风格 `first_frame_image_url` 发送；Agnes 后端
    ///   如果字段名不同，下一版在 #if 块里按 model 区分即可。
    func generateVideo(prompt: String, referenceImageURLs: [String] = []) async {
        isGeneratingVideo = true
        videoError = nil
        videoPhase = "提交任务"
        generatedVideoURL = nil

        let cfg = LLMConfigStore.config(for: .video)
        guard cfg.isValid else {
            DebugLog.shared.error(.agnes, "video config missing")
            videoError = "请先在「大模型配置」填写 API Key"
            videoPhase = ""
            isGeneratingVideo = false
            return
        }

        let key = cfg.apiKey
        let base = cfg.baseURL
        let model = cfg.model
        DebugLog.shared.info(.agnes, "video generate start", details: "model=\(model), prompt_chars=\(prompt.count), ref_imgs=\(referenceImageURLs.count)")
        let started = Date()

        do {
            // 只对"提交任务"阶段重试 — 轮询阶段单独跑（避免重复创建任务）
            // 第一次失败：2s 后重试；第二次失败：5s 后重试；第三次失败：抛错
            let videoId = try await withRetry(
                {
                    try await Self.submitVideoTask(
                        baseURL: base,
                        apiKey: key,
                        model: model,
                        prompt: prompt,
                        firstFrameURL: referenceImageURLs.first
                    )
                },
                onRetry: { [weak self] retryNumber, _ in
                    self?.videoPhase = "提交失败,\(RetryPolicy.backoffSeconds[retryNumber - 1])s 后重试（\(retryNumber)/2）"
                    DebugLog.shared.warn(.agnes, "video submit retry", details: "retry=\(retryNumber)/2")
                }
            )
            // 提交成功 → 进入轮询阶段（不重试）
            let url = try await Self.pollVideoTask(
                videoId: videoId,
                apiKey: key,
                model: model
            ) { [weak self] _, progress in
                // progress 是 0-100（官方 progress 字段），比"第 N 次查询"更准
                Task { @MainActor in
                    self?.videoProgress = progress
                    self?.videoPhase = "生成中（\(progress)%）"
                }
            }
            // 关键：所有模型远程视频 URL 都有时效 → 立即下载到本地
            videoPhase = "下载到本地"
            videoProgress = 100
            let localURL = await LocalAssetStore.downloadIfNeeded(remoteURL: url, kind: .video)
            generatedVideoURL = localURL ?? url
            videoPhase = "完成"
            DebugLog.shared.info(.agnes, "video generate ok", details: "elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms, local=\(localURL ?? url)")
        } catch {
            DebugLog.shared.error(.agnes, "video generate failed", details: error.localizedDescription)
            videoError = error.localizedDescription
            videoPhase = ""
            videoProgress = 0
        }
        isGeneratingVideo = false
    }

    /// Agnes video 异步任务：POST 创建任务 → 轮询直到完成 → 返回视频 URL。
    /// 端点：
    /// - 创建：`POST {baseURL}/videos`（baseURL 含 `/v1`）
    /// - 查询：`GET {agnesAPIBase}/agnesapi?video_id=...&model_name=...`（独立 host，不在 `/v1` 下）
    /// - firstFrameURL: 有值时作为顶层 `image` 字段提交，触发 i2v（图生视频）。
    ///   无值时纯文生视频，行为完全不变。
    ///   字段名按官方文档：单图放在顶层 `image`，多图/keyframes 放在 `extra_body.image`。
    ///   官方文档：https://wiki.agnes-ai.com/llms.txt
    ///
    /// 拆分原因：把"提交任务"和"轮询"独立出来，让 generateVideo 只能对**提交阶段**重试。
    /// 如果重试整个 callVideoAPI，第一次"已经成功提交但响应丢失"会被错误地再发一次请求
    /// → 服务端会创建第二个任务（重复扣额度）。
    nonisolated static func callVideoAPI(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        firstFrameURL: String? = nil,
        onPoll: ((Int, Int) -> Void)? = nil
    ) async throws -> String {
        // 1. 提交任务（注意：这里**不**用 retry 包，由 generateVideo 决定是否重试）
        let videoId = try await submitVideoTask(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            firstFrameURL: firstFrameURL
        )
        // 2. 轮询结果（不重试，每次轮询是一次独立 GET）
        return try await pollVideoTask(
            videoId: videoId,
            apiKey: apiKey,
            model: model,
            onPoll: onPoll
        )
    }

    /// 视频任务提交：POST `{baseURL}/videos`
    /// 失败抛出可重试的错误（AgnesError.submitTimeout / URLError* / invalidResponse），
    /// 或不可重试的错误（HTTP 4xx/5xx → httpError，URL 解析失败 → invalidURL）。
    nonisolated static func submitVideoTask(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        firstFrameURL: String?
    ) async throws -> String {
        guard let submitURL = URL(string: "\(baseURL)/videos") else {
            throw AgnesError.invalidURL
        }
        var submitReq = URLRequest(url: submitURL)
        submitReq.httpMethod = "POST"
        // 视频提交可能慢（冷启动 / 大模型调度）。如果 body 含 first frame 图
        // （图生视频模式），1 张 1024px 压缩后 ~200-400KB，传完需要 10-30s。
        // 60s 容易超时 → 180s 留够 buffer（官方文档推荐 60-360s）。
        submitReq.timeoutInterval = Self.submitTimeoutSeconds
        submitReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submitReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt
        ]
        // 图生视频：把首帧 URL 放在顶层 `image` 字段（官方文档示例 2）
        if let firstFrame = firstFrameURL, !firstFrame.isEmpty {
            body["image"] = firstFrame
        }
        // 合并默认视频参数（width/height/num_frames/frame_rate）
        // 5 秒 = num_frames 121 / frame_rate 24（文档"约 5 秒"推荐档位）
        for (k, v) in videoDefaults { body[k] = v }
        submitReq.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (submitData, submitResp): (Data, URLResponse)
        do {
            (submitData, submitResp) = try await URLSession.shared.data(for: submitReq)
        } catch let urlErr as URLError where urlErr.code == .timedOut {
            throw AgnesError.submitTimeout
        } catch {
            throw error
        }
        guard let submitHttp = submitResp as? HTTPURLResponse else {
            throw AgnesError.invalidResponse
        }
        if !(200..<300).contains(submitHttp.statusCode) {
            let snippet = String(data: submitData.prefix(300), encoding: .utf8) ?? ""
            throw AgnesError.httpError(statusCode: submitHttp.statusCode, body: snippet)
        }
        guard let submitJSON = try JSONSerialization.jsonObject(with: submitData) as? [String: Any] else {
            throw AgnesError.invalidResponse
        }
        // 优先 video_id（新接口推荐）→ task_id → id（旧版兼容）
        guard let videoId = submitJSON["video_id"] as? String
                           ?? submitJSON["task_id"] as? String
                           ?? submitJSON["id"] as? String else {
            throw AgnesError.invalidResponse
        }
        return videoId
    }

    /// 视频任务轮询：GET `{agnesAPIBase}/agnesapi?video_id=...&model_name=...`
    /// 独立函数不重试——重试会导致已经在生成的任务被错认成"未提交"，浪费额度。
    nonisolated static func pollVideoTask(
        videoId: String,
        apiKey: String,
        model: String,
        onPoll: ((Int, Int) -> Void)? = nil
    ) async throws -> String {
        // `/agnesapi` 不在 `/v1` 下，用独立的 agnesAPIBase；带 model_name 更稳。
        var pollComps = URLComponents(string: "\(agnesAPIBase)/agnesapi")
        pollComps?.queryItems = [
            URLQueryItem(name: "video_id", value: videoId),
            URLQueryItem(name: "model_name", value: model)
        ]
        guard let pollURL = pollComps?.url else {
            throw AgnesError.invalidURL
        }
        let pollStart = Date()
        // 抽卡偶尔 5-7 分钟，最长拉到 10 分钟（num_frames 441 ≈ 18 秒为上限）
        let timeout = Self.maxVideoWaitSeconds
        var attempts = 0
        var lastProgress: Int = 0
        while Date().timeIntervalSince(pollStart) < timeout {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            attempts += 1
            var pollReq = URLRequest(url: pollURL)
            pollReq.timeoutInterval = Self.pollTimeoutSeconds
            pollReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (pollData, pollResp) = try await URLSession.shared.data(for: pollReq)
            guard let pollHttp = pollResp as? HTTPURLResponse else {
                continue
            }
            // 401/404 是确定性错误，不应继续轮询到超时
            if pollHttp.statusCode == 401 || pollHttp.statusCode == 404 {
                let snippet = String(data: pollData.prefix(300), encoding: .utf8) ?? ""
                throw AgnesError.httpError(statusCode: pollHttp.statusCode, body: snippet)
            }
            if !(200..<300).contains(pollHttp.statusCode) {
                continue
            }
            guard let pollJSON = try JSONSerialization.jsonObject(with: pollData) as? [String: Any] else {
                continue
            }
            // /agnesapi 端点错误格式：`{"message":"...","success":false}` 没有 status
            if let success = pollJSON["success"] as? Bool, !success {
                let msg = (pollJSON["message"] as? String) ?? "video query failed"
                throw AgnesError.apiError(msg)
            }
            // 官方状态机：queued / in_progress / completed / failed
            let status = (pollJSON["status"] as? String ?? "").lowercased()
            // 进度：progress 字段是 0-100 整数，用它显示比 attempts 更准
            if let p = pollJSON["progress"] as? Int {
                lastProgress = p
            }
            onPoll?(attempts, lastProgress)   // 通知调用方更新 phase 文案

            if status == "completed" {
                // 视频 URL：remixed_from_video_id（官方文档确认）
                if let url = pollJSON["remixed_from_video_id"] as? String,
                   !url.isEmpty {
                    return url
                }
                // fallback 到 video_url / url（旧版兼容）
                if let url = pollJSON["video_url"] as? String
                           ?? pollJSON["url"] as? String,
                   !url.isEmpty {
                    return url
                }
                throw AgnesError.invalidResponse
            }
            if status == "failed" {
                // error 字段可能是 {message: "..."} 或字符串
                let err = pollJSON["error"]
                let msg: String
                if let s = err as? String {
                    msg = s
                } else if let obj = err as? [String: Any], let m = obj["message"] as? String {
                    msg = m
                } else {
                    msg = "video task failed"
                }
                throw AgnesError.apiError(msg)
            }
            // queued / in_progress → 继续轮询
        }
        throw AgnesError.timeout
    }

    // MARK: - Reset

    func reset() {
        isGeneratingImage = false
        isGeneratingVideo = false
        generatedImageURLs = []
        generatedVideoURL = nil
        imageError = nil
        videoError = nil
        imagePhase = ""
        videoPhase = ""
        videoProgress = 0
    }
}

// MARK: - Errors

enum AgnesError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case apiError(String)
    case timeout
    case submitTimeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "API URL 无效"
        case .invalidResponse: return "无效响应"
        case .httpError(let code, let body): return "HTTP \(code)：\(body)"
        case .apiError(let msg): return msg
        case .timeout: return "视频生成超时（10 分钟未完成）"
        case .submitTimeout: return "视频任务提交超时，请稍后重试"
        }
    }
}

// MARK: - Retry Helper

/// 网络层错误的重试策略：2 次重试，2s/5s 退避。
/// **只重试"明显是网络抖动"的错误**（URLError 的 connectionLost / timedOut / notConnected），
/// 不重试 HTTP 4xx/5xx（服务端已处理，不应重复创建任务）。
///
/// - 视频提交场景：服务端可能已创建任务但客户端没收到响应（-1005），重试有**重复创建任务**
///   的风险，但 Agnes 后端似乎没有 idempotency_key 支持，只能靠 UI 提示让用户知情。
/// - 图片生成场景：每次 prompt 1 张图，重复创建会浪费额度，但 2 次重试成功率 > 90%，
///   比直接失败让用户手动点重试的体感好。
enum RetryPolicy {
    static let maxAttempts: Int = 3         // 首次 + 2 次重试
    static let backoffSeconds: [UInt64] = [2, 5]   // 第 1 次重试等 2s,第 2 次等 5s

    /// 判定这个 error 是否值得重试。
    /// URLError（除 -1002 "用户取消" 外）+ AgnesError.submitTimeout / timeout / invalidResponse
    /// 都视为网络/瞬时错误，可重试。
    /// HTTP 4xx/5xx / apiError（"video task failed" 这种服务端业务错误）不重试。
    static func shouldRetry(_ error: Error) -> Bool {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet,      // -1009
                 .networkConnectionLost,       // -1005
                 .timedOut,                    // -1001
                 .cannotConnectToHost,         // -1004
                 .dnsLookupFailed,             // -1006
                 .cannotFindHost,              // -1003
                 .resourceUnavailable:         // -1008
                 return true
            case .cancelled:                   // -1002 用户主动取消 → 不重试
                return false
            default:
                return false
            }
        }
        if let agnes = error as? AgnesError {
            switch agnes {
            case .submitTimeout, .timeout, .invalidResponse:
                return true
            case .invalidURL, .httpError, .apiError:
                return false
            }
        }
        return false
    }
}

/// 通用重试包装：最多重试 2 次（2s/5s 退避），只对网络层错误生效。
/// - 每次重试前会调 `onRetry(retryNumber)` 让调用方更新 phase 文案。
/// - HTTP 4xx/5xx / apiError 等"服务端已处理"错误不重试，直接抛。
@MainActor
func withRetry<T>(
    _ block: () async throws -> T,
    onRetry: @MainActor (Int, Error) -> Void = { _, _ in }
) async throws -> T {
    var lastError: Error?
    for attempt in 0..<RetryPolicy.maxAttempts {
        do {
            return try await block()
        } catch {
            lastError = error
            // 不可重试 → 立即抛
            if !RetryPolicy.shouldRetry(error) {
                throw error
            }
            // 已经重试够多次 → 抛最后的错
            if attempt >= RetryPolicy.maxAttempts - 1 {
                throw error
            }
            // 计算退避时间
            let backoff = RetryPolicy.backoffSeconds[attempt]
            onRetry(attempt + 1, error)
            DebugLog.shared.warn(.agnes, "retrying after error", details: "attempt=\(attempt + 1)/\(RetryPolicy.maxAttempts - 1), wait=\(backoff)s, error=\(error.localizedDescription)")
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
        }
    }
    throw lastError ?? AgnesError.invalidResponse
}