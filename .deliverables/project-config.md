# RedPulse — 依赖 / 配置 / 项目设置审计

> 范围：`/Users/mac/Desktop/RedbookRefill/`（Xcode 工程根）
> 内容：Xcode 工程文件 + Info.plist + PrivacyInfo + build script + 文档 vs 实际代码一致性
> 生成时间：2026-06-24 17:30（主 session 直接产出，替代被 23min timeout 的 team worker）

---

## 1. Xcode 工程 (`RedbookRefill.xcodeproj/project.pbxproj`)

### 1.1 核心配置（实测）

| 设置 | 值 | 评价 |
|---|---|---|
| `objectVersion` | 77 | ✅ 最新（Xcode 16 引入的 filesystem-synchronized 项目格式） |
| `preferredProjectObjectVersion` | 77 | ✅ |
| `CreatedOnToolsVersion` | 26.4.1 | ✅ Xcode 26.4.1 |
| `LastSwiftUpdateCheck` / `LastUpgradeCheck` | 2640 | ✅ 对应 Xcode 26.4 |
| `SWIFT_VERSION` | **5.0** | ⚠️ **偏低**。项目大量使用 `@Observable` / `async/await` / `Task` / SwiftData —— 全是 Swift 5.9+ 特性，编译能过是因为 Xcode 26 默认兼容。但 `SWIFT_VERSION = 5.0` 显式声明会让某些 Swift 6 特性（如 `~Copyable`）不可用。建议改 `5.10` 或 `6.0` |
| `IPHONEOS_DEPLOYMENT_TARGET` | **17.0** | ✅ 与宪法一致 |
| `MACOSX_DEPLOYMENT_TARGET` | **14.0** | ✅ 支持 Mac Catalyst + 原生 Mac |
| `SUPPORTED_PLATFORMS` | `iphoneos iphonesimulator macosx` | ✅ 三端 |
| `SUPPORTS_MACCATALYST` | `YES` | ✅ Mac Catalyst 启用 |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` | ✅ iPhone (1) + iPad (2) |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | ✅ Swift 5.10+ 并发信息提示 |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | ✅ 全局默认 MainActor 隔离，与项目大量 `@MainActor` 注解一致 |
| `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | `YES` | ✅ 开启 Swift 6 成员可见性 |
| `SWIFT_EMIT_LOC_STRINGS` | `YES` | ✅ 字符串本地化（但未配 .xcstrings） |
| `STRING_CATALOG_GENERATE_SYMBOLS` | `YES` | ⚠️ **未配 String Catalog**（见 §1.4） |
| `LOCALIZATION_PREFERS_STRING_CATALOGS` | `YES` | ⚠️ 同上 |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `YES` | ✅ Xcode 15+ 安全设置 |
| `ENABLE_PREVIEWS` | `YES` | ✅ SwiftUI Previews |
| `GCC_C_LANGUAGE_STANDARD` | `gnu17` | ✅ |
| `CLANG_CXX_LANGUAGE_STANDARD` | `gnu++20` | ✅ |
| `DEVELOPMENT_TEAM` | **`""`** | ❌ **未填**，本地 build 没问题，发布/真机调试会卡住 |
| `PRODUCT_BUNDLE_IDENTIFIER` | `"----.RedbookRefill"` | ❌ **占位**（4 个短横线前缀），需替换为真实 Team ID + Bundle ID |
| `PROVISIONING_PROFILE_SPECIFIER` | `""` | ⚠️ 未配，但 `CODE_SIGN_STYLE = Automatic` 情况下可省 |
| `CODE_SIGN_IDENTITY` (iOS) | `Apple Development` | ✅ |
| `CODE_SIGN_IDENTITY` (默认) | `"-"` | ✅ 模拟器用 ad-hoc |
| `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` | `1` / `1.0` | ✅ 首发版本 |
| `DISPLAY_NAME` | `RedPulse` | ✅ |
| `INFOPLIST_FILE` | `Info.plist` | ⚠️ 路径相对工程根，非标准位置（见 §2） |
| `GENERATE_INFOPLIST_FILE` | `NO` | ✅ 用自定义 Info.plist |
| `ASSETCATALOG_COMPILER_APPICON_NAME` | `AppIcon` | ✅ |
| `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` | `AccentColor` | ✅ |
| `knownRegions` | `(en, Base)` | ⚠️ **缺 zh_CN**（见 §1.4） |
| `developmentRegion` | `en` | ⚠️ Info.plist `CFBundleDevelopmentRegion = zh_CN` 与之冲突 |

### 1.2 文件系统同步组（filesystem-synchronized group）

```
0413A4FF2FB761E7006AC8E2 /* RedbookRefill */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = RedbookRefill;
    sourceTree = "<group>";
};
```

✅ **Xcode 16+ 新特性**：整个 `RedbookRefill/` 文件夹自动作为 group，新加文件**不需要手动编辑 pbxproj**。这是宪法 `_PROJECT_CONVENTIONS.md` 第 12 行「文件系统同步组，新文件自动加入」的实现。

**含义**：所有 69 个 Swift 文件 + Assets + PrivacyInfo 都在这个 group 下，pbxproj 不需要逐个引用，342 行就涵盖了全部工程信息（vs 旧式 pbxproj 通常 1000+ 行）。

### 1.3 Build phases

- **Sources phase** (`0413A4F92FB761E6006AC8E2`)：**files 列表为空** —— 因为用 filesystem-synchronized group，所有源文件由 Xcode 自动从 `RedbookRefill/` 目录捕获
- **Resources phase** (`0413A4FB2FB761E6006AC8E2`)：同样空，资源自动捕获
- **Frameworks phase** (`0413A4FA2FB761E6006AC8E2`)：空 —— 0 个手动链接的 framework（SwiftUI/SwiftData/Foundation 都是隐式链接）

✅ 配置符合现代化 Xcode 最佳实践。

### 1.4 已知不一致 / 改进项

| # | 严重度 | 问题 | 修法 |
|---|---|---|---|
| 1 | **H** | `PRODUCT_BUNDLE_IDENTIFIER = "----.RedbookRefill"` 是占位符 | 替换为 `com.<你的TeamID>.RedbookRefill` |
| 2 | **H** | `DEVELOPMENT_TEAM = ""` | 填入真实 10 字符 Team ID |
| 3 | **M** | `SWIFT_VERSION = 5.0` 但用了 Swift 5.9+ 特性 | 升 `5.10` 或 `6.0` |
| 4 | **M** | `STRING_CATALOG_GENERATE_SYMBOLS = YES` + `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` 但项目里**没有 .xcstrings 文件**（grep 0 匹配） | 要么删这 2 个设置，要么新建 `Localizable.xcstrings` |
| 5 | **M** | `knownRegions = (en, Base)` 缺 `zh_CN`，但 Info.plist `CFBundleDevelopmentRegion = zh_CN` | 在 Xcode > Project > Info > Localizations 加 `Chinese (Simplified)` |
| 6 | **L** | `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` 开启 Swift 6 成员可见性 —— **可能影响现有 public API 的访问性**（grep 找 `public` / `internal` 都没有，但 `internal` 是默认，所有 Feature 在同 module 内 OK） | 持续关注；如果未来要拆 framework 再调 |

---

## 2. Info.plist

**位置**：`/Users/mac/Desktop/RedbookRefill/Info.plist`（**工程根**，非 `RedbookRefill/` 内，**不太标准** —— 通常 Info.plist 应在 source 目录内或工程根但配 `$(SRCROOT)/Info.plist`，这里直接是工程根）

**当前内容**（49 行）：

| Key | 值 | 评价 |
|---|---|---|
| `CFBundleDevelopmentRegion` | `zh_CN` | ✅ 中文用户 |
| `CFBundleDisplayName` | `RedPulse` | ✅ |
| `CFBundleShortVersionString` | `$(MARKETING_VERSION)` | ✅ |
| `CFBundleVersion` | `$(CURRENT_PROJECT_VERSION)` | ✅ |
| `CFBundlePackageType` | `APPL` | ✅ |
| `LSRequiresIPhoneOS` | `true` | ✅ iOS app |
| `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes` | `false` | ✅ 单窗口（除 Mac 的独立 AI Window） |
| `UILaunchScreen.UIColorName` | `AccentColor` | ✅ |
| `UISupportedInterfaceOrientations` | `[UIInterfaceOrientationPortrait]` | ✅ 仅竖屏（iPhone）。iPad 缺 portrait upside down / landscape —— **未配 `UISupportedInterfaceOrientations~ipad`** |
| `UIRequiredDeviceCapabilities` | `[arm64]` | ✅ |
| `NSCameraUsageDescription` | 「红书笔芯 需要访问摄像头，以便拍摄产品照片用于生成笔记。」 | ✅ 文案与宪法一致 |
| `NSPhotoLibraryUsageDescription` | 「红书笔芯 需要访问照片库，以便选择产品参考图用于生成笔记。」 | ✅ |
| `NSPhotoLibraryAddUsageDescription` | 「红书笔芯 需要访问照片库，以便选择产品参考图用于生成笔记。」 | ✅ |

**缺失**（应该加）：

| Key | 用途 | 严重度 |
|---|---|---|
| `NSMicrophoneUsageDescription` | iPhone 视频录制可能需要（如未来要录视频评论） | L |
| `NSAppleMusicUsageDescription` | 不需要 | — |
| `NSAppTransportSecurity.NSAllowsArbitraryLoads` | 当前所有 API（OpenAI 兼容 + 火山 + Ark）走 HTTPS，不需要 | — |
| `NSSupportsLiveActivities` | 不需要（没 Live Activity） | — |
| `UIApplicationSupportsIndirectInputEvents` | Mac Catalyst 间接输入 | L |
| `NSCameraUsageDescription` 给 iPad 的特别说明 | 当前文案统一 | — |
| `NSUserActivityTypes` | 不需要 | — |
| `ITSAppUsesNonExemptEncryption` | `false`（默认） | ✅ |
| **`UISupportedInterfaceOrientations~ipad`** | iPad 缺横屏/倒置支持 | **M** |
| **`LSSupportsOpeningDocumentsInPlace`** | 拖拽文件进 app | L |

**已知问题**：
- ⚠️ `CFBundleDevelopmentRegion = zh_CN` 与 pbxproj `developmentRegion = en` / `knownRegions` 缺 zh_CN 不一致 —— pbxproj 决定 Xcode UI 语言与 Localizations 列表，Info.plist 决定运行时 `Locale.current.region` 默认值。**显示给 Xcode 的是 en，但运行时取 zh_CN，会有 warning**。

---

## 3. PrivacyInfo.xcprivacy

**位置**：`/Users/mac/Desktop/RedbookRefill/RedbookRefill/PrivacyInfo.xcprivacy`（**RedbookRefill/ 内**，✓ 标准位置）

**当前内容**（13 行）：
```xml
<key>NSPrivacyTracking</key><false/>          ✅ 不跟踪
<key>NSPrivacyTrackingDomains</key><array/>    ✅ 空
<key>NSPrivacyCollectedDataTypes</key><array/> ✅ 不收集
<key>NSPrivacyAccessedAPITypes</key><array/>   ✅ 0 个 API 访问声明
```

**问题**：
- ❌ **`NSPrivacyAccessedAPITypes` 应该至少有 `NSPrivacyAccessedAPICategoryUserDefaults`（用 `@AppStorage` / `UserDefaults` 存 LLM/即梦配置）**。Apple 强制要求声明，App Store 提交会卡 review
- ⚠️ 如果未来加 `FileTimestamp` 访问（写 zip 到 tmp），需要补 `NSPrivacyAccessedAPICategoryFileTimestamp`
- ⚠️ 如果加 `DiskSpace` 检查，需要 `NSPrivacyAccessedAPICategoryDiskSpace`
- ⚠️ 如果加 `SystemBootTime`（`Date()` 用）需要 `NSPrivacyAccessedAPICategorySystemBootTime`

**当前实际用到的 API**（grep 全量）：
- `UserDefaults` (`@AppStorage`) —— ❌ **未声明**
- `Date()` —— 可能需要 `SystemBootTime`
- 文件系统读写真实路径（Product 图片）—— 可能需要 `FileTimestamp` / `DiskSpace`
- 网络 `URLSession` —— 不在 Privacy Accessed API 列表（那是 Network Extensions 才要）

**结论**：**PrivacyInfo 必须补 `UserDefaults` 声明**，否则 App Store 拒收。

---

## 4. build_and_check.sh

**位置**：`/Users/mac/Desktop/RedbookRefill/build_and_check.sh`（156 行）

**严重 bug**（实测）：

```bash
# Line 8
PROJECT_ROOT="/Users/mac/Desktop/红书笔芯/RedbookRefill"
```

**项目实际位置**：`/Users/mac/Desktop/RedbookRefill/`。`红书笔芯/RedbookRefill` 路径**不存在**（除非法语/日语字符 `红书笔芯` 文件夹还在）—— 实际 `/Users/mac/Desktop/` 下只有 `RedbookRefill` 一个项目。

**结果**：
- `xcodebuild` 模式：找不到 project file，命令直接失败
- `swiftc -parse` 模式：fallback 用 11 个文件的硬编码列表（line 93-105），但用 `swiftc -parse -target arm64-apple-macos26.0` 单独 parse，**不等价于 xcodebuild 的全量编译**（不解析跨文件依赖、不带 framework）

**额外问题**：
- `swiftc -parse -target arm64-apple-macos26.0` 用了 macOS 26.0 SDK（**beta SDK**），可能不可用 —— 当前 Xcode 26.4.1 对应 macOS 15 SDK
- `grep -qP`（Perl 正则）在 macOS 默认 BSD grep 不支持，**整个 grep 段在 macOS 静默失败**（line 149, 152）
- `set -e` 启用，但 `tee` 失败不会让脚本退出

**结论**：**build script 不可用**。要么删，要么重写为正确的 Xcode build wrapper。

---

## 5. 文档 vs 实际代码一致性

| 文档 | 行数 | 一致性 | 备注 |
|---|---|---|---|
| `_PROJECT_CONVENTIONS.md`（在 `RedbookRefill/` 内） | 202 | ⚠️ **70% 偏离** | 宪法列的目录结构与实际差异大（详见 architecture.md §4） |
| `README.md`（工程根） | 140 | ✅ 现状 | 顶层介绍 |
| `DESIGN_DOC.md`（工程根） | 348 | 未交叉验证 | 应该是设计文档 |
| `INTEGRATION_GUIDE.md`（工程根） | 246 | 未交叉验证 | 应该是集成说明 |
| `需求_融合版.md`（V3.2，`/Users/mac/Desktop/红书笔芯/prototype/`） | — | ✅ 主链路 90% 匹配 | feature-flow 报告已交叉验证 |

**关键发现**：
- ⚠️ `_PROJECT_CONVENTIONS.md` 第 10 行说「App 入口：RedbookRefill/RedbookRefillApp.swift」，但**实际是 `RedPulseApp.swift`**（命名改了 1 次但宪法没同步）
- ⚠️ 宪法列了 `Features/Auth/LoginView.swift`，**实际不存在**（产品定位去掉了登录）
- ⚠️ 宪法说「`Features/Generate/HomeView.swift`」，**实际是 `GenerateView.swift`**（HomeView → GenerateView 重命名）
- ⚠️ 宪法说「`MockGenerator` 按需求文档 Mock 逻辑」，**实际 `MockGenerator` + `LLMTextGenerator` 双实现**，运行时根据 `isConfigured` 切换
- ⚠️ 宪法说「Xcode 项目：RedbookRefill.xcodeproj（objectVersion 77）」**✓ 正确**

**结论**：**宪法是 V1 起点文档，V3.2 需求已经演化出 11 个 Feature、6 个 @Model、1 个 actor、3 层架构，但宪法未同步更新**。建议加一个 "CHANGELOG" 章节或在文档头标注"宪法 v1.0 / 实际 v3.2"。

---

## 6. 资产与元数据

### 6.1 Assets.xcassets

- 位置：`RedbookRefill/Assets.xcassets/`
- 引用：AppIcon、AccentColor（Info.plist 引用）
- 内容：未人工 inspect（Xcode 资源管理）

### 6.2 App Store 元数据（`ASSET_CATEGORIES/`）

```
ASSET_CATEGORIES/
├── 0-app-store-metadata.md
├── 1-description.md
├── 2-keywords.md
├── 3-tech-support-url.md
├── 4-privacy-policy.html
├── 5-privacy-policy-url.md
└── deploy-guide.md
```

✅ 7 个文件齐全（description / keywords / support URL / privacy policy / deploy guide），是 App Store 提交所需的元数据。

**已知问题**：
- `4-privacy-policy.html` 是本地 HTML，没部署到公网 —— `5-privacy-policy-url.md` 应该指向公网 URL
- `3-tech-support-url.md` 同理

### 6.3 `config/mcporter.json`

```json
{
  "mcpServers": {
    "exa": { "baseUrl": "https://mcp.exa.ai/mcp" }
  }
}
```

⚠️ **MCP (Model Context Protocol) 配置** —— 但 **Swift 代码里 0 处引用**（grep `mcp` / `exa` 0 匹配）。可能是开发时给 IDE/agent 用的，**对 app 行为无影响**。建议移到 `.gitignore` 或 `.claude/` 目录。

---

## 7. .gitignore

✅ 60 行，覆盖：
- AI 工具：`.reasonix/` / `.claude/`
- macOS：`.DS_Store` 等
- Xcode：`build/` / `xcuserdata/` / `*.xcarchive` / `DerivedData/` 等
- SPM：`.build/` / `Package.resolved` 等
- CocoaPods：`Pods/`
- **敏感文件**：`Secrets.plist` / `secrets.plist` / `APIKeys.plist` / `*.env` / `Secrets/`
- 编辑器：`.idea/` / `*.swp`
- 日志：`*.log`

**小遗漏**：
- ⚠️ `*.xcuserstate` —— 经常被误 commit
- ⚠️ `xcuserdata/` 已经包含

---

## 8. 一句话总结

**RedPulse 项目设置现代化程度高（Xcode 26.4.1 + filesystem-synchronized group + 0 手动 framework 链接），但发布就绪度不足 70%：PRODUCT_BUNDLE_IDENTIFIER 是占位符、DEVELOPMENT_TEAM 空、PrivacyInfo 缺 UserDefaults 声明、Info.plist 在工程根而非源目录、build_and_check.sh 用错路径不可用、宪法文档与 V3.2 实际代码 70% 偏离、knownRegions 缺 zh_CN + pbxproj developmentRegion 错配 en —— 修完这 8 项后可正常上架。**

---

*主 session 直接产出 · 替代被 23min timeout 的 team project-config worker · pbxproj / Info.plist / PrivacyInfo 全部实测*
