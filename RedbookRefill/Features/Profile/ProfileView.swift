//
//  ProfileView.swift
//  灵芯
//
//  「我的」个人中心 — 数据看板 + 快捷操作 + 设置入口。
//  No auth required — app is always available.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query(sort: \Product.createdAt, order: .reverse) private var products: [Product]
    @Query(sort: \GenerationRecord.createdAt, order: .reverse) private var records: [GenerationRecord]

    @Binding var selectedTab: TabItem
    @State private var showInspirationBoard = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xl)

                statsCards
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.bottom, Spacing.xl)

                quickActions
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.bottom, Spacing.lg)

                settingsList
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.bottom, Spacing.xl)
            }
            .contentWidthCap()
            .padding(.bottom, 100)
        }
        .background(Color.bg)
        .sheet(isPresented: $showInspirationBoard) {
            NavigationStack {
                InspirationBoardView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showInspirationBoard = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.brand.opacity(0.7), Color.brand],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("用户")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.ink)

            statusChip
        }
    }

    private var statusChip: some View {
        Text("普通用户")
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 4)
            .background(Color.ink3.opacity(0.12))
            .foregroundStyle(Color.ink2)
            .clipShape(Capsule())
    }

    // MARK: - Stats cards

    private var statsCards: some View {
        HStack(spacing: Spacing.sm) {
            StatCard(
                count: records.count,
                label: "生成次数",
                icon: "wand.and.stars",
                color: Color.brand
            ) {
                selectedTab = .history
            }

            StatCard(
                count: products.count,
                label: "产品数",
                icon: "square.grid.2x2",
                color: Color.brand
            ) {
                selectedTab = .products
            }

            StatCard(
                count: records.count,
                label: "历史记录",
                icon: "clock.arrow.circlepath",
                color: Color.brand.opacity(0.85)
            ) {
                selectedTab = .history
            }
        }
    }

    // MARK: - Quick actions (2x2 grid)

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("快捷操作")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink3)
                .padding(.leading, 4)

            // 严格 2x2 网格（上二下二），跨平台视觉一致
            // 之前 P1-8 改成自适应 .adaptive(minimum: 200)，
            // 在 Mac 宽屏上自动撑成 3+1，用户觉得"还是上二下二"不对
            // —— 这里用户明确要求固定 2x2
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                QuickActionButton(
                    icon: "wand.and.stars",
                    label: "新建生成",
                    color: Color.brand
                ) {
                    selectedTab = .generate
                }

                QuickActionButton(
                    icon: "tray.full",
                    label: "管理产品",
                    color: Color.brand
                ) {
                    selectedTab = .products
                }

                QuickActionButton(
                    icon: "clock.arrow.circlepath",
                    label: "查看历史",
                    color: Color.brand.opacity(0.85)
                ) {
                    selectedTab = .history
                }

                QuickActionButton(
                    icon: "lightbulb",
                    label: "灵感板",
                    color: Color.suggestionBlue
                ) {
                    showInspirationBoard = true
                }
            }
        }
    }

    // MARK: - Settings list

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("设置与帮助")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink3)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                SettingsRow(icon: "gearshape", label: "设置") {
                    SettingsView()
                }

                Divider()
                    .padding(.leading, 52)

                SettingsRow(icon: "questionmark.circle", label: "帮助") {
                    HelpView()
                }

                Divider()
                    .padding(.leading, 52)

                SettingsRow(icon: "bubble.left", label: "反馈") {
                    FeedbackView()
                }

                Divider()
                    .padding(.leading, 52)

                // 重新引导按钮（重置 currentStep 让所有 popover 重新触发）
                Button {
                    UserDefaults.standard.set(-1, forKey: "generate_onboarding_step")
                    selectedTab = .generate
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 28)
                        Text("重新引导")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink3)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 16)
                    .frame(minHeight: 52)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 52)

                SettingsRow(icon: "doc.text", label: "隐私协议") {
                    LegalView(type: .privacy)
                }

                Divider()
                    .padding(.leading, 52)

                SettingsRow(icon: "scroll", label: "服务条款") {
                    LegalView(type: .terms)
                }
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }
}

// MARK: - Stat card

private struct StatCard: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {

            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.12), in: Circle())

                Text("\(count)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick action button

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {

            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 16)
            .frame(minHeight: 52)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings row (navigation)

private struct SettingsRow<Destination: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 28)

                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ink)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 16)
            .frame(minHeight: 52)
            // 强制覆盖 macOS NavigationLink 的默认 hover/selected tint
            // — 不加这一行整行会被 brand 红色的淡化版铺满
            .background(Color.surface)
        }
        // macOS 上 NavigationLink 默认会带 tint hover，强制 plain 关掉
        .buttonStyle(.plain)
    }
}
