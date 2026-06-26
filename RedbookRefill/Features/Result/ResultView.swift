//
//  ResultView.swift
//  灵芯
//
//  结果页 — 三栏/双栏/TAB 自适应布局
//  拆分后作为 orchestrator，实际子组件在 ResultEditorPanels/ResultAITools/ResultLayoutHelpers/ResultRegenHelpers 中。
//

import SwiftUI
import SwiftData
import AVKit

struct ResultView: View {
    // MARK: - Data & Environment
    @Environment(Repository.self) private var repository
    @State private var record: GenerationRecord
    let fromHistory: Bool
    let adType: String?

    @State private var editorFraction: CGFloat = 0.4

    /// Result display mode (edit vs. preview) — used on iPhone
    enum ResultMode: String, CaseIterable {
        case edit = "编辑"
        case preview = "预览"
    }
    // P0-2: 从 @AppStorage 改为 @State —— 状态是 view-scoped 的，不应跨设备/跨 view 持久化。
    // 之前用 @AppStorage 会导致 iPhone 用户切到 preview 后，去 iPad 打开会继承 preview 状态，
    // 但 iPad tripane 模式根本不看 resultMode，造成跨设备状态污染。
    @State private var resultMode: ResultMode = .edit

    enum RightPanelTab: String, CaseIterable {
        case image = "image"
        case video = "video"
    }
    @State private var rightPanelTab: RightPanelTab = .image

    // MARK: - Shared State
    @Environment(\.modelContext) private var modelContext
    @Environment(RegenSession.self) private var regenSession
    @State private var generator: GeneratorProtocol
    @State private var jimengService: AgnesService
    @State private var volcService: VolcengineVideoService
    @State private var selectedText: String = ""
    @State private var showEmojiPicker: Bool = false
    @State private var showAddTag: Bool = false
    @State private var newTagText: String = ""
    @State private var debugMode: Bool = false
    @State private var isGenerating: Bool = false
    @State private var regeneratingField: RegenField? = nil
    @State private var imageCount: Int = 1
    @State private var isPreparingPrompts: Bool = false
    @State private var showPreviewHighlight: Bool = false
    /// 全屏查看小红书预览（RedNoteReaderView）
    @State private var showPhonePreview: Bool = false
    @State private var aiAssistantScrollTrigger: Int = 0

    // MARK: - AI Assistant
    @State private var diagnosticAgent: DiagnosticAgent? = nil
    @State private var triggerDiagnose: Bool = false

    private func handleDiagnose() {
        triggerDiagnose = true
        Task {
            await diagnosticAgent?.diagnose(record: record)
            await MainActor.run {
                triggerDiagnose = false
                if let error = diagnosticAgent?.lastError {
                    popToast(error)
                }
            }
        }
    }

    // MARK: - Copy / Toast / Undo
    @State private var undo: ResultUndoSnapshot? = nil
    @State private var undoCountdown: Int = 5
    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var cloneCreated: Bool = false

    // MARK: - Packaging
    @State private var isPackaging: Bool = false
    @State private var showPackageShareSheet: Bool = false
    @State private var zipURLToShare: URL? = nil

    @State private var allProducts: [Product] = []

    init(record: GenerationRecord, fromHistory: Bool = false, adType: String? = nil) {
        self._record = State(initialValue: record)
        self.fromHistory = fromHistory
        self.adType = adType
        self._generator = State(initialValue: LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator())
        self._jimengService = State(initialValue: AgnesService())
        self._volcService = State(initialValue: VolcengineVideoService())
    }

    // MARK: - Computed

    private var effectiveImageURLs: [String] {
        #if os(macOS)
        return record.imageUrls.filter { URL.safeURL(from: $0) != nil }
        #else
        return record.imageUrls
        #endif
    }

    private var effectiveVideoURL: String? {
        // P0-9: 之前 macOS 分支用 URL.safeURL 过滤 record.videoUrl,
        // 但 URL.safeURL 对 file:///...mp4(本地下载视频)偶尔返回 nil,
        // 导致整个 videoUrl 被设成 nil → RedNoteReaderView 拿不到 videoUrl
        // → 视频按钮点了不切换。
        // 修法:不做这层过滤,直接返回 record.videoUrl,
        // 让 RedNoteReaderView 用 parseLooseURL 自己判断(file:// 路径也能解析)。
        return record.videoUrl
    }

    // MARK: - Layout

    /// Whether to use the 3-pane layout (文案 + drag handle + AI tools).
    /// macOS always uses it. iPad (regular width) uses it. iPhone uses single-column.
    private var shouldUseTripane: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        if #available(iOS 16.0, *) {
            return UITraitCollection.current.horizontalSizeClass == .regular
        }
        return false
        #else
        return true
        #endif
    }

    /// Whether to show the edit/preview segmented picker.
    /// Only shown in single-column mode (iPhone). On wide screens the mode switch is in topToolbar.
    private var shouldShowModePicker: Bool {
        #if os(macOS)
        return false
        #elseif os(iOS)
        if #available(iOS 16.0, *) {
            return UITraitCollection.current.horizontalSizeClass == .compact
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: - Body

    var body: some View {
        content
            // P0-1: 用 .toolbar modifier 替代自建 topToolbar。
            //  - iPhone: 进 navigationBar（大标题 + 操作按钮）
            //  - macOS: 进 window toolbar（不再与系统 toolbar 重复）
            //  - iPad: 走系统原生导航栏
            .toolbar { topToolbarContent }
            .navigationTitle(navigationTitleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .overlay(alignment: .bottom) {
                notificationsOverlay
            }
            .onAppear {
            setupDiagnosticAgent()
            Task {
                allProducts = repository.allProducts()
            }
            // TipKit 自动接管引导 — 各按钮挂 .popoverTip(...)
        }
        .onChange(of: isGenerating) { _, newValue in
            DebugLog.shared.log(.info, .llm, "isGenerating changed", details: "value=\(newValue)")
        }
        .sheet(isPresented: $showPackageShareSheet) {
            if let url = zipURLToShare {
                #if os(iOS)
                PackageShareSheet(items: [url])
                #endif
            }
        }
        .overlay {
            if showPhonePreview {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { showPhonePreview = false }
                    RedNoteReaderView(
                        currentRecord: fromHistory ? nil : record,
                        noteTitle: record.noteTitle,
                        content: record.content,
                        tags: record.tags,
                        imageUrls: effectiveImageURLs,
                        videoUrl: effectiveVideoURL,
                        adType: record.adType,
                        currentRecordId: record.id,
                        isDiagnosing: diagnosticAgent?.isDiagnosing ?? false,
                        onSendComment: { text in
                            await diagnosticAgent?.sendUserMessage(text, replyTo: nil, record: record)
                        },
                        onApplySuggestion: { comment in
                            diagnosticAgent?.applySuggestion(from: comment, to: record)
                            popToast("已应用 AI 建议")
                        },
                        onIgnoreSuggestion: { comment in
                            diagnosticAgent?.ignoreSuggestion(on: comment)
                        },
                        onStartDiagnose: {
                            handleDiagnose()
                        },
                        triggerDiagnose: false
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                .animation(.easeOut(duration: 0.2), value: showPhonePreview)
            }
        }
    }

    // MARK: - Diagnostic Agent

    private func setupDiagnosticAgent() {
        diagnosticAgent = DiagnosticAgent(modelContext: modelContext)
    }

    // MARK: - Top Toolbar

    /// navigation bar 大标题。iPhone 显示"结果编辑"，iPad/Mac 走 system title placeholder 由
    /// NavigationSplitView 的 detail 容器决定（避免与外层 navigationTitle 重复）。
    private var navigationTitleText: String {
        // iPhone / iPad：详情区自带 nav bar，用大标题
        // macOS：window 自带 title，重复显示无意义，返回空让系统接管
        #if os(macOS)
        return ""
        #else
        return "结果编辑"
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if shouldShowModePicker {
            // iPhone: single-column with edit/preview toggle
            VStack(spacing: 0) {
                Picker("模式", selection: $resultMode) {
                    Label("编辑", systemImage: "pencil").tag(ResultMode.edit)
                    Label("预览", systemImage: "eye").tag(ResultMode.preview)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.vertical, Spacing.md)

                if resultMode == .edit {
                    editorPanel
                } else {
                    previewPanel
                }
            }
            .background(Color.bg.ignoresSafeArea())
        } else if resultMode == .edit {
            // Wide screens: tri-pane layout
            GeometryReader { geo in
                tripaneContent(totalWidth: geo.size.width)
            }
            .background(Color.bg.ignoresSafeArea())
        } else {
            previewPanel
        }
    }

    @ToolbarContentBuilder
    private var topToolbarContent: some ToolbarContent {
        // Ad type badge — iOS 走 principal（中间），macOS toolbar 主区
        let adTypeStr = adType ?? record.adType
        if !adTypeStr.isEmpty {
            ToolbarItem(placement: .principal) {
                Text(adTypeStr)
                    .font(Typography.caption.weight(.medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.surfaceMuted, in: Capsule())
            }
        }

        // 操作按钮（手机预览 / 打包）— 右侧 / trailing
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showPhonePreview = true
            } label: {
                Label("手机预览", systemImage: "iphone")
            }
            .help("在小红书手机版样式中预览")

            Button {
                startPackaging()
            } label: {
                Label("打包", systemImage: "archivebox")
            }
            .disabled(isPackaging)
            .help("导出为 zip 包")
        }
    }

    // MARK: - Notifications

    private var notificationsOverlay: some View {
        Group {
            if undo != nil || showToast {
                VStack(spacing: Spacing.sm) {
                    if let undo {
                        undoBanner(undo)
                    }
                    if showToast {
                        toastBubble
                    }
                }
                .padding(.horizontal, Spacing.page)
                .padding(.vertical, Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func undoBanner(_ snap: ResultUndoSnapshot) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
            Text("\(snap.value.displayName)已更新")
                .font(Typography.bodySmall).foregroundStyle(Color.white)
            Spacer()
            Text("\(undoCountdown)s")
                .font(Typography.monoSmall).foregroundStyle(Color.white.opacity(0.6))
            Button {
                performUndo(snap)
            } label: {
                Text("撤销")
                    .font(Typography.bodySmall.weight(.semibold))
                    .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, Spacing.page)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var toastBubble: some View {
        Text(toastText)
            .font(Typography.bodySmall)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .transition(.opacity)
    }

    // MARK: - Layout

    private func tripaneContent(totalWidth: CGFloat) -> some View {
        let gap = ResultLayoutConstants.columnGap
        let hPad = ResultLayoutConstants.pageHPad
        let usableWidth = totalWidth - hPad * 2 - gap
        // editor 最小宽度：380pt 让 22pt serif 标题能完整放下一行（之前 320pt 在窄窗会切字）
        let editorW = min(max(usableWidth * editorFraction, 380), usableWidth * 0.78)

        return HStack(spacing: 0) {
            ResultStepColumn(step: 1, title: "文案内容", icon: "text.alignleft") {
                editorPanel
            }
            .frame(width: editorW)

            ResultDragHandle(
                usableWidth: usableWidth,
                editorWidth: editorW,
                gap: gap,
                maxFraction: 0.78
            ) { newFrac in
                editorFraction = newFrac
            }

            ResultStepColumn(step: 2, title: "AI 生成", icon: "sparkles") {
                aiToolColumnBody
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aiToolColumnBody: some View {
        ScrollView {
            aiToolInner
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xl)
        }
    }

    private var previewColumnBody: some View {
        GeometryReader { geo in
            let phoneW = ResultPreviewHelper.responsivePreviewWidth(containerWidth: geo.size.width)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    previewWithComments(previewWidth: phoneW)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(showPreviewHighlight ? Color.brand : Color.clear, lineWidth: 2)
                        )
                        .animation(.easeInOut(duration: 0.5), value: showPreviewHighlight)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .padding(.bottom, Spacing.xl)
                }
                .onChange(of: aiAssistantScrollTrigger) { _, _ in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(PublishPreviewView.commentAnchorID, anchor: .top)
                    }
                }
            }
        }
    }

    private func previewWithComments(previewWidth: CGFloat) -> some View {
        PublishPreviewView(
            noteTitle: record.noteTitle,
            content: record.content,
            tags: record.tags,
            imageUrls: effectiveImageURLs,
            videoUrl: effectiveVideoURL,
            adType: record.adType,
            chromeless: true,
            previewWidth: previewWidth,
            recordId: record.id,
            isDiagnosing: diagnosticAgent?.isDiagnosing ?? false,
            onSendComment: { text in
                await diagnosticAgent?.sendUserMessage(text, replyTo: nil, record: record)
            },
            onApplySuggestion: { comment in
                diagnosticAgent?.applySuggestion(from: comment, to: record)
                popToast("已应用 AI 建议")
            },
            onIgnoreSuggestion: { comment in
                diagnosticAgent?.ignoreSuggestion(on: comment)
            },
            onStartDiagnose: {
                handleDiagnose()
            },
            diagnoseError: diagnosticAgent?.lastError,
        )
    }

    private func dualPanelContent(totalWidth: CGFloat) -> some View {
        let gap = ResultLayoutConstants.columnGap
        let hPad = ResultLayoutConstants.pageHPad
        let usableWidth = totalWidth - hPad * 2 - gap
        let editorMax = min(usableWidth * 0.72, 960)
        let editorMin = max(420, usableWidth * 0.42)
        let editorWidth = min(max(usableWidth * editorFraction, editorMin), editorMax)

        return HStack(spacing: 0) {
            ResultStepColumn(step: 1, title: "文案内容", icon: "text.alignleft") {
                editorPanel
            }
            .frame(width: editorWidth)

            ResultDragHandle(
                usableWidth: usableWidth,
                editorWidth: editorWidth,
                gap: gap,
                maxFraction: 0.7
            ) { newW in
                let newFrac = min(max(newW / usableWidth, 0.25), 0.7)
                editorFraction = newFrac
            }

            ResultStepColumn(step: 2, title: "AI 生成", icon: "sparkles") {
                aiToolColumnBody
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor Panel

    private var editorPanel: some View {
        ResultEditorPanel(
            record: $record,
            selectedText: $selectedText,
            showEmojiPicker: $showEmojiPicker,
            showAddTag: $showAddTag,
            newTagText: $newTagText,
            debugMode: $debugMode,
            isGenerating: $isGenerating,
            regeneratingField: $regeneratingField,
            fromHistory: fromHistory,
            cloneCreated: cloneCreated,
            onEnsureClone: { ensureCloneIfNeeded() },
            onCopyAll: { copyAll() },
            onRegenerateAll: { regenerateAll() },
            onRegenerateField: { regenerateField($0) },
            onSaveToInspiration: { saveToInspiration(type: $0, content: $1, source: $2) },
            onPopToast: { popToast($0) }
        )
    }

    // MARK: - Preview Panel (iPhone)

    private var previewPanel: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        previewWithComments(previewWidth: min(max(geo.size.width - Adaptive.horizontalPageMargin * 2, 320), 420))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(showPreviewHighlight ? Color.brand : Color.clear, lineWidth: 2)
                            )
                            .animation(.easeInOut(duration: 0.5), value: showPreviewHighlight)
                    }
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, 120)
                }
                .onChange(of: aiAssistantScrollTrigger) { _, _ in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(PublishPreviewView.commentAnchorID, anchor: .top)
                    }
                }
            }
        }
        .background(Color.surface)
    }

    // MARK: - AI Tool Inner

    private var aiToolInner: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("AI 工具", selection: $rightPanelTab) {
                Label("AI 配图", systemImage: "paintpalette").tag(RightPanelTab.image)
                Label("AI 视频", systemImage: "film").tag(RightPanelTab.video)
            }
            .pickerStyle(.segmented)

            aiStatusBadge

            Group {
                if rightPanelTab == .image {
                    imageGenSection
                } else {
                    videoGenSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { }
    }

    private var aiStatusBadge: some View {
        let isImage = rightPanelTab == .image
        let isBusy = isImage ? jimengService.isGeneratingImage : jimengService.isGeneratingVideo
        let imageCountVal = effectiveImageURLs.count
        let hasVideo = effectiveVideoURL != nil
        let hasContent = isImage ? imageCountVal > 0 : hasVideo

        let (dotColor, text): (Color, String) = {
            if isBusy { return (.orange, "生成中…") }
            if hasContent {
                return (.green, isImage ? "已生成 \(imageCountVal) 张" : "已生成视频")
            }
            return (Color.ink3, "未生成")
        }()

        return HStack(spacing: Spacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Color.ink3)
        }
    }

    // MARK: - Image Generation

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
                    HStack(spacing: Spacing.sm) {
                        imageCountStepper
                        Spacer()
                        Button {
                            Task { await generateImages() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("重新生成 \(imageCount) 张")
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }

            if !jimengService.isConfigValidForImage {
                configMissingHint("请先在「我的 → 大模型配置 → 图片生成」中填写 Ark Key 或 AK/SK + req_key")
            } else if isPreparingPrompts {
                generatingStatus("正在为 \(imageCount) 张图扩出不同的提示词...")
            } else if jimengService.isGeneratingImage {
                // 优先用 jimengService.imagePhase（Agnes 多阶段进度跟豆包对齐）
                // 图片生成没有官方 progress 字段（Agnes image 同步返回），用 phase 文字 + 准备/完成事件
                let phase = jimengService.imagePhase
                let fallback = imageCount > 1 ? "正在并行生成 \(imageCount) 张配图..." : "正在生成配图..."
                let displayPhase = phase.isEmpty ? fallback : phase
                // 图片生成总进度估算：准备 prompt (10%) + 生成中 (10% → 90%) + 下载 (90% → 100%)
                let estimateProgress: Double = {
                    if phase.contains("完成") { return 100 }
                    if phase.contains("下载") { return 95 }
                    if phase.contains("生成中") { return 50 }
                    if phase.contains("并行") || phase.contains("准备") { return 20 }
                    return 0
                }()
                generatingProgress(kind: "图片", phase: displayPhase, progress: estimateProgress)
            } else if let error = jimengService.imageError {
                generationErrorCard(
                    kind: "图片",
                    rawError: error,
                    provider: "Agnes",
                    onRetry: { Task { await generateImages() } }
                )
            } else if !effectiveImageURLs.isEmpty {
                imageGallery
            } else {
                imagePromptAndButton
            }
        }
    }

    private var imagePromptAndButton: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if record.imagePrompt.isEmpty {
                if !record.content.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("根据文案自动总结生图提示词")
                            .font(Typography.bodySmall)
                            .foregroundStyle(Color.ink3)
                        Button {
                            Task { await generateImagePromptFromContent() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("AI 总结配图提示词")
                            }
                        }
                        .buttonStyle(GhostButtonStyle(tint: .brand))
                        .disabled(isGenerating)
                    }
                } else {
                    Text("暂无文生图提示词，请先生成文案")
                        .font(Typography.bodySmall)
                        .foregroundStyle(Color.ink4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if effectiveImageURLs.isEmpty && !jimengService.isGeneratingImage {
                aiToolEmptyGuide
            } else {
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
                .font(Typography.caption)
            Text(count > 0 ? "将使用 \(count) 张产品图作为参考，AI 会基于产品外观生成配图" : "未上传产品图，将根据提示词直接生成配图")
                .font(Typography.caption)
        }
        .foregroundStyle(count > 0 ? Color.suggestionBlue : Color.ink3)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(count > 0 ? Color.suggestionBg : Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm))
    }

    private var imageCountPicker: some View {
        imageCountStepper
    }

    @State private var galleryPageIndex: Int = 0

    /// 仅展示图片（不含顶部控制栏，控制栏在 imageGenSection 中统一显示）
    private var imageGallery: some View {
        let count = effectiveImageURLs.count
        return VStack(alignment: .leading, spacing: Spacing.md) {
            // Image thumbnails strip (horizontal, scrollable)
            if count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(effectiveImageURLs.enumerated()), id: \.offset) { i, url in
                            thumbnailButton(url: url, index: i, totalCount: count)
                        }
                    }
                }
                .frame(height: 80)
            }

            // Large preview of selected image
            if count > 0 {
                largeImagePreview(
                    url: effectiveImageURLs[galleryPageIndex],
                    index: galleryPageIndex,
                    count: count
                )
            } else if isPreparingPrompts {
                generatingStatus("正在为 \(imageCount) 张图扩出不同的提示词...")
            } else if jimengService.isGeneratingImage {
                generatingStatus(imageCount > 1 ? "正在并行生成 \(imageCount) 张配图..." : "正在生成配图...")
            } else if let error = jimengService.imageError {
                errorHint(error)
            }

            aiAnnotation("图片由AI生成")
        }
    }

    private func thumbnailButton(url: String, index: Int, totalCount: Int) -> some View {
        let isSelected = galleryPageIndex == index
        return Button {
            HapticManager.lightImpact()
            withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                galleryPageIndex = index
            }
        } label: {
            AsyncImage(url: URL.safeURL(from: url)) { phase in
                Group {
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.ink3)
                    case .empty:
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.ink4)
                    @unknown default:
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.ink4)
                    }
                }
                .padding(2)
                .background(isSelected ? Color.brandSoft : Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.brand : Color.clear, lineWidth: 2)
                )
                .shadow(color: isSelected ? Color.brand.opacity(0.15) : Color.clear, radius: 4)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func largeImagePreview(url: String, index: Int, count: Int) -> some View {
        VStack(spacing: Spacing.md) {
            // Image with elegant overlay navigation
            if count > 1 {
                ZStack(alignment: .center) {
                    // Main image
                    AsyncImage(url: URL.safeURL(from: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 420)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        case .failure:
                            Rectangle()
                                .fill(Color.surfaceMuted)
                                .frame(height: 420)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .font(.system(size: 48, weight: .light))
                                            .foregroundStyle(Color.ink4)
                                        Text("图片加载失败").font(Typography.bodySmall).foregroundStyle(Color.ink3)
                                        Text("链接可能已过期").font(Typography.caption).foregroundStyle(Color.ink4)
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        case .empty:
                            Rectangle()
                                .fill(Color.surfaceMuted)
                                .frame(height: 420)
                                .overlay(ProgressView())
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .contextMenu {
                        Button { ResultCopyHelper.copyStringToClipboard(url); popToast("已复制图片链接") } label: {
                            Label("复制图片链接", systemImage: "link")
                        }
                        Button { Task { await ResultSaveHelper.saveImage(url: url, onPopToast: popToast) } } label: {
                            Label("保存到本地", systemImage: "square.and.arrow.down")
                        }
                    }

                    // Left arrow overlay — visible circle button
                    Button {
                        HapticManager.lightImpact()
                        withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                            galleryPageIndex = (galleryPageIndex - 1 + count) % count
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.45))
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)

                    // Right arrow overlay — visible circle button
                    Button {
                        HapticManager.lightImpact()
                        withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                            galleryPageIndex = (galleryPageIndex + 1) % count
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.45))
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width < -50 {
                                withAnimation { galleryPageIndex = (galleryPageIndex + 1) % count }
                            } else if value.translation.width > 50 {
                                withAnimation { galleryPageIndex = (galleryPageIndex - 1 + count) % count }
                            }
                        }
                )

                // Page dot indicator below the image
                HStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(galleryPageIndex == i ? Color.brand : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            } else {
                // Single image (no navigation)
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL.safeURL(from: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 420)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        case .failure:
                            Rectangle()
                                .fill(Color.surfaceMuted)
                                .frame(height: 420)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .font(.system(size: 48, weight: .light))
                                            .foregroundStyle(Color.ink4)
                                        Text("图片加载失败").font(Typography.bodySmall).foregroundStyle(Color.ink3)
                                        Text("链接可能已过期").font(Typography.caption).foregroundStyle(Color.ink4)
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        case .empty:
                            Rectangle()
                                .fill(Color.surfaceMuted)
                                .frame(height: 420)
                                .overlay(ProgressView())
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .contextMenu {
                        Button { ResultCopyHelper.copyStringToClipboard(url); popToast("已复制图片链接") } label: {
                            Label("复制图片链接", systemImage: "link")
                        }
                        Button { Task { await ResultSaveHelper.saveImage(url: url, onPopToast: popToast) } } label: {
                            Label("保存到本地", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button {
                    ResultCopyHelper.copyStringToClipboard(url)
                    popToast("已复制图片链接")
                } label: {
                    Label("复制链接", systemImage: "link")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.surfaceMuted)
                        .foregroundStyle(Color.ink2)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.border, lineWidth: BorderWidth.hairline))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await ResultSaveHelper.saveImage(url: url, onPopToast: popToast) }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.brand)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Video Generation

    private var videoGenSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("AI 视频生成").editorialLabel()
                Spacer()
                if effectiveVideoURL != nil && !jimengService.isGeneratingVideo && !volcService.isGenerating {
                    Button {
                        Task { await generateVideo() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("重新生成")
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }

            if !jimengService.isConfigValidForVideo {
                configMissingHint("请先在「我的 → 大模型配置 → 视频生成」中填写 Ark Key 或 AK/SK + req_key")
            } else if jimengService.isGeneratingVideo {
                // Agnes：phase 文本 + progress 字段（0-100）双驱动
                // phase 可能短暂为空，统一兜底"正在生成视频"
                let phase = jimengService.videoPhase.isEmpty ? "正在生成视频" : jimengService.videoPhase
                generatingProgress(kind: "视频", phase: phase, progress: Double(jimengService.videoProgress))
            } else if volcService.isGenerating {
                // 豆包：v1 API 没有 progress 字段，只显示 phase 文字
                let phase = volcService.phase.isEmpty ? "正在生成视频" : volcService.phase
                generatingStatus(phase)
            } else if let error = jimengService.videoError {
                generationErrorCard(
                    kind: "视频",
                    rawError: error,
                    provider: "Agnes",
                    onRetry: { Task { await generateVideo() } }
                )
            } else if let error = volcService.error {
                // 豆包之前漏了错误分支，补上
                generationErrorCard(
                    kind: "视频",
                    rawError: error,
                    provider: "豆包",
                    onRetry: { Task { await generateVideo() } }
                )
            } else if let videoURL = effectiveVideoURL {
                videoResult(videoURL)
            } else {
                videoPromptAndButton
            }
        }
        // videoGenSection 暂不加引导 popover（imageGenSection 已经覆盖首次使用引导）
    }

    private var videoPromptAndButton: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if record.videoPrompt.isEmpty {
                Text("暂无视频提示词，请先生成文案")
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if effectiveVideoURL == nil && !jimengService.isGeneratingVideo && !volcService.isGenerating {
                aiToolEmptyGuide
            } else {
                if effectiveImageURLs.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(Typography.caption)
                        Text("请先生成配图。视频会用配图作为首帧生成。")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(Color.ink3)
                }

                Button {
                    Task { await generateVideo() }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "video.badge.plus")
                        Text("生成视频")
                    }
                }
                .buttonStyle(GhostButtonStyle(tint: .brand))
                .disabled(effectiveImageURLs.isEmpty)
            }
        }
    }

    private func videoResult(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                Text("视频生成完成").font(Typography.bodySmall).foregroundStyle(Color.ink2)
                Spacer()
            }

            if let videoURL = URL.safeURL(from: url) {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 480, maxHeight: 640)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.border, lineWidth: BorderWidth.hairline))
                    .id(url)
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    ResultCopyHelper.copyStringToClipboard(url)
                    popToast("已复制视频链接")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 16, weight: .semibold))
                        Text("复制链接").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.surfaceMuted)
                    .foregroundStyle(Color.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.border, lineWidth: BorderWidth.hairline))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await ResultSaveHelper.saveVideo(url: url, onPopToast: popToast) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 16, weight: .semibold))
                        Text("保存到本地").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.brand)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            aiAnnotation("视频由AI生成")
                .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Empty Guide / Annotations

    private var aiToolEmptyGuide: some View {
        VStack(spacing: Spacing.lg) {
            Spacer().frame(height: Spacing.lg)

            Image(systemName: rightPanelTab == .image ? "photo.badge.plus" : "video.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.ink4)

            Text(rightPanelTab == .image ? "点这里生成你的封面配图" : "点这里生成你的短视频")
                .font(Typography.body)
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)

            if rightPanelTab == .image {
                emptyGuideImageCountPicker
            }

            Button {
                Task {
                    if rightPanelTab == .image {
                        await generateImages()
                    } else {
                        await generateVideo()
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: rightPanelTab == .image ? "paintpalette" : "film")
                    Text(rightPanelTab == .image
                         ? (imageCount > 1 ? "生成 \(imageCount) 张配图" : "生成配图")
                         : "生成视频")
                }
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(Color.brand, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer().frame(height: Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        // imageGenSection 暂不加引导 popover（ResultView 引导后续再加，当前聚焦 generate 页 5 步）
    }

    private var emptyGuideImageCountPicker: some View {
        imageCountStepper
    }

    private func aiAnnotation(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(Typography.micro)
            Text(text).font(Typography.caption)
        }
        .foregroundStyle(Color.ink4)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.surfaceMuted, in: Capsule())
    }

    // MARK: - Helpers

    /// 图片数量选择器（1-9）。用 SwiftUI 原生 Stepper，跨平台一致：
    /// - iPhone 紧凑：紧凑的 - 数字 + 控件
    /// - iPad / Mac：与系统风格一致
    /// 同时提供常用档位 [1, 3, 5, 9] 快速选择。
    /// 替代之前 1-9 个 button 横排的 imageCountPicker（9 个 32x28 button 在 iPhone
    /// 上挤，iPad 上也丑）。
    private var imageCountStepper: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text("数量")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.ink3)
                Stepper(value: $imageCount, in: 1...9) {
                    HStack(spacing: 4) {
                        Text("\(imageCount)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.brand)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(imageCount > 1 ? "张配图" : "张配图")
                            .font(Typography.caption)
                            .foregroundStyle(Color.ink2)
                    }
                }
                .labelsHidden()
            }
            // 常用档位快速选择（一行 4 颗紧凑 chip）
            HStack(spacing: 6) {
                ForEach([1, 3, 5, 9], id: \.self) { n in
                    Button {
                        imageCount = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(imageCount == n ? .white : Color.ink3)
                            .frame(minWidth: 24, idealWidth: 28)
                            .frame(height: 22)
                            .background(imageCount == n ? Color.brand : Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if imageCount > 1 {
                    Text("将先扩出 \(imageCount) 个不同 prompt 并行生成")
                        .font(Typography.caption)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(2)
                        .padding(.leading, 4)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func configMissingHint(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "gearshape.2").font(Typography.caption).foregroundStyle(Color.ink3)
            Text(message).font(Typography.bodySmall).foregroundStyle(Color.ink3)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func generatingStatus(_ text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            ProgressView().scaleEffect(0.8)
            Text(text).font(Typography.bodySmall).foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, Spacing.lg)
    }

    /// 带进度条的"正在生成"状态。
    /// - progress: 0-100；0 表示不确定（不显示百分比）。
    /// - 默认头部加"正在生成视频/图片"作为锚点文案，避免 phase 短暂为空时空白。
    private func generatingProgress(
        kind: String,         // "视频" / "图片"
        phase: String,        // 后端返回的当前阶段文案
        progress: Double      // 0-100，传 0 表示"未知"
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ProgressView().scaleEffect(0.85).tint(Color.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("正在生成\(kind)…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    if !phase.isEmpty {
                        Text(phase)
                            .font(Typography.caption)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Spacer()
                if progress > 0 && progress < 100 {
                    Text("\(Int(progress))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.brand)
                }
            }
            if progress > 0 {
                ProgressView(value: progress, total: 100)
                    .progressViewStyle(.linear)
                    .tint(Color.brand)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        )
    }

    private func errorHint(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").font(Typography.caption).foregroundStyle(Color.brand)
            Text(message).font(Typography.bodySmall).foregroundStyle(Color.brand)
        }
    }

    // MARK: - 失败错误卡片（视频/图片生成通用）
    //
    // 比 errorHint 更显眼：标题 + icon + 原始错误 + 解决建议 + 重试/复制按钮。
    // 用户点 "复制" 把错误全文写到剪贴板，方便反馈；点 "重试" 直接重跑生成。
    // 解决建议根据错误类型给出常见 fix（API Key / 网络 / 余额 / 模型名）。
    private func generationErrorCard(
        kind: String,              // "视频" / "图片"
        rawError: String,
        provider: String,          // "Agnes" / "豆包"
        onRetry: @escaping () -> Void
    ) -> some View {
        let (title, suggestion) = Self.diagnoseVideoError(rawError)
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
                        popToast("错误信息已复制")
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

    /// 简易错误诊断：基于关键词给用户原因 + 建议，避免技术黑话
    private static func diagnoseVideoError(_ raw: String) -> (title: String, suggestion: String) {
        let lower = raw.lowercased()
        if raw.contains("API Key") || raw.contains("401") || raw.contains("403") {
            return ("未授权：API Key 无效或未填写",
                    "到「我的 → 大模型配置 → 视频生成」检查 Key 是否正确填写，或在服务商控制台确认 Key 有效。")
        }
        if raw.contains("超时") || raw.contains("timed out") || lower.contains("timeout") || raw.contains("-1001") {
            return ("任务超时（10 分钟未完成）",
                    "视频生成偶尔会比较慢。如果多次超时：① 检查网络稳定性 ② 简化提示词（去除长描述） ③ 切换到豆包 Seedance 重试。")
        }
        if raw.contains("-1005") || raw.contains("网络连接已中断") || raw.contains("network connection lost") {
            // TCP 连接中途断（不是 body 大小的问题，是网络层被 reset / WiFi 切换 / 代理断开）
            return ("网络连接已中断",
                    "请求在传输途中被关闭（可能切换了 WiFi、VPN 断开、或者本地网络瞬时抖动）。\n\n建议：① 确认当前网络稳定 ② 重新点击「生成视频」重试 — 视频生成通常是 5-7 分钟内出结果。")
        }
        if raw.contains("-1009") || raw.contains("无互联网连接") || raw.contains("no internet") {
            return ("无网络连接",
                    "设备当前连不上互联网。检查 WiFi / 蜂窝数据是否正常，或等待网络恢复后重试。")
        }
        if raw.contains("404") {
            return ("任务或视频未找到",
                    "服务端没找到这个任务（可能已过期被清理）。请重新生成。")
        }
        if raw.contains("400") {
            return ("请求参数无效",
                    "提示词或参数不符合接口规范。检查：① 提示词是否含特殊字符 ② 模型名是否正确（agnes-video-v2.0 / doubao-seedance） ③ 图片 URL 是否可公开访问。")
        }
        if raw.contains("5") && (raw.contains("500") || raw.contains("503")) {
            return ("服务端异常",
                    "Agnes / 豆包服务端暂时不可用。请稍等 1-2 分钟再试，或到「我的 → 大模型配置」切换到另一个服务商。")
        }
        if raw.contains("无法连接") || raw.contains("无法找到主机") || lower.contains("cannotconnect") || raw.contains("-1004") {
            return ("网络连接失败",
                    "检查：① 当前网络是否可用 ② 大模型配置的 baseURL 是否正确 ③ 公司网络是否拦截了 API 域名。")
        }
        // fallback：原文透传
        return ("生成未成功", "请重试。如果反复失败，到「我的 → 大模型配置」切换到豆包 Seedance，或在设置页复制错误反馈给我们。")
    }

    private func ensureCloneIfNeeded() {
        guard fromHistory, !cloneCreated else { return }
        let newRecord = GenerationRecord(
            id: UUID(),
            adType: record.adType,
            inputKeyword: record.inputKeyword,
            keywordHint: record.keywordHint,
            productId: record.productId,
            noteTitle: record.noteTitle,
            content: record.content,
            tags: record.tags,
            imageSuggestion: record.imageSuggestion,
            imagePrompt: record.imagePrompt,
            videoPrompt: record.videoPrompt,
            imageUrls: record.imageUrls,
            videoUrl: record.videoUrl,
            easterEggText: record.easterEggText,
            hotScore: record.hotScore,
            suggestion: record.suggestion,
            isEdited: false,
            createdAt: Date()
        )
        repository.saveRecord(newRecord)
        record = newRecord
        cloneCreated = true
    }

    // MARK: - Image/Video Generation Actions

    private func generateImages() async {
        ensureCloneIfNeeded()
        let capturedRecordId = record.id
        let capturedRecord = record
        let capturedImageCount = imageCount
        let capturedImagePrompt = record.imagePrompt
        let capturedKeyword = record.inputKeyword
        let capturedAdType = AdType(rawValue: record.adType) ?? .feedAd
        let capturedImageSuggestion = record.imageSuggestion
        let capturedProductId = record.productId
        let capturedReferenceImages = productReferenceImagesData()
        let capturedGenerator = generator
        let capturedRepository = repository
        // ⚠️ 关键修复：之前 `let agnes = AgnesService()` 在 task 内自建了新实例，
        // 跟 view 的 @State jimengService 是两个不同对象 → UI 监听的
        // jimengService.isGeneratingImage 永远是 false → 进度条永远不显示。
        // 修法：直接用 self.jimengService（@State 持有），UI 同一实例监听进度。

        // 委托给 regenSession — 任务跨 view 生命周期
        regenSession.startImage(recordId: capturedRecordId) { [self] in
            let n = max(1, min(capturedImageCount, 9))
            // 闭包内 fetch product — 让 regenerateImagePrompts 知道产品是什么，
            // 生成的 prompt 才能跟产品图 reference 一起精准产出
            let product = capturedProductId.flatMap { pid in
                capturedRepository.allProducts().first { $0.id == pid }
            }
            var prompts: [String] = [capturedImagePrompt]
            if n > 1, let llm = capturedGenerator as? LLMTextGenerator {
                self.regenSession.setImagePreparing(recordId: capturedRecordId, isPreparing: true)
                do {
                    prompts = try await llm.regenerateImagePrompts(
                        count: n,
                        basePrompt: capturedImagePrompt,
                        keyword: capturedKeyword,
                        product: product,
                        adType: capturedAdType,
                        imageSuggestion: capturedImageSuggestion
                    )
                } catch {
                    DebugLog.shared.log(.warn, .llm, "regenerateImagePrompts failed, fallback to base prompt repeated", details: error.localizedDescription)
                    prompts = Array(repeating: capturedImagePrompt, count: n)
                }
                self.regenSession.setImagePreparing(recordId: capturedRecordId, isPreparing: false)
            } else if n > 1 {
                prompts = Array(repeating: capturedImagePrompt, count: n)
            }
            await jimengService.generateImages(prompts: prompts, referenceImagesData: capturedReferenceImages)
            if !jimengService.generatedImageURLs.isEmpty {
                capturedRecord.imageUrls = jimengService.generatedImageURLs
                capturedRepository.saveRecord(capturedRecord)
                await MainActor.run {
                    self.popToast("⬇ 已带入预览")
                    self.showPreviewHighlight = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.easeInOut(duration: 0.5)) { self.showPreviewHighlight = false }
                    }
                }
            }
        }
    }

    private func generateVideo() async {
        ensureCloneIfNeeded()
        let capturedRecordId = record.id
        let capturedRecord = record
        let capturedVideoPrompt = record.videoPrompt
        let capturedReferenceImageURLs = effectiveImageURLs
        let capturedRepository = repository
        let provider = LLMConfigStore.config(for: .video).provider

        // 委托给 regenSession — 任务跨 view 生命周期
        regenSession.startVideo(recordId: capturedRecordId) { [self] in
            let savedURL: String?
            switch provider {
            case .doubao:
                // 豆包 Seedance：submit → 轮询 → 下载到本地（24h URL 过期问题）
                // 直接用 self.volcService（@State 持有），UI 同一实例监听进度
                await volcService.generateVideo(prompt: capturedVideoPrompt)
                savedURL = volcService.localVideoURL
            case .agnes:
                // Agnes：直接用 self.jimengService（@State 持有），UI 同一实例监听进度
                // —— 关键：之前 `let agnes = AgnesService()` 在 task 内自建了**新实例**，
                // 跟 view 的 @State jimengService 是两个不同对象 → 视频跑在 agnes 上，
                // UI 监听的 jimengService.isGeneratingVideo 永远是 false → 进度条永远不显示
                await jimengService.generateVideo(
                    prompt: capturedVideoPrompt,
                    referenceImageURLs: capturedReferenceImageURLs
                )
                savedURL = jimengService.generatedVideoURL
            case .deepseek:
                // 错误通过 toast 提示（不写 record，因为没结果）
                await MainActor.run {
                    self.popToast("DeepSeek 不支持视频生成，请切换到 Agnes 或豆包")
                }
                return
            }
            if let url = savedURL {
                capturedRecord.videoUrl = url
                capturedRepository.saveRecord(capturedRecord)
                await MainActor.run {
                    self.popToast("⬇ 已带入预览")
                    self.showPreviewHighlight = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.easeInOut(duration: 0.5)) { self.showPreviewHighlight = false }
                    }
                }
            }
        }
    }

    private func generateImagePromptFromContent() async {
        guard !record.content.isEmpty, generator is LLMTextGenerator else { return }
        ensureCloneIfNeeded()
        do {
            let prompt = try await (generator as! LLMTextGenerator).summarizeImagePrompt(
                content: record.content,
                title: record.noteTitle,
                tags: record.tags,
                adType: AdType(rawValue: record.adType) ?? .feedAd
            )
            await MainActor.run {
                record.imagePrompt = prompt
                repository.saveRecord(record)
                popToast("配图提示词已生成")
            }
        } catch {
            await MainActor.run {
                popToast("生成失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Product Reference Images

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

    /// 取产品参考图（Agnes i2v / image-to-image 用）。
    /// 关键原因：之前传 `product.imagePaths + product.styleImagePaths` **所有**图
    /// （曾经传过 8 张），base64 进 JSON body 容易 10-20MB，60s 内传不完 → 视频/
    /// 图片生成提交超时。修法：① 限前 2 张  ② 缩到 1024px  ③ JPEG 0.85 压缩
    /// → 单张 ~150-300KB，2 张总共 < 1MB，60s 内轻松传完。
    private func productReferenceImagesData() -> [Data] {
        guard let pid = record.productId,
              let product = allProducts.first(where: { $0.id == pid }) else { return [] }
        // imagePaths 优先（产品主图，主体外观最准）；styleImages 兜底
        // 合并后取前 2 张 —— 够 AI 看清产品外观，又不会撑爆 body
        let candidates = (product.imagePaths + product.styleImagePaths)
            .filter { !$0.isEmpty }
            .prefix(2)
        guard !candidates.isEmpty else { return [] }
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var result: [Data] = []
        for relative in candidates {
            let url = docs.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path),
                  let raw = try? Data(contentsOf: url) else { continue }
            // 缩到 1024px + JPEG 0.85 压缩
            if let compressed = Self.compressForReferenceImage(raw, maxSide: 1024, quality: 0.85) {
                result.append(compressed)
            } else {
                result.append(raw)   // 压缩失败就用原图（极端兜底）
            }
        }
        return result
    }

    /// 把图片 Data 缩到最长边 ≤ maxSide，JPEG 重新压缩到指定 quality。
    /// 失败返回 nil（让调用方决定是否回退原图）。
    private static func compressForReferenceImage(_ data: Data, maxSide: CGFloat, quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        guard let img = UIImage(data: data) else { return nil }
        let size = img.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? (maxSide / longest) : 1.0
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
        #elseif canImport(AppKit)
        guard let img = NSImage(data: data) else { return nil }
        let size = img.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? (maxSide / longest) : 1.0
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        defer { resized.unlockFocus() }
        img.draw(in: NSRect(origin: .zero, size: newSize),
                 from: NSRect(origin: .zero, size: size),
                 operation: .copy,
                 fraction: 1.0)
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        return nil
        #endif
    }

    // MARK: - Regenerate Actions

    private func regenerateAll() {
        guard !isGenerating, !regenSession.isTextRunning(recordId: record.id) else { return }
        HapticManager.mediumImpact()
        ensureCloneIfNeeded()
        isGenerating = true

        let gen = generator
        let capturedRecordId = record.id
        let capturedFromHistory = fromHistory
        let capturedCloneCreated = cloneCreated
        let capturedRecord = record
        let capturedRepository = repository

        // 委托给 regenSession — 任务跨 view 生命周期，切到别的 tab 继续跑
        regenSession.startText(recordId: capturedRecordId) { [self] in
            let request = GenerateRequest(
                recordId: UUID(),
                keyword: capturedRecord.inputKeyword,
                adType: AdType(rawValue: capturedRecord.adType) ?? .feedAd,
                keywordHint: capturedRecord.keywordHint,
                product: nil,
                images: [],
                styleImages: []
            )
            do {
                let resp = try await gen.generate(request)
                await MainActor.run {
                    if capturedFromHistory && capturedCloneCreated {
                        capturedRecord.noteTitle = resp.noteTitle
                        capturedRecord.content = resp.content
                        capturedRecord.tags = resp.tags
                        capturedRecord.imageSuggestion = resp.imageSuggestion
                        capturedRecord.imagePrompt = resp.imagePrompt
                        capturedRecord.videoPrompt = resp.videoPrompt
                        capturedRecord.easterEggText = resp.easterEgg
                        capturedRecord.hotScore = resp.hotScore
                        capturedRecord.suggestion = resp.suggestion
                        capturedRecord.isEdited = true
                        capturedRecord.createdAt = Date()
                    } else {
                        let newRecord = GenerationRecord(
                            adType: capturedRecord.adType,
                            inputKeyword: capturedRecord.inputKeyword,
                            keywordHint: capturedRecord.keywordHint,
                            noteTitle: resp.noteTitle,
                            content: resp.content,
                            tags: resp.tags,
                            imageSuggestion: resp.imageSuggestion,
                            imagePrompt: resp.imagePrompt,
                            videoPrompt: resp.videoPrompt,
                            easterEggText: resp.easterEgg,
                            hotScore: resp.hotScore,
                            suggestion: resp.suggestion
                        )
                        capturedRepository.saveRecord(newRecord)
                        self.record = newRecord
                    }
                    self.isGenerating = false
                    self.popToast("已换一批")
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.popToast("生成失败，请重试")
                }
            }
        }
    }

    private func regenerateField(_ field: RegenField) {
        guard !isGenerating, !regenSession.isTextRunning(recordId: record.id) else { return }
        ensureCloneIfNeeded()
        isGenerating = true
        regeneratingField = field

        let snapValue: ResultUndoValue
        switch field {
        case .title: snapValue = .title(record.noteTitle)
        case .body:  snapValue = .body(record.content)
        case .tags:  snapValue = .tags(record.tags)
        }

        let snapField = field
        let capturedRecordId = record.id
        let capturedRecord = record
        let capturedGenerator = generator
        let capturedAdType = AdType(rawValue: record.adType) ?? .feedAd
        let capturedKeyword = record.inputKeyword
        let capturedHint = record.keywordHint
        let capturedTitle = record.noteTitle
        let capturedContent = record.content
        let capturedTags = record.tags

        // 委托给 regenSession — 任务跨 view 生命周期，切到别的 tab 继续跑
        regenSession.startText(recordId: capturedRecordId) { [self] in
            do {
                switch snapField {
                case .title:
                    let newValue = try await capturedGenerator.regenerateTitle(
                        recordId: capturedRecordId,
                        keyword: capturedKeyword,
                        product: nil,
                        adType: capturedAdType,
                        keywordHint: capturedHint
                    )
                    await MainActor.run {
                        capturedRecord.noteTitle = newValue
                        self.finishRegen(snapField: snapField, snapValue: snapValue)
                    }
                case .body:
                    let newValue = try await capturedGenerator.regenerateBody(
                        recordId: capturedRecordId,
                        keyword: capturedKeyword,
                        product: nil,
                        adType: capturedAdType,
                        keywordHint: capturedHint,
                        existingTitle: capturedTitle,
                        existingTags: capturedTags
                    )
                    await MainActor.run {
                        capturedRecord.content = newValue
                        self.finishRegen(snapField: snapField, snapValue: snapValue)
                    }
                case .tags:
                    let newValue = try await capturedGenerator.regenerateTags(
                        recordId: capturedRecordId,
                        keyword: capturedKeyword,
                        product: nil,
                        adType: capturedAdType,
                        keywordHint: capturedHint,
                        existingTitle: capturedTitle,
                        existingContent: capturedContent
                    )
                    await MainActor.run {
                        capturedRecord.tags = newValue
                        self.finishRegen(snapField: snapField, snapValue: snapValue)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.regeneratingField = nil
                    self.popToast("生成失败，请重试")
                }
            }
        }
    }

    private func finishRegen(snapField: RegenField, snapValue: ResultUndoValue) {
        record.isEdited = true
        isGenerating = false
        regeneratingField = nil
        let snap = ResultUndoSnapshot(field: snapField, value: snapValue, deadline: Date().addingTimeInterval(5))
        undoCountdown = 5
        withAnimation(.easeOut(duration: AnimDuration.fast)) {
            undo = snap
        }
        startUndoTimer(for: snap)
    }

    private func startUndoTimer(for snap: ResultUndoSnapshot) {
        Task {
            for remaining in stride(from: 4, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    if self.undo?.id == snap.id {
                        self.undoCountdown = remaining
                    }
                }
            }
            await MainActor.run {
                if self.undo?.id == snap.id {
                    withAnimation(.easeOut(duration: AnimDuration.fast)) {
                        self.undo = nil
                    }
                }
            }
        }
    }

    private func performUndo(_ snap: ResultUndoSnapshot) {
        switch snap.value {
        case .title(let v): record.noteTitle = v
        case .body(let v):  record.content = v
        case .tags(let v):  record.tags = v
        }
        withAnimation(.easeOut(duration: AnimDuration.fast)) {
            undo = nil
        }
        popToast("已撤销")
    }

    // MARK: - Copy

    private func copyAll() {
        ResultCopyHelper.copyAll(record: record, onPopToast: popToast)
    }

    // MARK: - Save to Inspiration

    private func saveToInspiration(type: InspirationType, content: String, source: String) {
        ResultInspirationHelper.saveToInspiration(
            type: type, content: content, source: source,
            repository: repository, onPopToast: popToast
        )
    }

    // MARK: - Save All Images

    private func saveAllImages() async {
        await ResultSaveHelper.saveAllImages(urls: effectiveImageURLs, onPopToast: popToast)
    }

    // MARK: - Packaging

    private func startPackaging() {
        guard !isPackaging else { return }
        Task {
            isPackaging = true
            let packager = AssetPackager()
            do {
                #if os(macOS)
                let destDir = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.prompt = "保存到这里"
                    panel.message = "选一个文件夹，打包的素材会放在它的子文件夹里"
                    panel.begin { response in
                        if response == .OK, let url = panel.url {
                            cont.resume(returning: url)
                        } else {
                            cont.resume(throwing: CancellationError())
                        }
                    }
                }
                let resultURL = try await packager.package(record: record, to: destDir)
                await MainActor.run {
                    isPackaging = false
                    popToast("已打包到 \(resultURL.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([resultURL])
                }
                #else
                let zipURL = try await packager.packageAsZip(record: record)
                await MainActor.run {
                    isPackaging = false
                    zipURLToShare = zipURL
                    showPackageShareSheet = true
                }
                #endif
            } catch is CancellationError {
                await MainActor.run { isPackaging = false }
            } catch {
                await MainActor.run {
                    isPackaging = false
                    popToast("打包失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Toast

    private func popToast(_ text: String) {
        toastText = text
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Types (needed since regen module uses them)

enum RegenField: Hashable {
    case title, body, tags
}

struct ResultUndoSnapshot: Identifiable {
    let id = UUID()
    let field: RegenField
    let value: ResultUndoValue
    let deadline: Date
}

enum ResultUndoValue {
    case title(String)
    case body(String)
    case tags([String])

    var displayName: String {
        switch self {
        case .title: return "标题"
        case .body: return "正文"
        case .tags: return "标签"
        }
    }
}

#if os(iOS)
private struct PackageShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
