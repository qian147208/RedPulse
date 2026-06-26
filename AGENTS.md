# AGENTS.md

> **红书笔芯 / RedbookRefill** — iOS + macOS SwiftUI 小红书种草笔记生成器（小红书风格文/图/视频多模态生成 + 灵感和发布预览）。
> 
> 本文件被 OpenCode / Codex / Cursor / Aider / Devin / Gemini CLI / Claude Code / Mavis 等所有 AGENTS.md-aware 工具识别。每次新会话先读这个。

---

## Setup & Build

| 动作 | 命令 |
|------|------|
| **打开项目** | Xcode 打开 `RedbookRefill.xcodeproj` |
| **一键 build**（推荐） | `bash build_and_check.sh` — 跑 Debug 配置到 macOS |
| **手动 build** | `xcodebuild -project RedbookRefill.xcodeproj -scheme RedbookRefill -destination 'platform=macOS' -configuration Debug build` |
| **Run** | Xcode ⌘R 或 `xcodebuild ... build && open build/.../RedbookRefill.app` |
| **测试** | 当前**无单元测试**（`RedbookRefillTests/` 不存在）— 靠手动跑 |
| **Lint / Format** | 当前**无 SwiftLint / swift-format 集成**——靠项目内 `_PROJECT_CONVENTIONS.md` 约定 |

**前置环境**：Xcode 17+、macOS 14+（macOS target 14.0，iOS target 17.0）。无 CocoaPods / SPM 依赖——纯 Apple SDK + 自写。

**Branch**：当前开发在 `main`（之前 `qian147208/fix/sidebar-click-macos` 等都已合并）。本仓库**单分支、单开发者**，不需要 PR review 流程。

---

## 项目结构

```
RedbookRefill/                          ← Xcode project 根（这里跑 git）
├── RedbookRefill.xcodeproj/            ← objectVersion 77，文件系统同步组（自动 pick up 新文件）
├── RedbookRefill/                      ← 源码根（所有 Swift 代码在这里）
│   ├── RedbookRefillApp.swift          ← App 入口（注意：文件名是历史遗留，叫 RedPulse 不叫 RedbookRefill）
│   ├── ContentView.swift                ← 路由根容器
│   ├── RootTabView.swift                ← iOS Tab 视图根
│   ├── DesignSystem/                    ← 设计 token / ViewModifier / 动效
│   ├── Models/                          ← SwiftData @Model：Product / GenerationRecord / NoteComment / Feedback
│   ├── Data/                            ← Repository（唯一持有 ModelContext）+ DebugLog
│   ├── Navigation/                      ← 路由抽象
│   ├── Network/                         ← LLMTextGenerator / AgnesService / JimengService / MockGenerator / APIError
│   ├── Features/                        ← 按业务域分：Generate / Result / History / Onboarding / Profile / SelectionToolbar / Assistant / Inspiration
│   ├── PrivacyInfo.xcprivacy            ← 隐私 manifest（CA92.1/C617.1/E174.1 已声明）
│   └── _PROJECT_CONVENTIONS.md          ← 项目宪法（**最高优先级**约束）
├── build_and_check.sh                  ← 三端 build 验证脚本
├── DESIGN_DOC.md                       ← 整体设计文档
├── INTEGRATION_GUIDE.md                ← 第三方 API 接入指南
├── README.md
├── config/                              ← 构建配置
├── website/                             ← 官网源码
└── .deliverables/                       ← 生成产物（不入 git）
```

---

## 代码风格（强约束）

**SwiftUI 派别**（继承自 `_PROJECT_CONVENTIONS.md`）：

| 维度 | 选择 | 反例 |
|------|------|------|
| UI 框架 | SwiftUI | ~~UIKit~~（除非必要） |
| 数据持久化 | SwiftData | ~~CoreData~~ |
| 状态管理 | `@Observable` 宏 | ~~ObservableObject / @Published~~ |
| 异步 | Swift Concurrency（async/await） | ~~Combine~~ |
| 最低版本 | iOS 17 / macOS 14 | — |

**Swift 风格**：

- SwiftUI 视图默认 `private struct`，对外 API 才 `public`
- `@MainActor` 标在 `@Observable` 类上
- 错误一律 `enum X: LocalizedError`，中文 `errorDescription`
- 日志统一走 `DebugLog.shared`（分类：`.llm` / `.agnes` / `.jimeng` / `.ui` 等）
- 网络层 `nonisolated static` 函数发请求，避免 actor 隔离
- 命名：PascalCase 类型，camelCase 变量/方法，SCREAMING_SNAKE_CASE 静态常量

**Git 风格**：

- 提交信息中英混合：`fix:` / `重构:` / `feat:` 前缀
- 中文长描述 OK（团队习惯）
- 不强求 conventional commits，但建议

---

## API 配置（关键！）

**所有 LLM / 图像 / 视频**走**一个** endpoint + **一个** API Key（Agnes AI）：

| UserDefaults Key | 默认值 | 用途 |
|----------------|--------|------|
| `api_base_url` | `https://apihub.agnes-ai.com/v1` | LLM + Image base URL |
| `api_key` | （空） | Bearer Token |

**三个模型共用同一 Key**：

| 模型 | 用途 | 字段 |
|------|------|------|
| `agnes-2.0-flash` | 文案生成（标题/正文/标签） | `LLMTextGenerator.textModel` |
| `agnes-image-2.1-flash` | 图片生成（OpenAI `/v1/images/generations` 兼容） | `AgnesService.imageModel` |
| `agnes-video-v2.0` | 视频生成（异步任务 + 轮询） | `AgnesService.videoModel` |

UI 配置入口：`Profile/LLMConfigView.swift`（App 内「我的 → 大模型配置」）。

**目前模型预设只保留 Agnes 一家**——其他 provider 在 `ModelConfigStore.swift` 里已被隐藏（之前切换过 provider，留下接口但 UI 不暴露）。

---

## 详细模块文档

要改某一块前，**先读对应 topic 文件**——里面写了数据流、关键函数、坑：

| 改什么 | 读这个 |
|--------|--------|
| 文/图/视频生成端到端 | [`docs/text-to-image-pipeline.md`](docs/text-to-image-pipeline.md) |
| Agnes 视频 API（轮询、字段、错误） | [`docs/agnes-video-api.md`](docs/agnes-video-api.md) |
| 网络层整体架构 | [`docs/network-layer.md`](docs/network-layer.md) |
| 数据层（SwiftData + Repository） | [`docs/data-and-state.md`](docs/data-and-state.md) |
| Features 各模块对照 | [`docs/features-map.md`](docs/features-map.md) |
| 共享约定（最权威） | `RedbookRefill/_PROJECT_CONVENTIONS.md` |

---

## 常见修改任务 → 关键文件

| 任务 | 改这里 |
|------|--------|
| 改正文生成 prompt / JSON schema | `Network/LLMTextGenerator.swift` → `chatJSON()` 函数 |
| 改图片生成尺寸/参数 | `Network/AgnesService.swift` → `callImageAPI()` |
| 改视频生成参数/超时/轮询 | `Network/AgnesService.swift` → `callVideoAPI()` |
| 加新 adType | `Models/AdType.swift` |
| 改 SwiftData schema | `Models/*.swift`（注意 @Model 迁移） |
| 改 UI 配色/间距 | `DesignSystem/DesignTokens.swift` |
| 加新页面 | `Features/<新模块>/` + 改 `Navigation/` |
| 改保存逻辑 | `Data/Repository.swift` |
| 加新 LLM 调用 | 复制 `chatCompletions()` 模式，加 `DebugLog` tag |

---

## 已知问题 / 坑

1. **Stale Jimeng 引用**：Xcode project 历史上引用过 `JimengService.swift` / `JimengAPIClient.swift` / `JimengContracts.swift` / `ArkJimengClient.swift` ——这些文件已经删除但 `project.pbxproj` 里可能仍有引用。**现在统一用 Agnes**，遇到 stale ref 在 build 报错时从 pbxproj 里手动清掉。
2. **`QualityToggle.swift`**：已删除，Xcode project 引用可能还在。
3. **`RedbookRefillApp.swift` vs `RedbookRefill.xcodeproj`**：入口文件名是历史遗留（叫 `RedPulseApp.swift` 时代），不要 rename，会断 Xcode 引用。
4. **`DebugLog.shared` 是单例**：异步安全，多分类（`.llm` / `.agnes` / `.jimeng` 等），所有日志入口。
5. **Agnes 视频是异步任务**：POST 创建任务 → 轮询查结果，**最长 8 分钟超时**——别用同步阻塞调用。
6. **网络层 `nonisolated static`**：发请求必须用 `nonisolated` 函数，不然 `@MainActor` 隔离会让请求被 dispatch 回主线程。

---

## 修改工作流（推荐）

1. **读 `_PROJECT_CONVENTIONS.md`** —— 所有架构 / 命名 / 目录约定都在那
2. **读对应 `docs/<topic>.md`** —— 拿到数据流 / 关键函数
3. **改代码** —— 单文件 / 单职责
4. **跑 `bash build_and_check.sh`** —— 必须 BUILD SUCCEEDED 才能算完
5. **macOS 上手动 ⌘R 跑一遍** —— 关键路径点一下，截图保留

不要做的：
- ❌ 不要 commit `RedbookRefill/Features/Generate/QualityToggle.swift`（已删除）
- ❌ 不要 commit `RedbookRefill/Network/Jimeng*.swift`（已删除）
- ❌ 不要新建并行 LLM 协议——统一走 `chatCompletions()`
- ❌ 不要把 debug log 散落在 print()——统一走 `DebugLog.shared`
- ❌ 不要破坏 Xcode 文件系统同步组（不要手动改 pbxproj 除非必要）

---

## 不在本项目范围

- 单元测试（暂未建）
- CI/CD（`.github/workflows/` 不存在）
- 国际化（zh-CN 单语）
- 应用商店发布（无 fastlane / match 配置）