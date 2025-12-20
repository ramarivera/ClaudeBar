import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct GeminiUsageProbeParsingTests {

    // MARK: - Sample API Responses

    static let sampleAPIResponse = """
    {
        "buckets": [
            {
                "modelId": "gemini-2.0-flash-exp",
                "remainingFraction": 0.65,
                "resetTime": "2025-01-15T15:30:00Z",
                "tokenType": "input"
            },
            {
                "modelId": "gemini-2.0-flash-exp",
                "remainingFraction": 0.80,
                "resetTime": "2025-01-15T15:30:00Z",
                "tokenType": "output"
            },
            {
                "modelId": "gemini-exp-1206",
                "remainingFraction": 0.35,
                "resetTime": "2025-01-15T15:30:00Z",
                "tokenType": "input"
            }
        ]
    }
    """

    static let exhaustedQuotaResponse = """
    {
        "buckets": [
            {
                "modelId": "gemini-2.0-flash-exp",
                "remainingFraction": 0.0,
                "resetTime": "2025-01-15T15:30:00Z",
                "tokenType": "input"
            }
        ]
    }
    """

    static let emptyBucketsResponse = """
    {
        "buckets": []
    }
    """

    // MARK: - Parsing API Responses

    @Test
    func `parses model quota from api response`() throws {
        // Given
        let data = Data(Self.sampleAPIResponse.utf8)

        // When
        let snapshot = try GeminiUsageProbe.parseAPIResponse(data)

        // Then
        #expect(snapshot.quotas.count >= 1)
        #expect(snapshot.provider == .gemini)
    }

    @Test
    func `takes lowest quota per model from input and output buckets`() throws {
        // Given - gemini-2.0-flash-exp has 65% input, 80% output
        let data = Data(Self.sampleAPIResponse.utf8)

        // When
        let snapshot = try GeminiUsageProbe.parseAPIResponse(data)

        // Then - Should use 65% (the lower one)
        let flashQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("gemini-2.0-flash-exp") }
        #expect(flashQuota?.percentRemaining == 65)
    }

    @Test
    func `detects depleted quota at zero percent`() throws {
        // Given
        let data = Data(Self.exhaustedQuotaResponse.utf8)

        // When
        let snapshot = try GeminiUsageProbe.parseAPIResponse(data)

        // Then
        let quota = snapshot.quotas.first
        #expect(quota?.percentRemaining == 0)
        #expect(quota?.status == .depleted)
    }

    @Test
    func `throws error for empty buckets`() throws {
        // Given
        let data = Data(Self.emptyBucketsResponse.utf8)

        // When & Then
        #expect(throws: ProbeError.self) {
            try GeminiUsageProbe.parseAPIResponse(data)
        }
    }

    // MARK: - Legacy CLI Parsing

    static let sampleCLIOutput = """
    Gemini CLI v1.0.0

    Model Usage:
    │ gemini-2.0-flash-exp     │ 65.0% (resets in 2h 15m) │
    │ gemini-exp-1206          │ 35.0% (resets in 2h 15m) │

    Account: user@example.com
    """

    @Test
    func `parses model quota from cli output`() throws {
        // Given
        let output = Self.sampleCLIOutput

        // When
        let snapshot = try GeminiUsageProbe.parseCLIOutput(output)

        // Then
        #expect(snapshot.quotas.count >= 1)
        #expect(snapshot.provider == .gemini)
    }

    // MARK: - Error Detection

    static let notLoggedInOutput = """
    Login with Google to continue
    Use Gemini API key
    """

    @Test
    func `detects not logged in error`() throws {
        // Given
        let output = Self.notLoggedInOutput

        // When & Then
        #expect(throws: ProbeError.self) {
            try GeminiUsageProbe.parseCLIOutput(output)
        }
    }
}
