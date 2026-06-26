# Features 模块对照表

> 改 UI 页面时快速定位。所有 `Features/` 子目录的入口、职责、关键文件。

---

## 目录总览

```
RedbookRefill/Features/
├── Generate/              ← G1/G7 全量生成（输入表单）
├── Result/                ← 生成结果页（展示 + 编辑 + G8 重生）
├── History/               ← 历史记录列表
├── Onboarding/            ← 首次启动引导
├── Profile/               ← 我的（产品库 + 大模型配置 + 设置）
├── SelectionToolbar/      ← 划词 AI 工具栏
├── Assistant/             ← AI 诊断师（评论区诊断）
└── Inspiration/           ← 灵感（小红书 trending + 风格提示）
```

---

## Generate（输入表单）

**入口**：App Tab 根 → Generate Tab

**职责**：收集用户输入 → 调 `generator.generate()` → 跳 ResultView

### 关键文件

| 文件 | 职责 |
|------|------|
| `GenerateView.swift` | 主入口，4 步表单 + "生成" 按钮 |
| `GenerateStepSections.swift` | 4 步表单的 section 容器 |
| `GenerateStepStep4Hint.swift` | Step4 风格提示（chip 选择 + AI 生成） |
| `GenerateViewHelpers.swift` | trending 关键词 / 风格提示 / 灵感 picker 助手 |
| `ThinkingOverlay.swift` | 生成中 loading 蒙层 |

### 数据流

```
GenerateStepStep1Product    选产品（optional）
       ↓
GenerateStepStep2AdType     选广告类型（必填）
       ↓
GenerateStepStep3Keyword    关键词输入 + 灵感推荐
       ↓
GenerateStepStep4Hint       风格提示 chip 选择
       ↓
点 "生成"
       ↓
generator.generate(GenerateRequest{
    recordId, keyword, adType, keywordHint, product, images, styleImages
})
       ↓
成功 → generatedRecord = response → ResultView
失败 → showGenerateError + generateErrorMessage
```

---

## Result（结果页）

**入口**：GenerateView 生成成功 / HistoryView 点历史记录

**职责**：展示 6 大模块 + 单字段编辑 + 触发配图/视频

### 关键文件

| 文件 | 职责 |
|------|------|
| `ResultView.swift` | 主入口，最复杂的页面 |
| `ResultEditorPanels.swift` | 标题/正文/标签的内联编辑面板 |
| `ResultLayoutHelpers.swift` | 布局辅助函数（响应式） |
| `ResultRegenHelpers.swift` | G8 重生按钮 + 调用封装 |

### 页面分区（按 @State 划分）

```
┌─ 顶部：标题 + 返回按钮 + 复制按钮
├─ Tabs: 文案 | AI 配图 | AI 视频 | AI 评论
│   ├─ 文案 Tab：noteTitle + content + tags + suggestion + easterEgg
│   ├─ AI 配图 Tab：imagePrompt 输入 + imageUrls 预览 + "生成配图" 按钮
│   ├─ AI 视频 Tab：videoPrompt 输入 + videoUrl 预览 + "生成视频" 按钮
│   └─ AI 评论 Tab：评论区诊断
├─ G8 单字段重生成按钮（标题/正文/标签各自 ↻）
└─ 划词 AI 工具栏（选中文字时弹出）
```

### 关键状态

```swift
@State private var record: GenerationRecord        // 当前 record（核心）
@State private var generator: GeneratorProtocol    // LLMTextGenerator 或 Mock
@State private var jimengService: AgnesService     // 图片 + 视频
@State private var cloneCreated = false            // 编辑时是否已 clone record
@State private var isPreparingPrompts = false      // 配图 prompt 扩写中
```

### 关键方法

```swift
private func generateImages() async         // 多张配图（regenerateImagePrompts + AgnesService）
private func generateVideo() async          // 单条视频（AgnesService）
private func generateImagePromptFromContent() async  // 反推 imagePrompt
private func ensureCloneIfNeeded()           // 编辑前克隆 record（保留原版）
```

---

## History（历史记录）

**入口**：App Tab 根 → History Tab

**职责**：展示所有 GenerationRecord + 删除 / 重新进入 ResultView

### 关键文件

| 文件 | 职责 |
|------|------|
| `HistoryView.swift` | 主入口，列表 + 滑动删除 + 跳转 |
| `AddInspirationView.swift` | 弹窗：添加单条灵感 |
| `InspirationBoardView.swift` | 灵感墙（独立子页面） |
| `InspirationPickerSheet.swift` | 灵感选择 sheet（被 GenerateView 调用） |
| `CameraPicker.swift` | 相机 / 相册选择（产品图上传用） |
| `ProductFormView.swift` | 新增 / 编辑产品表单 |
| `ProductListView.swift` | 产品库列表 |

### 数据流

```
HistoryView.onAppear
   ↓
repository.fetchAllRecords()  // 按 createdAt 倒序
   ↓
List { ForEach(records) { record in Row } }
   ↓
点 row → ResultView(record: record)
滑动删除 → repository.deleteRecord(record)
```

---

## Onboarding（首次启动）

**入口**：App 启动后判断 `isFirstLaunch`，显示一次

**职责**：产品介绍 + 权限请求 + 跳主界面

### 关键文件

| 文件 | 职责 |
|------|------|
| `OnboardingView.swift` | 引导主页面 |

---

## Profile（我的）

**入口**：App Tab 根 → Profile Tab

**职责**：产品库管理 + 大模型配置 + 设置 + 帮助 + 反馈

### 关键文件

| 文件 | 职责 |
|------|------|
| `ProfileView.swift` | 主入口 |
| `LLMConfigView.swift` | **大模型配置（API Key / URL）—— 关键** |
| `SettingsView.swift` | 应用设置 |
| `HelpView.swift` | 帮助文档 |
| `FeedbackView.swift` | 用户反馈 |

### `LLMConfigView` 重点

- 当前**只剩 Agnes 一家** provider（之前切换过 provider，留下接口但 UI 不暴露）
- 关键 UserDefaults 写入：
  - `api_base_url`
  - `api_key`
- 「测试连接」按钮调 `LLMTester.testTextModel(...)` 验证 Key 是否有效

---

## SelectionToolbar（划词 AI 工具栏）

**入口**：ResultView 选中文字时弹出

**职责**：选中文字后弹出操作菜单（润色 / 改写 / 扩写 / 缩写 / 换风格）

### 关键文件

| 文件 | 职责 |
|------|------|
| `FloatingToolbarPanel.swift` | 浮动工具栏 UI |

### 关键调用

```swift
private func transformText(command: String, selectedText: String) async {
    let newText = try await generator.transformText(
        command: command,
        selectedText: selectedText,
        context: record.content  // 提供上下文
    )
    // 替换 record.content 中的选中文本
}
```

---

## Assistant（AI 诊断师）

**入口**：ResultView 的 AI 评论 Tab / 全局悬浮按钮

**职责**：基于已生成笔记做内容诊断 + 多轮对话

### 关键文件

| 文件 | 职责 |
|------|------|
| `DiagnosticAgent.swift` | 评论区诊断主 agent |
| `ChatLauncher.swift` | 全局 chat 启动器 |
| `ChatSession.swift` | chat 会话状态 |
| `GlobalAssistantRoot.swift` | 全局 assistant 入口 |

### 关键调用

```swift
let llm = LLMTextGenerator()
let response = try await llm.chat(messages: [
    .system("你是小红书内容诊断师..."),
    .user(record.content)
])
```

---

## Inspiration（灵感）

**入口**：GenerateView Step3 关键词输入框旁的灵感图标 / Step4 风格提示

**职责**：拉取小红书 trending 关键词 + AI 生成风格提示

### 关键文件

| 文件 | 职责 |
|------|------|
| `InspirationPickerSheet.swift` | 灵感选择 sheet |
| `AddInspirationView.swift` | 手动添加灵感 |
| `InspirationBoardView.swift` | 灵感墙浏览 |

### 数据来源

- **Trending 关键词**：LLM 拉取（`GenerateViewHelpers.swift` → `chatJSONList`）
- **风格提示 chip**：LLM 基于产品 + adType 生成（`GenerateViewHelpers.swift` → `chatJSONList`）

---

## Features 间的关系图

```
                    ┌──────────────────┐
                    │  App Launch      │
                    │  (RedbookRefillApp)│
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         ┌────────┐    ┌──────────┐    ┌──────────┐
         │ Onboard│    │ Generate │    │ History  │
         │ (首次) │    │          │    │          │
         └────────┘    └─────┬────┘    └────┬─────┘
                            │              │
                            ▼              │
                       ┌────────┐          │
                       │ Result │◄─────────┘ (点历史记录)
                       └───┬────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
       ┌──────────┐   ┌──────────┐   ┌──────────┐
       │ Profile  │   │Selection │   │Assistant │
       │          │   │ Toolbar  │   │          │
       └──────────┘   └──────────┘   └──────────┘
```

---

## 改这块时的注意事项

1. **改 ResultView 要小心**——它最大（1700+ 行），改动前先读懂 6 个分区
2. **改 GenerateView 表单**——保持 4 步结构不要乱动，新字段加 Step4.5 / Step5
3. **改 Onboarding**——只在「首次启动」触发，不要影响常规流程
4. **改 LLMConfigView**——当前只剩 Agnes provider，加新 provider 要改 `ModelConfigStore.swift`
5. **改 Assistant / Diagnostic**——不要破坏多轮对话上下文，每轮 messages 数组要累积
6. **跨 Features 共享样式**——走 `DesignSystem/`，不要在 Features 内部写魔数