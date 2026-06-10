//
//  ResultLayoutHelpers.swift
//  RedPulse
//
//  Shared layout helpers extracted from ResultView (triple/dual pane layouts, drag handle, step columns).
//  These are layout utilities, not business logic — they take content as @ViewBuilder.
//

import SwiftUI

// MARK: - Layout Constants

struct ResultLayoutConstants {
    static let columnGap: CGFloat = 12
    static let pageHPad: CGFloat = 16
}

// MARK: - Drag Handle (resize divider)

struct ResultDragHandle: View {
    let usableWidth: CGFloat
    let editorWidth: CGFloat
    let gap: CGFloat
    let maxFraction: CGFloat
    let onDragChanged: (CGFloat) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: gap)
            .contentShape(Rectangle())
        #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
        #endif
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newW = editorWidth + value.translation.width
                        onDragChanged(min(max(newW / usableWidth, 0.25), maxFraction))
                    }
            )
    }
}

// MARK: - Step Column Container

struct ResultStepColumn<Content: View>: View {
    let step: Int
    let title: String
    let icon: String
    let content: Content

    init(step: Int, title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.step = step
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text("\(step)")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.brand, in: Circle())
                Image(systemName: icon)
                    .font(Typography.bodySmall.weight(.semibold))
                    .foregroundStyle(Color.ink3)
                Text(title)
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.border).frame(height: BorderWidth.hairline)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.hairline)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Collapsible Section

struct ResultCollapsibleSection<Content: View>: View {
    let id: String
    let label: String
    let counter: String?
    let showsCopy: Bool
    let copyText: () -> String
    let hasRegenerate: Bool
    let isRegenerating: Bool
    let isDualPanel: Bool
    let content: Content

    @State private var isCollapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Color.ink3)
                        .frame(width: 16)
                    Text(label).editorialLabel()
                    if let counter {
                        Text(counter).font(Typography.monoSmall).foregroundStyle(Color.ink3)
                    }
                    Spacer()
                    if isDualPanel {
                        if showsCopy {
                            copyButton
                        }
                        if hasRegenerate {
                            regenButton
                        }
                    } else if showsCopy || hasRegenerate {
                        Menu {
                            if showsCopy {
                                copyAllItem
                            }
                            if hasRegenerate {
                                regenItem
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(Typography.caption.weight(.semibold))
                                .foregroundStyle(Color.ink3)
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.horizontal, Spacing.lg)
                    content
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.border, lineWidth: BorderWidth.thin)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var copyButton: some View {
        Button {
            let text = copyText()
            guard !text.isEmpty else { return }
            #if canImport(UIKit) && !os(macOS)
            UIPasteboard.general.string = text
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                Text("复制")
            }
        }
        .buttonStyle(GhostButtonStyle())
        .help("复制\(label)")
    }

    private var regenButton: some View {
        Button {
            // Triggered from parent via onRegenerate
        } label: {
            HStack(spacing: 4) {
                if isRegenerating {
                    Text("Thinking...")
                        .font(Typography.bodySmall.weight(.medium))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("重生成")
                }
            }
        }
        .buttonStyle(GhostButtonStyle())
        .disabled(isRegenerating)
    }

    @ViewBuilder
    private var copyAllItem: some View {
        Button {
            let text = copyText()
            guard !text.isEmpty else { return }
            #if canImport(UIKit) && !os(macOS)
            UIPasteboard.general.string = text
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
        } label: {
            Label("复制\(label)", systemImage: "doc.on.doc")
        }
    }

    @ViewBuilder
    private var regenItem: some View {
        Button {
            // Triggered from parent
        } label: {
            Label("重生成\(label)", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isRegenerating)
    }
}

// MARK: - Preview Width Calculator

struct ResultPreviewHelper {
    /// 计算给定容器宽度下，预览卡的合适宽度
    /// - 上限 375pt（设计稿原始尺寸）
    /// - 下限 240pt（再小内部字号会挤死，由 ScrollView 兜底允许水平滚）
    /// - 中间按 容器宽 - 32pt 左右内边距 自适应
    static func responsivePreviewWidth(containerWidth: CGFloat) -> CGFloat {
        let target = containerWidth - 32
        return max(min(target, 375), 240)
    }
}
