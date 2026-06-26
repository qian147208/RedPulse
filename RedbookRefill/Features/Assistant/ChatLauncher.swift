//
//  ChatLauncher.swift
//  RedPulse
//
//  全局 AI 助手 FAB。每个 Tab 都看得到，点击打开 AI 笔记助手。
//  - macOS: 调 openWindow 打开独立 Window（Cmd+Shift+A 快捷键）
//  - iPad: sheet 弹出（保持上下文）
//  - iPhone: fullScreenCover 弹出（避免误关）
//  - 可拖拽到屏幕任何位置；位置用 @AppStorage 持久化（按容器宽高的分数存）
//

import SwiftUI

struct ChatLauncher: View {
    /// 持久化的位置 fraction（0-1），默认靠右下但避开底部 Tab 栏
    @AppStorage("chat_launcher_pos_fx") private var posFractionX: Double = 0.93
    @AppStorage("chat_launcher_pos_fy") private var posFractionY: Double = 0.84

    /// 拖拽中的瞬时偏移（拖完结后并到 AppStorage 再清零）
    @State private var dragDelta: CGSize = .zero
    /// 区分 tap 与 drag：超过 8pt 才算拖
    @State private var didDrag: Bool = false
    /// 贴边隐藏：拖到左右边缘时只露 16pt
    @State private var snappedToEdge: Edge? = nil

    private enum Edge {
        case left, right
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var showSheet: Bool = false
    #endif

    private var titleBarHeight: CGFloat {
        #if os(macOS)
        return 60
        #else
        // P1-6: 已关闭 Mac Catalyst（SUPPORTS_MACCATALYST = NO），这里不再需要 Catalyst 分支。
        // iOS app on Mac（通过 App Store 在 Apple Silicon Mac 上跑 iOS app）走 isiOSAppOnMac 检查。
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return 60
        }
        if sizeClass == .regular {
            return 50
        }
        return 0
        #endif
    }

    private static let buttonSize: CGFloat = 56
    private static let dragThreshold: CGFloat = 8
    private static let edgeInset: CGFloat = 12     // 离屏边的最小距离

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let base = anchorPoint(in: size)
            let snapThreshold: CGFloat = 44  // 距边缘 44pt 内触发贴边
            let snapPeek: CGFloat = 16       // 贴边后露出的宽度
            let snappedX: CGFloat = {
                guard let edge = snappedToEdge else { return base.x + dragDelta.width }
                if edge == .right { return size.width - snapPeek + Self.buttonSize / 2 }
                return snapPeek - Self.buttonSize / 2
            }()
            let liveX = clamp(snappedX,
                              min: Self.buttonSize / 2 + Self.edgeInset,
                              max: size.width - Self.buttonSize / 2 - Self.edgeInset)
            let liveY = clamp(base.y + dragDelta.height,
                              min: Self.buttonSize / 2 + Self.edgeInset + titleBarHeight,
                              max: size.height - Self.buttonSize / 2 - Self.edgeInset)

            launcherButton
                .scaleEffect(snappedToEdge != nil ? 0.65 : 1.0)
                .opacity(snappedToEdge != nil ? 0.7 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: snappedToEdge)
                .position(x: liveX, y: liveY)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // 拖拽时取消贴边
                            if snappedToEdge != nil {
                                snappedToEdge = nil
                            }
                            let dist = hypot(value.translation.width, value.translation.height)
                            if dist > Self.dragThreshold {
                                didDrag = true
                            }
                            if didDrag {
                                dragDelta = value.translation
                            }
                        }
                        .onEnded { value in
                            defer {
                                dragDelta = .zero
                                didDrag = false
                            }
                            // 拖拽 → 提交新位置 + 贴边检测
                            if didDrag {
                                let rawX = base.x + value.translation.width
                                let rawY = base.y + value.translation.height
                                let finalX = clamp(rawX,
                                                   min: Self.buttonSize / 2 + Self.edgeInset,
                                                   max: size.width - Self.buttonSize / 2 - Self.edgeInset)
                                let finalY = clamp(rawY,
                                                   min: Self.buttonSize / 2 + Self.edgeInset + titleBarHeight,
                                                   max: size.height - Self.buttonSize / 2 - Self.edgeInset)
                                // 贴边检测
                                if rawX < snapThreshold {
                                    snappedToEdge = .left
                                } else if rawX > size.width - snapThreshold {
                                    snappedToEdge = .right
                                } else {
                                    snappedToEdge = nil
                                }
                                posFractionX = Double(finalX / max(size.width, 1))
                                posFractionY = Double(finalY / max(size.height, 1))
                            } else {
                                // 点击 → 如果有贴边先取消
                                if snappedToEdge != nil {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                        snappedToEdge = nil
                                    }
                                }
                                openAssistant()
                            }
                        }
                )
        }
        #if !os(macOS)
        .modifier(SheetPresenter(showSheet: $showSheet))
        #endif
        // External triggers → open assistant (Pencil double-tap, macOS menu ⌘⇧A, etc.)
        .onReceive(NotificationCenter.default.publisher(for: .pencilDoubleTapOpenAssistant)) { _ in
            openAssistant()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAIAssistant)) { _ in
            openAssistant()
        }
        // Pencil double-tap handler: tucked inside ChatLauncher so it never
        // interferes with the drag gesture on the button itself.
        #if os(iOS)
        .overlay {
            PencilDoubleTapHandler {
                openAssistant()
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        #endif
        // 透传背景区域的命中：GeometryReader 默认不吞普通点击，按钮的命中区只在 56×56 圆内
        .allowsHitTesting(true)
    }

    /// 按持久化分数 + 容器大小，算出按钮中心点；fraction 0=左/顶，1=右/底
    private func anchorPoint(in size: CGSize) -> CGPoint {
        let inset = Self.buttonSize / 2 + Self.edgeInset
        let minX = inset, maxX = max(inset, size.width - inset)
        let minY = inset + titleBarHeight, maxY = max(minY, size.height - inset)
        let x = clamp(CGFloat(posFractionX) * size.width, min: minX, max: maxX)
        let y = clamp(CGFloat(posFractionY) * size.height, min: minY, max: maxY)
        return CGPoint(x: x, y: y)
    }

    private func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(v, lo), hi)
    }

    private func openAssistant() {
        HapticManager.lightImpact()
        #if os(macOS)
        openWindow(id: "global-assistant")
        #else
        showSheet = true
        #endif
    }

    private var launcherButton: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.brand, Color.brand.opacity(0.78)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: Self.buttonSize, height: Self.buttonSize)
        .shadow(color: Color.brand.opacity(didDrag ? 0.5 : 0.35),
                radius: didDrag ? 16 : 12, x: 0, y: didDrag ? 8 : 6)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .scaleEffect(didDrag ? 1.08 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: didDrag)
        .contentShape(Circle())
        #if os(macOS)
        .keyboardShortcut("a", modifiers: [.command, .shift])
        #endif
        .help("AI 笔记助手 (⇧⌘A) · 长按拖动")
        .accessibilityLabel("打开 AI 笔记助手")
        .accessibilityHint("拖拽可移动位置")
    }
}

#if !os(macOS)
/// iPhone fullScreenCover / iPad sheet 二选一
private struct SheetPresenter: ViewModifier {
    @Binding var showSheet: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.sheet(isPresented: $showSheet) {
                NavigationStack {
                    GlobalAssistantRoot()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showSheet = false }
                            }
                        }
                }
                .frame(minWidth: 720, minHeight: 560)
            }
        } else {
            content.fullScreenCover(isPresented: $showSheet) {
                NavigationStack {
                    GlobalAssistantRoot()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showSheet = false }
                            }
                        }
                }
            }
        }
    }
}
#endif
