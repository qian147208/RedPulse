# AI 划词应用 —— 集成指南

> 版本：1.0  
> 日期：2026-01-15  
> 项目：RedbookRefill（红书笔芯）

---

## 一、文件变更清单

### 新建文件（需在 Xcode 中手动添加到项目）

```
Features/SelectionToolbar/
├── QuickActionsHistory.swift          # QuickAction 枚举 + IntentGuesser + 历史存储
├── SelectionToolbarViewModel.swift     # UI 状态管理
└── SelectionToolbarView.swift          # 浮动工具栏 + 结果卡片 + 微调面板

DesignSystem/
└── PlatformInteractions.swift         # iPad Drag & Drop + Pencil 双击 + 键盘快捷键

DESIGN_DOC.md                           # 设计说明文档（本目录）
INTEGRATION_GUIDE.md                    # 本文件
```

### 修改文件（已由本重构完成）

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `RedbookRefillApp.swift` | 修改 | 新增 AppCommands（Mac 菜单栏）、AppStorage 持久化 Tab、ContentView 传参 |
| `ContentView.swift` | 修改 | 新增 `selectedTabRaw` Binding 参数 |
| `RootTabView.swift` | 重写 | Liquid Glass 导航结构、glass tab bar / sidebar |
| `DesignSystem/DesignTokens.swift` | 扩展 | 新增 Liquid Glass 材质颜色、GlassMetrics 尺寸体系 |
| `DesignSystem/ViewModifiers.swift` | 扩展 | 新增 glassSurface/glassCard/glassButton/interactiveGlass 等 modifier |
| `Features/Result/RewritableTextEditor.swift` | 重写 | 集成 SelectionToolbarView 替代 RewritePromptDialog |
| `Features/Result/ResultView.swift` | 修改 | 新增 SelectionToolbarViewModel、overlay + onChange |
| `DesignSystem/PlatformInteractions.swift` | **新建** | iPad Drag & Drop、Pencil 双击、键盘快捷键修饰器 |
| `Features/Assistant/GlobalAssistantRoot.swift` | 修改 | ChatPane 增加 textDropTarget |
| `Features/Assistant/ChatLauncher.swift` | 修改 | 监听 Pencil 双击通知 |

---

## 二、如何将新文件加入 Xcode 项目

### 2.1 在 Xcode 中添加新建文件

1. 打开 `RedbookRefill.xcodeproj`
2. 在 Project Navigator 中，右键点击 `RedbookRefill/Features` 目录
3. 选择 **"Add Files to 'RedbookRefill'…"**
4. 导航到 `RedbookRefill/RedbookRefill/Features/SelectionToolbar/`
5. 选中以下三个文件：
   - `QuickActionsHistory.swift`
   - `SelectionToolbarViewModel.swift`
   - `SelectionToolbarView.swift`
6. 确保勾选 **"Copy items if needed"**，Target 选中 **RedbookRefill**
7. 点击 **Add**

### 2.2 验证 Target Membership

在 Project Navigator 中依次选中三个新文件，在右侧 File Inspector 的 **Target Membership** 中确认 `RedbookRefill` 已勾选。

### 2.3 构建设置确认

- **Deployment Target**: iOS 17.0 / macOS 14.0（不变）
- **Swift Language Version**: Swift 5.9+（不变）

---

## 三、如何调用原有 AI 接口

### 3.1 SelectionToolbarView 接入现有 AI 管道

`SelectionToolbarViewModel` 提供了两个闭包来连接现有 AI 服务：

```swift
// 在您的视图中（如 ResultView 或 RewritableTextEditor）
let viewModel = SelectionToolbarViewModel()

// 1. 连接 AI 生成
viewModel.onGenerate = { action, selectedText, customInstruction in
    // action: QuickAction (translate/explain/summarize/rewrite/shorter/longer/custom)
    // selectedText: 用户选中的原始文本
    // customInstruction: 可选的自定义指令（仅 .custom 时非空）
    //
    // 构造指令字符串：
    let instruction = customInstruction ?? action.llmInstruction
    
    // 调用现有 LLM：
    return try await generator.transformText(
        command: instruction,
        selectedText: selectedText,
        context: contextSnippet
    )
}

// 2. 连接替换操作
viewModel.onReplace = { resultText in
    // 用 AI 结果替换原文中的选中部分
    record.content = record.content.replacingOccurrences(
        of: selectedText,
        with: resultText
    )
}
```

### 3.2 保持 RewritePromptDialog 兼容

旧的 `RewritePromptDialog` 仍完整保留，两个入口：

| 入口 | 位置 | 说明 |
|------|------|------|
| `RewritableTextEditor` | `.sheet(isPresented: $showRewriteDialog)` | Fallback 模式，当 `useNewToolbar = false` 时 |
| `ResultView` | `.sheet(isPresented: $showRewriteDialog)` | 划词改写小窗，保持兼容 |

新代码默认使用 `SelectionToolbarView` 浮动工具栏，但旧 dialog 入口未删除。

---

## 四、三端编译条件

所有平台差异通过以下方式隔离：

```swift
// 1. OS 条件编译
#if os(macOS)
    // Mac 专属代码（菜单栏、独立窗口）
#elseif os(iOS)
    // iOS/iPad 专属代码（触觉反馈、尺寸类别）
#endif

// 2. 未来 Liquid Glass 原生支持（Xcode 26+）
#if compiler(>=6.2)
    // 使用原生 glassEffect / GlassEffectContainer
#else
    // 使用 .ultraThinMaterial + 自定义光晕模拟
#endif

// 3. 运行时尺寸适配
@Environment(\.horizontalSizeClass) private var sizeClass
if sizeClass == .regular {
    // iPad 横屏 / Mac → Sidebar 布局
} else {
    // iPhone → Tab Bar 布局
}
```

---

## 五、关键设计 Token 对照

### 5.1 Liquid Glass 模拟 → 原生映射

| 模拟方案 (iOS 17+) | 原生方案 (iOS 26+/Xcode 26) | 用途 |
|---------------------|------------------------------|------|
| `.ultraThinMaterial` + `Color.glassSurface` + `LinearGradient` highlight | `glassEffect` | 导航栏/Sidebar/Tab Bar |
| `.regularMaterial` + `Color.glassSurface` + shadow | `glassEffect` (smaller) | 内容卡片 |
| `RadialGradient` glow on press | 原生 glass 交互光效 | 按钮按下反馈 |
| `ScrollEdgeDissolveModifier` (mask) | `scrollEdgeEffect` | 滚动内容溶解 |
| `GlassCardModifier` (layered material) | `glassEffect` variant | AI 结果面板 |

### 5.2 颜色系统

| Token | Light | Dark | 用途 |
|-------|-------|------|------|
| `glassSurface` | `white/0.72` | `#1C1C1E/0.82` | 玻璃材质底色 |
| `glassElevated` | `white/0.88` | `#2C2C2E/0.92` | 弹出层玻璃 |
| `glassHighlight` | `white/0.55` | `white/0.12` | 顶部高光 |
| `glassShadow` | `black/0.10` | `black/0.50` | 玻璃阴影 |
| `glassGlow` | `white/0.70` | `white/0.25` | 按压发光 |
| `glassBrandTint` | `brand/0.18` | `brand/0.22` | 品牌色玻璃着色 |

---

## 六、验证清单

在 Xcode 中 build & run 后，逐项验证：

### 6.1 导航层
- [ ] iPhone 竖屏：底部浮动 glass tab bar 正常显示，三个 Tab 可切换
- [ ] iPhone 横屏 / iPad：左侧 glass sidebar 正常显示
- [ ] Mac：sidebar 浮动在内容之上，窗口缩放时正常
- [ ] ChatLauncher FAB 在所有 Tab 都可见、可拖拽
- [ ] Dynamic Type 放大后 Tab Bar 高度自适应
- [ ] 浅色/深色模式切换后 glass 材质正确自适应

### 6.2 划词工具栏
- [ ] 在 `RewritableTextEditor` 中选中文字 → 浮动工具栏出现
- [ ] 推荐动作（蓝色高亮）符合意图猜测预期
- [ ] 点击任意快捷动作 → 显示 loading → 显示结果卡片
- [ ] 结果卡片可点击"替换原文"完成替换
- [ ] 结果卡片"复制"按钮正常工作
- [ ] "…"微调面板：更短/更详细/更口语/更正式 + 自定义指令
- [ ] `ESC` 键或 `×` 按钮关闭工具栏
- [ ] 在 `ResultView` 的正文编辑区选中文字 → 工具栏同样出现

### 6.3 Mac 菜单栏
- [ ] `⌘1/2/3` 可切换 Tab
- [ ] `⌘,` 打开设置
- [ ] `⇧⌘A` 打开 AI 助手窗口
- [ ] 菜单栏显示"红书笔芯"菜单项

### 6.4 无障碍
- [ ] 系统设置 → 辅助功能 → 降低透明度 → glass 元素变为不透明
- [ ] 系统设置 → 辅助功能 → 减弱动态效果 → 动画禁用
- [ ] VoiceOver 可朗读所有按钮标签

### 6.5 兼容性
- [ ] 旧的 RewritePromptDialog 仍可通过特定路径触发（不报错）
- [ ] 所有原有功能（生成笔记、产品库、历史记录、设置、登录）正常工作
- [ ] SwiftData 数据持久化不受影响

---

## 七、常见问题

### Q: 编译报错 `Cannot find 'SelectionToolbarViewModel' in scope`
**A:** 新文件尚未加入 Xcode target。按照 §2.1 步骤将 `Features/SelectionToolbar/` 下三个文件添加到项目。

### Q: `@Environment(\.accessibilityReduceTransparency)` 在 `ButtonStyle` 中报错
**A:** SwiftUI `ButtonStyle` 从 iOS 15+ / macOS 12+ 已支持 `@Environment`。请确认 Deployment Target ≥ iOS 17.0（项目已满足）。

### Q: Glass 效果在模拟器中不显示
**A:** `.ultraThinMaterial` 在旧版模拟器可能渲染为纯色。在真机或最新 Xcode 模拟器中验证。

### Q: `IntentGuesser` 的意图猜测不准确
**A:** `IntentGuesser.guess()` 是简单启发式函数，仅影响推荐动作的高亮显示。用户可以自由点击任何其他动作。如需调整阈值，修改 `QuickActionsHistory.swift` 中的 `guess(for:)` 函数。

---

## 八、回滚方案

如需完全回滚到重构前的状态：

1. 使用之前创建的备份：`RedbookRefill_backup_YYYYMMDD`
2. 或通过 Git 回滚：
   ```bash
   cd RedbookRefill
   git checkout -- RedbookRefillApp.swift ContentView.swift RootTabView.swift
   git checkout -- DesignSystem/DesignTokens.swift DesignSystem/ViewModifiers.swift
   git checkout -- Features/Result/RewritableTextEditor.swift Features/Result/ResultView.swift
   rm -rf RedbookRefill/RedbookRefill/Features/SelectionToolbar/
   ```

---

*本指南基于 WWDC25 Liquid Glass 设计语言编写，所有 AI 核心功能保持不变。*
