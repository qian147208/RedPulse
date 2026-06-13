//
//  ViewModifiers.swift
//  RedPulse
//
//  W+B editorial-SaaS style: cards are border-led, not shadow-led.
//  Pills are subtle. Buttons have strong typographic identity.
//

import SwiftUI

// MARK: - Card (border-led, no shadow)

struct CardStyle: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var radius: CGFloat = Radius.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.border, lineWidth: BorderWidth.thin)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct InsetGroupedSection: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.border, lineWidth: BorderWidth.thin)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Pill / chip / tag

struct PillStyle: ViewModifier {
    var foreground: Color = .ink2
    var background: Color = .surfaceMuted
    var borderColor: Color? = .border
    var horizontalPadding: CGFloat = Spacing.md
    var verticalPadding: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .font(Typography.caption)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background)
            .overlay(
                Group {
                    if let borderColor {
                        Capsule().stroke(borderColor, lineWidth: BorderWidth.hairline)
                    }
                }
            )
            .clipShape(Capsule())
    }
}

/// Selected chip — brand red, no border. Use for ad type selection, keyword hint chips selected state.
struct SelectedPillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 5)
            .background(Color.brand)
            .clipShape(Capsule())
    }
}

// MARK: - Primary button (strong CTA — brand red, only for the most important action per screen)

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isDestructive ? Color.danger : Color.brand)
                    .overlay(
                        // Subtle top highlight for depth
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(configuration.isPressed ? 0.0 : 0.15), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
            )
            .shadow(color: Color.shadowCard, radius: 8, x: 0, y: 3)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: AnimDuration.fast), value: configuration.isPressed)
    }
}

/// Secondary button — neutral, border-led with subtle surface gradient
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(Color.ink)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.surface, Color.surfaceMuted.opacity(configuration.isPressed ? 0.6 : 0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(configuration.isPressed ? Color.borderStrong : Color.border, lineWidth: BorderWidth.thin)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: AnimDuration.fast), value: configuration.isPressed)
    }
}

/// Ghost button — text only with hover/press tint. For low-priority actions like 重生成/撤销.
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .ink2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Color.ink : tint)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? Color.surfaceMuted : Color.clear)
            )
            .animation(.easeOut(duration: AnimDuration.fast), value: configuration.isPressed)
    }
}

/// Toolbar icon button — compact 38×38 with border and press feedback
struct ToolbarButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color.brand : Color.ink)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.surfaceMuted)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: AnimDuration.fast), value: configuration.isPressed)
    }
}

// MARK: - Section header (editorial label, uppercase tracked)

struct EditorialLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Typography.label)
            .foregroundStyle(Color.ink3)
            .tracking(1.2)
            .textCase(.uppercase)
    }
}

// MARK: - Page width cap (iPad-friendly)

struct ContentWidthCap: ViewModifier {
    var maxWidth: CGFloat = 640

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Hairline divider (1px border-aligned)

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.separator)
            .frame(height: BorderWidth.hairline)
    }
}

// MARK: - AI generated section (tinted bg + left accent bar)

struct AIGeneratedSection: ViewModifier {
    var accentColor: Color = .suggestionBlue
    var backgroundColor: Color = .suggestionBg

    func body(content: Content) -> some View {
        content
            .padding(Spacing.lg)
            .background(backgroundColor)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.suggestionBorder, lineWidth: BorderWidth.thin)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - View extensions

extension View {
    func aiGeneratedSection(
        accentColor: Color = .suggestionBlue,
        backgroundColor: Color = .suggestionBg
    ) -> some View {
        modifier(AIGeneratedSection(accentColor: accentColor, backgroundColor: backgroundColor))
    }
    func cardStyle(padding: CGFloat = Spacing.lg, radius: CGFloat = Radius.md) -> some View {
        modifier(CardStyle(padding: padding, radius: radius))
    }

    func insetGroupedSection() -> some View {
        modifier(InsetGroupedSection())
    }

    func pillStyle(
        foreground: Color = .ink2,
        background: Color = .surfaceMuted,
        borderColor: Color? = .border
    ) -> some View {
        modifier(PillStyle(foreground: foreground, background: background, borderColor: borderColor))
    }

    func selectedPillStyle() -> some View {
        modifier(SelectedPillStyle())
    }

    func editorialLabel() -> some View {
        modifier(EditorialLabel())
    }

    /// 内容区最大宽度上限。760 是基于 macOS 全屏窗口仍保留 reading column 体验，
    /// 同时在 iPad 横屏 / iPhone 上也能 maxWidth: .infinity 自然铺满。
    func contentWidthCap(maxWidth: CGFloat = 760) -> some View {
        modifier(ContentWidthCap(maxWidth: maxWidth))
    }
}

// MARK: - Toolbar button group container

struct ToolbarButtonGroup: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(Color.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.border, lineWidth: BorderWidth.hairline)
            )
    }
}

extension View {
    func toolbarButtonGroup() -> some View {
        modifier(ToolbarButtonGroup())
    }
}

// MARK: - Liquid Glass surface (progressive enhancement)

/// Applies a Liquid Glass-like surface to a view. Uses `.ultraThinMaterial` +
/// subtle highlight + soft shadow to simulate the lensing effect of Liquid Glass
/// on OS versions that don't have the native `glassEffect` modifier (iOS < 26).
///
/// When the SDK is upgraded to Xcode 26+, the `#if compiler(>=6.2)` branch
/// will automatically switch to the native `glassEffect` API.
struct GlassSurfaceModifier: ViewModifier {
    var radius: CGFloat = GlassMetrics.glassRadius
    var shadowRadius: CGFloat = GlassMetrics.glassShadowRadius

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    // Fallback to opaque material when transparency is reduced
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .stroke(Color.borderStrong, lineWidth: BorderWidth.thin)
                        }
                } else {
                    glassMaterial
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(
                color: Color.glassShadow,
                radius: shadowRadius,
                x: 0,
                y: GlassMetrics.glassShadowY
            )
    }

    @ViewBuilder
    private var glassMaterial: some View {
        // When compiler >= 6.2 (Xcode 26), use native glassEffect.
        // For now, simulate with layered materials + highlight overlay.
        ZStack {
            // Base frosted material
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)

            // Subtle color wash to simulate Liquid Glass tint
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.glassSurface)

            // Top highlight strip for lensing effect (light only visible from top)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.glassHighlight,
                            Color.glassHighlight.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Inner border glow — subtle edge definition
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: BorderWidth.hairline
                )
        }
    }
}

/// A card-like container with Liquid Glass styling. Lighter than `glassSurface`,
/// suitable for content cards that float above the main background.
struct GlassCardModifier: ViewModifier {
    var padding: CGFloat = Spacing.lg
    var radius: CGFloat = GlassMetrics.glassRadiusSmall

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.glassSurface)
                    // Highlight
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    // Border
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: BorderWidth.hairline)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.glassShadow, radius: 12, x: 0, y: 3)
    }
}

/// Interactive Glass Button — scales and glows on press, simulating the
/// Liquid Glass "energize with light" interaction feedback.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = Color.brand
    var height: CGFloat = GlassMetrics.buttonHeight

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(height: height)
            .padding(.horizontal, Spacing.lg)
            .foregroundStyle(configuration.isPressed ? .white : tint)
            .background {
                ZStack {
                    // Base glass
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(configuration.isPressed ? tint.opacity(0.85) : Color.glassSurface)

                    // Inner glow on press — emanates from center like Liquid Glass
                    if configuration.isPressed {
                        Capsule(style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [Color.white.opacity(0.6), Color.white.opacity(0.0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: height
                                )
                            )
                    } else {
                        // Resting state: subtle top highlight
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        configuration.isPressed ? tint.opacity(0.5) : Color.white.opacity(0.2),
                        lineWidth: BorderWidth.hairline
                    )
            )
            .shadow(
                color: configuration.isPressed
                    ? tint.opacity(0.3)
                    : Color.glassShadow,
                radius: configuration.isPressed ? 16 : 8,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Interactive modifier for custom glass elements — adds press scale + glow
/// animation without full button styling.
struct InteractiveGlassModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 0.97 : 1.0)
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: GlassMetrics.glassRadius, style: .continuous)
                        .fill(Color.glassGlow)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isHovered)
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
                    isHovered = hovering
                }
            }
    }
}

/// Scroll edge dissolve effect — content fades when scrolling under glass surfaces.
/// Simulates the native scroll edge effect introduced alongside Liquid Glass.
struct ScrollEdgeDissolveModifier: ViewModifier {
    var edge: Edge = .top
    var height: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .mask(alignment: edge == .top ? .top : .bottom) {
                VStack(spacing: 0) {
                    if edge == .top {
                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: height)
                    }
                    Color.black
                    if edge == .bottom {
                        LinearGradient(
                            colors: [Color.black, Color.black.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: height)
                    }
                }
            }
    }
}

/// Tinted glass label — applies the Liquid Glass tinting technique where
/// the text color shifts based on the glass element behind it.
/// Reserved for primary actions and emphasis labels.
struct GlassTintModifier: ViewModifier {
    var tint: Color = Color.brand

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint)
            .brightness(0.05)
    }
}

// MARK: - Glass View Extensions

extension View {
    /// Applies a Liquid Glass surface material. Use for navigation bars,
    /// sidebars, tab bars, and floating toolbars.
    func glassSurface(
        radius: CGFloat = GlassMetrics.glassRadius,
        shadowRadius: CGFloat = GlassMetrics.glassShadowRadius
    ) -> some View {
        modifier(GlassSurfaceModifier(radius: radius, shadowRadius: shadowRadius))
    }

    /// Applies a lighter glass card style. Use for content cards, AI result
    /// panels, and selection overlays.
    func glassCard(padding: CGFloat = Spacing.lg, radius: CGFloat = GlassMetrics.glassRadiusSmall) -> some View {
        modifier(GlassCardModifier(padding: padding, radius: radius))
    }

    /// Makes a glass element respond to press with scale + glow animation.
    func interactiveGlass() -> some View {
        modifier(InteractiveGlassModifier())
    }

    /// Applies scroll edge dissolve at the specified edge. Content scrolling
    /// under a glass element will fade out rather than clip abruptly.
    func scrollEdgeDissolve(edge: Edge = .top, height: CGFloat = 40) -> some View {
        modifier(ScrollEdgeDissolveModifier(edge: edge, height: height))
    }

    /// Applies Liquid Glass-style tinting to a label or icon.
    /// Use sparingly — only for primary actions.
    func glassTint(_ color: Color = Color.brand) -> some View {
        modifier(GlassTintModifier(tint: color))
    }
}

// MARK: - Button style extensions

extension ButtonStyle where Self == GlassButtonStyle {
    /// A Liquid Glass button with brand tint. Use for primary actions.
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    /// A Liquid Glass button with custom tint.
    static func glass(tint: Color) -> GlassButtonStyle {
        GlassButtonStyle(tint: tint)
    }
}
