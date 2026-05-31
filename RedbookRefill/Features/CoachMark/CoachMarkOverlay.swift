//
//  CoachMarkOverlay.swift
//  RedPulse
//
//  聚光灯式操作引导：半透明遮罩 + 挖孔高亮 + 文字说明卡片。
//  GenerateView 用 1 步（生成按钮），ResultView 用 2 步（配图 + 视频）。
//

import SwiftUI

// MARK: - Step definition

struct CoachMarkStep {
    let id: String          // 对应 coachMarkTarget 的 id
    let title: String
    let message: String
}

// MARK: - Manager

@Observable
final class CoachMarkManager {
    var isActive = false
    var currentStep = 0
    var steps: [CoachMarkStep] = []
    var hasShownGenerate = false
    var hasShownResult = false

    /// 目标 view 的 frame（由 preference key 写入）
    var targetFrames: CoachMarkFrameMap = [:]

    var currentStepDef: CoachMarkStep? {
        guard currentStep >= 0 && currentStep < steps.count else { return nil }
        return steps[currentStep]
    }

    var isLastStep: Bool {
        currentStep >= steps.count - 1
    }

    func start(steps: [CoachMarkStep]) {
        self.steps = steps
        self.currentStep = 0
        self.isActive = true
    }

    func next() {
        if currentStep < steps.count - 1 {
            currentStep += 1
        } else {
            finish()
        }
    }

    func skip() {
        finish()
    }

    func finish() {
        isActive = false
        currentStep = 0
        steps = []
        targetFrames = [:]
    }
}

// MARK: - Preference key for target frames

typealias CoachMarkFrameMap = [String: Anchor<CGRect>]

struct CoachMarkTargetKey: PreferenceKey {
    static var defaultValue: CoachMarkFrameMap = [:]

    static func reduce(value: inout CoachMarkFrameMap,
                       nextValue: () -> CoachMarkFrameMap) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - View modifier to mark a target

struct CoachMarkTargetModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content.anchorPreference(key: CoachMarkTargetKey.self, value: .bounds) {
            [id: $0]
        }
    }
}

extension View {
    func coachMarkTarget(_ id: String) -> some View {
        modifier(CoachMarkTargetModifier(id: id))
    }
}

// MARK: - Overlay

struct CoachMarkOverlay: View {
    @Environment(CoachMarkManager.self) private var manager

    var body: some View {
        if manager.isActive, let step = manager.currentStepDef {
            GeometryReader { proxy in
                if let anchor = manager.targetFrames[step.id] {
                    let frame = proxy[anchor]
                    ZStack {
                        // 半透明遮罩 + 挖孔
                        spotlightMask(targetFrame: frame)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    manager.next()
                                }
                            }

                        // 引导卡片
                        coachCard(step: step, targetFrame: frame, proxy: proxy)
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: manager.currentStep)
                } else {
                    // 目标 frame 尚未就绪（ScrollView 还没滚动到位），
                    // 先显示遮罩 + 卡片居中，避免空白
                    Color.black.opacity(0.01)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                manager.next()
                            }
                        }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(true)
        }
    }

    // MARK: - Spotlight mask (遮罩 + 挖孔)

    private func spotlightMask(targetFrame: CGRect) -> some View {
        let padding: CGFloat = 8
        let cornerRadius: CGFloat = 14
        let expanded = targetFrame.insetBy(dx: -padding, dy: -padding)

        return Rectangle()
            .fill(.black.opacity(0.65))
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .frame(width: expanded.width, height: expanded.height)
                            .position(x: expanded.midX, y: expanded.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            )
            .overlay(
                // 聚光灯边框
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: expanded.width, height: expanded.height)
                    .position(x: expanded.midX, y: expanded.midY)
            )
    }

    // MARK: - Coach card (引导卡片)

    @ViewBuilder
    private func coachCard(step: CoachMarkStep, targetFrame: CGRect, proxy: GeometryProxy) -> some View {
        let screenHeight = proxy.size.height
        let targetMidY = targetFrame.midY
        let cardAboveTarget = targetMidY > screenHeight * 0.55

        let cardWidth: CGFloat = min(proxy.size.width - 40, 340)
        let padding: CGFloat = 12
        let expanded = targetFrame.insetBy(dx: -padding, dy: -padding)

        let cardY: CGFloat = cardAboveTarget
            ? expanded.minY - 90   // 目标在下半屏 → 卡片在目标上方
            : expanded.maxY + 90   // 目标在上半屏 → 卡片在目标下方

        VStack(spacing: 0) {
            // 步骤指示圆点
            HStack(spacing: 8) {
                ForEach(0..<manager.steps.count, id: \.self) { i in
                    let isCurrent = i == manager.currentStep
                    Circle()
                        .fill(isCurrent ? Color.brand : Color.white.opacity(0.4))
                        .frame(width: isCurrent ? 10 : 6, height: isCurrent ? 10 : 6)
                        .animation(.easeOut(duration: 0.2), value: manager.currentStep)
                }
            }
            .padding(.bottom, 12)

            // 标题
            Text(step.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.ink)
                .padding(.bottom, 8)

            // 说明
            Text(step.message)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            // 按钮
            HStack(spacing: 12) {
                if !manager.isLastStep {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            manager.skip()
                        }
                    } label: {
                        Text("跳过")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ink3)
                            .frame(height: 40)
                            .padding(.horizontal, 20)
                            .background(Color.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        manager.next()
                    }
                } label: {
                    Text(manager.isLastStep ? "知道了" : "下一步")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 40)
                        .padding(.horizontal, 24)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: cardWidth)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
        .position(x: proxy.size.width / 2, y: cardY)
    }
}

// MARK: - Preset steps

extension CoachMarkStep {
    /// GenerateView 引导步骤
    static let generateSteps: [CoachMarkStep] = [
        CoachMarkStep(
            id: "gen_product_select",
            title: "选择产品",
            message: "从产品库中选择要推广的产品，或直接输入产品名称和卖点"
        ),
        CoachMarkStep(
            id: "gen_ad_type",
            title: "选择广告类型",
            message: "根据推广目标选择信息流、搜索、品牌或带货笔记，AI 会调整文案风格"
        ),
        CoachMarkStep(
            id: "gen_keyword",
            title: "输入关键词",
            message: "填写产品关键词，可从下方热门词中选择。AI 会围绕这些词展开创作"
        ),
        CoachMarkStep(
            id: "gen_style",
            title: "选择风格",
            message: "选择测评向、干货风等写作风格，也可让 AI 智能推荐匹配的风格"
        ),
        CoachMarkStep(
            id: "generate_button",
            title: "一键生成",
            message: "所有信息填好后，点击这里让 AI 生成完整的小红书笔记"
        )
    ]

    /// ResultView 引导步骤
    static let resultSteps: [CoachMarkStep] = [
        CoachMarkStep(
            id: "gen_image",
            title: "第二步：生成配图",
            message: "文案生成好了！切换到「AI 配图」标签，点击按钮为笔记生成封面图"
        ),
        CoachMarkStep(
            id: "gen_video",
            title: "第三步：生成视频",
            message: "有了配图后，切换到「AI 视频」标签，一键生成笔记短视频"
        )
    ]
}
