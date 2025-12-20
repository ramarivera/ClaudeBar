import Foundation
import Domain

/// Infrastructure adapter that probes the Codex CLI to fetch usage quotas.
/// Implements the UsageProbePort from the domain layer.
public struct CodexUsageProbe: UsageProbePort {
    public let provider: AIProvider = .codex

    private let codexBinary: String
    private let timeout: TimeInterval

    public init(codexBinary: String = "codex", timeout: TimeInterval = 20.0) {
        self.codexBinary = codexBinary
        self.timeout = timeout
    }

    public func isAvailable() async -> Bool {
        PTYCommandRunner.which(codexBinary) != nil
    }

    public func probe() async throws -> UsageSnapshot {
        let runner = PTYCommandRunner()
        let options = PTYCommandRunner.Options(
            timeout: timeout,
            extraArgs: ["-s", "read-only", "-a", "untrusted"]
        )

        let result: PTYCommandRunner.Result
        do {
            result = try runner.run(binary: codexBinary, send: "/status\n", options: options)
        } catch let error as PTYCommandRunner.RunError {
            throw mapRunError(error)
        }

        return try Self.parse(result.text)
    }

    // MARK: - Parsing

    public static func parse(_ text: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)

        // Check for errors first
        if let error = extractUsageError(clean) {
            throw error
        }

        // Extract percentages from limit lines
        let fiveHourPct = extractPercent(labelSubstring: "5h limit", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Weekly limit", text: clean)

        // Build quotas
        var quotas: [UsageQuota] = []

        if let fiveHourPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(fiveHourPct),
                quotaType: .session,
                provider: .codex
            ))
        }

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                provider: .codex
            ))
        }

        // If we couldn't find any quotas, it's a parse failure
        if quotas.isEmpty {
            throw ProbeError.parseFailed("Could not find usage limits in Codex output")
        }

        return UsageSnapshot(
            provider: .codex,
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Text Parsing Helpers

    private static func stripANSICodes(_ text: String) -> String {
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

    // MARK: - Error Detection

    private static func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if lower.contains("data not available yet") {
            return .parseFailed("Data not available yet")
        }

        if lower.contains("update available") && lower.contains("codex") {
            return .updateRequired("Codex CLI update required")
        }

        return nil
    }

    private func mapRunError(_ error: PTYCommandRunner.RunError) -> ProbeError {
        switch error {
        case .binaryNotFound(let bin):
            .cliNotFound(bin)
        case .timedOut:
            .timeout
        case .launchFailed(let msg):
            .executionFailed(msg)
        }
    }
}
