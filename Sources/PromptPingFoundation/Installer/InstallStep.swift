import Foundation
import Logging

/// Protocol for installation pipeline steps
///
/// Each step represents a discrete phase in the daemon installation process.
/// Steps are executed sequentially and can modify the shared `InstallResult`.
///
/// ## Example Implementation
///
/// ```swift
/// public struct MyStep: InstallStep {
///     public let name = "My Step"
///
///     public init() {}
///
///     public func execute(
///         config: DaemonConfig,
///         context: InstallContext,
///         result: inout InstallResult
///     ) async throws(InstallerError) {
///         // Step implementation
///     }
/// }
/// ```
public protocol InstallStep: Sendable {
  /// Human-readable name for logging
  var name: String { get }

  /// Execute the step
  ///
  /// - Parameters:
  ///   - config: Daemon configuration
  ///   - context: Shared context with managers
  ///   - result: Installation result to update
  /// - Throws: `InstallerError` if the step fails
  func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError)
}

/// Shared context for installation steps
///
/// Contains all the managers and utilities needed by installation steps.
/// Passed to each step during execution to provide consistent access
/// to infrastructure components.
public struct InstallContext: Sendable {
  /// Subprocess runner for executing shell commands
  public let subprocess: SubprocessRunner

  /// Port manager for port availability checking and allocation
  public let portManager: PortManager

  /// File manager for atomic file operations
  public let fileManager: AtomicFileManager

  /// Launch agent manager for launchd service operations
  public let launchAgentManager: LaunchAgentManager

  /// Logger for step execution logging
  public let logger: Logger

  /// Creates a new installation context
  ///
  /// - Parameters:
  ///   - subprocess: Subprocess runner instance
  ///   - portManager: Port manager instance
  ///   - fileManager: Atomic file manager instance
  ///   - launchAgentManager: Launch agent manager instance
  ///   - logger: Logger instance
  public init(
    subprocess: SubprocessRunner,
    portManager: PortManager,
    fileManager: AtomicFileManager,
    launchAgentManager: LaunchAgentManager,
    logger: Logger
  ) {
    self.subprocess = subprocess
    self.portManager = portManager
    self.fileManager = fileManager
    self.launchAgentManager = launchAgentManager
    self.logger = logger
  }
}
