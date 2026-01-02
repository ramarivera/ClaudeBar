# ClaudeBar Design Guide

> **Architecture documentation:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Overview

ClaudeBar is a macOS 15+ menu bar application for monitoring AI coding assistant usage quotas (Claude, Codex, Gemini, GitHub Copilot, Antigravity, Z.ai). Built with TDD, rich domain models, and clean architecture.

## Design Principles

### 1. Rich Domain Models

Domain models contain business logic, not just data:

```swift
public struct UsageQuota {
    public let percentRemaining: Double
    public let quotaType: QuotaType

    // Business logic in the model
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining)
    }

    public var isDepleted: Bool { percentRemaining <= 0 }
    public var needsAttention: Bool { status.needsAttention }
}
```

### 2. Domain-Driven Terminology

Use domain language, not technical terms:

| Domain Term | Technical Term |
|-------------|----------------|
| `UsageQuota` | `UsageData` |
| `QuotaStatus` | `HealthStatus` |
| `AIProvider` | `ServiceProvider` |
| `UsageSnapshot` | `UsageDataResponse` |
| `QuotaMonitor` | `UsageDataFetcher` |

### 3. No ViewModel Layer

UI directly uses rich domain models:

```swift
struct QuotaCardView: View {
    let quota: UsageQuota  // Domain model directly

    var body: some View {
        Text("\(Int(quota.percentRemaining))%")
            .foregroundStyle(quota.status.displayColor)  // Rich model
    }
}
```

### 4. Repository Pattern

Settings and credentials abstracted behind injectable protocols:

```swift
// Domain defines protocol
@Mockable
public protocol ProviderSettingsRepository: Sendable {
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool
    func setEnabled(_ enabled: Bool, forProvider id: String)
}

// Providers receive via injection
public init(probe: any UsageProbe, settingsRepository: any ProviderSettingsRepository) {
    self.settingsRepository = settingsRepository
    self.isEnabled = settingsRepository.isEnabled(forProvider: id)
}
```

### 5. Chicago School TDD

Tests focus on state changes and return values, not method call verification:

```swift
@Test
func `quota with more than 50 percent remaining is healthy`() {
    let quota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")
    #expect(quota.status == .healthy)  // Test state, not interactions
}
```

## Status Thresholds

Business rules encoded in domain:

| Percentage Remaining | Status |
|---------------------|--------|
| > 50% | `.healthy` |
| 20-50% | `.warning` |
| < 20% | `.critical` |
| 0% | `.depleted` |

## Dependencies

- **Mockable**: Protocol mocking for tests
- **Sparkle**: Auto-update functionality
- **Swift Testing**: Modern test framework

## Features

- **Multi-provider support** - Claude, Codex, Gemini, Copilot, Antigravity, Z.ai probes
- **Auto-refresh** - Configurable refresh intervals with AsyncStream
- **System notifications** - Alerts on status degradation
- **Enable/disable providers** - Toggle providers on/off in Settings
- **Provider selection** - View individual provider quotas
- **Theme support** - Light, dark, and seasonal themes
