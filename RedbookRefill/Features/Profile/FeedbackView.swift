//
//  FeedbackView.swift
//  RedPulse
//
//  意见反馈子页面（见需求 §模块8 M4）。
//  - TextEditor 200 字限制 + 实时字数
//  - 图片上限 3 张（占位符模式，原型一致）
//  - 提交 → repository.saveFeedback → toast「感谢反馈 ✨」→ pop
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct FeedbackView: View {
    // MARK: - Environment

    @Environment(Repository.self) private var repository
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var text: String = ""
    @State private var imagePaths: [String] = []

    @State private var showToast: Bool = false
    @State private var toastText: String = ""

    // MARK: - Constants

    private let maxTextLength = 200
    private let maxImages = 3

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    textCard
                    imagesCard
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }

            // 浮动操作栏
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    submitButton
                        .frame(maxWidth: 760)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Adaptive.horizontalPageMargin)
                .padding(.vertical, Spacing.md)
                #if os(iOS)
                .padding(.bottom, 4)
                #endif
                .background(Color.surface)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("意见反馈")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .overlay(alignment: .bottom) {
            if showToast { toastView }
        }
    }

    // MARK: - Text input

    private var textCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("请详细描述你的问题或建议")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink2)
                Spacer()
                Text("\(text.count) / \(maxTextLength)")
                    .font(.system(size: 12))
                    .foregroundStyle(text.count >= maxTextLength ? Color.brand : Color.ink3)
            }

            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(Spacing.sm)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(Color.ink3.opacity(0.15), lineWidth: 1)
                )
                .onChange(of: text) { _, newValue in
                    if newValue.count > maxTextLength {
                        text = String(newValue.prefix(maxTextLength))
                    }
                }
        }
        .padding(Spacing.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Images

    private var imagesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("上传截图（选填，最多 3 张）")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink2)

            HStack(spacing: Spacing.md) {
                ForEach(Array(imagePaths.enumerated()), id: \.offset) { idx, _ in
                    imageThumb(index: idx)
                }
                if imagePaths.count < maxImages {
                    addImageButton
                }
                Spacer()
            }
        }
        .padding(Spacing.lg)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func imageThumb(index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.bg)
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.ink3)
                )

            Button {
                imagePaths.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink.opacity(0.7))
                    .background(Circle().fill(Color.white))
            }
            .offset(x: 6, y: -6)
        }
    }

    private var addImageButton: some View {
        Button {
            // 原型一致：占位文件名，不真接相册
            let name = "截图\(imagePaths.count + 1).jpg"
            imagePaths.append(name)
        } label: {
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(Color.ink3.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.ink3)
                )
        }
    }

    // MARK: - Submit

    private var submitButton: some View {
        Button(action: handleSubmit) {
            Text("提交反馈")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Color.brand : Color.ink3)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Toast

    private var toastView: some View {
        VStack {
            Spacer()
            Text(toastText)
                .font(.system(size: 14))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .padding(.bottom, 100)
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    /// 收件邮箱（产品负责人）。如需修改请直接改这里。
    private static let feedbackRecipient = "1445007455@qq.com"

    private func handleSubmit() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 本地落库（保留之前的本地反馈记录，方便用户在历史里也能看到自己反馈过什么）
        let feedback = Feedback(
            id: UUID(),
            content: body,
            imagePaths: imagePaths,
            createdAt: Date(),
            isSubmitted: false
        )
        repository.saveFeedback(feedback)

        // 触发 mailto: URL 让系统邮件 App 打开预填收件人 + 主题 + 正文。
        // App 不直接走 SMTP（需要 Key 服务），由邮件 App 完成最后一步发送。
        if openMailComposer(to: Self.feedbackRecipient, body: body) {
            toastText = "已为你打开邮件，请点击发送 ✉️"
        } else {
            toastText = "未找到邮件 App，已收到反馈 ✨"
        }
        withAnimation { showToast = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }

    /// 用 mailto: scheme 调用系统邮件 composer。
    /// 成功打开返回 true；找不到能处理 mailto: 的 App 返回 false。
    private func openMailComposer(to: String, body: String) -> Bool {
        let subject = "用户反馈"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        guard let url = URL(string: "mailto:\(to)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return false
        }
        // 纯 macOS 走 NSWorkspace；Mac Catalyst / iOS / iPadOS 全部走 UIApplication
        // （Mac Catalyst 上 NSWorkspace 被标 unavailable）。
        #if os(macOS)
        return NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
        #else
        return false
        #endif
    }
}
