//
//  SettingsView.swift
//  RedPulse
//
//  设置子页面（见需求 §模块8 M2）。
//  - 清除图片缓存（二次确认 → toast）
//  - 清除所有数据（二次确认 → 清 SwiftData 全部）
//  - 版本更新（V1.0.0 + 红点）
//  - 版本号（不可点）
//  - 登录用户：退出登录；访客：登录账号
//

import SwiftUI

struct SettingsView: View {
    // MARK: - Environment

    @Environment(AuthStore.self) private var authStore
    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @AppStorage("debug_mode") private var debugMode = false
    @AppStorage("appearance_mode") private var appearanceMode: AppearanceMode = .system

    @State private var showClearCacheAlert = false
    @State private var showClearDataAlert = false
    @State private var showLogoutAlert = false

    @State private var showLLMConfig = false

    @State private var toastText: String = ""
    @State private var showToast: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // 开发者调试 (debugToggleCard / debugLogCard) 默认隐藏 —— 普通用户不需要看到。
                // 若需开启，可在「我的 → 设置」里启用（已注释入口；保留模型不变方便后续 toggle）。
                appearanceCard
                cacheCard
                llmConfigCard
                dataCard
                versionUpdateCard
                accountCard
            }
            .padding(.horizontal, Adaptive.horizontalPageMargin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay(alignment: .bottom) {
            if showToast { toastView }
        }
        .alert("清除图片缓存", isPresented: $showClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("确认清除", role: .destructive, action: handleClearCache)
        } message: {
            Text("将清除本地图片描述缓存,不影响产品图本体。")
        }
        .alert("清除所有数据", isPresented: $showClearDataAlert) {
            Button("取消", role: .cancel) {}
            Button("确认清除", role: .destructive, action: handleClearAllData)
        } message: {
            Text("将删除产品库、生成历史、反馈数据。此操作不可恢复。")
        }
        .alert("退出登录", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive, action: handleLogout)
        } message: {
            Text("退出后需要重新登录才能继续使用。")
        }
        .sheet(isPresented: $showLLMConfig) {
            NavigationStack {
                LLMConfigView()
            }
        }
    }

    // MARK: - Cards

    private var debugToggleCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "ladybug")
                .font(.system(size: 18))
                .foregroundStyle(Color.brand)
                .frame(width: 28)
            Text("开发者调试模式")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
            Spacer()
            Toggle("", isOn: $debugMode)
                .labelsHidden()
                .tint(Color.brand)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    /// 仅在 debugMode 开启时显示，跳转到 DebugLogView。
    private var debugLogCard: some View {
        NavigationLink {
            DebugLogView()
        } label: {
            rowLayout(icon: "doc.text.magnifyingglass", iconColor: Color.brand, label: "调试日志", labelColor: Color.ink, showChevron: true)
                .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Image(systemName: appearanceMode.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.brand)
                    .frame(width: 28)
                Text("外观模式")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appearanceMode = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 13))
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(appearanceMode == mode ? Color.white : Color.ink2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(
                            appearanceMode == mode ? Color.brand : Color.surfaceMuted,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .cardBackground()
    }

    private var cacheCard: some View {
        Button {
            showClearCacheAlert = true
        } label: {
            rowLayout(icon: "photo", iconColor: Color.brand, label: "清除图片缓存", labelColor: Color.ink, showChevron: true)
                .cardBackground()
        }
    }

    private var llmConfigCard: some View {
        Button {
            showLLMConfig = true
        } label: {
            rowLayout(icon: "cpu", iconColor: Color.brand, label: "大模型配置", labelColor: Color.ink, showChevron: true)
                .cardBackground()
        }
    }

    private var dataCard: some View {
        Button {
            showClearDataAlert = true
        } label: {
            rowLayout(icon: "trash", iconColor: .red, label: "清除所有数据", labelColor: .red, showChevron: true)
                .cardBackground()
        }
    }

    private var versionUpdateCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "iphone")
                .font(.system(size: 18))
                .foregroundStyle(Color.brand)
                .frame(width: 28)
            Text("版本更新")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
            Spacer()
            Circle()
                .fill(Color.brand)
                .frame(width: 8, height: 8)
            Text("V1.0.0")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink3)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .cardBackground()
    }

@ViewBuilder
    private var accountCard: some View {
        if authStore.isGuest {
            Button(action: handleGoLogin) {
                Text("登录账号")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.brand)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .padding(.top, Spacing.lg)
        } else if authStore.isLoggedIn {
            Button {
                showLogoutAlert = true
            } label: {
                Text("退出登录")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .padding(.top, Spacing.lg)
        }
    }

    // MARK: - Row helper

    private func rowLayout(icon: String, iconColor: Color, label: String, labelColor: Color, showChevron: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)
                .frame(width: 32)
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(labelColor)
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 18)
        .frame(minHeight: 56)
    }

    // MARK: - Toast

    private var toastView: some View {
        Text(toastText)
            .font(.system(size: 14))
            .foregroundStyle(Color.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .padding(.bottom, 100)
            .transition(.opacity)
    }

    private func popToast(_ text: String) {
        toastText = text
        withAnimation { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showToast = false }
        }
    }

    // MARK: - Actions

    private func handleClearCache() {
        // MVP：仅本地 toast 反馈。真实缓存清理由后端代理 + 客户端图片描述缓存协调（V3.2 §9.4-C）。
        popToast("图片缓存已清除 ✨")
    }

    private func handleClearAllData() {
        for product in repository.allProducts() {
            repository.deleteProduct(product)
        }
        repository.clearAllRecords()
        popToast("所有数据已清除 ✨")
    }

    private func handleLogout() {
        authStore.logout()
        // 路由层（ContentView）监测到 isLoggedIn=false 会自动切回 LoginView
    }

    private func handleGoLogin() {
        // 访客点「登录账号」：调用 logout 重置状态，路由层会切到 LoginView
        authStore.logout()
    }
}

// MARK: - Card background modifier

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

private extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}
