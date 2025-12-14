import Foundation
import Logging

/// Step 3: Stop existing service if running
///
/// Checks if a service with the same label is already running
/// and stops it before proceeding with installation.
public struct StopExistingServiceStep: InstallStep {
  public let name = "Stop Existing Service"

  public init() {}

  public func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError) {
    guard let serviceConfig = config.serviceConfig else {
      context.logger.debug("No service config provided, skipping stop step")
      return
    }

    let status = await context.launchAgentManager.getServiceStatus(serviceConfig.label)

    guard case .running = status else {
      context.logger.debug("Service \(serviceConfig.label) is not running")
      return
    }

    context.logger.info("Stopping existing service: \(serviceConfig.label)")

    do {
      try await context.launchAgentManager.bootout(serviceConfig.label)
      result.previousServiceStopped = true
      context.logger.info("Stopped existing service: \(serviceConfig.label)")
    } catch {
      throw .serviceNotLoaded("Failed to stop \(serviceConfig.label): \(error)")
    }
  }
}
