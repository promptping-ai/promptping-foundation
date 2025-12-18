import Foundation

/// Factory for creating and detecting PR providers
public struct ProviderFactory: Sendable {
  private let cli = CLIHelper()

  public init() {}

  /// Automatically detect and create the appropriate provider
  /// - Parameter manualType: Optional manual provider type selection
  /// - Returns: The detected or specified provider
  public func createProvider(manualType: ProviderType? = nil) async throws -> any PRProvider {
    // If manually specified, use that
    if let type = manualType {
      let provider = type.createProvider()
      guard await provider.isAvailable() else {
        throw PRProviderError.cliNotFound(type.rawValue)
      }
      return provider
    }

    // Otherwise, try to auto-detect from git remote
    do {
      let remoteURL = try await cli.getGitRemoteURL()
      if let detected = ProviderType.detect(from: remoteURL) {
        let provider = detected.createProvider()
        if await provider.isAvailable() {
          return provider
        }
      }
    } catch {
      // If git remote detection fails, try available CLIs
    }

    // Try each provider in order of likelihood
    for providerType in ProviderType.allCases {
      let provider = providerType.createProvider()
      if await provider.isAvailable() {
        return provider
      }
    }

    // No provider available
    throw PRProviderError.cliNotFound("No PR provider CLI found (gh, glab, or az)")
  }

  /// Get all available providers
  public func availableProviders() async -> [any PRProvider] {
    var providers: [any PRProvider] = []

    for providerType in ProviderType.allCases {
      let provider = providerType.createProvider()
      if await provider.isAvailable() {
        providers.append(provider)
      }
    }

    return providers
  }
}
