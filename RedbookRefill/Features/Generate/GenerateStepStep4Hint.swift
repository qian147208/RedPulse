//
//  GenerateStepStep4Hint.swift
//  RedPulse
//
//  Step 4: Style hint chips section for GenerateView.
//  Extracted from the original 1272-line GenerateView.
//

import SwiftUI

// MARK: - Step 4: Hint Chips

struct GenerateStepStep4Hint: View {
    @Binding var hintText: String
    @Binding var hintChips: [String]
    @Binding var isLoadingHints: Bool
    @Binding var showStep4Tip: Bool
    @Binding var showInspirationPicker: Bool
    @Binding var inspirationPickerType: InspirationType
    @Binding var refreshHintsToken: Int

    @AppStorage("hint_collapse") private var hintCollapsed = false

    var body: some View {
        let isCollapsed = hintCollapsed
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed { hintCollapsed = false }
                    else { hintCollapsed = true }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    stepBadge(4, active: !isCollapsed)
                    Text("风格关键词").editorialLabel()
                    Spacer()
                    if !isCollapsed {
                        if isLoadingHints {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                refreshHintsToken += 1
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.brand)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    inspirationButton(type: .style)

                    hintTextInputArea
                        .background(Color.surfaceMuted)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(Color.border, lineWidth: BorderWidth.hairline)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    if showStep4Tip {
                        step4TipView
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    FlowLayout(spacing: Spacing.sm) {
                        ForEach(hintChips, id: \.self) { chip in
                            let isSelected = hintText.contains(chip)
                            hintChip(chip: chip, isSelected: isSelected)
                        }
                    }
                }
                .padding(Spacing.lg)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !hintText.isEmpty {
                Text("风格：\(hintText)")
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sub-views

    private var hintTextInputArea: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                if hintText.isEmpty {
                    Text("写提示关键词，引导 AI 写作方向")
                        .font(Typography.bodySmall)
                        .foregroundStyle(Color.ink4)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $hintText)
                    .font(Typography.bodySmall)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 100)
            }
            .padding(Spacing.md)

            HStack(spacing: 8) {
                if !hintText.isEmpty {
                    Button {
                        hintText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(hintText.count) 字")
                    .font(Typography.monoSmall)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.trailing, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var step4TipView: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("💡")
                .font(.system(size: 13))
            Text("选择或输入风格关键词，可以微调大模型的生成语气，让您的笔记更具特色与说服力。")
                .font(Typography.caption)
                .foregroundStyle(Color.ink3)
                .lineSpacing(3)
            Spacer(minLength: 0)
            Button {
                withAnimation {
                    showStep4Tip = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ink4)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.brandSoft.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func inspirationButton(type: InspirationType) -> some View {
        Button {
            inspirationPickerType = type
            showInspirationPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12, weight: .medium))
                Text("从灵感板导入风格")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.suggestionBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.suggestionBg, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func hintChip(chip: String, isSelected: Bool) -> some View {
        Button {
            HapticManager.lightImpact()
            withAnimation(.spring(duration: 0.2, bounce: 0.2)) {
                if isSelected {
                    hintText = hintText
                        .replacingOccurrences(of: " \(chip)", with: "")
                        .replacingOccurrences(of: "\(chip) ", with: "")
                        .replacingOccurrences(of: chip, with: "")
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    if hintText.isEmpty {
                        hintText = chip
                    } else {
                        hintText += " " + chip
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(chip)
                    .font(Typography.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : Color.ink2)
            .background(isSelected ? Color.brand : Color.surfaceMuted)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stepBadge(_ num: Int, active: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text("STEP")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
            Text(String(format: "%02d", num))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(active ? Color.brand : Color.ink3)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(active ? Color.brandSoft : Color.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
