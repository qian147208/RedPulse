//
//  RedPulseApp.swift
//  RedPulse
//
//  App entry. Owns the SwiftData container.
//  No auth required — app opens directly to the main tab view.
//

import SwiftUI
import SwiftData

// MARK: - App-wide commands (macOS menu bar)

struct AppCommands: Commands {
    @Binding var selectedTab: TabItem
    var showSettings: () -> Void
    var showAIWindow: () -> Void

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("设置…") { showSettings() }
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
            Button("RedPulse 帮助") {
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
    @State private var coachMarkManager = CoachMarkManager()
    @AppStorage("appearance_mode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("root.selected_tab") private var selectedTabRaw: Int = 0
    @State private var showSettings: Bool = false

    // 显式构建 ModelContainer，便于打 log 排查 schema/store 问题。
    private let modelContainer: ModelContainer = {
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

    var body: some Scene {
        WindowGroup {
            ContentView(selectedTabRaw: $selectedTabRaw)
                .environment(coachMarkManager)
                .tint(.brand)
                .preferredColorScheme(appearanceMode.colorScheme)
                .trackScreenMetrics()
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("完成") { showSettings = false }
                                }
                            }
                    }
                    #if os(macOS)
                    .frame(minWidth: 640, minHeight: 520)
                    #endif
                }
        }
        .modelContainer(modelContainer)
        .commands {
            AppCommands(
                selectedTab: Binding(
                    get: { TabItem(rawValue: selectedTabRaw) ?? .generate },
                    set: { selectedTabRaw = $0.rawValue }
                ),
                showSettings: { showSettings = true },
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
        .modelContainer(modelContainer)
        #endif
    }
}
