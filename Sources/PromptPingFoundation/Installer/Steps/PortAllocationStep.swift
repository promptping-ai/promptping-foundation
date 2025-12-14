import Foundation
import Logging

/// Step 2: Allocate port for the daemon
///
/// Checks if the default port is available, or finds a free port
/// in the configured range if the default is in use.
public struct PortAllocationStep: InstallStep {
  public let name = "Port Allocation"

  public init() {}

  public func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError) {
    let port: Int

    if let portConfig = config.portConfig {
      port = try await allocatePort(portConfig, context: context)
      context.logger.info("Allocated port: \(port)")
    } else {
      port = config.portConfig?.defaultPort ?? 50052
      context.logger.info("Using default port: \(port)")
    }

    result.port = port
  }

  private func allocatePort(
    _ portConfig: PortConfig,
    context: InstallContext
  ) async throws(InstallerError) -> Int {
    let defaultInUse = await context.portManager.isPortInUse(portConfig.defaultPort)

    if !defaultInUse {
      return portConfig.defaultPort
    }

    if let range = portConfig.portRange {
      do {
        return try await context.portManager.findFreePort(
          in: range, excluding: portConfig.excludedPorts)
      } catch {
        throw .portAllocationFailed("No free port in range \(range)")
      }
    }

    throw .portAllocationFailed("Default port \(portConfig.defaultPort) is in use")
  }
}
