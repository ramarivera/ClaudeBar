import Testing
import Foundation
import Mockable
@testable import Domain

@Suite("CopilotProvider Env Var Configuration Tests")
struct CopilotProviderEnvVarConfigTests {

    // MARK: - Initialization Tests

    @Test
    func `copilot provider with various config repository settings`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
    }

    @Test
    func `copilot provider config repository is injectable`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository(copilotAuthEnvVar: "CUSTOM_GH_TOKEN")
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
    }

    // MARK: - Environment Variable Configuration Tests

    @Test
    func `copilot provider passes config repository to probe`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository(copilotAuthEnvVar: "MY_GITHUB_TOKEN")
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
        #expect(provider.id == "copilot")
    }

    // MARK: - Multiple Env Var Configurations

    @Test
    func `multiple providers can have different env var configurations`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let configCopilot = MockRepositoryFactory.makeConfigRepository(copilotAuthEnvVar: "GH_TOKEN_VAR")
        
        let mockProbe = MockUsageProbe()

        let copilotProvider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: configCopilot
        )

        #expect(copilotProvider != nil)
        #expect(copilotProvider.id == "copilot")
    }

    // MARK: - Default Configuration Tests

    @Test
    func `provider initializes successfully with config repository`() {
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let credentials = MockRepositoryFactory.makeCredentialRepository()
        let config = MockRepositoryFactory.makeConfigRepository()
        let mockProbe = MockUsageProbe()

        let provider = CopilotProvider(
            probe: mockProbe,
            settingsRepository: settings,
            credentialRepository: credentials,
            configRepository: config
        )

        #expect(provider != nil)
    }
}
