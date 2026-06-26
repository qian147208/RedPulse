//
//  RootTabView.swift
//  灵芯
//
//  Adaptive root navigation with Liquid Glass accents.
//  iPhone: native TabView for full safe-area & iPhone 13+ adaptation
//  iPad/Mac: NavigationSplitView + sidebar
//  No login/guest — app is always available.
//

import SwiftUI
import SwiftData

// MARK: - TabItem (unchanged)

enum TabItem: Int, CaseIterable, Identifiable {
    var id: Int { rawValue }
    case generate
    case products
    case history
    case profile

    var title: String {
        switch self {
        case .generate: "生成"
        case .products: "产品库"
        case .history: "历史"
        case .profile: "我的"
        }
    }

    var icon: String {
        switch self {
        case .generate: "wand.and.stars"
        case .products: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        case .profile: "person.circle"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .generate: "1"
        case .products: "2"
        case .history: "3"
        case .profile: "4"
        }
    }
}

// MARK: - RootTabView

struct RootTabView: View {
    @Binding var selectedTabRaw: Int
    private var selectedTab: TabItem {
        get { TabItem(rawValue: selectedTabRaw) ?? .generate }
        nonmutating set { selectedTabRaw = newValue.rawValue }
    }
    @State private var sidebarSelection: TabItem? = .generate
    /// iPad / Mac sidebar 显隐。默认收起（`.detailOnly`）→ 内容区占满整个窗口，
    /// toolbar 侧边栏按钮可手动展开，NavigationSplitView 自动处理动画与转场。
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    /// 用户上次主动设置的可见性（用于 onAppear 强制覆盖 NavigationSplitView 自动恢复）
    @AppStorage("split_column_visibility") private var savedVisibilityRaw: String = "detailOnly"
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        rootLayout
        // TipKit 接管引导 — 各 view 自己挂 .popoverTip(...)，无需在 RootTabView 层挂 overlay
    }

    /// Top-right padding for the quality toggle — clears window traffic lights on macOS
    private var topBarInset: CGFloat {
        #if os(macOS)
        return 52
        #else
        return 12
        #endif
    }
    private var trailingBarInset: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 16
        #endif
    }

    /// iPhone 紧凑布局底部有自定义 TabBar（≈48pt + padding），FAB 要让开。
    private var chatLauncherBottomPadding: CGFloat {
        #if os(iOS)
        if sizeClass == .regular {
            return 24
        } else {
            return 86
        }
        #else
        return 24
        #endif
    }

    @ViewBuilder
    private var rootLayout: some View {
        #if os(iOS)
        if sizeClass == .regular {
            sidebarLayout
        } else {
            tabLayout
        }
        #else
        // macOS: always use sidebar layout.
        sidebarLayout
        #endif
    }

    // MARK: - Sidebar Layout (iPad / Mac)

    private var sidebarLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $sidebarSelection) {
                ForEach(TabItem.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .font(.system(size: 15))
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            switch sidebarSelection ?? .generate {
            case .generate:
                NavigationStack {
                    GenerateView()
                        // 显式占位 principal，覆盖系统默认渲染
                        // —— SwiftUI 在 macOS 上会把 sidebar toggle 渲染到
                        // navigationTitle 位置。如果 navigationTitle 是空字符串，
                        // 它会渲染一个空 principal + 隐藏的 sidebar toggle。
                        // 用一个 EmptyView 显式占位告诉 SwiftUI："这块我自己管"。
                        .toolbar {
                            ToolbarItem(placement: .principal) { EmptyView() }
                        }
                }
            case .products:
                NavigationStack {
                    ProductListView()
                        .toolbar {
                            ToolbarItem(placement: .principal) { EmptyView() }
                        }
                }
            case .history:
                NavigationStack {
                    HistoryView()
                        .toolbar {
                            ToolbarItem(placement: .principal) { EmptyView() }
                        }
                }
            case .profile:
                NavigationStack {
                    ProfileView(selectedTab: Binding(
                        get: { sidebarSelection ?? .generate },
                        set: { sidebarSelection = $0 }
                    ))
                        .navigationTitle("我的")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .principal) { EmptyView() }
                        }
                }
            }
        }
        .tint(Color.brand)
        .onChange(of: sidebarSelection) { _, newSelection in
            if let newSelection {
                selectedTabRaw = newSelection.rawValue
            }
        }
        // P0-3: iPad 转屏 / Stage Manager / 多任务窗口尺寸变化时，size class 会从 .compact 切到 .regular，
        // 这时 sidebarLayout 重新挂载，但 .task 只在首次 onAppear 触发一次，sidebarSelection 不会自动
        // 跟 AppStorage 同步 → 用户感觉"tab 跳了"。补一条 selectedTabRaw → sidebarSelection 的反向同步。
        .onChange(of: selectedTabRaw) { _, newRaw in
            if let tab = TabItem(rawValue: newRaw), sidebarSelection != tab {
                sidebarSelection = tab
            }
        }
        .onChange(of: columnVisibility) { _, new in
            savedVisibilityRaw = (new == .detailOnly) ? "detailOnly" : "all"
        }
        .task {
            // 初始化时同步 AppStorage → sidebarSelection
            if let tab = TabItem(rawValue: selectedTabRaw) {
                sidebarSelection = tab
            }
            // 强制应用用户偏好（首次启动也走 .detailOnly）
            columnVisibility = (savedVisibilityRaw == "all") ? .all : .detailOnly
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // P0-7 (修正版)：用 SwiftUI 在 macOS 上自动渲染的 sidebar toggle 按钮
        // (会出现在 toolbar 中间、navigationTitle 左侧的"红框"位置)。
        // 之前我手动加了一个 .primaryAction 按钮，加上系统自动的 → 同时显示 2 个。
        // 现在只保留系统自动的（你红框框住的那个），删掉手动加的。
        // AppStorage 持久化保留（onChange(of: columnVisibility) + .task 同步）。
        // 系统自动按钮的操作直接改 columnVisibility binding，触发持久化 onChange。
    }



    // MARK: - iPhone tab layout (safeAreaInset)

    private var tabLayout: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                // Only render the active tab — prevents all 4 tabs from being
                // instantiated simultaneously, which blocks the main thread on startup.
                switch selectedTab {
                case .generate:
                    NavigationStack {
                        GenerateView()
                    }
                case .products:
                    NavigationStack {
                        ProductListView()
                    }
                case .history:
                    NavigationStack {
                        HistoryView()
                    }
                case .profile:
                    NavigationStack {
                        ProfileView(selectedTab: Binding(
                            get: { TabItem(rawValue: selectedTabRaw) ?? .generate },
                            set: { selectedTabRaw = $0.rawValue }
                        ))
                            .navigationTitle("我的")
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                    }
                }
            }

            // Tab bar with glass styling — 背景延伸到 Home Indicator
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.border)
                    .frame(height: BorderWidth.hairline)
                HStack(spacing: 0) {
                    ForEach(TabItem.allCases) { tab in
                        Button {
                            HapticManager.lightImpact()
                            selectedTab = tab
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: Adaptive.tabIconSize))
                                Text(tab.title)
                                    .font(.system(size: Adaptive.tabLabelSize, weight: .medium))
                            }
                            .foregroundStyle(tab == selectedTab ? Color.brand : Color.ink3)
                            .frame(maxWidth: .infinity)
                            .frame(height: Adaptive.tabItemHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(KeyboardShortcut(tab.shortcutKey, modifiers: .command))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 2)
            }
            .background(.regularMaterial)
        }
        .ignoresSafeArea(.keyboard)
        .tint(Color.brand)
    }

    // MARK: - Sidebar footer

    private var sidebarFooter: some View {
        EmptyView()
    }
}



#Preview {
    @Previewable @State var tab: Int = 0
    return RootTabView(selectedTabRaw: $tab)
}
