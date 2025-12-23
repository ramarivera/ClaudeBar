import Foundation

/// Represents the type of Claude account being used.
/// Different account tiers have different quota and cost tracking features.
public enum ClaudeAccountType: String, Sendable, Equatable, Hashable {
    /// Claude Max subscription with session/weekly quotas + optional extra usage cost tracking
    case max
    /// Claude Pro subscription with session/weekly quotas + optional extra usage cost tracking
    case pro
    /// Claude API account with pay-per-use pricing (cost tracking only)
    case api
}
