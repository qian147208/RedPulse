//
//  SelectionToolbarView.swift
//  RedPulse
//
//  Lightweight AI floating toolbar for text selection.
//  Appears when text is selected in any text editor, offering quick AI actions
//  (translate, explain, summarize, rewrite, etc.) without modal disruption.
//
//  Platform adaptations:
//  - iPhone: Bottom-floating glass bar above the keyboard/safe area
//  - iPad: Appears near the selected text position (if position info available)
//  - Mac: Popover-style floating panel, keyboard-navigable
//

import SwiftUI
import Observation

// MARK: - Selection Toolbar View

struct SelectionToolbarView: View {
    @Bindable var viewModel: SelectionToolbarViewModel

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if viewModel.isVisible {
            VStack(spacing: Spacing.sm) {
                // Drop zone indicator (only shown when text is being dragged over)
                dropZoneHint
                    .transition(.scale.combined(with: .opacity))
                // Result card (shown after AI returns)
                if viewModel.resultText != nil || viewModel.errorMessage != nil {
                    resultCard
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                // Micro-adjustment panel
                if viewModel.showMicroAdjustments {
                    microAdjustmentPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Main action toolbar
                actionToolbar
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, toolbarBottomPadding)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: viewModel.isVisible)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: viewModel.resultText != nil)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.75), value: viewModel.showMicroAdjustments)
        }
    }

    // MARK: - Drop zone hint

    /// When text is dragged from another app (or within the app), the toolbar
    /// shows a drop indicator prompting the user to drop for AI processing.
    private var dropZoneHint: some View {
        Text("将文本拖到此处 → AI 处理")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.ink4)
            .textCase(.uppercase)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .opacity(0.6)
    }

    // MARK: - Platform padding

    private var toolbarBottomPadding: CGFloat {
        #if os(iOS)
        if sizeClass == .regular {
            return 24
        } else {
            // On iPhone, the toolbar sits above the tab bar / keyboard
            return 16
        }
        #else
        return 24
        #endif
    }

    // MARK: - Action Toolbar

    private var actionToolbar: some View {
        VStack(spacing: 0) {
            // Loading indicator (hidden on macOS — floating panel is compact)
            #if !os(macOS)
            if viewModel.isLoading {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.brand)
                    Text("AI 正在处理…")
                        .font(Typography.caption)
                        .foregroundStyle(Color.ink2)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                Divider().background(Color.separator)
            }
            #endif

            // Action buttons row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    // Recommended (primary) action
                    recommendedButton

                    // Divider
                    Rectangle()
                        .fill(Color.separator)
                        .frame(width: BorderWidth.hairline, height: 28)

                    // Other actions
                    ForEach(secondaryActions, id: \.self) { action in
                        actionButton(for: action)
                    }

                    // Micro-adjustments toggle
                    microAdjustToggle

                    // Close button
                    closeButton
                }
                #if os(macOS)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                #else
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                #endif
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background {
            #if os(macOS)
            Color.clear
            #else
            glassToolbarBackground
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous))
        .shadow(
            color: Color.glassShadow,
            radius: GlassMetrics.glassShadowRadius,
            x: 0,
            y: GlassMetrics.glassShadowY
        )
        // iPad Drag & Drop: accept text drops onto the toolbar
        .textDropTarget { droppedText in
            viewModel.show(for: droppedText)
        }
    }

    private var glassToolbarBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous)
                .fill(Color.glassSurface)
            // Top highlight
            RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.glassHighlight, Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }

    /// The secondary actions (excluding the recommended one and custom/close).
    private var secondaryActions: [QuickAction] {
        QuickAction.allCases
            .filter { $0 != viewModel.recommendedAction }
            .filter { $0 != .custom }
    }

    // MARK: - Recommended button (prominent, glass-tinted)

    private var recommendedButton: some View {
        Button {
            HapticManager.mediumImpact()
            viewModel.performAction(viewModel.recommendedAction)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.recommendedAction.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(viewModel.recommendedAction.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md)
            .frame(height: GlassMetrics.chipHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.brand)
            )
            .shadow(color: Color.brand.opacity(0.3), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("\(viewModel.recommendedAction.displayName)（推荐）")
        .accessibilityHint("对选中的文本执行\(viewModel.recommendedAction.displayName)操作")
    }

    // MARK: - Secondary action button

    private func actionButton(for action: QuickAction) -> some View {
        Button {
            HapticManager.lightImpact()
            viewModel.performAction(action)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 13, weight: .medium))
                Text(action.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, Spacing.sm + 2)
            .frame(height: GlassMetrics.chipHeight)
            .frame(minWidth: GlassMetrics.minTouchTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: BorderWidth.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(action.displayName)
    }

    // MARK: - Micro-adjust toggle

    private var microAdjustToggle: some View {
        Button {
            HapticManager.lightImpact()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.showMicroAdjustments.toggle()
                if viewModel.showMicroAdjustments {
                    viewModel.customInstruction = ""
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.showMicroAdjustments ? Color.brand : Color.ink2)
                .frame(width: GlassMetrics.chipHeight, height: GlassMetrics.chipHeight)
                .background(
                    Circle()
                        .fill(viewModel.showMicroAdjustments ? Color.brandSoft : Color.clear)
                )
                .background(
                    Circle()
                        .fill(.regularMaterial)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("更多选项")
        .accessibilityHint("展开微调和自定义指令选项")
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            HapticManager.lightImpact()
            viewModel.hide()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink3)
                .frame(width: GlassMetrics.chipHeight, height: GlassMetrics.chipHeight)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("关闭工具栏")
    }

    // MARK: - Result Card

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                Image(systemName: viewModel.activeAction?.icon ?? "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text(viewModel.activeAction?.displayName ?? "AI 结果")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Color.ink)
                Spacer()

                // Copy button
                Button {
                    viewModel.copyResult()
                    HapticManager.success()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .frame(width: GlassMetrics.minTouchTarget, height: GlassMetrics.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("复制结果")
            }

            // Error display
            if let error = viewModel.errorMessage {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.warning)
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(Color.ink2)
                    Spacer()
                    Button("重试") {
                        viewModel.retry()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                }
                .padding(Spacing.md)
                .background(Color.warningBg.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.md))
            }

            // Result text (or loading skeleton)
            if let result = viewModel.resultText {
                Text(result)
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(4)
                    .lineLimit(viewModel.isResultExpanded ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if result.count > 200 && !viewModel.isResultExpanded {
                    Button {
                        withAnimation(.easeOut(duration: AnimDuration.fast)) {
                            viewModel.isResultExpanded = true
                        }
                    } label: {
                        Text("展开全文…")
                            .font(Typography.caption)
                            .foregroundStyle(Color.brand)
                    }
                    .buttonStyle(.plain)
                }

                // Action buttons
                HStack(spacing: Spacing.sm) {
                    // Replace button (primary)
                    Button {
                        HapticManager.success()
                        viewModel.replaceText()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 12, weight: .semibold))
                            Text("替换原文")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: GlassMetrics.chipHeight)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.brand)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("用结果替换选中文本")

                    Spacer()

                    // Micro-adjust toggle (if not already visible)
                    if !viewModel.showMicroAdjustments {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.showMicroAdjustments = true
                            }
                        } label: {
                            Text("微调…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.ink2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: GlassMetrics.selectionResultCardMaxWidth)
        .glassCard(padding: 0, radius: GlassMetrics.glassRadiusSmall)
    }

    // MARK: - Micro-Adjustment Panel

    private var microAdjustmentPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
                Text("调整结果")
                    .font(Typography.cardTitle)
                    .foregroundStyle(Color.ink)
                Spacer()
                Button {
                    withAnimation { viewModel.showMicroAdjustments = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.ink3)
                        .frame(width: GlassMetrics.minTouchTarget, height: GlassMetrics.minTouchTarget)
                }
                .buttonStyle(.plain)
            }

            // Quick adjustment chips
            FlowLayout(spacing: Spacing.sm) {
                microChip("更短", icon: "text.badge.minus") {
                    viewModel.makeShorter()
                }
                microChip("更详细", icon: "text.badge.plus") {
                    viewModel.makeLonger()
                }
                microChip("更口语", icon: "bubble.left") {
                    viewModel.makeMoreCasual()
                }
                microChip("更正式", icon: "building.2") {
                    viewModel.makeMoreFormal()
                }
            }

            // Custom instruction
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("自定义指令")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink4)
                    .textCase(.uppercase)
                HStack(spacing: Spacing.sm) {
                    TextField("如：加入 emoji、突出产品卖点", text: $viewModel.customInstruction)
                        .textFieldStyle(.plain)
                        .font(Typography.caption)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs + 2)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .onSubmit {
                            viewModel.executeCustomInstruction()
                        }

                    Button {
                        viewModel.executeCustomInstruction()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: GlassMetrics.minTouchTarget, height: GlassMetrics.minTouchTarget)
                            .background(
                                Circle()
                                    .fill(viewModel.customInstruction.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.ink4 : Color.brand)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.customInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("发送自定义指令")
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: GlassMetrics.selectionResultCardMaxWidth)
        .glassCard(padding: 0, radius: GlassMetrics.glassRadiusSmall)
    }

    private func microChip(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.lightImpact()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, Spacing.md)
            .frame(height: GlassMetrics.chipHeight)
            .frame(minWidth: GlassMetrics.minTouchTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: BorderWidth.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
    }
}
