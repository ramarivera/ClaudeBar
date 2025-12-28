import Foundation
import Domain
import OSLog

internal struct GeminiAPIProbe {
    private let homeDirectory: String
    private let timeout: TimeInterval
    private let networkClient: any NetworkClient

    private static let quotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let credentialsPath = "/.gemini/oauth_creds.json"

    private let maxRetries: Int

    init(
        homeDirectory: String,
        timeout: TimeInterval,
        networkClient: any NetworkClient,
        maxRetries: Int = 3
    ) {
        self.homeDirectory = homeDirectory
        self.timeout = timeout
        self.networkClient = networkClient
        self.maxRetries = maxRetries
    }

    func probe() async throws -> UsageSnapshot {
        let creds = try loadCredentials()
        Logger.probes.debug("Gemini credentials loaded, expiry: \(String(describing: creds.expiryDate))")

        guard let accessToken = creds.accessToken, !accessToken.isEmpty else {
            Logger.probes.error("Gemini probe failed: no access token in credentials file")
            throw ProbeError.authenticationRequired
        }

        // Discover the Gemini project ID for accurate quota data
        // Uses retry logic to handle cold-start network delays
        let repository = GeminiProjectRepository(networkClient: networkClient, timeout: timeout, maxRetries: maxRetries)
        let projectId = await repository.fetchBestProject(accessToken: accessToken)?.projectId

        if projectId == nil {
            Logger.probes.warning("Gemini: Project discovery failed, proceeding without project ID (quota may be less accurate)")
        } else {
            Logger.probes.debug("Gemini: Using project ID \(projectId ?? "")")
        }

        guard let url = URL(string: Self.quotaEndpoint) else {
            throw ProbeError.executionFailed("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include project ID if discovered for accurate quota
        if let projectId {
            request.httpBody = Data("{\"project\": \"\(projectId)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        Logger.probes.debug("Gemini API response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            Logger.probes.error("Gemini probe failed: authentication required (401)")
            throw ProbeError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            Logger.probes.error("Gemini probe failed: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level (privacy: private)
        if let jsonString = String(data: data, encoding: .utf8) {
            Logger.probes.debug("Gemini API response:\n\(jsonString, privacy: .private)")
        }

        let snapshot = try mapToSnapshot(data)
        Logger.probes.info("Gemini probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            Logger.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    private func mapToSnapshot(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(QuotaResponse.self, from: data)

        guard let buckets = response.buckets, !buckets.isEmpty else {
            Logger.probes.error("Gemini parse failed: no quota buckets in API response")
            throw ProbeError.parseFailed("No quota buckets in response")
        }

        // Group quotas by model, keeping lowest per model
        var modelQuotaMap: [String: (fraction: Double, resetTime: String?)] = [:]

        for bucket in buckets {
            guard let modelId = bucket.modelId, let fraction = bucket.remainingFraction else { continue }

            if let existing = modelQuotaMap[modelId] {
                if fraction < existing.fraction {
                    modelQuotaMap[modelId] = (fraction, bucket.resetTime)
                }
            } else {
                modelQuotaMap[modelId] = (fraction, bucket.resetTime)
            }
        }

        let quotas: [UsageQuota] = modelQuotaMap
            .sorted { $0.key < $1.key }
            .map { modelId, data in
                UsageQuota(
                    percentRemaining: data.fraction * 100,
                    quotaType: .modelSpecific(modelId),
                    providerId: "gemini",
                    resetText: data.resetTime.map { "Resets \($0)" }
                )
            }

        guard !quotas.isEmpty else {
            Logger.probes.error("Gemini parse failed: no valid quotas after processing buckets")
            throw ProbeError.parseFailed("No valid quotas found")
        }

        return UsageSnapshot(
            providerId: "gemini",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Credentials & Models

    private struct OAuthCredentials {
        let accessToken: String?
        let refreshToken: String?
        let expiryDate: Date?
    }

    private func loadCredentials() throws -> OAuthCredentials {
        let credsURL = URL(fileURLWithPath: homeDirectory + Self.credentialsPath)

        guard FileManager.default.fileExists(atPath: credsURL.path) else {
            Logger.probes.error("Gemini probe failed: credentials file not found at \(credsURL.path, privacy: .private)")
            throw ProbeError.authenticationRequired
        }

        let data = try Data(contentsOf: credsURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.probes.error("Gemini probe failed: invalid JSON in credentials file")
            throw ProbeError.parseFailed("Invalid credentials file")
        }

        let accessToken = json["access_token"] as? String
        let refreshToken = json["refresh_token"] as? String

        var expiryDate: Date?
        if let expiryMs = json["expiry_date"] as? Double {
            expiryDate = Date(timeIntervalSince1970: expiryMs / 1000)
        }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiryDate: expiryDate
        )
    }

    private struct QuotaBucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelId: String?
        let tokenType: String?
    }

    private struct QuotaResponse: Decodable {
        let buckets: [QuotaBucket]?
    }
}
