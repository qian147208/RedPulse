//
//  DesignTokens.swift
//  RedPulse
//
//  Style direction: W + B  ——  SaaS-grade neutrals (Stripe/Linear) with
//  editorial typography (Apple Newsroom) and a single red accent inherited
//  from Xiaohongshu DNA. Cards are border-led, not shadow-led.
//
//  Supports system dark mode following Apple HIG color guidelines.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Adaptive color helper

/// Creates a Color that resolves differently in light and dark mode,
/// following the Apple HIG dynamic color pattern.
private func adaptive(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                      dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
    #if canImport(UIKit)
    return Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: light.3)
    })
    #elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
            : NSColor(red: light.0, green: light.1, blue: light.2, alpha: light.3)
    })
    #endif
}

// MARK: - Color tokens (Apple HIG adaptive)

extension Color {
    // Brand accent (rare, CTA-only)
    static let brand = adaptive(
        light: (1.0, 0.141, 0.259, 1.0),      // #FF2442
        dark:  (1.0, 0.302, 0.416, 1.0)        // #FF4D6A
    )
    static let brandSoft = adaptive(
        light: (1.0, 0.94, 0.95, 1.0),         // #FFF0F2
        dark:  (0.239, 0.082, 0.125, 1.0)      // #3D1520
    )

    // Neutral ramp — ink hierarchy (Apple HIG label system)
    static let ink = adaptive(
        light: (0.0, 0.0, 0.0, 1.0),           // #000000  label
        dark:  (1.0, 1.0, 1.0, 1.0)            // #FFFFFF  label
    )
    static let ink2 = adaptive(
        light: (0.235, 0.235, 0.263, 0.98),    // #3C3C43  secondaryLabel
        dark:  (0.922, 0.922, 0.961, 0.96)     // #EBEBF5  secondaryLabel
    )
    static let ink3 = adaptive(
        light: (0.235, 0.235, 0.263, 0.6),     // #3C3C43  tertiaryLabel
        dark:  (0.922, 0.922, 0.961, 0.6)      // #EBEBF5  tertiaryLabel
    )
    static let ink4 = adaptive(
        light: (0.235, 0.235, 0.263, 0.3),     // #3C3C43  quaternaryLabel
        dark:  (0.922, 0.922, 0.961, 0.3)      // #EBEBF5  quaternaryLabel
    )

    // Surfaces (Apple HIG grouped background hierarchy)
    static let bg = adaptive(
        light: (0.949, 0.949, 0.969, 1.0),     // #F2F2F7  systemGroupedBackground
        dark:  (0.0, 0.0, 0.0, 1.0)            // #000000  systemGroupedBackground
    )
    static let surface = adaptive(
        light: (1.0, 1.0, 1.0, 1.0),           // #FFFFFF  secondarySystemGroupedBackground
        dark:  (0.110, 0.110, 0.118, 1.0)      // #1C1C1E  secondarySystemGroupedBackground
    )
    static let surfaceMuted = adaptive(
        light: (0.949, 0.949, 0.969, 1.0),     // #F2F2F7  tertiarySystemGroupedBackground
        dark:  (0.173, 0.173, 0.180, 1.0)      // #2C2C2E  tertiarySystemGroupedBackground
    )

    // Borders & separators (Apple HIG separator system)
    static let border = adaptive(
        light: (0.776, 0.776, 0.784, 1.0),     // #C6C6C8  separator (opaque)
        dark:  (0.220, 0.220, 0.227, 1.0)      // #38383A  separator (opaque)
    )
    static let borderStrong = adaptive(
        light: (0.690, 0.690, 0.698, 1.0),     // #B0B0B2
        dark:  (0.329, 0.329, 0.345, 1.0)      // #545458
    )
    static let separator = adaptive(
        light: (0.776, 0.776, 0.784, 0.6),     // #C6C6C8  separator
        dark:  (0.329, 0.329, 0.345, 0.65)     // #545458  separator
    )

    // Suggestion card (AI section — blue-tinted)
    static let suggestionBlue = adaptive(
        light: (0.137, 0.310, 0.580, 1.0),     // #234E94
        dark:  (0.345, 0.651, 1.0, 1.0)        // #58A6FF
    )
    static let suggestionBg = adaptive(
        light: (0.941, 0.961, 0.988, 1.0),     // #F0F5FC
        dark:  (0.051, 0.114, 0.188, 1.0)      // #0D1D30
    )
    static let suggestionBorder = adaptive(
        light: (0.737, 0.808, 0.910, 1.0),     // #BCCEE8
        dark:  (0.122, 0.227, 0.373, 1.0)      // #1F3A5F
    )

    // Status colors (Apple HIG system colors)
    static let success = adaptive(
        light: (0.204, 0.780, 0.349, 1.0),     // #34C759  systemGreen
        dark:  (0.188, 0.816, 0.345, 1.0)      // #30D158  systemGreen
    )
    static let warning = adaptive(
        light: (1.0, 0.584, 0.0, 1.0),         // #FF9500  systemOrange
        dark:  (1.0, 0.624, 0.039, 1.0)        // #FF9F0A  systemOrange
    )
    static let danger = adaptive(
        light: (1.0, 0.231, 0.188, 1.0),       // #FF3B30  systemRed
        dark:  (1.0, 0.271, 0.227, 1.0)        // #FF453A  systemRed
    )

    // Status tinted backgrounds (for status pills)
    static let successBg = adaptive(
        light: (0.910, 0.976, 0.945, 1.0),     // #E8F9F1
        dark:  (0.039, 0.180, 0.078, 1.0)      // #0A2E14
    )
    static let warningBg = adaptive(
        light: (1.0, 0.957, 0.902, 1.0),       // #FFF4E6
        dark:  (0.176, 0.122, 0.0, 1.0)        // #2D1F00
    )
    static let errorBg = adaptive(
        light: (1.0, 0.945, 0.949, 1.0),       // #FFF1F2
        dark:  (0.239, 0.082, 0.094, 1.0)      // #3D1518
    )
}

// MARK: - Shadow colors (adaptive for dark mode)

extension Color {
    /// Subtle shadow for cards — barely visible in light, pronounced in dark
    static let shadowCard = adaptive(
        light: (0.0, 0.0, 0.0, 0.08),
        dark:  (0.0, 0.0, 0.0, 0.4)
    )
    /// Elevated shadow for floating elements (FAB, dropdowns)
    static let shadowElevated = adaptive(
        light: (0.0, 0.0, 0.0, 0.15),
        dark:  (0.0, 0.0, 0.0, 0.6)
    )
}

// MARK: - Appearance mode (light / dark / system)

enum AppearanceMode: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Spacing scale (tighter than before — editorial density)

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let section: CGFloat = 28
    static let page: CGFloat = 24    // horizontal page margin
}

// MARK: - Radius scale (smaller than before — corners 8-12pt)

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let pill: CGFloat = 999
}

// MARK: - Border width

enum BorderWidth {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1
    static let strong: CGFloat = 1.5
}

// MARK: - Typography (W+B editorial)

enum Typography {
    /// Hero / page titles — New York serif (SwiftUI .serif design)
    static let hero = Font.system(size: 32, weight: .bold, design: .serif)
    static let pageTitle = Font.system(size: 24, weight: .semibold, design: .serif)

    /// Section / card titles — sans, weight matters
    static let sectionTitle = Font.system(size: 18, weight: .semibold)
    static let cardTitle = Font.system(size: 16, weight: .semibold)

    /// Body
    static let body = Font.system(size: 17, weight: .regular)
    static let bodyEmphasis = Font.system(size: 17, weight: .medium)
    static let bodySmall = Font.system(size: 15, weight: .regular)

    /// Labels / captions (uppercase tracking suits editorial feel)
    static let label = Font.system(size: 15, weight: .semibold)
    static let caption = Font.system(size: 15, weight: .regular)

    /// Micro labels — tiny badges, overlay annotations only
    static let micro = Font.system(size: 13, weight: .semibold)

    /// Monospaced digits — counters, timestamps, hotScore (admin)
    static let mono = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .medium, design: .monospaced)

    /// Toolbar / interactive chrome — slightly larger than caption for touch targets
    static let toolbarLabel = Font.system(size: 15, weight: .semibold)
    static let toolbarIcon = Font.system(size: 17, weight: .medium)
}

// MARK: - Animation

enum AnimDuration {
    static let fast: Double = 0.15
    static let normal: Double = 0.25
    static let slow: Double = 0.4
    static let spring: Double = 0.3
    static let morph: Double = 0.35
}

// MARK: - Liquid Glass material colors (progressive: simulates glass on iOS 17+, native on iOS 26+)

extension Color {
    /// Surface color for Liquid Glass navigation elements (sidebar, tab bar).
    /// On iOS 26+ this maps to the native glass material; on earlier OS it's
    /// a semi-transparent adaptive color that works with .ultraThinMaterial.
    static let glassSurface = adaptive(
        light: (1.0, 1.0, 1.0, 0.72),
        dark:  (0.110, 0.110, 0.118, 0.82)
    )
    /// More opaque glass variant for sheets and large overlays.
    static let glassElevated = adaptive(
        light: (1.0, 1.0, 1.0, 0.88),
        dark:  (0.173, 0.173, 0.180, 0.92)
    )
    /// Subtle highlight that sits on top of glass surfaces to simulate lensing.
    static let glassHighlight = adaptive(
        light: (1.0, 1.0, 1.0, 0.55),
        dark:  (1.0, 1.0, 1.0, 0.12)
    )
    /// Shadow color specifically tuned for glass elements — softer and more
    /// diffuse than card shadows, with the shadow opacity adapting to the
    /// background brightness (darker bg → deeper shadow → stronger perceived elevation).
    static let glassShadow = adaptive(
        light: (0.0, 0.0, 0.0, 0.10),
        dark:  (0.0, 0.0, 0.0, 0.50)
    )
    /// The inner glow that appears when a glass element is pressed/interacted with.
    /// This simulates the Liquid Glass "energize with light" behavior.
    static let glassGlow = adaptive(
        light: (1.0, 1.0, 1.0, 0.70),
        dark:  (1.0, 1.0, 1.0, 0.25)
    )
    /// Tinted glass for primary action emphasis — brand-colored transparent overlay.
    static let glassBrandTint = adaptive(
        light: (1.0, 0.141, 0.259, 0.18),
        dark:  (1.0, 0.302, 0.416, 0.22)
    )
}

// MARK: - Screen metrics (Observable singleton, GeometryReader-driven)

/// Observable singleton for the current window size.
/// Updated by `ScreenMetricsTracker` (GeometryReader at app root).
/// Because it's `@Observable`, any SwiftUI view that reads its properties
/// will automatically re-render when the window resizes (rotation,
/// iPad multitasking, Stage Manager, etc.).
///
/// Replaces the deprecated `UIScreen.main.bounds` approach.
@Observable
final class ScreenMetrics {
    /// Shared instance — the single source of truth for window dimensions.
    static let shared = ScreenMetrics()

    var width: CGFloat = 393    // default: iPhone 13/14/15 standard
    var height: CGFloat = 852
}

/// Root-level view modifier that injects GeometryReader to track window size.
/// Apply once at the top of the view hierarchy (in RedPulseApp).
/// Updates `ScreenMetrics.shared` so all views that read `Adaptive.*`
/// re-render when the window size changes.
struct ScreenMetricsTracker: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            ScreenMetrics.shared.width = geo.size.width
                            ScreenMetrics.shared.height = geo.size.height
                        }
                        .onChange(of: geo.size) { _, newSize in
                            ScreenMetrics.shared.width = newSize.width
                            ScreenMetrics.shared.height = newSize.height
                        }
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Tracks screen dimensions for the `Adaptive` system.
    /// Apply once at the app root.
    func trackScreenMetrics() -> some View {
        modifier(ScreenMetricsTracker())
    }
}

// MARK: - Screen size adaptation (iPhone 13+)

/// Adapts spacing, font sizes, and layout values to the current device screen width.
/// Buckets: iPhone SE/mini (≤375pt) → tight, iPhone 13-16 (376-429pt) → standard,
/// iPhone Plus/Pro Max (≥430pt) → spacious.
///
/// All properties read from `ScreenMetrics.shared` which is `@Observable`,
/// so SwiftUI views automatically re-render when the window size changes.
enum Adaptive {
    #if os(iOS)
    // MARK: - Spacing

    public static var horizontalPageMargin: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 12 }
        if w < 430  { return 16 }
        return 20
    }

    public static var cardPadding: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 12 }
        if w < 430  { return 16 }
        return 20
    }

    public static var stackSpacing: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 10 }
        if w < 430  { return 12 }
        return 16
    }

    // MARK: - Font scaling

    /// Scale factor: 0.92 (SE) → 1.0 (standard) → 1.08 (Pro Max).
    public static var fontScale: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 0.92 }
        if w < 430  { return 1.0 }
        return min(w / 393, 1.08)
    }

    public static var heroFontSize: CGFloat { 26 * fontScale }
    public static var sectionTitleFontSize: CGFloat { 18 * fontScale }
    public static var cardTitleFontSize: CGFloat { 16 * fontScale }

    // MARK: - Layout dimensions

    public static var tabIconSize: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 20 }
        if w < 430  { return 22 }
        return 24
    }

    public static var tabLabelSize: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 11 }
        if w < 430  { return 12 }
        return 13
    }

    public static var tabItemHeight: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 46 }
        if w < 430  { return 48 }
        return 52
    }

    public static var thumbSize: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 64 }
        if w < 430  { return 72 }
        return 80
    }

    public static var buttonHeight: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 48 }
        if w < 430  { return 52 }
        return 52
    }

    public static var floatingButtonBottomPadding: CGFloat {
        let w = ScreenMetrics.shared.width
        if w <= 375 { return 56 }
        if w < 430  { return 64 }
        return 64
    }

    // MARK: - Grid columns

    public static var adTypeColumns: Int { 2 }

    #else
    public static let horizontalPageMargin: CGFloat = 24
    public static let cardPadding: CGFloat = 16
    public static let stackSpacing: CGFloat = 12
    public static let fontScale: CGFloat = 1.0
    public static let heroFontSize: CGFloat = 26
    public static let sectionTitleFontSize: CGFloat = 18
    public static let cardTitleFontSize: CGFloat = 16
    public static let tabIconSize: CGFloat = 22
    public static let tabLabelSize: CGFloat = 12
    public static let tabItemHeight: CGFloat = 48
    public static let thumbSize: CGFloat = 72
    public static let buttonHeight: CGFloat = 52
    public static let floatingButtonBottomPadding: CGFloat = 64
    public static let adTypeColumns: Int = 2
    #endif
}

// MARK: - Glass-specific spacing & sizing

enum GlassMetrics {
    /// Minimum touch target size per Apple HIG
    static let minTouchTarget: CGFloat = 44
    /// Standard glass button size (capsule height)
    static let buttonHeight: CGFloat = 44
    /// Chip height — must be ≥44pt per Apple HIG touch target
    static let chipHeight: CGFloat = 44
    /// Glass toolbar height (bottom floating bar)
    static let toolbarHeight: CGFloat = 52
    /// Glass sidebar minimum width
    static let sidebarMinWidth: CGFloat = 220
    /// Glass sidebar ideal width
    static let sidebarIdealWidth: CGFloat = 260
    /// Glass sidebar max width
    static let sidebarMaxWidth: CGFloat = 340
    /// Corner radius for glass containers (matches Apple's Liquid Glass aesthetic)
    static let glassRadius: CGFloat = 20
    /// Small glass radius for nested elements
    static let glassRadiusSmall: CGFloat = 14
    /// Shadow radius for glass surfaces — wider and softer than card shadows
    static let glassShadowRadius: CGFloat = 24
    /// Shadow offset for glass surfaces — small y offset for floating feel
    static let glassShadowY: CGFloat = 4

    // Selection toolbar
    static let selectionToolbarHeight: CGFloat = 54
    static let selectionToolbarButtonSize: CGFloat = 44
    static let selectionResultCardMaxWidth: CGFloat = 360
}
