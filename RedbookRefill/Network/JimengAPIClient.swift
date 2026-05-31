//
//  JimengAPIClient.swift
//  RedPulse
//
//  火山引擎即梦 OpenAPI 客户端。
//  使用 AK/SK HMAC-SHA256 签名 (Signature V4)。
//  Service: cv · Region: cn-north-1
//

import Foundation
import CryptoKit

final class JimengAPIClient {
    private let accessKey: String
    private let secretKey: String
    private let host = "visual.volcengineapi.com"
    private let service = "cv"
    private let region = "cn-north-1"
    private let version = "2022-08-31"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 即梦文生图同步返回，单张需 30-90s
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    // MARK: - Public API

    /// 文生图 / 图生图。返回图片 URL 列表。
    func generateImage(prompt: String, reqKey: String) async throws -> [String] {
        let body = JimengImageRequest(req_key: reqKey, prompt: prompt)
        let data = try await cvProcess(body: body)
        let resp = try JSONDecoder().decode(JimengImageResponse.self, from: data)
        guard resp.isSuccess, let urls = resp.data?.image_urls, !urls.isEmpty else {
            throw JimengError.apiFailed(resp.message)
        }
        return urls
    }

    /// 文生视频 / 图生视频。异步提交 → 轮询 → 返回视频 URL。
    /// - Parameter firstFrameURL: 图生视频的首帧图片 URL。传 nil/空字符串走 t2v；
    ///   传值时 reqKey 建议用 `jimeng_i2v_first_frame` 系列。
    func generateVideo(prompt: String, reqKey: String, firstFrameURL: String? = nil) async throws -> String {
        // 1. 提交任务
        let imageURLs: [String]? = {
            guard let url = firstFrameURL, !url.isEmpty else { return nil }
            return [url]
        }()
        let body = JimengVideoRequest(req_key: reqKey, prompt: prompt, image_urls: imageURLs)
        let submitData = try await cvProcess(body: body)
        let submitResp = try JSONDecoder().decode(JimengVideoSubmitResponse.self, from: submitData)
        guard submitResp.isSuccess, let taskId = submitResp.taskId else {
            throw JimengError.apiFailed(submitResp.message)
        }

        // 2. 轮询结果（最多 120 次 × 5s = 10 分钟）
        for attempt in 1...120 {
            try await Task.sleep(for: .seconds(5))

            let resultData = try await cvGetResult(taskId: taskId)
            let resultResp = try JSONDecoder().decode(JimengTaskResultResponse.self, from: resultData)

            if resultResp.isFailed {
                throw JimengError.generationFailed
            }
            if resultResp.isDone, let url = resultResp.videoURL {
                return url
            }
            // 继续轮询
            _ = attempt
        }
        throw JimengError.timeout
    }

    // MARK: - Low-level API calls

    private func cvProcess(body: Encodable) async throws -> Data {
        try await signedRequest(
            action: "CVProcess",
            body: body
        )
    }

    private func cvGetResult(taskId: String) async throws -> Data {
        struct TaskQuery: Encodable {
            let task_id: String
        }
        return try await signedRequest(
            action: "CVGetResult",
            body: TaskQuery(task_id: taskId)
        )
    }

    // MARK: - Signed HTTP Request

    private func signedRequest(action: String, body: Encodable) async throws -> Data {
        let bodyData = try JSONEncoder().encode(body)
        let url = URL(string: "https://\(host)/?Action=\(action)&Version=\(version)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")

        sign(request: &request, action: action, bodyData: bodyData)

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

    // MARK: - Signature V4

    private func sign(request: inout URLRequest, action: String, bodyData: Data) {
        let now = Date()
        let xDate = formatISO8601(now)       // yyyyMMdd'T'HHmmss'Z'
        let dateShort = formatDateShort(now) // yyyyMMdd

        let bodyHash = SHA256.hash(data: bodyData).hex

        request.setValue(xDate, forHTTPHeaderField: "X-Date")
        request.setValue(bodyHash, forHTTPHeaderField: "X-Content-Sha256")

        // Canonical headers (sorted alphabetically by header name)
        let canonicalHeaders = [
            "content-type:application/json",
            "host:\(host)",
            "x-content-sha256:\(bodyHash)",
            "x-date:\(xDate)",
        ].joined(separator: "\n")

        let signedHeaders = "content-type;host;x-content-sha256;x-date"

        // Canonical Query (sorted by key: Action < Version)
        let canonicalQuery = "Action=\(action)&Version=\(version)"
        let canonicalRequest = [
            "POST",
            "/",
            canonicalQuery,
            canonicalHeaders,
            "",
            signedHeaders,
            bodyHash,
        ].joined(separator: "\n")

        let canonicalRequestHash = SHA256.hash(data: canonicalRequest.data(using: .utf8)!).hex

        // String to Sign
        let credentialScope = "\(dateShort)/\(region)/\(service)/request"
        let stringToSign = [
            "HMAC-SHA256",
            xDate,
            credentialScope,
            canonicalRequestHash,
        ].joined(separator: "\n")

        // Signing Key
        let signingKey = deriveSigningKey(dateShort: dateShort)

        // Signature
        let signature = HMAC<SHA256>.authenticationCode(
            for: stringToSign.data(using: .utf8)!,
            using: signingKey
        ).hex

        // Authorization Header
        let auth = "HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
    }

    private func deriveSigningKey(dateShort: String) -> SymmetricKey {
        let skBytes = secretKey.data(using: .utf8)!
        let skKey = SymmetricKey(data: skBytes)

        let kDate = HMAC<SHA256>.authenticationCode(
            for: dateShort.data(using: .utf8)!,
            using: skKey
        )
        let kRegion = HMAC<SHA256>.authenticationCode(
            for: region.data(using: .utf8)!,
            using: SymmetricKey(data: Data(kDate))
        )
        let kService = HMAC<SHA256>.authenticationCode(
            for: service.data(using: .utf8)!,
            using: SymmetricKey(data: Data(kRegion))
        )
        let kSigning = HMAC<SHA256>.authenticationCode(
            for: "request".data(using: .utf8)!,
            using: SymmetricKey(data: Data(kService))
        )
        return SymmetricKey(data: Data(kSigning))
    }

    // MARK: - Date Helpers

    private func formatISO8601(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    private func formatDateShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }
}

// MARK: - Hex Encoding

extension Sequence where Element == UInt8 {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Error

enum JimengError: Error, LocalizedError {
    case apiFailed(String)
    case generationFailed
    case timeout
    case network
    case httpError(Int, Data)
    case missingConfig(String)

    var errorDescription: String? {
        switch self {
        case .apiFailed(let msg):    return "即梦 API 错误: \(msg)"
        case .generationFailed:      return "生成失败，请重试"
        case .timeout:               return "生成超时，模型还在思考，请稍后重试"
        case .network:               return "请检查网络连接"
        case .httpError(let code, let data):
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            return body.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(body)"
        case .missingConfig(let f):  return "缺少配置: \(f)"
        }
    }
}
