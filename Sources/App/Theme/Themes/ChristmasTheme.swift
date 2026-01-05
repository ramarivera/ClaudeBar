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

    // MARK: - Christmas-Specific Colors (Matching original AppTheme)

    private let christmasBlack = Color(red: 0.08, green: 0.06, blue: 0.10)
    private let christmasRed = Color(red: 0.92, green: 0.12, blue: 0.15)      // Original red
    private let christmasCrimson = Color(red: 0.72, green: 0.08, blue: 0.12)  // Darker red
    private let christmasGreen = Color(red: 0.10, green: 0.72, blue: 0.32)    // Original green
    private let christmasForest = Color(red: 0.05, green: 0.52, blue: 0.22)   // Darker green
    private let christmasGold = Color(red: 1.0, green: 0.84, blue: 0.0)       // Original gold
    private let christmasGoldWarm = Color(red: 0.95, green: 0.70, blue: 0.15) // Warm gold
    private let christmasSnow = Color(red: 0.98, green: 0.98, blue: 1.0)
    private let christmasDarkGreen = Color(red: 0.12, green: 0.45, blue: 0.28)

    // MARK: - Background (Matching original - red top, green bottom)

    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.25, green: 0.05, blue: 0.08),  // Deep red tint top
                Color(red: 0.10, green: 0.10, blue: 0.12),  // Charcoal middle
                Color(red: 0.05, green: 0.18, blue: 0.10)   // Deep green tint bottom
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

    // MARK: - Cards & Glass (Matching original AppTheme)

    public var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                christmasGold.opacity(0.03)  // Subtle gold shimmer
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var glassBackground: Color {
        Color.white.opacity(0.10)  // Match original
    }

    public var glassBorder: Color {
        christmasGold.opacity(0.6)  // Match original AppTheme
    }

    public var glassHighlight: Color {
        christmasGold.opacity(0.7)  // Match original AppTheme
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

    // MARK: - Accents (Matching original AppTheme)

    public var accentPrimary: Color { christmasRed }
    public var accentSecondary: Color { christmasGreen }

    /// Christmas accent gradient - red to gold (festive!)
    public var accentGradient: LinearGradient {
        LinearGradient(
            colors: [christmasRed, christmasGold],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Christmas pill gradient - subtle red/green shimmer
    public var pillGradient: LinearGradient {
        LinearGradient(
            colors: [
                christmasRed.opacity(0.3),
                christmasGreen.opacity(0.2)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Christmas gold gradient - for share button
    public var shareGradient: LinearGradient {
        LinearGradient(
            colors: [christmasGold, christmasGoldWarm],
            startPoint: .leading,
            endPoint: .trailing
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
