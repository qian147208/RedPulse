# RedPulse (RedbookRefill) — 三平台构建验证报告

**验证时间**：2026-06-24 14:03–14:05 (Asia/Shanghai)
**Xcode 版本**：26.4.1 (Build 17E202)
**目标设备**：
- macOS — `generic/platform=macOS`
- iPhone — `platform=iOS Simulator,name=iPhone 17 Pro` (UDID: AB771032-287D-435C-B578-81CC4BAA4D86)
- iPad — `platform=iOS Simulator,name=iPad Pro 13-inch (M5)` (UDID: E8F10BD8-A0A7-48A4-8116-314D54B85A7B)

**项目根**：`/Users/mac/Desktop/RedbookRefill/`
**项目文件**：`RedbookRefill.xcodeproj`
**Scheme**：`RedbookRefill`
**Configuration**：`Debug`
**签名**：`CODE_SIGNING_ALLOWED=NO`（跳过代码签名）

原始日志保留在 `/Users/mac/Desktop/RedbookRefill/.deliverables/build_<platform>.log`。

---

## 三平台构建状态总览

| 平台 | 状态 | 耗时 | 错误数 | 警告数（去重） |
|---|---|---|---|---|
| macOS desktop | ✅ BUILD SUCCEEDED | 31 s | 0 | 11 |
| iOS Simulator (iPhone 17 Pro) | ❌ BUILD FAILED | 10 s | 4 | 5 |
| iOS Simulator (iPad Pro 13-inch M5) | ❌ BUILD FAILED | 13 s | 4 | 4 |

---

## 各平台 error 清单

### macOS desktop

**无 error。** Build 全程无 Swift 编译错误，最终 `** BUILD SUCCEEDED **`。

### iOS Simulator (iPhone 17 Pro)

```
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultRegenHelpers.swift:87:26: error: cannot find 'PHAssetCreationRequest' in scope
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultRegenHelpers.swift:88:39: error: cannot infer contextual base in reference to member 'video'
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultRegenHelpers.swift:88:67: error: 'nil' requires a contextual type
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultView.swift:272:17: error: cannot find 'generatedRecord' in scope
```

报错源码上下文：

`ResultRegenHelpers.swift:86-89`
```swift
#if canImport(UIKit) && !os(macOS)
let assets = PHAssetCreationRequest.forAsset()
assets.addResource(with: .video, data: data, options: nil)
#endif
```
> 注释：Photos.framework 中正确的 API 是 `PHAssetChangeRequest.creationRequestForAsset(from:)`，当前代码把类名写错成了 `PHAssetCreationRequest`，因此在 iOS 路径下 `#if` 分支打开时无法解析。

`ResultView.swift:270-273`
```swift
#if os(iOS)
Button {
    generatedRecord = nil
} label: {
```
> 注释：第 272 行引用了 `generatedRecord`，但当前类型 / 视图上下文中找不到该符号（很可能缺失 `@State` 声明或属性绑定）。

### iOS Simulator (iPad Pro 13-inch M5)

error 与 iPhone **完全相同**（同一份 SwiftCompile 任务失败，因为代码是 iOS 共享的）：

```
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultRegenHelpers.swift:87:26: error: cannot find 'PHAssetCreationRequest' in scope
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultRegenHelpers.swift:88:39: error: cannot infer contextual base in reference to member 'video'
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultRegenHelpers.swift:88:67: error: 'nil' requires a contextual type
/Users/mac/Desktop/RedbookRefill/RedbookRefill/Features/Result/ResultView.swift:272:17: error: cannot find 'generatedRecord' in scope
```

---

## 各平台 warning 清单（合并去重，标注出现平台）

| 文件:行 | 警告 | 出现平台 |
|---|---|---|
| `Features/Export/AssetPackager.swift:211:29` | main actor-isolated static method 'safeURL(from:)' cannot be called from outside of the actor; this is an error in the Swift 6 language mode | macOS |
| `Features/Export/AssetPackager.swift:242:29` | main actor-isolated static method 'safeURL(from:)' cannot be called from outside of the actor; this is an error in the Swift 6 language mode | macOS |
| `Features/Onboarding/OnboardingView.swift:124:22` | conformance of 'BounceSymbolEffect' to 'IndefiniteSymbolEffect' is only available in macOS 15.0 / iOS 18.0 or newer; this is an error in the Swift 6 language mode | macOS, iPad |
| `Features/Result/ResultEditorPanels.swift:66:13` | initialization of immutable value 'newRecord' was never used; consider replacing with assignment to '_' or removing it | macOS, iPhone, iPad |
| `Features/Result/ResultRegenHelpers.swift:61:28` | no 'async' operations occur within 'await' expression | macOS, iPhone, iPad |
| `Features/Result/ResultRegenHelpers.swift:81:28` | no 'async' operations occur within 'await' expression | macOS, iPhone, iPad |
| `Features/Result/ResultView.swift:287:46` | left side of nil coalescing operator '??' has non-optional type 'String', so the right side is never used | macOS |
| `Features/SelectionToolbar/FloatingToolbarPanel.swift:133:34` | main actor-isolated property 'panel' can not be referenced from a Sendable closure | macOS |
| `Features/SelectionToolbar/FloatingToolbarPanel.swift:137:18` | call to main actor-isolated instance method 'updatePosition(to:)' in a synchronous nonisolated context | macOS |
| `Models/NoteComment.swift:81:55` | main actor-isolated conformance of 'NoteCommentSuggestion' to 'Encodable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode | macOS, iPhone |
| `Models/NoteComment.swift:94:35` | main actor-isolated conformance of 'NoteCommentSuggestion' to 'Decodable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode | macOS, iPhone |
| `appintentsmetadataprocessor` | warning: Metadata extraction skipped. No AppIntents.framework dependency found. | macOS |

> 注：macOS 平台下 `AssetPackager.swift:211` 与 `:242` 这条 warning 在日志里重复出现多次（每个 SwiftCompile 任务各报一次），实际 unique 只此一处。

---

## 已知非阻塞警告

下面这些 warning **不阻塞当前 Swift 5 模式构建**，但在 Swift 6 严格并发模式下会变成 error，是后续升级到 Swift 6 时需要修的点：

1. **`AppIntents metadata extraction skipped`** — `appintentsmetadataprocessor` 在 macOS 链接产物中提示"No AppIntents.framework dependency found"，因为项目尚未引入 AppIntents。这是 Xcode 26 默认会跑的步骤，纯 informational，没有 AppShortcuts 也属正常。
2. **Main-actor 隔离警告**（`AssetPackager.swift:211:29` / `:242:29`、`FloatingToolbarPanel.swift:133:34` / `:137:18`、`NoteComment.swift:81:55` / `:94:35`）— 当前 Swift 5 模式下只是 warning，迁移到 Swift 6 时需要在调用方加 `await MainActor.run { ... }` 或为被调方法去掉 `@MainActor` 标注。
3. **`BounceSymbolEffect` API availability** — `OnboardingView.swift:124` 用了 `BounceSymbolEffect` 的 `IndefiniteSymbolEffect` conformance，该 conformance 仅在 macOS 15.0 / iOS 18.0+ 提供。当前项目 deployment target 是 14.0/iOS 17，所以是 warning；升级 deployment target 到 15.0/iOS 18 后即消失。
4. **未使用变量 / 冗余 nil-coalesce / 冗余 await** — `ResultEditorPanels.swift:66`、`ResultView.swift:287`、`ResultRegenHelpers.swift:61`、`:81` 都是无害的代码卫生 warning，不影响产物。

---

## 结论：当前 main 分支能否开箱即用 ⌘B？

> **❌ FAIL — iOS / iPadOS 不能开箱即用。**

**原因**：
- **macOS desktop**：✅ `xcodebuild -scheme RedbookRefill -destination 'generic/platform=macOS' -configuration Debug` **成功**，31 秒。
- **iOS Simulator (iPhone / iPad)**：❌ `xcodebuild` 在 Swift 编译阶段直接失败，4 个 error，全部位于 `Features/Result/` 目录：
  - `ResultRegenHelpers.swift:87-88` — Photos.framework API 类名拼错（`PHAssetCreationRequest` → 应为 `PHAssetChangeRequest`），导致 iOS 路径下 `#if canImport(UIKit) && !os(macOS)` 分支打开时整段报错并 cascade 出 `cannot infer contextual base` 与 `'nil' requires a contextual type`。
  - `ResultView.swift:272` — `#if os(iOS)` 分支里使用了未声明的 `generatedRecord` 符号。
- 这两个 bug 都用 `#if` 包在 iOS-only 路径里，所以 macOS 编译时绕开了；一旦切到 iPhone / iPad scheme 编译就立刻暴露。

**结论**：当前 main 分支**只能**在 macOS 上 ⌘B 通过；任何 iOS / iPadOS device 编译（包括模拟器）都会失败。修复后 ⌘B 才能在三平台开箱即用。

修复建议（仅供参考，不在本次任务范围）：
1. `ResultRegenHelpers.swift:87` 把 `PHAssetCreationRequest.forAsset()` 改成 `PHAssetChangeRequest.creationRequestForAsset()`（注意 `PHAssetChangeRequest.creationRequestForAsset()` 是 `PHAssetCollectionChangeRequest` 块内的方法，需在 `performChanges` 闭包中调用，并把 `assets.addResource` 改成 `request.addResource`）。
2. `ResultView.swift:272` 给 `ResultView` 增加 `@State private var generatedRecord: SomeType?`（类型取决于上游定义），或在 `topToolbar` 里改用已存在的状态变量。

---

## 附录：完整原始日志

| 平台 | 日志路径 | 行数 | 大小 |
|---|---|---|---|
| macOS desktop | `/Users/mac/Desktop/RedbookRefill/.deliverables/build_macos.log` | 1202 | 170 KB |
| iOS iPhone | `/Users/mac/Desktop/RedbookRefill/.deliverables/build_iphone.log` | 458 | 75 KB |
| iOS iPad | `/Users/mac/Desktop/RedbookRefill/.deliverables/build_ipad.log` | 318 | 50 KB |