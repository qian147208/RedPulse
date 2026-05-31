//
//  ArkJimengClient.swift
//  RedPulse
//
//  火山引擎 Ark（方舟）平台客户端。
//  使用 API Key Bearer 认证，比 AK/SK SigV4 签名更简洁。
//  Endpoint: https://ark.cn-beijing.volces.com/api/v3
//

import Foundation

final class ArkJimengClient {
    private let apiKey: String
    private let baseURL = "https://ark.cn-beijing.volces.com/api/v3"
    private let defaultImageModel = "doubao-seedream-4-5-251128"
    private let defaultVideoModel = "doubao-seedance-1-0-pro-250528"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 方舟 Seedream 文生图同步返回，单张需 30-90s，
        // 设 180s 避免 N 张并行时首包超时。
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Image Generation

    /// Ark Seedream 文生图 / 图生图。
    /// - Parameter referenceImageData: 非 nil 时走 image-to-image：把参考图编码为
    ///   `data:image/...;base64,...` 形式塞到 body 的 `image` 字段。
    ///   方舟 seedream 系列支持 image 字段做风格/构图参考。
    func generateImage(prompt: String, model: String, referenceImageData: Data? = nil) async throws -> [String] {
        let imageModel = Self.resolveModel(requested: model, fallback: defaultImageModel)

        struct ImageReq: Encodable {
            let model: String
            let prompt: String
            let n: Int
            let size: String
            let response_format: String
            let image: String?
        }
        // 3:4 竖图适配小红书 feed 主流封面；1620x2880 = 4,665,600 像素，
        // 安全过线方舟 seedream 4 系列 ≥ 3,686,400 像素的硬性要求。
        let imageField: String? = {
            guard let data = referenceImageData, !data.isEmpty else { return nil }
            // 方舟接受 `data:image/<type>;base64,<...>` 形式，默认按 png 写头。
            let mime = Self.sniffMime(data: data)
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }()
        let body = ImageReq(
            model: imageModel,
            prompt: prompt,
            n: 1,
            size: "1620x2880",
            response_format: "url",
            image: imageField
        )

        let data = try await post(path: "/images/generations", body: body)

        struct ImageResp: Decodable {
            struct Item: Decodable { let url: String? }
            let data: [Item]?
        }
        let resp = try JSONDecoder().decode(ImageResp.self, from: data)
        let urls = resp.data?.compactMap(\.url) ?? []
        guard !urls.isEmpty else {
            throw JimengError.generationFailed
        }
        return urls
    }

    /// 用前 12 字节嗅探图片格式，返回 MIME 字符串（默认 png）。
    private static func sniffMime(data: Data) -> String {
        let head = data.prefix(12)
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if head.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if head.count >= 12,
           head[0...3] == Data([0x52, 0x49, 0x46, 0x46]),
           head[8...11] == Data([0x57, 0x45, 0x42, 0x50]) { return "image/webp" }
        return "image/png"
    }

    /// Ark 的 `model` 字段只接受方舟 model 名（如 `doubao-seedream-*`）。
    /// 老配置里常被填成 Volc 旧 API 的 req_key（如 `jimeng_t2i_v46`），方舟会返回 404。
    /// 这里把已知的 Volc 风格 req_key 自动映射到对应 Ark model 名。
    private static func resolveModel(requested: String, fallback: String) -> String {
        let trimmed = requested.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return fallback
        }
        if trimmed.hasPrefix("jimeng_") {
            if let mapped = volcToArkMap[trimmed] {
                DebugLog.shared.log(
                    .warn,
                    .jimeng,
                    "auto-converted Volc-style key \(trimmed) → \(mapped)",
                    details: "建议到「我的 → 大模型配置」把模型标识更新为 \(mapped)"
                )
                return mapped
            }
            DebugLog.shared.log(
                .warn,
                .jimeng,
                "unknown Volc-style key \(trimmed), falling back to \(fallback)",
                details: "请到「我的 → 大模型配置」把模型标识改成方舟 model 名"
            )
            return fallback
        }
        return trimmed
    }

    /// Volc 旧 API req_key → Ark model name 映射表。
    private static let volcToArkMap: [String: String] = [
        // 图片生成
        "jimeng_t2i_v46": "doubao-seedream-4-5-251128",
        "jimeng_t2i_v30": "doubao-seedream-4-5-251128",
        "jimeng_i2i_v30": "doubao-seedream-4-5-251128",
        // 视频生成
        "jimeng_i2v_v30_pro": "doubao-seedance-1-0-pro-250528",
        "jimeng_t2v_v30": "doubao-seedance-1-0-pro-250528",
        "jimeng_t2v_v30_pro": "doubao-seedance-1-0-pro-250528",
    ]

    // MARK: - Video Generation

    /// 文生视频 / 图生视频。方舟 Seedance 系列走异步任务接口：
    /// POST /contents/generations/tasks 提交 → 轮询 GET /contents/generations/tasks/{id}。
    /// - Parameter referenceImageURLs: 0 张走 t2v；1 张当首帧；≥2 张作为多帧参考（Seedance
    ///   会按首帧/末帧/参考的语义解读）。空数组等价之前的 firstFrameURL=nil。
    func generateVideo(prompt: String, model: String, referenceImageURLs: [String] = []) async throws -> String {
        let videoModel = Self.resolveModel(
            requested: model,
            fallback: defaultVideoModel
        )

        // Seedance 异步任务接口：model + content 数组（text / image_url）。
        struct ContentPart: Encodable {
            let type: String
            let text: String?
            let image_url: ImageURL?
            struct ImageURL: Encodable { let url: String }

            enum CodingKeys: CodingKey { case type; case text; case image_url }
        }
        struct TaskReq: Encodable {
            let model: String
            let content: [ContentPart]
        }
        var parts: [ContentPart] = [
            ContentPart(type: "text", text: prompt, image_url: nil)
        ]
        for url in referenceImageURLs where !url.isEmpty {
            parts.append(ContentPart(
                type: "image_url",
                text: nil,
                image_url: .init(url: url)
            ))
        }
        let submitData = try await post(
            path: "/contents/generations/tasks",
            body: TaskReq(model: videoModel, content: parts)
        )

        struct SubmitResp: Decodable {
            let id: String?
        }
        let submit = try JSONDecoder().decode(SubmitResp.self, from: submitData)
        guard let taskId = submit.id, !taskId.isEmpty else {
            throw JimengError.generationFailed
        }

        // 轮询：最多 120 次 × 5s = 10 分钟，与 AK/SK 路径保持一致。
        struct TaskResp: Decodable {
            let id: String?
            let status: String?
            let content: TaskContent?
            let error: TaskError?
            struct TaskContent: Decodable { let video_url: String? }
            struct TaskError: Decodable { let code: String?; let message: String? }
        }
        for _ in 1...120 {
            try await Task.sleep(for: .seconds(5))
            let pollData = try await get(path: "/contents/generations/tasks/\(taskId)")
            let task = try JSONDecoder().decode(TaskResp.self, from: pollData)
            switch task.status {
            case "succeeded":
                if let url = task.content?.video_url, !url.isEmpty {
                    return url
                }
                throw JimengError.generationFailed
            case "failed", "cancelled":
                throw JimengError.apiFailed(task.error?.message ?? "task \(task.status ?? "failed")")
            default:
                continue // queued / running / 其他中间态
            }
        }
        throw JimengError.timeout
    }

    // MARK: - HTTP

    private func post(path: String, body: Encodable) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func get(path: String) async throws -> Data {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw JimengError.timeout
        }
        guard let httpResp = response as? HTTPURLResponse else {
            throw JimengError.network
        }
        guard httpResp.statusCode == 200 else {
            throw JimengError.httpError(httpResp.statusCode, data)
        }
        return data
    }
}
