# RedPulse — 业务功能与用户流程梳理

> 范围：`/Users/mac/Desktop/RedbookRefill/RedbookRefill/`（iOS 17+ / iPadOS / macOS SwiftUI 工程，~14.5k 行 Swift）。
> 阅读对象：产品、运营、后续并行 agent。
> 输入来源：源码反推 + `_PROJECT_CONVENTIONS.md` + 需求文档 `/Users/mac/Desktop/红书笔芯/prototype/需求_融合版.md`（V3.2）。

---

## 1. 一句话定位

**RedPulse 是一款面向小红书创作者/品牌运营的本地优先 AI 笔记工作台 —— 在 iPhone / iPad / Mac 三端，用 LLM（OpenAI 兼容协议）+ 即梦（图片/视频）把"产品库 → 生成文案 → 配图视频 → 模拟发布预览 → AI 内容诊断 → 一键打包导出"串成闭环，所有数据走 SwiftData 落本地，不依赖云端账号体系。**

---

## 2. Feature 矩阵

| 模块 (Feature) | 入口 View | 用户可见功能 | 核心 ViewModel / Agent / Service | 持久化（@Model） |
|---|---|---|---|---|
| **Generate（生成）** | `Features/Generate/GenerateView.swift` | ① 四步表单：选产品 → 选广告类型 → 写关键词 + 风格提示 → 点"立即生成"；② 一键生成标题 / 正文 / 标签 / 配图建议 / 配图 prompt / 视频 prompt / 彩蛋金句 / 优化建议；③ 高质量 vs 快速模型切换；④ 灵感板选择关键词 / 风格片段；⑤ trending 关键词 LLM 推荐 | `GenerateViewModel`（内嵌于 GenerateView，用 `@State` + `@AppStorage` 状态机）<br/>`GeneratorProtocol`（策略：`LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()`）<br/>`ThinkingOverlay`（生成中 4 步进度动效） | `GenerationRecord`（生成产物）<br/>`Product`（如选了产品库）<br/>`InspirationItem`（可选，灵感板） |
| **Library / Product（产品库）** | `Features/Library/ProductListView.swift`<br/>`Features/Library/ProductFormView.swift` | ① 产品列表（搜索 + 删除 + 卡片预览）；② 新增 / 编辑产品（名称 / 卖点 / 人群 / 场景 / 图片风格 / ≤5 张参考图）；③ iPhone 相机 / 照片库 / Mac 文件导入三种图片来源 | 无独立 VM（直接走 `@Query` + Repository）<br/>`CameraPicker`（仅 iPhone 真机） | `Product`（含 `imagePaths` / `styleImagePaths` 相对路径） |
| **Result（结果编辑 / 预览 / 打包）** | `Features/Result/ResultView.swift` | ① 三栏（Mac/iPad regular）/ 双栏 / 单栏 + 模式切换器（iPhone compact）自适应布局；② 文案编辑 + 单字段重生成 + 划词 AI 工具栏；③ 即梦 AI 配图（1-4 张并行，可指定产品参考图）；④ 即梦 AI 视频（用配图作首帧 / 多帧参考）；⑤ 手机预览（`RedNoteReaderView` / `PublishPreviewView`）；⑥ 一键打包 ZIP（`AssetPackager`，写笔记.txt + 提示词.txt + 图片 + 视频） | `JimengService`（@Observable，封装 Ark / AK/SK 两路）<br/>`SelectionToolbarViewModel`（划词润色/改写/扩写/缩写/换风格/自定义）<br/>`AssetPackager`（actor，三端通用 zip） | `GenerationRecord`（写回 `isEdited` / `imageUrls` / `videoUrl`） |
| **History（历史记录）** | `Features/History/HistoryView.swift` | ① 按"今天 / 昨天 / yyyy.MM.dd（周X）"分组，可折叠日期；② 广告类型筛选胶囊；③ 全文搜索（标题 / 正文 / 标签 / 关键词）；④ 点卡片跳详情（`ResultDetailView`）；⑤ 一键清空；⑥ 左滑 / 右键删除单条 | 无独立 VM（`@Query` 直接绑定） | `GenerationRecord` |
| **Assistant（AI 笔记助手 + 评论诊断师）** | `Features/Assistant/GlobalAssistantRoot.swift`（独立 Window / Sheet）<br/>`Features/Assistant/DiagnosticAgent.swift`（嵌入结果页评论区） | ① 全局助手：多会话侧栏、消息流、新对话 / 重命名 / 删除、流式打字光标（SSE）；② 评论诊断师：进入结果页时自动跑 4 维度评审（标题 / 正文 / 标签 / 配图），每条建议可"应用 / 忽略"；③ 多轮对话：用户在评论区发问 → 拼历史 → 流式回答；④ Pencil 双击（iPad） / ⌘⇧A（Mac） / 全屏 FAB 快捷唤起 | `GlobalChatAgent`（@Observable，流式 `chatStream`）<br/>`DiagnosticAgent`（@Observable，初始诊断 + 多轮 + applySuggestion / ignoreSuggestion） | `ChatSession`（多会话元数据）<br/>`NoteComment`（消息复用：recordId 字段既绑 record 也绑 session） |
| **Inspiration（灵感板）** | `Features/Inspiration/InspirationBoardView.swift` | ① 3 种类型：snippet / keyword / style；② 类型筛选 + 全文搜索；③ 在结果页"收藏到灵感板"快捷入口；④ 手动添加（`AddInspirationView`） | 无 VM | `InspirationItem` |
| **Profile（我的 / 设置 / 配置）** | `Features/Profile/ProfileView.swift` | ① 数据看板（产品数 / 历史数）；② 快捷操作（新建 / 灵感板 / 历史）；③ 设置入口：大模型配置（`LLMConfigView`，含连接测试）、帮助 / 反馈 / 隐私协议 / 服务条款 / 重新引导；④ Debug 日志查看（`DebugLogView`） | 无 VM（直接 `@AppStorage` 读写） | 间接：`UserDefaults`（llm_content_url 等所有 LLM / 即梦配置项） |
| **Onboarding（新手引导）** | `Features/Onboarding/OnboardingView.swift` | 4 页翻页引导（AI 写笔记 / 产品库 / 结果编辑 / 开始创作），可勾选"不再提醒"，用 `has_seen_onboarding` 持久化 | — | `@AppStorage("has_seen_onboarding")` |
| **CoachMark（操作引导）** | `Features/CoachMark/CoachMarkOverlay.swift` | 新用户首次进入"生成"页时逐步高亮 4 个表单区域；"我的 → 重新引导"可重看 | `CoachMarkManager`（@Observable，注入 environment） | `@AppStorage("has_seen_coach_marks_*")` |
| **SelectionToolbar（划词 AI 工具栏）** | `Features/SelectionToolbar/SelectionToolbarViewModel.swift`<br/>`Features/SelectionToolbar/FloatingToolbarPanel.swift` | 在 ResultView 编辑正文时浮窗，提供 5 种快捷动作 + 自定义指令 + 微调（更短/更长/更口语/更正式） | `SelectionToolbarViewModel`（UI 状态 + `history` 记录 + `IntentGuesser` 猜意图） | `QuickActionRecord`（内存中 history，未持久化） |
| **Export（导出）** | `Features/Export/AssetPackager.swift` | 写笔记.txt / 提示词.txt / 并发下载图片 / 视频 → 用 `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)` 生成 zip | `AssetPackager`（actor） | — |

---

## 3. 核心用户流程

### 流程 A · 生成笔记（"立即生成"主流程）

**触发点**：`GenerateView` 底部悬浮的 `GenerateActionButton`（品牌红渐变胶囊按钮）。

**步骤序列**：

1. `GenerateView.handleGenerate()` 构造 `GenerateRequest(recordId: UUID(), keyword, adType, keywordHint, product, images: [], styleImages: [])`。
2. 根据 `LLMTextGenerator.isConfigured` 选择 `LLMTextGenerator()` 或 `MockGenerator()`：
   - **Mock 模式**：`MockGenerator.generate()` 睡 1.5s → 按 `AdType` 选模板（`feedAd` / `searchAd` / `brandAd` / `salesNote`） → 随机抽标题 / 正文 / 标签 / 配图建议 / 配图 prompt / 彩蛋金句 → 返回 `GenerateResponse`。
   - **LLM 模式**：`LLMTextGenerator.generate()` 并行发两个 chat completion：
     - **标题小模型**（`generateTitleIfConfigured`，若 `llm_title_url/key/model` 配齐则走，否则 fallback）；
     - **内容大模型**（`chatJSON` → 强 JSON schema：noteTitle/content/tags/imageSuggestion/imagePrompt/videoPrompt/suggestion/easterEgg）。
   - 二者结果合并到 `GenerateResponse`，如有标题小模型返回，则用它的 title 覆盖。
3. `Task` 中 try `Task.checkCancellation()` → 拿到 `response` → 构造 `GenerationRecord`（`isEdited: false`，`hotScore` 等于 mock 随机值或 LLM 的 0）。
4. `capturedModelContext.insert(record)` + `modelContext.save()` 落库（`@MainActor`）。
5. `generatedRecord = record` 触发 `body` 切换：`ResultView(record: record)` 出现，顶栏"返回"按钮可回到四步表单。
6. ResultView `onAppear` 创建 `DiagnosticAgent(modelContext:)`，但**不会自动诊断**（由顶部"AI 内容诊断师"按钮触发，或在 `RedNoteReaderView` 中以 `triggerDiagnose` 触发）。
7. 用户在右栏 `imageGenSection` 选 1-4 张 → 点"生成 N 张配图" → `JimengService.generateImages(prompts:referenceImagesData:)`：每个 prompt 并行调 `ArkJimengClient` 或 `JimengAPIClient`，Ark 路径支持 `image-to-image`（产品参考图 base64 注入），AK/SK 路径暂未实现（图生图）。
8. 图片 URL 累积到 `jimengService.generatedImageURLs` → 写入 `record.imageUrls` 持久化。
9. 视频路径：`videoPrompt` + `referenceImageURLs`（当前所有图）→ `JimengService.generateVideo()` → 写 `record.videoUrl`。

**终态**：
- 一条 `GenerationRecord` 落库（标题/正文/标签/优化建议/图片/视频全部就位或部分为空）。
- `GenerationRecord.hotScore` 字段已落库但 UI 不展示（仅后端质量监控用）。
- 用户可立即点 "打包"（`AssetPackager`） → 下载 zip 分享，或"全选复制"粘贴到小红书 App。

**取消路径**：用户点 `ThinkingOverlay` 上的"取消"→ `cancelGeneration()` → `generateTask?.cancel()` → URLSession 抛 `URLError.cancelled` → `resetGenerationState()`，不写库。

**网络降级**：`dataWithAutoRetry` 包装层对瞬时网络错（-1001/-1005/-1009 等）自动重试 1 次（400ms 后），并通过 `friendlyNetworkError` 把 URLError 翻译成中文提示（"网络连接已断开 / 无法连接到大模型服务 / 请求超时"等）。

---

### 流程 B · 历史记录回看与编辑

**触发点**：
- 底部 Tab 的"历史" / Mac 侧栏的"历史" / 顶部 ⌘3 快捷键 / `ProfileView` 上的"查看历史"统计卡。
- 卡片被点击 → `NavigationLink` push 到 `ResultDetailView(record:record, fromHistory: true)`。

**步骤序列**：

1. `HistoryView` 用 `@Query(sort: \GenerationRecord.createdAt, order: .reverse)` 拿所有 `GenerationRecord`。
2. `filteredRecords` 同时套两层过滤：`adTypeFilter`（广告类型胶囊，单选可再次点取消）+ `searchText`（标题/正文/关键词/风格提示/标签模糊匹配，不区分大小写）。
3. `sections` 按 `cal.startOfDay(for:)` 分桶 → 转 `[HistoryDaySection]` 按日倒序。
4. 渲染：`LazyVGrid` 自适应列（min 300pt），每张卡片显示 `adType` 色块 + `isEdited` 标 + 时间 HH:mm + 标题（lineLimit 1）+ 正文预览（lineLimit 2）+ 前 3 个标签。
5. `sectionHeader` 可点击折叠/展开（旋转 90° chevron）。
6. 卡片左滑 / 右键 → 弹 `showDeleteAlert` → `repository.deleteRecord(record)` → SwiftData 自动更新 `@Query`。
7. 卡片点击 → push `ResultDetailView`：标题 / 正文 / 标签 / 配图建议只读，配图区可重新生成（也走 `JimengService`），视频区只读播放。
8. 顶部"清空所有历史记录"按钮 → `showClearAlert` → `repository.clearAllRecords()`。

**编辑路径**：从历史跳进的详情页是只读；想编辑需走"`GenerateView` → 重新生成"或在主生成后从 ResultView 编辑（同流程 A）。

**终态**：UI 实时随 SwiftData 变化刷新；删除/清空都不可撤销（清空有 alert 确认，单条删除有 alert）。

---

### 流程 C · AI 内容诊断师对话

**入口 A（嵌入式，在 ResultView / RedNoteReaderView / PublishPreviewView 评论区里）**：

1. ResultView 顶部点击 "AI 内容诊断师"按钮（`debugMode.toggle()` 实际是占位，待确认；当前触发是 `handleDiagnose()` → `await diagnosticAgent.diagnose(record:)`）。
2. `DiagnosticAgent.diagnose()`：
   - 先清掉旧 AI 评论（`roleRaw == "ai"` 的 `NoteComment`），保留用户评论。
   - 用 `chatJSON(system: systemPromptDiagnose, user: userPromptDiagnose)` 调 LLM，期望返回 `{ "comments": [{ "body", "kind", "newText", "originalSnippet" }] }`。
   - 每条落库为 `NoteComment(role: .ai, authorName: "AI 内容诊断师", suggestion: NoteCommentSuggestion(kind, originalSnippet, newText), suggestionStatus: .pending)`。
3. 评论区用 `@Query(filter: recordId)` 拉所有评论 → UI 渲染气泡，AI 评论底部带"应用建议 / 忽略"按钮（`PublishPreviewView.commentRow`）。
4. 用户点"应用建议" → `DiagnosticAgent.applySuggestion(from:to:)` 按 `kind` 改 `record.noteTitle` / `record.content`（支持 `originalSnippet` 行内替换） / `record.tags`（split 解析逗号空格）/ 追加 tag。
5. 用户点"忽略" → `comment.updateSuggestionStatus(.ignored)`，UI 显示"· 已忽略"。

**入口 B（嵌入式多轮对话）**：

1. 用户在评论区输入文本 → `PublishPreviewView.commentInputBar` → `onSendComment(text)` 回调 → `diagnosticAgent.sendUserMessage(text, replyTo: nil, record: record)`。
2. `sendUserMessage`：
   - 立即 `insert` 一条 `NoteComment(role: .user, ...)` 并 save → UI 立刻显示气泡。
   - 拉 `fetchConversationHistory(recordId:)`（按 createdAt 排序全量 record 的 NoteComment）。
   - 再 `insert` 一条空 `NoteComment(role: .ai, body: "", isStreaming: true)` → UI 立刻看到"AI 正在思考…" + sparkles 光标动画。
   - `for try await chunk in generator.chatStream(messages: turns)`：每来一个 token 就 `aiComment.body = accumulated` + `save()`，UI 看到打字机效果。
   - 流式结束 / 出错后 `isStreaming = false` + save。

**入口 C（全局 AI 助手，独立 Window / Sheet）**：

1. 用户点击 `ChatLauncher`（右下角浮动 sparkles FAB，位置 `@AppStorage` 持久化，可拖拽、贴边、缩放；iPad 用 Pencil 双击 / Mac 用 ⌘⇧A 都能唤起）。
2. Mac：`openWindow(id: "global-assistant")` 打开 `RedPulseApp` 中声明的独立 `Window` 块（`defaultSize 1100×720`）。
3. iPad：`sheet` 弹出（`sizeClass == .regular`）。
4. iPhone：`fullScreenCover` 弹出。
5. `GlobalAssistantRoot`：
   - **mac / iPad regular**：`NavigationSplitView` 双栏（左侧 session 列表 + "新对话"按钮，右侧聊天）。
   - **iPhone / iPad compact**：单栈 + 顶部汉堡 → 弹出 session 列表 sheet。
6. 消息流复用 `NoteComment` 表：`recordId = session.id`。
7. `GlobalChatAgent.sendUserMessage`：
   - 首条用户消息自动把 `session.title` 改成消息前 20 字。
   - 落库 user NoteComment + 空 ai NoteComment（isStreaming）→ SSE 流式追加 → save。
8. 删除会话：`deleteSession` 同时删关联的所有 `NoteComment`。

**终态**：
- 评论诊断落库为 `NoteComment`，**用 recordId 与 GenerationRecord 绑定**；用户/AI 角色区分通过 `roleRaw`。
- 全局助手的对话同样落 `NoteComment`，但 recordId 字段值是 `ChatSession.id`，形成"消息复用一张表，两种语义共享 schema"的巧妙设计。
- `NoteComment.suggestionJSON`（`NoteCommentSuggestion` Codable 序列化）承载结构化建议（kind + originalSnippet + newText），`suggestionStatusRaw` 跟踪"待处理 / 已应用 / 已忽略"。

---

### 流程 D · 大模型配置（一次性）

**触发点**：`ProfileView → 设置 → 大模型配置`。

**步骤**：

1. `LLMConfigView` 三个卡片：文案生成 / 图片生成 / 视频生成。所有字段走 `@AppStorage` 直写 `UserDefaults`（key 前缀 `llm_content_*` / `llm_image_*` / `llm_video_*`）。
2. 文案生成：API URL + API Key + 快速模型 + 可选高质量模型；4 字段齐全时 `LLMTextGenerator.isConfigured == true`，GenerateView 自动切真模型。
3. 图片 / 视频生成：Ark Key（推荐，走 Bearer 认证）或 AK/SK + req_key（兼容旧火山 API）；`JimengService.isConfigValidForImage/Video` 判断。
4. 每卡片带"测试连接"按钮（`LLMConfigView` 的 `contentTestStatus` 等），发一次最小请求验证。
5. 底部"恢复默认"按钮清空所有配置。

**关键设计**：`@AppStorage` 让"配置"独立于 SwiftData，关闭 app 不丢（UserDefaults 持久）；`GeneratorProtocol` 让配置状态可以运行时变化（每次构造 generator 都重新检查 `isConfigured`）。

---

## 4. 数据流图

### 一条笔记从输入到持久化的完整数据流

```
┌─────────────────────────────────────────────────────────────────┐
│ 用户输入 (GenerateView)                                          │
│   • selectedProduct: Product?       (从 ProductListView 选)       │
│   • keyword: String                (关键词文本)                   │
│   • keywordHint: String?           (风格提示)                     │
│   • selectedAdType: AdType         (4 种枚举)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              GenerateView.handleGenerate()
                              │
                              ▼
              ┌──────────────────────────────┐
              │ 构造 GenerateRequest          │
              │  (recordId: UUID(), ...)      │
              └──────────────────────────────┘
                              │
                  LLMTextGenerator.isConfigured ?
                       │                │
                     true            false
                       │                │
                       ▼                ▼
        ┌────────────────────────┐  ┌──────────────────────┐
        │ LLMTextGenerator       │  │ MockGenerator         │
        │ ──────────────────     │  │ ─────────────────     │
        │ 并行：                  │  │ sleep 1.5s            │
        │  • title 小模型         │  │ TemplatePack.pick()   │
        │  • content 大模型 (JSON)│  │ 随机抽模板             │
        └────────┬───────────────┘  └─────────┬──────────────┘
                 │                            │
                 └─────────────┬──────────────┘
                               ▼
                    GenerateResponse
                  (noteTitle/content/tags/
                   imageSuggestion/imagePrompt/
                   videoPrompt/suggestion/easterEgg/
                   hotScore)
                               │
                               ▼
              GenerationRecord (init)
                  adType, inputKeyword, keywordHint,
                  productId, noteTitle, content, tags,
                  imageSuggestion, imagePrompt, videoPrompt,
                  easterEggText, hotScore, suggestion,
                  isEdited=false, createdAt=now
                               │
                               ▼
        ModelContext.insert(record) + save()
                               │
                               ▼
              ┌──────────────────────────────┐
              │ SwiftData · RedPulse.sqlite   │
              │ 持久化 GenerationRecord       │
              └──────────────────────────────┘
                               │
                               ▼
              generatedRecord = record (UI 触发)
                               │
                               ▼
                  ResultView(record: record)
                  (三栏 / 双栏 / 单栏 自适应)
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
   配图 (imagePrompt)    视频 (videoPrompt)      评论区诊断
   ─────────            ─────────              ─────────────
   JimengService        JimengService          DiagnosticAgent
   .generateImages()    .generateVideo()       .diagnose()
        │                      │                     │
        ▼                      ▼                     ▼
   ┌────────┐            ┌────────┐            ┌─────────┐
   │ Ark    │            │ Ark    │            │ 多条     │
   │ 路径:  │            │ 路径:  │            │ NoteComment│
   │ Bearer │            │ Bearer │            │ (role=ai) │
   │ Auth   │            │ + 多帧  │            │ suggestionJSON│
   └────┬───┘            └────┬───┘            └────┬────┘
        │                     │                    │
        ▼                     ▼                    ▼
   imageUrls[]            videoUrl            recordId 关联
   写入 record.imageUrls  写入 record.videoUrl  user 评论亦然
```

### 文字说明

- **文本生成路径**：`GenerateRequest` → （`LLMTextGenerator` 走 OpenAI 兼容 chat/completions，`MockGenerator` 走本地模板）→ `GenerateResponse` → `GenerationRecord` → `ModelContext.save` → UI。
- **配图路径**：`record.imagePrompt` → `JimengService.generateImage(prompt:)`（单张）或 `.generateImages(prompts:referenceImagesData:)`（N 张并行，`withTaskGroup`） → 走 `ArkJimengClient`（Bearer）或 `JimengAPIClient`（HMAC-SHA256） → `imageUrls: [String]` → 写入 `record.imageUrls`。
- **视频路径**：`record.videoPrompt` + 当前所有 `imageUrls`（作参考帧）→ `JimengService.generateVideo(prompt:referenceImageURLs:)` → `ArkJimengClient.generateVideo` / `JimengAPIClient.generateVideo` → `videoUrl: String?` → 写入 `record.videoUrl`。
- **诊断路径**：`record` → `DiagnosticAgent.diagnose` → `chatJSON(system: user:)` → 多条 `NoteComment(role=.ai, suggestion, suggestionStatus=.pending)` → 用户点"应用建议" → 改 `record` 字段 → `suggestionStatus=.applied`。
- **全局助手路径**：`ChatSession` + 用户文本 → `GlobalChatAgent.sendUserMessage` → 多条 `NoteComment(role=user/ai, recordId=session.id)` → 流式 `chatStream` 持续 `save`。
- **配置路径**：`LLMConfigView` 的 `@AppStorage` → `UserDefaults` → `LLMTextGenerator.isConfigured` / `JimengService.isConfigValidForImage` / `JimengService.isConfigValidForVideo` 实时检查。

---

## 5. 平台差异行为对照表

| 行为 / 控件 | iPhone (compact) | iPad (regular) | Mac (Catalyst & native) |
|---|---|---|---|
| **根容器** | `ZStack + 自定义 TabBar`（`tabLayout`，4 个 SF Symbol + 文字 + `regularMaterial` 背景延伸到 Home Indicator，`⌘1-4` 快捷键） | `NavigationSplitView` 双栏（左侧 sidebar 4 Tab，右侧 `NavigationStack`） | `NavigationSplitView` + macOS sidebar；菜单栏 4 个自定义 Command（`⌘1/2/3` + `设置…`） |
| **GenerateView 布局** | `compactLayout`：滚动区 + 底部浮动"立即生成"按钮 + `ThinkingOverlay` | `regularLayout`：限制最大宽度 600pt | 与 iPad regular 相同 |
| **ResultView 布局** | 单栏 + `Picker("模式")` 切换 edit/preview | tri-pane（文案 + drag handle + AI 工具）+ 预览可独立显示 | tri-pane 默认；`topToolbar` 不显示 iOS 风格的 chevron.back |
| **AI 笔记助手入口** | `ChatLauncher` FAB → `fullScreenCover`（避免误关） | `ChatLauncher` FAB → `sheet`（`minWidth 720 minHeight 560`）；iPad 还可 Pencil 双击唤起 | 菜单栏 `文件 → AI 笔记助手` (`⌘⇧A`) + FAB → `openWindow(id: "global-assistant")`（独立 `Window` 块，`defaultSize 1100×720`） |
| **GlobalAssistantRoot 布局** | 单栈 + 顶部汉堡弹出 session sheet | `NavigationSplitView` 双栏（sidebar + chat） | 同 iPad |
| **历史记录删除手势** | 左滑 / 右键 contextMenu | 左滑 / 右键 | 右键 contextMenu（Mac 无 swipe） |
| **图片下载 / 保存** | `UIImageWriteToSavedPhotosAlbum` | 同 iPhone | `NSSavePanel` 单图 / `NSOpenPanel` 多图存目录 |
| **Zip 分享** | `.sheet → PackageShareSheet (UIActivityViewController)` | 同 iPhone | 直接 `NSSavePanel` 选目录，写入文件系统（不走 share sheet） |
| **CameraPicker** | `UIImagePickerController.sourceType = .camera`（仅真机 iPhone） | 不暴露 | 不暴露（Mac 上走 `NSOpenPanel`） |
| **键盘快捷键** | `⌘1-4` 切 Tab、`⌘⇧A` 助手 | 同 + `⌘↩` 发送 | 同 + 菜单栏全套 |
| **Pencil 双击** | 无（iPhone 无 Pencil） | 唤起 AI 助手 | 不适用 |
| **Text Drag & Drop** | 同 iPad（来自其他 app 拖文字进输入框） | `textDropTarget` 修饰器（带高亮指示器） | 不适用 / 不启用 |
| **OnboardingView 样式** | 翻页 `TabView(.page)` + 跳过 | 同 iPhone | 限定 `minWidth 480 idealWidth 540 minHeight 600 idealHeight 660` |
| **质量模式 toggle** | 浮动在 GenerateView 顶部 | 同 iPhone | 同 iPhone |
| **CoachMark** | 仅 iPhone 显示 step-by-step 高亮（用 `coachMarkTarget` 修饰） | 同 iPhone | Mac 上一般不显示（pointing device 不需要） |

**功能独占小结**：
- **Mac 独占**：独立 AI 助手 Window（`RedPulseApp` 的 `Window("AI 笔记助手", id: "global-assistant")` 块）、菜单栏自定义命令、⌘⇧A 快捷键直接打开助手。
- **iPhone 独占**：`CameraPicker` 真机相机拍摄、`fullScreenCover` 助手弹出、自定义 `TabBar` 占用底部 safe area。
- **iPad 独占 / 增强**：Apple Pencil 双击唤起助手、`NavigationSplitView` 双栏、Text Drop 目标高亮（macOS 也支持但默认不显示指示器）。

---

## 6. 已知不完整 / 占位功能清单

按"未实现"程度从高到低排序：

| # | 位置 | 类型 | 说明 |
|---|---|---|---|
| 1 | `Network/LLMTextGenerator.swift:117-123` | **未实现** | `LLMTextGenerator.generateImage()` 和 `.generateVideo()` 都 `throw LLMTextGeneratorError(message: "未实现")` —— 文本 Generator 不负责生图生视频，调用方必须走 `JimengService`（GeneratorProtocol 接口定义在那里但实现抛错）。 |
| 2 | `Network/JimengService.swift:185` | **未实现（Volc 路径）** | "Volc 旧 API 路径暂未实现 image-to-image；refData 被忽略。"—— 多参考图生图只在 Ark 路径有效，走 AK/SK 路径时 `referenceImagesData` 参数被静默丢弃。 |
| 3 | `MockGenerator` | **占位** | 整个 Mock 模式只生成模板化的标题 / 正文 / 标签 / 配图 prompt，**不调真实 LLM / 不调即梦**。图片返回 `picsum.photos` 占位 URL，视频返回 `https://example.com/mock-video-*.mp4`（实际打不开）。 |
| 4 | `ResultView.swift:300` | **占位 / 误命名** | 顶栏"编辑"按钮（pencil.circle 图标）实际 `debugMode.toggle()`，从命名看应是进入编辑模式，但 ResultView 已用 `resultMode` Picker 控模式，`debugMode` 字段在初始化后没看到其他使用 —— 可能残留/未接通。 |
| 5 | `RedPulseApp.swift:57` | **占位** | "RedPulse 帮助"菜单按钮跳 `https://example.com/help`（占位 URL）。 |
| 6 | `RootTabView.swift:71-77` | **注释掉 / 未启用** | `.overlay { ChatLauncher() ... }` 与 `.overlay { CoachMarkOverlay() }` 整段被注释，未挂在根视图上 —— ChatLauncher 仅在 Assistant feature 内部引用，CoachMark 暂时未启用。 |
| 7 | `Features/Assistant/ChatLauncher.swift:139` | **实现不完整** | `onReceive(.pencilDoubleTapOpenAssistant)` 订阅了通知，但 `Features/CoachMark/CoachMarkOverlay.swift` 中没有发布该通知的代码路径；只有 macOS 菜单通过 `NotificationCenter.default.post(name: .openAIAssistant)` 触发。Pencil 双击实际依赖系统 `UIPencilInteraction` delegate 回调。 |
| 8 | `Models/GenerationRecord.swift:36` | **持久化但未消费** | `hotScore` 字段写入 SwiftData 但 UI 不展示，文档明确说"仅后台质量监控"——目前没有任何后端消费方。 |
| 9 | `Data/Repository.swift:56, 92, 107, 122, 159` | **字符串转义 bug** | 多处 log 调用里 `\(error.localizedDescription)` 写成了 `\\(error.localizedDescription)`（两个反斜杠）—— 编译能过，但日志输出会是字面 `\()` 而非实际错误描述。 |
| 10 | `Features/SelectionToolbar/QuickActionsHistory.swift` | **未持久化** | 划词 AI 工具栏的 history 只在内存（`history.addRecord`），关闭 app 即丢失，注释暗示这是 by-design 但没明示。 |
| 11 | `Features/Profile/DebugLogView.swift` | **仅开发用** | 调试日志查看器，UI 入口在 `我的 → 设置 → 调试日志`，正式版是否暴露待定。 |
| 12 | `Network/JimengService.swift:71-74, 83-84` | **校验逻辑倒置** | `validateConfig` 当 `imageArkKey` 空时会先 push `imageAK/SK/reqKey` 三个 issues，然后**又追加**"Ark API Key 未配置（可选，填了可走更简洁的认证路径）"——但 Ark 是可选项，把它当 issue 提示会让用户困惑。 |
| 13 | `Data/Repository.swift` | **未提供** | 没有 `updateProduct(_:)` / `updateRecord(_:)` 方法 —— 更新走 `modelContext.insert()` + `try? save()`，调用方（如 `ResultView` 编辑场景）必须自己改字段后 save，缺统一更新入口。 |
| 14 | `Features/Generate/GenerateView.swift:80` | **未启用** | 顶栏"返回"按钮在 iOS 上只在 ResultView 出现，但 `ResultView.topToolbar` 中的 `#if os(iOS) Button { generatedRecord = nil }` 引用了一个未声明的 `generatedRecord` 局部变量（实际是 GenerateView 的 state，从 ResultView 不可见），疑似 bug 或注释残留。 |
| 15 | `_PROJECT_CONVENTIONS.md` vs 实际 | **约定 ≠ 实现** | 宪法规定 iOS 17+、SwiftData、`@Observable`、Swift Concurrency —— 实际全部遵守。但宪法列出的目录（`Features/Auth`、`Features/HomeView` 等）和实际文件名（`GenerateView.swift`、`ResultView.swift`）有差异 —— 实际项目结构在 V3.2 演化中已偏离宪法初始规划。 |

---

## 7. 一句话总结

**RedPulse 是一个以 SwiftData 为本地唯一数据源、GeneratorProtocol 为文本生成抽象、JimengService 为即梦图片视频网关、NoteComment 复用为评论与全局助手消息统一载体的 SwiftUI 多端 AI 笔记创作工具 —— iPhone 用 Tab+Bottom 浮动按钮，iPad/Mac 用 NavigationSplitView 多栏 + Mac 独立 Window 助手 —— 主链路（选产品 → LLM 出文案 → 即梦出图/视频 → 模拟发布 → AI 诊断师评审 + 全局助手对话）已串通，但 LLMGenerator 的 image/video 占位未实现、CoachMark/ChatLauncher 未挂到 Root、Repository 字符串转义错误等小问题待修复。**

---

*生成时间：2026-06-24 14:xx* · 范围：`/Users/mac/Desktop/RedbookRefill/RedbookRefill/` 全量源码反推 + 项目宪法 + 需求文档 V3.2 · 字数：~3500 中文字符（含表格）。