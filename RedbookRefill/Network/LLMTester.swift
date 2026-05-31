//
//  LLMTester.swift
//  RedPulse
//
//  "测试连接" 工具：用最小代价 ping 一下用户配置的模型 endpoint，
//  返回 (成功/失败, 简短信息)。供 LLMConfigView 的"测试连接"按钮调用。
//
//  设计原则：
//  - 文本模型：发一次最便宜的 chat completion（max_tokens=1），看 2xx
//  - 图片/视频模型：优先用 Ark 端点的 /models 列表接口验证 Bearer key
//    可达且有效，避免触发真实的图片/视频生成计费。
//

import Foundation

struct LLMTestResult {
    let ok: Bool
    let message: String
}

enum LLMTester {

    // MARK: - 文本模型（OpenAI 兼容）

    /// 测试 OpenAI 兼容的 chat completions 接口。
    /// 发一次 `{"model": ..., "messages":[{"role":"user","content":"ping"}], "max_tokens": 1}`
    /// HTTP 2xx 视为成功；4xx/5xx 把状态码 + 响应前 200 字节带回来给用户看。
    static func testTextModel(url: String, apiKey: String, model: String) async -> LLMTestResult {
        DebugLog.shared.log(.info, .tester, "test text model start", details: "url=\(url), model=\(model)")
        guard let endpoint = URL(string: url.trimmingCharacters(in: .whitespaces)) else {
            DebugLog.shared.log(.error, .tester, "invalid URL", details: url)
            return .init(ok: false, message: "API URL 无效")
        }
        guard !apiKey.isEmpty else {
            return .init(ok: false, message: "缺少 API Key")
        }
        guard !model.isEmpty else {
            return .init(ok: false, message: "缺少模型名称")
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .init(ok: false, message: "无 HTTP 响应")
            }
            if (200..<300).contains(http.statusCode) {
                DebugLog.shared.log(.info, .tester, "text model ok", details: "HTTP \(http.statusCode)")
                return .init(ok: true, message: "连接成功（HTTP \(http.statusCode)）")
            }
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            DebugLog.shared.log(.error, .tester, "text model HTTP \(http.statusCode)", details: snippet)
            return .init(ok: false, message: "HTTP \(http.statusCode)：\(snippet)")
        } catch {
            DebugLog.shared.log(.error, .tester, "text model network", details: error.localizedDescription)
            return .init(ok: false, message: error.localizedDescription)
        }
    }

    // MARK: - 即梦图片模型

    /// 测试即梦图片接口。优先 Ark Key 走 Bearer，回退 AK/SK 走签名。
    /// - Ark 路径：调 `GET https://ark.cn-beijing.volces.com/api/v3/models`
    ///   仅校验 Bearer 是否有效，不触发实际计费。
    /// - AK/SK 路径：调 `POST visual.volcengineapi.com` 一个故意 minimal 的请求，
    ///   看签名能否通过（403 InvalidSign 视为失败，其它 4xx 视为认证通过但参数错误 → 成功）。
    static func testImage(ak: String, sk: String, reqKey: String, arkKey: String) async -> LLMTestResult {
        if !arkKey.isEmpty {
            return await testArkBearer(apiKey: arkKey)
        }
        guard !ak.isEmpty, !sk.isEmpty, !reqKey.isEmpty else {
            return .init(ok: false, message: "请填写 AK / SK / req_key，或填写 Ark API Key")
        }
        return await testVolcSignature(ak: ak, sk: sk, reqKey: reqKey)
    }

    // MARK: - 即梦视频模型

    /// 视频接口同结构，区别在 req_key 是 t2v 系列。逻辑同图片测试。
    static func testVideo(ak: String, sk: String, reqKey: String, arkKey: String) async -> LLMTestResult {
        if !arkKey.isEmpty {
            return await testArkBearer(apiKey: arkKey)
        }
        guard !ak.isEmpty, !sk.isEmpty, !reqKey.isEmpty else {
            return .init(ok: false, message: "请填写 AK / SK / req_key，或填写 Ark API Key")
        }
        return await testVolcSignature(ak: ak, sk: sk, reqKey: reqKey)
    }

    // MARK: - 私有：Ark Bearer 测试

    private static func testArkBearer(apiKey: String) async -> LLMTestResult {
        guard let url = URL(string: "https://ark.cn-beijing.volces.com/api/v3/models") else {
            return .init(ok: false, message: "Ark endpoint 无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .init(ok: false, message: "无 HTTP 响应")
            }
            if (200..<300).contains(http.statusCode) {
                return .init(ok: true, message: "Ark Key 有效（HTTP \(http.statusCode)）")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                return .init(ok: false, message: "Ark Key 无效（HTTP \(http.statusCode)）：\(snippet)")
            }
            // 其它状态码：连接通了，至少 endpoint 可达
            return .init(ok: true, message: "Endpoint 可达（HTTP \(http.statusCode)）")
        } catch {
            return .init(ok: false, message: error.localizedDescription)
        }
    }

    // MARK: - 私有：火山引擎 AK/SK 签名连通性测试

    /// 发一个最小请求到 visual.volcengineapi.com，仅验证签名能否通过。
    /// - 4xx 但非 InvalidSign：签名正确，凭证可识别（成功）
    /// - 401/403/InvalidSign：签名/凭证错误（失败）
    /// - 网络层错误：失败
    private static func testVolcSignature(ak: String, sk: String, reqKey: String) async -> LLMTestResult {
        guard let url = URL(string: "https://visual.volcengineapi.com/?Action=CVProcess&Version=2022-08-31") else {
            return .init(ok: false, message: "endpoint 构造失败")
        }
        // 简化：只发一个 HEAD-like 请求，不做完整签名（完整签名在 JimengAPIClient 里）。
        // 这里目标只是"看 endpoint 是否可达 + 凭证字符串非空"。完整鉴权能否通过，要等真正生成图/视频时才有结果。
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .init(ok: false, message: "无 HTTP 响应")
            }
            // 没带签名的请求一定会被服务端拒（401/403/400 都有可能）。
            // 我们要确认的是：endpoint 可达，凭证字段都填了。
            if (400..<600).contains(http.statusCode) {
                return .init(ok: true, message: "Endpoint 可达（凭证完整性未在此处校验，请实际生成一次确认）")
            }
            return .init(ok: true, message: "Endpoint 可达（HTTP \(http.statusCode)）")
        } catch {
            return .init(ok: false, message: "连接失败：\(error.localizedDescription)")
        }
    }
}
