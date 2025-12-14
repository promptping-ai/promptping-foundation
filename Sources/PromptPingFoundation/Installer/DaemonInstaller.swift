import Foundation
import Logging

/// High-level daemon installation orchestrator
///
/// Combines SubprocessRunner, PortManager, AtomicFileManager, and LaunchAgentManager
/// to provide a complete daemon installation workflow using the Strategy pattern.
///
/// ## Architecture
///
/// The installer uses a pipeline of `InstallStep` implementations:
/// 1. `BuildStep` - Build products (if not skipped)
/// 2. `PortAllocationStep` - Allocate port (if port config provided)
/// 3. `StopExistingServiceStep` - Stop existing service (if running)
/// 4. `InstallBinariesStep` - Install binaries atomically
/// 5. `InstallPlistStep` - Generate and install plist
/// 6. `BootstrapServiceStep` - Bootstrap service
///
/// Each step is independently testable and can be customized or replaced.
///
/// ## Example Usage
///
/// ```swift
/// let installer = DaemonInstaller()
/// let config = DaemonConfig(
///     name: "my-daemon",
///     serviceLabel: "com.myorg.my-daemon",
///     binaries: [BinaryConfig(name: "my-daemon", sourcePath: buildURL)]
/// )
/// let result = try await installer.install(config)
/// ```
public actor DaemonInstaller {
  private let context: InstallContext
  private let steps: [any InstallStep]
  private let logger: Logger

  /// Creates a new daemon installer with default configuration
  ///
  /// - Parameter logger: Logger instance for installation logging
  public init(logger: Logger = Logger(label: "promptping.installer")) {
    self.logger = logger
    let subprocess = SubprocessRunner(logger: logger)
    let portManager = PortManager(logger: logger)
    let fileManager = AtomicFileManager(logger: logger)
    let launchAgentManager = LaunchAgentManager(
      subprocessRunner: subprocess,
      logger: logger
    )

    self.context = InstallContext(
      subprocess: subprocess,
      portManager: portManager,
      fileManager: fileManager,
      launchAgentManager: launchAgentManager,
      logger: logger
    )

    self.steps = [
      BuildStep(),
      PortAllocationStep(),
      StopExistingServiceStep(),
      InstallBinariesStep(),
      InstallPlistStep(),
      BootstrapServiceStep(),
    ]
  }

  /// Creates a daemon installer with custom steps
  ///
  /// Use this initializer for testing or to customize the installation pipeline.
  ///
  /// - Parameters:
  ///   - context: Installation context with managers
  ///   - steps: Custom installation steps
  ///   - logger: Logger instance
  public init(
    context: InstallContext,
    steps: [any InstallStep],
    logger: Logger = Logger(label: "promptping.installer")
  ) {
    self.context = context
    self.steps = steps
    self.logger = logger
  }

  /// Install a daemon with the given configuration
  ///
  /// Executes each installation step in sequence. If any step fails,
  /// the installation is aborted and the error is propagated.
  ///
  /// - Parameter config: Daemon configuration
  /// - Returns: Installation result with details about what was installed
  /// - Throws: `InstallerError` if any step fails
  public func install(_ config: DaemonConfig) async throws(InstallerError) -> InstallResult {
    logger.info("Installing daemon: \(config.name)")
    var result = InstallResult(name: config.name)

    for step in steps {
      logger.info("Executing step: \(step.name)")
      try await step.execute(config: config, context: context, result: &result)
    }

    logger.info("Installation complete!")
    return result
  }

  /// Uninstall a daemon
  ///
  /// Stops and unloads the service, optionally removing binaries and logs.
  ///
  /// - Parameters:
  ///   - config: Daemon configuration
  ///   - removeBinaries: Whether to remove installed binaries
  ///   - removeLogs: Whether to remove log files
  /// - Throws: `InstallerError` if uninstallation fails
  public func uninstall(
    _ config: DaemonConfig,
    removeBinaries: Bool = false,
    removeLogs: Bool = false
  ) async throws(InstallerError) {
    logger.info("Uninstalling daemon: \(config.name)")

    if let serviceConfig = config.serviceConfig {
      let status = await context.launchAgentManager.getServiceStatus(serviceConfig.label)
      if case .running = status {
        logger.info("Stopping service...")
        try? await context.launchAgentManager.kill(serviceConfig.label, signal: "SIGTERM")
      }

      do {
        try await context.launchAgentManager.bootout(serviceConfig.label)
      } catch {
        throw .serviceNotLoaded("Failed to unload \(serviceConfig.label): \(error)")
      }

      let launchAgentsDir = PathResolver.StandardPath.launchAgents.url
      let plistURL = launchAgentsDir.appendingPathComponent("\(serviceConfig.label).plist")
      try? Foundation.FileManager.default.removeItem(at: plistURL)
      logger.info("Removed plist: \(plistURL.path)")
    }

    if removeBinaries {
      let swiftpmBin = PathResolver.StandardPath.swiftpmBin.url
      for binary in config.binaries {
        let binaryPath = swiftpmBin.appendingPathComponent(binary.name)
        try? Foundation.FileManager.default.removeItem(at: binaryPath)
        logger.info("Removed binary: \(binary.name)")
      }
    }

    if removeLogs, let logDir = config.logDirectory {
      let logURL = PathResolver().resolve(logDir)
      try? Foundation.FileManager.default.removeItem(at: logURL)
      logger.info("Removed logs: \(logDir)")
    }

    logger.info("Uninstall complete!")
  }
}

// MARK: - Configuration Types

/// Configuration for daemon installation
public struct DaemonConfig: Sendable {
  /// Name of the daemon
  public let name: String

  /// Service label for launchd
  public let serviceLabel: String

  /// Binary configurations to install
  public let binaries: [BinaryConfig]

  /// Skip building (assume binaries exist)
  public var skipBuild: Bool

  /// Use swift build system (swiftbuild) instead of native
  public var useSwiftBuild: Bool

  /// Number of parallel build jobs
  public var buildJobs: Int?

  /// Port configuration
  public var portConfig: PortConfig?

  /// Service configuration for launchd
  public var serviceConfig: ServiceConfig?

  /// Log directory path (supports ~ expansion)
  public var logDirectory: String?

  /// Cache directory path (supports ~ expansion)
  public var cacheDirectory: String?

  public init(
    name: String,
    serviceLabel: String,
    binaries: [BinaryConfig],
    skipBuild: Bool = false,
    useSwiftBuild: Bool = true,
    buildJobs: Int? = nil,
    portConfig: PortConfig? = nil,
    serviceConfig: ServiceConfig? = nil,
    logDirectory: String? = nil,
    cacheDirectory: String? = nil
  ) {
    self.name = name
    self.serviceLabel = serviceLabel
    self.binaries = binaries
    self.skipBuild = skipBuild
    self.useSwiftBuild = useSwiftBuild
    self.buildJobs = buildJobs
    self.portConfig = portConfig
    self.serviceConfig = serviceConfig
    self.logDirectory = logDirectory
    self.cacheDirectory = cacheDirectory
  }
}

/// Configuration for a single binary to install
public struct BinaryConfig: Sendable {
  /// Name of the binary (used as destination filename)
  public let name: String

  /// Source path of the built binary
  public let sourcePath: URL

  /// Whether this is the main daemon binary
  public var isDaemon: Bool

  public init(name: String, sourcePath: URL, isDaemon: Bool = false) {
    self.name = name
    self.sourcePath = sourcePath
    self.isDaemon = isDaemon
  }
}

/// Configuration for port allocation
public struct PortConfig: Sendable {
  /// Default port to use
  public let defaultPort: Int

  /// Range to search for free port if default is in use
  public var portRange: ClosedRange<Int>?

  /// Ports to exclude from allocation
  public var excludedPorts: Set<Int>

  public init(
    defaultPort: Int,
    portRange: ClosedRange<Int>? = nil,
    excludedPorts: Set<Int> = []
  ) {
    self.defaultPort = defaultPort
    self.portRange = portRange
    self.excludedPorts = excludedPorts
  }
}
