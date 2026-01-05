import SwiftUI

// MARK: - Christmas Theme

/// Festive holiday theme with red, green, and gold accents.
/// Features snowfall animation overlay and warm holiday colors.
public struct ChristmasTheme: AppThemeProvider {
    // MARK: - Identity

    public let id = "christmas"
    public let displayName = "Christmas"
    public let icon = "snowflake"
    public let subtitle: String? = "Festive"

    // MARK: - Christmas-Specific Colors

    private let christmasBlack = Color(red: 0.08, green: 0.06, blue: 0.10)
    private let christmasRed = Color(red: 0.92, green: 0.22, blue: 0.25)
    private let christmasGreen = Color(red: 0.18, green: 0.72, blue: 0.38)
    private let christmasGold = Color(red: 0.98, green: 0.82, blue: 0.32)
    private let christmasSnow = Color(red: 0.98, green: 0.98, blue: 1.0)
    private let christmasDarkGreen = Color(red: 0.12, green: 0.45, blue: 0.28)

    // MARK: - Background

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                christmasBlack,
                Color(red: 0.10, green: 0.08, blue: 0.14),
                Color(red: 0.12, green: 0.10, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { true }

    @MainActor
    public var overlayView: AnyView? {
        AnyView(ChristmasSnowfallOverlay(snowflakeCount: 25))
    }

    // MARK: - Cards & Glass

    public var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.15),
                Color.white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var glassBackground: Color {
        Color.white.opacity(0.12)
    }

    public var glassBorder: Color {
        christmasGold.opacity(0.35)
    }

    public var glassHighlight: Color {
        christmasGold.opacity(0.25)
    }

    public var cardCornerRadius: CGFloat { 14 }
    public var pillCornerRadius: CGFloat { 20 }

    // MARK: - Typography

    public var textPrimary: Color { christmasSnow }
    public var textSecondary: Color { christmasSnow.opacity(0.85) }
    public var textTertiary: Color { christmasSnow.opacity(0.6) }
    public var fontDesign: Font.Design { .rounded }

    // MARK: - Status Colors

    public var statusHealthy: Color { christmasGreen }
    public var statusWarning: Color { christmasGold }
    public var statusCritical: Color { christmasRed }
    public var statusDepleted: Color { christmasRed.opacity(0.7) }

    // MARK: - Accents

    public var accentPrimary: Color { christmasRed }
    public var accentSecondary: Color { christmasGreen }

    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [christmasRed, christmasGreen],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [
                christmasGreen.opacity(0.5),
                christmasRed.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [christmasGold, christmasGold.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Interactive States

    public var hoverOverlay: Color {
        christmasGold.opacity(0.1)
    }

    public var pressedOverlay: Color {
        christmasGold.opacity(0.15)
    }

    // MARK: - Progress Bar

    public var progressTrack: Color {
        Color.white.opacity(0.15)
    }

    // MARK: - Initializer

    public init() {}
}

// MARK: - Christmas Snowfall Overlay (Internal)

/// Snowfall animation overlay for Christmas theme
struct ChristmasSnowfallOverlay: View {
    let snowflakeCount: Int

    var body: some View {
        // Reference the existing SnowfallOverlay from Theme.swift
        // This will be migrated later, for now use the existing one
        SnowfallOverlay(snowflakeCount: snowflakeCount)
    }
}

// MARK: - Christmas Background Orbs

/// Animated background orbs with Christmas colors
struct ChristmasOrbsView: View {
    var body: some View {
        ChristmasBackgroundOrbs()
    }
}
