//
//  LegalConsentView.swift
//  RedPulse
//
//  P1:首次启动硬性同意页 —— 必须在用户勾选「我已阅读并同意《隐私协议》和《服务条款》」
//  后才能进入主界面。
//
//  设计:
//  - 用 .fullScreenCover 模态盖住主界面,不可绕过(没有"X"按钮,没有 swipe-to-dismiss)
//  - 把协议核心条款(摘要)放在屏幕上让用户读
//  - 「查看完整协议」按钮进 LegalView 读全文
//  - 必须勾选 checkbox 才能点「同意并继续」
//  - AppStorage("legal_consent_v1_2_accepted") 持久化同意状态
//  - 隐私协议 / 服务条款 任一更新,版本号升一档,重新弹窗让用户重新同意
//

import SwiftUI

/// 协议版本号 — 任一文档改动,版本号 +1,触发所有用户重新同意
private let kLegalVersion = "1.2"
private let kLegalAcceptedKey = "legal_consent_v\(kLegalVersion.replacingOccurrences(of: ".", with: "_"))_accepted"

struct LegalConsentView: View {
    /// 用户点同意后回调,让 RedPulseApp 关闭 fullScreenCover
    var onAccept: () -> Void

    @State private var accepted: Bool = false
    @State private var showingFullLegal: LegalType? = nil

    var body: some View {
        ZStack {
            // 背景渐变 —— 给用户"这是严肃界面"的视觉提示
            LinearGradient(
                colors: [Color.brand.opacity(0.08), Color.bg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                // 顶部图标 + 标题
                header

                Spacer(minLength: 16)

                // 协议摘要(可滚动阅读)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection
                        Divider()
                        bulletSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.surface)
                        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                )
                .padding(.horizontal, 20)

                Spacer(minLength: 12)

                // 勾选 + 操作按钮
                checkboxAndButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        // macOS 不支持 fullScreenCover,但 sheet + .interactiveDismissDisabled 也能阻止绕过
        #if os(iOS)
        .interactiveDismissDisabled(true)
        #endif
        .sheet(item: $showingFullLegal) { type in
            NavigationStack {
                LegalView(type: type)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showingFullLegal = nil }
                        }
                    }
            }
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .symbolRenderingMode(.hierarchical)
            }

            Text("欢迎使用 RedPulse")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.ink)

            Text("继续使用前,请阅读并同意以下条款")
                .font(.system(size: 14))
                .foregroundStyle(Color.ink3)
        }
    }

    // MARK: - 摘要

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("协议核心要点")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)

            Text("""
                RedPulse 是一款本地优先的 AI 内容创作工具。本应用不运营服务器、不收集您的个人信息,所有创作数据存储在您的设备本地,卸载即永久删除。
                """)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink2)
                .lineSpacing(4)

            Text("""
                AI 生成能力由第三方服务(Agnes / DeepSeek / 火山引擎方舟)提供。您输入的关键词、产品信息、参考图会发送给对应服务商,由其处理并返回结果。
                """)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink2)
                .lineSpacing(4)

            Text("""
                本应用内置了一个 Agnes 默认 API Key,用于零配置体验,费用由开发者承担。您可在「设置 → API 配置」填写自己的 Key 替换。
                """)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink2)
                .lineSpacing(4)

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brand)
                Text("您对使用本应用生成、编辑、发布的所有内容承担全部责任。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.brand)
            }
        }
    }

    private var bulletSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("点击下方按钮查看完整协议")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ink3)

            HStack(spacing: 10) {
                Button {
                    showingFullLegal = .privacy
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("查看《隐私协议》")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    showingFullLegal = .terms
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scroll")
                        Text("查看《服务条款》")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Checkbox + Buttons

    private var checkboxAndButtons: some View {
        VStack(spacing: 14) {
            Button {
                accepted.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: accepted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accepted ? Color.brand : Color.ink3)
                    Text("我已阅读并同意《隐私协议》和《服务条款》")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Button {
                UserDefaults.standard.set(true, forKey: kLegalAcceptedKey)
                UserDefaults.standard.set(Date(), forKey: "legal_consent_accepted_at")
                onAccept()
            } label: {
                Text("同意并继续")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accepted ? Color.brand : Color.ink4)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!accepted)

            Button {
                // 用户拒绝时,直接退出 App
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #else
                exit(0)
                #endif
            } label: {
                Text("不同意,退出 App")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - LegalType 适配 sheet(item:)

extension LegalType: Identifiable {
    public var id: String { rawValue }
}

// MARK: - 全局访问

/// 检查用户是否已同意当前版本协议(RedPulseApp 调用)
enum LegalConsent {
    static var hasAcceptedCurrentVersion: Bool {
        UserDefaults.standard.bool(forKey: kLegalAcceptedKey)
    }

    /// 用于"清除所有数据"场景下重置同意状态
    static func resetConsent() {
        UserDefaults.standard.removeObject(forKey: kLegalAcceptedKey)
    }

    static var currentVersion: String { kLegalVersion }
}