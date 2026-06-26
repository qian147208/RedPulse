# AI 划词应用 —— UI 重构设计说明书

> 版本：1.0  
> 日期：2026-01-15  
> 项目：RedbookRefill（灵芯）

---

## 一、调研总结

### 1.1 信息来源

| 来源 | 内容 | 链接 |
|------|------|------|
| WWDC25 "Meet Liquid Glass" | Apple 新设计语言核心原则、光学特性、材质变体 | [developer.apple.com/videos/play/wwdc2025/219](https://developer.apple.com/videos/play/wwdc2025/219) |
| WWDC25 "Build a SwiftUI app with the new design" | SwiftUI API 实现、TabView/NavigationSplitView 更新、控件新样式 | [developer.apple.com/videos/play/wwdc2025/323](https://developer.apple.com/videos/play/wwdc2025/323) |
| Apple HIG (长期参考) | 无障碍规范、触摸目标、动态字体、色彩系统 | [developer.apple.com/design](https://developer.apple.com/design) |
| 现有项目代码分析 | 理解当前 UI 架构、交互流程、业务边界 | 本地代码库 |

### 1.2 核心设计原则

#### 原则一：内容优先，导航退让
Liquid Glass 的核心理念是**让导航成为一层透明、浮动的光**，而非厚重的容器。导航栏、Tab Bar、Sidebar 都应该：
- 浮动在内容之上，不占据固定矩形空间
- 随滚动自动折叠/展开（`tabBarMinimizeBehavior`）
- 透明度根据背景内容自适应调整

#### 原则二：光学折射 (Lensing) 建立层次
传统 UI 通过阴影 + 边框区分层次，Liquid Glass 通过**光线的弯曲和聚焦**来传达深度：
- 小元素（按钮、chip）：透明 + 光晕，触碰时发光
- 大元素（Sidebar、Sheet）：自适应着色 + 环境光反射
- 从不过度叠加（禁止 Glass-on-Glass）

#### 原则三：流体动画联动
动画不是独立属性，而是材质的固有部分：
- 按钮按下 → 弹性缩放 + 内部发光扩散
- 菜单弹出 → 从按钮位置「生长」出来
- 页面切换 → 导航元素「变形」而非「替换」

#### 原则四：平台自适应
同一套导航 API，在不同平台自动适配：
| 平台 | 导航模式 | 特点 |
|------|----------|------|
| iPhone | 浮动 Tab Bar + 可折叠 | 单手操作热区，底部悬浮 |
| iPad | 浮动 Sidebar + Tab Bar | 侧栏可隐藏，双栏布局 |
| Mac | 独立窗口 + 菜单栏 | 多窗口，键盘快捷键 |

#### 原则五：轻量 AI 交互
AI 辅助应该**存在但不打扰**：
- 划词后弹出悬浮工具栏（非模态对话框）
- 快捷动作一键触发，无需输入额外指令
- 结果以小卡片形式展示，可一键替换/复制
- 智能猜测用户意图，减少选择负担

---

## 二、整体设计方案

### 2.1 渐进式 Liquid Glass 策略

由于本项目最低支持 iOS 17 / macOS 14，而原生 Liquid Glass API（`glassEffect` modifier）需要 Xcode 26 SDK (iOS 26 / macOS Tahoe)，我们采用**渐进式适配**：

```
┌─────────────────────────────────────────────┐
│  #if compiler(>=6.2)                        │
│    → 使用原生 glassEffect / GlassEffectContainer │
│  #else                                      │
│    → 使用 .ultraThinMaterial + 自定义光晕效果   │
│  #endif                                     │
└─────────────────────────────────────────────┘
```

**模拟 Liquid Glass 的技术方案（兼容模式）**：
1. `.ultraThinMaterial` + `.background(.regularMaterial)` 双层材质
2. 叠加微弱的 `LinearGradient` 高光层（模拟 lensing）
3. `shadow` 透明度根据背景动态调整（深色背景 → 更深的阴影）
4. 按钮按压时：`scaleEffect` + 内部光晕扩散动画
5. 滚动边缘：`.mask` + `LinearGradient` 实现内容溶解

### 2.2 色彩系统

保留现有品牌色 `#FF2442`（小红书红），新增 Liquid Glass 配套的**自适应材质色**：

```
glassSurface    — 用于 Sidebar / Sheet 的浮动材质
glassElevated   — 用于弹出菜单 / 工具栏的背景
glassHighlight  — 材质表面的高光线
glassShadow     — 自适应阴影色（深色背景更深）
```

### 2.3 导航架构重构

```
RedbookRefillApp
├── ContentView（路由根，不变）
│   ├── LoginView（不变）
│   └── RootTabView ★ 重构
│       ├── [iPhone] TabView(.page) + glassTabBar
│       │   ├── GenerateView（业务逻辑不变，外层包装更新）
│       │   ├── ProductListView（不变）
│       │   └── HistoryView（不变）
│       └── [iPad/Mac] NavigationSplitView
│           ├── Sidebar: Liquid Glass 浮动面板
│           │   ├── 功能列表（TabItem）
│           │   ├── 头像入口
│           │   └── 设置入口
│           └── Detail: 内容区
│               └── NavigationStack → Tab 内容
├── ChatLauncher（FAB，保留但视觉更新）
└── [Mac] Window "global-assistant"（不变）
```

### 2.4 动画系统

| 交互 | 动画 | 时长 |
|------|------|------|
| Tab 切换 | `.spring(response: 0.3, dampingFraction: 0.7)` | 0.3s |
| 按钮按下 | `.interactiveSpring(response: 0.2, dampingFraction: 0.6)` | 0.2s |
| 菜单弹出 | `.spring(response: 0.35, dampingFraction: 0.8)` | 0.35s |
| 页面过渡 | `.easeInOut(duration: 0.25)` | 0.25s |
| 浮动工具栏出现 | `.spring(response: 0.3, dampingFraction: 0.75)` | 0.3s |
| Scroll 边缘溶解 | 隐式（随 offset 渐变） | 实时 |

---

## 三、AI 划词小功能设计

### 3.1 交互流程

```
用户选中文本
    │
    ▼ (0.3s debounce)
┌──────────────────────────┐
│  智能意图猜测引擎           │
│  - 纯中文短文本 → 解释      │
│  - 含英文 → 翻译           │
│  - 长文本 → 总结           │
│  - 含"标题"/"tag" → 改写   │
└──────────────────────────┘
    │
    ▼
┌──────────────────────────────┐
│  浮动工具栏（非模态）          │
│  ┌────┬────┬────┬────┬───┐  │
│  │翻译│解释│总结│改写│···│  │
│  └────┴────┴────┴────┴───┘  │
│         ↑ 推荐动作高亮        │
└──────────────────────────────┘
    │ 点击动作
    ▼
┌──────────────────────────────┐
│  结果卡片（可拖拽）            │
│  ┌────────────────────────┐  │
│  │ [AI 图标] 翻译结果       │  │
│  │ ...译文内容...           │  │
│  │ [复制] [替换] [···]     │  │
│  └────────────────────────┘  │
│         ↓ 点击 ···            │
│  ┌────────────────────────┐  │
│  │ 微调选项                 │  │
│  │ · 更短  · 更详细        │  │
│  │ · 更口语 · 更正式       │  │
│  │ · 自定义指令…            │  │
│  └────────────────────────┘  │
└──────────────────────────────┘
```

### 3.2 工具栏位置（三端适配）

| 平台 | 位置 | 理由 |
|------|------|------|
| iPhone | 键盘上方 / 选中文本下方 | 单手操作热区，不遮挡内容 |
| iPad | 选中文本附近（智能避让） | 利用更大屏幕空间 |
| Mac | 光标跟随气泡 | 鼠标交互，跟随指针 |

### 3.3 快捷动作

| 动作 | 图标 | 适用场景 |
|------|------|----------|
| 翻译 | `globe` | 选中含英文/外文 → 翻译为中文 |
| 解释 | `text.magnifyingglass` | 选中术语/概念 → 通俗解释 |
| 总结 | `text.alignleft` | 选中长段落 → 提取关键点 |
| 改写 | `sparkles` | 选中中文文本 → AI 润色改写 |
| 更短 | `text.badge.minus` | 压缩文本保留核心意思 |
| 更详细 | `text.badge.plus` | 展开要点增加细节 |

### 3.4 智能意图猜测

```swift
func guessIntent(for text: String) -> QuickAction {
    // 含大量英文/外文字符 → 翻译
    if containsMainlyNonChinese(text) { return .translate }
    // 少于 20 字 → 解释
    if text.count < 20 { return .explain }
    // 超过 200 字 → 总结
    if text.count > 200 { return .summarize }
    // 默认 → 改写
    return .rewrite
}
```

### 3.5 历史记录存储

使用 `UserDefaults` 存储最近 20 条操作记录：

```swift
struct QuickActionRecord: Codable {
    let action: String      // "translate" / "explain" / ...
    let originalText: String
    let resultText: String
    let timestamp: Date
}
```

---

## 四、三端差异化适配

### 4.1 iPhone

- **Tab Bar**: 底部浮动，跟随滚动折叠（`.tabBarMinimizeBehavior(.onScrollDown)`）
- **划词工具栏**: 键盘上方 / 选中文本下方 8pt
- **ChatLauncher FAB**: 右下角，可拖拽
- **触摸目标**: ≥44pt 所有按钮
- **手势**: 右滑返回（系统级）

### 4.2 iPad

- **Sidebar**: 浮动 Liquid Glass 材质，可折叠/展开
- **Tab Bar**: 与 Sidebar 二选一，`sizeClass == .regular` 时用 Sidebar
- **划词工具栏**: 选中文本附近，智能避让（不在键盘下方）
- **多窗口**: 支持 Split View / Slide Over
- **拖拽**: 支持 Drag & Drop 文本到 AI 助手
- **Pencil**: 双击切换工具

### 4.3 Mac

- **Sidebar**: 浮动半透明，跟随窗口四角弧度
- **菜单栏**: 完整的 App Menu（File / Edit / View / Window / Help）
- **快捷键**:
  - `⌘1/2/3` — 切换 Tab
  - `⇧⌘A` — 打开 AI 助手窗口
  - `⌘,` — 设置
  - `ESC` — 关闭浮动工具栏
- **多窗口**: 支持打开多个 AI 助手窗口
- **Drag & Drop**: 从其他 app 拖动文本到 AI 助手聊天栏

### 4.4 跨平台多模态交互

| 交互模式 | iPhone | iPad | Mac |
|----------|--------|------|-----|
| 触控 | ✅ 主交互 | ✅ 主交互 | — |
| 键盘快捷键 | ⌘1/2/3（外接键盘） | ⌘1/2/3（外接键盘） | ✅ 完整菜单栏 |
| 鼠标/触控板 | — | ✅ 右键菜单 | ✅ 完整支持 |
| Apple Pencil 双击 | — | ✅ 快速打开 AI 助手 | — |
| Drag & Drop | — | ✅ 拖文本到工具栏/聊天 | ✅ 跨应用拖放 |

---

## 五、兼容性保证

### 5.1 未改动的核心功能

| 模块 | 文件 | 说明 |
|------|------|------|
| 数据模型 | `Models/*.swift` | Product, GenerationRecord, Feedback, ChatSession 等 @Model 类完全不改 |
| 数据访问 | `Data/Repository.swift`, `Data/AuthStore.swift`, `Data/KeychainHelper.swift` | 不改任何持久化逻辑 |
| 网络层 | `Network/*.swift` | LLMTextGenerator, MockGenerator, JimengService 等完全不改 |
| AI 调用 | `LLMTextGenerator`, `ArkJimengClient`, `JimengAPIClient` | 不改 API 调用、请求构造、响应解析 |
| 设置存储 | `UserDefaults` 键值 | 不改任何 AppStorage key |
| 业务视图 | `Features/Generate/GenerateView.swift`, `Features/Result/ResultView.swift`, `Features/History/HistoryView.swift`, `Features/Library/*.swift`, `Features/Profile/*.swift`, `Features/Auth/LoginView.swift`, `Features/Onboarding/OnboardingView.swift` | 所有业务视图的主体逻辑不改，仅外层包装需要适配新导航结构 |

### 5.2 适配器模式

对于 `SelectableTextEditor`，原有 `RewritePromptDialog` 的调用方式不变（回调接口 `onConfirm: (String) async -> Void` 保持不变），我们在外层包一个 `SelectionToolbarView` 作为新的入口，内部继续调用同一个 `onConfirm` 回调：

```
SelectionToolbarView (新 UI)
    ↓ 用户点击动作
    ↓ 构造指令字符串
    ↓
RewritePromptDialog.onConfirm(prompt)  ← 完全不变的接口
    ↓
LLMTextGenerator (核心业务逻辑，不动)
```

### 5.3 编译安全

- 使用 `#if os(macOS)` / `#if os(iOS)` 条件编译隔离平台代码
- 使用 `#if compiler(>=6.2)` 预留 Liquid Glass 原生 API 路径
- 使用 `@available(iOS 17.0, macOS 14.0, *)` 标注新 API 使用
- 所有新视图遵循项目现有命名约定

---

## 六、文件清单

### 新建文件

```
Features/SelectionToolbar/
├── SelectionToolbarView.swift       # 浮动工具栏主视图
├── SelectionToolbarViewModel.swift   # UI 状态管理
└── QuickActionsHistory.swift        # UserDefaults 历史记录

DesignSystem/
└── PlatformInteractions.swift       # iPad Drag & Drop + Pencil 双击 + 键盘快捷键

RedbookRefill/
├── DESIGN_DOC.md                    # 本文件
└── INTEGRATION_GUIDE.md             # 集成指南
```

### 修改文件

```
RedbookRefillApp.swift               # 添加 Mac 菜单栏 + 无障碍
ContentView.swift                    # 透传 selectedTabRaw
RootTabView.swift                    # 重构导航结构 + Pencil 支持
DesignSystem/
├── DesignTokens.swift               # 新增 Liquid Glass 色值 + 材质常量
└── ViewModifiers.swift              # 新增 glassCard, glassButton, interactiveGlass modifier
Features/Result/
├── SelectableTextEditor.swift       # 不变（接口保持）
├── RewritableTextEditor.swift       # 集成 SelectionToolbarView
└── ResultView.swift                 # 集成 SelectionToolbarViewModel
Features/Assistant/
├── ChatLauncher.swift               # 监听 Pencil 双击通知
└── GlobalAssistantRoot.swift        # ChatPane 增加 textDropTarget
```

### 修改文件

```
RedbookRefillApp.swift               # 添加 Mac 菜单栏 + 无障碍
RootTabView.swift                    # 重构导航结构
DesignSystem/
├── DesignTokens.swift               # 新增 Liquid Glass 色值 + 材质常量
└── ViewModifiers.swift              # 新增 glassCard, glassButton, interactiveGlass modifier
Features/Result/
├── SelectableTextEditor.swift       # 接入浮动工具栏
└── RewritePromptDialog.swift        # 微调面板适配（保留作为二级面板）
```

---

*本设计文档基于 WWDC25 Apple 官方资料撰写，具体实现考虑了 iOS 17+ / macOS 14+ 的最低版本限制。*
