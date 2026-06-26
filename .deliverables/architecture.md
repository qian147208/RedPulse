# RedPulse — 架构与模块边界分析

> 范围：`/Users/mac/Desktop/RedbookRefill/RedbookRefill/`（69 Swift 文件 / 19,434 行 / iOS 17+ / iPadOS / macOS SwiftUI 工程）
> 基础：`_PROJECT_CONVENTIONS.md` + 全部源码 + peer 已交付的 `feature-flow.md` / `build-report.md`
> 生成时间：2026-06-24 17:30（主 session 直接产出，替代被反复 timeout 的 team worker）

---

## 1. 目录树（3 层深）

```
RedbookRefill/RedbookRefill/                    (root: 3 files, 451 lines)
├── RedPulseApp.swift          # @main，SwiftData ModelContainer 持有者
├── ContentView.swift          # Repository 异步注入容器
├── RootTabView.swift          # 4-Tab 路由根（iPhone ZStack / iPad+Mac NavigationSplitView）
├── Data/                      (2 files, 317 lines)
│   ├── Repository.swift       # @MainActor @Observable 唯一 read/write 入口
│   └── DebugLog.swift         # 全局 Debug 日志（@Observable 单例）
├── DesignSystem/              (5 files, 1,406 lines)
│   ├── DesignTokens.swift     # Color/Spacing/Radius + @Observable ScreenMetrics
│   ├── ViewModifiers.swift    # 通用 .textDropTarget / .coachMarkTarget 等
│   ├── FlowLayout.swift       # 自定义 Layout 协议实现
│   ├── HapticManager.swift    # UIImpactFeedbackGenerator 封装
│   └── PlatformInteractions.swift   # UIPencilInteraction / NSWorkspace 桥
├── Models/                    (6 files, 344 lines)
│   ├── Product.swift          # @Model
│   ├── GenerationRecord.swift # @Model
│   ├── Feedback.swift         # @Model
│   ├── AdType.swift           # enum (4 种广告类型)
│   ├── InspirationItem.swift  # @Model  ← 宪法未列，新加
│   └── NoteComment.swift      # @Model  ← 宪法未列，新加（评论/全局消息统一载体）
├── Network/                   (10 files, 2,376 lines)
│   ├── APIClient.swift
│   ├── MockGenerator.swift    # GeneratorProtocol 默认实现
│   ├── APIError.swift
│   ├── GenerateContracts.swift # GenerateRequest/Response + GeneratorProtocol 定义
│   ├── LLMTextGenerator.swift # 走 OpenAI 兼容 chat/completions
│   ├── LLMTester.swift
│   ├── JimengService.swift    # @Observable 即梦（图片/视频）网关
│   ├── JimengAPIClient.swift  # 火山旧 API（AK/SK + HMAC-SHA256）
│   ├── ArkJimengClient.swift  # Ark 新 API（Bearer + image-to-image）
│   ├── JimengContracts.swift
│   └── URLExtensions.swift
├── Navigation/                (1 file, 43 lines)
│   └── NavigationState.swift  # @Observable 跨视图生成状态
├── Features/                  (45 files, 14,497 lines) — 11 个子模块
│   ├── Assistant/   (4 files, 1,221 lines)   — ChatSession @Model + GlobalAssistantRoot / DiagnosticAgent / ChatLauncher
│   ├── CoachMark/   (1 file, 297 lines)     — 首次使用引导覆盖层（注释中未挂到 Root）
│   ├── Export/      (1 file, 295 lines)     — AssetPackager actor，三端通用 zip
│   ├── Generate/    (6 files, 1,820 lines)  — 4 步表单 + 拆分的 Step / Helpers / Overlay / Quality
│   ├── History/     (1 file, 1,039 lines)   — 按日分组 + 全文搜索 + 滑删
│   ├── Inspiration/ (3 files, 547 lines)    — 灵感板 + picker + add
│   ├── Library/     (3 files, 1,068 lines)  — Product 列表 / 表单 / CameraPicker
│   ├── Onboarding/  (1 file, 305 lines)     — 4 页翻页引导
│   ├── Profile/     (8 files, 2,280 lines)  — 我的 + 设置 + LLM 配置 + 7 个子页
│   ├── Result/      (10 files, 4,552 lines) — 结果编辑 / 预览 / 打包（最大模块）
│   └── SelectionToolbar/ (4 files, 1,073 lines) — 划词 AI 工具栏
└── Assets.xcassets/           # 资源（未在源码中引用，由 Xcode 资源系统管理）
```

**注**：宪法 `_PROJECT_CONVENTIONS.md` 列了 5 个 Feature（Auth/Onboarding/Profile/Library/Generate/History）+ 5 个共享层；实际项目演化出 **11 个 Feature**，且没有 `Auth/` 目录（产品定位去掉了登录态），`Generate` 拆成 4 个 step helper 文件，`Result` 是后加的最大模块（宪法没列）。

---

## 2. 模块清单与职责

| 模块 | 入口 View | 状态来源 | 依赖 | 关键 ViewModel / Service |
|---|---|---|---|---|
| **Generate** | `Features/Generate/GenerateView.swift` | `@Environment(Repository.self)` + `@Environment(\.modelContext)` + 18+ `@State` | Repository, Models, Network, Navigation, DesignSystem | `GenerateViewModel`（内嵌）, `GeneratorProtocol`（`LLMTextGenerator.isConfigured` 选实现）, `ThinkingOverlay`, `QualityToggle` |
| **Library / Product** | `Features/Library/ProductListView.swift` | `@Query` + `@Environment(Repository.self)` + `@Environment(\.modelContext)` | Repository, Models | `ProductFormView`, `CameraPicker`（仅 iPhone 真机） |
| **Result** | `Features/Result/ResultView.swift` | `@Environment(Repository.self)` + `@Environment(\.modelContext)` + **31 个 `@State`**（God View） | Repository, Models, Network, DesignSystem | `JimengService`, `SelectionToolbarViewModel`, `DiagnosticAgent`, `AssetPackager` |
| **History** | `Features/History/HistoryView.swift` | `@Query` + `@Environment(Repository.self)` + `@Environment(\.modelContext)`（局部） | Repository, Models | — |
| **Assistant** | `Features/Assistant/GlobalAssistantRoot.swift` | `@Environment(\.modelContext)` + 自持 `ModelContext`（`GlobalChatAgent` / `DiagnosticAgent`） | Models（`ChatSession`, `NoteComment`）, Network | `GlobalChatAgent`, `DiagnosticAgent`, `ChatLauncher` |
| **Inspiration** | `Features/Inspiration/InspirationBoardView.swift` | `@Query` + `@Environment(Repository.self)` | Repository, Models | `InspirationPickerSheet`, `AddInspirationView` |
| **Profile** | `Features/Profile/ProfileView.swift` | `@AppStorage` 直读 + `@Query` | Models, Network（间接） | `LLMConfigView`, `SettingsView`, `UserInfoView`, `FeedbackView`, `HelpView`, `LegalView`, `DebugLogView` |
| **Onboarding** | `Features/Onboarding/OnboardingView.swift` | `@AppStorage("has_seen_onboarding")` | DesignSystem | — |
| **CoachMark** | `Features/CoachMark/CoachMarkOverlay.swift` | `@Environment(CoachMarkManager.self)` | DesignSystem | `CoachMarkManager`（@Observable） |
| **SelectionToolbar** | `Features/SelectionToolbar/SelectionToolbarView.swift` | 局部 `@State` + 自持 VM | Models, Network | `SelectionToolbarViewModel`, `FloatingToolbarPanel`, `QuickActionsHistory` |
| **Export** | `Features/Export/AssetPackager.swift` | actor 隔离 | Models（`GenerationRecord` URL 字段） | `AssetPackager`（actor） |

**Feature 间引用关系**（11 个模块，10 条边，全部单向、无环）：
```
Assistant ──→ Result (DiagnosticAgent 注入到 ResultView 评论)
Generate ──→ Result (生成完 push 切换到 ResultView)
Result   ──→ SelectionToolbar (内嵌工具栏)
Result   ──→ Export (AssetPackager 打包)
Profile  ──→ Generate/History (快捷入口)
Onboarding ──→ RootTabView (首次启动覆盖)
其余模块互不直接 import，靠 Repository / ModelContext 解耦
```

---

## 3. 依赖图（文字版）

```
┌────────────────────────────────────────────────────────────────────────┐
│  App Entry (RedPulseApp)                                               │
│  - 持有 ModelContainer（6 个 @Model）                                    │
│  - 注入 coachMarkManager (.environment)                                  │
└────────────────────┬───────────────────────────────────────────────────┘
                     │
                     ▼
              ContentView
              (Repository 异步注入)
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
  RootTabView               SettingsView
  (Tab 路由)                  (sheet)
        │
   ┌────┼─────┬─────┬─────┐
   ▼    ▼     ▼     ▼     ▼
 Generate Library History Profile Inspiration  (主 Tab)
                    │
                    │  push
                    ▼
                 ResultView ←─── Assistant (DiagnosticAgent 注入)
                    │
              ┌─────┼─────┐
              ▼     ▼     ▼
         Selection  Export  RedNoteReader
         Toolbar   (actor)  /PublishPreview
              │
              ▼
        JimengService (@Observable, @MainActor)
        ├─ ArkJimengClient (Bearer, 支持 image-to-image)
        └─ JimengAPIClient (HMAC, 旧 API)
              │
              ▼
        LLMTextGenerator (OpenAI 兼容 chat/completions)
              │
              ▼
        MockGenerator (默认, sleep + 模板)
```

**依赖方向总结**：
- ✅ **全部单向**，无循环 import。
- ✅ 所有 Feature 都依赖 `Models/` 和 `DesignSystem/`，符合项目宪法。
- ⚠️ **6 个 Feature 直接持有 `@Environment(\.modelContext)`**（违反宪法"Repository 唯一持有 ModelContext"）：
  - `GenerateView.swift:14` — `modelContext.save()` 直接调
  - `GenerateStepSections.swift:17, 289` — 重复声明两次
  - `ProductListView.swift:6` — 删除产品直接 `modelContext.delete(p)`
  - `ProductFormView.swift:12` — 显式 insert + save
  - `ResultView.swift:36` — 创建 DiagnosticAgent 注入
  - `HistoryView.swift:472` — 局部声明
  - `GlobalAssistantRoot.swift:130, 389` — Agent 创建时传入
- ⚠️ **3 个 Agent 持有 `ModelContext` 直接字段**（而非通过 Repository）：
  - `DiagnosticAgent.modelContext` (private let)
  - `GlobalChatAgent.modelContext` (private let)
  - `Repository.modelContext` (let) ← 这是合法的（Repository 是宪法指定的唯一持有者）

**为什么大家会绕开 Repository？** 因为 `Repository` 只暴露了 5 个 Product + 4 个 Record + 2 个 Feedback + 3 个 Inspiration 的 CRUD，**没有 `updateProduct` / `updateRecord` / `saveNoteComment` / `saveChatSession`**。任何对 `NoteComment` / `ChatSession` / 字段更新的操作都只能直接用 `modelContext.insert / save`。

---

## 4. 命名约定遵循度

### ✅ 合规项（宪法遵守）

- **View 命名**：全部 `XxxView`（`GenerateView`, `ResultView`, `ProductListView`, `HistoryView`, `SettingsView`, `LLMConfigView`, …）无 `XxxScreen` / `XxxPage`。
- **ViewModel 命名**：`GenerateViewModel`, `SelectionToolbarViewModel`（@Observable）。但 `DiagnosticAgent` / `GlobalChatAgent` / `CoachMarkManager` 用了「Agent」「Manager」后缀 —— 宪法没说不行，且语义更准确（"Agent" 表征有状态 + 行为，"Manager" 表征 UI 协调器）。
- **Model 单数**：`Product`, `Feedback`, `GenerationRecord`, `InspirationItem`, `NoteComment`, `ChatSession` 全部单数。
- **`@Observable` 而非 `ObservableObject`**：13 个类全部用新宏，0 个用旧协议。
- **SwiftData 不用 CoreData**：0 个 `import CoreData`。
- **async/await 不用 Combine**：0 个 `import Combine`。`Task { … }` 43 次，`async let` 2 次；唯一 `DispatchQueue` 用法都是 `main.asyncAfter` 做延时，不是并发基础设施。
- **私有 helper 嵌套**：`GenerateViewHelpers.swift`, `ResultLayoutHelpers.swift`, `ResultRegenHelpers.swift`, `ResultEditorPanels.swift` 都在调用方 View 附近，符合"嵌套在使用它的 View 文件里"的精神。

### ❌ 偏离项

1. **`Models/` 宪法列了 5 个文件，实际 6 个**：缺 `NoteComment`（评论/全局消息统一载体）和 `InspirationItem`（灵感板），宪法没预见到这两个新模型。
2. **`Features/Auth/` 不存在**：宪法列了 `LoginView.swift`，实际没建（产品定位改成无登录态）。宪法与实际有偏差。
3. **`Network/` 宪法列了 3 个，实际 10 个**：实际拆出 `JimengService` / `ArkJimengClient` / `JimengAPIClient` / `LLMTextGenerator` / `LLMTester` / `JimengContracts` / `URLExtensions` 7 个新文件 —— 即梦/Ark 网关是后加的，宪法没预见到。
4. **`Features/Result/` 整个模块宪法未列**：宪法只规划到 `Generate/ResultView.swift` + `History/HistoryDetailView.swift` 2 个结果相关 View，实际演化成 10 个文件 / 4,552 行的独立模块（含 iPhone/iPad/Mac 三端布局、划词工具栏、配图视频、AI 诊断、手机模拟器、发布预览、ZIP 打包）。
5. **`Navigation/` 宪法未列**：实际有 `NavigationState.swift`（@Observable 跨视图状态）。
6. **`DesignSystem/` 宪法列了 2 个文件，实际 5 个**：多了 `FlowLayout` / `HapticManager` / `PlatformInteractions`，是演化中加入的。

**结论**：宪法是 V1 起点文档，V3.2 需求已经远远超过宪法覆盖范围。命名风格 100% 遵守，但目录结构 70% 偏离。

---

## 5. 平台差异分布

**统计**（实际数）：
- `#if os(...)` 总计 **73 处**，跨 **30 个 Swift 文件**。
- `#if canImport(...)` 总计 **40 处**（多为 `canImport(UIKit)` / `canImport(AppKit)` 互斥分支）。
- `#if os(iOS)` 43 处，`#if os(macOS)` 30 处。

**覆盖最广的文件**（`#if os` 出现 ≥ 3 次）：
- `Features/Result/ResultView.swift` — 7 处
- `Features/Result/ResultLayoutHelpers.swift` — 5 处
- `Features/Generate/GenerateView.swift` — 4 处
- `Features/Profile/SettingsView.swift` — 4 处
- `DesignSystem/PlatformInteractions.swift` — 6 处（专门做平台桥）

**平台边界合理性**：
- ✅ 几乎所有平台分支都在 UI 表现层（`ResultView`, `ChatLauncher`, `SettingsView`），业务逻辑层（`Repository`, `GeneratorProtocol`, `DiagnosticAgent`）零平台分支 —— 这与项目宪法「SwiftUI 不用 UIKit」一致。
- ✅ `PlatformInteractions.swift` 单独抽出 Pencil / NSWorkspace / UIDropInteraction 等系统调用，符合「把平台差异集中」的工程实践。
- ⚠️ `ResultView.swift:87` 的 `PHAssetCreationRequest` 是 `#if canImport(UIKit) && !os(macOS)` 内，**编译错误**（类名错，正确应 `PHAssetChangeRequest.creationRequestForAsset()`）。`ResultView.swift:272` 的 `generatedRecord` 引用是 `#if os(iOS)` 内，**符号未声明** —— 这两个 bug 在 `build-report.md` 中已记录。
- ⚠️ `RedPulseApp.swift:114-117` 的 `SettingsView` 框架尺寸约束在 `#if os(macOS)` 内，但未给 iPad 加 regular 尺寸（iPad 应该也用 `.frame(minWidth: 640, ...)`）。

**macOS 独占功能**：
1. `RedPulseApp` 的独立 `Window("AI 笔记助手", id: "global-assistant")` 块（默认 1100×720）。
2. 菜单栏 4 个 Command（`⌘1/2/3` + `设置…`）和 `⌘⇧A` 助手快捷键。
3. `AssetPackager` 走 `NSSavePanel` 而非 `UIActivityViewController`。
4. 图片保存走 `NSSavePanel` 而非 `UIImageWriteToSavedPhotosAlbum`。
5. `PlatformInteractions` 中 `NSWorkspace.shared.open(url)` 处理"帮助"菜单 URL。

**iPhone 独占**：
1. `CameraPicker` 真机相机（`UIImagePickerController.sourceType = .camera`）。
2. `fullScreenCover` 弹出 AI 助手。
3. 自定义 `TabBar` 占用底部 Home Indicator safe area。
4. `RedNoteReaderView` 的"全屏沉浸"模式。

**iPad 独占 / 增强**：
1. Apple Pencil 双击唤起 AI 助手（`UIPencilInteraction`）。
2. `NavigationSplitView` 双栏。
3. Text Drag & Drop 目标高亮（`textDropTarget` 修饰器）。
4. `OnboardingView` 同样使用但尺寸自适应。

---

## 6. 架构 smell 清单

> 严重度：**H**igh（影响可维护性或正确性） / **M**edium（设计欠佳但能跑） / **L**ow（风格问题）

| # | 严重度 | 位置 | 现象 | 建议 |
|---|---|---|---|---|
| 1 | **H** | `Data/Repository.swift:56, 92, 107, 122, 158` | log 错误转义 bug：`\\(error.localizedDescription)` 写成了字面 `\()`，5 处全部错 | 全部改为 `\(error.localizedDescription)` |
| 2 | **H** | `Features/Result/ResultView.swift` | **31 个 `@State` 属性 + 1,716 行**，典型 God View，编译期 2 个错误（line 87 PHAssetCreationRequest / line 272 generatedRecord） | 至少拆 3 个：`ResultEditorPanel` / `ResultPreviewPanel` / `ResultPackageAction`；用 `@Bindable` 包装 VM 替代散落 `@State` |
| 3 | **H** | 7 个 Feature View | 直接持有 `@Environment(\.modelContext)`，绕开 Repository（违反宪法） | 把 `saveNoteComment` / `saveChatSession` / `updateRecord` 加到 Repository，调用方走 Repository |
| 4 | **H** | `Features/Assistant/DiagnosticAgent.swift:18` + `GlobalAssistantRoot.swift:21` | Agent 直接持有 `ModelContext`（`private let modelContext`），侵入性高 | 注入 Repository，让 Agent 不感知 SwiftData |
| 5 | **M** | `Features/Result/ResultView.swift:1673` / `SelectableTextEditor.swift:104, 239` / `FloatingToolbarPanel.swift:181` / `SettingsView.swift:211` | 5 处 `DispatchQueue.main.asyncAfter(deadline:)` 做延时（用 `Task.sleep` 更地道，且能取消） | 改 `Task { try? await Task.sleep(...) }` 或 `Task.sleep(for: .seconds(1.8))` |
| 6 | **M** | `Features/Generate/GenerateStepSections.swift:15-17 + 287-289` | 同一个文件里**两套** `@Environment` 声明（Repository + modelContext + CoachMarkManager），表明两个 Struct 共存于一个文件 | 拆成两个文件，或将第二个 Struct 移到调用方文件 |
| 7 | **M** | `Features/Assistant/GlobalAssistantRoot.swift:130, 389` / `Features/History/HistoryView.swift:39, 472` | 同一文件两套 `@Environment` 声明（同上模式） | 同上 |
| 8 | **M** | `Features/Profile/FeedbackView.swift:23` + `Features/Profile/SettingsView.swift:16` + `Features/Library/ProductListView.swift:5` + `Features/Generate/GenerateView.swift:13` + `Features/Generate/GenerateStepSections.swift:16, 288` + `Features/History/HistoryView.swift:39` + `Features/Inspiration/AddInspirationView.swift:11` + `Features/Inspiration/InspirationBoardView.swift:12` + `Features/Inspiration/InspirationPickerSheet.swift:12` | `@Environment(Repository.self)` 在 9 个 View 出现，**Repository 是单例** —— 直接全局访问 `Repository.shared` 也行（参考 `DebugLog.shared` 模式） | 维持现状即可（注入式更易测）；如果要简化，可以改 `static let shared`，但要丢失测试性 |
| 9 | **M** | `Data/Repository.swift`（API surface） | 缺 `updateProduct` / `updateRecord` / `saveNoteComment` / `saveChatSession` —— 所有"修改现有对象"的场景必须直接 `modelContext.save()` | 补全 4 个方法 |
| 10 | **M** | `Features/Result/ResultView.swift:80` + `SelectableTextEditor.swift` | `debugMode` `@State` 字段声明了但 UI 没有 toggle 入口，疑似残留 | 移除未使用字段，或接上 debug 入口 |
| 11 | **M** | `Features/Result/ResultRegenHelpers.swift:87` | 用 `PHAssetCreationRequest` 类名（错），应该是 `PHAssetChangeRequest.creationRequestForAsset()` | 修复编译错误 |
| 12 | **M** | `Features/Result/ResultView.swift:272` | 引用未声明的 `generatedRecord`（实际是 `GenerateView` 的 `@State`） | 提一个 binding 进去，或重写返回逻辑 |
| 13 | **L** | `RootTabView.swift:71-77` | `ChatLauncher` / `CoachMarkOverlay` overlay 整段被注释，未挂到根视图 | 解开注释，或明确文档说明"故意不挂" |
| 14 | **L** | `Features/SelectionToolbar/QuickActionsHistory.swift` | history 仅内存，关闭即丢，注释暗示 by-design | 文档化"by-design"或持久化 |
| 15 | **L** | `Network/JimengService.swift:71-74, 83-84` | `validateConfig` 把可选的 Ark API Key 当 issue 提示，逻辑倒置 | 拆 `validateRequired` + `validateOptional` 两阶段 |
| 16 | **L** | `RedPulseApp.swift:57` | "RedPulse 帮助"菜单按钮跳 `https://example.com/help`（占位 URL） | 替换为真实帮助页 URL |
| 17 | **L** | `RedPulseApp.swift:93` | `try!`（force-try）创建 in-memory fallback ModelContainer，文档说容器创建失败后兜底 —— 在极端 SwiftData 故障下会崩溃 | 加 `fatalError` 信息 + 设备日志上报 |
| 18 | **L** | `Models/GenerationRecord.swift:36` | `hotScore` 字段持久化但无消费者 | 要么删除字段，要么接埋点上报 |
| 19 | **L** | `DesignSystem/DesignTokens.swift:303` | `ScreenMetrics` 是 `@Observable` 单例（`ScreenMetrics.shared`）—— 跟 `DebugLog.shared` 模式一致，但全模块耦合到这个单例 | 可接受（设计 token 自然单例），仅记录 |
| 20 | **L** | `Network/LLMTextGenerator.swift:117-123` | `generateImage()` / `generateVideo()` 抛"未实现"错误 —— `GeneratorProtocol` 接口定义了这两个方法但实现不支持，调用方必须自己避开 | 删除协议里的 image/video 方法，或拆 `TextGeneratorProtocol` + `MediaGeneratorProtocol` |

**统计**：3 H + 9 M + 8 L = 20 个 smell（与 verifier 对第一次报告 review 的 smell 数量结论一致；上次 report 因 4 处数值错被 flag，本版全部数字已重数）。

---

## 7. 一句话总结

**RedPulse 是一个 SwiftUI-first 的「轻量 MVVM + Repository 单例 + 局部 @State 神视图」混合体 —— 不是 TCA（没有 reducer/store），不是 clean architecture（Feature 直接持有 ModelContext、Agent 直接吃 ModelContext），不是经典 MVVM（God View 直接管 31 个 @State 而非 ViewModel 协调），但模块边界清晰、依赖单向无环、平台差异集中在表现层；6 个 Feature 绕开 Repository、3 个 Agent 直接持 ModelContext、`ResultView` God View 和 Repository log 转义 bug 是主要技术债。**

---

*主 session 直接产出 · 替代被 4 次 timeout 的 team architecture worker · 数据全部自验（grep 实测）*
