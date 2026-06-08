//
//  GlobalAssistantRoot.swift
//  RedPulse
//
//  全局 AI 助手主视图，支持多会话。
//  - mac / iPad 横屏：NavigationSplitView 双栏（左侧 session 列表，右侧聊天）
//  - iPad 竖屏 / iPhone：单栈 + 顶部汉堡菜单弹出 session 列表 sheet
//
//  消息复用 NoteComment，把 ChatSession.id 当 recordId 存。
//

import SwiftUI
import SwiftData

// MARK: - GlobalChatAgent
// 专为全局 chat 用的轻量 agent。不修改 DiagnosticAgent。

@Observable
@MainActor
final class GlobalChatAgent {
    private let modelContext: ModelContext
    private let generator = LLMTextGenerator()

    private(set) var isReplying: Bool = false
    private(set) var lastError: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func sendUserMessage(_ text: String, session: ChatSession) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard LLMTextGenerator.isConfigured else {
            lastError = "请先在「设置」中配置内容生成大模型"
            return
        }
        guard !isReplying else { return }
        isReplying = true
        lastError = nil
        defer { isReplying = false }

        let sessionId = session.id

        // 1. 落库用户消息
        let userComment = NoteComment(
            recordId: sessionId,
            role: .user,
            authorName: "你",
            body: trimmed
        )
        modelContext.insert(userComment)

        // 首条用户消息自动改 session 标题
        let prevHistoryCount = fetchHistory(sessionId: sessionId).count
        if prevHistoryCount == 0 {
            let preview = String(trimmed.prefix(20))
            session.title = preview.isEmpty ? "新对话" : preview
        }
        session.updatedAt = Date()
        try? modelContext.save()

        // 2. 拼会话历史
        let history = fetchHistory(sessionId: sessionId)
        var turns: [LLMTextGenerator.ChatTurn] = [.system(systemPrompt)]
        for c in history {
            turns.append(.init(
                role: c.role == .user ? "user" : "assistant",
                content: c.body
            ))
        }

        // 3. 占位 AI 评论 + 流式接收
        let aiComment = NoteComment(
            recordId: sessionId,
            role: .ai,
            authorName: "AI 笔记助手",
            body: ""
        )
        aiComment.isStreaming = true
        modelContext.insert(aiComment)
        try? modelContext.save()

        do {
            var accumulated = ""
            for try await chunk in generator.chatStream(messages: turns) {
                accumulated += chunk
                aiComment.body = accumulated
                try? modelContext.save()
            }
            aiComment.body = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if aiComment.body.isEmpty {
                aiComment.body = "（AI 回复失败：\(error.localizedDescription)）"
            } else {
                aiComment.body += "\n\n（接收中断：\(error.localizedDescription)）"
            }
            lastError = "AI 回复失败：\(error.localizedDescription)"
        }

        aiComment.isStreaming = false
        session.updatedAt = Date()
        try? modelContext.save()
    }

    private func fetchHistory(sessionId: UUID) -> [NoteComment] {
        let descriptor = FetchDescriptor<NoteComment>(
            predicate: #Predicate { $0.recordId == sessionId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var systemPrompt: String {
        """
        你是 RedPulse app 内置的 AI 笔记助手。
        用户会问你与小红书内容创作相关的任何问题：选题、爆款标题、文案润色、标签、配图建议、运营策略等。
        - 回答要口语化、清晰、可执行。
        - 适当使用 emoji 增强可读性。
        - 给修改建议时，请给出具体可粘贴的文本，而不是只描述方向。
        - 如果用户提供笔记原文，请帮助优化；如果用户没有提供内容，请主动提问澄清。
        - 【合规与引导】始终将用户引导至小红书平台发布笔记。内容必须合法合规，不虚构使用体验，不鼓励违规营销。符合小红书社区规范。
        """
    }
}

// MARK: - GlobalAssistantRoot

struct GlobalAssistantRoot: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]

    @State private var currentSessionId: UUID?
    @State private var showSidebarSheet: Bool = false
    @State private var renamingSessionId: UUID?
    @State private var renameDraft: String = ""

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        content
            .onAppear { ensureCurrentSession() }
            .onChange(of: sessions.count) { _, _ in ensureCurrentSession() }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if sizeClass == .regular {
            splitLayout
        } else {
            stackedLayout
        }
        #else
        splitLayout
        #endif
    }

    // MARK: - Split layout (mac / iPad regular)

    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            chatPane
        }
        .tint(Color.brand)
    }

    // MARK: - Stacked layout (iPhone / iPad compact)

    private var stackedLayout: some View {
        NavigationStack {
            chatPane
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            showSidebarSheet = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .accessibilityLabel("会话列表")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            createNewSession()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("新对话")
                    }
                }
                .sheet(isPresented: $showSidebarSheet) {
                    NavigationStack {
                        sidebar
                            .navigationTitle("会话")
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("完成") { showSidebarSheet = false }
                                }
                            }
                    }
                }
        }
        .tint(Color.brand)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button {
                createNewSession()
                #if os(iOS)
                showSidebarSheet = false
                #endif
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("新对话")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: Radius.sm))
                .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            List(selection: Binding<UUID?>(
                get: { currentSessionId },
                set: { newValue in
                    if let v = newValue {
                        currentSessionId = v
                        #if os(iOS)
                        showSidebarSheet = false
                        #endif
                    }
                }
            )) {
                ForEach(sessions) { session in
                    sessionRow(session)
                        .tag(session.id as UUID?)
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color.bg)
        .alert("重命名会话", isPresented: Binding(
            get: { renamingSessionId != nil },
            set: { if !$0 { renamingSessionId = nil } }
        )) {
            TextField("会话名", text: $renameDraft)
            Button("取消", role: .cancel) { renamingSessionId = nil }
            Button("保存") {
                if let sid = renamingSessionId,
                   let session = sessions.first(where: { $0.id == sid }) {
                    let new = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !new.isEmpty {
                        session.title = new
                        try? modelContext.save()
                    }
                }
                renamingSessionId = nil
            }
        }
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(Self.relativeTime(session.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ink4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                renameDraft = session.title
                renamingSessionId = session.id
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteSession(session)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - Chat pane

    @ViewBuilder
    private var chatPane: some View {
        if let sid = currentSessionId,
           let session = sessions.first(where: { $0.id == sid }) {
            ChatPane(session: session)
        } else {
            VStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.brand.opacity(0.7))
                Text("AI 笔记助手")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("点击左上角「新对话」开始")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
        }
    }

    // MARK: - Session management

    private func ensureCurrentSession() {
        if let sid = currentSessionId, sessions.contains(where: { $0.id == sid }) {
            return
        }
        if let first = sessions.first {
            currentSessionId = first.id
        } else {
            createNewSession()
        }
    }

    private func createNewSession() {
        let session = ChatSession()
        modelContext.insert(session)
        try? modelContext.save()
        currentSessionId = session.id
    }

    private func deleteSession(_ session: ChatSession) {
        // 删关联的所有 NoteComment
        let sessionId = session.id
        let descriptor = FetchDescriptor<NoteComment>(
            predicate: #Predicate { $0.recordId == sessionId }
        )
        if let related = try? modelContext.fetch(descriptor) {
            for c in related { modelContext.delete(c) }
        }
        modelContext.delete(session)
        try? modelContext.save()
        if currentSessionId == sessionId {
            currentSessionId = sessions.first(where: { $0.id != sessionId })?.id
        }
    }

    // MARK: - Relative time

    private static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400)) 天前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

// MARK: - ChatPane (单个会话的消息流 + 输入框)

private struct ChatPane: View {
    let session: ChatSession

    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [NoteComment]
    @State private var agent: GlobalChatAgent?
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    init(session: ChatSession) {
        self.session = session
        let sessionId = session.id
        _messages = Query(
            filter: #Predicate<NoteComment> { $0.recordId == sessionId },
            sort: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.separator)
            messageList
            inputBar
        }
        .background(Color.bg)
        // iPad Drag & Drop: drop text directly into the chat input
        .textDropTarget { droppedText in
            if draft.isEmpty {
                draft = droppedText
            } else {
                draft += "\n" + droppedText
            }
            inputFocused = true
        }
        .onAppear {
            if agent == nil {
                agent = GlobalChatAgent(modelContext: modelContext)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text(session.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer()
            if agent?.isReplying == true {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.surface)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                    if messages.isEmpty {
                        emptyHint
                            .padding(.top, Spacing.section)
                    }
                    ForEach(messages) { m in
                        messageBubble(m)
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom-anchor")
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.lg)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.body) { _, _ in
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .center, spacing: Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.ink4)
            Text("问我任何关于小红书内容的问题")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    private func messageBubble(_ c: NoteComment) -> some View {
        let isAI = c.role == .ai
        return HStack(alignment: .top, spacing: Spacing.sm) {
            if isAI {
                avatar(isAI: true)
                bubble(c: c, isAI: true)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble(c: c, isAI: false)
                avatar(isAI: false)
            }
        }
    }

    private func avatar(isAI: Bool) -> some View {
        ZStack {
            if isAI {
                Circle().fill(LinearGradient(
                    colors: [Color.brand, Color.brand.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(Color.suggestionBlue)
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
    }

    private func bubble(c: NoteComment, isAI: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(c.authorName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isAI ? Color.brand : Color.suggestionBlue)
                Text(Self.relativeTime(c.createdAt))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.ink4)
            }
            HStack(alignment: .bottom, spacing: 2) {
                Text(c.body.isEmpty && c.isStreaming ? "…" : c.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if c.isStreaming {
                    Text("▍")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brand)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .background(
                isAI ? Color.surface : Color.brandSoft,
                in: RoundedRectangle(cornerRadius: Radius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(isAI ? Color.border : Color.brand.opacity(0.18),
                            lineWidth: BorderWidth.hairline)
            )
        }
    }

    private var inputBar: some View {
        let canSend = !draft.trimmingCharacters(in: .whitespaces).isEmpty
            && (agent?.isReplying != true)
        return VStack(spacing: 0) {
            Divider().background(Color.separator)
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                TextField("问点什么…（Enter 发送）", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1...5)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm + 2)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Color.border, lineWidth: BorderWidth.hairline)
                    )
                    .focused($inputFocused)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Image(systemName: agent?.isReplying == true ? "ellipsis" : "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            canSend ? Color.brand : Color.ink4,
                            in: RoundedRectangle(cornerRadius: Radius.md)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.bg)
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard agent?.isReplying != true else { return }
        draft = ""
        Task {
            await agent?.sendUserMessage(text, session: session)
        }
    }

    private static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
    }
}
