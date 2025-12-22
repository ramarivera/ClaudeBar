import Foundation
import Domain
import Mockable
import os.log

private let logger = Logger(subsystem: "com.claudebar", category: "CodexProbe")

// MARK: - RPC Client Protocol (for testability)

/// Protocol for Codex RPC client - enables mocking for unit tests.
@Mockable
public protocol CodexRPCClient: Sendable {
    func initialize() async throws
    func fetchRateLimits() async throws -> CodexRateLimitsResponse
    func shutdown()
}

/// Response from Codex rate limits API.
public struct CodexRateLimitsResponse: Sendable, Equatable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let planType: String?

    public init(primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?, planType: String? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

/// A rate limit window from Codex API.
public struct CodexRateLimitWindow: Sendable, Equatable {
    public let usedPercent: Double
    public let resetDescription: String?

    public init(usedPercent: Double, resetDescription: String?) {
        self.usedPercent = usedPercent
        self.resetDescription = resetDescription
    }
}

/// Factory type for creating RPC clients.
public typealias CodexRPCClientFactory = @Sendable (String, TimeInterval) throws -> any CodexRPCClient

/// Infrastructure adapter that probes the Codex CLI to fetch usage quotas.
/// Uses JSON-RPC via `codex app-server` for reliable data fetching.
public struct CodexUsageProbe: UsageProbe {
    private let codexBinary: String
    private let timeout: TimeInterval
    private let rpcClientFactory: CodexRPCClientFactory
    private let cliExecutor: CLIExecutor

    public init(
        codexBinary: String = "codex",
        timeout: TimeInterval = 20.0,
        rpcClientFactory: CodexRPCClientFactory? = nil,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.codexBinary = codexBinary
        self.timeout = timeout
        self.rpcClientFactory = rpcClientFactory ?? { binary, timeout in
            try DefaultCodexRPCClient(executable: binary, timeout: timeout)
        }
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        cliExecutor.locate(codexBinary) != nil
    }

    public func probe() async throws -> UsageSnapshot {
        logger.info("Starting Codex probe...")

        // Try RPC first, fall back to TTY
        do {
            let snapshot = try await probeViaRPC()
            logger.info("Codex RPC probe success: \(snapshot.quotas.count) quotas found")
            for quota in snapshot.quotas {
                logger.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
            }
            return snapshot
        } catch {
            logger.warning("Codex RPC failed: \(error.localizedDescription), trying TTY fallback...")
            let snapshot = try await probeViaTTY()
            logger.info("Codex TTY probe success: \(snapshot.quotas.count) quotas found")
            return snapshot
        }
    }

    // MARK: - RPC Approach

    private func probeViaRPC() async throws -> UsageSnapshot {
        let rpc = try rpcClientFactory(codexBinary, timeout)
        defer { rpc.shutdown() }

        try await rpc.initialize()
        let limits = try await rpc.fetchRateLimits()

        return try Self.mapRateLimitsToSnapshot(limits)
    }

    /// Maps RPC rate limits response to a UsageSnapshot (internal for testing).
    internal static func mapRateLimitsToSnapshot(_ limits: CodexRateLimitsResponse) throws -> UsageSnapshot {
        var quotas: [UsageQuota] = []

        if let primary = limits.primary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - primary.usedPercent),
                quotaType: .session,
                providerId: "codex",
                resetText: primary.resetDescription
            ))
        }

        if let secondary = limits.secondary {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - secondary.usedPercent),
                quotaType: .weekly,
                providerId: "codex",
                resetText: secondary.resetDescription
            ))
        }

        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No rate limits found")
        }

        return UsageSnapshot(
            providerId: "codex",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - TTY Fallback

    private func probeViaTTY() async throws -> UsageSnapshot {
        logger.info("Starting Codex TTY fallback...")

        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: codexBinary,
                args: ["-s", "read-only", "-a", "untrusted"],
                input: "/status\n",
                timeout: timeout,
                workingDirectory: nil,
                sendOnSubstrings: [:]
            )
        } catch {
            logger.error("Codex TTY failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        logger.debug("Codex TTY raw output:\n\(result.output)")

        let snapshot = try Self.parse(result.output)
        logger.info("Codex TTY success: \(snapshot.quotas.count) quotas")
        return snapshot
    }

    // MARK: - Parsing (for TTY fallback)

    public static func parse(_ text: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)

        if let error = extractUsageError(clean) {
            throw error
        }

        let fiveHourPct = extractPercent(labelSubstring: "5h limit", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Weekly limit", text: clean)

        var quotas: [UsageQuota] = []

        if let fiveHourPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(fiveHourPct),
                quotaType: .session,
                providerId: "codex"
            ))
        }

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                providerId: "codex"
            ))
        }

        if quotas.isEmpty {
            throw ProbeError.parseFailed("Could not find usage limits in Codex output")
        }

        return UsageSnapshot(
            providerId: "codex",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Text Parsing Helpers

    internal static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func extractPercent(labelSubstring: String, text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(12)
            for candidate in window {
                if let pct = percentFromLine(candidate) {
                    return pct
                }
            }
        }
        return nil
    }

    private static func percentFromLine(_ line: String) -> Int? {
        let pattern = #"([0-9]{1,3})%\s+left"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let valRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Int(line[valRange])
    }

    internal static func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if lower.contains("data not available yet") {
            return .parseFailed("Data not available yet")
        }

        if lower.contains("update available") && lower.contains("codex") {
            return .updateRequired
        }

        return nil
    }
}

