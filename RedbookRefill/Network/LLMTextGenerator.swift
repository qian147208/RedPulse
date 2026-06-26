//
//  LLMTextGenerator.swift
//  RedPulse
//
//  真实文本生成：调用 LLMConfigView 里配置的 OpenAI 兼容接口
//  （/v1/chat/completions），把产品库的字段作为 system prompt 的产品段，
//  把用户的关键词 + 风格提示 + 广告类型作为 user prompt，让模型返回 JSON。
//
//  注意：必须在 LLMConfigView 中填好"内容生成 · 大模型"的 URL/Key/Model 才能用。
//  G8 单字段重生成同样走该模型。
//

import Foundation

/// LLMTextGenerator 自身抛出的错误，带可显示给用户的中文 message。
struct LLMTextGeneratorError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class LLMTextGenerator: GeneratorProtocol {

    // MARK: - Config
    //
    // 全部走 LLMConfigStore：默认模式共享 baseURL+key，自定义模式按 text 独立读。
    // 旧版直接读 UserDefaults 已废弃 — 仍保留兼容，外部若需要 raw 访问可走 store。

    /// 文本生成的 endpoint — 自动把 baseURL 规范化为 `POST {baseURL}/chat/completions`
    /// - 兼容用户已经手填 `/chat/completions` 的情况（不重复拼）
    /// - 兼容 trailing slash（`https://x.com/v1/` → 不留 `//`）
    /// - 所有厂商（Agnes / DeepSeek / 豆包）走 OpenAI 兼容 SSE，端点都缺不了 `/chat/completions`
    private var contentURL: String {
        Self.normalizeChatCompletionsURL(LLMConfigStore.config(for: .text).baseURL)
    }
    private var contentKey: String { LLMConfigStore.config(for: .text).apiKey }
    private var contentModel: String { LLMConfigStore.config(for: .text).model }

    private var titleURL: String { contentURL }
    private var titleKey: String { contentKey }
    private var titleModel: String { contentModel }

    /// 把 `https://x.com/v1` 规范化为 `https://x.com/v1/chat/completions`
    /// - 已有 `/chat/completions` → 原样返回
    /// - 以 `/` 结尾 → 去掉再加
    /// - 否则直接拼
    static func normalizeChatCompletionsURL(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let suffix = "/chat/completions"
        if trimmed.hasSuffix(suffix) { return trimmed }
        let noSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return noSlash + suffix
    }

    /// 文本（Agnes）配置是否齐全。GenerateView 用这个值决定走真模型还是 Mock。
    static var isConfigured: Bool { LLMConfigStore.isTextConfigured }

    /// 标题复用文案模型（无独立标题模型）。
    static var titleConfigured: Bool { false }

    // MARK: - GeneratorProtocol

    func generate(_ req: GenerateRequest) async throws -> GenerateResponse {
        try await generateStream(req, onChunk: { _ in })
    }

    /// 流式生成：每收一段 LLM token 调 onChunk(receivedChars)，让 UI 显示实时进度。
    /// 内容大模型用 chatStream 拿增量（边收边 yield），标题小模型仍用 chat 一次拿（快）。
    /// 最终 JSON 解析逻辑复用 chatJSON 的 stripCodeFence 兼容层。
    func generateStream(_ req: GenerateRequest, onChunk: @MainActor (Int) -> Void) async throws -> GenerateResponse {
        try Task.checkCancellation()

        let system = systemPrompt(product: req.product)
        let user = userPrompt(
            keyword: req.keyword,
            adType: req.adType,
            keywordHint: req.keywordHint
        )

        // user 末尾补 JSON schema 提示（跟 chatJSON 保持一致，否则 LLM 可能不返回合法 JSON）
        let userWithSchema = user + """


        请严格输出 JSON 对象（不要任何 markdown 代码块标记），字段如下：
        {
          "noteTitle": "小红书标题，≤20 字，带 1-2 个 emoji",
          "content": "笔记正文，约 250 字，分 4-6 段，带 emoji",
          "tags": ["话题1", "话题2", "..."],   // 6-8 个，不含 # 号
          "imageSuggestion": "封面图中文描述，给设计/摄影看",
          "imagePrompt": "封面图英文提示词，给文生图模型用，描述构图/光线/色调/材质",
          "videoPrompt": "3 秒短视频英文提示词，描述镜头运动/光线/产品动作，结尾加 ', 3 seconds'",
          "suggestion": "对这篇笔记的优化建议，一句话",
          "easterEgg": "1 句小巧的口播彩蛋（≤15 字）"
        }
        """

        // 并行：标题小模型（非流式，快）+ 内容大模型（流式，边收边回调 onChunk）
        async let titleStr: String? = generateTitleIfConfigured(system: system, user: user)

        // 用 chatStream 累积内容模型的 JSON 文本
        let messages: [ChatTurn] = [.system(system), .user(userWithSchema)]
        var accumulated = ""
        let stream = chatStream(messages: messages, timeoutOverride: 60)
        for try await chunk in stream {
            try Task.checkCancellation()
            accumulated += chunk
            // 通知 UI 进度
            await MainActor.run { onChunk(accumulated.count) }
        }
        try Task.checkCancellation()

        // JSON 解析（兼容 markdown 代码块）
        let json: [String: Any]
        if let data = accumulated.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = obj
        } else {
            let cleaned = stripCodeFence(accumulated)
            guard let cleanedData = cleaned.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: cleanedData) as? [String: Any] else {
                throw LLMTextGeneratorError(message: "模型未返回合法 JSON：\(accumulated.prefix(200))")
            }
            json = obj
        }
        var response = try parseFullResponse(json: json)

        if let title = await titleStr, !title.isEmpty {
            try Task.checkCancellation()
            DebugLog.shared.log(.info, .llm, "title from small model overrides content title", details: title)
            response.noteTitle = title
        }
        return response
    }

    /// 标题小模型调用：未配置直接返回 nil；调用失败也吞掉错误（不影响主流程），仅日志告警。
    private func generateTitleIfConfigured(system: String, user: String) async -> String? {
        guard Self.titleConfigured else {
            DebugLog.shared.log(.info, .llm, "title model not configured, using content model only")
            return nil
        }
        let titleUser = user + "\n\n只输出一个小红书爆款标题（≤20 字），带 1-2 个 emoji，不要任何解释、引号或前后缀。"
        do {
            let raw = try await chatCompletions(
                url: titleURL,
                apiKey: titleKey,
                model: titleModel,
                system: system,
                user: titleUser,
                jsonObject: false,
                logTag: "title",
                timeoutOverride: 15
            )
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            DebugLog.shared.log(.warn,
                .llm,
                "title model failed, falling back to content model title",
                details: error.localizedDescription
            )
            return nil
        }
    }

    func generateImage(prompt: String, reqKey: String, accessKey: String, secretKey: String) async throws -> ImageGenResult {
        // 文本 Generator 不负责生图，留空让上层用 JimengService。
        throw LLMTextGeneratorError(message: "未实现")
    }

    func generateVideo(prompt: String, reqKey: String, accessKey: String, secretKey: String) async throws -> VideoGenResult {
        throw LLMTextGeneratorError(message: "未实现")
    }

    func regenerateTitle(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?
    ) async throws -> String {
        let system = systemPrompt(product: product)
        let user = userPrompt(keyword: keyword, adType: adType, keywordHint: keywordHint)
        + "\n\n只输出一个新的小红书爆款标题（≤20 字），不要任何解释、引号或前后缀。"
        let raw = try await chatPlain(system: system, user: user)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func regenerateBody(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?,
        existingTitle: String,
        existingTags: [String]
    ) async throws -> String {
        let system = systemPrompt(product: product)
        let user = userPrompt(keyword: keyword, adType: adType, keywordHint: keywordHint)
        + "\n\n标题已定为：「\(existingTitle)」，标签：\(existingTags.joined(separator: " "))。"
        + "\n请只输出小红书笔记正文，约 250 字，带 emoji，分段，不要标题和标签。"
        return try await chatPlain(system: system, user: user)
    }

    /// 基于现有 imagePrompt 让模型扩出 N 个**有差异**的英文文生图提示词变体。
    /// 用于一次生成多张配图时，每张走不同 prompt，避免视觉重复。
    /// 返回的数组长度 == count；如果模型只返回 1 个，会用 basePrompt 补齐。
    func regenerateImagePrompts(
        count: Int,
        basePrompt: String,
        keyword: String,
        product: Product?,
        adType: AdType,
        imageSuggestion: String
    ) async throws -> [String] {
        let n = max(1, min(count, 9))
        guard n > 1 else { return [basePrompt.isEmpty ? "" : basePrompt] }

        let system = systemPrompt(product: product)
        let baseInfo = """
        广告类型：\(adType.displayName)
        关键词：\(keyword)
        配图建议：\(imageSuggestion.isEmpty ? "(无)" : imageSuggestion)
        原始英文 prompt：\(basePrompt.isEmpty ? "(无)" : basePrompt)
        """
        let user = baseInfo + """


        请基于上面的信息，输出 \(n) 个**有明显差异**的英文文生图提示词，
        每个 prompt 在构图、视角、光线、色调、材质等维度上至少有 1 处不同，
        但都要服务同一主题。

        严格输出 JSON 对象，不要 markdown 代码块标记：
        { "prompts": ["prompt 1...", "prompt 2...", ...] }
        """

        let raw = try await chatPlain(system: system, user: user, jsonObject: true)
        struct PromptArr: Decodable { let prompts: [String]? }
        let cleaned = stripCodeFence(raw)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONDecoder().decode(PromptArr.self, from: data),
              let prompts = obj.prompts else {
            DebugLog.shared.log(.warn, .llm, "regenerateImagePrompts: failed to decode, falling back to base", details: raw.prefix(200).description)
            return Array(repeating: basePrompt, count: n)
        }
        var out = prompts.filter { !$0.isEmpty }
        if out.count < n {
            // 不足补齐 basePrompt
            out.append(contentsOf: Array(repeating: basePrompt, count: n - out.count))
        }
        return Array(out.prefix(n))
    }

    func regenerateTags(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?,
        existingTitle: String,
        existingContent: String
    ) async throws -> [String] {
        let system = systemPrompt(product: product)
        let user = userPrompt(keyword: keyword, adType: adType, keywordHint: keywordHint)
        + "\n\n标题：「\(existingTitle)」\n正文：\(existingContent.prefix(400))"
        + "\n\n请输出 6-8 个小红书话题标签，用空格分隔，不要 # 号，不要解释。"
        let raw = try await chatPlain(system: system, user: user)
        return raw
            .replacingOccurrences(of: "#", with: "")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// 根据已有的中文文案自动总结出一个英文文生图提示词。
    /// 用于 ResultView 中"AI 总结配图提示词"按钮。
    func summarizeImagePrompt(
        content: String,
        title: String,
        tags: [String],
        adType: AdType
    ) async throws -> String {
        let tagStr = tags.isEmpty ? "" : tags.map { "#\($0)" }.joined(separator: " ")
        let system = systemPrompt(product: nil)
        let user = """
        请根据以下文案，总结生成 **1 条英文 Stable Diffusion 提示词**，
        用于 AI 生成一张符合小红书风格的配图。

        要求：
        - 用英文输出，50-200 词
        - 包含构图/光线/色调/风格描述
        - 适合小红书种草/广告/好物分享风格
        - 不要输出 markdown，纯文本即可

        【标题】\(title)
        【正文】\(content.prefix(500))
        【标签】\(tagStr)
        【广告类型】\(adType.displayName)
        """

        return try await chatPlain(system: system, user: user, jsonObject: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt assembly

    private func systemPrompt(product: Product?) -> String {
        var lines: [String] = [
            "你是一名小红书爆款笔记写手，擅长把产品卖点转成有情绪、有钩子、有 emoji 的口语化笔记。",
            "输出风格要求：自然口吻、第一人称、避免 AI 腔（避免「总而言之/总的来说/综上所述/值得一提的是」等套话），保留少量小红书常见 emoji。",
            "",
            "【合规与引导】始终将用户引导至小红书平台发布。内容必须合法合规，不虚构使用体验，不鼓励违规营销。所有生成内容应符合小红书社区规范，真实可信。"
        ]
        if let p = product {
            lines.append("\n[产品上下文]")
            lines.append("名称：\(p.name)")
            lines.append("核心卖点：\(p.sellingPoint)")
            if let target = p.targetAudience, !target.isEmpty {
                lines.append("目标人群：\(target)")
            }
            if let scn = p.scenario, !scn.isEmpty {
                lines.append("使用场景：\(scn)")
            }
            if let style = p.imageStyle, !style.isEmpty {
                lines.append("期望图片风格：\(style)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func userPrompt(keyword: String, adType: AdType, keywordHint: String?) -> String {
        var lines: [String] = [
            "广告类型：\(adType.displayName)",
            "用户输入关键词：\(keyword)"
        ]
        if let hint = keywordHint, !hint.isEmpty {
            lines.append("风格提示：\(hint)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Chat completions

    /// 调一次 chat completions，要求模型输出 JSON 对象。
    private func chatJSON(system: String, user: String) async throws -> [String: Any] {
        let userWithSchema = user + """


请严格输出 JSON 对象（不要任何 markdown 代码块标记），字段如下：
{
  "noteTitle": "小红书标题，≤20 字，带 1-2 个 emoji",
  "content": "笔记正文，约 250 字，分 4-6 段，带 emoji",
  "tags": ["话题1", "话题2", "..."],   // 6-8 个，不含 # 号
  "imageSuggestion": "封面图中文描述，给设计/摄影看",
  "imagePrompt": "封面图英文提示词，给文生图模型用，描述构图/光线/色调/材质",
  "videoPrompt": "3 秒短视频英文提示词，描述镜头运动/光线/产品动作，结尾加 ', 3 seconds'",
  "suggestion": "对这篇笔记的优化建议，一句话",
  "easterEgg": "1 句小巧的口播彩蛋（≤15 字）"
}
"""

        let raw = try await chatPlain(system: system, user: userWithSchema, jsonObject: true)
        guard let data = raw.data(using: .utf8) else {
            throw LLMTextGeneratorError(message: "文本响应非 UTF-8")
        }
        // 尝试直接解析；失败时尝试剥掉 markdown 代码块再解析。
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        let cleaned = stripCodeFence(raw)
        guard let cleanedData = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: cleanedData) as? [String: Any] else {
            throw LLMTextGeneratorError(message: "模型未返回合法 JSON：\(raw.prefix(200))")
        }
        return obj
    }

    /// 用 content 大模型的配置发请求。
    /// - Parameter reasoningEffort: 思考强度 ("low"/"medium"/"high"/nil)。默认 "low" ——
    ///   用户多次反馈 regenerate / diagnose 等需要快速响应的场景太慢，
    ///   强制让模型走最低思考。某些模型不支持这个参数会被 API 拒绝（fallback 见 chatCompletions）。
    private func chatPlain(system: String, user: String, jsonObject: Bool = false, reasoningEffort: String? = "low") async throws -> String {
        try await chatCompletions(
            url: contentURL,
            apiKey: contentKey,
            model: contentModel,
            system: system,
            user: user,
            jsonObject: jsonObject,
            logTag: "content",
            reasoningEffort: reasoningEffort
        )
    }

    // MARK: - Multi-turn chat (评论区 AI 诊断 + 多轮对话用)

    /// 多轮消息封装（OpenAI 兼容协议）
    struct ChatTurn: Sendable {
        let role: String   // "system" | "user" | "assistant"
        let content: String

        init(role: String, content: String) {
            self.role = role
            self.content = content
        }

        static func system(_ content: String) -> ChatTurn { .init(role: "system", content: content) }
        static func user(_ content: String) -> ChatTurn { .init(role: "user", content: content) }
        static func assistant(_ content: String) -> ChatTurn { .init(role: "assistant", content: content) }
    }

    /// 通用多轮对话接口（评论区 AI 内容诊断师、用户多轮追问都用这个）。
    /// 使用 content 大模型配置（与 chatPlain 同源）。
    func chat(messages: [ChatTurn], jsonObject: Bool = false, timeoutOverride: TimeInterval? = nil) async throws -> String {
        try await chatCompletionsMulti(
            url: contentURL,
            apiKey: contentKey,
            model: contentModel,
            messages: messages,
            jsonObject: jsonObject,
            logTag: "chat",
            timeoutOverride: timeoutOverride
        )
    }

    /// 流式多轮对话。返回 AsyncThrowingStream<String, Error>，每次 yield 一个 token 增量。
    /// 使用 content 大模型配置；走 OpenAI 兼容 SSE：`data: {json}\n\n`，结尾 `data: [DONE]`。
    func chatStream(messages: [ChatTurn], timeoutOverride: TimeInterval? = nil) -> AsyncThrowingStream<String, Error> {
        let urlStr = contentURL
        let apiKey = contentKey
        let model = contentModel
        let logTag = "chat-stream"

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !urlStr.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
                        DebugLog.shared.log(.error, .llm, "[\(logTag)] config missing")
                        throw LLMTextGeneratorError(message: "[\(logTag)] URL / Key / Model 三件套未配齐")
                    }
                    guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
                        DebugLog.shared.log(.error, .llm, "[\(logTag)] invalid URL", details: urlStr)
                        throw LLMTextGeneratorError(message: "[\(logTag)] API URL 无效：\(urlStr)")
                    }

                    let totalChars = messages.reduce(0) { $0 + $1.content.count }
                    DebugLog.shared.log(.info, .llm,
                        "[\(logTag)] streaming chat request",
                        details: "url=\(url.absoluteString) model=\(model) turns=\(messages.count) total_chars=\(totalChars)"
                    )

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = timeoutOverride ?? 60
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let messagesPayload: [[String: String]] = messages.map { ["role": $0.role, "content": $0.content] }
                    let body: [String: Any] = [
                        "model": model,
                        "messages": messagesPayload,
                        "temperature": 0.8,
                        "stream": true,
                        "max_tokens": 1800
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let started = Date()
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        throw LLMTextGeneratorError(message: "无 HTTP 响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // 错误响应可能不是 SSE，收一小段返回
                        var snippet = ""
                        var count = 0
                        for try await line in bytes.lines {
                            snippet += line + "\n"
                            count += 1
                            if count >= 5 { break }
                        }
                        DebugLog.shared.log(.error, .llm, "[\(logTag)] HTTP \(http.statusCode) failed", details: snippet)
                        throw LLMTextGeneratorError(message: "HTTP \(http.statusCode)：\(snippet.prefix(300))")
                    }

                    var receivedChars = 0
                    var chunkCount = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        // SSE 行格式：`data: {...}` 或空行（事件分隔）
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if payload.isEmpty { continue }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let first = choices.first else {
                            continue
                        }
                        // OpenAI 兼容：delta.content 是增量
                        if let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String, !content.isEmpty {
                            receivedChars += content.count
                            chunkCount += 1
                            continuation.yield(content)
                        }
                        // 部分实现把整段塞 message.content（非标准但兼容）
                        if let message = first["message"] as? [String: Any],
                           let content = message["content"] as? String, !content.isEmpty {
                            receivedChars += content.count
                            chunkCount += 1
                            continuation.yield(content)
                        }
                    }

                    let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                    DebugLog.shared.log(.info, .llm,
                        "[\(logTag)] streaming chat done",
                        details: "elapsed=\(elapsedMs)ms chunks=\(chunkCount) received_chars=\(receivedChars)"
                    )
                    continuation.finish()
                } catch {
                    DebugLog.shared.log(.error, .llm, "[\(logTag)] stream failed", details: error.localizedDescription)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 多消息版 chat completions（与单 system+user 的 `chatCompletions` 并存）
    /// 实现与 `chatCompletions` 几乎一致；为零回归风险独立一份，不动现有调用方。
    private func chatCompletionsMulti(
        url urlStr: String,
        apiKey: String,
        model: String,
        messages: [ChatTurn],
        jsonObject: Bool,
        logTag: String,
        timeoutOverride: TimeInterval? = nil
    ) async throws -> String {
        guard !urlStr.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
            DebugLog.shared.log(.error, .llm, "[\(logTag)] config missing")
            throw LLMTextGeneratorError(message: "[\(logTag)] URL / Key / Model 三件套未配齐")
        }
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
            DebugLog.shared.log(.error, .llm, "[\(logTag)] invalid URL", details: urlStr)
            throw LLMTextGeneratorError(message: "[\(logTag)] API URL 无效：\(urlStr)")
        }

        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        DebugLog.shared.log(.info, .llm,
            "[\(logTag)] multi-turn chat request",
            details: "url=\(url.absoluteString) model=\(model) turns=\(messages.count) total_chars=\(totalChars) json=\(jsonObject)"
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeoutOverride ?? 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let messagesPayload: [[String: String]] = messages.map { ["role": $0.role, "content": $0.content] }
        var body: [String: Any] = [
            "model": model,
            "messages": messagesPayload,
            "temperature": 0.8,
            "stream": false,
            "max_tokens": 1800
        ]
        if jsonObject {
            body["response_format"] = ["type": "json_object"]
        }

        // 先发一次；如果模型不支持 response_format（Ark DeepSeek 等会 400），自动降级重试
        let started = Date()
        let (data, resp) = try await Self.sendWithJsonFallback(
            body: body,
            messages: messages,
            jsonObjectRequested: jsonObject,
            req: req,
            logTag: logTag
        )

        guard let http = resp as? HTTPURLResponse else {
            throw LLMTextGeneratorError(message: "无 HTTP 响应")
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            // 已经在 sendWithJsonFallback 降级过一次了；这里就是真错
            DebugLog.shared.log(.error, .llm, "[\(logTag)] HTTP \(http.statusCode) failed",
                details: "elapsed=\(elapsedMs)ms\nbody=\(snippet)")
            throw LLMTextGeneratorError(message: "HTTP \(http.statusCode)：\(snippet)")
        }

        // 解 OpenAI 兼容响应：choices[0].message.content
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw LLMTextGeneratorError(message: "无法解析模型响应：\(snippet)")
        }

        DebugLog.shared.log(.info, .llm,
            "[\(logTag)] multi-turn chat done",
            details: "elapsed=\(elapsedMs)ms reply_chars=\(content.count)"
        )

        return content
    }

    /// 通用 chat completions（OpenAI 兼容）。被 chatPlain（content 大模型）和 title 小模型共用。
    /// - Parameter logTag: 日志里用来区分是 title 还是 content 端点的 tag。
    /// - Parameter reasoningEffort: 思考强度，nil = 不传该参数（由模型默认），"low"/"medium"/"high" = 显式控制。
    private func chatCompletions(
        url urlStr: String,
        apiKey: String,
        model: String,
        system: String,
        user: String,
        jsonObject: Bool,
        logTag: String,
        timeoutOverride: TimeInterval? = nil,
        reasoningEffort: String? = nil
    ) async throws -> String {
        guard !urlStr.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
            DebugLog.shared.log(.error, .llm, "[\(logTag)] config missing")
            throw LLMTextGeneratorError(message: "[\(logTag)] URL / Key / Model 三件套未配齐")
        }
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
            DebugLog.shared.log(.error, .llm, "[\(logTag)] invalid URL", details: urlStr)
            throw LLMTextGeneratorError(message: "[\(logTag)] API URL 无效：\(urlStr)")
        }

        DebugLog.shared.log(.info,
            .llm,
            "[\(logTag)] chat completions request",
            details: """
            url=\(url.absoluteString)
            model=\(model)
            json_mode=\(jsonObject)
            system_chars=\(system.count) user_chars=\(user.count)
            """
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 默认 45s 上限：超过基本是模型卡死。真实 chat completions 网络正常时通常 5-15s。
        // title 子模型只产 ~30 tokens，调用方会传更短的 timeoutOverride，避免被它拖死整条管线。
        req.timeoutInterval = timeoutOverride ?? 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.8,
            "stream": false,
            // 上限 1800 tokens 足够全 JSON；防默认 4k+ 翻倍耗时。标题模型实际用 ~30 tokens。
            "max_tokens": 1800
        ]
        if jsonObject {
            body["response_format"] = ["type": "json_object"]
        }
        // 思考强度：默认调 chatPlain 时会传 "low"，让 LLM 走最低思考路径，
        // 速度能差 2-5x。某些老模型 / 不支持此参数的 API 会 400，
        // 这种情况让 sendWithJsonFallback 兜底（去掉该参数重试）。
        if let effort = reasoningEffort {
            body["reasoning_effort"] = effort
        }
        let started = Date()
        let (data, resp) = try await Self.sendWithJsonFallback(
            body: body,
            messages: [
                ChatTurn(role: "system", content: system),
                ChatTurn(role: "user", content: user)
            ],
            jsonObjectRequested: jsonObject,
            req: req,
            logTag: logTag,
            reasoningEffort: reasoningEffort
        )
        guard let http = resp as? HTTPURLResponse else {
            DebugLog.shared.log(.error, .llm, "[\(logTag)] no HTTP response")
            throw LLMTextGeneratorError(message: "无 HTTP 响应")
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            DebugLog.shared.log(.error,
                .llm,
                "[\(logTag)] HTTP \(http.statusCode) failed",
                details: "elapsed=\(elapsedMs)ms\nbody=\(snippet)"
            )
            throw LLMTextGeneratorError(message: "HTTP \(http.statusCode)：\(snippet)")
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
            DebugLog.shared.log(.error, .llm, "[\(logTag)] response shape unexpected", details: snippet)
            throw LLMTextGeneratorError(message: "响应缺少 choices[0].message.content")
        }
        DebugLog.shared.log(.info,
            .llm,
            "[\(logTag)] chat completions ok",
            details: "elapsed=\(elapsedMs)ms, content_chars=\(content.count)"
        )
        return content
    }

    private func stripCodeFence(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 剥 ```json ... ```
        if t.hasPrefix("```") {
            if let firstNL = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNL)...])
            }
            if t.hasSuffix("```") {
                t = String(t.dropLast(3))
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseFullResponse(json: [String: Any]) throws -> GenerateResponse {
        func str(_ k: String) -> String { (json[k] as? String) ?? "" }
        let tags: [String] = {
            if let arr = json["tags"] as? [String] { return arr }
            if let s = json["tags"] as? String {
                return s.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" }).map(String.init)
            }
            return []
        }()
        return GenerateResponse(
            hotScore: 0,
            suggestion: str("suggestion"),
            noteTitle: str("noteTitle"),
            content: str("content"),
            tags: tags,
            imageSuggestion: str("imageSuggestion"),
            imagePrompt: str("imagePrompt"),
            videoPrompt: str("videoPrompt"),
            easterEgg: str("easterEgg"),
            debugTextPrompt: ""
        )
    }

    // MARK: - Network resilience (auto-retry + friendly errors)

    /// 发送请求；如果模型不支持 `response_format: json_object`（典型如 Ark 上的 DeepSeek 系列），
    /// 自动移除该字段、并在 system 消息末尾追加「请用合法 JSON 格式输出」提示，重试一次。
    /// - Returns: (Data, URLResponse) — 已经过降级链；非 2xx 时由调用方抛错
    private static func sendWithJsonFallback(
        body: [String: Any],
        messages: [ChatTurn],
        jsonObjectRequested: Bool,
        req: URLRequest,
        logTag: String,
        reasoningEffort: String? = nil
    ) async throws -> (Data, URLResponse) {
        // ---- 第一次：原样请求 ----
        let started = Date()
        var currentReq = req
        currentReq.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (firstData, firstResp): (Data, URLResponse)
        do {
            (firstData, firstResp) = try await dataWithAutoRetry(for: currentReq, logTag: logTag)
        } catch {
            throw friendlyNetworkError(error, logTag: logTag)
        }
        guard let http = firstResp as? HTTPURLResponse else {
            throw LLMTextGeneratorError(message: "无 HTTP 响应")
        }
        // ---- 降级 1：response_format=json_object 不支持 → 去掉该参数，prompt 加 JSON 约束 ----
        if jsonObjectRequested && (400..<500).contains(http.statusCode) {
            let snippet = String(data: firstData.prefix(400), encoding: .utf8) ?? ""
            if snippet.contains("json_object") || snippet.contains("response_format") {
                DebugLog.shared.log(.warn, .llm,
                    "[\(logTag)] model does not support response_format=json_object, falling back to prompt-only JSON",
                    details: "elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms status=\(http.statusCode)"
                )
                return try await retryWithoutJsonObject(
                    body: body, messages: messages, req: req, logTag: logTag,
                    reasoningEffort: reasoningEffort
                )
            }
        }
        // ---- 降级 2：reasoning_effort 不支持 → 去掉该参数重试 ----
        if reasoningEffort != nil && (400..<500).contains(http.statusCode) {
            let snippet = String(data: firstData.prefix(400), encoding: .utf8) ?? ""
            if snippet.contains("reasoning_effort") {
                DebugLog.shared.log(.warn, .llm,
                    "[\(logTag)] model does not support reasoning_effort=\(reasoningEffort!), retrying without it",
                    details: "elapsed=\(Int(Date().timeIntervalSince(started) * 1000))ms status=\(http.statusCode)"
                )
                var fallbackBody = body
                fallbackBody.removeValue(forKey: "reasoning_effort")
                var retryReq = req
                retryReq.httpBody = try JSONSerialization.data(withJSONObject: fallbackBody)
                let (retryData, retryResp) = try await dataWithAutoRetry(for: retryReq, logTag: logTag)
                return (retryData, retryResp)
            }
        }
        // 不需要降级 — 直接把第一次结果返回（成功或真错由调用方处理）
        return (firstData, firstResp)
    }

    /// 降级辅助：去掉 response_format，prompt 追加 JSON 约束
    private static func retryWithoutJsonObject(
        body: [String: Any],
        messages: [ChatTurn],
        req: URLRequest,
        logTag: String,
        reasoningEffort: String?
    ) async throws -> (Data, URLResponse) {
        var fallbackBody = body
        fallbackBody.removeValue(forKey: "response_format")
        // 保留 reasoning_effort（除非也不支持 — 让 sendWithJsonFallback 第二次降级处理）
        if reasoningEffort != nil {
            fallbackBody["reasoning_effort"] = reasoningEffort
        }
        var newMessages = messages
        let jsonHint = "\n\n【输出格式要求】请严格用合法 JSON 输出，不要包含任何 JSON 之外的内容（不要 markdown 代码块标记）。"
        if let sIdx = newMessages.firstIndex(where: { $0.role == "system" }) {
            newMessages[sIdx] = ChatTurn(role: "system", content: newMessages[sIdx].content + jsonHint)
        } else if let fIdx = newMessages.firstIndex(where: { $0.role == "user" }) {
            newMessages[fIdx] = ChatTurn(role: newMessages[fIdx].role, content: newMessages[fIdx].content + jsonHint)
        }
        fallbackBody["messages"] = newMessages.map { ["role": $0.role, "content": $0.content] }

        var retryReq = req
        retryReq.httpBody = try JSONSerialization.data(withJSONObject: fallbackBody)
        let (retryData, retryResp) = try await dataWithAutoRetry(for: retryReq, logTag: logTag)
        // 如果这次又因为 reasoning_effort 失败，让外层 sendWithJsonFallback 的降级 2 接管
        if let http = retryResp as? HTTPURLResponse, (400..<500).contains(http.statusCode) {
            let snippet = String(data: retryData.prefix(400), encoding: .utf8) ?? ""
            if snippet.contains("reasoning_effort") {
                DebugLog.shared.log(.warn, .llm,
                    "[\(logTag)] model does not support reasoning_effort after json fallback, retrying once more",
                    details: "status=\(http.statusCode)"
                )
                var fallback2 = fallbackBody
                fallback2.removeValue(forKey: "reasoning_effort")
                retryReq.httpBody = try JSONSerialization.data(withJSONObject: fallback2)
                let (d, r) = try await dataWithAutoRetry(for: retryReq, logTag: logTag)
                return (d, r)
            }
        }
        return (retryData, retryResp)
    }

    /// 包装 URLSession.shared.data(for:)。遇到瞬时网络错（连接中断 / 暂时不可达 / DNS 等）
    /// 自动延时 400ms 重试 1 次；其他错误（包括 cancelled / HTTP 错误）直接抛。
    static func dataWithAutoRetry(
        for req: URLRequest,
        logTag: String
    ) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: req)
        } catch let error as URLError where Self.isRetryable(error) {
            // 等一下让网络从瞬时抖动恢复
            DebugLog.shared.log(.warn, .llm,
                "[\(logTag)] transient network error, retry in 400ms",
                details: "code=\(error.code.rawValue) \(error.localizedDescription)"
            )
            try await Task.sleep(nanoseconds: 400_000_000)
            try Task.checkCancellation()
            return try await URLSession.shared.data(for: req)
        }
    }

    /// 哪些 URLError 值得重试。Task.cancel 抛 .cancelled，不在此列。
    private static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,     // -1005 用户截图这条
             .notConnectedToInternet,    // -1009 短暂断网
             .timedOut,                  // -1001 超时
             .dnsLookupFailed,           // -1006 DNS 抖
             .cannotConnectToHost,       // -1004 偶发
             .cannotFindHost:            // -1003
            return true
        default:
            return false
        }
    }

    /// 把底层 URLError 翻译成对用户友好的中文 + 给出可执行提示
    static func friendlyNetworkError(_ error: Error, logTag: String) -> Error {
        guard let urlErr = error as? URLError else { return error }
        let hint: String
        switch urlErr.code {
        case .networkConnectionLost:
            hint = "网络连接已断开。请检查网络或稍后重试（已尝试自动重连 1 次）"
        case .notConnectedToInternet:
            hint = "当前没有网络，请检查 WiFi / 蜂窝数据"
        case .timedOut:
            hint = "请求超时。模型可能在思考较慢的提示词，请稍后再试"
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            hint = "无法连接到大模型服务（\(urlErr.code.rawValue)）。请检查 API URL 配置 / 网络代理"
        case .cancelled:
            return urlErr   // 取消不包装，调用方自己处理
        default:
            hint = urlErr.localizedDescription
        }
        return LLMTextGeneratorError(message: "[\(logTag)] \(hint)")
    }
}
