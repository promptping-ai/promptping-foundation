import Foundation
import Logging

/// Step 6: Bootstrap the service
///
/// Loads the launchd service from the installed plist file.
/// This is the final step that starts the daemon.
public struct BootstrapServiceStep: InstallStep {
  public let name = "Bootstrap Service"

  public init() {}

  public func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError) {
    guard let serviceConfig = config.serviceConfig else {
      context.logger.debug("No service config provided, skipping bootstrap")
      return
    }

    guard let plistPath = result.plistPath else {
      context.logger.warning("No plist path in result, skipping bootstrap")
      return
    }

    context.logger.info("Bootstrapping service: \(serviceConfig.label)")

    do {
      try await context.launchAgentManager.bootstrap(plistPath)
    } catch {
      throw .serviceNotLoaded("Failed to bootstrap \(serviceConfig.label): \(error)")
    }

    context.logger.info("Service bootstrapped: \(serviceConfig.label)")
  }
}
