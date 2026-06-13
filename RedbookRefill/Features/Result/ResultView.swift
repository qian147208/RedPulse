//
//  ResultView.swift
//  RedPulse
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
    @AppStorage("result_mode") private var resultMode: ResultMode = .edit

    enum RightPanelTab: String, CaseIterable {
        case image = "image"
        case video = "video"
    }
    @State private var rightPanelTab: RightPanelTab = .image

    // MARK: - Shared State
    @Environment(\.modelContext) private var modelContext
    @State private var generator: GeneratorProtocol
    @State private var jimengService: JimengService
    @State private var selectedText: String = ""
    @State private var showRewriteDialog: Bool = false
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
    @State private var selectionToolbarVM: SelectionToolbarViewModel
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
        self._jimengService = State(initialValue: JimengService())
        self._selectionToolbarVM = State(initialValue: SelectionToolbarViewModel())
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
        #if os(macOS)
        return record.videoUrl.flatMap { URL.safeURL(from: $0) != nil ? $0 : nil }
        #else
        return record.videoUrl
        #endif
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
        VStack(spacing: 0) {
            topToolbar

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
        .overlay(alignment: .bottom) {
            notificationsOverlay
        }
        .onAppear {
            setupDiagnosticAgent()
            setupSelectionToolbar()
            Task {
                allProducts = repository.allProducts()
            }
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

    private func setupSelectionToolbar() {
        selectionToolbarVM.onGenerate = { [self] action, text, customInstruction in
            let instruction: String
            if let custom = customInstruction, action == .custom {
                instruction = custom
            } else {
                instruction = action.llmInstruction
            }
            return try await generator.transformText(
                command: instruction,
                selectedText: text,
                context: String(record.content.prefix(200))
            )
        }

        selectionToolbarVM.onReplace = { [self] result in
            guard !selectedText.isEmpty else { return }
            ensureCloneIfNeeded()
            record.content = record.content.replacingOccurrences(of: selectedText, with: result)
            record.isEdited = true
            selectedText = ""
            popToast("已替换")
        }
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: Spacing.sm) {
            #if os(iOS)
            Button {
                generatedRecord = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surfaceMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            #endif

            Spacer()

            // Ad type badge
            if let adTypeStr = record.adType ?? adType {
                Text(adTypeStr)
                    .font(Typography.caption.weight(.medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.surfaceMuted, in: Capsule())
            }

            Spacer()

            // Edit button
            Button {
                debugMode.toggle()
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)

            // Phone preview
            Button {
                showPhonePreview = true
            } label: {
                Image(systemName: "iphone")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surfaceMuted, in: Capsule())
            }
            .buttonStyle(.plain)

            // Packaging
            Button {
                startPackaging()
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surfaceMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isPackaging)
        }
        .padding(.horizontal, Adaptive.horizontalPageMargin)
        .padding(.vertical, Spacing.sm)
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
        let editorW = min(max(usableWidth * editorFraction, 320), usableWidth * 0.78)

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
            showRewriteDialog: $showRewriteDialog,
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
                        Text("数量").editorialLabel()
                        HStack(spacing: 4) {
                            ForEach([1, 2, 3, 4], id: \.self) { n in
                                Button {
                                    imageCount = n
                                } label: {
                                    Text("\(n)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(imageCount == n ? .white : Color.ink2)
                                        .frame(width: 28, height: 24)
                                        .background(imageCount == n ? Color.brand : Color.surfaceMuted)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
                    .font(Typography.caption)
                    .foregroundStyle(Color.ink3)
            }
        }
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
                if effectiveVideoURL != nil && !jimengService.isGeneratingVideo {
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
                generatingStatus("正在生成视频，预计需要几分钟...")
            } else if let error = jimengService.videoError {
                errorHint(error)
            } else if let videoURL = effectiveVideoURL {
                videoResult(videoURL)
            } else {
                videoPromptAndButton
            }
        }
    }

    private var videoPromptAndButton: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if record.videoPrompt.isEmpty {
                Text("暂无视频提示词，请先生成文案")
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if effectiveVideoURL == nil && !jimengService.isGeneratingVideo {
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
        .coachMarkTarget(rightPanelTab == .image ? "gen_image" : "gen_video")
    }

    private var emptyGuideImageCountPicker: some View {
        HStack(spacing: Spacing.sm) {
            Text("数量")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Color.ink3)
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
        }
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

    private func errorHint(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").font(Typography.caption).foregroundStyle(Color.brand)
            Text(message).font(Typography.bodySmall).foregroundStyle(Color.brand)
        }
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
                DebugLog.shared.log(.warn, .llm, "regenerateImagePrompts failed, fallback to base prompt repeated", details: error.localizedDescription)
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
            repository.saveRecord(record)
            await MainActor.run {
                popToast("⬇ 已带入预览")
                showPreviewHighlight = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(.easeInOut(duration: 0.5)) { showPreviewHighlight = false }
                }
            }
        }
    }

    private func generateVideo() async {
        ensureCloneIfNeeded()
        await jimengService.generateVideo(prompt: record.videoPrompt, referenceImageURLs: effectiveImageURLs)
        if let url = jimengService.generatedVideoURL {
            record.videoUrl = url
            repository.saveRecord(record)
            await MainActor.run {
                popToast("⬇ 已带入预览")
                showPreviewHighlight = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(.easeInOut(duration: 0.5)) { showPreviewHighlight = false }
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

    // MARK: - Regenerate Actions

    private func regenerateAll() {
        guard !isGenerating else { return }
        HapticManager.mediumImpact()
        ensureCloneIfNeeded()
        isGenerating = true

        let gen = generator
        Task {
            let request = GenerateRequest(
                recordId: UUID(),
                keyword: record.inputKeyword,
                adType: AdType(rawValue: record.adType) ?? .feedAd,
                keywordHint: record.keywordHint,
                product: nil,
                images: [],
                styleImages: []
            )
            do {
                let resp = try await gen.generate(request)
                await MainActor.run {
                    if fromHistory && cloneCreated {
                        record.noteTitle = resp.noteTitle
                        record.content = resp.content
                        record.tags = resp.tags
                        record.imageSuggestion = resp.imageSuggestion
                        record.imagePrompt = resp.imagePrompt
                        record.videoPrompt = resp.videoPrompt
                        record.easterEggText = resp.easterEgg
                        record.hotScore = resp.hotScore
                        record.suggestion = resp.suggestion
                        record.isEdited = true
                        record.createdAt = Date()
                    } else {
                        let newRecord = GenerationRecord(
                            adType: record.adType,
                            inputKeyword: record.inputKeyword,
                            keywordHint: record.keywordHint,
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
                        repository.saveRecord(newRecord)
                        self.record = newRecord
                    }
                    self.isGenerating = false
                    popToast("已换一批")
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    popToast("生成失败，请重试")
                }
            }
        }
    }

    private func regenerateField(_ field: RegenField) {
        guard !isGenerating else { return }
        ensureCloneIfNeeded()
        isGenerating = true
        regeneratingField = field

        let snapValue: ResultUndoValue
        switch field {
        case .title: snapValue = .title(record.noteTitle)
        case .body:  snapValue = .body(record.content)
        case .tags:  snapValue = .tags(record.tags)
        }

        Task {
            do {
                let adType = AdType(rawValue: record.adType) ?? .feedAd
                switch field {
                case .title:
                    let newValue = try await generator.regenerateTitle(
                        recordId: record.id,
                        keyword: record.inputKeyword,
                        product: nil,
                        adType: adType,
                        keywordHint: record.keywordHint
                    )
                    await MainActor.run {
                        record.noteTitle = newValue
                        finishRegen(snapField: field, snapValue: snapValue)
                    }
                case .body:
                    let newValue = try await generator.regenerateBody(
                        recordId: record.id,
                        keyword: record.inputKeyword,
                        product: nil,
                        adType: adType,
                        keywordHint: record.keywordHint,
                        existingTitle: record.noteTitle,
                        existingTags: record.tags
                    )
                    await MainActor.run {
                        record.content = newValue
                        finishRegen(snapField: field, snapValue: snapValue)
                    }
                case .tags:
                    let newValue = try await generator.regenerateTags(
                        recordId: record.id,
                        keyword: record.inputKeyword,
                        product: nil,
                        adType: adType,
                        keywordHint: record.keywordHint,
                        existingTitle: record.noteTitle,
                        existingContent: record.content
                    )
                    await MainActor.run {
                        record.tags = newValue
                        finishRegen(snapField: field, snapValue: snapValue)
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    regeneratingField = nil
                    popToast("生成失败，请重试")
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
