//
//  GenerateViewHelpers.swift
//  RedPulse
//
//  LLM helpers and state management extracted from GenerateView.
//  Extracted from the original 1272-line GenerateView.
//

import Foundation
import SwiftUI

// MARK: - Quality Mode Toggle

struct QualityModeToggle: View {
    @AppStorage("llm_high_quality_mode") private var highQualityMode: Bool = false
    @Binding var isGenerating: Bool

    private var hasQualityModel: Bool {
        !(UserDefaults.standard.string(forKey: "llm_content_model_quality") ?? "").isEmpty
    }

    var body: some View {
        Button {
            guard hasQualityModel else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                highQualityMode.toggle()
            }
            DebugLog.shared.info(
                .llm,
                "quality mode toggled",
                details: "highQuality=\(highQualityMode)"
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: highQualityMode ? "sparkles" : "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(highQualityMode ? "高质量" : "快速")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(highQualityMode ? .white : Color.ink2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(highQualityMode ? Color.brand : Color.surfaceMuted, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(highQualityMode ? Color.clear : Color.border, lineWidth: BorderWidth.thin)
            )
            .opacity(hasQualityModel ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .contentShape(Rectangle())
    }
}

// MARK: - Generate Action Button

struct GenerateActionButton: View {
    @Binding var isGenerating: Bool
    let onGenerate: () -> Void

    private var enabled: Bool {
        !isGenerating
    }

    var body: some View {
        Button {
            HapticManager.heavyImpact()
            onGenerate()
        } label: {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                    Text("AI 撰写中...")
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                    Text("立即生成小红书笔记")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Adaptive.buttonHeight)
            .background(
                LinearGradient(
                    colors: [Color.brand, Color(red: 0.95, green: 0.08, blue: 0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            )
            .shadow(color: Color.brand.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.5)
        .keyboardShortcut("r", modifiers: .command)
        .coachMarkTarget("generate_button")
    }
}

// MARK: - Generation Helpers (LLM & error handling)

struct GenerationHelpers {
    /// "大模型刷新"按钮触发：基于当前选中产品上下文（无则通用风格）
    /// 让模型重写 6-10 个风格定调胶囊词（2-5 字），写入 hintChips。
    static func fetchHintChipsFromLLM(
        product: Product?,
        keyword: String,
        completion: @escaping ([String]) async -> Void
    ) async {
        let ctx = productContextLine(product: product, keyword: keyword)
        let prompt = """
        基于以下产品/关键词上下文，输出 8 个**写小红书笔记时可选的风格 / 角度提示词**。
        要求：
        - 每个 2-5 字
        - 例如「测评向」「干货风」「避雷指南」「问号钩子」这种风格定调
        - 不同提示词在角度上要互补，覆盖测评、教程、情绪、对比、避雷等
        \(ctx.isEmpty ? "" : ctx)
        严格输出 JSON 数组：["提示1","提示2",...]，不要 markdown 不要解释。
        """
        if let list = await chatJSONList(prompt: prompt, maxTokens: 200), !list.isEmpty {
            await completion(Array(list.prefix(10)))
        }
    }

    /// 用 LLM 生成小红书当前热门关键词（≤12 个），如有产品上下文会聚焦该产品所在领域。
    static func fetchKeywordsFromLLM(
        product: Product?,
        keyword: String
    ) async -> [String]? {
        let ctx = productContextLine(product: product, keyword: keyword)
        let prompt = """
        请输出 12 个**适合下面产品/关键词** 在小红书上的热门关键词或话题（每个 2-6 字）。
        要求：聚焦该产品所在的内容领域，结合当下趋势（2026 年），适合中国年轻女性用户。
        \(ctx.isEmpty ? "" : ctx)
        严格输出 JSON 数组：["关键词1","关键词2",...]，不要 markdown 代码块标记，不要解释。
        """
        return await chatJSONList(prompt: prompt, maxTokens: 300)
    }

    /// 把选中产品 / 当前关键词 / 风格提示 拼成简短上下文段落，给 LLM 做 prompt 参考。
    static func productContextLine(product: Product?, keyword: String) -> String {
        guard let p = product else {
            let kw = keyword.trimmingCharacters(in: .whitespaces)
            return kw.isEmpty ? "" : "\n[当前关键词]\n\(kw)"
        }
        var lines = ["产品名称：\(p.name)", "卖点：\(p.sellingPoint)"]
        if let t = p.targetAudience, !t.isEmpty { lines.append("目标人群：\(t)") }
        if let s = p.scenario, !s.isEmpty { lines.append("场景：\(s)") }
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty { lines.append("当前关键词：\(kw)") }
        return "\n[产品上下文]\n" + lines.joined(separator: "\n")
    }

    /// 通用 LLM JSON 数组返回工具：发请求 → 期望 content 是 JSON 数组 → 解析返回。
    static func chatJSONList(prompt: String, maxTokens: Int) async -> [String]? {
        let urlStr = UserDefaults.standard.string(forKey: "llm_content_url") ?? ""
        let key = UserDefaults.standard.string(forKey: "llm_content_key") ?? ""
        let model = UserDefaults.standard.string(forKey: "llm_content_model") ?? ""
        guard !urlStr.isEmpty, !key.isEmpty, !model.isEmpty,
              let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一个 JSON 输出机器人，只输出 JSON 数组，不输出任何其它内容。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.9,
            "max_tokens": maxTokens
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```") {
                if let nl = cleaned.firstIndex(of: "\n") {
                    cleaned = String(cleaned[cleaned.index(after: nl)...])
                }
                if cleaned.hasSuffix("```") {
                    cleaned = String(cleaned.dropLast(3))
                }
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let arr = try? JSONSerialization.jsonObject(with: cleaned.data(using: .utf8) ?? Data()) as? [String] else {
                return nil
            }
            return arr.filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }

    /// 把底层网络/解析错误转成用户能直接看懂的中文短句。
    static func friendlyErrorMessage(raw: String, error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut:
                return "网络超时，请检查 LLM 服务可达性或更换网络"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "无法连接到 LLM 服务，请到 设置 → 大模型 检查 URL"
            case .notConnectedToInternet:
                return "当前无网络连接"
            default:
                break
            }
        }
        if raw.contains("HTTP 401") || raw.contains("HTTP 403") {
            return "API Key 无效，请到 设置 → 大模型 检查"
        }
        if raw.contains("HTTP 429") {
            return "调用过于频繁，请稍后再试"
        }
        if raw.contains("HTTP 5") {
            return "LLM 服务异常，请稍后再试"
        }
        if raw.contains("URL / Key / Model 三件套未配齐") {
            return "尚未配置大模型，请到 设置 → 大模型 填写 URL/Key/Model"
        }
        if raw.contains("API URL 无效") {
            return "LLM URL 格式有误，请到 设置 → 大模型 修正"
        }
        if raw.contains("未返回合法 JSON") || raw.contains("响应缺少") || raw.contains("非 UTF-8") {
            return "模型返回格式异常，请换一个模型或重试"
        }
        return raw
    }
}
