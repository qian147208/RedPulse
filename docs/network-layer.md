# 网络层架构

> 改任何 API 调用前必读。覆盖 LLMTextGenerator / AgnesService / JimengService 的设计模式、错误处理、超时策略。

---

## 三层架构

```
┌────────────────────────────────────────────────────────────────┐
│  UI Layer (SwiftUI Views)                                      │
│  GenerateView / ResultView / HistoryView                        │
│  只持有 GeneratorProtocol / AgnesService / JimengService 引用  │
└────────────┬───────────────────────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────────────┐
│  Service Layer (业务封装)                                       │
│  ├─ LLMTextGenerator  (文案生成：标题/正文/标签/...)             │
│  ├─ AgnesService       (图片 + 视频，OpenAI 兼容 + 异步轮询)    │
│  └─ JimengService      (火山引擎即梦，老接口，**当前未使用**)    │
└────────────┬───────────────────────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────────────┐
│  HTTP Layer (URLSession + JSONSerialization)                    │
│  ├─ chatCompletions()        ← LLM 调用通用函数                 │
│  ├─ dataWithAutoRetry()      ← 自动重试 + 错误翻译             │
│  └─ URLSession.shared        ← Apple 默认实现                  │
└────────────────────────────────────────────────────────────────┘
```

**关键认知**：
- 所有 HTTP 调用都用 Apple 原生 `URLSession`，无 Alamofire / Moya
- 无 SPM / CocoaPods 依赖
- 所有网络代码都是 `nonisolated static`（避免 @MainActor 隔离把请求 dispatch 回主线程）

---

## Generator Protocol 抽象

```swift
@MainActor
protocol GeneratorProtocol {
    func generate(_ req: GenerateRequest) async throws -> GenerateResponse
    func generateImage(prompt: String, ...) async throws -> ImageGenResult
    func generateVideo(prompt: String, ...) async throws -> VideoGenResult
    func regenerateTitle(...) async throws -> String
    func regenerateBody(...) async throws -> String
    func regenerateTags(...) async throws -> [String]
    func transformText(command: String, selectedText: String, context: String) async throws -> String
}
```

**两个实现**：

| 实现 | 何时用 | 入口 |
|------|-------|------|
| `LLMTextGenerator` | 配置了 API（`isConfigured == true`） | 真实调用 |
| `MockGenerator` | 没配 API 时 fallback | 返回假数据让 UI 跑起来 |

UI 用法：
```swift
private var generator: GeneratorProtocol {
    LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()
}
```

---

## LLMTextGenerator 详细解剖

### 内部状态

**所有配置从 UserDefaults 读**：
```swift
private var contentURL: String {
    UserDefaults.standard.string(forKey: "api_base_url") ?? "https://apihub.agnes-ai.com/v1"
}
private var contentKey: String {
    UserDefaults.standard.string(forKey: "api_key") ?? ""
}
private var contentModel: String { AgnesService.textModel }   // "agnes-2.0-flash"
```

**配置检查**（决定走真实还是 Mock）：
```swift
static var isConfigured: Bool {
    let url = UserDefaults.standard.string(forKey: "api_base_url") ?? ""
    let key = UserDefaults.standard.string(forKey: "api_key") ?? ""
    return !url.isEmpty && !key.isEmpty
}
```

### 公开方法清单

```swift
// 单次全量生成（G1/G7）
func generate(_ req: GenerateRequest) async throws -> GenerateResponse

// 单字段重生成（G8）
func regenerateTitle(...) async throws -> String
func regenerateBody(...) async throws -> String
func regenerateTags(...) async throws -> [String]

// 划词 AI
func transformText(command: String, selectedText: String, context: String) async throws -> String

// 多张配图 prompt 扩写
func regenerateImagePrompts(count: Int, basePrompt: String, keyword: String,
                            product: Product?, adType: AdType,
                            imageSuggestion: String) async throws -> [String]

// 反推配图 prompt
func summarizeImagePrompt(content: String, title: String, tags: [String],
                          adType: AdType) async throws -> String

// 通用多轮对话
func chat(messages: [ChatTurn], jsonObject: Bool) async throws -> String
func chatStream(messages: [ChatTurn]) -> AsyncThrowingStream<String, Error>
```

### 私有方法（HTTP 层）

```swift
// 单 system+user chat
private func chatCompletions(url: String, apiKey: String, model: String,
                             system: String, user: String,
                             jsonObject: Bool, logTag: String,
                             timeoutOverride: TimeInterval?) async throws -> String

// 多 messages chat
private func chatCompletionsMulti(url: String, ..., messages: [ChatTurn], ...) async throws -> String

// JSON 模式封装
private func chatJSON(system: String, user: String) async throws -> [String: Any]
private func chatPlain(system: String, user: String, jsonObject: Bool) async throws -> String
```

---

## AgnesService 详细解剖

### 状态（@Observable）

```swift
@MainActor
@Observable
final class AgnesService {
    var isGeneratingImage = false
    var isGeneratingVideo = false
    var generatedImageURLs: [String] = []
    var generatedVideoURL: String?
    var imageError: String?
    var videoError: String?

    var isConfigValidForImage: Bool { !apiKey.isEmpty }
    var isConfigValidForVideo: Bool { !apiKey.isEmpty }
}
```

### 配置（也走 UserDefaults）

```swift
private var apiBaseURL: String {
    UserDefaults.standard.string(forKey: "api_base_url") ?? "https://apihub.agnes-ai.com/v1"
}
private var apiKey: String {
    UserDefaults.standard.string(forKey: "api_key") ?? ""
}

nonisolated static let textModel = "agnes-2.0-flash"
nonisolated static let imageModel = "agnes-image-2.1-flash"
nonisolated static let videoModel = "agnes-video-v2.0"
nonisolated static let agnesAPIBase = "https://apihub.agnes-ai.com"  // 注意：不是 /v1
nonisolated static let videoDefaults: [String: Any] = [
    "width": 1152, "height": 768,
    "num_frames": 121, "frame_rate": 24
]
```

### 公开方法

```swift
// 图片
func generateImage(prompt: String) async
func generateImages(prompts: [String], referenceImagesData: [Data] = []) async
nonisolated static func callImageAPI(baseURL: String, apiKey: String,
                                      prompt: String) async throws -> [String]

// 视频
func generateVideo(prompt: String, referenceImageURLs: [String] = []) async
nonisolated static func callVideoAPI(baseURL: String, apiKey: String,
                                      prompt: String) async throws -> String

// 重置
func reset()
```

---

## 通用模式

### 1. 请求构造（chatCompletions 模板）

```swift
var req = URLRequest(url: url)
req.httpMethod = "POST"
req.timeoutInterval = timeoutOverride ?? 45
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

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
req.httpBody = try JSONSerialization.data(withJSONObject: body)
```

### 2. 响应解析（OpenAI 兼容）

```swift
guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = obj["choices"] as? [[String: Any]],
      let first = choices.first,
      let message = first["message"] as? [String: Any],
      let content = message["content"] as? String else {
    throw LLMTextGeneratorError(message: "无法解析模型响应：<snippet>")
}
```

### 3. 流式响应（SSE）

```swift
func chatStream(...) -> AsyncThrowingStream<String, Error> {
    return AsyncThrowingStream { continuation in
        let task = Task {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                // 解析 delta.content
                continuation.yield(content)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

---

## 网络弹性（自动重试 + 错误翻译）

### `dataWithAutoRetry`

```swift
static func dataWithAutoRetry(for req: URLRequest, logTag: String) async throws -> (Data, URLResponse) {
    do {
        return try await URLSession.shared.data(for: req)
    } catch let error as URLError where Self.isRetryable(error) {
        // 400ms 后重试 1 次
        try await Task.sleep(nanoseconds: 400_000_000)
        try Task.checkCancellation()
        return try await URLSession.shared.data(for: req)
    }
}
```

### 可重试的 URLError

```swift
case .networkConnectionLost,     // -1005 断连
     .notConnectedToInternet,    // -1009 断网
     .timedOut,                  // -1001 超时
     .dnsLookupFailed,           // -1006 DNS
     .cannotConnectToHost,       // -1004
     .cannotFindHost:            // -1003
    return true
```

### `friendlyNetworkError`（URLError → 中文）

| 错误码 | 用户提示 |
|-------|---------|
| `.networkConnectionLost` | 网络连接已断开。请检查网络或稍后重试 |
| `.notConnectedToInternet` | 当前没有网络，请检查 WiFi / 蜂窝数据 |
| `.timedOut` | 请求超时。模型可能在思考较慢的提示词 |
| `.cannotConnectToHost` / `.cannotFindHost` / `.dnsLookupFailed` | 无法连接到大模型服务。请检查 API URL 配置 / 网络代理 |

---

## 取消支持（Task.checkCancellation）

所有 LLM 调用的关键 await 节点都加：
```swift
try Task.checkCancellation()
```

用户切页面 / 退出时会自动取消，不会浪费 token。

---

## DebugLog 分类约定

```swift
DebugLog.shared.log(.info, .llm,    "...", details: "...")
DebugLog.shared.log(.info, .agnes,  "video generate start", details: "...")
DebugLog.shared.log(.info, .jimeng, "...")
DebugLog.shared.log(.info, .ui,     "...")
DebugLog.shared.error(.llm, "...", details: error.localizedDescription)
```

**所有网络调用必须加 DebugLog**——出问题时先看日志，类别 + tag + elapsed_ms + payload snippet 一目了然。

---

## 改这块时的注意事项

1. **`nonisolated static` 不可省**——发请求的函数必须是 `nonisolated static`，不然 `@MainActor` 隔离会强制回主线程
2. **`Task.checkCancellation()` 必加**——每个 await 前点一下
3. **不要自己写 SSE 解析**——直接复制 `chatStream` 模板，OpenAI 兼容格式是 `data: {...}\n\ndata: [DONE]`
4. **超时不要用默认 60s**——chat 一般 5-15s，45s 够；超时多半是模型卡死，重试无意义
5. **错误用 `enum X: LocalizedError`**——`errorDescription` 返回中文，不要 throw String
6. **JSON 解析双保险**——直接解析 + `stripCodeFence()` 剥 markdown 包裹
7. **UserDefaults key 别拼写错**——`api_base_url` 和 `api_key` 是约定，UI 那边也是这俩