# 红书笔芯 iOS - 项目宪法

> 这是所有并行开发 agent 必须遵守的共享约定。优先级高于个人风格偏好。

## 项目背景

- **需求文档**：`/Users/mac/Desktop/红书笔芯/prototype/需求_融合版.md`（V3.2）
- **HTML 原型**：`/Users/mac/Desktop/红书笔芯/prototype/index.html`（V3.2 实现，可参考交互细节）
- **后端代理设计**：`/Users/mac/Desktop/红书笔芯/prototype/后端代理设计.md`
- **App 入口**：`RedbookRefill/RedbookRefillApp.swift`
- **Xcode 项目**：`RedbookRefill.xcodeproj`（objectVersion 77，文件系统同步组，新文件自动加入）

## 技术栈

- iOS 17.0+
- SwiftUI（不用 UIKit，除非必要）
- SwiftData（不用 CoreData）
- @Observable 宏（不用 ObservableObject）
- Swift Concurrency（async/await，不用 Combine）

## 目录结构（强制）

```
RedbookRefill/RedbookRefill/
├── RedbookRefillApp.swift          # 入口（Agent 1 改造）
├── ContentView.swift                # 路由根容器（Agent 1 改造）
├── DesignSystem/                    # Agent 1
│   ├── DesignTokens.swift
│   └── ViewModifiers.swift
├── Models/                          # Agent 1
│   ├── Product.swift                # @Model
│   ├── GenerationRecord.swift       # @Model
│   ├── Feedback.swift               # @Model
│   └── AdType.swift                 # enum
├── Data/                            # Agent 1
│   └── Repository.swift             # 唯一持有 ModelContext
├── Network/                         # Agent 1
│   ├── APIClient.swift              # 网络层
│   ├── MockGenerator.swift          # Mock 模式（首版用）
│   └── APIError.swift               # 错误码 enum
├── Features/
│   ├── Auth/                        # Agent 2
│   │   └── LoginView.swift
│   ├── Onboarding/                  # Agent 2
│   │   └── OnboardingView.swift
│   ├── Profile/                     # Agent 2
│   │   ├── ProfileView.swift
│   │   ├── SettingsView.swift
│   │   ├── HelpView.swift
│   │   └── FeedbackView.swift
│   ├── Library/                     # Agent 3
│   │   ├── ProductListView.swift
│   │   └── ProductFormView.swift
│   ├── Generate/                    # Agent 4
│   │   ├── HomeView.swift
│   │   ├── ResultView.swift
│   │   └── GenerateViewModel.swift
│   └── History/                     # Agent 4
│       ├── HistoryListView.swift
│       └── HistoryDetailView.swift
└── Assets.xcassets/
```

**核心规则**：每个 agent 只写自己目录下的文件。不跨目录创建/修改文件。共享类型在 Models/、Data/、Network/、DesignSystem/，由 Agent 1 定义，其它 agent 只读。

## 共享 API 契约（Agent 1 必须先定义这些，其它 agent 依赖它们）

### Repository 接口

```swift
@MainActor
final class Repository {
    // 单例由 RedbookRefillApp 注入 environment
    let modelContext: ModelContext

    // Products
    func allProducts() -> [Product]
    func saveProduct(_ p: Product)
    func deleteProduct(_ p: Product)

    // Records
    func allRecords() -> [GenerationRecord]  // 按 createdAt DESC
    func saveRecord(_ r: GenerationRecord)
    func deleteRecord(_ r: GenerationRecord)
    func clearAllRecords()

    // Feedback
    func saveFeedback(_ f: Feedback)
}
```

### GeneratorProtocol + APIClient

```swift
struct GenerateRequest {
    let recordId: UUID
    let keyword: String
    let adType: AdType
    let keywordHint: String?
    let product: Product?
    let images: [Data]       // ≤3 张产品图
    let styleImages: [Data]  // ≤3 张风格图
}

struct GenerateResponse {
    let hotScore: Int          // 后台监控字段，UI 不展示
    let suggestion: String     // 显示为独立卡片
    let noteTitle: String
    let content: String
    let tags: [String]
    let imageSuggestion: String
    let imagePrompt: String    // 不展示给用户
    let easterEgg: String
}

protocol GeneratorProtocol {
    func generate(_ req: GenerateRequest) async throws -> GenerateResponse
    func regenerateTitle(recordId: UUID, ...) async throws -> String
    func regenerateBody(recordId: UUID, ...) async throws -> String
    func regenerateTags(recordId: UUID, ...) async throws -> [String]
}

// 首版用 MockGenerator，按需求文档 Mock 逻辑
final class MockGenerator: GeneratorProtocol { ... }
```

### AdType 枚举

```swift
enum AdType: String, CaseIterable, Codable {
    case feedAd = "信息流广告"
    case searchAd = "搜索广告"
    case brandAd = "品牌广告"
    case salesNote = "带货笔记"
}
```

## 设计 Token（DesignTokens.swift）

```swift
extension Color {
    static let brand = Color(red: 1.0, green: 0.141, blue: 0.259)  // #FF2442 (light) / #FF4D6A (dark)
    static let brandSoft = Color(red: 1.0, green: 0.94, blue: 0.95) // #FFF0F2 (light) / #3D1520 (dark)
    static let ink = Color(red: 0.0, green: 0.0, blue: 0.0)         // #000000 (light) / #FFFFFF (dark)
    static let ink2 = Color(red: 0.235, green: 0.235, blue: 0.263)  // #3C3C43 (light) / #EBEBF5 (dark)
    static let ink3 = Color(red: 0.235, green: 0.235, blue: 0.263)  // alpha 0.6 (light) / alpha 0.6 (dark)
    static let bg = Color(red: 0.949, green: 0.949, blue: 0.969)    // #F2F2F7 (light) / #000000 (dark)
    static let surface = Color.white                                 // #FFFFFF (light) / #1C1C1E (dark)
    static let suggestionBlue = Color(red: 0.137, green: 0.310, blue: 0.580) // #234E94 (light) / #58A6FF (dark)
    static let suggestionBg = Color(red: 0.941, green: 0.961, blue: 0.988)    // #F0F5FC (light) / #0D1D30 (dark)
}

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
}
```

## 命名约定

- View：`XxxView`（如 `LoginView`，不要 `LoginScreen` / `LoginPage`）
- ViewModel：`XxxViewModel`，使用 `@Observable`
- Model：单数形（`Product` 不是 `Products`）
- 私有 helper：嵌套在使用它的 View 文件里，不创建新文件除非真的复用

## 不做的事

- 不写单元测试（首版聚焦能跑通）
- 不接真后端（Mock 模式）
- 不实现真实图片上传（占位 `[String]` 文件名，与原型一致）
- 不做埋点（按需求 §十三留空接口即可）
- 不做无障碍/本地化优化（仅中文 UI）
- 不用 emojis 装饰代码注释（按用户全局规则）

## 编译验证

- Xcode 完整安装但 `xcode-select` 指向 CLT，agent 不要尝试 `xcodebuild`
- 不做编译验证，最后由用户在 Xcode 里 build
- 写代码时**尽量保证语法和类型正确**，避免低级错误

## CLAUDE.md（项目根）的核心约束

每个 agent 必须遵守：
1. 不假设、不猜测、有疑问停下来
2. 最小代码量解决问题，不写投机抽象
3. 外科手术式改动，不改无关代码
4. 验证驱动：每步要能验证

---

**最重要的一条**：所有 agent 在开始写代码前，先读完这份宪法 + 需求 V3.2 文档相关章节。不要根据 HTML 原型猜规格，HTML 原型是参考、需求文档是权威。
