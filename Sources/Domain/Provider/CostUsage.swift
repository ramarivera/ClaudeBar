import Foundation

/// Represents cost-based usage data for Claude API accounts.
/// This is distinct from UsageQuota which tracks percentage-based quotas.
public struct CostUsage: Sendable, Equatable, Hashable {
    /// The total cost in dollars
    public let totalCost: Decimal

    /// Total time spent on API calls
    public let apiDuration: TimeInterval

    /// Total wall clock time (includes thinking/typing time)
    public let wallDuration: TimeInterval

    /// Number of lines of code added
    public let linesAdded: Int

    /// Number of lines of code removed
    public let linesRemoved: Int

    /// The provider ID this cost belongs to (e.g., "claude")
    public let providerId: String

    /// When this usage data was captured
    public let capturedAt: Date

    // MARK: - Initialization

    public init(
        totalCost: Decimal,
        apiDuration: TimeInterval,
        wallDuration: TimeInterval = 0,
        linesAdded: Int = 0,
        linesRemoved: Int = 0,
        providerId: String,
        capturedAt: Date = Date()
    ) {
        self.totalCost = totalCost
        self.apiDuration = apiDuration
        self.wallDuration = wallDuration
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.providerId = providerId
        self.capturedAt = capturedAt
    }

    // MARK: - Formatting

    /// Formatted cost string (e.g., "$0.55")
    public var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalCost as NSDecimalNumber) ?? "$\(totalCost)"
    }

    /// Formatted API duration (e.g., "6m 19.7s")
    public var formattedApiDuration: String {
        formatDuration(apiDuration)
    }

    /// Formatted wall duration (e.g., "6h 33m 10.2s")
    public var formattedWallDuration: String {
        formatDuration(wallDuration)
    }

    /// Formatted code changes (e.g., "+10 / -5 lines")
    public var formattedCodeChanges: String {
        "+\(linesAdded) / -\(linesRemoved) lines"
    }

    // MARK: - Budget Calculation

    /// Calculates the budget status based on the given budget threshold
    public func budgetStatus(budget: Decimal) -> BudgetStatus {
        BudgetStatus.from(cost: totalCost, budget: budget)
    }

    /// Calculates the percentage of budget used
    public func budgetPercentUsed(budget: Decimal) -> Double {
        guard budget > 0 else { return 0 }
        let percentage = (totalCost / budget) * 100
        return Double(truncating: percentage as NSDecimalNumber)
    }

    // MARK: - Private Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)

        if hours > 0 {
            return String(format: "%dh %dm %.1fs", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %.1fs", minutes, seconds)
        } else {
            return String(format: "%.1fs", seconds)
        }
    }
}
