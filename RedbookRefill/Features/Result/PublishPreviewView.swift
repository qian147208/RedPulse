//
//  PublishPreviewView.swift
//  灵芯
//
//  发布预览：模拟小红书笔记卡片，文案 + 配图 + 视频合在一起预览。
//

import SwiftUI
import AVKit
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct PublishPreviewView: View {
    let noteTitle: String
    let content: String
    let tags: [String]
    let imageUrls: [String]
    let videoUrl: String?
    let adType: String
    /// true 时只渲染卡片本身（不带 ScrollView/导航标题/页面背景），便于嵌入 overlay。
    var chromeless: Bool = false
    /// 预览卡宽度。默认 375 与设计稿一致；嵌进 ResultView 时由调用方按列宽传入。
    /// 最大不超过 420，防止在桌面端卡片过宽。
    var previewWidth: CGFloat = 375

    /// 评论区绑定的 record id。nil 时不渲染评论区（兼容老调用方）
    var recordId: UUID? = nil
    /// AI 正在跑诊断时 true（调用方传入，用于状态展示）
    var isDiagnosing: Bool = false
    /// 用户在评论区按发送时的回调
    var onSendComment: ((String) async -> Void)? = nil
    /// 点 "应用建议" 时回调
    var onApplySuggestion: ((NoteComment) -> Void)? = nil
    /// 点 "忽略" 时回调
    var onIgnoreSuggestion: ((NoteComment) -> Void)? = nil
    /// 点 "让AI帮我点评" 时回调
    var onStartDiagnose: (() -> Void)? = nil
    /// 诊断/回复失败时显示错误信息
    var diagnoseError: String? = nil

    /// 媒体区高度（保持 3:4 竖屏比例）
    private var mediaHeight: CGFloat { previewWidth * 500.0 / 375.0 }
    /// 占位区高度（无图时压缩，避免大片空白）
    private var placeholderHeight: CGFloat { previewWidth * 0.55 }

    @State private var currentMediaIndex = 0
    @State private var loadedImages: [Int: Image] = [:]

    /// 全量评论 + 按 recordId 客户端过滤（量小、简单可靠）
    @Query(sort: \NoteComment.createdAt, order: .forward) private var allComments: [NoteComment]
    private var liveComments: [NoteComment] {
        guard let rid = recordId else { return [] }
        return allComments.filter { $0.recordId == rid }
    }

    @State private var newCommentText: String = ""
    @State private var isSending: Bool = false

    private enum MediaItem: Equatable {
        case video(URL)
        case image(index: Int)
    }

    private var mediaItems: [MediaItem] {
        var items: [MediaItem] = []
        if let video = videoUrl, let url = URL.safeURL(from: video) {
            items.append(.video(url))
        }
        for idx in imageUrls.indices {
            items.append(.image(index: idx))
        }
        return items
    }

    private static let fakeLikeCount = "1.2k"
    private static let fakeStarCount = "320"
    private static let fakeCommentCount = "88"

    var body: some View {
        phoneFrame
            .task { await preloadImages() }
    }

    /// 提前下载图片，让 AsyncImage 能立即命中 URL 缓存
    private func preloadImages() async {
        for (idx, urlStr) in imageUrls.enumerated() {
            guard let url = URL.safeURL(from: urlStr) else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                await MainActor.run {
                    loadedImages[idx] = makeImage(from: data)
                }
            }
        }
    }

    #if canImport(UIKit)
    private func makeImage(from data: Data) -> Image? {
        UIImage(data: data).map { Image(uiImage: $0) }
    }
    #elseif canImport(AppKit)
    private func makeImage(from data: Data) -> Image? {
        NSImage(data: data).map { Image(nsImage: $0) }
    }
    #endif

    // MARK: - Phone frame

    private var phoneFrame: some View {
        VStack(spacing: 0) {
            headerBar
            mediaArea
            engagementBar
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            contentArea
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)

            // 评论区（AI 内容诊断 + 用户回复 mock，下一轮接 LLM）
            Divider()
                .background(Color.separator)
            commentSection
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .id(PublishPreviewView.commentAnchorID)
        }
        .frame(width: previewWidth)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 16, x: 0, y: 6)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.brand, Color.brand.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("小红书用户")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(adTypeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink4)
            }

            Spacer()

            Text("+ 关注")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Color.brand, lineWidth: BorderWidth.hairline)
                )

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.ink2)
                .padding(.leading, Spacing.xs)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var adTypeLabel: String {
        switch adType {
        case "feedAd": return "信息流广告 · 种草笔记"
        case "searchAd": return "搜索广告 · 关键词笔记"
        case "brandCard": return "品牌卡片 · 心智笔记"
        default: return adType
        }
    }

    // MARK: - Media area

    @ViewBuilder
    private var mediaArea: some View {
        let items = mediaItems
        if !items.isEmpty {
            ZStack(alignment: .topTrailing) {
                mediaContent(for: items[safeClamped: currentMediaIndex])

                // 页码 badge：N/Total
                mediaBadge(
                    "\(min(currentMediaIndex, items.count - 1) + 1)/\(items.count)",
                    systemImage: badgeIcon(for: items[safeClamped: currentMediaIndex])
                )
                .padding(8)

                // 左右翻页箭头（>1 时）
                if items.count > 1 {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentMediaIndex = (currentMediaIndex - 1 + items.count) % items.count
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentMediaIndex = (currentMediaIndex + 1) % items.count
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                }
            }
            .frame(width: previewWidth, height: mediaHeight)
            .overlay(alignment: .bottom) {
                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(items.indices, id: \.self) { i in
                            Circle()
                                .fill(i == currentMediaIndex ? Color.white : Color.white.opacity(0.45))
                                .frame(width: 6, height: 6)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        currentMediaIndex = i
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.4), in: Capsule())
                    .padding(.bottom, 12)
                }
            }
        } else {
            // 无媒体
            Rectangle()
                .fill(Color.surfaceMuted)
                .frame(width: previewWidth, height: placeholderHeight)
                .overlay(
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.ink4)
                        Text("请先生成配图")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.ink3)
                        Text("生成图片后将在此处展示")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink4)
                    }
                )
        }
    }

    @ViewBuilder
    private func mediaContent(for item: MediaItem?) -> some View {
        switch item {
        case .video(let url):
            VideoPlayer(player: AVPlayer(url: url))
                .aspectRatio(3/4, contentMode: .fill)
                .frame(width: previewWidth, height: mediaHeight)
                .clipped()
        case .image(let idx):
            if let img = loadedImages[idx] {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: previewWidth, height: mediaHeight)
                    .clipped()
            } else if imageUrls.indices.contains(idx) {
                AsyncImage(url: URL.safeURL(from: imageUrls[idx])) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: previewWidth, height: mediaHeight)
                            .clipped()
                    case .failure:
                        imageErrorPlaceholder
                    case .empty:
                        imageLoadingPlaceholder
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                imageErrorPlaceholder
            }
        case .none:
            imageLoadingPlaceholder
        }
    }

    private func badgeIcon(for item: MediaItem?) -> String {
        switch item {
        case .video: return "video.fill"
        case .image, .none: return "photo.fill"
        }
    }

    // MARK: - Image placeholders

    private var imageLoadingPlaceholder: some View {
        Rectangle()
            .fill(Color.surfaceMuted)
            .frame(width: previewWidth, height: mediaHeight)
            .overlay(
                VStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text("加载中...")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink4)
                }
            )
    }

    private var imageErrorPlaceholder: some View {
        Rectangle()
            .fill(Color.surfaceMuted)
            .frame(width: previewWidth, height: mediaHeight)
            .overlay(
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.ink4)
                    Text("图片加载失败")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink3)
                    Text("链接可能已过期")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ink4)
                }
            )
    }

    private func mediaBadge(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    // MARK: - Engagement bar

    private var engagementBar: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink4)
                Text("说点...")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.surfaceMuted, in: Capsule())

            engagementCountIcon("heart", count: Self.fakeLikeCount)
            engagementCountIcon("star", count: Self.fakeStarCount)
            engagementCountIcon("message", count: Self.fakeCommentCount)
        }
    }

    private func engagementCountIcon(_ systemName: String, count: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.ink2)
            Text(count)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Color.ink2)
        }
    }

    // MARK: - Content area

    /// 根据正文字数动态调整行间距，让短内容更紧凑、长内容不拥挤
    private var contentLineSpacing: CGFloat {
        let count = content.count
        if count <= 60 { return 4 }
        if count <= 200 { return 5 }
        return 6
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !noteTitle.isEmpty {
                HStack(spacing: 6) {
                    Text(noteTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(3)
                    if hasPendingTitleSuggestion {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.brand)
                            .help("AI 给标题留了一条建议")
                    }
                }
            }

            if !content.isEmpty {
                // 用 AttributedString 把 AI 建议引用到的 originalSnippet 标黄高亮
                Text(highlightedContent)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(contentLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.brand)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 3)
                                .background(Color.brandSoft, in: Capsule())
                        }
                    }
                }
                .padding(.top, Spacing.xs)
            }

            // 发布时间 + AI 标注
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("内容由AI生成 · 预览效果")
                    .font(.system(size: 11))
                Spacer()
                Text(formattedNow)
                    .font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(Color.ink4)
            .padding(.top, Spacing.sm)
        }
    }

    private var formattedNow: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }

    // MARK: - Comment section (mock，下一轮接 LLM)

    /// 滚动锚点，让 toolbar 上的 "AI 助手" 按钮可以滚到评论区
    static let commentAnchorID = "preview-comments"

    // MARK: - Inline marker (P1)
    // 在预览卡正文上把 AI 待处理建议引用的 originalSnippet 高亮（黄底 + 红字下划线）
    // 标题如果有待处理建议（kind = .title），在标题旁加 ✨ 小图标提示

    /// 当前 record 上是否有 pending 的标题建议
    private var hasPendingTitleSuggestion: Bool {
        liveComments.contains { c in
            c.role == .ai
                && c.suggestionStatus == .pending
                && c.suggestion?.kind == .title
        }
    }

    /// 正文 AttributedString：对所有 pending 的 body 建议高亮其 originalSnippet
    private var highlightedContent: AttributedString {
        var attr = AttributedString(content)
        let snippets = liveComments.compactMap { c -> String? in
            guard c.role == .ai, c.suggestionStatus == .pending else { return nil }
            guard let s = c.suggestion, s.kind == .body else { return nil }
            guard let snippet = s.originalSnippet?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !snippet.isEmpty else { return nil }
            return snippet
        }
        for snippet in Set(snippets) {
            // 对一段原文可能命中多次，全部都高亮
            var cursor = attr.startIndex
            while cursor < attr.endIndex {
                let remaining = attr[cursor..<attr.endIndex]
                guard let r = remaining.range(of: snippet) else { break }
                attr[r].backgroundColor = Color.yellow.opacity(0.45)
                attr[r].underlineStyle = Text.LineStyle(pattern: .solid, color: Color.brand)
                cursor = r.upperBound
            }
        }
        return attr
    }

    @ViewBuilder
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 顶部标题行
            HStack(spacing: 6) {
                Image(systemName: "message.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ink3)
                Text("评论 \(liveComments.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                if isDiagnosing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("AI 正在分析…")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ink4)
                    }
                } else if let error = diagnoseError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                } else {
                    Text("· AI 在帮你点评")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink4)
                }
                Spacer()
            }

            // 空状态（更紧凑，减少太空感）
            if liveComments.isEmpty && !isDiagnosing {
                Button {
                    onStartDiagnose?()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text("让 AI 帮我点评")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.brand)
                    .padding(.vertical, Spacing.xs)
                    .padding(.horizontal, Spacing.sm)
                    .background(Color.brandSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(liveComments.enumerated()), id: \.element.id) { _, c in
                commentRow(c, isLastAndDiagnosing: isDiagnosing && c === liveComments.last)
            }

            // 用户输入框
            commentInputBar
                .padding(.top, Spacing.xs)
        }
    }

    private func commentRow(_ c: NoteComment, isLastAndDiagnosing: Bool = false) -> some View {
        let isAI = c.role == .ai
        return HStack(alignment: .top, spacing: Spacing.sm) {
            // 头像
            ZStack {
                if isAI {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.brand, Color.brand.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().fill(Color.suggestionBlue)
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(c.authorName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isAI ? Color.brand : Color.suggestionBlue)
                    Text(Self.relativeTime(c.createdAt))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.ink4)

                    if c.suggestionStatus == .applied {
                        Text("· 已应用")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.success)
                    } else if c.suggestionStatus == .ignored {
                        Text("· 已忽略")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.ink4)
                    }
                }

                // Show typing indicator for last AI comment while diagnosing
                if isLastAndDiagnosing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("AI 正在思考…").font(.system(size: 12)).foregroundStyle(Color.ink4)
                    }
                } else {
                    Text(c.body)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isAI && c.suggestion != nil && c.suggestionStatus == .pending {
                    HStack(spacing: 6) {
                        Button {
                            onApplySuggestion?(c)
                        } label: {
                            actionPillLabel(icon: "checkmark.circle.fill", label: "应用建议", kind: .primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(onApplySuggestion == nil)

                        Button {
                            onIgnoreSuggestion?(c)
                        } label: {
                            actionPillLabel(icon: "xmark", label: "忽略", kind: .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(onIgnoreSuggestion == nil)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private enum CommentActionKind { case primary, secondary }

    private func actionPillLabel(icon: String, label: String, kind: CommentActionKind) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            kind == .primary ? Color.brandSoft : Color.surfaceMuted,
            in: Capsule()
        )
        .foregroundStyle(kind == .primary ? Color.brand : Color.ink2)
    }

    private var commentInputBar: some View {
        let canSend = !newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSending
            && onSendComment != nil

        return HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.system(size: 10))
                .foregroundStyle(Color.ink4)
            TextField("说点你想问的…", text: $newCommentText, axis: .horizontal)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.ink)
                .onSubmit { triggerSend() }
                .disabled(onSendComment == nil || isSending)
            Spacer(minLength: 0)
            if isSending {
                ProgressView().controlSize(.mini)
            } else {
                Button(action: triggerSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(canSend ? Color.brand : Color.ink4)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 8)
        .background(Color.surfaceMuted, in: Capsule())
    }

    private func triggerSend() {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let send = onSendComment, !isSending else { return }
        isSending = true
        newCommentText = ""
        Task {
            await send(text)
            await MainActor.run { isSending = false }
        }
    }

    /// "刚刚 / N 分钟前 / N 小时前 / yyyy-MM-dd"
    private static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

private extension Array {
    /// 越界时夹紧到合法范围；空数组返回 nil。
    subscript(safeClamped index: Int) -> Element? {
        guard !isEmpty else { return nil }
        let clamped = Swift.min(Swift.max(index, 0), count - 1)
        return self[clamped]
    }
}

#Preview {
    NavigationStack {
        PublishPreviewView(
            noteTitle: "这个气垫真的绝绝子！",
            content: "姐妹们快冲！这个气垫也太好用了吧，上妆超服帖，完全不卡粉。持妆一整天没问题，油皮亲妈！",
            tags: ["气垫", "底妆推荐", "美妆测评", "平价好物"],
            imageUrls: [],
            videoUrl: nil,
            adType: "feedAd"
        )
    }
}
