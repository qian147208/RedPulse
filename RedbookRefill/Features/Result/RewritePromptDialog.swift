//
//  RewritePromptDialog.swift
//  灵芯
//
//  划词 AI 改写对话框。
//  用户在文本编辑器选中一段文字后直接弹出此对话框 →
//  输入指令（如"更口语 / 突出熬夜修护 / 缩短到50字"）→ 回车或点改写按钮 → 触发 LLM 改写。
//

import SwiftUI

struct RewritePromptDialog: View {
    /// 选中的原文，只读展示
    let selectedText: String
    /// 文本类型描述（用于上下文 prompt：标题/正文/配图建议）
    var sourceLabel: String = "正文"
    /// 用户确认后回调：传入指令字符串
    var onConfirm: (String) async -> Void
    /// 用户取消回调
    var onCancel: () -> Void

    @State private var instruction: String = ""
    @State private var isWorking: Bool = false

    /// 常用快捷词条
    private static let quickPrompts: [String] = [
        "更口语", "更短", "更详细", "更感性", "更专业", "增加 emoji"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // 标题栏
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text("AI 改写")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Color.ink)
                Text("· \(sourceLabel)")
                    .font(Typography.caption)
                    .foregroundStyle(Color.ink4)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // 原文（只读 灰底 最多 3 行）
            VStack(alignment: .leading, spacing: 4) {
                Text("原文")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink4)
                    .textCase(.uppercase)
                Text(selectedText)
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm))
            }

            // 指令输入
            VStack(alignment: .leading, spacing: 4) {
                Text("想怎么改？（填几个关键词即可）")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink4)
                    .textCase(.uppercase)
                TextField("如：更口语、更短、突出某个卖点", text: $instruction)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .padding(Spacing.sm)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(Color.border, lineWidth: BorderWidth.hairline)
                    )
                    .onSubmit { triggerRewrite() }
                    .disabled(isWorking)
            }

            // 快捷词条
            VStack(alignment: .leading, spacing: 6) {
                Text("常用")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink4)
                    .textCase(.uppercase)
                FlowLayout(spacing: 6) {
                    ForEach(Self.quickPrompts, id: \.self) { p in
                        Button {
                            // 追加到指令（若已有则空格分隔），不直接发送
                            if instruction.isEmpty {
                                instruction = p
                            } else if !instruction.contains(p) {
                                instruction += "、\(p)"
                            }
                        } label: {
                            Text(p)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.ink2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.surfaceMuted, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking)
                    }
                }
            }

            // 底部按钮
            HStack(spacing: Spacing.sm) {
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Text("取消")
                        .font(Typography.bodySmall.weight(.semibold))
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 36)
                        .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                Button {
                    triggerRewrite()
                } label: {
                    HStack(spacing: 6) {
                        if isWorking {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                        }
                        Text(isWorking ? "改写中…" : "改写")
                            .font(Typography.bodySmall.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 36)
                    .background(canSend ? Color.brand : Color.brand.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 380)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var canSend: Bool {
        !instruction.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking
    }

    private func triggerRewrite() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        isWorking = true
        Task {
            await onConfirm(trimmed)
            await MainActor.run {
                isWorking = false
            }
        }
    }
}
