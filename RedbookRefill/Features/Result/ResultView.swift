import SwiftUI
import SwiftData
import AVKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Regen field enum

enum RegenField {
    case title, body, tags

    var displayName: String {
        switch self {
        case .title: return "标题"
        case .body:  return "正文"
        case .tags:  return "标签"
        }
    }
}

// MARK: - Result mode (iPhone)

enum ResultMode {
    case edit, preview
}

// MARK: - Right panel tab (Krea 风格 AI 工具切换)

enum RightPanelTab: String {
    case image, video
}

// MARK: - Undo snapshot (in-memory only)

private enum UndoValue {
    case title(String)
    case body(String)
    case tags([String])
}

private struct UndoSnapshot: Identifiable {
    let id = UUID()
    let field: RegenField
    let value: UndoValue
    let deadline: Date
}

// MARK: - Section ID for collapse state

private enum SectionID: String, CaseIterable {
    case title, body, tags
    var label: String {
        switch self {
        case .title: return "笔记标题"
        case .body: return "正文"
        case .tags: return "标签"
        }
    }
}

// MARK: - ResultView

struct ResultView: View {
    @State private var record: GenerationRecord
    @Environment(Repository.self) private var repository
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allProducts: [Product]

    @Environment(CoachMarkManager.self) private var coachMarkManager
    @AppStorage("debug_mode") private var debugMode = false
    @AppStorage("has_seen_coach_marks_result") private var hasSeenCoachMarksResult = false

    @State private var jimengService = JimengService()

    @State private var newTagText = ""
    @State private var showAddTag = false
    @State private var showToast = false
    @State private var toastText = ""
    @State private var isGenerating = false
    @State private var regeneratingField: RegenField? = nil
    @State private var undo: UndoSnapshot? = nil
    @State private var undoCountdown: Int = 0
    @State private var expandedDebugSection: String? = nil
    @State private var imageCount: Int = 1
    @State private var isPreparingPrompts: Bool = false

    @State private var showEmojiPicker: Bool = false
    @State private var showGuestAlert: Bool = false
    @State private var selectedText: String = ""
    @State private var showRewriteDialog: Bool = false
    @State private var selectionToolbarVM = SelectionToolbarViewModel()
    #if os(macOS)
    @State private var selectionScreenOrigin: CGPoint = .zero
    #endif

    /// AI 助手按钮触发的 trigger（自增计数；ScrollViewReader 监听变化滚到评论锚点）
    @State private var aiAssistantScrollTrigger: Int = 0

    /// 小红书预览评论区 · AI 内容诊断师 agent
    /// 首次出现在 onAppear 时用 modelContext 绑定创建
    @State private var diagnosticAgent: DiagnosticAgent? = nil

    /// 一键打包状态
    @State private var isPackaging: Bool = false
    /// 生成完成后触发预览区高亮
    @State private var showPreviewHighlight: Bool = false
    @State private var showPhonePreview: Bool = false
    @State private var showInspirationSaved: Bool = false
    #if os(iOS)
    @State private var zipURLToShare: URL? = nil
    @State private var showPackageShareSheet: Bool = false
    #endif

    /// Collapsible sections
    @State private var collapsedSections: Set<String> = []

    /// 双面板编辑器宽度比例（用户可拖拽调整）
    @State private var editorFraction: CGFloat = 0.65
    /// Mac 窗口过窄时自动切 Tab 布局
    @State private var useCompactLayout: Bool = false

    /// iPhone: edit / preview mode toggle
    @State private var resultMode: ResultMode = .edit

    /// 右栏 Krea 风格 AI 工具区 tab
    @State private var rightPanelTab: RightPanelTab = .image
    /// 空态按钮脉冲动效触发
    @State private var pulseTrigger: Bool = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private let fromHistory: Bool
    @State private var cloneCreated = false

    private var generator: GeneratorProtocol {
        LLMTextGenerator.isConfigured ? LLMTextGenerator() : MockGenerator()
    }

    private var effectiveImageURLs: [String] {
        jimengService.generatedImageURLs.isEmpty ? record.imageUrls : jimengService.generatedImageURLs
    }

    private var effectiveVideoURL: String? {
        jimengService.generatedVideoURL ?? record.videoUrl
    }

    init(record: GenerationRecord, fromHistory: Bool = false) {
        _record = State(initialValue: record)
        self.fromHistory = fromHistory
    }

    /// iPad (regular) 或 Mac → 双面板；iPhone (compact) → 编辑/预览切换
    private var isDualPanel: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        Group {
            if isDualPanel {
                dualPanelLayout
            } else {
                tabbedLayout
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(fromHistory && cloneCreated ? "编辑副本" : "生成结果")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .disabled(isGenerating)
        .alert("访客次数已用完", isPresented: $showGuestAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("登录后可解锁无限生成次数")
        }
        .task {
            // 首次进入时绑 modelContext 创建 DiagnosticAgent（只创建一次）
            if diagnosticAgent == nil {
                diagnosticAgent = DiagnosticAgent(modelContext: modelContext)
            }
            // 首次进入结果页 → 触发配图+视频引导
            if !hasSeenCoachMarksResult {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run {
                    // 确保切到图片 tab 以便聚光灯对准正确位置
                    rightPanelTab = .image
                    coachMarkManager.start(steps: CoachMarkStep.resultSteps)
                }
            }
        }
        .onChange(of: coachMarkManager.isActive) { _, isActive in
            if !isActive && !hasSeenCoachMarksResult
                && coachMarkManager.steps.map(\.id) == CoachMarkStep.resultSteps.map(\.id) {
                hasSeenCoachMarksResult = true
            }
        }
        .onChange(of: coachMarkManager.currentStep) { _, step in
            // 切到视频 tab 以便聚光灯对准"生成视频"按钮
            if coachMarkManager.isActive
                && coachMarkManager.steps.map(\.id) == CoachMarkStep.resultSteps.map(\.id)
                && step == 1 {
                withAnimation { rightPanelTab = .video }
            }
        }
        // 划词改写小窗：保留作为 fallback，当浮动工具栏不可用时显示
        .sheet(isPresented: Binding(
            get: { showRewriteDialog && !selectionToolbarVM.isVisible },
            set: { showRewriteDialog = $0 }
        )) {
            RewritePromptDialog(
                selectedText: selectedText,
                sourceLabel: "正文",
                onConfirm: { instruction in
                    await performRewrite(instruction)
                    await MainActor.run { showRewriteDialog = false }
                },
                onCancel: { showRewriteDialog = false }
            )
            .presentationDetents([.fraction(0.5), .large])
            .presentationDragIndicator(.visible)
        }
        // New: floating glass selection toolbar
        // - iOS/iPad: inline overlay at the bottom of the editor
        // - macOS: system-wide floating panel that follows the mouse
        .overlay(alignment: .bottom) {
            #if os(macOS)
            MacSelectionToolbarBridge(viewModel: selectionToolbarVM)
            #else
            SelectionToolbarView(viewModel: selectionToolbarVM)
                .padding(.bottom, 8)
            #endif
        }
        .onChange(of: selectedText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                selectionToolbarVM.show(for: trimmed)
                #if os(macOS)
                selectionToolbarVM.selectionScreenOrigin = selectionScreenOrigin
                #endif
                if showRewriteDialog {
                    showRewriteDialog = false // suppress legacy dialog
                }
            } else {
                selectionToolbarVM.hide()
            }
        }
        .onAppear {
            setupSelectionToolbar()
        }
        .overlay {
            if showPhonePreview {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { showPhonePreview = false }
                    RedNoteReaderView(
                    currentRecord: record,
                    noteTitle: record.noteTitle,
                    content: record.content,
                    tags: record.tags,
                    imageUrls: effectiveImageURLs,
                    videoUrl: effectiveVideoURL,
                    adType: record.adType,
                    currentRecordId: record.id,
                    isDiagnosing: diagnosticAgent?.isDiagnosing ?? false,
                    onSendComment: { [diag = diagnosticAgent] text in
                        await diag?.sendUserMessage(text, replyTo: nil, record: record)
                    },
                    onApplySuggestion: { [diag = diagnosticAgent] comment in
                        diag?.applySuggestion(from: comment, to: record)
                    },
                    onIgnoreSuggestion: { [diag = diagnosticAgent] comment in
                        diag?.ignoreSuggestion(on: comment)
                    },
                    onStartDiagnose: { [diag = diagnosticAgent] in
                        Task { await diag?.diagnose(record: record) }
                    }
                )
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showPhonePreview)
    }

    // MARK: - Dual-panel layout (iPad / Mac)

    /// 自适应断点（三端共用，仅 iPad/Mac 调用）：
    /// - ≥ 1100pt：等宽 3 栏（文案 / AI / 预览）+ ❶❷❸ 步骤化叙事
    /// - 680-1100pt：可拖拽 2 栏（编辑器 + Krea 风 AI&预览右栏）
    /// - <  680pt：单栏 segmented（与 iPhone 一致）
    private static let tripaneBreakpoint: CGFloat = 1100
    private static let dualPaneBreakpoint: CGFloat = 680

    private var dualPanelLayout: some View {
        VStack(spacing: 0) {
            topToolbar
            GeometryReader { geometry in
                let totalWidth = geometry.size.width

                if totalWidth >= Self.tripaneBreakpoint {
                    tripaneContent(totalWidth: totalWidth)
                        .onAppear { useCompactLayout = false }
                } else if totalWidth >= Self.dualPaneBreakpoint {
                    dualPanelContent(totalWidth: totalWidth)
                        .onAppear { useCompactLayout = false }
                } else {
                    tabbedContent
                        .onAppear { useCompactLayout = true }
                        .onDisappear { useCompactLayout = false }
                }
            }
        }
        .background(Color.surfaceMuted.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            notificationsOverlay
        }
    }

    // MARK: - Top toolbar (贯通三栏，包含 换一批 / 打包 / 复制全部)

    private var topToolbar: some View {
        HStack(spacing: Spacing.md) {
            // 左侧 · 状态胶囊组（合规 / 配图 / 视频）
            statusDashboard

            Spacer(minLength: Spacing.sm)

            // 右侧 · 操作按钮组
            HStack(spacing: 2) {
                // 换一批
                Button { regenerateAll() } label: {
                    Group {
                        if isGenerating && regeneratingField == nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(Typography.toolbarIcon)
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(ToolbarButtonStyle())
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.5 : 1)
                .help("换一批")
                .keyboardShortcut("r", modifiers: .command)

                // 打包
                Button { startPackaging() } label: {
                    Group {
                        if isPackaging {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "archivebox")
                                .font(Typography.toolbarIcon)
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(ToolbarButtonStyle())
                .disabled(isPackaging)
                .opacity(isPackaging ? 0.5 : 1)
                .help("打包素材")

                // 小红书浏览 — 仅 iPad/Mac（iPhone 用预览 Tab）
                if isDualPanel {
                Button { showPhonePreview = true } label: {
                    Image(systemName: "eye.fill")
                        .font(Typography.toolbarIcon)
                        .foregroundStyle(Color.ink)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(ToolbarButtonStyle())
                .help("小红书浏览模式")
                .keyboardShortcut("p", modifiers: .command)
                }

                // 复制全部（主操作）
                Button { copyAll() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("复制全部")
                            .font(Typography.toolbarLabel)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: Adaptive.buttonHeight)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, Adaptive.horizontalPageMargin)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.border)
                .frame(height: BorderWidth.hairline)
        }
        #if os(iOS)
        // 打包后弹分享 sheet（iPad / iPhone）
        .sheet(isPresented: $showPackageShareSheet) {
            if let url = zipURLToShare {
                PackageShareSheet(items: [url])
            }
        }
        #endif
    }

    // MARK: - AI 助手快捷入口（toolbar 中间）

    /// 品牌色胶囊按钮，宽屏带文字、窄屏只显示图标
    // (AI 助手按钮已移除)
    private var aiAssistantButton: some View {
        EmptyView()
    }

    // MARK: - 状态心表盘（左侧 toolbar · 3 pill）

    private var statusDashboard: some View {
        // ViewThatFits 自动挑能塞下的版本：宽时显示完整 pill，窄时仅圆点
        ViewThatFits(in: .horizontal) {
            statusPillRow(compact: false)
            statusPillRow(compact: true)
        }
    }

    @ViewBuilder
    private func statusPillRow(compact: Bool) -> some View {
        HStack(spacing: 3) {
            // 1. 合规
            statusPill(
                dotColor: hasGeneratedContent ? Color.success : Color.ink4,
                bgColor: hasGeneratedContent ? Color.successBg : Color.surfaceMuted,
                icon: hasGeneratedContent ? "checkmark" : nil,
                text: hasGeneratedContent ? "合规" : "待生成",
                tooltip: hasGeneratedContent ? "已通过基础合规校验" : "尚未生成笔记内容",
                compact: compact
            )

            // 2. 配图
            statusPill(
                dotColor: imageStatusColor,
                bgColor: imageStatusBgColor,
                pulse: jimengService.isGeneratingImage,
                icon: imageStatusIcon,
                text: imageStatusText,
                tooltip: "AI 配图当前状态",
                compact: compact
            )

            // 3. 视频
            statusPill(
                dotColor: videoStatusColor,
                bgColor: videoStatusBgColor,
                pulse: jimengService.isGeneratingVideo,
                icon: videoStatusIcon,
                text: videoStatusText,
                tooltip: "AI 视频当前状态",
                compact: compact
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
    }

    private var hasGeneratedContent: Bool {
        !record.noteTitle.isEmpty || !record.content.isEmpty || !record.tags.isEmpty
    }

    private var imageStatusColor: Color {
        if jimengService.isGeneratingImage { return .orange }
        if !effectiveImageURLs.isEmpty { return Color.success }
        return Color.ink4
    }
    private var imageStatusBgColor: Color {
        if jimengService.isGeneratingImage { return Color.warningBg }
        if !effectiveImageURLs.isEmpty { return Color.successBg }
        return Color.surfaceMuted
    }
    private var imageStatusIcon: String? {
        if jimengService.isGeneratingImage { return nil }
        if !effectiveImageURLs.isEmpty { return "checkmark" }
        return nil
    }
    private var imageStatusText: String {
        if jimengService.isGeneratingImage { return "生成中…" }
        if !effectiveImageURLs.isEmpty { return "已出 \(effectiveImageURLs.count) 张" }
        return "未出图"
    }

    private var videoStatusColor: Color {
        if jimengService.isGeneratingVideo { return .orange }
        if effectiveVideoURL != nil { return Color.success }
        return Color.ink4
    }
    private var videoStatusBgColor: Color {
        if jimengService.isGeneratingVideo { return Color.warningBg }
        if effectiveVideoURL != nil { return Color.successBg }
        return Color.surfaceMuted
    }
    private var videoStatusIcon: String? {
        if jimengService.isGeneratingVideo { return nil }
        if effectiveVideoURL != nil { return "checkmark" }
        return nil
    }
    private var videoStatusText: String {
        if jimengService.isGeneratingVideo { return "生成中…" }
        if effectiveVideoURL != nil { return "已出视频" }
        return "未出视频"
    }

    /// 单个状态 pill；compact 为 true 时折叠为纯圆点 / 勾
    private func statusPill(
        dotColor: Color,
        bgColor: Color = Color.surface,
        pulse: Bool = false,
        icon: String? = nil,
        text: String,
        tooltip: String,
        compact: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(dotColor)
                } else {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 9, height: 9)
                        .scaleEffect(pulse && pulseTrigger ? 1.3 : 1.0)
                        .animation(
                            pulse ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                            value: pulseTrigger
                        )
                }
            }
            .frame(width: 14, height: 14)

            if !compact {
                Text(text)
                    .font(Typography.toolbarLabel)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .frame(height: 34)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
        .help(tooltip)
    }

    // MARK: - Notifications overlay (undo banner + toast bubble，浮在底部)

    @ViewBuilder
    private var notificationsOverlay: some View {
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
            .padding(.bottom, Spacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Tripane content (≥1100pt · 2 栏 可拖拽)

    private static let columnGap: CGFloat = 12
    private static let pageHPad: CGFloat = 16

    private func tripaneContent(totalWidth: CGFloat) -> some View {
        let gap = Self.columnGap
        let hPad = Self.pageHPad
        let usableWidth = totalWidth - hPad * 2 - gap
        let editorW = min(max(usableWidth * editorFraction, 320), usableWidth * 0.78)

        return HStack(spacing: 0) {
            stepColumn(step: 1, title: "文案内容", icon: "text.alignleft") {
                editorPanel
            }
            .frame(width: editorW)

            // 可拖拽分隔条
            dragHandle(usableWidth: usableWidth, editorWidth: editorW, gap: gap)

            stepColumn(step: 2, title: "AI 生成", icon: "sparkles") {
                aiToolColumnBody
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func dragHandle(usableWidth: CGFloat, editorWidth: CGFloat, gap: CGFloat, maxFraction: CGFloat = 0.78) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: gap)
            .contentShape(Rectangle())
        #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
        #endif
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newW = editorWidth + value.translation.width
                        editorFraction = min(max(newW / usableWidth, 0.25), maxFraction)
                    }
            )
    }

    /// 列卡片容器：顶部 ❶❷❸ 步骤徽章 + 标题 + 自定义内容
    /// 白色背板 + 圆角 + 浅描边，浮在灰底之上
    @ViewBuilder
    private func stepColumn<Content: View>(
        step: Int,
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text("\(step)")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.brand, in: Circle())
                Image(systemName: icon)
                    .font(Typography.bodySmall.weight(.semibold))
                    .foregroundStyle(Color.ink3)
                Text(title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.border).frame(height: BorderWidth.hairline)
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    /// 3 栏模式下 · 第 2 栏 AI 工具区（不带预览，只放 AI 配图/视频 segmented + 内容）
    /// stepColumn 已经提供白卡 chrome，这里直接用 inner 版避免嵌套
    private var aiToolColumnBody: some View {
        ScrollView {
            aiToolInner
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xl)
        }
    }

    /// 3 栏模式下 · 第 3 栏纯手机预览
    /// 用 GeometryReader 读取当前列宽，按列宽自适应缩放 PublishPreviewView
    private var previewColumnBody: some View {
        GeometryReader { geo in
            let phoneW = Self.responsivePreviewWidth(containerWidth: geo.size.width)
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

    /// 把 PublishPreviewView + 评论区 agent 接入封装成一个 View
    /// 两个 layout 路径（3 栏 previewColumnBody / 2 栏 previewPanel）都复用这个
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
            }
        )
    }

    /// 计算给定容器宽度下，预览卡的合适宽度
    /// - 上限 375pt（设计稿原始尺寸）
    /// - 下限 240pt（再小内部字号会挤死，由 ScrollView 兜底允许水平滚）
    /// - 中间按 容器宽 - 32pt 左右内边距 自适应
    private static func responsivePreviewWidth(containerWidth: CGFloat) -> CGFloat {
        let target = containerWidth - 32
        return max(min(target, 375), 240)
    }

    private func dualPanelContent(totalWidth: CGFloat) -> some View {
        let gap = Self.columnGap
        let hPad = Self.pageHPad
        let usableWidth = totalWidth - hPad * 2 - gap
        let editorMax = min(usableWidth * 0.72, 960)
        let editorMin = max(420, usableWidth * 0.42)
        let editorWidth = min(max(usableWidth * editorFraction, editorMin), editorMax)

        return HStack(spacing: 0) {
            stepColumn(step: 1, title: "文案内容", icon: "text.alignleft") {
                editorPanel
            }
            .frame(width: editorWidth)

            // 可拖拽分隔条
            dragHandle(usableWidth: usableWidth, editorWidth: editorWidth, gap: gap, maxFraction: 0.7)

            stepColumn(step: 2, title: "AI 生成", icon: "sparkles") {
                aiToolColumnBody
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 窄窗口 / compact 模式下的编辑
    private var tabbedContent: some View {
        editorPanel
    }

    // MARK: - Tabbed layout (iPhone)

    private var tabbedLayout: some View {
        VStack(spacing: 0) {
            topToolbar

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
        .background(Color.surfaceMuted.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            notificationsOverlay
        }
    }

    // MARK: - Editor panel (轻松阅读流)

    private var editorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // ── 顶部工具栏 ──
                toolbarRow
                    .padding(.bottom, Spacing.xs)

                // ── 标题（大号字体加粗） ──
                titleEditor

                Divider()
                    .background(Color.border)

                // ── 正文（带行高与选中文字改写） ──
                bodyEditor

                Divider()
                    .background(Color.border)

                // ── 标签（正文底部流式标签组） ──
                tagsEditor
                    .padding(.top, Spacing.xs)

                if debugMode {
                    debugPromptSection
                        .padding(.top, Spacing.md)
                }
                
                Spacer().frame(height: 80)
            }
            .padding(Adaptive.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.surface)
    }

    /// 统一工具栏：复制全部 + 重写菜单
    private var toolbarRow: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            Button { copyAll() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .medium))
                    Text("复制全部").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Menu {
                Button { Task { await regenerateAll() } } label: { Label("换一批", systemImage: "arrow.triangle.2.circlepath") }
                Button { Task { await regenerateField(.title) } } label: { Label("重写标题", systemImage: "textformat") }
                Button { Task { await regenerateField(.body) } } label: { Label("重写正文", systemImage: "doc.text") }
                Button { Task { await regenerateField(.tags) } } label: { Label("重写标签", systemImage: "number") }
                Divider()
                if !record.noteTitle.isEmpty {
                    Button { saveToInspiration(type: .snippet, content: record.noteTitle, source: "标题") } label: { Label("收藏标题到灵感板", systemImage: "heart") }
                }
                if !record.content.isEmpty {
                    Button { saveToInspiration(type: .snippet, content: record.content, source: "正文") } label: { Label("收藏正文到灵感板", systemImage: "heart") }
                }
                if !record.tags.isEmpty {
                    Button { saveToInspiration(type: .keyword, content: record.tags.map { "#\($0)" }.joined(separator: " "), source: "标签") } label: { Label("收藏标签到灵感板", systemImage: "heart") }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .medium))
                    Text("重写").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 7))
            }
            .disabled(isGenerating)
        }
    }

    // MARK: - Preview panel (iPhone)
    // 全宽模拟小红书笔记，顶部保留 AI 生图/生视频

    private var previewPanel: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // AI 生图/生视频工具
                        aiToolInner

                        Divider()

                        // 全宽小红书预览（减去外层 padding）
                        previewWithComments(previewWidth: max(geo.size.width - Adaptive.horizontalPageMargin * 2, 320))
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

    /// AI 工具 inner：纯内容（segmented + 状态徽章 + section 切换），无卡片 chrome
    /// 嵌进 stepColumn 时直接用这个，避免双层卡
    private var aiToolInner: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // segmented picker
            Picker("AI 工具", selection: $rightPanelTab) {
                Label("AI 配图", systemImage: "paintpalette").tag(RightPanelTab.image)
                Label("AI 视频", systemImage: "film").tag(RightPanelTab.video)
            }
            .pickerStyle(.segmented)

            // 状态徽章
            aiStatusBadge

            // 内容
            Group {
                if rightPanelTab == .image {
                    imageGenSection
                } else {
                    videoGenSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { pulseTrigger = true }
    }

    /// AI 工具卡（带 chrome）：留作兼容，未嵌 stepColumn 的场景仍可用
    private var aiToolCard: some View {
        aiToolInner
            .padding(Spacing.lg)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Color.border, lineWidth: BorderWidth.hairline)
            )
    }

    /// 状态 pill：未生成（灰）/ 生成中（橙脉冲）/ 已生成（绿）
    @ViewBuilder
    private var aiStatusBadge: some View {
        let isImage = rightPanelTab == .image
        let isBusy = isImage ? jimengService.isGeneratingImage : jimengService.isGeneratingVideo
        let imageCount = effectiveImageURLs.count
        let hasVideo = effectiveVideoURL != nil
        let hasContent = isImage ? imageCount > 0 : hasVideo

        let (dotColor, text): (Color, String) = {
            if isBusy {
                return (.orange, isImage ? "生成中…" : "生成中…")
            }
            if hasContent {
                return (.green, isImage ? "已生成 \(imageCount) 张" : "已生成视频")
            }
            return (Color.ink3, "未生成")
        }()

        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .scaleEffect(isBusy && pulseTrigger ? 1.25 : 1.0)
                .animation(
                    isBusy ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                    value: pulseTrigger
                )
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Color.ink3)
        }
    }

    // MARK: - Collapsible section container

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        id: String,
        label: String,
        field: RegenField?,
        counter: String? = nil,
        showsCopy: Bool = true,
        copyText: @escaping () -> String = { "" },
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCollapsed = collapsedSections.contains(id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedSections.remove(id)
                    } else {
                        collapsedSections.insert(id)
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Color.ink3)
                        .frame(width: 16)
                    Text(label).editorialLabel()
                    if let counter {
                        Text(counter).font(Typography.monoSmall).foregroundStyle(Color.ink3)
                    }
                    Spacer()
                    if isDualPanel {
                        if showsCopy {
                            Button {
                                let text = copyText()
                                guard !text.isEmpty else {
                                    popToast("\(label)为空")
                                    return
                                }
                                copyToClipboard(text)
                                popToast("已复制\(label)")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("复制")
                                }
                            }
                            .buttonStyle(GhostButtonStyle())
                            .help("复制\(label)")
                        }
                        if let field {
                            Button {
                                regenerateField(field)
                            } label: {
                                HStack(spacing: 4) {
                                    if regeneratingField == field {
                                        Text("Thinking...")
                                            .font(Typography.bodySmall.weight(.medium))
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("重生成")
                                    }
                                }
                            }
                            .buttonStyle(GhostButtonStyle())
                            .disabled(isGenerating)
                        }
                    } else if showsCopy || field != nil {
                        Menu {
                            if showsCopy {
                                Button {
                                    let text = copyText()
                                    guard !text.isEmpty else {
                                        popToast("\(label)为空")
                                        return
                                    }
                                    copyToClipboard(text)
                                    popToast("已复制\(label)")
                                } label: {
                                    Label("复制\(label)", systemImage: "doc.on.doc")
                                }
                            }
                            if let field {
                                Button {
                                    regenerateField(field)
                                } label: {
                                    Label("重生成\(label)", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .disabled(isGenerating)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(Typography.caption.weight(.semibold))
                                .foregroundStyle(Color.ink3)
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.horizontal, Spacing.lg)
                    content()
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.thin)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Title editor (小红书笔记风格)

    private var titleEditor: some View {
        TextField("输入笔记标题", text: Binding(
            get: { record.noteTitle },
            set: {
                ensureCloneIfNeeded()
                record.noteTitle = String($0.prefix(40))
                record.isEdited = true
            }
        ))
        .font(.system(size: 22, weight: .bold, design: .serif))
        .foregroundStyle(Color.ink)
        .textFieldStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Body editor

    private static let quickEmojis = ["✨", "🔥", "💄", "💰", "🎯", "📸", "🌟", "💡", "🎁", "❤️", "😍", "👀"]

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Group {
                #if os(macOS)
                SelectableTextEditor(
                    text: Binding(
                        get: { record.content },
                        set: {
                            ensureCloneIfNeeded()
                            record.content = $0
                            record.isEdited = true
                        }
                    ),
                    selectedText: $selectedText,
                    showRewriteDialog: $showRewriteDialog,
                    selectionScreenOrigin: $selectionScreenOrigin,
                    font: .systemFont(ofSize: 16),
                    lineSpacing: 7
                )
                #else
                SelectableTextEditor(
                    text: Binding(
                        get: { record.content },
                        set: {
                            ensureCloneIfNeeded()
                            record.content = $0
                            record.isEdited = true
                        }
                    ),
                    selectedText: $selectedText,
                    showRewriteDialog: $showRewriteDialog,
                    font: .systemFont(ofSize: 16),
                    lineSpacing: 7
                )
                #endif
            }
            .frame(minHeight: 380) // 显著增大最小高度，避免在输入中等长度文案时出现内部双重滚动条
            .padding(.bottom, 4)

            // 编辑器工具栏：表情选择 + 字符数统计
            HStack(spacing: Spacing.md) {
                Button {
                    HapticManager.lightImpact()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showEmojiPicker.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 13, weight: .medium))
                        Text("表情")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(showEmojiPicker ? Color.brand : Color.ink3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showEmojiPicker ? Color.brandSoft : Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                if showEmojiPicker {
                    emojiGrid
                        .transition(.opacity)
                }
                
                Spacer()
                
                Text("\(record.content.count) 字")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    /// 常用 emoji 横向滚动行 — 替代原来的 6 列网格，节省 ~60pt 纵向空间
    private var emojiGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(Self.quickEmojis.prefix(6), id: \.self) { emoji in
                    Button {
                        HapticManager.lightImpact()
                        ensureCloneIfNeeded()
                        record.content += emoji
                        record.isEdited = true
                        withAnimation { showEmojiPicker = false }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 34)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tags editor

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FlowLayout(spacing: Spacing.sm) {
                ForEach(Array(record.tags.enumerated()), id: \.offset) { index, tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                            .font(Typography.caption)
                        Button {
                            guard index < record.tags.count else { return }
                            ensureCloneIfNeeded()
                            record.tags.remove(at: index)
                            record.isEdited = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(Typography.micro.weight(.bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .pillStyle()
                }

                Button {
                    showAddTag = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(Typography.micro.weight(.bold))
                        Text("添加标签")
                            .font(Typography.caption)
                    }
                }
                .buttonStyle(.plain)
                .pillStyle(foreground: .ink3, background: .surface, borderColor: .borderStrong)
            }

            if showAddTag {
                HStack(spacing: Spacing.sm) {
                    TextField("标签内容", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(Typography.bodySmall)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(Color.surfaceMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .stroke(Color.border, lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .onSubmit(addTag)

                    Button("添加", action: addTag)
                        .buttonStyle(GhostButtonStyle(tint: .brand))

                    Button {
                        showAddTag = false
                        newTagText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - AI 配图生成

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
                    // Has content but no image prompt → offer to auto-generate
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

    @ViewBuilder
    private var imageGallery: some View {
        let count = effectiveImageURLs.count
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if count > 1 {
                HStack(spacing: 4) {
                    Spacer()
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(i == galleryPageIndex ? Color.brand : Color.ink4)
                            .frame(width: 6, height: 6)
                    }
                    Spacer()
                }
            }

            TabView(selection: $galleryPageIndex) {
                ForEach(Array(effectiveImageURLs.enumerated()), id: \.offset) { i, url in
                    VStack(spacing: Spacing.sm) {
                        AsyncImage(url: URL.safeURL(from: url)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 320, height: 427)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            case .failure:
                                Rectangle().fill(Color.surfaceMuted).frame(width: 320, height: 427)
                                    .overlay(VStack(spacing: 4) {
                                        Image(systemName: "photo.badge.exclamationmark").font(.system(size: 22))
                                        Text("加载失败").font(Typography.caption)
                                    }.foregroundStyle(Color.ink3))
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            case .empty:
                                Rectangle().fill(Color.surfaceMuted).frame(width: 320, height: 427)
                                    .overlay(ProgressView())
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            @unknown default: EmptyView()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 15)
                                .onEnded { value in
                                    guard count > 1 else { return }
                                    if value.translation.width < -40 {
                                        withAnimation { galleryPageIndex = min(galleryPageIndex + 1, count - 1) }
                                    } else if value.translation.width > 40 {
                                        withAnimation { galleryPageIndex = max(galleryPageIndex - 1, 0) }
                                    }
                                }
                        )
                        .contextMenu {
                            Button { copyToClipboard(url); popToast("已复制图片链接") } label: { Label("复制图片链接", systemImage: "link") }
                            Button { Task { await saveImage(url: url) } } label: { Label("保存到本地", systemImage: "square.and.arrow.down") }
                        }

                        HStack(spacing: Spacing.sm) {
                            Button { copyToClipboard(url); popToast("已复制图片链接") } label: {
                                Label("复制链接", systemImage: "link")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(Color.surfaceMuted).foregroundStyle(Color.ink2)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.border, lineWidth: BorderWidth.hairline))
                            }.buttonStyle(.plain)
                            Button { Task { await saveImage(url: url) } } label: {
                                Label("保存", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(Color.brand).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            }.buttonStyle(.plain)
                        }
                    }
                    .tag(i)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: 427 + 60)

            aiAnnotation("图片由AI生成")
        }
    }

    // MARK: - AI 视频生成

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
                    copyToClipboard(url)
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
                    Task { await saveVideo(url: url) }
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





    // MARK: - Debug Prompt Section

    private var debugPromptSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "ladybug")
                    .font(Typography.body)
                    .foregroundStyle(Color.brand)
                Text("调试信息")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Color.ink)
            }
            .padding(Spacing.lg)

            Divider().padding(.horizontal, Spacing.lg)

            debugPromptRow(title: "文生文提示词", icon: "text.bubble", content: debugTextPrompt)
            Divider().padding(.horizontal, Spacing.lg)
            debugPromptRow(title: "文生图提示词", icon: "photo", content: record.imagePrompt.isEmpty ? "暂无" : record.imagePrompt)
            Divider().padding(.horizontal, Spacing.lg)
            debugPromptRow(title: "图生视频提示词", icon: "video", content: record.videoPrompt.isEmpty ? "暂无" : record.videoPrompt)
        }
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.border, lineWidth: BorderWidth.thin))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func debugPromptRow(title: String, icon: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    expandedDebugSection = expandedDebugSection == title ? nil : title
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(Typography.caption).foregroundStyle(Color.ink3).frame(width: 16)
                    Text(title).font(Typography.bodySmall.weight(.medium)).foregroundStyle(Color.ink2)
                    Spacer()
                    Image(systemName: expandedDebugSection == title ? "chevron.up" : "chevron.down")
                        .font(Typography.caption.weight(.semibold)).foregroundStyle(Color.ink3)
                }
            }
            .buttonStyle(.plain)

            if expandedDebugSection == title {
                Text(content)
                    .font(Typography.mono)
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
    }

    private var debugTextPrompt: String {
        let keyword = record.inputKeyword
        let hint = record.keywordHint.map { "\n风格提示：\($0)" } ?? ""
        return """
        [文生文提示词]
        你是一个小红书文案专家。产品：\(keyword)
        广告类型：\(record.adType)
        关键词：\(keyword)\(hint)

        请根据以上信息生成一篇小红书笔记，包含标题、正文、标签。
        """
    }

    // 旧的 floatingActionDock 已迁移到顶部 topToolbar（换一批 / 打包 / 复制全部）

    // MARK: - Shared helpers

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

    // MARK: - Clone for history mode

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
        modelContext.insert(newRecord)
        record = newRecord
        cloneCreated = true
    }

    // MARK: - Undo banner

    private func undoBanner(_ snap: UndoSnapshot) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
            Text("\(snap.field.displayName)已更新")
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

    // MARK: - Regenerate actions

    private func regenerateAll() {
        guard !isGenerating else { return }
        HapticManager.mediumImpact()
        ensureCloneIfNeeded()
        isGenerating = true

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
                let resp = try await generator.generate(request)
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
                        modelContext.insert(newRecord)
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

        let snapValue: UndoValue
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

    private func finishRegen(snapField: RegenField, snapValue: UndoValue) {
        record.isEdited = true
        isGenerating = false
        regeneratingField = nil
        let snap = UndoSnapshot(field: snapField, value: snapValue, deadline: Date().addingTimeInterval(5))
        undoCountdown = 5
        withAnimation(.easeOut(duration: AnimDuration.fast)) {
            undo = snap
        }
        startUndoTimer(for: snap)
    }

    private func startUndoTimer(for snap: UndoSnapshot) {
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

    private func performUndo(_ snap: UndoSnapshot) {
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

    // MARK: - Selection Toolbar setup

    /// Wires the SelectionToolbarViewModel to the existing LLM pipeline.
    /// The ViewModel calls `onGenerate` when a quick action is tapped, and
    /// `onReplace` when the user wants to inline-replace the selected text.
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

    // MARK: - AI rewrite (划词改写) — legacy

    /// 把用户的修改指令传给 LLM，用结果替换选中文字。
    /// (Kept for backward compatibility with RewritePromptDialog)
    private func performRewrite(_ instruction: String) async {
        let original = selectedText
        guard !original.isEmpty else { return }
        do {
            let result = try await generator.transformText(
                command: instruction,
                selectedText: original,
                context: String(record.content.prefix(200))
            )
            await MainActor.run {
                ensureCloneIfNeeded()
                record.content = record.content.replacingOccurrences(of: original, with: result)
                record.isEdited = true
                selectedText = ""
                popToast("已按你的指令改写")
            }
        } catch {
            await MainActor.run {
                popToast("改写失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tag add

    private func addTag() {
        ensureCloneIfNeeded()
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAddTag = false
            newTagText = ""
            return
        }
        guard record.tags.count < 10 else {
            popToast("最多 10 个标签")
            return
        }
        record.tags.append(trimmed)
        record.isEdited = true
        newTagText = ""
        showAddTag = false
    }

    // MARK: - Copy

    private func copyAll() {
        HapticManager.lightImpact()
        var parts: [String] = []
        if !record.noteTitle.isEmpty { parts.append("【笔记标题】\(record.noteTitle)") }
        if !record.content.isEmpty { parts.append("【正文】\(record.content)") }
        if !record.tags.isEmpty { parts.append("【标签】\(record.tags.map { "#\($0)" }.joined(separator: " "))") }
        if !record.imageSuggestion.isEmpty { parts.append("【配图建议】\(record.imageSuggestion)") }

        copyToClipboard(parts.joined(separator: "\n"))
        popToast("全部内容已复制")
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit) && !os(macOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Save to Inspiration Board

    private func saveToInspiration(type: InspirationType, content: String, source: String) {
        let item = InspirationItem(type: type, content: content, source: source)
        repository.saveInspirationItem(item)
        popToast("已收藏到灵感板")
    }

    // MARK: - Auto-generate image prompt from content

    /// 根据已有文案内容，调用 LLM 自动总结生成一个英文配图提示词。
    /// 提示词存入 record.imagePrompt（对用户不可见，仅在 debug 模式显示）。
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
                try? modelContext.save()
                popToast("配图提示词已生成")
            }
        } catch {
            await MainActor.run {
                popToast("生成失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Image generation

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
            try? modelContext.save()
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

    // MARK: - Video generation

    private func generateVideo() async {
        ensureCloneIfNeeded()
        await jimengService.generateVideo(prompt: record.videoPrompt, referenceImageURLs: effectiveImageURLs)
        if let url = jimengService.generatedVideoURL {
            record.videoUrl = url
            try? modelContext.save()
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

    // MARK: - Save to local

    private func saveImage(url: String) async {
        guard let imageURL = URL.safeURL(from: url) else {
            popToast("图片链接无效")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            let ext = imageURL.pathExtension.isEmpty ? "png" : imageURL.pathExtension
            #if os(macOS)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "redbook-image.\(ext)"
                if panel.runModal() == .OK, let dest = panel.url {
                    do {
                        try data.write(to: dest)
                        popToast("已保存图片")
                    } catch {
                        popToast("保存失败：\(error.localizedDescription)")
                    }
                }
            }
            #elseif canImport(UIKit)
            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                popToast("已保存到相册")
            } else {
                popToast("图片格式无法识别")
            }
            #endif
        } catch {
            popToast("下载失败：\(error.localizedDescription)")
        }
    }

    private func saveAllImages() async {
        let urls = effectiveImageURLs
        guard !urls.isEmpty else {
            popToast("没有可下载的图片")
            return
        }
        #if os(macOS)
        let dest: URL? = await MainActor.run { () -> URL? in
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
        var ok = 0
        var fail = 0
        for (idx, url) in urls.enumerated() {
            guard let remote = URL.safeURL(from: url) else { fail += 1; continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                let ext = remote.pathExtension.isEmpty ? "png" : remote.pathExtension
                let filename = "redbook-image-\(idx + 1).\(ext)"
                try data.write(to: dir.appendingPathComponent(filename))
                ok += 1
            } catch {
                fail += 1
            }
        }
        popToast(fail == 0 ? "已保存 \(ok) 张图片" : "保存 \(ok) 张，失败 \(fail) 张")
        #elseif canImport(UIKit)
        var ok = 0
        var fail = 0
        for url in urls {
            guard let remote = URL.safeURL(from: url) else { fail += 1; continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                if let img = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                    ok += 1
                } else { fail += 1 }
            } catch { fail += 1 }
        }
        popToast(fail == 0 ? "已保存 \(ok) 张到相册" : "保存 \(ok) 张，失败 \(fail) 张")
        #endif
    }

    private func saveVideo(url: String) async {
        guard let videoURL = URL.safeURL(from: url) else {
            popToast("视频链接无效")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: videoURL)
            let ext = videoURL.pathExtension.isEmpty ? "mp4" : videoURL.pathExtension
            #if os(macOS)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "redbook-video.\(ext)"
                if panel.runModal() == .OK, let dest = panel.url {
                    do {
                        try data.write(to: dest)
                        popToast("已保存视频")
                    } catch {
                        popToast("保存失败：\(error.localizedDescription)")
                    }
                }
            }
            #elseif canImport(UIKit)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("redbook-video.\(ext)")
            try data.write(to: tmp)
            popToast("视频已下载，请在文件 app 中查看")
            #endif
        } catch {
            popToast("下载失败：\(error.localizedDescription)")
        }
    }

    private func popToast(_ text: String) {
        toastText = text
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showToast = false }
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

    // MARK: - 一键打包

    private func startPackaging() {
        guard !isPackaging else { return }
        Task {
            await MainActor.run { isPackaging = true }
            let packager = AssetPackager()
            do {
                #if os(macOS)
                // Mac：先弹 NSOpenPanel 让用户选目标目录，然后写到目录里
                let destDir = try await pickMacDestDir()
                let resultURL = try await packager.package(record: record, to: destDir)
                await MainActor.run {
                    isPackaging = false
                    popToast("已打包到 \(resultURL.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([resultURL])
                }
                #else
                // iPad / iPhone：打成 zip 后弹分享 sheet
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

    #if os(macOS)
    @MainActor
    private func pickMacDestDir() async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
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
    }
    #endif

    // MARK: - AI 工具空态引导（Krea 风格）

    /// 未生成任何产物时的引导占位：大图标 + 引导文案 + 红色脉冲按钮
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

            // 仅图片 tab 显示数量选择（1-4 张）
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
            .scaleEffect(pulseTrigger ? 1.05 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: pulseTrigger
            )

            Spacer().frame(height: Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .coachMarkTarget(rightPanelTab == .image ? "gen_image" : "gen_video")
    }

    /// 空态下的居中数量选择器（不带"数量"标签和右侧文案，更紧凑）
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
}

#if os(iOS)
/// iPad / iPhone 分享 sheet 桥接 — 把 zip URL 交给系统 share sheet
private struct PackageShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
