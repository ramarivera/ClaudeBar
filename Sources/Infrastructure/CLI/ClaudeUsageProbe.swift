import Foundation
import Domain
import os.log

private let logger = Logger(subsystem: "com.claudebar", category: "ClaudeProbe")

/// Infrastructure adapter that probes the Claude CLI to fetch usage quotas.
/// Implements the UsageProbe protocol from the domain layer.
public struct ClaudeUsageProbe: UsageProbe {
    private let claudeBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        claudeBinary: String = "claude",
        timeout: TimeInterval = 20.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.claudeBinary = claudeBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        cliExecutor.locate(claudeBinary) != nil
    }

    public func probe() async throws -> UsageSnapshot {
        logger.info("Starting Claude probe...")

        // Step 1: Run /status to detect account type
        let statusResult: CLIResult
        do {
            statusResult = try cliExecutor.execute(
                binary: claudeBinary,
                args: ["/status", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: probeWorkingDirectory(),
                sendOnSubstrings: [
                    "Do you trust the files in this folder?": "y\r",
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                ]
            )
        } catch {
            logger.error("Claude /status probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        logger.debug("Claude /status output:\n\(statusResult.output)")

        let cleanStatus = stripANSICodes(statusResult.output)
        let accountType = detectAccountType(cleanStatus)

        // Step 2: Run appropriate command based on account type
        if accountType == .api {
            logger.info("Detected API account, running /cost command...")
            return try await probeApiCost(statusOutput: cleanStatus)
        }

        // Step 3: For Max accounts, run /usage command
        logger.info("Detected Max account, running /usage command...")
        return try await probeMaxUsage(statusOutput: cleanStatus)
    }

    /// Probes usage information for Max accounts using /usage command
    private func probeMaxUsage(statusOutput: String) async throws -> UsageSnapshot {
        let usageResult: CLIResult
        do {
            usageResult = try cliExecutor.execute(
                binary: claudeBinary,
                args: ["/usage", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: probeWorkingDirectory(),
                sendOnSubstrings: [
                    "Do you trust the files in this folder?": "y\r",
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                ]
            )
        } catch {
            logger.error("Claude /usage probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        logger.debug("Claude /usage output:\n\(usageResult.output)")

        let snapshot = try parseClaudeOutput(usageResult.output, statusOutput: statusOutput)
        logger.info("Claude probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            logger.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    /// Probes cost information for API accounts using /cost command
    private func probeApiCost(statusOutput: String) async throws -> UsageSnapshot {
        let costResult: CLIResult
        do {
            costResult = try cliExecutor.execute(
                binary: claudeBinary,
                args: ["/cost", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: probeWorkingDirectory(),
                sendOnSubstrings: [
                    "Do you trust the files in this folder?": "y\r",
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                ]
            )
        } catch {
            logger.error("Claude /cost probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        logger.debug("Claude /cost raw output:\n\(costResult.output)")

        let snapshot = try parseCostOutput(costResult.output, statusOutput: statusOutput)
        logger.info("Claude API probe success: cost=\(snapshot.costUsage?.formattedCost ?? "N/A")")

        return snapshot
    }

    // MARK: - Parsing

    /// Parses Claude CLI output into a UsageSnapshot (for testing)
    public static func parse(_ text: String) throws -> UsageSnapshot {
        try ClaudeUsageProbe().parseClaudeOutput(text, statusOutput: text)
    }

    private func parseClaudeOutput(_ text: String, statusOutput: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(text)
        let cleanStatus = stripANSICodes(statusOutput)

        // Check for errors first
        if let error = extractUsageError(clean) {
            throw error
        }

        // Extract percentages
        let sessionPct = extractPercent(labelSubstring: "Current session", text: clean)
        let weeklyPct = extractPercent(labelSubstring: "Current week (all models)", text: clean)
        let opusPct = extractPercent(labelSubstrings: [
            "Current week (Opus)",
            "Current week (Sonnet only)",
            "Current week (Sonnet)",
        ], text: clean)

        guard let sessionPct else {
            throw ProbeError.parseFailed("Could not find session usage")
        }

        // Extract reset times
        let sessionReset = extractReset(labelSubstring: "Current session", text: clean)
        let weeklyReset = extractReset(labelSubstring: "Current week", text: clean)

        // Extract account info from /status output
        let email = extractEmail(text: cleanStatus)
        let org = extractOrganization(text: cleanStatus)
        let loginMethod = extractLoginMethod(text: cleanStatus)

        // Build quotas
        var quotas: [UsageQuota] = []

        quotas.append(UsageQuota(
            percentRemaining: Double(sessionPct),
            quotaType: .session,
            providerId: "claude",
            resetsAt: parseResetDate(sessionReset),
            resetText: cleanResetText(sessionReset)
        ))

        if let weeklyPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(weeklyPct),
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        if let opusPct {
            quotas.append(UsageQuota(
                percentRemaining: Double(opusPct),
                quotaType: .modelSpecific("opus"),
                providerId: "claude",
                resetsAt: parseResetDate(weeklyReset),
                resetText: cleanResetText(weeklyReset)
            ))
        }

        return UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: email,
            accountOrganization: org,
            loginMethod: loginMethod,
            accountType: .max,
            costUsage: nil
        )
    }

    // MARK: - Account Type Detection

    /// Detects whether the account is a Max subscription or API account
    /// based on the /usage command output.
    internal func detectAccountType(_ text: String) -> ClaudeAccountType {
        let lower = text.lowercased()
        logger.debug("Detecting account type from output...")

        // Check for explicit API Account indicator (exact match from CLI)
        if lower.contains("login method: claude api account") ||
           lower.contains("claude api account") {
            logger.info("Detected Claude API Account from login method")
            return .api
        }

        // Check for explicit Max Account indicator (exact match from CLI)
        if lower.contains("login method: claude max account") ||
           lower.contains("claude max account") {
            logger.info("Detected Claude Max Account from login method")
            return .max
        }

        // Legacy checks for older CLI versions
        if lower.contains("login method: api") ||
           lower.contains("login method:api") {
            logger.info("Detected API account from legacy login method")
            return .api
        }

        if lower.contains("login method: claude max") ||
           lower.contains("login method:claude max") ||
           lower.contains("max subscription") {
            logger.info("Detected Max account from legacy login method")
            return .max
        }

        // Check for presence of quota data (Max accounts have quotas)
        let hasSessionQuota = lower.contains("current session") && (lower.contains("% left") || lower.contains("% used"))

        if hasSessionQuota {
            logger.info("Detected Max account from quota data presence")
            return .max
        }

        // Check for API-specific messages
        if lower.contains("no usage quotas") ||
           lower.contains("use /cost to see") ||
           lower.contains("api account") {
            logger.info("Detected API account from API-specific messages")
            return .api
        }

        // Default to Max if we can't determine
        logger.warning("Could not determine account type, defaulting to Max")
        return .max
    }

    // MARK: - Cost Parsing

    /// Parses /cost command output into a UsageSnapshot with CostUsage
    internal func parseCostOutput(_ costText: String, statusOutput: String) throws -> UsageSnapshot {
        let clean = stripANSICodes(costText)
        let cleanStatus = stripANSICodes(statusOutput)

        // Extract cost data
        guard let totalCost = extractTotalCost(clean) else {
            throw ProbeError.parseFailed("Could not find total cost in /cost output")
        }

        let apiDuration = extractApiDuration(clean) ?? 0
        let wallDuration = extractWallDuration(clean) ?? 0
        let (linesAdded, linesRemoved) = extractCodeChanges(clean)

        // Extract account info from /status output
        let email = extractEmail(text: cleanStatus)
        let org = extractOrganization(text: cleanStatus)
        let loginMethod = extractLoginMethod(text: cleanStatus)

        let costUsage = CostUsage(
            totalCost: totalCost,
            apiDuration: apiDuration,
            wallDuration: wallDuration,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            providerId: "claude",
            capturedAt: Date()
        )

        return UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            accountEmail: email,
            accountOrganization: org,
            loginMethod: loginMethod,
            accountType: .api,
            costUsage: costUsage
        )
    }

    /// Parses /cost command output for testing
    public static func parseCost(_ costText: String, statusOutput: String = "") throws -> UsageSnapshot {
        try ClaudeUsageProbe().parseCostOutput(costText, statusOutput: statusOutput)
    }

    /// Extracts total cost from /cost output (e.g., "Total cost: $0.55")
    internal func extractTotalCost(_ text: String) -> Decimal? {
        // Pattern: "Total cost: $0.55" or "Total cost: 0.55"
        let pattern = #"(?i)total\s+cost:\s*\$?([\d,]+\.?\d*)"#
        guard let match = extractFirst(pattern: pattern, text: text) else {
            return nil
        }

        // Remove commas and parse
        let cleaned = match.replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    /// Extracts API duration from /cost output (e.g., "Total duration (API): 6m 19.7s")
    internal func extractApiDuration(_ text: String) -> TimeInterval? {
        let pattern = #"(?i)total\s+duration\s*\(api\):\s*(.+)"#
        guard let match = extractFirst(pattern: pattern, text: text) else {
            return nil
        }
        return parseDurationString(match)
    }

    /// Extracts wall duration from /cost output (e.g., "Total duration (wall): 6h 33m 10.2s")
    internal func extractWallDuration(_ text: String) -> TimeInterval? {
        let pattern = #"(?i)total\s+duration\s*\(wall\):\s*(.+)"#
        guard let match = extractFirst(pattern: pattern, text: text) else {
            return nil
        }
        return parseDurationString(match)
    }

    /// Extracts code changes from /cost output (e.g., "Total code changes: 0 lines added, 0 lines removed")
    internal func extractCodeChanges(_ text: String) -> (added: Int, removed: Int) {
        let pattern = #"(?i)total\s+code\s+changes:\s*(\d+)\s*lines?\s+added[,\s]+(\d+)\s*lines?\s+removed"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (0, 0)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let addedRange = Range(match.range(at: 1), in: text),
              let removedRange = Range(match.range(at: 2), in: text) else {
            return (0, 0)
        }

        let added = Int(text[addedRange]) ?? 0
        let removed = Int(text[removedRange]) ?? 0
        return (added, removed)
    }

    /// Parses duration strings like "6m 19.7s" or "6h 33m 10.2s"
    internal func parseDurationString(_ text: String) -> TimeInterval {
        var totalSeconds: TimeInterval = 0

        // Extract hours
        if let hourMatch = text.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            let hourStr = String(text[hourMatch])
            if let hours = Double(hourStr.filter { $0.isNumber }) {
                totalSeconds += hours * 3600
            }
        }

        // Extract minutes
        if let minMatch = text.range(of: #"(\d+)\s*m(?!s)"#, options: .regularExpression) {
            let minStr = String(text[minMatch])
            if let minutes = Double(minStr.filter { $0.isNumber }) {
                totalSeconds += minutes * 60
            }
        }

        // Extract seconds (including decimals)
        let secPattern = #"([\d.]+)\s*s"#
        if let regex = try? NSRegularExpression(pattern: secPattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
           match.numberOfRanges >= 2,
           let secRange = Range(match.range(at: 1), in: text),
           let seconds = Double(text[secRange]) {
            totalSeconds += seconds
        }

        return totalSeconds
    }

    // MARK: - Text Parsing Helpers

    internal func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    internal func extractPercent(labelSubstring: String, text: String) -> Int? {
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

    internal func extractPercent(labelSubstrings: [String], text: String) -> Int? {
        for label in labelSubstrings {
            if let value = extractPercent(labelSubstring: label, text: text) {
                return value
            }
        }
        return nil
    }

    internal func percentFromLine(_ line: String) -> Int? {
        let pattern = #"([0-9]{1,3})\s*%\s*(used|left)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let valRange = Range(match.range(at: 1), in: line),
              let kindRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        let rawVal = Int(line[valRange]) ?? 0
        let isUsed = line[kindRange].lowercased().contains("used")
        return isUsed ? max(0, 100 - rawVal) : rawVal
    }

    internal func extractReset(labelSubstring: String, text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let label = labelSubstring.lowercased()

        for (idx, line) in lines.enumerated() where line.lowercased().contains(label) {
            let window = lines.dropFirst(idx).prefix(14)
            for candidate in window {
                let lower = candidate.lowercased()
                // Look for "resets" or time indicators like "2h" or "30m"
                if lower.contains("reset") ||
                   (lower.contains("in") && (lower.contains("h") || lower.contains("m"))) {
                    return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    internal func extractEmail(text: String) -> String? {
        let pattern = #"(?i)(?:Account|Email):\s*([^\s@]+@[^\s@]+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    internal func extractOrganization(text: String) -> String? {
        let pattern = #"(?i)(?:Org|Organization):\s*(.+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    internal func extractLoginMethod(text: String) -> String? {
        let pattern = #"(?i)login\s+method:\s*(.+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    internal func extractFirst(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal func cleanResetText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If it doesn't start with "Resets", add it
        if trimmed.lowercased().hasPrefix("reset") {
            return trimmed
        }
        return "Resets \(trimmed)"
    }

    internal func parseResetDate(_ text: String?) -> Date? {
        guard let text else { return nil }

        var totalSeconds: TimeInterval = 0

        // Extract days: "2d" or "2 d" or "2 days"
        if let dayMatch = text.range(of: #"(\d+)\s*d(?:ays?)?"#, options: .regularExpression) {
            let dayStr = String(text[dayMatch])
            if let days = Int(dayStr.filter { $0.isNumber }) {
                totalSeconds += Double(days) * 24 * 3600
            }
        }

        // Extract hours: "2h" or "2 h" or "2 hours"
        if let hourMatch = text.range(of: #"(\d+)\s*h(?:ours?|r)?"#, options: .regularExpression) {
            let hourStr = String(text[hourMatch])
            if let hours = Int(hourStr.filter { $0.isNumber }) {
                totalSeconds += Double(hours) * 3600
            }
        }

        // Extract minutes: "15m" or "15 m" or "15 min" or "15 minutes"
        if let minMatch = text.range(of: #"(\d+)\s*m(?:in(?:utes?)?)?"#, options: .regularExpression) {
            let minStr = String(text[minMatch])
            if let minutes = Int(minStr.filter { $0.isNumber }) {
                totalSeconds += Double(minutes) * 60
            }
        }

        if totalSeconds > 0 {
            return Date().addingTimeInterval(totalSeconds)
        }

        return nil
    }

    // MARK: - Error Detection

    internal func extractUsageError(_ text: String) -> ProbeError? {
        let lower = text.lowercased()

        if lower.contains("do you trust the files in this folder?"), !lower.contains("current session") {
            return .folderTrustRequired
        }

        if lower.contains("token_expired") || lower.contains("token has expired") {
            return .authenticationRequired
        }

        if lower.contains("authentication_error") {
            return .authenticationRequired
        }

        return nil
    }

    internal func extractFolderFromTrustPrompt(_ text: String) -> String? {
        let pattern = #"Do you trust the files in this folder\?\s*(?:\r?\n)+\s*([^\r\n]+)"#
        return extractFirst(pattern: pattern, text: text)
    }

    // MARK: - Helpers

    internal func probeWorkingDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("ClaudeBar", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
