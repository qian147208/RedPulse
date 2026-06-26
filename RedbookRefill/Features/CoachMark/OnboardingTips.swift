//
//  OnboardingTips.swift
//  灵芯
//
//  用 SwiftUI 标准 .popover(isPresented:) 自管首次引导（不用 TipKit）。
//
//  为什么不用 TipKit：
//  - TipKit 的 popoverTip(_:isPresented:) 要 iOS 26+，popoverTip 强制自动模式
//  - TipKit 的 statusUpdates 跨 tip instance 不同步，无法严格顺序推进
//  - iOS 17 simulator 上 .task 监听 statusUpdates 经常收不到 .invalidated 信号
//
//  采用 SwiftUI popover + 自定义 view 完全控制：
//  - 5 个 step 各自独立 isPresented state
//  - 用户点"知道了"按钮 → dismiss popover + currentStep += 1
//  - 下一个 step 的 isPresented 自动变 true（onChange 触发）
//
//  流程：
//  1. Generate 页：选产品 → 选广告类型 → 写关键词 → 选风格 → 点生成按钮
//  2. Result 页：  生成配图 → 生成视频
//

import SwiftUI
import TipKit  // 保留 import，给业务代码用 Tip 类型仍然方便（比如后续扩展）

// MARK: - Generate 流程的 5 个 Tip 定义（用作步骤数据，不直接走 popoverTip）
//
// 注：保留 Tip struct 是为了结构化引导步骤的数据（title/message/icon），
// 但**不再用 popoverTip 渲染**，而是把数据塞进 OnboardingPopover 自定义 view，
// 用 SwiftUI .popover(isPresented:) 完全控制显示。

struct ProductSelectTip: Tip {
    var title: Text { Text("选你的产品") }
    var message: Text {
        Text("从这里挑一个之前录入的产品，或点 + 新建。所有 AI 生成都会围绕这个产品的卖点展开")
    }
    var image: Image? { Image(systemName: "square.grid.2x2.fill") }
}

struct AdTypeTip: Tip {
    var title: Text { Text("选笔记类型") }
    var message: Text {
        Text("信息流/搜索/品牌/带货 4 种风格，AI 会按你的目标调整标题和正文语气")
    }
    var image: Image? { Image(systemName: "rectangle.3.group.fill") }
}

struct KeywordTip: Tip {
    var title: Text { Text("写关键词") }
    var message: Text {
        Text("可以自己写，也可以从 AI 推荐的热门词里挑。选中的词会变成标题和正文的核心")
    }
    var image: Image? { Image(systemName: "text.magnifyingglass") }
}

struct StyleTip: Tip {
    var title: Text { Text("选写作风格") }
    var message: Text {
        Text("测评向 / 干货风 / 种草向，AI 按风格生成匹配的语气和节奏")
    }
    var image: Image? { Image(systemName: "paintpalette.fill") }
}

struct GenerateButtonTip: Tip {
    var title: Text { Text("一键生成") }
    var message: Text {
        Text("信息填好后点这里，AI 一次性给你标题、正文、标签。下一步教你怎么生成配图和视频")
    }
    var image: Image? { Image(systemName: "wand.and.stars") }
}

struct GenerateImageTip: Tip {
    var title: Text { Text("生成小红书封面") }
    var message: Text {
        Text("切到「配图」标签，点按钮，AI 按笔记内容生成 1-9 张 3:4 竖图。会自动用上你的产品图作参考")
    }
    var image: Image? { Image(systemName: "photo.on.rectangle.angled") }
}

struct GenerateVideoTip: Tip {
    var title: Text { Text("生成笔记视频") }
    var message: Text {
        Text("有了配图后切到「视频」标签，一键生成 5 秒短视频脚本 + 画面")
    }
    var image: Image? { Image(systemName: "video.fill") }
}

// MARK: - TipGroup（iOS 18+，iOS 17 不支持；这里留个标记，将来升 iOS 18 时再用）
//
// 注意：TipGroup 是 iOS 18+ 才有的 API，我们 deployment target 是 iOS 17，
// 所以这里不直接用 TipGroup。iOS 17 下靠 TipKit 自带的"关掉当前 → 自动显示下一个
// 没读过的 tip"机制就能实现顺序展示（每个 .popoverTip 挂到对应 view 上）。
//
// struct GenerateOnboarding: TipGroup {
//     static let tips: [any Tip.Type] = [
//         ProductSelectTip.self, AdTypeTip.self, KeywordTip.self,
//         StyleTip.self, GenerateButtonTip.self
//     ]
// }
// struct ResultOnboarding: TipGroup {
//     static let tips: [any Tip.Type] = [GenerateImageTip.self, GenerateVideoTip.self]
// }

// MARK: - 自定义引导气泡（SwiftUI popover + 自管，替代 TipKit popoverTip）

/// 用 SwiftUI .popover(isPresented:) 自管的引导气泡：
/// - icon + title + message + 「知道了」按钮
/// - onDismiss: 用户点按钮 → 父 view 自己推进 step + 关 popover
/// - 完全脱离 TipKit，行为可预测
struct OnboardingPopover: View {
    let title: String
    let message: String
    let icon: String
    let buttonText: String  // 默认 "知道了"
    let onDismiss: () -> Void

    init(
        title: String,
        message: String,
        icon: String,
        buttonText: String = "知道了",
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.buttonText = buttonText
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 36, height: 36)
                    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Text(buttonText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.brand.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}

// MARK: - 保留 BrandTipViewStyle 以备扩展（当前未使用，因为改用 SwiftUI popover 自管）

struct BrandTipViewStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let image = configuration.image {
                    image
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 32, height: 32)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 4) {
                    configuration.title
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink)
                    configuration.message
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.brand.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 6)
    }
}