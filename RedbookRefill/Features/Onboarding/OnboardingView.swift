//
//  OnboardingView.swift
//  RedPulse
//
//  新手引导：4 页 — AI 生成 / 产品库 / 结果编辑 / 开始创作。
//

import SwiftUI

struct OnboardingView: View {
    /// P1:新增 onFinish 回调,让 RedPulseApp 控制关闭,
    /// 不再依赖 @Environment(\.dismiss)(后者只在 sheet 上下文有效)
    var onFinish: () -> Void = {}
    @AppStorage("has_seen_onboarding") private var hasSeenOnboarding: Bool = false
    @State private var currentPage: Int = 0
    @State private var dontShowAgain: Bool = false

    private let pages: [OnboardPage] = [
        OnboardPage(
            icon: "sparkles",
            iconBg: Color.brand,
            title: "AI 写小红书笔记",
            subtitle: "选产品 → 写关键词 → 选风格，\n一键生成标题、正文、标签、配图建议。",
            hint: "支持 4 种笔记类型：信息流 / 搜索 / 品牌 / 带货"
        ),
        OnboardPage(
            icon: "square.grid.2x2",
            iconBg: Color.brand,
            title: "产品库管理",
            subtitle: "录入产品名称、卖点、目标人群，\n生成时自动带入上下文，笔记更精准。",
            hint: nil
        ),
        OnboardPage(
            icon: "wand.and.stars",
            iconBg: Color.suggestionBlue,
            title: "结果页随心编辑",
            subtitle: "标题、正文、标签可单独重生成，\n支持 AI 配图、视频脚本、手机预览。",
            hint: "长按文本可选中局部重写"
        ),
        OnboardPage(
            icon: "checkmark.seal",
            iconBg: Color.success,
            title: "开始创作",
            subtitle: "历史记录自动保存，随手复制发布。\niPhone / iPad / Mac 三端通用。",
            hint: nil
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, item in
                    pageContent(item)
                        .tag(idx)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.lg)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .gesture(swipeGesture)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            dotsIndicator
                .padding(.top, Spacing.md)

            controls
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            dontShowAgainRow
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 540, minHeight: 600, idealHeight: 660)
        #endif
        .background(Color.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("快速上手")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)
            Spacer()
            Button("跳过") { finishOnboarding() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
    }

    // MARK: - Page

    private func pageContent(_ item: OnboardPage) -> some View {
        let w = ScreenMetrics.shared.width
        let iconOuter: CGFloat = w <= 375 ? 160 : w < 430 ? 180 : 200
        let iconInner: CGFloat = w <= 375 ? 112 : w < 430 ? 128 : 140
        let iconFont: CGFloat = w <= 375 ? 48 : w < 430 ? 56 : 64
        let titleFont: CGFloat = Adaptive.heroFontSize - 2

        return VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(item.iconBg.opacity(0.12))
                    .frame(width: iconOuter, height: iconOuter)
                Circle()
                    .fill(item.iconBg.opacity(0.20))
                    .frame(width: iconInner, height: iconInner)
                Image(systemName: item.icon)
                    .font(.system(size: iconFont, weight: .semibold))
                    .foregroundStyle(item.iconBg)
                    .symbolRenderingMode(.hierarchical)
                    .modifier(BounceEffectIfAvailable())
            }
            .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                Text(item.title)
                    .font(.system(size: titleFont, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)

                Text(item.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)

                if let hint = item.hint {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brand)
                        Text(hint)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ink3)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dots

    private var dotsIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == currentPage ? Color.brand : Color.ink3.opacity(0.25))
                    .frame(width: i == currentPage ? 22 : 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: currentPage)
                    .onTapGesture { withAnimation { currentPage = i } }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Spacing.md) {
            Button {
                withAnimation { currentPage = max(0, currentPage - 1) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上一页")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(currentPage == 0 ? Color.ink4 : Color.ink2)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(currentPage == 0)

            if currentPage < pages.count - 1 {
                Button {
                    withAnimation { currentPage = min(pages.count - 1, currentPage + 1) }
                } label: {
                    HStack(spacing: 4) {
                        Text("下一页")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Color.brand)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.15), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                    )
                    .shadow(color: Color.brand.opacity(0.25), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            } else {
                Button { finishOnboarding() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("开始使用")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Color.brand)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.15), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                    )
                    .shadow(color: Color.brand.opacity(0.25), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - "Don't show again"

    private var dontShowAgainRow: some View {
        Button {
            dontShowAgain.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(dontShowAgain ? Color.brand : Color.ink3)
                Text("不再提醒")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink2)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Swipe

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                if dx < -60, currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else if dx > 60, currentPage > 0 {
                    withAnimation { currentPage -= 1 }
                }
            }
    }

    private func finishOnboarding() {
        // 总是标记为已看过：用户点"开始使用"或"跳过"就代表这次引导结束。
        // "不再提醒"仅作为 UI 提示保留，不参与 flag 逻辑（避免修又走完又弹的老 bug）。
        hasSeenOnboarding = true
        onFinish()
    }
}

/// macOS 15.0+ / iOS 18.0+ 才支持 BounceSymbolEffect.IndefiniteSymbolEffect conformance
/// （BounceSymbolEffect 本身 iOS 17+ 可用，但用作 indefinite effect 在 macOS 上需 15.0+、iOS 上需 18.0+）。
/// Swift 6 模式下，缺这层守卫会变成编译错误。
private struct BounceEffectIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.symbolEffect(.bounce)
        } else {
            content
        }
        #else
        if #available(iOS 18.0, *) {
            content.symbolEffect(.bounce)
        } else {
            content
        }
        #endif
    }
}

private struct OnboardPage {
    let icon: String
    let iconBg: Color
    let title: String
    let subtitle: String
    let hint: String?
}
