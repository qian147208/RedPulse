//
//  HelpView.swift
//  RedPulse
//
//  帮助中心子页面（见需求 §模块8 M3）。FAQ 6 条，可折叠。
//  V3.2 调整：去掉「什么是爆款指数？」，新增「重生成后能撤销吗？」。
//

import SwiftUI

struct HelpView: View {
    // MARK: - FAQ data (按 V3.2 文档)

    private let faqs: [FAQItem] = [
        .init(
            question: "如何使用产品库？",
            answer: "在「产品库」Tab 中点击「+」可录入产品信息（名称、卖点、目标人群、使用场景、图片风格、风格参考图）。生成时点击产品卡片即可一键带入关键词。"
        ),
        .init(
            question: "生成结果能编辑吗？",
            answer: "可以。结果页中标题、正文、标签、配图建议、彩蛋金句都支持点击直接编辑,焦点离开自动保存。编辑过的记录会在历史列表中以「✏️」图标标记。优化建议为锁定字段，不可编辑。"
        ),
        .init(
            question: "访客有什么限制？",
            answer: "访客模式累计可生成 3 次,产品库管理、历史查看完全开放。3 次后生成按钮禁用,点击「设置 → 登录账号」即可解锁无限生成,期间录入的产品库与历史会保留。"
        ),
        .init(
            question: "标题/正文/标签可单独重生成？",
            answer: "可以。结果页每个区域右侧都有「🔄重生成」按钮,点击后仅刷新该字段,不会新增历史记录。响应时间通常 ≤ 5 秒。"
        ),
        .init(
            question: "重生成后能撤销吗？",
            answer: "可以。单独重生成成功后,底部会弹出 Toast「[字段]已更新 · 撤销」,5 秒内点击「撤销」可回滚到上一版本。超时 Toast 自动消失,撤销不可再进行。连续多次重生成只能撤回到最近一版。"
        ),
        .init(
            question: "配图建议是什么？",
            answer: "AI 根据产品特征生成的封面构图建议,包含主体摆放、角度、光线、背景元素等中文描述,帮助你拍出适合发笔记的图片。建议参考但不强制。"
        )
    ]

    // MARK: - State

    @State private var expanded: Set<Int> = []

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(Array(faqs.enumerated()), id: \.offset) { idx, item in
                    faqCard(index: idx, item: item)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bg)
        .navigationTitle("帮助中心")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - FAQ card

    private func faqCard(index: Int, item: FAQItem) -> some View {
        let isOpen = expanded.contains(index)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen {
                        expanded.remove(index)
                    } else {
                        expanded.insert(index)
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: Spacing.md) {
                    Text(item.question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md + 2)
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(item.answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md + 2)
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - FAQ model

private struct FAQItem {
    let question: String
    let answer: String
}
