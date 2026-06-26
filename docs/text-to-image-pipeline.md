# 生文 → 生图 → 生视频：端到端数据流

> 改这一块前必读。覆盖 GenerateView → ResultView → 后端 API 的完整链路。

---

## 整体架构（一图流）

```
┌─────────────────────────────────────────────────────────────────────────┐
│  GenerateView  (用户输入：产品 + 广告类型 + 关键词 + 风格提示)            │
│  ├─ GenerateStepStep1Product / Step2AdType / Step3Keyword / Step4Hint    │
│  └─ 点 "生成" → generator.generate(GenerateRequest)                      │
└─────────────┬───────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  LLMTextGenerator.generate(_:)   ← 单次 chatCompletions 拿全部 JSON      │
│                                                                         │
│  system = systemPrompt(product)         ← 产品上下文 + 风格人设          │
│  user   = userPrompt(keyword, adType, keywordHint) + JSON schema        │
│                                                                         │
│  async let contentJSON = chatJSON(...)    ← POST /v1/chat/completions   │
│  parseFullResponse(json)                  ← 8 字段解出                  │
└─────────────┬───────────────────────────────────────────────────────────┘
              │
              ▼ GenerateResponse { noteTitle, content, tags,
              │                    imageSuggestion, imagePrompt,
              │                    videoPrompt, easterEgg, suggestion }
              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ResultView  (生成结果页)                                                │
│  ├─ 一次性展示：标题 + 正文 + 标签 + 优化建议                              │
│  ├─ G8 单字段重生成：regenerateTitle / regenerateBody / regenerateTags  │
│  ├─ AI 总结配图：summarizeImagePrompt(正文 → 英文 imagePrompt)            │
│  └─ 改 imagePrompt / videoPrompt → 触发配图/视频                          │
└─────────────┬───────────────────────────────────────────────────────────┘
              │
              ▼ record.imagePrompt                    record.videoPrompt
              │
┌─────────────────────────────────────────────────────────────────────────┐
│  配图 / 视频生成                                                          │
│  ├─ 多张图：LLMTextGenerator.regenerateImagePrompts() 扩 N 个有差异 prompt │
│  └─ AgnesService.generateImages() / .generateVideo() 调 Agnes API       │
└─────────────────────────────────────────────────────────────────────────┘
```

**关键认知**：
- 正文（body/content）是**一次性产物**——只在 G1/G7 全量生成时产出，之后**不再回写**
- 后续改正文只能通过 G8 单字段重生成或划词 AI（局部改）
- 图/视频是**可重新触发的**——只要 imagePrompt/videoPrompt 还在 record 上

---

## 触发点清单

| 触发 | 函数 | 入口 UI |
|------|------|---------|
| G1 全量生成（首次） | `LLMTextGenerator.generate(_:)` | GenerateView → "生成" 按钮 |
| G7 换一批（全量重生成） | 同上 | ResultView → "换一批" 按钮 |
| **G8 重生标题** | `LLMTextGenerator.regenerateTitle(...)` | ResultView 标题卡片 ↻ |
| **G8 重生正文** | `LLMTextGenerator.regenerateBody(...)` | ResultView 正文卡片 ↻ |
| **G8 重生标签** | `LLMTextGenerator.regenerateTags(...)` | ResultView 标签卡片 ↻ |
| 划词 AI（局部改） | `LLMTextGenerator.transformText(...)` | ResultView 选中文字 → AI 操作 |
| AI 总结配图 | `LLMTextGenerator.summarizeImagePrompt(...)` | ResultView 配图区 "AI 总结" |
| 多张配图 prompt 扩写 | `LLMTextGenerator.regenerateImagePrompts(...)` | 自动，ResultView.generateImages() |
| 配图生成 | `AgnesService.generateImages(prompts:referenceImagesData:)` | ResultView → "生成配图" |
| 视频生成 | `AgnesService.generateVideo(prompt:referenceImageURLs:)` | ResultView → "生成视频" |

---

## 正文（content）生成的两条入口详解

### 入口 1：G1 / G7 全量生成

```swift
// LLMTextGenerator.generate(_ req: GenerateRequest)
let system = systemPrompt(product: req.product)
let user = userPrompt(
    keyword: req.keyword,
    adType: req.adType,
    keywordHint: req.keywordHint
)

async let titleStr: String? = generateTitleIfConfigured(...)  // 标题小模型（当前 disabled）
async let contentJSON: [String: Any] = chatJSON(system: system, user: user)

let json = try await contentJSON
var response = try parseFullResponse(json: json)
if let title = await titleStr, !title.isEmpty {
    response.noteTitle = title
}
return response
```

**核心是 `chatJSON()`**——一次拿全部 8 个字段 JSON，模型必须按 schema 返回（强制 `response_format: {type: "json_object"}`）。

### 入口 2：G8 重生正文

```swift
// LLMTextGenerator.regenerateBody(...)
let system = systemPrompt(product: product)
let user = userPrompt(keyword: keyword, adType: adType, keywordHint: keywordHint)
    + "\n\n标题已定为：「\(existingTitle)」，标签：\(existingTags.joined(separator: " "))。"
    + "\n请只输出小红书笔记正文，约 250 字，带 emoji，分段，不要标题和标签。"
return try await chatPlain(system: system, user: user)
```

走 `chatPlain()`（**不是** chatJSON）——只要正文，prompt 显式说"标题已定，别瞎改"，是**带上下文的续写**。

---

## Prompt 三段拼装

### System Prompt

```
你是一名小红书爆款笔记写手，擅长把产品卖点转成有情绪、有钩子、有 emoji 的口语化笔记。
输出风格要求：自然口吻、第一人称、避免 AI 腔（避免「总而言之/总的来说/综上所述/值得一提的是」等套话），保留少量小红书常见 emoji。

【合规与引导】始终将用户引导至小红书平台发布。内容必须合法合规，不虚构使用体验，不鼓励违规营销。所有生成内容应符合小红书社区规范，真实可信。

[产品上下文]                 ← 只有选了产品才拼
  名称：<name>
  核心卖点：<sellingPoint>
  目标人群：<targetAudience>   ← 可选
  使用场景：<scenario>          ← 可选
  期望图片风格：<imageStyle>    ← 可选
```

### User Prompt

```
广告类型：<AdType.displayName>
用户输入关键词：<keyword>
风格提示：<keywordHint>        ← 可选
```

### JSON Schema（chatJSON 追加）

```json
{
  "noteTitle":      "小红书标题，≤20字，带 1-2 个 emoji",
  "content":        "笔记正文，约 250 字，分 4-6 段，带 emoji",   ← 正文的硬规格
  "tags":           ["话题1", ...],   // 6-8 个，不含 # 号
  "imageSuggestion":"封面图中文描述",
  "imagePrompt":    "封面图英文提示词，构图/光线/色调/材质",
  "videoPrompt":    "3 秒短视频英文提示词，结尾加 ', 3 seconds'",
  "suggestion":     "优化建议一句话",
  "easterEgg":      "小巧口播彩蛋（≤15 字）"
}
```

---

## 网络层（`chatCompletions`）

```swift
private func chatCompletions(
    url urlStr: String,           // api_base_url
    apiKey: String,               // api_key
    model: String,                // agnes-2.0-flash
    system: String, user: String,
    jsonObject: Bool,             // 是否强制 JSON 模式
    logTag: String,
    timeoutOverride: TimeInterval? = nil
) async throws -> String
```

请求体（OpenAI 兼容）：
```json
{
  "model": "agnes-2.0-flash",
  "messages": [
    {"role": "system", "content": "<system>"},
    {"role": "user", "content": "<user>"}
  ],
  "temperature": 0.8,
  "stream": false,
  "max_tokens": 1800,
  "response_format": {"type": "json_object"}    // 仅 jsonObject=true 时
}
```

**默认超时 45s**——真实 chat 一般 5-15s，超过基本是模型卡死。标题子模型调用方传 15s 避免拖死。

**网络弹性**（`dataWithAutoRetry` + `friendlyNetworkError`）：
- 瞬时网络错（断连 / DNS / 超时）自动重试 1 次（400ms 后）
- URLError 翻译成中文友好提示

---

## 响应解析（`parseFullResponse`）

```swift
func parseFullResponse(json: [String: Any]) throws -> GenerateResponse {
    func str(_ k: String) -> String { (json[k] as? String) ?? "" }
    let tags: [String] = {
        if let arr = json["tags"] as? [String] { return arr }
        if let s = json["tags"] as? String {
            return s.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" }).map(String.init)
        }
        return []
    }()
    return GenerateResponse(
        hotScore: 0,                          // 后台字段，UI 不展示
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
```

**JSON 解析降级链**：
1. 直接 `JSONSerialization.jsonObject`
2. 失败 → `stripCodeFence()` 剥 ```json ... ``` 包裹
3. 还失败 → 抛 `"模型未返回合法 JSON：<前 200 字>"`

**`tags` 兼容**：可能是 JSON 数组或空格/逗号/中文逗号分隔的字符串。

---

## 生成后的 record 持久化

`ResultView` 拿到 `GenerateResponse` 后会构造一个 `record`，存进 `Repository`：

```swift
// ResultView 内部
let newRecord = GenerationRecord(
    inputKeyword: req.keyword,
    adType: req.adType.rawValue,
    noteTitle: response.noteTitle,
    content: response.content,
    tags: response.tags,
    imageSuggestion: response.imageSuggestion,
    imagePrompt: response.imagePrompt,
    videoPrompt: response.videoPrompt,
    easterEgg: response.easterEgg,
    ...
)
repository.saveRecord(newRecord)
record = newRecord
```

后续所有编辑都在 `record` 上做，最后调 `repository.saveRecord(record)` 落库。

---

## 改这块时要看的文件

| 改什么 | 文件 |
|--------|------|
| system / user / JSON schema | `Network/LLMTextGenerator.swift` → `systemPrompt` / `userPrompt` / `chatJSON` |
| 改标题/正文/标签单字段重生成 | `Network/LLMTextGenerator.swift` → `regenerateTitle` / `regenerateBody` / `regenerateTags` |
| 改划词 AI 指令 | `Network/LLMTextGenerator.swift` → `transformText` |
| 改多张配图 prompt 扩写 | `Network/LLMTextGenerator.swift` → `regenerateImagePrompts` |
| 改正文 → 配图 prompt 反推 | `Network/LLMTextGenerator.swift` → `summarizeImagePrompt` |
| 改 chat 通用请求层 | `Network/LLMTextGenerator.swift` → `chatCompletions` / `chatCompletionsMulti` / `chatStream` |
| 改 G1/G7 入口 | `Features/Generate/GenerateView.swift`（generator 计算逻辑） |
| 改 G8 UI 入口 | `Features/Result/ResultView.swift` → 标题/正文/标签卡片 |
| 改流式对话（SSE） | `Network/LLMTextGenerator.swift` → `chatStream` |

---

## 关键不变式

1. **`noteTitle` / `content` / `tags` 是 record 的「核心三件套」**——一旦写入 record，只通过 G8 走完整链路再生成，**不能由配图/视频路径回写**
2. **`imagePrompt` / `videoPrompt` 是「可重建字段」**——可以从正文反推（summarizeImagePrompt），可以扩写（regenerateImagePrompts）
3. **流式对话用 `chatStream`**——返回 `AsyncThrowingStream<String, Error>`，UI 用 `.onAppear` 启动 + `for await` 增量
4. **所有 LLM 调用都过 `DebugLog.shared` 的 `.llm` 分类**——出问题时先看日志，不要靠 print