import ArgumentParser
import Foundation
import Logging
import PromptPingFoundation

@main
struct InstallDaemonCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install-daemon",
    abstract: "Install daemon with launchd service management",
    discussion: """
      Installs daemon binaries to ~/.swiftpm/bin/ and optionally configures a launchd service.
      Reads configuration from a daemon-config.json file in the current directory.

      Examples:
        install-daemon                                    # Install with defaults
        install-daemon --skip-build                       # Use pre-built binaries
        install-daemon --port 50053                       # Override default port
        install-daemon uninstall                          # Remove service and plist
        install-daemon uninstall --remove-binaries        # Also remove binaries
      """,
    subcommands: [Install.self, Uninstall.self],
    defaultSubcommand: Install.self
  )
}

// MARK: - Install Subcommand

struct Install: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Install daemon binaries and optionally configure launchd service"
  )

  @Option(name: .shortAndLong, help: "Path to daemon-config.json")
  var config: String = "daemon-config.json"

  @Option(name: .shortAndLong, help: "Override default port")
  var port: Int?

  @Option(name: .long, help: "Log level for daemon (trace, debug, info, notice, warning, error)")
  var logLevel: String = "info"

  @Flag(name: .long, help: "Skip building, use existing binaries from .build/release/")
  var skipBuild: Bool = false

  @Flag(name: .long, help: "Use native build system instead of swiftbuild")
  var useNativeBuild: Bool = false

  @Option(name: .shortAndLong, help: "Number of parallel build jobs")
  var jobs: Int?

  @Flag(name: .long, help: "Show what would be done without making changes")
  var dryRun: Bool = false

  func run() async throws {
    // Load configuration file
    let fileConfig = try DaemonConfigFile.load(from: config)

    // Setup logging
    var logger = Logger(label: "install-daemon")
    logger.logLevel = .info

    if dryRun {
      print("═══════════════════════════════════════════════════════════")
      print("  DRY RUN - No changes will be made")
      print("═══════════════════════════════════════════════════════════")
      print("")
      print("Configuration: \(config)")
      print("  Name: \(fileConfig.name)")
      print("  Service Label: \(fileConfig.serviceLabel)")
      print("  Products: \(fileConfig.products.joined(separator: ", "))")
      if let daemon = fileConfig.daemonProduct {
        print("  Daemon Product: \(daemon)")
      }
      print("  Port: \(port ?? fileConfig.defaultPort ?? 50052)")
      print("  Skip Build: \(skipBuild)")
      print("")
      return
    }

    // Convert file config to DaemonConfig
    let daemonConfig = try fileConfig.toDaemonConfig(
      port: port,
      logLevel: logLevel,
      skipBuild: skipBuild,
      useSwiftBuild: !useNativeBuild,
      buildJobs: jobs
    )

    // Run installation
    let installer = DaemonInstaller(logger: logger)

    print("═══════════════════════════════════════════════════════════")
    print("  Installing daemon: \(daemonConfig.name)")
    print("═══════════════════════════════════════════════════════════")
    print("")

    let result = try await installer.install(daemonConfig)

    // Print results
    print("")
    print("═══════════════════════════════════════════════════════════")
    print("  Installation Complete!")
    print("═══════════════════════════════════════════════════════════")
    print("")
    print("  Binaries installed: \(result.binariesInstalled.joined(separator: ", "))")
    if let port = result.port {
      print("  Port: \(port)")
    }
    if result.serviceInstalled, let plistPath = result.plistPath {
      print("  Service plist: \(plistPath.path)")
    }
    print("")
  }
}

// MARK: - Uninstall Subcommand

struct Uninstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "uninstall",
    abstract: "Uninstall daemon service and optionally remove binaries"
  )

  @Option(name: .shortAndLong, help: "Path to daemon-config.json")
  var config: String = "daemon-config.json"

  @Flag(name: .long, help: "Also remove installed binaries from ~/.swiftpm/bin/")
  var removeBinaries: Bool = false

  @Flag(name: .long, help: "Also remove log files")
  var removeLogs: Bool = false

  func run() async throws {
    // Load configuration file
    let fileConfig = try DaemonConfigFile.load(from: config)

    // Setup logging
    var logger = Logger(label: "install-daemon")
    logger.logLevel = .info

    // Convert file config to DaemonConfig
    let daemonConfig = try fileConfig.toDaemonConfig()

    // Run uninstallation
    let installer = DaemonInstaller(logger: logger)

    print("═══════════════════════════════════════════════════════════")
    print("  Uninstalling daemon: \(daemonConfig.name)")
    print("═══════════════════════════════════════════════════════════")
    print("")

    try await installer.uninstall(
      daemonConfig,
      removeBinaries: removeBinaries,
      removeLogs: removeLogs
    )

    print("")
    print("═══════════════════════════════════════════════════════════")
    print("  Uninstall Complete!")
    print("═══════════════════════════════════════════════════════════")
    print("")
  }
}
