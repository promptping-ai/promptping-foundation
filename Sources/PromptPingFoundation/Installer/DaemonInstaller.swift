import Foundation
import Logging

/// High-level daemon installation orchestrator
///
/// Combines SubprocessRunner, PortManager, AtomicFileManager, and LaunchAgentManager
/// to provide a complete daemon installation workflow.
public actor DaemonInstaller {
  private let subprocess: SubprocessRunner
  private let portManager: PortManager
  private let fileManager: AtomicFileManager
  private let launchAgentManager: LaunchAgentManager
  private let logger: Logger

  public init(logger: Logger = Logger(label: "promptping.installer")) {
    self.logger = logger
    self.subprocess = SubprocessRunner(logger: logger)
    self.portManager = PortManager(logger: logger)
    self.fileManager = AtomicFileManager(logger: logger)
    self.launchAgentManager = LaunchAgentManager(
      subprocessRunner: subprocess,
      logger: logger
    )
  }

  /// Install a daemon with the given configuration
  ///
  /// This performs the full installation workflow:
  /// 1. Build products (if not skipped)
  /// 2. Allocate port (if port config provided)
  /// 3. Stop existing service (if running)
  /// 4. Install binaries atomically
  /// 5. Generate and install plist
  /// 6. Bootstrap service
  public func install(_ config: DaemonConfig) async throws(InstallerError) -> InstallResult {
    logger.info("Installing daemon: \(config.name)")
    var result = InstallResult(name: config.name)

    // Step 1: Build products (if not skipped)
    if !config.skipBuild {
      logger.info("Building products...")
      let buildDir = try await buildProducts(config)
      result.buildPath = buildDir
    }

    // Step 2: Allocate port
    let port: Int
    if let portConfig = config.portConfig {
      port = try await allocatePort(portConfig)
      result.port = port
      logger.info("Allocated port: \(port)")
    } else {
      port = config.portConfig?.defaultPort ?? 50052
      result.port = port
    }

    // Step 3: Stop existing service if running
    if let serviceConfig = config.serviceConfig {
      let status = await launchAgentManager.getServiceStatus(serviceConfig.label)
      if case .running = status {
        logger.info("Stopping existing service...")
        do {
          try await launchAgentManager.bootout(serviceConfig.label)
          result.previousServiceStopped = true
        } catch {
          throw .serviceNotLoaded("Failed to stop \(serviceConfig.label): \(error)")
        }
      }
    }

    // Step 4: Install binaries atomically
    let swiftpmBin = PathResolver.StandardPath.swiftpmBin.url
    do {
      try await fileManager.ensureDirectory(at: swiftpmBin)
    } catch {
      throw .binaryNotFound("Failed to create bin directory: \(error)")
    }

    let operations = config.binaries.map { binary in
      (source: binary.sourcePath, destination: swiftpmBin.appendingPathComponent(binary.name))
    }

    do {
      try await fileManager.atomicInstall(operations)
    } catch {
      throw .binaryNotFound("Failed to install binaries: \(error)")
    }
    result.binariesInstalled = config.binaries.map(\.name)
    logger.info("Installed binaries: \(result.binariesInstalled.joined(separator: ", "))")

    // Step 5: Generate and install plist
    if var serviceConfig = config.serviceConfig {
      serviceConfig.arguments = updatePortArguments(serviceConfig.arguments, port: port)

      let launchAgentsDir = PathResolver.StandardPath.launchAgents.url
      let plistURL = launchAgentsDir.appendingPathComponent("\(serviceConfig.label).plist")

      do {
        try await launchAgentManager.installPlist(config: serviceConfig, to: plistURL)
      } catch {
        throw .configurationMissing("Failed to install plist: \(error)")
      }
      result.plistPath = plistURL
      result.serviceInstalled = true

      // Step 6: Bootstrap service
      do {
        try await launchAgentManager.bootstrap(plistURL)
      } catch {
        throw .serviceNotLoaded("Failed to bootstrap \(serviceConfig.label): \(error)")
      }
      logger.info("Service bootstrapped: \(serviceConfig.label)")
    }

    logger.info("Installation complete!")
    return result
  }

  /// Uninstall a daemon
  public func uninstall(
    _ config: DaemonConfig,
    removeBinaries: Bool = false,
    removeLogs: Bool = false
  ) async throws(InstallerError) {
    logger.info("Uninstalling daemon: \(config.name)")

    if let serviceConfig = config.serviceConfig {
      let status = await launchAgentManager.getServiceStatus(serviceConfig.label)
      if case .running = status {
        logger.info("Stopping service...")
        try? await launchAgentManager.kill(serviceConfig.label, signal: "SIGTERM")
      }

      do {
        try await launchAgentManager.bootout(serviceConfig.label)
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

  // MARK: - Private Helpers

  private func buildProducts(_ config: DaemonConfig) async throws(InstallerError) -> URL {
    var args =
      config.useSwiftBuild
      ? ["build", "--build-system", "swiftbuild", "-c", "release"]
      : ["build", "-c", "release"]

    if let jobs = config.buildJobs {
      args += ["-j", String(jobs)]
    }

    do {
      let result = try await subprocess.run(.swift, arguments: args)
      guard result.succeeded else {
        throw InstallerError.buildFailed(result.error)
      }
    } catch let error as InstallerError {
      throw error
    } catch {
      throw .buildFailed(error.localizedDescription)
    }

    let buildDir = Foundation.FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: buildDir).appendingPathComponent(".build/release")
  }

  private func allocatePort(_ portConfig: PortConfig) async throws(InstallerError) -> Int {
    let defaultInUse = await portManager.isPortInUse(portConfig.defaultPort)
    if !defaultInUse {
      return portConfig.defaultPort
    }

    if let range = portConfig.portRange {
      do {
        return try await portManager.findFreePort(in: range, excluding: portConfig.excludedPorts)
      } catch {
        throw .portAllocationFailed("No free port in range \(range)")
      }
    }

    throw .portAllocationFailed("Default port \(portConfig.defaultPort) is in use")
  }

  private func updatePortArguments(_ arguments: [String], port: Int) -> [String] {
    var result = arguments
    if let portIndex = result.firstIndex(of: "--port") {
      if portIndex + 1 < result.count {
        result[portIndex + 1] = String(port)
      } else {
        // --port exists but no value follows - append the port value
        result.append(String(port))
        logger.warning("Found --port flag without value, appending port \(port)")
      }
    } else {
      // No --port flag found - add it with the value
      result.append(contentsOf: ["--port", String(port)])
      logger.info("Added --port \(port) to service arguments")
    }
    return result
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
