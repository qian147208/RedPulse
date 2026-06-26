//
//  GenerateView.swift
//  灵芯
//
//  生成笔记主页面 — 四步表单：产品 → 广告类型 → 关键词 → 风格
//  拆分后作为 orchestrator，实际 UI 子组件在 GenerateStepSections/GenerateStepStep4Hint/GenerateViewHelpers 中。
//

import SwiftUI
import SwiftData

struct GenerateView: View {
    @Environment(Repository.self) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]

    @AppStorage("show_step3_tip") private var showStep3Tip = true
    @AppStorage("show_step4_tip") private var showStep4Tip = true

    // MARK: - 引导状态（SwiftUI popover 自管，iOS 17 严格顺序）
    // 5 个独立 Bool state + 1 个 currentStep 跟踪进度
    // 点 "知道了" 按钮 → dismiss 当前 popover + 推进 step → onChange 触发下一个 popover
    @AppStorage("generate_onboarding_step") private var currentStep: Int = -1
    @State private var showOnboardStep1: Bool = false
    @State private var showOnboardStep2: Bool = false
    @State private var showOnboardStep3: Bool = false
    @State private var showOnboardStep4: Bool = false
    @State private var showOnboardStep5: Bool = false

    // MARK: - 全部 state 移到 session（跨 view 持久 — 切 tab 不丢）
    @Environment(GenerationSession.self) private var session

    /// 文本模型配置齐全时走真实 LLM，否则回退到 Mock。
    private var generator: GeneratorProtocol {
        LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()
    }

    var body: some View {
        if let record = session.generatedRecord {
            ResultView(record: record)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            session.clearResult()
                        } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                    }
                }
        } else {
            generationFormBody
        }
    }

    // MARK: - Layouts

    private var formCard: some View {
        @Bindable var bindableSession = session
        return VStack(spacing: Spacing.lg) {
            GenerateStepStep1Product(
                selectedProduct: $bindableSession.selectedProduct,
                keyword: $bindableSession.keyword,
                selectedChips: $bindableSession.selectedTrendingChips,
                isGenerating: session.isGenerating
            )
            .cardStyle(padding: 0, radius: Radius.lg)
            // Step 1: 选产品
            // P0-4: popover 在 iPad/Mac 上箭头方向/定位行为不一致，改用 sheet 跨平台统一
            .sheet(isPresented: $showOnboardStep1) {
                OnboardingPopover(
                    title: "选你的产品",
                    message: "从这里挑一个之前录入的产品，或点 + 新建。所有 AI 生成都会围绕这个产品的卖点展开",
                    icon: "square.grid.2x2.fill",
                    onDismiss: {
                        showOnboardStep1 = false
                        currentStep = 1
                    }
                )
            }

            GenerateStepStep2AdType(selectedAdType: $bindableSession.selectedAdType)
                .cardStyle(padding: 0, radius: Radius.lg)
                // Step 2: 选广告类型
                .sheet(isPresented: $showOnboardStep2) {
                    OnboardingPopover(
                        title: "选笔记类型",
                        message: "信息流/搜索/品牌/带货 4 种风格，AI 会按你的目标调整标题和正文语气",
                        icon: "rectangle.3.group.fill",
                        onDismiss: {
                            showOnboardStep2 = false
                            currentStep = 2
                        }
                    )
                }

            GenerateStepStep3Keyword(
                keyword: $bindableSession.keyword,
                showStep3Tip: $showStep3Tip,
                selectedChips: $bindableSession.selectedTrendingChips,
                trendingKeywords: $bindableSession.trendingKeywords,
                isLoadingTrending: $bindableSession.isLoadingTrending,
                showInspirationPicker: $bindableSession.showInspirationPicker,
                inspirationPickerType: $bindableSession.inspirationPickerType,
                trendingKeywordsToken: $bindableSession.trendingKeywordsToken
            )
            .cardStyle(padding: 0, radius: Radius.lg)
            // Step 3: 关键词
            .sheet(isPresented: $showOnboardStep3) {
                OnboardingPopover(
                    title: "写关键词",
                    message: "可以自己写，也可以从 AI 推荐的热门词里挑。选中的词会变成标题和正文的核心",
                    icon: "text.magnifyingglass",
                    onDismiss: {
                        showOnboardStep3 = false
                        currentStep = 3
                    }
                )
            }

            GenerateStepStep4Hint(
                hintText: $bindableSession.hintText,
                selectedChips: $bindableSession.selectedHintChips,
                hintChips: $bindableSession.hintChips,
                isLoadingHints: $bindableSession.isLoadingHints,
                showStep4Tip: $showStep4Tip,
                showInspirationPicker: $bindableSession.showInspirationPicker,
                inspirationPickerType: $bindableSession.inspirationPickerType,
                refreshHintsToken: $bindableSession.refreshHintsToken
            )
            .cardStyle(padding: 0, radius: Radius.lg)
            // Step 4: 风格
            .sheet(isPresented: $showOnboardStep4) {
                OnboardingPopover(
                    title: "选写作风格",
                    message: "测评向 / 干货风 / 种草向，AI 按风格生成匹配的语气和节奏",
                    icon: "paintpalette.fill",
                    onDismiss: {
                        showOnboardStep4 = false
                        currentStep = 4
                    }
                )
            }
        }
    }

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        HStack(alignment: .center) {
                            Text("生成笔记")
                                .font(.system(size: Adaptive.heroFontSize, weight: .bold, design: .serif))
                                .foregroundStyle(Color.ink)
                            Spacer()
                        }
                        .padding(.horizontal, Adaptive.horizontalPageMargin)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xs)

                        formCard
                            .id("stepCards")
                    }
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.vertical, Spacing.lg)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }

            VStack(spacing: 0) {
                Spacer()
                // P2-9: iPad 竖屏(compact)下，浮动按钮从全宽改成居中 maxWidth: 600
                // （跟 regularLayout 一致）。iPhone 保持全宽。
                let isWideCompact = ScreenMetrics.shared.width >= 600
                if isWideCompact {
                    HStack {
                        Spacer(minLength: 0)
                        GenerateActionButton(
                            isGenerating: session.isGenerating,
                            onGenerate: { handleGenerate() }
                        )
                        .frame(maxWidth: 600)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                } else {
                    GenerateActionButton(
                        isGenerating: session.isGenerating,
                        onGenerate: { handleGenerate() }
                    )
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                }
            }
            .padding(.vertical, Spacing.md)
            .background(.ultraThinMaterial)
        }
        .background(Color.bg.ignoresSafeArea())
        .overlay {
            ThinkingOverlay(
                isActive: session.isGenerating,
                onCancel: { session.cancel() },
                progress: session.isGenerating
                    ? min(Double(session.receivedChars) / Double(max(session.targetChars, 1)), 1.0)
                    : 0,
                stage: session.currentStage,
                receivedChars: session.receivedChars,
                targetChars: session.targetChars
            )
        }
    }

    private var regularLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("生成笔记")
                        .font(.system(size: Adaptive.heroFontSize + 2, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xs)

                    formCard
                }
                .padding(.horizontal, Spacing.page)
                .padding(.vertical, Spacing.lg)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.never)

            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    GenerateActionButton(
                        isGenerating: session.isGenerating,
                        onGenerate: { handleGenerate() }
                    )
                    .frame(maxWidth: 600)
                    Spacer()
                }
                .padding(.horizontal, Spacing.page)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
                .background(.ultraThinMaterial)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bg.ignoresSafeArea())
        .overlay {
            ThinkingOverlay(
                isActive: session.isGenerating,
                onCancel: { session.cancel() },
                progress: session.isGenerating
                    ? min(Double(session.receivedChars) / Double(max(session.targetChars, 1)), 1.0)
                    : 0,
                stage: session.currentStage,
                receivedChars: session.receivedChars,
                targetChars: session.targetChars
            )
        }
    }

    // MARK: - Body

    private var generationFormBody: some View {
        @Bindable var bindableSession = session
        return Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        #endif
        .onAppear {
            Task { await fetchTrendingKeywords() }
            // 首次启动引导：currentStep 从 -1 → 0
            // 延迟 1.0s 等 layout 就绪，否则 popover 位置算不准
            if currentStep == -1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    currentStep = 0
                    showOnboardStep1 = true
                }
            }
        }
        .onChange(of: currentStep) { _, new in
            // currentStep 推进 → 触发下一个 popover
            switch new {
            case 1: showOnboardStep2 = true
            case 2: showOnboardStep3 = true
            case 3: showOnboardStep4 = true
            case 4: showOnboardStep5 = true   // 生成按钮的 popover（在 GenerateActionButton 里挂）
            default: break
            }
        }
        // 错误卡片（替代之前的简单 alert）
        // 跟图片/视频的 generationErrorCard 风格一致：原因 + 建议 + 重试/复制按钮
        // 包在 Group 里避免外层 modifier chain 的类型推断问题
        Group {
            if let error = session.errorMessage, session.showError {
                generationErrorCard(
                    kind: "文案",
                    rawError: error,
                    provider: LLMConfigStore.config(for: .text).provider.rawValue,
                    onRetry: { handleGenerate() }
                )
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.top, Spacing.md)
            }
        }
        .onChange(of: session.isGenerating) { _, newValue in
            DebugLog.shared.log(.info, .llm, "isGenerating changed", details: "value=\(newValue)")
        }
        .sheet(isPresented: $bindableSession.showInspirationPicker) {
            InspirationPickerSheet(
                filterType: session.inspirationPickerType,
                onSelect: { content in
                    if session.inspirationPickerType == .keyword {
                        if session.keyword.isEmpty {
                            session.keyword = content
                        } else if !session.keyword.contains(content) {
                            session.keyword += " " + content
                        }
                        // 也记入 Set — 跟点 LLM chip 一致：刷新时如果 LLM 这次也搜到
                        // 同样的词，会自动显示选中
                        session.selectedTrendingChips.insert(content)
                    } else {
                        if session.hintText.isEmpty {
                            session.hintText = content
                        } else if !session.hintText.contains(content) {
                            session.hintText += " " + content
                        }
                        session.selectedHintChips.insert(content)
                    }
                    session.showInspirationPicker = false
                }
            )
        }
        .onChange(of: session.refreshHintsToken) { _, _ in
            Task { await fetchHintChipsFromLLM() }
        }
        .onChange(of: session.trendingKeywordsToken) { _, _ in
            Task { await fetchTrendingKeywords() }
        }
    }

    // MARK: - Helpers

    private func fetchTrendingKeywords() async {
        guard !session.isLoadingTrending else { return }
        session.isLoadingTrending = true
        defer { session.isLoadingTrending = false }

        // helper 内部已处理 LLM 失败 fallback，永远返回非空数组
        let keywords = await GenerationHelpers.fetchKeywordsFromLLM(
            product: session.selectedProduct,
            keyword: session.keyword
        )

        await MainActor.run {
            // 已选中的 LLM chip 永远保留在列表最前（即使 LLM 这次没搜到），
            // 这样用户刷新后还能再点这些 chip 取消选中 — isSelected 由 Set 追踪自动为 true
            // 用户手输入的 token **不**进 chip 列表（避免"被判定为 LLM 搜出来的"）
            let pinned = Array(session.selectedTrendingChips)
            let newOnes = keywords.filter { kw in !session.selectedTrendingChips.contains(kw) }
            session.trendingKeywords = pinned + newOnes
        }
    }

    private func fetchHintChipsFromLLM() async {
        guard !session.isLoadingHints else { return }
        session.isLoadingHints = true
        defer { session.isLoadingHints = false }

        await GenerationHelpers.fetchHintChipsFromLLM(
            product: session.selectedProduct,
            keyword: session.keyword
        ) { chips in
            await MainActor.run {
                // 同上：已选中的 LLM chip 保留在列表最前
                let pinned = Array(session.selectedHintChips)
                let newOnes = chips.filter { c in !session.selectedHintChips.contains(c) }
                session.hintChips = pinned + newOnes
            }
        }
    }

    // MARK: - Generation logic
    //
    // 业务入口：构造请求 → 委托给 GenerationSession.startGeneration
    // 真正的 task 持有 / 进度更新 / 错误处理都在 session 里，跨 view 生命周期

    private func handleGenerate() {
        let hint = session.hintText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : session.hintText.trimmingCharacters(in: .whitespaces)
        let request = GenerateRequest(
            recordId: UUID(),
            keyword: session.keyword,
            adType: session.selectedAdType,
            keywordHint: hint,
            product: session.selectedProduct,
            images: [],
            styleImages: []
        )

        session.startGeneration(
            request: request,
            generator: generator,
            modelContext: modelContext
        )
    }
}

// MARK: - 错误卡片（文案生成专用，复用 ResultView 风格）
//
// 跟 ResultView.generationErrorCard 风格一致：原因 + 建议 + 重试/复制按钮。
// 暂不复用 ResultView 私有函数（避免跨文件 private 依赖）—— 后续可提取到
// DesignSystem/GenerationErrorCard.swift 共享。
private func generationErrorCard(
    kind: String,
    rawError: String,
    provider: String,
    onRetry: @escaping () -> Void
) -> some View {
    let (title, suggestion) = diagnoseGenerationError(rawError)
    return VStack(alignment: .leading, spacing: Spacing.md) {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.danger)
                .font(.system(size: 16, weight: .semibold))
            Text("\(kind)生成失败")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
            Spacer()
        }

        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("原因")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Color.ink3)
            Text(title)
                .font(Typography.bodySmall)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("建议")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Color.ink3)
            Text(suggestion)
                .font(Typography.bodySmall)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("技术细节（\(provider)）")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.ink4)
                Spacer()
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = rawError
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rawError, forType: .string)
                    #endif
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc").font(Typography.caption)
                        Text("复制").font(Typography.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink3)
            }
            Text(rawError)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.ink3)
                .lineLimit(6)
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm))
        }

        Button {
            onRetry()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("重新生成\(kind)")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GhostButtonStyle(tint: .brand))
    }
    .padding(Spacing.md)
    .background(Color.errorBg.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(Color.danger.opacity(0.25), lineWidth: 1)
    )
}

/// 文案生成错误诊断（关键词匹配，简化版 ——
/// 跟 ResultView.diagnoseVideoError 一样，逻辑通用不区分 kind）。
private func diagnoseGenerationError(_ raw: String) -> (title: String, suggestion: String) {
    let lower = raw.lowercased()
    if raw.contains("API Key") || raw.contains("URL / Key / Model") || raw.contains("401") || raw.contains("403") || raw.contains("未授权") {
        return ("未授权：API Key / URL / Model 三件套未配齐或无效",
                "到「我的 → 大模型配置 → 文案生成」检查 URL / Key / Model 是否正确填写，或在服务商控制台确认 Key 有效。")
    }
    if raw.contains("超时") || raw.contains("timed out") || lower.contains("timeout") || raw.contains("-1001") {
        return ("请求超时",
                "文案生成偶尔会比较慢。如果多次超时：① 检查网络稳定性 ② 简化关键词和风格提示 ③ 切到更轻量的模型。")
    }
    if raw.contains("-1005") || raw.contains("网络连接已中断") || raw.contains("network connection lost") {
        return ("网络连接已中断",
                "请求在传输途中被关闭（可能切换了 WiFi、VPN 断开、或者本地网络瞬时抖动）。\n\n建议：① 确认当前网络稳定 ② 重新点击「重新生成文案」重试。")
    }
    if raw.contains("-1009") || raw.contains("无网络") {
        return ("无网络连接",
                "设备当前连不上互联网。检查 WiFi / 蜂窝数据是否正常，或等待网络恢复后重试。")
    }
    if raw.contains("JSON") || raw.contains("未返回合法") {
        return ("模型返回了非预期的格式",
                "LLM 返回的不是合法 JSON（文案标题/正文/标签格式）。建议：① 简化关键词 ② 换一个模型 ③ 重试。")
    }
    if raw.contains("rate") && (raw.contains("limit") || raw.contains("429")) {
        return ("调用过于频繁（限流）",
                "服务商返回 429。等 30 秒再重试，或切换到备用服务商。")
    }
    return ("生成未成功", "请重试。如果反复失败，简化输入或切换模型，或到设置页复制错误反馈给我们。")
}
