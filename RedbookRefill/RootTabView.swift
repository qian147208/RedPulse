//
//  RootTabView.swift
//  RedPulse
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
    @State private var showOnboardingSheet: Bool = false
    @State private var coachMarkScheduled = false
    @AppStorage("has_seen_onboarding") private var hasSeenOnboarding: Bool = false
    @Environment(CoachMarkManager.self) private var coachMarkManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        rootLayout
            // .overlay {
                // ChatLauncher()
                    // .padding(.bottom, chatLauncherBottomPadding)
            // }
            // .overlay {
                // CoachMarkOverlay()
            // }
            .onAppear {
                if !hasSeenOnboarding {
                    showOnboardingSheet = true
                }
            }
            .onChange(of: showOnboardingSheet) { _, showing in
                if !showing {
                    scheduleCoachMark()
                }
            }
            .onAppear {
                if hasSeenOnboarding {
                    scheduleCoachMark()
                }
            }
            .sheet(isPresented: $showOnboardingSheet) {
                OnboardingView()
            }
    }

    private func scheduleCoachMark() {
        guard !coachMarkManager.hasShownGenerate else { return }
        coachMarkScheduled = true
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
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                ForEach(TabItem.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .font(.system(size: 15))
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            switch sidebarSelection ?? .generate {
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
                        get: { sidebarSelection ?? .generate },
                        set: { sidebarSelection = $0 }
                    ))
                        .navigationTitle("我的")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
            }
        }
        .tint(Color.brand)
        .onChange(of: sidebarSelection) { _, newSelection in
            if let newSelection {
                selectedTabRaw = newSelection.rawValue
            }
        }
        .task {
            // 初始化时同步 AppStorage → sidebarSelection
            if let tab = TabItem(rawValue: selectedTabRaw) {
                sidebarSelection = tab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
