//
//  RedPulseApp.swift
//  灵芯
//
//  App entry. Owns the SwiftData container.
//  No auth required — app opens directly to the main tab view.
//

import SwiftUI
import SwiftData

// MARK: - App-wide commands (macOS menu bar)

struct AppCommands: Commands {
    @Binding var selectedTab: TabItem
    var showAIWindow: () -> Void

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            // ⌘+, 快捷键：直接切到「我的」tab（设置在 tab 内的 NavigationStack 里）
            // — 完全在主窗口内，不再弹 sheet 跑出主窗口
            Button("设置…") { selectedTab = .profile }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("生成笔记") {
                selectedTab = .generate
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(selectedTab == .generate)

            Button("产品库") {
                selectedTab = .products
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(selectedTab == .products)

            Button("历史记录") {
                selectedTab = .history
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(selectedTab == .history)
        }

        #if os(macOS)
        CommandGroup(replacing: .newItem) {
            Button("AI 笔记助手") {
                showAIWindow()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        #endif

        CommandGroup(replacing: .help) {
            Button("灵芯 帮助") {
                if let url = URL(string: "https://example.com/help") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }
        }
    }
}

@main
struct RedPulseApp: App {
    /// 跨 view 生命周期持有"生成任务"状态 — 切到别的 tab 后 task 不丢失
    @State private var generationSession = GenerationSession()
    /// 跨 view 持有"重新生成"任务（文本/图/视频），跟顶层 mainContext 绑定
    @State private var regenSession: RegenSession
    @AppStorage("appearance_mode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("root.selected_tab") private var selectedTabRaw: Int = 0

    /// P1:启动状态机 — 严格按顺序:法律协议 → 功能引导 → 主界面
    /// 任一阶段不接受,后续阶段不展示。
    @State private var launchStage: LaunchStage = {
        if !LegalConsent.hasAcceptedCurrentVersion {
            return .legalConsent
        }
        if !UserDefaults.standard.bool(forKey: "has_seen_onboarding") {
            return .onboarding
        }
        return .mainContent
    }()

    // 显式构建 ModelContainer，便于打 log 排查 schema/store 问题。
    // 这里用 file-scope 的 static lazy，让 init 和 body 都拿到**同一份**实例 ——
    // 否则 init 里 makeContainer 构造的 mainContext 跟 body 里 .modelContainer 注入的不是一个
    private static let modelContainer: ModelContainer = {
        let schema = Schema([
            Product.self,
            GenerationRecord.self,
            Feedback.self,
            NoteComment.self,
            ChatSession.self,
            InspirationItem.self
        ])
        let config = ModelConfiguration("RedPulse", schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            print("[App] ModelContainer created ok. schema entities=\(schema.entities.map(\.name))")
            return container
        } catch {
            print("[App] ModelContainer FAILED: \(error). Falling back to in-memory store.")
            let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [inMemoryConfig])
        }
    }()

    init() {
        // 用同一份 static modelContainer 构造 regenSession，mainContext 跨 view 持久
        _regenSession = State(initialValue: RegenSession(mainContext: Self.modelContainer.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(selectedTabRaw: $selectedTabRaw)
                    .environment(\.launchStage, launchStage)
                    .environment(generationSession)
                    .environment(regenSession)
                    .tint(.brand)
                    .preferredColorScheme(appearanceMode.colorScheme)
                    .trackScreenMetrics()
                    .frame(minWidth: 900, maxWidth: 1400, minHeight: 600, maxHeight: 900)
                    .task {
                        // 启动时一次性迁移：把 SwiftData 里历史远程 URL 下到本地
                        await LocalAssetMigrator.runIfNeeded(modelContext: Self.modelContainer.mainContext)
                    }
                    // 只有到了 mainContent 阶段,主界面才可交互
                    .allowsHitTesting(launchStage == .mainContent)
                    .opacity(launchStage == .mainContent ? 1 : 0)

                // P1:阶段 1 — 法律协议(首次启动强制)
                if launchStage == .legalConsent {
                    LegalConsentView {
                        // 同意后进入下一阶段:功能引导
                        withAnimation(.easeInOut(duration: 0.25)) {
                            launchStage = .onboarding
                        }
                    }
                    .transition(.opacity)
                }

                // P1:阶段 2 — 功能引导(同意协议后、首次启动时弹一次)
                if launchStage == .onboarding {
                    OnboardingView {
                        // 引导完成后进入主界面
                        withAnimation(.easeInOut(duration: 0.25)) {
                            launchStage = .mainContent
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .modelContainer(Self.modelContainer)
        .commands {
            AppCommands(
                selectedTab: Binding(
                    get: { TabItem(rawValue: selectedTabRaw) ?? .generate },
                    set: { selectedTabRaw = $0.rawValue }
                ),
                showAIWindow: {
                    NotificationCenter.default.post(name: .openAIAssistant, object: nil)
                }
            )
        }

        #if os(macOS)
        Window("AI 笔记助手", id: "global-assistant") {
            GlobalAssistantRoot()
                .tint(.brand)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .defaultSize(width: 1100, height: 720)
        .modelContainer(Self.modelContainer)
        #endif
    }
}

// MARK: - LaunchStage environment
//
// 把启动阶段(法律协议 / 引导 / 主界面)暴露给子 view,让它们知道当前是不是已经到主界面。
// 主要给 GenerateView 的"首次启动引导"用 ——
// 之前用 onAppear 触发,结果 ContentView 一直在 view tree 里(opacity=0 但 mount 着),
// 协议还没同意就 onAppear → 1 秒后弹引导,顺序错。

enum LaunchStage: Equatable {
    case legalConsent   // 必须先同意法律协议
    case onboarding     // 协议同意后才进入引导(首次启动时弹一次)
    case mainContent    // 主界面
}

private struct LaunchStageKey: EnvironmentKey {
    static let defaultValue: LaunchStage = .mainContent
}

extension EnvironmentValues {
    var launchStage: LaunchStage {
        get { self[LaunchStageKey.self] }
        set { self[LaunchStageKey.self] = newValue }
    }
}
