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
  /// Type alias for subprocess execution - enables testing via closure injection
  public typealias RunCommand =
    @Sendable (
      Executable, [String], String?
    ) async throws(SubprocessError) -> SubprocessResult

  private let subprocessRunner: SubprocessRunner
  private let runCommand: RunCommand
  private let logger: Logger
  private let fileManager: FileManager

  /// Creates a new launch agent manager
  ///
  /// - Parameters:
  ///   - subprocessRunner: The subprocess runner for executing commands
  ///   - logger: Logger instance for diagnostic output
  ///   - fileManager: File manager for plist operations
  ///   - runCommand: Optional closure override for testing subprocess execution
  public init(
    subprocessRunner: SubprocessRunner,
    logger: Logger = Logger(label: "promptping.launchagent"),
    fileManager: FileManager = .default,
    runCommand: RunCommand? = nil
  ) {
    self.subprocessRunner = subprocessRunner
    self.logger = logger
    self.fileManager = fileManager
    if let runCommand {
      self.runCommand = runCommand
    } else {
      // Default: forward to actual SubprocessRunner
      // Note: Explicit closure typing required for Swift 6 typed throws
      self.runCommand = {
        @Sendable (executable: Executable, args: [String], workDir: String?)
          async throws(SubprocessError) -> SubprocessResult in
        try await subprocessRunner.run(executable, arguments: args, workingDirectory: workDir)
      }
    }
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
      let result = try await runCommand(.launchctl, ["print", target], nil)
      return result.succeeded
    } catch {
      logger.warning("Failed to check if service '\(label)' is loaded: \(error)")
      return false
    }
  }

  /// Gets the detailed status of a service
  public func getServiceStatus(_ label: String) async -> ServiceStatus {
    do {
      let target = try serviceTarget(label)
      let result = try await runCommand(.launchctl, ["print", target], nil)

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
      logger.warning("Failed to get status for service '\(label)': \(error)")
      return .unknown
    }
  }

  // MARK: - Service Lifecycle

  /// Bootstraps (loads) a service from a plist file
  ///
  /// This method handles the macOS launchctl quirk where `launchctl bootstrap`
  /// returns exit code 5 ("Input/output error") on service restarts, even though
  /// the service starts successfully. When error 5 occurs, it falls back to
  /// using `launchctl kickstart` and verifies the service is actually running.
  public func bootstrap(_ plistPath: URL) async throws(LaunchAgentError) {
    let path = plistPath.path
    guard fileManager.fileExists(atPath: path) else {
      throw .plistNotFound(path: path)
    }

    // Extract label for status checks and kickstart fallback
    let label = extractLabel(from: plistPath)

    if let label, await isServiceLoaded(label) {
      logger.info("Service \(label) already loaded, unloading first")
      do {
        try await bootout(label)
      } catch {
        logger.warning(
          "Failed to unload existing service \(label): \(error). Continuing with bootstrap attempt."
        )
      }
      try? await Task.sleep(for: .milliseconds(500))
    }

    let domain = try domainPath()
    logger.info("Bootstrapping service from \(path)")

    do {
      let result = try await runCommand(.launchctl, ["bootstrap", domain, path], nil)

      if result.succeeded {
        logger.info("Successfully bootstrapped service from \(path)")
        return
      }

      // Handle macOS launchctl quirk: error 5 (Input/output error) on restart
      // The service often starts anyway, so fallback to kickstart and verify
      if result.exitCode == 5, let label {
        logger.warning(
          "Bootstrap returned error 5 (I/O error), attempting kickstart fallback for \(label)"
        )
        try await kickstartFallback(label: label, plistPath: path)
        return
      }

      // Other non-zero exit codes are real failures
      struct BootstrapCommandError: Error, Sendable {
        let message: String
      }
      throw LaunchAgentError.bootstrapFailed(
        label: path,
        underlying: BootstrapCommandError(
          message: result.error.isEmpty ? "Exit code \(result.exitCode)" : result.error
        )
      )
    } catch let error as LaunchAgentError {
      throw error
    } catch {
      throw .bootstrapFailed(label: path, underlying: error)
    }
  }

  /// Fallback mechanism when bootstrap fails with error 5
  ///
  /// Uses kickstart to ensure the service is running, then verifies status.
  /// This handles the macOS launchctl quirk where bootstrap returns error 5
  /// but the service actually starts.
  private func kickstartFallback(label: String, plistPath: String) async throws(LaunchAgentError) {
    // First check if service is already running despite the error
    let initialStatus = await getServiceStatus(label)
    if case .running(let pid) = initialStatus {
      logger.info("Service \(label) is already running (PID: \(pid)) despite bootstrap error")
      return
    }

    // Try kickstart to force the service to start
    logger.info("Service not running, attempting kickstart for \(label)")

    do {
      try await kickstart(label)
    } catch {
      // Kickstart failed - service truly didn't start
      throw .bootstrapFailed(label: plistPath, underlying: error)
    }

    // Wait briefly and verify service is running
    try? await Task.sleep(for: .milliseconds(500))

    let finalStatus = await getServiceStatus(label)
    guard case .running(let pid) = finalStatus else {
      struct ServiceNotStartedError: Error, Sendable {
        let message: String
      }
      throw .bootstrapFailed(
        label: plistPath,
        underlying: ServiceNotStartedError(
          message: "Service failed to start after kickstart fallback. Status: \(finalStatus)"
        )
      )
    }

    logger.info("Successfully started service \(label) via kickstart fallback (PID: \(pid))")
  }

  /// Bootout (unloads) a service from launchd
  public func bootout(_ label: String) async throws(LaunchAgentError) {
    let target = try serviceTarget(label)
    logger.info("Booting out service \(label)")

    do {
      let result = try await runCommand(.launchctl, ["bootout", target], nil)

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
      let result = try await runCommand(.launchctl, ["kickstart", target], nil)

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
      let result = try await runCommand(.launchctl, ["kill", signal, target], nil)

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
        throw .plistWriteFailed(path: path, underlying: error)
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
    let path = plistURL.path
    do {
      let data = try Data(contentsOf: plistURL)
      guard
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any]
      else {
        logger.warning("Plist at \(path) is not a dictionary")
        return nil
      }
      guard let label = plist["Label"] as? String else {
        logger.warning("Plist at \(path) has no valid 'Label' key")
        return nil
      }
      return label
    } catch {
      logger.warning("Failed to extract label from plist at \(path): \(error)")
      return nil
    }
  }
}
