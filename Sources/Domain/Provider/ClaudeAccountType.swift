import Foundation

/// Represents the type of Claude account being used.
/// Claude Max accounts have percentage-based quotas, while API accounts track costs.
public enum ClaudeAccountType: String, Sendable, Equatable, Hashable {
    /// Claude Max subscription with session/weekly quotas
    case max
    /// Claude API account with pay-per-use pricing
    case api
}
