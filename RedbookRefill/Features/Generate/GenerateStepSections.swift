//
//  GenerateStepSections.swift
//  RedPulse
//
//  Step 1–4 sub-sections for GenerateView.
//  Extracted from the original 1272-line GenerateView to improve readability.
//

import SwiftUI
import SwiftData

// MARK: - Step 1: Product Quick Select

struct GenerateStepStep1Product: View {
    @Environment(CoachMarkManager.self) private var coachMarkManager
    @Environment(Repository.self) private var repository
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]

    @Binding var selectedProduct: Product?
    @Binding var keyword: String
    @Binding var isGenerating: Bool

    @ScaledMetric private var thumbSize: CGFloat = 72
    @ScaledMetric private var checkmarkSize: CGFloat = 16
    @ScaledMetric private var checkBgSize: CGFloat = 18
    @ScaledMetric private var thumbFontSize: CGFloat = 12

    private var adaptiveThumbSize: CGFloat {
        max(thumbSize, Adaptive.thumbSize)
    }

    var body: some View {
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
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Product Thumb Strip

    private static let quickSelectLimit = 6

    private var productThumbStrip: some View {
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
                           let img = loadThumbnail(path: firstPath) {
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

    private func loadThumbnail(path: String) -> Image? {
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

    // MARK: - Step Badge

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
}

// MARK: - Step 2: Ad Type Selection

struct GenerateStepStep2AdType: View {
    @Binding var selectedAdType: AdType

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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                stepBadge(2)
                Text("广告类型").editorialLabel()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(AdType.allCases) { type in
                    let isSelected = selectedAdType == type
                    let info = infoForAdType(type)
                    adTypeButton(type: type, isSelected: isSelected, info: info)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private func adTypeButton(type: AdType, isSelected: Bool, info: (icon: String, desc: String)) -> some View {
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

// MARK: - Step 3: Keyword Input

struct GenerateStepStep3Keyword: View {
    @Environment(CoachMarkManager.self) private var coachMarkManager
    @Environment(Repository.self) private var repository
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]

    @Binding var keyword: String
    @Binding var showStep3Tip: Bool
    @Binding var selectedSuggestions: Set<String>
    @Binding var trendingKeywords: [String]
    @Binding var isLoadingTrending: Bool
    @Binding var showInspirationPicker: Bool
    @Binding var inspirationPickerType: InspirationType
    @Binding var trendingKeywordsToken: Int

    @State private var keywordEditorText: String = ""

    var body: some View {
        let isCollapsed = keywordCollapsed
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { keywordCollapsed = false }
                    else { keywordCollapsed = true }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    stepBadge(3, active: !isCollapsed)
                    Text("产品关键词").editorialLabel()
                    Spacer()
                    if !isCollapsed {
                        if isLoadingTrending {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                trendingKeywordsToken += 1
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.brand)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
                    inspirationButton(type: .keyword)

                    keywordInputArea
                        .background(Color.surfaceMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(Color.border, lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    if showStep3Tip {
                        step3TipView
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

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

    @AppStorage("keyword_collapse") private var keywordCollapsed = false

    private var keywordInputArea: some View {
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
    }

    private var step3TipView: some View {
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
    }

    private func inspirationButton(type: InspirationType) -> some View {
        Button {
            inspirationPickerType = type
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
    }

    // MARK: - Step Badge

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

    // MARK: - Trending Keywords

    private var trendingKeywordsGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("热门关键词").editorialLabel()
                Spacer()
                if trendingKeywords.isEmpty && !isLoadingTrending {
                    ProgressView().controlSize(.small)
                }
            }

            if trendingKeywords.isEmpty && !isLoadingTrending {
                Text("暂无热门关键词，请刷新")
                    .font(Typography.caption)
                    .foregroundStyle(Color.ink4)
            } else {
                FlowLayout(spacing: Spacing.sm) {
                    ForEach(trendingKeywords, id: \.self) { item in
                        let isSelected = selectedSuggestions.contains(item)
                        keywordChip(item: item, isSelected: isSelected)
                    }
                }
            }
        }
    }

    private func keywordChip(item: String, isSelected: Bool) -> some View {
        Button {
            HapticManager.lightImpact()
            withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                if isSelected {
                    selectedSuggestions.remove(item)
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
