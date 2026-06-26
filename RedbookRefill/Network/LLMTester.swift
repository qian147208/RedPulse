//
//  LLMTester.swift
//  RedbookRefill
//
//  "测试连接" 工具：用最小代价 ping 一下用户配置的 endpoint。
//  Agnes AI 单一 endpoint，单一 Key，单一文本模型。
//

import Foundation

struct LLMTestResult {
    let ok: Bool
    let message: String
}

enum LLMTester {

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
}