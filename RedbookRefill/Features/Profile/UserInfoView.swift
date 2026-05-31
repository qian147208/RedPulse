//
//  UserInfoView.swift
//  RedPulse
//
//  从侧栏左下角头像入口打开的"个人信息"页。
//  - 头像 / 昵称 / 状态胶囊
//  - 手机号（来自 AuthStore，只读，访客时显示"未登录"）
//  - 邮箱（用户可编辑，落 UserDefaults）
//  - 帮助中心 / 意见反馈 / 退出登录
//
//  顶部"完成"按钮关闭 sheet，保证返回闭环。
//

import SwiftUI
import PhotosUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

struct UserInfoView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var emailFocused: Bool
    @State private var draftEmail: String = ""
    @State private var avatarImage: PlatformImage? = nil
    @State private var showPhotoPicker = false
    @AppStorage("user_avatar_data") private var avatarData: Data = Data()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.xl)

                infoCards
                    .padding(.horizontal, Adaptive.horizontalPageMargin)

                actionList
                    .padding(.horizontal, Adaptive.horizontalPageMargin)
                    .padding(.top, Spacing.lg)

                if authStore.isLoggedIn {
                    logoutButton
                        .padding(.horizontal, Adaptive.horizontalPageMargin)
                        .padding(.top, Spacing.xl)
                        .padding(.bottom, Spacing.xl)
                }
            }
            .contentWidthCap()
        }
        .background(Color.bg)
        .navigationTitle("个人信息")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    draftEmail = authStore.email
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    commitEmailIfNeeded()
                    dismiss()
                }
            }
        }
        .onAppear {
            draftEmail = authStore.email
            if !avatarData.isEmpty {
                #if canImport(UIKit)
                avatarImage = UIImage(data: avatarData)
                #elseif canImport(AppKit)
                avatarImage = NSImage(data: avatarData)
                #endif
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.lg) {
            // Avatar with upload
            Button {
                showPhotoPicker = true
            } label: {
                ZStack {
                    if let img = avatarImage {
                        #if canImport(UIKit)
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        #elseif canImport(AppKit)
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        #endif
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 100))
                            .foregroundStyle(Color.ink3)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        )
                        .opacity(0)
                }
            }
            .buttonStyle(.plain)
            .photosPicker(isPresented: $showPhotoPicker, selection: Binding(
                get: { nil },
                set: { item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                        avatarData = data
                        #if canImport(UIKit)
                        avatarImage = UIImage(data: data)
                        #elseif canImport(AppKit)
                        avatarImage = NSImage(data: data)
                        #endif
                    }
                }
            ), matching: .images)

            Text(authStore.isGuest ? "访客" : "用户")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ink)

            statusChip
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if authStore.isGuest {
            chipLabel(
                text: "访客 · 剩余 \(authStore.guestRemaining)/\(AuthStore.guestDailyLimit)",
                bg: Color.brandSoft,
                fg: Color.brand
            )
        } else if authStore.isLoggedIn {
            chipLabel(text: "普通用户", bg: Color.ink3.opacity(0.12), fg: Color.ink2)
        } else {
            chipLabel(text: "未登录", bg: Color.ink3.opacity(0.12), fg: Color.ink2)
        }
    }

    private func chipLabel(text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(Capsule())
    }

    // MARK: - Info cards (phone + email)

    private var infoCards: some View {
        VStack(spacing: Spacing.md) {
            infoRow(
                icon: "phone.fill",
                label: "手机号",
                value: authStore.phone.isEmpty ? "未登录" : Self.maskPhone(authStore.phone),
                placeholder: "登录后显示"
            )

            emailRow
        }
    }

    private func infoRow(icon: String, label: String, value: String, placeholder: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink3)
                Text(value.isEmpty ? placeholder : value)
                    .font(.system(size: 15))
                    .foregroundStyle(value.isEmpty ? Color.ink4 : Color.ink)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var emailRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("邮箱")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ink3)
                TextField("点击填写邮箱", text: $draftEmail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ink)
                    .focused($emailFocused)
                    .onSubmit { commitEmailIfNeeded() }
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
            }
            Spacer()
            if !draftEmail.isEmpty && draftEmail != authStore.email {
                Button {
                    commitEmailIfNeeded()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func commitEmailIfNeeded() {
        let trimmed = draftEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != authStore.email else { return }
        authStore.email = trimmed
    }

    // MARK: - Action list (help / feedback)

    private var actionList: some View {
        VStack(spacing: Spacing.sm) {
            NavigationLink {
                HelpView()
            } label: {
                actionRow(icon: "questionmark.circle", label: "帮助中心")
            }
            NavigationLink {
                FeedbackView()
            } label: {
                actionRow(icon: "bubble.left", label: "意见反馈")
            }
        }
    }

    private func actionRow(icon: String, label: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.brand)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Color.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            authStore.logout()
            dismiss()
        } label: {
            Text("退出登录")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// 手机号脱敏：保留首 3 末 4 位，中间 ****。短号直接返回。
    private static func maskPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 7 else { return phone }
        let head = digits.prefix(3)
        let tail = digits.suffix(4)
        return "\(head) **** \(tail)"
    }
}
