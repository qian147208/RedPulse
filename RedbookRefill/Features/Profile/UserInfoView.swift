//
//  UserInfoView.swift
//  灵芯
//
//  个人信息页（简化版，无登录/访客概念）。
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
                    draftEmail = UserDefaults.standard.string(forKey: "user.email") ?? ""
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
            draftEmail = UserDefaults.standard.string(forKey: "user.email") ?? ""
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

            Text("用户")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ink)

            Text("普通用户")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)
                .background(Color.ink3.opacity(0.12))
                .foregroundStyle(Color.ink2)
                .clipShape(Capsule())
        }
    }

    // MARK: - Info cards

    private var infoCards: some View {
        VStack(spacing: Spacing.md) {
            emailRow
        }
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
            if !draftEmail.isEmpty && draftEmail != UserDefaults.standard.string(forKey: "user.email") {
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
        guard trimmed != UserDefaults.standard.string(forKey: "user.email") else { return }
        UserDefaults.standard.set(trimmed, forKey: "user.email")
    }

    // MARK: - Action list

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
}
