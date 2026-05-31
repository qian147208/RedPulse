# 红书笔芯 (RedbookRefill)

> AI 驱动的小红书笔记生成工具，采用 Apple Liquid Glass 设计语言

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-green.svg)](https://developer.apple.com/xcode/swiftui/)

## 项目简介

红书笔芯是一款 iOS 应用，帮助用户快速生成小红书风格的笔记内容。通过 AI 技术，用户可以：

- 🎨 一键生成小红书风格的图文笔记
- ✍️ 智能文案撰写与优化
- 📸 AI 图片生成与编辑
- 📚 管理和复用历史生成内容

## 技术栈

| 技术 | 说明 |
|------|------|
| **SwiftUI** | 声明式 UI 框架，采用 Liquid Glass 设计语言 |
| **SwiftData** | 本地数据持久化（替代 CoreData） |
| **@Observable** | 响应式状态管理（Swift 5.9+） |
| **Swift Concurrency** | async/await 异步编程 |

## 系统要求

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## 项目结构

```
RedbookRefill/
├── RedPulseApp.swift          # 应用入口
├── ContentView.swift          # 路由根容器
├── RootTabView.swift          # 主 Tab 视图
├── DesignSystem/              # 设计系统
│   ├── DesignTokens.swift     # 设计令牌（颜色、字体、间距）
│   ├── ViewModifiers.swift    # 视图修饰符
│   ├── FlowLayout.swift       # 流式布局
│   └── HapticManager.swift    # 触觉反馈管理
├── Features/                  # 功能模块
│   ├── Generate/              # 内容生成
│   ├── History/               # 历史记录
│   ├── Library/               # 素材库
│   ├── Profile/               # 个人中心
│   └── Auth/                  # 认证模块
├── Models/                    # 数据模型
├── Network/                   # 网络层
│   ├── APIClient.swift        # API 客户端
│   ├── LLMTextGenerator.swift # LLM 文本生成
│   └── JimengService.swift    # 即梦图片生成服务
└── Data/                      # 数据层
    ├── Repository.swift       # 数据仓库
    └── AuthStore.swift        # 认证状态存储
```

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/yourusername/RedbookRefill.git
cd RedbookRefill
```

### 2. 打开项目

```bash
open RedbookRefill.xcodeproj
```

### 3. 配置 API 密钥

在 `Info.plist` 中配置所需的 API 密钥：

```xml
<key>LLM_API_KEY</key>
<string>your_llm_api_key</string>
<key>JIMENG_API_KEY</key>
<string>your_jimeng_api_key</string>
```

### 4. 运行项目

在 Xcode 中选择目标设备或模拟器，按 `Cmd + R` 运行。

## 功能特性

### 内容生成
- 支持多种小红书笔记风格
- AI 智能文案生成
- 一键生成配图

### Liquid Glass 设计
- 遵循 Apple 最新设计规范
- 流体动画与交互
- 自适应深色/浅色模式

### 离线支持
- 本地数据持久化
- 历史记录离线查看
- 草稿自动保存

## 开发规范

### 代码风格
- 使用 `@Observable` 宏替代 `ObservableObject`
- 优先使用 Swift Concurrency（async/await）
- 遵循 SwiftUI 声明式编程范式

### 提交规范

```
<type>: <description>

类型：feat, fix, refactor, docs, test, chore, perf, ci
```

## 相关文档

- [设计文档](DESIGN_DOC.md) - UI 重构设计说明书
- [集成指南](INTEGRATION_GUIDE.md) - API 集成说明

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 联系方式

如有问题或建议，请通过以下方式联系：

- 提交 [Issue](https://github.com/yourusername/RedbookRefill/issues)
- 发送邮件至 your.email@example.com

---

**红书笔芯** - 让小红书创作更简单 ✨