# 数据层架构

> 改 Models / Repository 前必读。覆盖 SwiftData schema、Repository 模式、数据流。

---

## 三层架构

```
┌─────────────────────────────────────────────────────────────────┐
│  SwiftData Models (@Model)                                       │
│  ├─ Product                产品库                                 │
│  ├─ GenerationRecord       生成历史（核心，所有结果都存这）        │
│  ├─ Feedback               用户反馈                                │
│  └─ NoteComment            笔记评论                                │
└─────────────┬───────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Repository（唯一持有 ModelContext 的地方）                       │
│  Data/Repository.swift                                           │
│  ├─ 增删改查全部走这里                                            │
│  ├─ @MainActor 隔离（SwiftData 主线程约束）                       │
│  └─ saveRecord / fetchAllRecords / deleteRecord / updateRecord  │
└─────────────┬───────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  UI / Services（消费方）                                          │
│  ├─ ResultView：构造 record、调 saveRecord                       │
│  ├─ HistoryView：fetchAllRecords + 显示列表                       │
│  └─ ProfileView：产品库 CRUD                                     │
└─────────────────────────────────────────────────────────────────┘
```

**关键认知**：
- 所有 SwiftData 操作**必须经过 Repository**——UI 不直接拿 ModelContext
- `@MainActor` 隔离是因为 SwiftData ModelContext 默认不是 Sendable
- 所有 record 修改后调 `repository.saveRecord(record)` 落库

---

## Models（`RedbookRefill/Models/`）

### Product

```swift
@Model
final class Product {
    var name: String
    var sellingPoint: String
    var targetAudience: String?
    var scenario: String?
    var imageStyle: String?
    // SwiftData 会自动生成 id
}
```

**用途**：用户「我的 → 产品库」里添加的产品，写笔记时选中作为上下文。

### GenerationRecord（**核心**——所有生成结果都存这里）

```swift
@Model
final class GenerationRecord {
    var createdAt: Date
    var inputKeyword: String             // 用户输入的关键词
    var adType: String                   // 枚举 rawValue
    var noteTitle: String                // ← G1 产出或 G8 覆盖
    var content: String                  // ← G1 产出或 G8 重生
    var tags: [String]                   // ← G1 产出或 G8 重生
    var imageSuggestion: String          // 中文封面描述
    var imagePrompt: String              // 英文 imagePrompt（生成配图用）
    var videoPrompt: String              // 英文 videoPrompt
    var easterEgg: String                // 口播彩蛋
    var imageUrls: [String]              // 生成后的图片 URL 列表
    var videoUrl: String?                // 生成后的视频 URL
    var productId: UUID?                 // 关联 Product（可选）
    var hotScore: Int                    // 后台字段，UI 不展示
    var suggestion: String               // 优化建议
}
```

**关键认知**：
- `noteTitle` / `content` / `tags` 是「核心三件套」——只在 G1/G7 全量生成或 G8 单字段重生时被写入
- `imageUrls` / `videoUrl` 是「媒体字段」——可被配图/视频生成路径更新
- `hotScore` 是后台预留字段，UI 不展示
- `productId` 是关联 Product 的外键（但当前没强约束）

### Feedback / NoteComment

辅助模型，留给未来扩展：
- `Feedback`：用户反馈
- `NoteComment`：评论区诊断用

---

## Repository 模式

### 类签名

```swift
@MainActor
final class Repository {
    static let shared = Repository()
    private let modelContext: ModelContext    // 唯一 ModelContext

    // CRUD
    func saveRecord(_ record: GenerationRecord)
    func fetchAllRecords() -> [GenerationRecord]
    func deleteRecord(_ record: GenerationRecord)
    func updateRecord(_ record: GenerationRecord)

    // Products
    func saveProduct(_ product: Product)
    func fetchAllProducts() -> [Product]
    func deleteProduct(_ product: Product)
}
```

### 关键设计

1. **单例**：`Repository.shared` 全局唯一
2. **@MainActor 隔离**：SwiftData 操作必须在主线程
3. **唯一 ModelContext**：所有 SwiftData 操作走同一个 context（避免多 context 同步问题）
4. **直接传 Model 对象**：UI 拿到 `record` 后修改字段，最后调 `saveRecord` 落库

### 调用模式

```swift
// 创建
let newRecord = GenerationRecord(
    inputKeyword: req.keyword,
    adType: req.adType.rawValue,
    noteTitle: response.noteTitle,
    content: response.content,
    // ...
)
repository.saveRecord(newRecord)
record = newRecord

// 更新
record.noteTitle = newTitle
record.content = newContent
repository.saveRecord(record)

// 删除
repository.deleteRecord(record)

// 查询
let allRecords = repository.fetchAllRecords()
```

---

## 数据流（典型）

### 写入（GenerateView → ResultView）

```
1. 用户在 GenerateView 填表单，点 "生成"
2. generator.generate(req) 拿到 GenerateResponse
3. 构造 GenerationRecord（直接 init，字段从 response 复制）
4. repository.saveRecord(newRecord)
5. record = newRecord （赋值给 ResultView 的 @State）
6. UI 自动刷新（@Observable + @State）
```

### 更新（G8 重生正文）

```
1. 用户在 ResultView 点正文卡片 ↻
2. generator.regenerateBody(...) 拿到新正文 String
3. record.content = newContent       ← 直接改字段
4. repository.saveRecord(record)    ← 落库
```

### 删除

```
1. 用户在 HistoryView 滑动删除某条
2. repository.deleteRecord(record)
3. records.remove(record)            ← 同步刷新 UI 数组
```

---

## SwiftData 迁移注意事项

⚠️ **改 `@Model` schema 是高风险操作**——SwiftData 自动迁移在生产数据上有坑：

1. **加字段**：纯加 optional 字段安全；非 optional 字段必须有默认值
2. **删字段**：删前先在 App 启动时把旧数据迁移
3. **重命名字段**：用 `@Attribute(originalName:)` 标记
4. **改类型**：先迁移数据再改类型
5. **重命名 class**：用 `@Model(originalName:)` 标记

**遇到 schema 不兼容**：
```swift
// 红书笔芯 App 启动时如果 schema 改了会崩
// 临时解决方案（仅 dev）：删 app 重装 / 清沙盒
```

生产数据迁移代码：`RedbookRefillApp.swift` 启动时检查 + 迁移。

---

## UserDefaults 配置存储

**不存 SwiftData**——配置（API Key / URL）走 UserDefaults：

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `api_base_url` | String | `https://apihub.agnes-ai.com/v1` | LLM / Image base |
| `api_key` | String | `""` | Bearer Token |

**写入入口**：`Profile/LLMConfigView.swift`
**读取入口**：`Network/LLMTextGenerator.swift` / `Network/AgnesService.swift`

---

## DebugLog 配套

数据层出问题查日志：
```bash
Xcode → Debug Area → filter category=ui,tag=repo
```

常见的失败模式：
- **save 失败**：一般是 record 字段不合法（nil required field）
- **fetch 失败**：很少见，可能是 schema 损坏
- **删除失败**：record 已经被外部 context 删除

---

## 改这块时的注意事项

1. **不要在 UI 里直接拿 ModelContext**——所有 SwiftData 操作走 Repository
2. **不要并发访问同一 record**——SwiftData 不支持跨线程同一对象
3. **改 @Model schema 前**——先在测试数据上演练，确认自动迁移能跑通
4. **重要 record 字段改类型**——加迁移代码，不要简单改 schema
5. **saveRecord 一定要调**——SwiftData 不会自动落盘
6. **删 record 后 UI 数组同步删**——不然下次 fetch 会有 dangling reference