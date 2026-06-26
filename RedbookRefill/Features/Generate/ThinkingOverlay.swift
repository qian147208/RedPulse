//
//  ThinkingOverlay.swift
//  灵芯
//
//  文本生成期间的全屏 thinking overlay。
//  - 半透明遮罩 + 居中卡片
//  - sparkles 图标做旋转 + 脉动 + 光晕
//  - "Thinking" 标题带动态省略号
//  - 分步进度：4 个大步骤依次亮起对勾，当前步旋转，未开始步置灰
//

import SwiftUI

struct ThinkingOverlay: View {
    /// 是否显示。绑定到生成中的状态。
    let isActive: Bool
    /// 点击「取消」时的回调；nil 时不显示取消按钮。
    let onCancel: (() -> Void)?
    /// LLM 真实进度（0.0-1.0）。0 表示不显示进度条。
    var progress: Double = 0
    /// LLM 阶段文案（如"撰写正文"），显示在卡片里
    var stage: String = ""
    /// 已收字符数（让用户看到具体进度数字）
    var receivedChars: Int = 0
    /// 目标字符数（分母）
    var targetChars: Int = 1000

    init(
        isActive: Bool,
        onCancel: (() -> Void)? = nil,
        progress: Double = 0,
        stage: String = "",
        receivedChars: Int = 0,
        targetChars: Int = 1000
    ) {
        self.isActive = isActive
        self.onCancel = onCancel
        self.progress = progress
        self.stage = stage
        self.receivedChars = receivedChars
        self.targetChars = targetChars
    }

    /// 分步进度步骤（每步自动推进，约 2.5s 一步）。
    private static let steps: [Step] = [
        Step(label: "分析产品特征…", icon: "magnifyingglass"),
        Step(label: "生成标题…", icon: "textformat.alt"),
        Step(label: "撰写正文…", icon: "doc.text"),
        Step(label: "优化润色…", icon: "sparkles"),
    ]

    struct Step: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
    }

    @State private var dots: String = ""
    @State private var activeStepIndex: Int = -1
    @State private var iconAngle: Double = 0
    @State private var iconScale: CGFloat = 1.0
    @State private var haloOpacity: Double = 0.4
    /// 开始时间，用于显示已用秒数。
    @State private var startedAt: Date = .distantPast
    @State private var elapsedSeconds: Int = 0
    /// 持有 4 个动画 task 的引用 — view 重建时 startAnimations 先取消这些，
    /// 避免上一轮 view 死掉的 task 还占着循环。
    @State private var animTasks: [Task<Void, Never>] = []

    var body: some View {
        ZStack {
            if isActive {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { /* 吞掉点击 */ }

                card
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: isActive)
        // view 出现时如果仍在 active，**主动**重启动画 ——
        // 解决"切到别的 tab 回来，session.isGenerating 一直 true → onChange 不触发
        // → startAnimations 不会被调用 → 动画卡住"的问题
        .onAppear {
            if isActive { startAnimations() }
        }
        .onChange(of: isActive) { _, on in
            if on { startAnimations() } else { stopAnimations() }
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            icon
                .padding(.bottom, 18)

            HStack(spacing: 0) {
                Text("Thinking")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ink)
                Text(dots)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.brand)
                    .frame(width: 24, alignment: .leading)
            }
            .padding(.bottom, 16)

            // 分步进度
            VStack(spacing: 0) {
                ForEach(Array(Self.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step: step, index: index)
                    if index < Self.steps.count - 1 {
                        connector(index: index)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 14)

            // 已用时
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                Text("已用 \(elapsedSeconds)s")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(elapsedSeconds >= 20 ? Color.warning : Color.ink3)

            // 真实进度条（LLM 流式字符数 / 目标字符数）
            if progress > 0 {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        if !stage.isEmpty {
                            Text(stage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.brand)
                        }
                        Spacer()
                        Text("\(receivedChars)/\(targetChars) 字")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.ink3)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.brand)
                            .frame(width: 36, alignment: .trailing)
                    }
                    ProgressView(value: min(progress, 1.0))
                        .progressViewStyle(.linear)
                        .tint(Color.brand)
                }
                .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 16)
            }

            if let onCancel {
                Button {
                    HapticManager.warning()
                    onCancel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("取消生成")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.surface, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.ink2.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 290)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.border, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 12)
    }

    // MARK: - Step Row

    private func stepRow(step: Step, index: Int) -> some View {
        HStack(spacing: 10) {
            // 状态图标
            stepIcon(index: index)

            Text(step.label)
                .font(.system(size: 13, weight: stepWeight(index: index)))
                .foregroundStyle(stepColor(index: index))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }

    /// 步骤间连线：细小渐变线，随进度亮起。
    private func connector(index: Int) -> some View {
        HStack {
            Rectangle()
                .fill(
                    index < activeStepIndex
                        ? Color.success.opacity(0.4)
                        : Color.ink4.opacity(0.2)
                )
                .frame(width: 2, height: 10)
                .cornerRadius(1)
            Spacer()
        }
        .padding(.leading, 9)
    }

    @ViewBuilder
    private func stepIcon(index: Int) -> some View {
        Group {
            if index < activeStepIndex {
                // 已完成 → 绿色对勾
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .symbolEffect(.bounce, value: activeStepIndex)
            } else if index == activeStepIndex {
                // 当前步 → 旋转图标
                Image(systemName: Self.steps[index].icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .rotationEffect(.degrees(index == activeStepIndex ? iconAngle : 0))
            } else {
                // 未开始 → 空心圆
                Image(systemName: "circle")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color.ink4)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func stepColor(index: Int) -> Color {
        if index < activeStepIndex { return Color.success }
        if index == activeStepIndex { return Color.brand }
        return Color.ink4
    }

    private func stepWeight(index: Int) -> Font.Weight {
        index == activeStepIndex ? .semibold : .regular
    }

    // MARK: - Icon

    private var icon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.brand.opacity(0.35), Color.brand.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 100, height: 100)
                .opacity(haloOpacity)
                .blur(radius: 8)

            Circle()
                .fill(Color.brandSoft)
                .frame(width: 64, height: 64)

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.brand)
                .rotationEffect(.degrees(iconAngle))
                .scaleEffect(iconScale)
        }
        .frame(width: 100, height: 100)
    }

    // MARK: - Animations

    private func startAnimations() {
        // 先取消上一轮的所有 task（view 重建 / 重入场景）— 防止旧 task 死循环占着
        animTasks.forEach { $0.cancel() }
        animTasks.removeAll()

        dots = ""
        activeStepIndex = 0
        iconAngle = 0
        iconScale = 1.0
        haloOpacity = 0.4
        startedAt = Date()
        elapsedSeconds = 0

        // elapsed 秒数轮询
        animTasks.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { break }
                let s = Int(Date().timeIntervalSince(startedAt))
                await MainActor.run { elapsedSeconds = s }
            }
        })

        // 图标无限旋转
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            iconAngle = 360
        }
        // 图标脉动
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            iconScale = 1.12
        }
        // 光晕呼吸
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            haloOpacity = 0.9
        }

        // 分步自动推进：每 2.5s 亮起下一步
        animTasks.append(Task {
            var i = 0
            while !Task.isCancelled && i < Self.steps.count {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled { break }
                i += 1
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        activeStepIndex = min(i, Self.steps.count - 1)
                    }
                }
            }
        })

        // dots 三点循环
        animTasks.append(Task {
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { break }
                n = (n + 1) % 4
                await MainActor.run { dots = String(repeating: ".", count: n) }
            }
        })
    }

    private func stopAnimations() {
        // 取消所有 task
        animTasks.forEach { $0.cancel() }
        animTasks.removeAll()
        dots = ""
        activeStepIndex = -1
    }
}
