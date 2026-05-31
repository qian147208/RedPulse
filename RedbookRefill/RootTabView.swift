//
//  RootTabView.swift
//  RedPulse
//
//  Adaptive root navigation with Liquid Glass accents.
//  iPhone: native TabView for full safe-area & iPhone 13+ adaptation
//  iPad/Mac: NavigationSplitView + sidebar
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
    @State private var showOnboardingSheet: Bool = false
    @AppStorage("has_seen_onboarding") private var hasSeenOnboarding: Bool = false
    @Environment(AuthStore.self) private var authStore
    @Environment(CoachMarkManager.self) private var coachMarkManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        rootLayout
            .overlay {
                ChatLauncher()
                    .padding(.bottom, chatLauncherBottomPadding)
            }
            .overlay {
                CoachMarkOverlay()
            }
            .onChange(of: authStore.isLoggedIn) { _, newValue in
                if newValue && !hasSeenOnboarding { showOnboardingSheet = true }
            }
            .onChange(of: authStore.isGuest) { _, newValue in
                if newValue && !hasSeenOnboarding { showOnboardingSheet = true }
            }
            .onAppear {
                if (authStore.isLoggedIn || authStore.isGuest) && !hasSeenOnboarding {
                    showOnboardingSheet = true
                } else if !coachMarkManager.hasShownGenerate {
                    coachMarkManager.hasShownGenerate = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        coachMarkManager.start(steps: CoachMarkStep.generateSteps)
                    }
                }
            }
            .onChange(of: showOnboardingSheet) { _, showing in
                if !showing && !coachMarkManager.hasShownGenerate {
                    coachMarkManager.hasShownGenerate = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        coachMarkManager.start(steps: CoachMarkStep.generateSteps)
                    }
                }
            }
            .sheet(isPresented: $showOnboardingSheet) {
                OnboardingView()
            }
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
        sidebarLayout
        #endif
    }

    // MARK: - Sidebar Layout (iPad / Mac)

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(selection: Binding<TabItem?>(
                get: { selectedTab },
                set: { newValue in
                    if let v = newValue { selectedTab = v }
                }
            )) {
                Section {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.brand)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(TabItem.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .font(.system(size: 15))
                            .padding(.vertical, 4)
                            .tag(tab)
                            .keyboardShortcut(KeyboardShortcut(tab.shortcutKey, modifiers: .command))
                    }
                } header: {
                    Text("功能")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sidebarFooter
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .generate:
                        GenerateView()
                    case .products:
                        ProductListView()
                    case .history:
                        HistoryView()
                    case .profile:
                        ProfileView(selectedTab: Binding(
                            get: { TabItem(rawValue: selectedTabRaw) ?? .generate },
                            set: { selectedTabRaw = $0.rawValue }
                        ))
                    }
                }
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        QualityToggle()
                    }
                    #endif
                }
            }
        }
        .tint(Color.brand)
    }



    // MARK: - iPhone tab layout (safeAreaInset)

    private var tabLayout: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                NavigationStack {
                    GenerateView()
                }
                .opacity(selectedTab == .generate ? 1 : 0)
                .allowsHitTesting(selectedTab == .generate)
                .zIndex(selectedTab == .generate ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                NavigationStack {
                    ProductListView()
                }
                .opacity(selectedTab == .products ? 1 : 0)
                .allowsHitTesting(selectedTab == .products)
                .zIndex(selectedTab == .products ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                NavigationStack {
                    HistoryView()
                }
                .opacity(selectedTab == .history ? 1 : 0)
                .allowsHitTesting(selectedTab == .history)
                .zIndex(selectedTab == .history ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                .opacity(selectedTab == .profile ? 1 : 0)
                .allowsHitTesting(selectedTab == .profile)
                .zIndex(selectedTab == .profile ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
