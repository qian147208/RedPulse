//
//  LLMModelListFetcher.swift
//  RedbookRefill
//
//  调 GET {baseURL}/models 拉取厂商提供的模型列表。
//  支持 OpenAI 兼容的 `{data: [{id, ...}]}` 格式（DeepSeek / Kimi / MiniMax / Qwen / Agnes）。
//  豆包（Ark）走自己的 `{data: [{id, ...}, ...]}` 格式但 id 字段不同，需要单独解析。
//
//  失败 / 返回异常时返回空数组；调用方按 UI 提示。
//

import Foundation

enum LLMModelListFetcher {

    struct FetchResult: Equatable {
        let models: [String]
        let rawError: String?    // 任何错误信息，nil = 成功
    }

    /// 调 GET {baseURL}/models 拉模型列表
    static func fetch(baseURL: String, apiKey: String) async -> FetchResult {
        guard !baseURL.isEmpty, !apiKey.isEmpty,
              let url = URL(string: "\(baseURL.trimmingCharacters(in: .whitespaces))/models") else {
            return FetchResult(models: [], rawError: "URL / Key 缺失")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return FetchResult(models: [], rawError: "无 HTTP 响应")
            }
            guard (200..<300).contains(http.statusCode) else {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                return FetchResult(models: [], rawError: "HTTP \(http.statusCode): \(snippet)")
            }
            let models = parseModels(data: data)
            return FetchResult(models: models, rawError: models.isEmpty ? "返回为空" : nil)
        } catch {
            return FetchResult(models: [], rawError: error.localizedDescription)
        }
    }

    /// 解析 OpenAI 兼容 /models 返回：{ "object": "list", "data": [{ "id": "...", ... }] }
    /// 豆包返回 { "data": [{ "id": "ep-...", ... }] } 也兼容。
    private static func parseModels(data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let arr = obj["data"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { $0["id"] as? String }
            .filter { !$0.isEmpty }
            .sorted()
    }
}
