import SwiftUI
import SwiftData
import AVKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Day Section Model

/// 历史记录按"日"分组：每天一个 section，section 头展示"今天 / 昨天 / yyyy.MM.dd"。
struct HistoryDaySection: Identifiable {
    /// `yyyy-MM-dd` 字符串，同时作为折叠状态的稳定 key。
    let id: String
    let date: Date
    let records: [GenerationRecord]

    /// section 头展示文案：今天 / 昨天 / 2026.05.17（周一）
    var displayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return Self.headerFormatter.string(from: date)
    }

    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.MM.dd EEE"
        return f
    }()
}

// MARK: - HistoryView

struct HistoryView: View {
    @Environment(Repository.self) private var repository
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \GenerationRecord.createdAt, order: .reverse) private var allRecords: [GenerationRecord]

    @State private var showClearAlert = false
    @State private var searchText: String = ""
    /// 广告类型筛选：nil = 全部，否则匹配 record.adType。
    @State private var adTypeFilter: String? = nil
    /// 折叠的日期集合（key = `yyyy-MM-dd`）；默认全展开。
    @State private var collapsedDays: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sizeClass == .regular {
                Text("历史记录")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xs)
            }

            if !allRecords.isEmpty {
                searchField
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)
                adTypeFilterBar
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.bottom, Spacing.sm)
            }
            if allRecords.isEmpty {
                emptyState
            } else {
                recordList
            }
        }
        .background(Color.bg.ignoresSafeArea())
        #if os(iOS)
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.large)
        #endif
        .alert("清空全部记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                repository.clearAllRecords()
            }
        } message: {
            Text("确定要清空所有生成记录吗？此操作不可恢复。")
        }
    }

    // MARK: - Filtering & Grouping

    /// 应用搜索过滤 + 广告类型筛选后的记录。
    private var filteredRecords: [GenerationRecord] {
        var result = allRecords

        // 广告类型筛选
        if let filter = adTypeFilter {
            result = result.filter { $0.adType == filter }
        }

        // 搜索文本筛选
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return result }
        let lower = q.lowercased()
        return result.filter { r in
            if r.noteTitle.lowercased().contains(lower) { return true }
            if r.content.lowercased().contains(lower) { return true }
            if r.inputKeyword.lowercased().contains(lower) { return true }
            if let hint = r.keywordHint, hint.lowercased().contains(lower) { return true }
            if r.adType.lowercased().contains(lower) { return true }
            if r.tags.contains(where: { $0.lowercased().contains(lower) }) { return true }
            return false
        }
    }

    /// 按天分组：每天一个 section，按日期倒序排列。
    private var sections: [HistoryDaySection] {
        let cal = Calendar.current
        var buckets: [String: (date: Date, records: [GenerationRecord])] = [:]
        for r in filteredRecords {
            let day = cal.startOfDay(for: r.createdAt)
            let key = Self.keyFormatter.string(from: day)
            if buckets[key] == nil {
                buckets[key] = (day, [r])
            } else {
                buckets[key]?.records.append(r)
            }
        }
        return buckets
            .map { (key, v) in HistoryDaySection(id: key, date: v.date, records: v.records) }
            .sorted { $0.date > $1.date }
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.brandSoft)
                    .frame(width: 100, height: 100)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.brand)
            }
            Text("还没有生成记录")
                .font(Typography.sectionTitle)
                .foregroundStyle(Color.ink)
            Text("去「生成」页创建你的第一篇小红书笔记")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)
            Text("⌘1 快速跳转")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.ink4)
                .padding(.top, Spacing.xs)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Ad Type Filter Bar

    /// 广告类型筛选胶囊栏，横向滚动。
    private var adTypeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                // "全部" 胶囊
                Button {
                    HapticManager.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        adTypeFilter = nil
                    }
                } label: {
                    Text("全部")
                        .font(.system(size: 13, weight: adTypeFilter == nil ? .semibold : .medium))
                        .foregroundStyle(adTypeFilter == nil ? Color.white : Color.ink2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(adTypeFilter == nil ? Color.brand : Color.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(adTypeFilter == nil ? Color.clear : Color.border, lineWidth: BorderWidth.hairline)
                        )
                }
                .buttonStyle(.plain)

                // 各广告类型胶囊
                ForEach(AdType.allCases) { adType in
                    Button {
                        HapticManager.lightImpact()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if adTypeFilter == adType.rawValue {
                                adTypeFilter = nil // 再次点击取消筛选
                            } else {
                                adTypeFilter = adType.rawValue
                            }
                        }
                    } label: {
                        Text(adType.displayName)
                            .font(.system(size: 13, weight: adTypeFilter == adType.rawValue ? .semibold : .medium))
                            .foregroundStyle(adTypeFilter == adType.rawValue ? Color.white : Color.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(adTypeFilter == adType.rawValue ? Color.brand : Color.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(adTypeFilter == adType.rawValue ? Color.clear : Color.border, lineWidth: BorderWidth.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Record List

    // MARK: - Inline search bar

    /// 内嵌搜索框（替代 .searchable，避免 ZStack 常驻 view 时把搜索框
    /// 漏到顶部 window toolbar 形成"全局搜索"假象）。仅作用于历史列表。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink3)
            TextField("搜标题 / 正文 / 标签 / 关键词", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink3)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
    }

    @ViewBuilder
    private var recordList: some View {
        if sections.isEmpty {
            // 有记录但搜索无结果
            VStack(spacing: Spacing.md) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.ink4)
                Text("没有匹配「\(searchText)」的记录")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink3)
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            let columns = [
                GridItem(.adaptive(minimum: 300), spacing: Spacing.md)
            ]
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            sectionHeader(section)
                            
                            if !collapsedDays.contains(section.id) {
                                LazyVGrid(columns: columns, spacing: Spacing.md) {
                                    ForEach(section.records) { record in
                                        NavigationLink {
                                            ResultView(record: record, fromHistory: true)
                                        } label: {
                                            RecordCard(record: record)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                HapticManager.warning()
                                                repository.deleteRecord(record)
                                            } label: {
                                                Label("删除这条记录", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, Adaptive.horizontalPageMargin)
                    }
                    
                    if searchText.isEmpty {
                        Button {
                            showClearAlert = true
                        } label: {
                            Text("清空所有历史记录")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.brand)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.brandSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.lg)
                    }
                }
                .padding(.top, Spacing.md)
            }
            .background(Color.bg)
        }
    }

    // MARK: - Section Header (tap to collapse)

    private func sectionHeader(_ section: HistoryDaySection) -> some View {
        let isCollapsed = collapsedDays.contains(section.id)
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                if isCollapsed {
                    collapsedDays.remove(section.id)
                } else {
                    collapsedDays.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brand)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(section.displayLabel)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text("\(section.records.count) 篇")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.brandSoft, in: Capsule())
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Premium Record Card

private struct RecordCard: View {
    let record: GenerationRecord

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: record.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                HStack(spacing: Spacing.sm) {
                    Text(AdType(rawValue: record.adType)?.displayName ?? record.adType)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.brandSoft)
                        .clipShape(Capsule())
                    
                    if record.isEdited {
                        Text("已编辑")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.ink3)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Spacer()
                
                Text(timeString)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.ink4)
            }
            
            Text(record.noteTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
            
            if !record.content.isEmpty {
                Text(record.content)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
            }
            
            if !record.tags.isEmpty || !record.inputKeyword.isEmpty {
                FlowLayout(spacing: Spacing.xs) {
                    if !record.inputKeyword.isEmpty {
                        Text(record.inputKeyword)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.ink3)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    ForEach(record.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.brand)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Spacing.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.015), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Result Detail View

/// 历史记录详情页，与 ResultView 使用一致的视觉结构。
/// 文案区只读；图片区支持选择张数和重新生成。
struct ResultDetailView: View {
    let record: GenerationRecord

    @Environment(\.modelContext) private var modelContext
    @Query private var allProducts: [Product]

    @State private var jimengService = JimengService()
    @State private var imageCount: Int = 1
    @State private var isPreparingPrompts: Bool = false
    @State private var generator: GeneratorProtocol =
        LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()

    /// 优先取本次会话生成的图片；为空回退到 record。
    private var effectiveImageURLs: [String] {
        jimengService.generatedImageURLs.isEmpty ? record.imageUrls : jimengService.generatedImageURLs
    }

    var body: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    titleSection
                    contentSection
                    tagsSection
                    imageSuggestionSection
                    earlyAccessSection
                    optimizationSection
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, Spacing.page)
                .padding(.vertical, Spacing.lg)
                .frame(maxWidth: 920)
                Spacer(minLength: 0)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("记录详情")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - 笔记标题

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("笔记标题").editorialLabel()
                Spacer()
                Text("\(record.noteTitle.count)/20").font(Typography.monoSmall).foregroundStyle(Color.ink3)
            }
            Text(record.noteTitle)
                .font(Typography.bodyEmphasis)
                .foregroundStyle(Color.ink)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .sectionCard()
    }

    // MARK: - 正文

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("正文").editorialLabel()
                Spacer()
                Text("\(record.content.count) 字").font(Typography.monoSmall).foregroundStyle(Color.ink3)
            }
            Text(record.content)
                .font(Typography.body)
                .foregroundStyle(Color.ink)
                .lineSpacing(4)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .sectionCard()
    }

    // MARK: - 标签

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("标签").editorialLabel()
                Spacer()
                Text("\(record.tags.count) 个").font(Typography.monoSmall).foregroundStyle(Color.ink3)
            }
            FlowLayout(spacing: Spacing.sm) {
                ForEach(record.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(Typography.caption)
                        .pillStyle()
                }
            }
        }
        .sectionCard()
    }

    // MARK: - 配图建议

    private var imageSuggestionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("配图建议").editorialLabel()
                Spacer()
                Text("\(record.imageSuggestion.count) 字").font(Typography.monoSmall).foregroundStyle(Color.ink3)
            }
            Text(record.imageSuggestion.isEmpty ? "暂无配图建议" : record.imageSuggestion)
                .font(Typography.body)
                .foregroundStyle(Color.ink)
                .lineSpacing(4)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .sectionCard()
    }

    // MARK: - 抢先体验功能卡片（可交互生图 + 只读视频）

    private var earlyAccessSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text("抢先体验功能").editorialLabel()
                Text("BETA")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.brand, in: Capsule())
                Spacer()
            }

            imageGenSection

            if record.videoUrl != nil {
                Divider()
                videoResultSection
            }
        }
        .sectionCard()
    }

    // MARK: - AI 配图生成（可交互）

    private var imageGenSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Text("AI 配图生成").editorialLabel()
                Spacer()
                if effectiveImageURLs.count > 1 && !jimengService.isGeneratingImage && !isPreparingPrompts {
                    Button {
                        Task { await saveAllImages() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.on.square")
                            Text("全部下载")
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                if !effectiveImageURLs.isEmpty && !jimengService.isGeneratingImage && !isPreparingPrompts {
                    Button {
                        Task { await generateImages() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("重新生成")
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }

            if !jimengService.isConfigValidForImage {
                configMissingHint("请先在「我的 → 大模型配置 → 图片生成」中填写 Ark Key 或 AK/SK + req_key")
            } else if isPreparingPrompts {
                generatingStatus("正在为 \(imageCount) 张图扩出不同的提示词...")
            } else if jimengService.isGeneratingImage {
                generatingStatus(imageCount > 1 ? "正在并行生成 \(imageCount) 张配图..." : "正在生成配图...")
            } else if let error = jimengService.imageError {
                errorHint(error)
            } else if !effectiveImageURLs.isEmpty {
                imageGallery
            } else {
                imagePromptAndButton
            }
        }
    }

    private var imagePromptAndButton: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(record.imagePrompt.isEmpty ? "暂无文生图提示词，请先生成文案" : record.imagePrompt)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(record.imagePrompt.isEmpty ? Color.ink4 : Color.ink3)
                .lineSpacing(2)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !record.imagePrompt.isEmpty {
                referenceImageHint
                imageCountPicker
                Button {
                    Task { await generateImages() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "photo.badge.plus")
                        Text(imageCount > 1 ? "生成 \(imageCount) 张配图" : "生成配图")
                    }
                }
                .buttonStyle(GhostButtonStyle(tint: .brand))
            }
        }
    }

    private var referenceImageHint: some View {
        let count = productReferenceImageCount
        return HStack(spacing: 6) {
            Image(systemName: count > 0 ? "photo.on.rectangle.angled" : "text.bubble")
                .font(.system(size: 13))
            Text(count > 0 ? "将使用 \(count) 张产品图作为参考，AI 会基于产品外观生成配图" : "未上传产品图，将根据提示词直接生成配图")
                .font(.system(size: 13))
        }
        .foregroundStyle(count > 0 ? Color.suggestionBlue : Color.ink3)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(count > 0 ? Color.suggestionBg : Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var imageCountPicker: some View {
        HStack(spacing: Spacing.sm) {
            Text("数量").editorialLabel()
            HStack(spacing: 6) {
                ForEach([1, 2, 3, 4], id: \.self) { n in
                    Button {
                        imageCount = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(imageCount == n ? .white : Color.ink2)
                            .frame(width: 32, height: 28)
                            .background(imageCount == n ? Color.brand : Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .stroke(imageCount == n ? Color.clear : Color.border, lineWidth: BorderWidth.hairline)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            if imageCount > 1 {
                Text("将先扩出 \(imageCount) 个不同 prompt 并行生成")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private var imageGallery: some View {
        let imgWidth: CGFloat = 320
        let imgHeight: CGFloat = 427
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(Array(effectiveImageURLs.enumerated()), id: \.offset) { _, url in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            AsyncImage(url: URL.safeURL(from: url)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: imgWidth, height: imgHeight)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                case .failure:
                                    Rectangle()
                                        .fill(Color.surfaceMuted)
                                        .frame(width: imgWidth, height: imgHeight)
                                        .overlay(
                                            VStack(spacing: Spacing.xs) {
                                                Image(systemName: "photo.badge.exclamationmark")
                                                    .font(.system(size: 22))
                                                Text("加载失败").font(.system(size: 13))
                                            }
                                            .foregroundStyle(Color.ink3)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                case .empty:
                                    Rectangle()
                                        .fill(Color.surfaceMuted)
                                        .frame(width: imgWidth, height: imgHeight)
                                        .overlay(ProgressView())
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .contextMenu {
                                Button {
                                    copyToClipboard(url)
                                } label: {
                                    Label("复制图片链接", systemImage: "link")
                                }
                                Button {
                                    Task { await saveImage(url: url) }
                                } label: {
                                    Label("保存到本地", systemImage: "square.and.arrow.down")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            aiAnnotationResult("图片由AI生成")
        }
    }

    // MARK: - AI 视频（只读）

    private var videoResultSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("AI 视频生成").editorialLabel()
            if let videoUrl = record.videoUrl, let url = URL.safeURL(from: videoUrl) {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 480, maxHeight: 640)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(Color.border, lineWidth: BorderWidth.hairline)
                    )
            }
            aiAnnotationResult("视频由AI生成")
        }
    }

    // MARK: - 优化建议

    private var optimizationSection: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.suggestionBlue)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("优化建议").editorialLabel()
                Text(record.suggestion.isEmpty ? "暂无优化建议" : record.suggestion)
                    .font(Typography.body)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .background(Color.suggestionBg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.suggestionBorder, lineWidth: BorderWidth.hairline)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.suggestionBlue)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.vertical, 8)
                .padding(.leading, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Image Generation

    private func generateImages() async {
        let n = max(1, min(imageCount, 4))
        var prompts: [String] = [record.imagePrompt]
        if n > 1, let llm = generator as? LLMTextGenerator {
            isPreparingPrompts = true
            do {
                prompts = try await llm.regenerateImagePrompts(
                    count: n,
                    basePrompt: record.imagePrompt,
                    keyword: record.inputKeyword,
                    product: nil,
                    adType: AdType(rawValue: record.adType) ?? .feedAd,
                    imageSuggestion: record.imageSuggestion
                )
            } catch {
                prompts = Array(repeating: record.imagePrompt, count: n)
            }
            isPreparingPrompts = false
        } else if n > 1 {
            prompts = Array(repeating: record.imagePrompt, count: n)
        }
        let referenceImages = productReferenceImagesData()
        await jimengService.generateImages(prompts: prompts, referenceImagesData: referenceImages)
        if !jimengService.generatedImageURLs.isEmpty {
            record.imageUrls = jimengService.generatedImageURLs
            try? modelContext.save()
        }
    }

    private var productReferenceImageCount: Int {
        guard let pid = record.productId,
              let product = allProducts.first(where: { $0.id == pid }) else { return 0 }
        let all = product.imagePaths + product.styleImagePaths
        guard !all.isEmpty else { return 0 }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return 0 }
        return all.filter { relative in
            !relative.isEmpty && fm.fileExists(atPath: docs.appendingPathComponent(relative).path)
        }.count
    }

    private func productReferenceImagesData() -> [Data] {
        guard let pid = record.productId,
              let product = allProducts.first(where: { $0.id == pid }) else { return [] }
        let relatives = product.imagePaths + product.styleImagePaths
        guard !relatives.isEmpty else { return [] }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var result: [Data] = []
        for relative in relatives where !relative.isEmpty {
            let url = docs.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url) else { continue }
            result.append(data)
        }
        return result
    }

    private func saveImage(url: String) async {
        guard let imageURL = URL.safeURL(from: url) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            #if os(macOS)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "redbook-image.\(imageURL.pathExtension.isEmpty ? "png" : imageURL.pathExtension)"
                if panel.runModal() == .OK, let dest = panel.url {
                    try? data.write(to: dest)
                }
            }
            #elseif canImport(UIKit)
            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            #endif
        } catch { }
    }

    private func saveAllImages() async {
        let urls = effectiveImageURLs
        guard !urls.isEmpty else { return }
        #if os(macOS)
        let dest: URL? = await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "选择保存图片的文件夹"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "保存到此处"
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let dir = dest else { return }
        for (idx, url) in urls.enumerated() {
            guard let remote = URL.safeURL(from: url) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                let ext = remote.pathExtension.isEmpty ? "png" : remote.pathExtension
                try data.write(to: dir.appendingPathComponent("redbook-image-\(idx + 1).\(ext)"))
            } catch { }
        }
        #elseif canImport(UIKit)
        for url in urls {
            guard let remote = URL.safeURL(from: url) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                if let img = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                }
            } catch { }
        }
        #endif
    }

    // MARK: - Shared helpers

    private func configMissingHint(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "gearshape.2")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink3)
            Text(message)
                .font(Typography.bodySmall)
                .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func generatingStatus(_ text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().scaleEffect(0.8)
            Text(text)
                .font(Typography.bodySmall)
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Spacing.lg)
    }

    private func errorHint(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.brand)
            Text(message)
                .font(Typography.bodySmall)
                .foregroundStyle(Color.brand)
        }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit) && !os(macOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func aiAnnotationResult(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 13))
        }
        .foregroundStyle(Color.ink4)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.surfaceMuted, in: Capsule())
        .padding(.top, Spacing.sm)
    }
}

// MARK: - Section Card Modifier

private extension View {
    func sectionCard() -> some View {
        padding(Spacing.lg)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.border, lineWidth: BorderWidth.thin)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
