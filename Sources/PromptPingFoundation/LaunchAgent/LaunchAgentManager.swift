import Foundation
import Logging

/// Manages macOS launchd services (LaunchAgents) using launchctl
///
/// This actor provides a Swift-native interface for managing launchd services,
/// including loading, unloading, starting, stopping, and monitoring services.
///
/// ## Example Usage
///
/// ```swift
/// let runner = SubprocessRunner()
/// let manager = LaunchAgentManager(subprocessRunner: runner)
///
/// // Check if service is loaded
/// let isLoaded = await manager.isServiceLoaded("com.myapp.daemon")
///
/// // Get detailed status
/// let status = await manager.getServiceStatus("com.myapp.daemon")
///
/// // Install and bootstrap a new service
/// let config = ServiceConfig(
///     label: "com.myapp.daemon",
///     executable: "/usr/local/bin/myapp-daemon",
///     arguments: ["--port", "8080"],
///     keepAlive: true
/// )
/// let plistURL = URL(fileURLWithPath: "~/Library/LaunchAgents/com.myapp.daemon.plist")
/// try await manager.installPlist(config: config, to: plistURL)
/// try await manager.bootstrap(plistURL)
/// ```
public actor LaunchAgentManager {
  private let subprocessRunner: SubprocessRunner
  private let logger: Logger
  private let fileManager: FileManager

  /// Creates a new launch agent manager
  public init(
    subprocessRunner: SubprocessRunner,
    logger: Logger = Logger(label: "promptping.launchagent"),
    fileManager: FileManager = .default
  ) {
    self.subprocessRunner = subprocessRunner
    self.logger = logger
    self.fileManager = fileManager
  }

  // MARK: - Service Domain

  private func domainPath() throws(LaunchAgentError) -> String {
    let uid = getuid()
    guard uid != UInt32.max else {
      throw .userIdUnavailable
    }
    return "gui/\(uid)"
  }

  private func serviceTarget(_ label: String) throws(LaunchAgentError) -> String {
    "\(try domainPath())/\(label)"
  }

  // MARK: - Status Queries

  /// Checks if a service is loaded in launchd
  public func isServiceLoaded(_ label: String) async -> Bool {
    do {
      let target = try serviceTarget(label)
      let result = try await subprocessRunner.run(.launchctl, arguments: ["print", target])
      return result.succeeded
    } catch {
      logger.debug("Failed to check service status: \(error)")
      return false
    }
  }

  /// Gets the detailed status of a service
  public func getServiceStatus(_ label: String) async -> ServiceStatus {
    do {
      let target = try serviceTarget(label)
      let result = try await subprocessRunner.run(.launchctl, arguments: ["print", target])

      guard result.succeeded else {
        return .notLoaded
      }

      let output = result.output
      if let pidMatch = output.range(of: #"pid\s*=\s*(\d+)"#, options: .regularExpression),
        let numberMatch = output[pidMatch].range(of: #"\d+"#, options: .regularExpression),
        let pid = Int32(output[pidMatch][numberMatch])
      {
        return .running(pid: pid)
      }

      if output.contains("pid = (null)") || output.contains("state = waiting") {
        return .loaded
      }

      return .loaded
    } catch {
      logger.debug("Failed to get service status: \(error)")
      return .unknown
    }
  }

  // MARK: - Service Lifecycle

  /// Bootstraps (loads) a service from a plist file
  public func bootstrap(_ plistPath: URL) async throws(LaunchAgentError) {
    let path = plistPath.path
    guard fileManager.fileExists(atPath: path) else {
      throw .plistNotFound(path: path)
    }

    if let label = extractLabel(from: plistPath), await isServiceLoaded(label) {
      logger.info("Service \(label) already loaded, unloading first")
      try? await bootout(label)
      try? await Task.sleep(for: .milliseconds(500))
    }

    let domain = try domainPath()
    logger.info("Bootstrapping service from \(path)")

    do {
      let result = try await subprocessRunner.run(
        .launchctl,
        arguments: ["bootstrap", domain, path]
      )

      guard result.succeeded else {
        struct BootstrapCommandError: Error, Sendable {
          let message: String
        }
        throw LaunchAgentError.bootstrapFailed(
          label: path,
          underlying: BootstrapCommandError(
            message: result.error.isEmpty ? "Exit code \(result.exitCode)" : result.error
          )
        )
      }
    } catch let error as LaunchAgentError {
      throw error
    } catch {
      throw .bootstrapFailed(label: path, underlying: error)
    }

    logger.info("Successfully bootstrapped service from \(path)")
  }

  /// Bootout (unloads) a service from launchd
  public func bootout(_ label: String) async throws(LaunchAgentError) {
    let target = try serviceTarget(label)
    logger.info("Booting out service \(label)")

    do {
      let result = try await subprocessRunner.run(
        .launchctl,
        arguments: ["bootout", target]
      )

      // Exit code 3 means "service not found" which is acceptable for bootout
      guard result.succeeded || result.exitCode == 3 else {
        struct BootoutCommandError: Error, Sendable {
          let message: String
        }
        throw LaunchAgentError.bootoutFailed(
          label: label,
          underlying: BootoutCommandError(
            message: result.error.isEmpty ? "Exit code \(result.exitCode)" : result.error
          )
        )
      }
    } catch let error as LaunchAgentError {
      throw error
    } catch {
      throw .bootoutFailed(label: label, underlying: error)
    }

    logger.info("Successfully booted out service \(label)")
  }

  /// Kickstarts a service, starting it immediately
  public func kickstart(_ label: String) async throws(LaunchAgentError) {
    let target = try serviceTarget(label)
    logger.info("Kickstarting service \(label)")

    do {
      let result = try await subprocessRunner.run(
        .launchctl,
        arguments: ["kickstart", target]
      )

      guard result.succeeded else {
        struct KickstartCommandError: Error, Sendable {
          let message: String
        }
        throw LaunchAgentError.kickstartFailed(
          label: label,
          underlying: KickstartCommandError(
            message: result.error.isEmpty ? "Exit code \(result.exitCode)" : result.error
          )
        )
      }
    } catch let error as LaunchAgentError {
      throw error
    } catch {
      throw .kickstartFailed(label: label, underlying: error)
    }

    logger.info("Successfully kickstarted service \(label)")
  }

  /// Sends a signal to a running service
  public func kill(_ label: String, signal: String = "SIGTERM") async throws(LaunchAgentError) {
    let target = try serviceTarget(label)
    logger.info("Sending \(signal) to service \(label)")

    do {
      let result = try await subprocessRunner.run(
        .launchctl,
      arguments: ["kill", signal, target]
    )

    guard result.succeeded else {
      struct KillCommandError: Error, Sendable {
        let message: String
      }
      throw LaunchAgentError.killFailed(
        label: label,
        signal: signal,
        underlying: KillCommandError(
          message: result.error.isEmpty ? "Exit code \(result.exitCode)" : result.error
        )
      )
    }
  } catch let error as LaunchAgentError {
    throw error
  } catch {
    throw .killFailed(label: label, signal: signal, underlying: error)
  }

  logger.info("Successfully sent \(signal) to service \(label)")
}

  // MARK: - Plist Management

  /// Installs a plist file from a service configuration
  public func installPlist(
    config: ServiceConfig,
    to destination: URL
  ) async throws(LaunchAgentError) {
    let plistContent = config.generatePlist()
    let path = destination.path

    logger.info("Installing plist for \(config.label) to \(path)")

    let parentDir = destination.deletingLastPathComponent().path
    if !fileManager.fileExists(atPath: parentDir) {
      do {
        try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
      } catch {
        throw .plistWriteFailed(
          path: path,
          underlying: error
        )
      }
    }

    do {
      try plistContent.write(to: destination, atomically: true, encoding: .utf8)
    } catch {
      throw .plistWriteFailed(path: path, underlying: error)
    }

    logger.info("Successfully installed plist for \(config.label)")
  }

  // MARK: - Helpers

  private func extractLabel(from plistURL: URL) -> String? {
    guard let data = try? Data(contentsOf: plistURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let label = plist["Label"] as? String
    else {
      return nil
    }
    return label
  }
}
