//
//  SettingsView.swift
//  RedPulse
//
//  设置子页面。
//  - 外观模式、图片缓存、大模型配置、数据清除、版本更新
//  No auth — app is always available.
//

import SwiftUI

struct SettingsView: View {
    // MARK: - Environment

    @Environment(Repository.self) private var repository
    // 不再需要 dismiss — SettingsView 通过 NavigationLink push 进入
    // 返回由系统自动按钮处理

    // MARK: - State

    @AppStorage("debug_mode") private var debugMode = false
    @AppStorage("appearance_mode") private var appearanceMode: AppearanceMode = .system

    @State private var showClearCacheAlert = false
    @State private var showClearDataAlert = false

    @State private var toastText: String = ""
    @State private var showToast: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                appearanceCard
                llmConfigCard   // 紧跟外观设置
                cacheCard
                dataCard
                versionUpdateCard
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
    }

    // MARK: - Cards

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
        // 关键：去 .plain — 否则 Mac 上默认 Button 会给整张卡片铺一层 hover 粉底纹
        .buttonStyle(.plain)
    }

    private var llmConfigCard: some View {
        // 用 NavigationLink push — 整个在主窗口 NavigationStack 内，不弹 sheet
        // 严格在主页面内（"他"指代：主窗口内、不在外面浮动）
        NavigationLink {
            LLMConfigView()
        } label: {
            rowLayout(icon: "cpu", iconColor: Color.brand, label: "大模型配置", labelColor: Color.ink, showChevron: true)
                .cardBackground()
        }
        .buttonStyle(.plain)
    }

    private var dataCard: some View {
        Button {
            showClearDataAlert = true
        } label: {
            rowLayout(icon: "trash", iconColor: .red, label: "清除所有数据", labelColor: .red, showChevron: true)
                .cardBackground()
        }
        // 同 cacheCard：去默认 Button 粉底纹
        .buttonStyle(.plain)
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
        // 跟其他单行卡片对齐：同 horizontal padding / 同 minHeight
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 18)
        .frame(minHeight: 56)
        .cardBackground()
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
        popToast("图片缓存已清除 ✨")
    }

    private func handleClearAllData() {
        for product in repository.allProducts() {
            repository.deleteProduct(product)
        }
        repository.clearAllRecords()
        popToast("所有数据已清除 ✨")
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
