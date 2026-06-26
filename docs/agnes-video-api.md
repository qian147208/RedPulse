# Agnes 视频 API 集成要点

> **改视频生成前必读**。覆盖端点、字段名、错误格式、轮询、超时——和官方文档的差异都标了。

---

## 端点速查

| 动作 | 端点 | 方法 | Auth |
|------|------|------|------|
| **创建任务（推荐）** | `https://apihub.agnes-ai.com/v1/videos` | `POST` | `Bearer <api_key>` |
| **查询结果（推荐）** | `https://apihub.agnes-ai.com/agnesapi?video_id=<VIDEO_ID>&model_name=<MODEL>` | `GET` | `Bearer <api_key>` |
| 查询结果（兼容旧版） | `https://apihub.agnes-ai.com/v1/videos/{task_id}` | `GET` | `Bearer <api_key>` |

⚠️ **`/agnesapi` 不在 `/v1` 路径下**——代码里要用独立的 host（`agnesAPIBase`），不能拼到 `apiBaseURL` 后。

⚠️ **`POST /v1/videos/generations` 是错的**——文档明确是 `/videos`，不是 `/videos/generations`（早期代码曾用错）。

---

## 创建任务（POST /v1/videos）

### 请求体

```json
{
  "model": "agnes-video-v2.0",
  "prompt": "A cinematic shot of a cat walking on the beach...",
  "height": 768,            // 默认 768
  "width": 1152,            // 默认 1152
  "num_frames": 121,        // 必须 8n+1 且 ≤ 441（如 81/121/161/241/441）
  "frame_rate": 24          // 1-60
}
```

`image` / `mode` / `seed` / `negative_prompt` 等可选参数当前**未启用**——代码不传。

### 默认参数（代码里的 `videoDefaults`）

```swift
nonisolated static let videoDefaults: [String: Any] = [
    "width": 1152,
    "height": 768,
    "num_frames": 121,      // ≈ 5 秒
    "frame_rate": 24
]
```

### 创建响应（成功 200）

```json
{
  "id": "task_xxxxxx",
  "task_id": "task_xxxxxx",       // 与 id 相同
  "video_id": "video_xxxxxx",     // ← 推荐用这个查结果
  "object": "video",
  "model": "agnes-video-v2.0",
  "status": "queued",
  "progress": 0,
  "created_at": 1780457477,
  "seconds": "10.0",              // 实际视频时长（标准化后）
  "size": "1280x768"              // 实际分辨率（标准化后）
}
```

**三个 ID 字段都要 fallback**：`video_id` → `task_id` → `id`（兼容不同版本）。

---

## 查询结果（GET /agnesapi?video_id=...）

### URL 构造

```swift
var pollComps = URLComponents(string: "\(agnesAPIBase)/agnesapi")
pollComps?.queryItems = [
    URLQueryItem(name: "video_id", value: videoId),
    URLQueryItem(name: "model_name", value: videoModel)
]
```

- `video_id` 必填
- `model_name` 可选但建议加，显式指定模型更稳

### 轮询策略

| 参数 | 值 | 来源 |
|------|----|------|
| 轮询间隔 | **5 秒** | `Task.sleep(nanoseconds: 5_000_000_000)` |
| 总超时 | **8 分钟** | `timeout: 480`（实际生成 1-3 分钟，抽卡偶尔 5-7 分钟） |
| 单次 HTTP 超时 | 15 秒 | `pollReq.timeoutInterval = 15` |

⚠️ **5 秒间隔是文档推荐值**，不用改。
⚠️ **8 分钟超时比文档建议的 5 分钟宽**——避免抽卡高峰时被误杀。

### 状态判断（task status）

```swift
let status = (pollJSON["status"] as? String ?? "").lowercased()
if status == "completed" || status == "success" || status == "succeeded" {
    // 返回视频 URL
}
if status == "failed" || status == "error" {
    // 抛 AgnesError.apiError(message)
}
// 其他（queued / in_progress）继续轮询
```

兼容 `success` / `succeeded` 是防御性的——Agnes 文档只用 `completed` / `failed`。

---

## 视频 URL 字段名（新旧版本差异！）

⚠️ **关键坑**——字段名在 Agnes 后端升级时**改过**：

| 文档版本 | 字段名 | 值 |
|---------|-------|---|
| **新版**（v2.0 当前） | `remixed_from_video_id` | 视频 URL 字符串（字段名非常误导） |
| **旧版** | `video_url` | 视频 URL 字符串 |
| 最旧版 | `url` | 视频 URL 字符串 |

代码用三级 fallback 兜底：
```swift
if let url = pollJSON["remixed_from_video_id"] as? String
           ?? pollJSON["video_url"] as? String
           ?? pollJSON["url"] as? String,
   !url.isEmpty {
    return url
}
```

---

## 错误响应格式（**文档里没提**——这是实际探测出来的）

⚠️ **两个端点的错误响应格式完全不一样**——文档对此**完全沉默**：

### 提交端点（POST /v1/videos）错误格式

```json
{
  "error": {
    "code": "",
    "message": "无效的令牌 (request id: ...)",
    "type": "AgnesAI_error"
  }
}
```

HTTP 状态：401 / 400 / 500 等。

### 查询端点（GET /agnesapi）错误格式

```json
{
  "message": "无效的令牌",
  "success": false
}
```

⚠️ **`success: false` + 顶层 `message`**，**没有** `error` 包裹对象。

⚠️ **没有 `status` 字段**——所以光看 `status` 字段会**漏掉这种错误**，导致一直轮询到 8 分钟超时。

代码必须单独处理：
```swift
if let success = pollJSON["success"] as? Bool, !success {
    let msg = (pollJSON["message"] as? String) ?? "video query failed"
    throw AgnesError.apiError(msg)
}
```

### 任务失败时（status: failed）的 error 字段

文档说：`error` 字段是 `object / null`。代码兼容两种形态：
```swift
let err = pollJSON["error"]
let msg: String
if let s = err as? String {
    msg = s                              // 字符串形式（旧版）
} else if let obj = err as? [String: Any], let m = obj["message"] as? String {
    msg = m                              // {message: "..."} 形式（新版）
} else {
    msg = "video task failed"
}
```

---

## 401 / 404 立即 throw

```swift
if pollHttp.statusCode == 401 || pollHttp.statusCode == 404 {
    let snippet = String(data: pollData.prefix(300), encoding: .utf8) ?? ""
    throw AgnesError.httpError(statusCode: pollHttp.statusCode, body: snippet)
}
```

401（API Key 错）和 404（任务不存在）是**确定性错误**——继续轮询毫无意义，立即抛出。其他 4xx/5xx 视为瞬时错误，继续轮询。

---

## 完整调用流程（伪代码）

```
1. submitTask(prompt)
   ├─ POST {baseURL}/videos
   │   body: { model, prompt, width, height, num_frames, frame_rate }
   ├─ 读 video_id (fallback task_id → id)
   └─ 失败 → throw（带 error.message）

2. loop (max 8 min):
   ├─ sleep 5s
   ├─ GET {agnesAPIBase}/agnesapi?video_id=...&model_name=...
   ├─ 401/404 → throw
   ├─ 200 + {success: false} → throw（message 字段）
   ├─ {status: "completed"} → 读 URL 字段（remixed_from_video_id → video_url → url）→ return
   ├─ {status: "failed"} → throw（读 error.message）
   └─ 其他 → continue

3. 8 min 到 → throw AgnesError.timeout
```

---

## 改这块时的注意事项

1. **不要改 5 秒轮询间隔**——文档明确推荐值
2. **不要把 `/agnesapi` 拼到 `apiBaseURL` 后**——`apiBaseURL` 默认是 `/v1`，要单独 host
3. **不要忘记 `success: false` 处理**——只判断 `status` 字段会漏掉这种错误
4. **不要写死 `video_url` 字段名**——要用三级 fallback（`remixed_from_video_id` → `video_url` → `url`）
5. **5 分钟超时太紧**——抽卡高峰偶尔 5-7 分钟，保留 8 分钟
6. **所有调用过 `DebugLog.shared` 的 `.agnes` 分类**——出问题时看日志

---

## 调试技巧

看完整请求 / 响应：
```bash
# 提交（无效 token 会立刻暴露错误格式）
curl -sS -X POST "https://apihub.agnes-ai.com/v1/videos" \
  -H "Authorization: Bearer <your_key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"agnes-video-v2.0","prompt":"hi","width":1152,"height":768,"num_frames":121,"frame_rate":24}'

# 查询
curl -sS "https://apihub.agnes-ai.com/agnesapi?video_id=<VIDEO_ID>&model_name=agnes-video-v2.0" \
  -H "Authorization: Bearer <your_key>"
```

App 内查日志：Xcode → Debug Area → 过滤 `category: agnes`。

---

## 价格

| 类型 | 标准价格 | **当前价格** |
|------|---------|------------|
| Video Duration | $0.005 / second | **$0 / second** ← 免费 |

抽卡没成本顾虑，但**生产环境用商用 API 时记得改回**。