//
//  GenerateView.swift
//  RedPulse
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

    @Environment(CoachMarkManager.self) private var coachMarkManager
    @AppStorage("llm_high_quality_mode") private var highQualityMode: Bool = false
    @AppStorage("show_step3_tip") private var showStep3Tip = true
    @AppStorage("show_step4_tip") private var showStep4Tip = true
    @AppStorage("has_seen_coach_marks_generate") private var hasSeenCoachMarksGenerate = false

    @State private var selectedAdType: AdType = .feedAd
    @State private var keyword: String = ""
    @State private var hintText: String = ""
    @State private var selectedSuggestions: Set<String> = []
    @State private var trendingKeywords: [String] = []
    @State private var isLoadingTrending = false
    @State private var hintChips: [String] = [
        "测评向", "干货风", "轻松搞笑", "好物分享",
        "真实体验", "干货科普", "问号钩子", "避雷指南"
    ]
    @State private var isLoadingHints = false

    @State private var generatedRecord: GenerationRecord?
    @State private var selectedProduct: Product? = nil
    @State private var showInspirationPicker = false
    @State private var inspirationPickerType: InspirationType = .keyword

    /// 可折叠 section: 默认全部展开，用户可手动折叠
    @State private var collapsedSections: Set<String> = []

    // MARK: - Generation state
    @State private var isGenerating = false
    @State private var generateTask: Task<Void, Never>? = nil
    @State private var showGenerateError = false
    @State private var generateErrorMessage: String? = nil

    /// 文本模型配置齐全时走真实 LLM，否则回退到 Mock。
    private var generator: GeneratorProtocol {
        LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()
    }

    @State private var refreshHintsToken: Int = 0
    @State private var trendingKeywordsToken: Int = 0

    var body: some View {
        if let record = generatedRecord {
            ResultView(record: record)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            generatedRecord = nil
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
        VStack(spacing: Spacing.lg) {
            GenerateStepStep1Product(
                selectedProduct: $selectedProduct,
                keyword: $keyword,
                isGenerating: $isGenerating
            )
            .cardStyle(padding: 0, radius: Radius.lg)
            .coachMarkTarget("gen_product_select")

            GenerateStepStep2AdType(selectedAdType: $selectedAdType)
                .cardStyle(padding: 0, radius: Radius.lg)
                .coachMarkTarget("gen_ad_type")

            GenerateStepStep3Keyword(
                keyword: $keyword,
                showStep3Tip: $showStep3Tip,
                selectedSuggestions: $selectedSuggestions,
                trendingKeywords: $trendingKeywords,
                isLoadingTrending: $isLoadingTrending,
                showInspirationPicker: $showInspirationPicker,
                inspirationPickerType: $inspirationPickerType,
                trendingKeywordsToken: $trendingKeywordsToken
            )
            .cardStyle(padding: 0, radius: Radius.lg)
            .coachMarkTarget("gen_keyword")

            GenerateStepStep4Hint(
                hintText: $hintText,
                hintChips: $hintChips,
                isLoadingHints: $isLoadingHints,
                showStep4Tip: $showStep4Tip,
                showInspirationPicker: $showInspirationPicker,
                inspirationPickerType: $inspirationPickerType,
                refreshHintsToken: $refreshHintsToken
            )
            .cardStyle(padding: 0, radius: Radius.lg)
            .coachMarkTarget("gen_style")
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
                            QualityModeToggle(isGenerating: $isGenerating)
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
                GenerateActionButton(
                    isGenerating: $isGenerating,
                    onGenerate: { handleGenerate() }
                )
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.vertical, Spacing.md)
                .background(.ultraThinMaterial)
            }
            .padding(.bottom, Adaptive.floatingButtonBottomPadding)
        }
        .background(Color.bg.ignoresSafeArea())
        .overlay {
            ThinkingOverlay(isActive: isGenerating, onCancel: {
                cancelGeneration()
            })
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
                        isGenerating: $isGenerating,
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
            ThinkingOverlay(isActive: isGenerating, onCancel: {
                cancelGeneration()
            })
        }
    }

    // MARK: - Body

    private var generationFormBody: some View {
        Group {
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
        }
        .onChange(of: coachMarkManager.isActive) { _, isActive in
            if !isActive && !hasSeenCoachMarksGenerate
                && coachMarkManager.steps.map(\.id) == CoachMarkStep.generateSteps.map(\.id) {
                hasSeenCoachMarksGenerate = true
            }
        }
        .alert("生成失败", isPresented: $showGenerateError) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(generateErrorMessage ?? "未知错误")
        }
        .onChange(of: isGenerating) { _, newValue in
            DebugLog.shared.log(.info, .llm, "isGenerating changed", details: "value=\(newValue)")
        }
        .sheet(isPresented: $showInspirationPicker) {
            InspirationPickerSheet(
                filterType: inspirationPickerType,
                onSelect: { content in
                    if inspirationPickerType == .keyword {
                        if keyword.isEmpty {
                            keyword = content
                        } else if !keyword.contains(content) {
                            keyword += " " + content
                        }
                    } else {
                        if hintText.isEmpty {
                            hintText = content
                        } else if !hintText.contains(content) {
                            hintText += " " + content
                        }
                    }
                    showInspirationPicker = false
                }
            )
        }
        .onChange(of: refreshHintsToken) { _, _ in
            Task { await fetchHintChipsFromLLM() }
        }
        .onChange(of: trendingKeywordsToken) { _, _ in
            Task { await fetchTrendingKeywords() }
        }
    }

    // MARK: - Helpers

    private func fetchTrendingKeywords() async {
        guard !isLoadingTrending else { return }
        isLoadingTrending = true
        defer { isLoadingTrending = false }

        let keywords = await GenerationHelpers.fetchKeywordsFromLLM(
            product: selectedProduct,
            keyword: keyword
        )

        await MainActor.run {
            if let llmKeywords = keywords {
                trendingKeywords = llmKeywords
            } else {
                trendingKeywords = [
                    "早八通勤穿搭", "氛围感妆容", "平价替代",
                    "沉浸式回家", "独居vlog", "减脂餐",
                    "职场干货", "好物合集", "换季护肤",
                    "旅行攻略", "咖啡日记", "穿搭灵感"
                ]
            }
        }
    }

    private func fetchHintChipsFromLLM() async {
        guard !isLoadingHints else { return }
        isLoadingHints = true
        defer { isLoadingHints = false }

        await GenerationHelpers.fetchHintChipsFromLLM(
            product: selectedProduct,
            keyword: keyword
        ) { chips in
            await MainActor.run {
                hintChips = Array(chips.prefix(10))
            }
        }
    }

    // MARK: - Generation logic

    private func handleGenerate() {
        isGenerating = true
        let hint = hintText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : hintText.trimmingCharacters(in: .whitespaces)
        let request = GenerateRequest(
            recordId: UUID(),
            keyword: keyword,
            adType: selectedAdType,
            keywordHint: hint,
            product: selectedProduct,
            images: [],
            styleImages: []
        )

        let gen = generator
        let usingReal = (gen is LLMTextGenerator)
        DebugLog.shared.info(
            .llm,
            "handleGenerate triggered",
            details: """
            generator=\(usingReal ? "LLMTextGenerator" : "MockGenerator")
            adType=\(selectedAdType.displayName)
            keyword=\(keyword)
            hint=\(hint ?? "(none)")
            product=\(selectedProduct?.name ?? "(none)")
            """
        )
        let capturedKeyword = keyword
        let capturedAdType = selectedAdType
        let capturedHint = hint
        let capturedModelContext = modelContext
        let capturedProductId = selectedProduct?.id

        generateTask = Task {
            do {
                let response = try await gen.generate(request)
                try Task.checkCancellation()

                let record = GenerationRecord(
                    adType: capturedAdType.rawValue,
                    inputKeyword: capturedKeyword,
                    keywordHint: capturedHint,
                    productId: capturedProductId,
                    noteTitle: response.noteTitle,
                    content: response.content,
                    tags: response.tags,
                    imageSuggestion: response.imageSuggestion,
                    imagePrompt: response.imagePrompt,
                    videoPrompt: response.videoPrompt,
                    easterEggText: response.easterEgg,
                    hotScore: response.hotScore,
                    suggestion: response.suggestion
                )

                finishGeneration(
                    response: response,
                    record: record,
                    capturedModelContext: capturedModelContext
                )
            } catch is CancellationError {
                DebugLog.shared.log(.warn, .llm, "generate cancelled by user")
                resetGenerationState()
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                DebugLog.shared.log(.warn, .llm, "generate cancelled (URLSession)")
                resetGenerationState()
            } catch {
                let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DebugLog.shared.log(.error, .llm, "generate pipeline failed", details: raw)
                let friendly = GenerationHelpers.friendlyErrorMessage(raw: raw, error: error)
                showGenerationError(friendly)
            }
        }
    }

    @MainActor
    private func finishGeneration(
        response: GenerateResponse,
        record: GenerationRecord,
        capturedModelContext: ModelContext
    ) {
        capturedModelContext.insert(record)
        do {
            try capturedModelContext.save()
        } catch {
            DebugLog.shared.log(.error, .llm, "modelContext.save() failed", details: error.localizedDescription)
        }
        generateTask = nil
        isGenerating = false
        generatedRecord = record
        DebugLog.shared.log(
            .info, .llm,
            "generation complete, navigating to result",
            details: "title=\(response.noteTitle) id=\(record.id)"
        )
    }

    @MainActor
    private func resetGenerationState() {
        isGenerating = false
        generateTask = nil
    }

    @MainActor
    private func showGenerationError(_ message: String) {
        isGenerating = false
        generateTask = nil
        generateErrorMessage = message
        showGenerateError = true
    }

    private func cancelGeneration() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
    }
}
