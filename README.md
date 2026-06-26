# RedPulse

> AI 驱动的小红书内容创作工具 — iPhone / iPad / Mac 三端通用

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-purple.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwUI-@Observable-green.svg)](https://developer.apple.com/xcode/swiftui/)

## 简介

RedPulse 是一款面向小红书创作者的桌面 / 移动端 AI 创作工具。在本地优先(Local-First)架构下,帮助你完成从产品库管理、AI 文案生成、AI 配图、AI 短视频到内容预览、发布前优化的完整工作流。

**核心特点**:
- **本地优先**:所有创作数据存储在设备本地(沙箱),卸载即永久删除,开发者无法访问
- **三端通用**:一套代码,iPhone / iPad / Mac 共用,自适应布局
- **AI 全流程**:文案 / 图片 / 视频 / 助手 都在应用内完成
- **零服务器架构**:不运营后端,数据不上传至开发者控制的服务器

## 功能

### ✍️ AI 内容生成
- **文案生成**:基于关键词 + 产品信息,生成小红书风格标题、正文、标签(支持 4 种笔记类型:信息流 / 搜索 / 品牌 / 带货)
- **图片生成**:文生图、图生图、参考图引导(支持多张参考图)
- **视频生成**:5 秒竖屏短视频(9:16),图生视频,可指定最多 2 张参考图
- **AI 助手**:基于多轮对话的笔记优化建议、标题改写、标签扩展

### 📱 内容预览
- **小红书发现页瀑布流**:2 列布局,模拟真实小红书阅读体验
- **笔记详情页**:用户头像、文案、配图、评论区一比一还原
- **手机模拟器**:在 Mac 上以手机外形预览生成效果
- **历史记录**:所有生成结果可浏览、编辑、删除、复制

### 🛠 产品库管理
- 录入产品名称、卖点、目标人群、使用场景
- 生成时自动带入上下文,产出更精准
- 支持配图参考、产品风格图

### 🔍 AI 诊断
- 生成内容的质量评分
- 平台合规风险提示
- 一键应用 AI 优化建议到记录

### 🔌 多 Provider 支持
- **Agnes**(文案 / 图片 / 视频)
- **DeepSeek**(文案)
- **火山引擎方舟 / Doubao Seedance**(视频)
- **OpenAI 兼容 API**(可自定义 endpoint)

## 系统要求

| 平台 | 最低版本 |
|---|---|
| iOS / iPadOS | 17.0+ |
| macOS | 14.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ |

## 项目结构

```
RedbookRefill/
├── RedPulseApp.swift              # 应用入口 + LaunchStage 状态机
├── ContentView.swift              # 主路由容器
├── RootTabView.swift              # 侧边栏 / Tab 切换
├── PrivacyInfo.xcprivacy         # Apple 隐私清单
│
├── DesignSystem/                  # 设计系统
│   ├── DesignTokens.swift         # 颜色 / 字体 / 间距令牌
│   ├── ViewModifiers.swift        # 通用修饰符
│   └── ...
│
├── Features/                      # 功能模块(按业务划分)
│   ├── Generate/                  # 内容生成(分步骤表单)
│   ├── History/                   # 历史记录浏览
│   ├── Library/                   # 产品库 + 素材库
│   ├── Result/                    # 生成结果编辑 + 手机预览
│   ├── Profile/                   # 个人中心 + 设置 + 法律协议
│   ├── Onboarding/                # 4 页功能引导
│   ├── Assistant/                 # AI 助手对话
│   ├── Regen/                     # 跨 view 生命周期的重新生成
│   ├── Inspiration/               # 灵感收集
│   ├── Export/                    # 内容导出
│   └── CoachMark/                 # 引导浮层
│
├── Network/                       # 网络层
│   ├── LLMConfigStore.swift       # API Key / Provider / Model 配置
│   ├── LLMTextGenerator.swift     # LLM 流式文案生成
│   ├── AgnesService.swift         # Agnes 文案 / 图片 / 视频
│   ├── VolcengineVideoService.swift  # 火山方舟视频生成
│   ├── LLMModelListFetcher.swift  # 模型列表拉取
│   ├── MockGenerator.swift        # Mock 数据生成(无 Key 时演示用)
│   └── ...
│
├── Models/                        # SwiftData @Model 数据模型
│   ├── Product.swift              # 产品库
│   ├── GenerationRecord.swift     # 生成记录
│   ├── NoteComment.swift          # 笔记评论(也用于 AI 对话消息)
│   ├── ChatSession.swift          # AI 助手会话
│   ├── InspirationItem.swift      # 灵感条目
│   └── Feedback.swift             # 用户反馈
│
└── Data/                          # 数据访问层
    ├── Repository.swift           # SwiftData 仓库
    └── LocalAssetMigrator.swift   # 历史远程 URL 一次性迁移到本地
```

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/qian147208/RedPulse.git
cd RedPulse
```

### 2. 打开项目

```bash
open RedbookRefill.xcodeproj
```

### 3. 配置 API Key(可选)

应用支持两种使用方式:

- **零配置体验**:首次启动可直接使用,内置默认配置(供演示)
- **配置自己的 Key**:`设置 → API 配置`,选择 Provider 并填入你的 API Key

API Key 仅存储在本地 UserDefaults,**不上传至任何服务器**。

### 4. 运行项目

- iOS:选择 iPhone / iPad 模拟器,`Cmd + R`
- macOS:选择 `My Mac`,`Cmd + R`(需 macOS 14+)

## 首次启动流程

1. **法律协议页**:首次启动需勾选"我已阅读并同意《隐私协议》和《服务条款》"才能继续。协议版本升级时强制重新同意。
2. **功能引导**:4 页教程(AI 生成 / 产品库 / 结果编辑 / 开始创作)
3. **主界面**:进入生成页

完整协议见 [docs/TERMS_AND_PRIVACY.md](docs/TERMS_AND_PRIVACY.md)。

## 数据存储

所有数据存储在设备本地沙箱,**卸载 App 即永久删除**:

- **SwiftData**(SQLite):产品库、生成记录、AI 对话、灵感、反馈
- **沙箱 Documents 目录**:产品配图、下载的视频缓存(`videos/{taskId}.mp4`)
- **UserDefaults**:API Key、Provider / Model 配置、外观设置

不收集任何个人信息,不接入任何分析 / 追踪 / 广告 SDK。
`PrivacyInfo.xcprivacy` 已声明 `NSPrivacyTracking = false`。

## 开发规范

### 命名约定
- 主入口:`RedPulseApp.swift`
- 设计令牌统一在 `DesignSystem/`
- 网络层用 `async/await` 异步
- 状态管理用 `@Observable`(Swift 5.9+)

### 提交规范

```
<type>(<scope>): <subject>

类型: feat / fix / refactor / docs / test / chore / perf / ci
范围: 模块名(可选)
```

## 已知限制

- 视频生成依赖第三方 API,有调用时长和并发限制
- iOS Simulator 无法播放部分视频编码格式,真机体验最佳
- AI 生成内容可能包含事实错误或偏见,发布前请人工审核

## 许可证

本项目采用 MIT 许可证 — 详见 [LICENSE](LICENSE) 文件。

## 联系方式

- 项目仓库:[github.com/qian147208/RedPulse](https://github.com/qian147208/RedPulse)
- 反馈:应用内 `我的 → 反馈`

---

**RedPulse** — 让小红书创作更简单 ✨