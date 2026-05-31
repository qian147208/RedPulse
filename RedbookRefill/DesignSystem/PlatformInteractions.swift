//
//  PlatformInteractions.swift
//  RedPulse
//
//  Platform-specific interaction modifiers:
//  - iPad: Drag & Drop (text dropping onto AI assistant)
//  - Apple Pencil: Double-tap quick action
//  - Mac: NSUserActivity / Handoff support
//

import SwiftUI

// MARK: - Notification names for cross-component communication

extension Notification.Name {
    /// Posted when the user double-taps Apple Pencil to quickly open the AI assistant.
    static let pencilDoubleTapOpenAssistant = Notification.Name("com.redpulse.pencilDoubleTapOpenAssistant")
    /// Posted when the macOS menu command (⇧⌘A) or other triggers request opening the AI assistant.
    static let openAIAssistant = Notification.Name("com.redpulse.openAIAssistant")
}

// MARK: - Text Drop Target (iPad Drag & Drop)

/// A view modifier that accepts text drops (from other apps or within the app)
/// and forwards the dropped text to a callback.
///
/// Usage:
/// ```swift
/// YourView()
///     .textDropTarget { droppedText in
///         viewModel.show(for: droppedText)
///     }
/// ```
struct TextDropTarget: ViewModifier {
    var onDrop: (String) -> Void
    /// Whether the drop zone should show a visual indicator when a drag hovers.
    var showIndicator: Bool = true

    @State private var isTargeted: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted && showIndicator {
                    RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous)
                        .fill(Color.brand.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous)
                                .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        )
                        .overlay(alignment: .center) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("松开以发送给 AI")
                                    .font(Typography.label)
                            }
                            .foregroundStyle(Color.brand)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.md)
                            .glassCard(padding: 0)
                        }
                        .padding(Spacing.md)
                        .transition(.opacity)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                // Concatenate all dropped strings
                let combined = items.joined(separator: "\n")
                guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                onDrop(combined)
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: AnimDuration.fast)) {
                    isTargeted = targeted
                }
            }
    }
}

// MARK: - Drag Source (for text within the app)

/// Adds drag-from-text capability to any view containing selectable text.
/// The dragged content is the provided text binding.
struct TextDragSource: ViewModifier {
    var text: String

    func body(content: Content) -> some View {
        content
            .draggable(text) {
                // Preview pill shown during drag
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12, weight: .medium))
                    Text(text.prefix(50))
                        .font(Typography.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: Color.glassShadow, radius: 8, x: 0, y: 4)
            }
    }
}

// MARK: - Apple Pencil double-tap handler (iPad)

#if os(iOS)
import UIKit

/// Hosts a UIPencilInteraction to detect Apple Pencil double-tap gestures
/// and route them to a SwiftUI callback.
struct PencilDoubleTapHandler: UIViewRepresentable {
    var onDoubleTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let interaction = UIPencilInteraction()
        interaction.delegate = context.coordinator
        view.addInteraction(interaction)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTap: onDoubleTap)
    }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        let onDoubleTap: () -> Void

        init(onDoubleTap: @escaping () -> Void) {
            self.onDoubleTap = onDoubleTap
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            // UIPencilInteraction fires on double-tap. The specific
            // tapAction depends on user Settings; we respond regardless.
            onDoubleTap()
        }
    }
}
#endif

// MARK: - Keyboard shortcut overlay (universal)

/// Adds a set of keyboard shortcuts to any view. On iPad with keyboard and Mac,
/// these provide quick access to common actions.
struct KeyboardShortcutOverlay: ViewModifier {
    var onEscape: (() -> Void)?
    var onEnter: (() -> Void)?
    var onSpace: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                onEscape?()
                return .handled
            }
            .onKeyPress(.return) {
                onEnter?()
                return .handled
            }
            .onKeyPress(.space) {
                onSpace?()
                return .handled
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Makes the view a drop target for text — useful for AI assistant input,
    /// search fields, and anywhere users might want to paste external text.
    func textDropTarget(
        showIndicator: Bool = true,
        onDrop: @escaping (String) -> Void
    ) -> some View {
        modifier(TextDropTarget(onDrop: onDrop, showIndicator: showIndicator))
    }

    /// Makes the view's text draggable to other apps (e.g. drag a note to Mail).
    func textDragSource(_ text: String) -> some View {
        modifier(TextDragSource(text: text))
    }

    /// Adds a transparent Pencil double-tap handler (iPad only).
    /// On platforms without Pencil support, this is a no-op.
    @ViewBuilder
    func pencilDoubleTap(action: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.overlay {
            PencilDoubleTapHandler(onDoubleTap: action)
                .frame(width: 0, height: 0) // invisible
                .allowsHitTesting(false)
        }
        #else
        self // no-op on macOS
        #endif
    }

    /// Adds common keyboard shortcuts (escape, enter, space).
    func keyboardShortcuts(
        onEscape: (() -> Void)? = nil,
        onEnter: (() -> Void)? = nil,
        onSpace: (() -> Void)? = nil
    ) -> some View {
        modifier(KeyboardShortcutOverlay(
            onEscape: onEscape,
            onEnter: onEnter,
            onSpace: onSpace
        ))
    }
}
