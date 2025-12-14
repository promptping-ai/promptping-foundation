import Foundation
import Logging

/// Step 5: Generate and install plist
///
/// Generates the launchd plist file from the service configuration
/// and writes it to the LaunchAgents directory.
public struct InstallPlistStep: InstallStep {
  public let name = "Install Plist"

  public init() {}

  public func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError) {
    guard var serviceConfig = config.serviceConfig else {
      context.logger.debug("No service config provided, skipping plist installation")
      return
    }

    // Update port in arguments if we have a port
    if let port = result.port {
      serviceConfig.arguments = updatePortArguments(
        serviceConfig.arguments, port: port, context: context)
    }

    let launchAgentsDir = PathResolver.StandardPath.launchAgents.url
    let plistURL = launchAgentsDir.appendingPathComponent("\(serviceConfig.label).plist")

    context.logger.info("Installing plist to: \(plistURL.path)")

    do {
      try await context.launchAgentManager.installPlist(config: serviceConfig, to: plistURL)
    } catch {
      throw .configurationMissing("Failed to install plist: \(error)")
    }

    result.plistPath = plistURL
    result.serviceInstalled = true
    context.logger.info("Installed plist for service: \(serviceConfig.label)")
  }

  private func updatePortArguments(_ arguments: [String], port: Int, context: InstallContext)
    -> [String]
  {
    var result = arguments

    if let portIndex = result.firstIndex(of: "--port") {
      if portIndex + 1 < result.count {
        result[portIndex + 1] = String(port)
      } else {
        // --port exists but no value follows - append the port value
        result.append(String(port))
        context.logger.warning("Found --port flag without value, appending port \(port)")
      }
    } else {
      // No --port flag found - add it with the value
      result.append(contentsOf: ["--port", String(port)])
      context.logger.info("Added --port \(port) to service arguments")
    }

    return result
  }
}
