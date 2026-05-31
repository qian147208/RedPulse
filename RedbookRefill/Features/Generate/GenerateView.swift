import SwiftUI
import SwiftData

struct GenerateView: View {
    @Environment(Repository.self) private var repository
    @Environment(AuthStore.self) private var authStore
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
    /// 提示关键词风格胶囊。初始内置一份默认值，用户点"大模型刷新"后用 LLM 重写。
    @State private var hintChips: [String] = [
        "测评向", "干货风", "轻松搞笑", "好物分享",
        "真实体验", "干货科普", "问号钩子", "避雷指南"
    ]
    @State private var isLoadingHints = false

    @State private var showGuestAlert = false
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
    /// 每次生成时新建实例，确保读到 UserDefaults 最新值。
    private var generator: GeneratorProtocol {
        LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()
    }

    var body: some View {
        // 用条件渲染替代 sheet/navigationDestination —— 这两套 API 在
        // NavigationSplitView.detail 内嵌 NavigationStack 的 macOS 场景下都被验证不稳。
        // 条件渲染是纯本地 @State 驱动，最稳定。
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

    // MARK: - Form card (shared by compact + regular)

    private var formCard: some View {
        VStack(spacing: Spacing.lg) {
            productQuickSelect
                .cardStyle(padding: 0, radius: Radius.lg)
                .coachMarkTarget("gen_product_select")
            
            adTypeSection
                .cardStyle(padding: 0, radius: Radius.lg)
                .coachMarkTarget("gen_ad_type")
            
            keywordSection
                .cardStyle(padding: 0, radius: Radius.lg)
                .coachMarkTarget("gen_keyword")
            
            hintChipsSection
                .cardStyle(padding: 0, radius: Radius.lg)
                .coachMarkTarget("gen_style")
        }
    }

    // MARK: - Layout: compact (iPhone) — with step progress

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        // 标题 + 模型切换（右侧齐平）
                        HStack(alignment: .center) {
                            Text("生成笔记")
                                .font(.system(size: Adaptive.heroFontSize, weight: .bold, design: .serif))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            qualityModeToggle
                        }
                        .padding(.horizontal, Adaptive.horizontalPageMargin)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.xs)



                        formCard
                            .id("stepCards")
                        guestFooterSection
                    }
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.vertical, Spacing.lg)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            
            // Frosted bottom bar — 底部64pt避开Tab栏
            VStack(spacing: 0) {
                Spacer()
                generateActionButton
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

    /// Step progress: 4 small dots indicating which step the user is on
    private var stepProgressBar: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(colorForStep(i))
                    .frame(width: i == currentVisibleStep ? 32 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentVisibleStep)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Tracks which step is most visible in the scroll view
    /// Simplified: uses the collapsedSections to determine "active" step
    @State private var currentVisibleStep: Int = 0

    private func colorForStep(_ step: Int) -> Color {
        step <= currentVisibleStep ? Color.brand : Color.border
    }

    // MARK: - Layout: regular (iPad / Mac)

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
                    guestFooterSection
                }
                .padding(.horizontal, Spacing.page)
                .padding(.vertical, Spacing.lg)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.never)

            // Frosted bottom bar
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    generateActionButton
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
        .alert("访客次数已用完", isPresented: $showGuestAlert) {
            Button("去登录", role: .cancel) {}
        } message: {
            Text("登录后可解锁无限生成次数")
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
    }

    

    /// 步骤编号胶囊
    private func stepBadge(_ num: Int, active: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text("STEP")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
            Text(String(format: "%02d", num))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(active ? Color.brand : Color.ink3)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(active ? Color.brandSoft : Color.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Product Quick Select

    private var productQuickSelect: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                stepBadge(1)
                Text("选择产品").editorialLabel()
                Spacer()
            }
            if products.isEmpty {
                Text("暂无产品，请先前往产品库添加")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink4)
            } else {
                productThumbStrip
                // }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 右上角 "⚡ 快速 / ✨ 高质量" 切换胶囊，与标题平齐靠右。
    /// 配置页里没填高质量模型时，按钮变灰提示先去填。
    private var qualityModeToggle: some View {
        let hasQualityModel = !(UserDefaults.standard.string(forKey: "llm_content_model_quality") ?? "").isEmpty
        return Button {
            // 用户没填高质量模型时禁用此切换
            guard hasQualityModel else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                highQualityMode.toggle()
            }
            DebugLog.shared.info(
                .llm,
                "quality mode toggled",
                details: "highQuality=\(highQualityMode)"
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: highQualityMode ? "sparkles" : "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(highQualityMode ? "高质量" : "快速")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(highQualityMode ? .white : Color.ink2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(highQualityMode ? Color.brand : Color.surfaceMuted, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(highQualityMode ? Color.clear : Color.border, lineWidth: BorderWidth.thin)
            )
            .opacity(hasQualityModel ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .contentShape(Rectangle())
    }

    // (batch mode removed)

    /// 横向产品卡片条：最多显示 6 个（按 createdAt 倒序），超过 6 个在末尾加一个"更多"卡片跳产品库。
    private static let quickSelectLimit = 6

    private var productThumbStrip: some View {
        // 批量模式已注释隐藏，仅保留单选逻辑
        let visible = Array(products.prefix(Self.quickSelectLimit))
        let hasMore = products.count > Self.quickSelectLimit
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(visible) { product in
                    productThumbCard(product)
                }
                if hasMore {
                    moreProductsCard
                }
            }
        }
    }

    @ScaledMetric private var thumbSize: CGFloat = 72
    @ScaledMetric private var checkmarkSize: CGFloat = 16
    @ScaledMetric private var checkBgSize: CGFloat = 18
    @ScaledMetric private var thumbFontSize: CGFloat = 12

    /// Adaptive thumb size that combines Dynamic Type scaling with screen-width scaling.
    private var adaptiveThumbSize: CGFloat {
        max(thumbSize, Adaptive.thumbSize)
    }

    private func productThumbCard(_ product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        return Button {
            withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                if isSelected {
                    selectedProduct = nil
                } else {
                    selectedProduct = product
                    keyword = product.name + " " + product.sellingPoint
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let firstPath = product.imagePaths.first,
                           let img = loadProductThumbnail(path: firstPath) {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: adaptiveThumbSize, height: adaptiveThumbSize)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(Color.surfaceMuted)
                                .frame(width: adaptiveThumbSize, height: adaptiveThumbSize)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundStyle(Color.ink4)
                                )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(isSelected ? Color.brand : Color.clear, lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? Color.brand.opacity(0.15) : Color.clear, radius: 4)
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: checkmarkSize, weight: .semibold))
                            .foregroundStyle(Color.brand)
                            .background(Circle().fill(Color.surface).frame(width: checkBgSize, height: checkBgSize))
                            .offset(x: 6, y: -6)
                    }
                }
                Text(product.name)
                    .font(.system(size: thumbFontSize, weight: .medium))
                    .foregroundStyle(isSelected ? Color.brand : Color.ink)
                    .lineLimit(1)
                    .frame(width: adaptiveThumbSize)
            }
        }
        .buttonStyle(.plain)
    }

    /// 产品多于 6 个时，末尾的"更多 →"卡片，导航到 ProductListView。
    private var moreProductsCard: some View {
        NavigationLink {
            ProductListView()
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.brandSoft)
                    .frame(width: 56, height: 56)
                    .overlay(
                        VStack(spacing: 2) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.brand)
                            Text("更多")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.brand)
                        }
                    )
                Text("查看全部")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.brand)
                    .lineLimit(1)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadProductThumbnail(path: String) -> Image? {
        guard !path.isEmpty else { return nil }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(path)
        guard fm.fileExists(atPath: url.path) else { return nil }
        #if canImport(UIKit)
        guard let ui = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: ui)
        #elseif canImport(AppKit)
        guard let ns = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    // MARK: - Ad Type

    private func infoForAdType(_ type: AdType) -> (icon: String, desc: String) {
        switch type {
        case .feedAd:
            return ("square.stack.3d.up.fill", "曝光优先，吸睛吸流")
        case .searchAd:
            return ("magnifyingglass.circle.fill", "精准SEO，搜索卡位")
        case .brandAd:
            return ("crown.fill", "调性心智，品牌故事")
        case .salesNote:
            return ("bag.fill", "高效变现，催促转化")
        }
    }

    private var adTypeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                stepBadge(2)
                Text("广告类型").editorialLabel()
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(AdType.allCases) { type in
                    let isSelected = selectedAdType == type
                    let info = infoForAdType(type)
                    Button {
                        withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                            selectedAdType = type
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? Color.brandSoft : Color.surfaceMuted)
                                    .frame(width: 32, height: 32)
                                Image(systemName: info.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.brand : Color.ink2)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.brand : Color.ink)
                                Text(info.desc)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.ink3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.brandSoft.opacity(0.3) : Color.surface)
                        .contentShape(Rectangle())
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(isSelected ? Color.brand : Color.border, lineWidth: isSelected ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Keyword

    private var keywordSection: some View {
        let isCollapsed = collapsedSections.contains("keyword")
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsedSections.remove("keyword") }
                    else { collapsedSections.insert("keyword") }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    stepBadge(3, active: !isCollapsed)
                    Text("产品关键词").editorialLabel()
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // 灵感板入口
                    Button {
                        inspirationPickerType = .keyword
                        showInspirationPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 12, weight: .medium))
                            Text("从灵感板导入关键词")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.suggestionBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.suggestionBg, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    ZStack(alignment: .bottomTrailing) {
                        ZStack(alignment: .topLeading) {
                            if keyword.isEmpty {
                                Text("写产品关键词，或从产品库带入")
                                    .font(Typography.bodySmall)
                                    .foregroundStyle(Color.ink4)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $keyword)
                                .font(Typography.bodySmall)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 80, maxHeight: 100)
                        }
                        .padding(Spacing.md)

                        HStack(spacing: 8) {
                            if !keyword.isEmpty {
                                Button {
                                    keyword = ""
                                    selectedSuggestions.removeAll()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.ink3)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("\(keyword.count) 字")
                                .font(Typography.monoSmall)
                                .foregroundStyle(Color.ink3)
                        }
                        .padding(.trailing, Spacing.md)
                        .padding(.bottom, Spacing.sm)
                    }
                    .background(Color.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(Color.border, lineWidth: BorderWidth.hairline)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    if showStep3Tip {
                        HStack(alignment: .top, spacing: 8) {
                            Text("💡")
                                .font(.system(size: 13))
                            Text("输入产品核心关键词即可，如「氨基酸洗面奶」「油皮亲妈」。AI 会自动扩展为完整笔记。")
                                .font(Typography.caption)
                                .foregroundStyle(Color.ink3)
                                .lineSpacing(3)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation {
                                    showStep3Tip = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.ink4)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.brandSoft.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // 热门关键词 — 内置于关键词 section
                    trendingKeywordsGrid
                }
                .padding(Spacing.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                if !keyword.isEmpty {
                    Text("关键词：\(keyword)")
                        .font(Typography.bodySmall)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 热门关键词网格 — 从 suggestionSection 移入 keyword section
    private var trendingKeywordsGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("热门关键词").editorialLabel()
                Spacer()
                if isLoadingTrending {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await fetchTrendingKeywords() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.brand)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(selectedProduct == nil ? "刷新热门关键词" : "基于「\(selectedProduct!.name)」刷新热门关键词")
                }
            }

            if trendingKeywords.isEmpty && !isLoadingTrending {
                Text("暂无热门关键词，请稍后刷新")
                    .font(Typography.caption)
                    .foregroundStyle(Color.ink4)
            } else {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(trendingKeywords, id: \.self) { item in
                        let isSelected = selectedSuggestions.contains(item)
                        Button {
                            HapticManager.lightImpact()
                            withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                                if isSelected {
                                    selectedSuggestions.remove(item)
                                    keyword = keyword
                                        .replacingOccurrences(of: item, with: "")
                                        .trimmingCharacters(in: .whitespaces)
                                } else {
                                    selectedSuggestions.insert(item)
                                    if keyword.isEmpty {
                                        keyword = item
                                    } else if !keyword.contains(item) {
                                        keyword += " " + item
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text(item)
                                    .font(Typography.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSelected ? .white : Color.ink2)
                            .background(isSelected ? Color.brand : Color.surfaceMuted)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Hint Chips

    private var hintChipsSection: some View {
        let isCollapsed = collapsedSections.contains("hint")
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { collapsedSections.remove("hint") }
                    else { collapsedSections.insert("hint") }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    stepBadge(4, active: !isCollapsed)
                    Text("风格关键词").editorialLabel()
                    Spacer()
                    if !isCollapsed {
                        if isLoadingHints {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                Task { await fetchHintChipsFromLLM() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.brand)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(selectedProduct == nil ? "刷新风格胶囊" : "基于「\(selectedProduct!.name)」重新生成风格胶囊")
                        }
                    }
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // 灵感板入口
                    Button {
                        inspirationPickerType = .style
                        showInspirationPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 12, weight: .medium))
                            Text("从灵感板导入风格")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.suggestionBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.suggestionBg, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    ZStack(alignment: .bottomTrailing) {
                        ZStack(alignment: .topLeading) {
                            if hintText.isEmpty {
                                Text("写提示关键词，引导 AI 写作方向")
                                    .font(Typography.bodySmall)
                                    .foregroundStyle(Color.ink4)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $hintText)
                                .font(Typography.bodySmall)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 80, maxHeight: 100)
                        }
                        .padding(Spacing.md)
                        
                        HStack(spacing: 8) {
                            if !hintText.isEmpty {
                                Button {
                                    hintText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.ink3)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("\(hintText.count) 字")
                                .font(Typography.monoSmall)
                                .foregroundStyle(Color.ink3)
                        }
                        .padding(.trailing, Spacing.md)
                        .padding(.bottom, Spacing.sm)
                    }
                    .background(Color.surfaceMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(Color.border, lineWidth: BorderWidth.hairline)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    if showStep4Tip {
                        HStack(alignment: .top, spacing: 8) {
                            Text("💡")
                                .font(.system(size: 13))
                            Text("选择或输入风格关键词，可以微调大模型的生成语气，让您的笔记更具特色与说服力。")
                                .font(Typography.caption)
                                .foregroundStyle(Color.ink3)
                                .lineSpacing(3)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation {
                                    showStep4Tip = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.ink4)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.brandSoft.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(hintChips, id: \.self) { chip in
                            let isSelected = hintText.contains(chip)
                            Button {
                                HapticManager.lightImpact()
                                withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                                    if isSelected {
                                        hintText = hintText
                                            .replacingOccurrences(of: " \(chip)", with: "")
                                            .replacingOccurrences(of: "\(chip) ", with: "")
                                            .replacingOccurrences(of: chip, with: "")
                                            .trimmingCharacters(in: .whitespaces)
                                    } else {
                                        if hintText.isEmpty {
                                            hintText = chip
                                        } else {
                                            hintText += " " + chip
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(chip)
                                        .font(Typography.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isSelected ? .white : Color.ink2)
                                .background(isSelected ? Color.brand : Color.surfaceMuted)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !hintText.isEmpty {
                Text("风格：\(hintText)")
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Buttons



    private var generateActionButton: some View {
        Button {
            HapticManager.heavyImpact()
            handleGenerate()
        } label: {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                    Text("AI 撰写中...")
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                    Text("立即生成小红书笔记")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Adaptive.buttonHeight)
            .background(
                LinearGradient(
                    colors: [Color.brand, Color(red: 0.95, green: 0.08, blue: 0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            )
            .shadow(color: canTriggerGenerate ? Color.brand.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canTriggerGenerate || isGenerating)
        .opacity(canTriggerGenerate ? 1.0 : 0.5)
        .animation(.easeOut(duration: AnimDuration.fast), value: canTriggerGenerate)
        .keyboardShortcut("r", modifiers: .command)
        .coachMarkTarget("generate_button")
    }



    // MARK: - Guest Footer

    @ViewBuilder
    private var guestFooterSection: some View {
        if authStore.isGuest {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(Typography.caption)
                Text("访客今日剩余 \(authStore.guestRemaining) 次（每天 \(AuthStore.guestDailyLimit) 次、本周已用 \(authStore.guestWeeklyCount)/\(AuthStore.guestWeeklyLimit)）")
                    .font(Typography.caption)
            }
            .foregroundStyle(Color.ink3)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private var canGenerate: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTriggerGenerate: Bool {
        canGenerate
    }

    private func fetchTrendingKeywords() async {
        guard !isLoadingTrending else { return }
        isLoadingTrending = true
        defer { isLoadingTrending = false }

        // 先尝试用 LLM 动态生成热门关键词（结合所选产品上下文）；配置未就绪或失败则回退 mock。
        if let llmKeywords = await fetchKeywordsFromLLM() {
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

    /// "大模型刷新"按钮触发：基于当前选中产品上下文（无则通用风格）
    /// 让模型重写 6-10 个**风格定调**胶囊词（2-5 字），写入 hintChips。
    private func fetchHintChipsFromLLM() async {
        guard !isLoadingHints else { return }
        isLoadingHints = true
        defer { isLoadingHints = false }

        let ctx = productContextLine()
        let prompt = """
        基于以下产品/关键词上下文，输出 8 个**写小红书笔记时可选的风格 / 角度提示词**。
        要求：
        - 每个 2-5 字
        - 例如「测评向」「干货风」「避雷指南」「问号钩子」这种风格定调
        - 不同提示词在角度上要互补，覆盖测评、教程、情绪、对比、避雷等
        \(ctx.isEmpty ? "" : ctx)
        严格输出 JSON 数组：["提示1","提示2",...]，不要 markdown 不要解释。
        """
        if let list = await chatJSONList(prompt: prompt, maxTokens: 200), !list.isEmpty {
            hintChips = Array(list.prefix(10))
        }
    }

    /// 用 LLM 生成小红书当前热门关键词（≤12 个），如有产品上下文会聚焦该产品所在领域。
    /// 返回 nil 表示配置不全或调用失败，调用方回退 mock。
    private func fetchKeywordsFromLLM() async -> [String]? {
        let ctx = productContextLine()
        let prompt = """
        请输出 12 个**适合下面产品/关键词** 在小红书上的热门关键词或话题（每个 2-6 字）。
        要求：聚焦该产品所在的内容领域，结合当下趋势（2026 年），适合中国年轻女性用户。
        \(ctx.isEmpty ? "如果没有产品上下文，则给小红书近期主流热门话题，覆盖穿搭、美妆、生活方式、家居、美食、职场。" : ctx)
        严格输出 JSON 数组：["关键词1","关键词2",...]，不要 markdown 代码块标记，不要解释。
        """
        return await chatJSONList(prompt: prompt, maxTokens: 300)
    }

    /// 把选中产品 / 当前关键词 / 风格提示 拼成简短上下文段落，给 LLM 做 prompt 参考。
    /// 没产品时返回空串，让 prompt 自然退化为通用版本。
    private func productContextLine() -> String {
        guard let p = selectedProduct else {
            let kw = keyword.trimmingCharacters(in: .whitespaces)
            return kw.isEmpty ? "" : "\n[当前关键词]\n\(kw)"
        }
        var lines = ["产品名称：\(p.name)", "卖点：\(p.sellingPoint)"]
        if let t = p.targetAudience, !t.isEmpty { lines.append("目标人群：\(t)") }
        if let s = p.scenario, !s.isEmpty { lines.append("场景：\(s)") }
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty { lines.append("当前关键词：\(kw)") }
        return "\n[产品上下文]\n" + lines.joined(separator: "\n")
    }

    /// 通用 LLM JSON 数组返回工具：发请求 → 期望 content 是 JSON 数组 → 解析返回。
    /// 配置不全 / HTTP 失败 / 解析失败一律返回 nil，由调用方决定 fallback。
    private func chatJSONList(prompt: String, maxTokens: Int) async -> [String]? {
        let urlStr = UserDefaults.standard.string(forKey: "llm_content_url") ?? ""
        let key = UserDefaults.standard.string(forKey: "llm_content_key") ?? ""
        let model = UserDefaults.standard.string(forKey: "llm_content_model") ?? ""
        guard !urlStr.isEmpty, !key.isEmpty, !model.isEmpty,
              let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一个 JSON 输出机器人，只输出 JSON 数组，不输出任何其它内容。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.9,
            "max_tokens": maxTokens
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```") {
                if let nl = cleaned.firstIndex(of: "\n") {
                    cleaned = String(cleaned[cleaned.index(after: nl)...])
                }
                if cleaned.hasSuffix("```") {
                    cleaned = String(cleaned.dropLast(3))
                }
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let arr = try? JSONSerialization.jsonObject(with: cleaned.data(using: .utf8) ?? Data()) as? [String] else {
                return nil
            }
            return arr.filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }

    private func handleGenerate() {
        if authStore.isGuest && !authStore.canGuestGenerate() {
            showGuestAlert = true
            return
        }

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
        let capturedAuthStore = authStore
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
                    capturedAuthStore: capturedAuthStore,
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
                let friendly = Self.friendlyErrorMessage(raw: raw, error: error)
                showGenerationError(friendly)
            }
        }
    }

    // MARK: - @MainActor state mutation helpers

    @MainActor
    private func finishGeneration(
        response: GenerateResponse,
        record: GenerationRecord,
        capturedAuthStore: AuthStore,
        capturedModelContext: ModelContext
    ) {
        capturedModelContext.insert(record)
        do {
            try capturedModelContext.save()
        } catch {
            DebugLog.shared.log(.error, .llm, "modelContext.save() failed", details: error.localizedDescription)
        }
        if capturedAuthStore.isGuest {
            capturedAuthStore.incrementGuestCount()
        }
        generateTask = nil
        isGenerating = false
        // 单一跳转触发点：body 顶层 `if let record = generatedRecord` 条件渲染切换到 ResultView。
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

    /// 把底层网络/解析错误转成用户能直接看懂的中文短句。
    /// 原文（raw）已经写入 DebugLog，这里只影响 alert 显示。
    private static func friendlyErrorMessage(raw: String, error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut:
                return "网络超时，请检查 LLM 服务可达性或更换网络"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "无法连接到 LLM 服务，请到 设置 → 大模型 检查 URL"
            case .notConnectedToInternet:
                return "当前无网络连接"
            default:
                break
            }
        }
        if raw.contains("HTTP 401") || raw.contains("HTTP 403") {
            return "API Key 无效，请到 设置 → 大模型 检查"
        }
        if raw.contains("HTTP 429") {
            return "调用过于频繁，请稍后再试"
        }
        if raw.contains("HTTP 5") {
            return "LLM 服务异常，请稍后再试"
        }
        if raw.contains("URL / Key / Model 三件套未配齐") {
            return "尚未配置大模型，请到 设置 → 大模型 填写 URL/Key/Model"
        }
        if raw.contains("API URL 无效") {
            return "LLM URL 格式有误，请到 设置 → 大模型 修正"
        }
        if raw.contains("未返回合法 JSON") || raw.contains("响应缺少") || raw.contains("非 UTF-8") {
            return "模型返回格式异常，请换一个模型或重试"
        }
        return raw
    }

    // (batch generate removed)
}
