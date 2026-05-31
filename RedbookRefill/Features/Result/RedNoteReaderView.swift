//
//  RedNoteReaderView.swift
//  RedPulse
//
//  iPhone 模拟器 · 三 Tab（同级）：
//   内容导航 → 小红书发现页 2 列瀑布流（含当前生成 + 历史记录）
//   内容预览 → 小红书文章详情页（点击导航卡片时切换内容）
//   AI 诊断 → 和内容预览同一页面，评论区与 Agent 对话
//

import SwiftUI
import AVKit
import SwiftData

private enum ReaderTab: String, CaseIterable {
    case nav = "内容导航"
    case preview = "内容预览"
    case diagnose = "AI诊断"
}

struct RedNoteReaderView: View {
    /// 当前刚生成的记录（默认预览内容）
    let currentRecord: GenerationRecord?
    let noteTitle: String
    let content: String
    let tags: [String]
    let imageUrls: [String]
    let videoUrl: String?
    /// Toggle between image preview and video preview
    @State private var showVideo: Bool = false
    /// Current image index for multi-image browsing
    @State private var currentImageIndex: Int = 0
    let adType: String
    var currentRecordId: UUID? = nil
    var isDiagnosing: Bool = false
    var onSendComment: ((String) async -> Void)? = nil
    var onApplySuggestion: ((NoteComment) -> Void)? = nil
    var onIgnoreSuggestion: ((NoteComment) -> Void)? = nil
    var onStartDiagnose: (() -> Void)? = nil
    var triggerDiagnose: Bool = false

    @State private var selectedTab: ReaderTab = .preview
    @State private var slotPosition: Int = 0
    @State private var loadedImages: [Int: Image] = [:]
    @State private var newCommentText: String = ""
    @State private var isSending: Bool = false
    /// 用户在导航页点中的历史记录（非 nil 时预览页展示该记录）
    @State private var activeRecord: GenerationRecord? = nil

    @Query(sort: \GenerationRecord.createdAt, order: .reverse) private var history: [GenerationRecord]
    @Query(sort: \NoteComment.createdAt, order: .forward) private var allComments: [NoteComment]
    private var liveComments: [NoteComment] {
        let rid = activeRecord?.id ?? currentRecordId
        guard let rid else { return [] }
        return allComments.filter { $0.recordId == rid }
    }

    // 当前预览用的数据源
    private var displayTitle: String { activeRecord?.noteTitle ?? noteTitle }
    private var displayContent: String { activeRecord?.content ?? content }
    private var displayTags: [String] { activeRecord?.tags ?? tags }
    private var displayImageUrls: [String] { activeRecord?.imageUrls ?? imageUrls }
    private var displayAdType: String { activeRecord?.adType ?? adType }

    private let pw: CGFloat = 375; private let ph: CGFloat = 812; private let pr: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let s = min((geo.size.height - 20) / ph, (geo.size.width - 60) / pw, 1.0)
            phoneFrame
                .scaleEffect(s)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onChange(of: triggerDiagnose) { _, new in
            if new {
                selectedTab = .preview
                onStartDiagnose?()
            }
        }
        .task { await preloadImages() }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ReaderTab.allCases, id: \.self) { tab in
                Button {
                    if tab == .diagnose {
                        selectedTab = .preview
                        onStartDiagnose?()
                    } else { selectedTab = tab }
                } label: {
                    HStack(spacing: 4) {
                        if tab == .diagnose {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: isActive(tab) ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == .diagnose ? (isActive(tab) ? Color.brand : Color.brand.opacity(0.7)) : (isActive(tab) ? Color.brand : Color.ink3))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(tab == .diagnose ? (isActive(tab) ? Color.brandSoft : Color.brandSoft.opacity(0.4)) : (isActive(tab) ? Color.brandSoft : Color.clear), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private func isActive(_ tab: ReaderTab) -> Bool {
        switch tab {
        case .nav:      return selectedTab == .nav
        case .preview:  return selectedTab == .preview
        case .diagnose: return selectedTab == .preview && triggerDiagnose
        }
    }

    // MARK: - Phone frame

    private var phoneFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: pr + 6, style: .continuous)
                .fill(Color(white: 0.1)).frame(width: pw + 16, height: ph + 16)
            VStack(spacing: 0) {
                Capsule().fill(Color.black).frame(width: 110, height: 30).padding(.top, 10)
                tabBar.padding(.top, 8)
                phoneScreen.frame(width: pw, height: ph - 108)
                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.25))
                    .frame(width: 130, height: 5).padding(.bottom, 8)
            }
            .frame(width: pw, height: ph).background(Color.bg)
            .clipShape(RoundedRectangle(cornerRadius: pr, style: .continuous))
        }
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 14)
    }

    @ViewBuilder
    private var phoneScreen: some View {
        switch selectedTab {
        case .nav:      discoverFeed
        case .preview:  articlePage
        case .diagnose: articlePage
        }
    }

    // MARK: ── 内容导航 ──

    private var discoverFeed: some View {
        VStack(spacing: 0) {
            HStack {
                Text("发现").font(Typography.sectionTitle).foregroundStyle(Color.ink)
                Spacer()
                Button { slotPosition = (slotPosition + 1) % 4 } label: {
                    Image(systemName: "shuffle").font(.system(size: 15)).foregroundStyle(Color.brand)
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Rectangle().fill(Color.separator).frame(height: BorderWidth.hairline)

            ScrollView {
                let items = buildFeedItems()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        feedCard(item: item, isOurs: idx == slotPosition)
                            .onTapGesture {
                                if let r = item.record { activeRecord = r }
                                selectedTab = .preview
                            }
                    }
                }.padding(10)
            }
        }
    }

    private struct FeedItem { let image: Image?; let title: String; let user: String; let likes: String; let url: String?; let record: GenerationRecord? }

    private func buildFeedItems() -> [FeedItem] {
        // 取前 5 条历史记录（含图片的优先），加上当前生成 = 共 6 条
        let histItems = history.prefix(5).map { h in
            FeedItem(image: nil, title: h.noteTitle, user: "历史记录", likes: "\(max(0, h.hotScore))", url: h.imageUrls.first, record: h)
        }
        // 当前生成卡片
        let our = FeedItem(image: loadedImages[0], title: noteTitle, user: "小红书用户", likes: "1.2k", url: imageUrls.first, record: currentRecord)

        var items: [FeedItem] = [our] + histItems
        // 用 shuffle 按钮循环换位（只在当前生成和历史之间切换）
        if slotPosition > 0 && !items.isEmpty {
            let idx = min(slotPosition, items.count - 1)
            items.swapAt(0, idx)
        }
        return items
    }

    private func feedCard(item: FeedItem, isOurs: Bool) -> some View {
        let w = (pw - 32) / 2
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let img = item.image {
                    img.resizable().aspectRatio(contentMode: .fill).frame(width: w, height: w * 1.2).clipped()
                } else if let urlStr = item.url, let url = URL.safeURL(from: urlStr) {
                    // 历史记录配图用 AsyncImage 异步加载
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let i): i.resizable().aspectRatio(contentMode: .fill).frame(width: w, height: w * 1.2).clipped()
                        case .failure: placeholderBg(isOurs: isOurs).frame(width: w, height: w * 1.2)
                        case .empty: placeholderBg(isOurs: isOurs).frame(width: w, height: w * 1.2).overlay(ProgressView().scaleEffect(0.5))
                        @unknown default: placeholderBg(isOurs: isOurs).frame(width: w, height: w * 1.2)
                        }
                    }
                } else {
                    placeholderBg(isOurs: isOurs).frame(width: w, height: w * 1.2)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                Text(item.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(2).padding(8)
            }.clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 4) {
                Circle().fill(Color.surfaceMuted).frame(width: 16, height: 16)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(Color.ink4))
                Text(item.user).font(.system(size: 12)).foregroundStyle(Color.ink3).lineLimit(1)
                Spacer()
                Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(Color.ink4)
                Text(item.likes).font(.system(size: 13)).foregroundStyle(Color.ink4)
            }.padding(.horizontal, 6).padding(.vertical, 6)
        }
        .background(Color.surface).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(isOurs ? RoundedRectangle(cornerRadius: 10).stroke(Color.brand, lineWidth: 2) : nil)
    }

    @ViewBuilder
    private func placeholderBg(isOurs: Bool) -> some View {
        RoundedRectangle(cornerRadius: 0).fill(
            isOurs ? AnyShapeStyle(LinearGradient(colors: [Color.brand.opacity(0.7), Color.brand.opacity(0.2)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Color.surfaceMuted)
        )
    }

    // MARK: ── 内容预览 / AI诊断 ──

    private var articlePage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    userBar
                    imageArea
                    interactionBar
                    titleArea
                    bodyArea
                    tagsArea
                    metaLine
                    commentDivider
                    commentSection
                }
            }
            .onChange(of: triggerDiagnose) { _, new in
                if new { withAnimation { proxy.scrollTo("comments", anchor: .top) } }
            }
            .onChange(of: activeRecord?.id) { _, _ in
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    private var userBar: some View {
        HStack(spacing: 8) {
            Circle().fill(LinearGradient(colors: [Color.brand, Color.brand.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text(activeRecord != nil ? "历史记录" : "小红书用户").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.ink)
                Text(formattedNow).font(.system(size: 12)).foregroundStyle(Color.ink4)
            }
            Spacer()
            Text("+ 关注").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.brand)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .overlay(Capsule().stroke(Color.brand, lineWidth: 0.5))
        }.padding(.horizontal, 12).padding(.vertical, 8).id("top")
    }

    private var imageArea: some View {
        VStack(spacing: 4) {
            // Image / Video toggle (only when both exist)
            if let _ = URL.safeURL(from: videoUrl ?? ""), !displayImageUrls.isEmpty {
                HStack(spacing: 2) {
                    Spacer()
                    Button { showVideo = false } label: {
                        Text("图片").font(.system(size: 11, weight: showVideo ? .regular : .semibold))
                            .foregroundStyle(showVideo ? Color.ink3 : Color.brand)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(showVideo ? Color.clear : Color.brandSoft)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                    Button { showVideo = true } label: {
                        Text("视频").font(.system(size: 11, weight: showVideo ? .semibold : .regular))
                            .foregroundStyle(showVideo ? Color.brand : Color.ink3)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(showVideo ? Color.brandSoft : Color.clear)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            // Content: show video, or the Nth image, or empty state
            if showVideo, let vid = videoUrl, let url = URL.safeURL(from: vid) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: pw, height: pw * 450 / 375)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !displayImageUrls.isEmpty, currentImageIndex < displayImageUrls.count,
                      let url = URL.safeURL(from: displayImageUrls[currentImageIndex]) {
                // Current image with swipe + nav arrows
                ZStack(alignment: .bottom) {
                    AsyncImage(url: url) { p in
                        if case .success(let i) = p {
                            i.resizable().aspectRatio(contentMode: .fill).frame(width: pw, height: pw * 420 / 375).clipped()
                        }
                    }
                    // Drag/swipe to switch images
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                let threshold: CGFloat = 30
                                if value.translation.width < -threshold {
                                    // Swipe left → next
                                    withAnimation { currentImageIndex = (currentImageIndex + 1) % displayImageUrls.count }
                                } else if value.translation.width > threshold {
                                    // Swipe right → previous
                                    withAnimation { currentImageIndex = (currentImageIndex - 1 + displayImageUrls.count) % displayImageUrls.count }
                                }
                            }
                    )

                    // Left/right arrows when multiple images
                    if displayImageUrls.count > 1 {
                        HStack {
                            Button {
                                currentImageIndex = (currentImageIndex - 1 + displayImageUrls.count) % displayImageUrls.count
                            } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                currentImageIndex = (currentImageIndex + 1) % displayImageUrls.count
                            } label: {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                    }
                }

                // Page dots
                if displayImageUrls.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<displayImageUrls.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentImageIndex ? Color.brand : Color.ink4)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.bottom, 4)
                }
            } else if let img = loadedImages[0], activeRecord == nil {
                img.resizable().aspectRatio(contentMode: .fill).frame(width: pw, height: pw * 420 / 375).clipped()
            } else {
                Rectangle().fill(Color.surfaceMuted).frame(width: pw, height: pw * 0.45)
                    .overlay(Text("暂无配图").font(.system(size: 13)).foregroundStyle(Color.ink4))
            }
        }
    }

    private var interactionBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) { Image(systemName: "heart"); Text("1.2k") }
            HStack(spacing: 3) { Image(systemName: "star"); Text("320") }
            HStack(spacing: 3) { Image(systemName: "message"); Text("\(88 + liveComments.count)") }
            Spacer()
            Image(systemName: "square.and.arrow.up")
        }.font(.system(size: 13)).foregroundStyle(Color.ink2).padding(.horizontal, 12).padding(.top, 10)
    }

    private var titleArea: some View {
        Text(displayTitle).font(Typography.sectionTitle).foregroundStyle(Color.ink)
            .padding(.horizontal, 12).padding(.top, 12)
    }

    private var bodyArea: some View {
        Text(displayContent).font(.system(size: 15)).foregroundStyle(Color.ink).lineSpacing(7)
            .padding(.horizontal, 12).padding(.top, 6)
    }

    private var tagsArea: some View {
        Group {
            if !displayTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(displayTags, id: \.self) { t in
                            Text("#\(t)").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(red: 0.2, green: 0.45, blue: 0.9))
                        }
                    }.padding(.horizontal, 12)
                }.padding(.top, 10)
            }
        }
    }

    private var metaLine: some View {
        Text("\(formattedNow) · RedPulse AI · IP 属地：广东")
            .font(.system(size: 12)).foregroundStyle(Color.ink4)
            .padding(.horizontal, 12).padding(.top, 12)
    }

    private var commentDivider: some View {
        Rectangle().fill(Color.separator).frame(height: BorderWidth.hairline)
            .padding(.top, 18).padding(.horizontal, 12)
    }

    // MARK: - 评论区

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("评论 \(liveComments.count + 88)").font(Typography.label).foregroundStyle(Color.ink)
                if isDiagnosing { HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("AI 分析…").font(.system(size: 12)).foregroundStyle(Color.ink4) } }
                Spacer()
            }
            commentRow(avatar: "😊", name: "美妆控小A", body: "这个也太好用了吧！种草了种草了🌿", time: "2小时前", likes: "32", isAI: false)
            ForEach(liveComments) { c in
                commentRow(avatar: c.role == .ai ? "🤖" : "👤", name: c.authorName, body: c.body,
                           time: relativeTime(c.createdAt), likes: "", isAI: c.role == .ai,
                           suggestion: c.suggestion, suggestionStatus: c.suggestionStatus, comment: c)
            }
            commentRow(avatar: "💫", name: "护肤小白", body: "油皮可以用吗？求回复～", time: "1天前", likes: "5", isAI: false)
            commentInput
        }.padding(12)
    }

    private var commentInput: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.surfaceMuted).frame(width: 28, height: 28)
                .overlay(Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.ink4))
            TextField("和 AI 聊聊怎么改…", text: $newCommentText).textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 7).background(Color.surfaceMuted, in: Capsule())
            Button {
                let t = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty, let s = onSendComment, !isSending else { return }
                isSending = true; newCommentText = ""
                Task { await s(t); await MainActor.run { isSending = false } }
            } label: {
                Text("发送").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.brand)
            }
        }.id("comments")
    }

    @ViewBuilder
    private func commentRow(avatar: String, name: String, body: String, time: String, likes: String, isAI: Bool,
                            suggestion: NoteCommentSuggestion? = nil, suggestionStatus: NoteCommentSuggestionStatus? = nil,
                            comment: NoteComment? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(avatar).font(.system(size: 16)).frame(width: 28, height: 28).background(Color.surfaceMuted, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(isAI ? Color.brand : Color.ink2)
                    if suggestionStatus == .applied { Text("已应用").font(.system(size: 9)).foregroundStyle(Color.success).padding(.horizontal, 4).padding(.vertical, 1).background(Color.successBg, in: Capsule()) }
                    Spacer()
                    if !likes.isEmpty { Text(likes).font(.system(size: 12)).foregroundStyle(Color.ink4); Image(systemName: "heart").font(.system(size: 12)).foregroundStyle(Color.ink4) }
                }
                Text(body).font(.system(size: 13)).foregroundStyle(Color.ink).lineSpacing(3)
                HStack(spacing: 8) {
                    Text(time).font(.system(size: 12)).foregroundStyle(Color.ink4)
                    if isAI, let c = comment, suggestion != nil, suggestionStatus == .pending {
                        Button { onApplySuggestion?(c) } label: {
                            Text("应用建议").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.brand)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.brandSoft, in: Capsule())
                        }.buttonStyle(.plain)
                        Button { onIgnoreSuggestion?(c) } label: {
                            Text("忽略").font(.system(size: 12)).foregroundStyle(Color.ink3)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var formattedNow: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }

    private func relativeTime(_ date: Date) -> String {
        let i = Date().timeIntervalSince(date)
        if i < 60 { return "刚刚" }
        if i < 3600 { return "\(Int(i/60)) 分钟前" }
        if i < 86400 { return "\(Int(i/3600)) 小时前" }
        let f = DateFormatter(); f.dateFormat = "MM-dd"; return f.string(from: date)
    }

    private func preloadImages() async {
        for (idx, urlStr) in imageUrls.enumerated() {
            guard let url = URL.safeURL(from: urlStr), let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            #if canImport(UIKit)
            if let ui = UIImage(data: data) { await MainActor.run { loadedImages[idx] = Image(uiImage: ui) } }
            #elseif canImport(AppKit)
            if let ns = NSImage(data: data) { await MainActor.run { loadedImages[idx] = Image(nsImage: ns) } }
            #endif
        }
    }
}
