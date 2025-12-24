import Foundation
import PromptPingFoundation

/// JSON configuration file format for daemon installation
///
/// This struct maps to the `daemon-config.json` file format used by packages
/// to define their daemon installation configuration.
///
/// ## Example daemon-config.json
///
/// ```json
/// {
///     "name": "my-daemon",
///     "serviceLabel": "com.example.my-daemon",
///     "products": ["my-daemon-server", "my-daemon-client"],
///     "daemonProduct": "my-daemon-server",
///     "defaultPort": 50052,
///     "portRange": [50052, 50102]
/// }
/// ```
struct DaemonConfigFile: Codable {
  /// Name of the daemon (used for directories and logging)
  let name: String

  /// Service label for launchd (e.g., "com.example.my-daemon")
  let serviceLabel: String

  /// List of product names to install
  let products: [String]

  /// Which product is the main daemon (optional - if nil, no service is created)
  let daemonProduct: String?

  /// Default port for the daemon
  let defaultPort: Int?

  /// Port range for automatic allocation [min, max]
  let portRange: [Int]?

  /// Custom log directory (defaults to ~/Library/Logs/<name>)
  let logDirectory: String?

  /// Custom cache directory (defaults to ~/.cache/<name>)
  let cacheDirectory: String?

  /// Load configuration from a JSON file
  ///
  /// - Parameter path: Path to the daemon-config.json file
  /// - Returns: Parsed configuration
  /// - Throws: If file cannot be read or parsed
  static func load(from path: String) throws -> Self {
    let url = URL(fileURLWithPath: path)

    guard FileManager.default.fileExists(atPath: url.path) else {
      throw ConfigError.fileNotFound(path)
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw ConfigError.readFailed(path, error.localizedDescription)
    }

    do {
      return try JSONDecoder().decode(Self.self, from: data)
    } catch {
      throw ConfigError.parseFailed(path, error.localizedDescription)
    }
  }

  /// Convert to library DaemonConfig type
  ///
  /// - Parameters:
  ///   - port: Override port (uses defaultPort if nil)
  ///   - logLevel: Log level for daemon arguments
  ///   - skipBuild: Whether to skip building
  ///   - useSwiftBuild: Whether to use swiftbuild system
  ///   - buildJobs: Number of parallel build jobs
  /// - Returns: DaemonConfig for use with DaemonInstaller
  func toDaemonConfig(
    port: Int? = nil,
    logLevel: String = "info",
    skipBuild: Bool = false,
    useSwiftBuild: Bool = true,
    buildJobs: Int? = nil
  ) throws -> DaemonConfig {
    // Resolve binary paths from .build/release/ when skipBuild is true
    // or from product names for building
    let releaseDir = FileManager.default.currentDirectoryPath + "/.build/release"
    let swiftpmBin =
      FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".swiftpm/bin")
      .path

    let binaries = products.map { product -> BinaryConfig in
      // Path to the built binary in the release directory
      let sourcePath = URL(fileURLWithPath: releaseDir).appendingPathComponent(product)

      let isDaemon = (product == daemonProduct)
      return BinaryConfig(name: product, sourcePath: sourcePath, isDaemon: isDaemon)
    }

    // Validate binaries exist when skip-build is set
    if skipBuild {
      for binary in binaries {
        guard FileManager.default.fileExists(atPath: binary.sourcePath.path) else {
          throw ConfigError.binaryNotFound(binary.name, binary.sourcePath.path)
        }
      }
    }

    // Build port configuration
    let portConfig: PortConfig?
    if let defaultPort = port ?? self.defaultPort {
      let range: ClosedRange<Int>?
      if let portRange = self.portRange, portRange.count >= 2 {
        range = portRange[0]...portRange[1]
      } else {
        range = nil
      }
      portConfig = PortConfig(defaultPort: defaultPort, portRange: range)
    } else {
      portConfig = nil
    }

    // Build service configuration for daemon
    let serviceConfig: ServiceConfig?
    if let daemonProduct = daemonProduct {
      let home = FileManager.default.homeDirectoryForCurrentUser.path
      let logDir = logDirectory ?? "~/Library/Logs/\(name)"
      let cacheDir = cacheDirectory ?? "~/.cache/\(name)"

      let effectivePort = port ?? defaultPort ?? 50052

      serviceConfig = ServiceConfig(
        label: serviceLabel,
        executable: "\(swiftpmBin)/\(daemonProduct)",
        arguments: ["--port", String(effectivePort), "--log-level", logLevel],
        runAtLoad: true,
        keepAlive: true,
        standardOutPath: logDir.replacingOccurrences(of: "~", with: home) + "/daemon.log",
        standardErrorPath: logDir.replacingOccurrences(of: "~", with: home) + "/daemon.err",
        environment: [
          "PATH": "\(swiftpmBin):/usr/local/bin:/usr/bin:/bin",
          "HOME": home,
        ],
        workingDirectory: cacheDir.replacingOccurrences(of: "~", with: home),
        throttleInterval: 10,
        processType: .background
      )
    } else {
      serviceConfig = nil
    }

    return DaemonConfig(
      name: name,
      serviceLabel: serviceLabel,
      binaries: binaries,
      skipBuild: skipBuild,
      useSwiftBuild: useSwiftBuild,
      buildJobs: buildJobs,
      portConfig: portConfig,
      serviceConfig: serviceConfig,
      logDirectory: logDirectory,
      cacheDirectory: cacheDirectory
    )
  }
}

// MARK: - Errors

enum ConfigError: Error, LocalizedError {
  case fileNotFound(String)
  case readFailed(String, String)
  case parseFailed(String, String)
  case binaryNotFound(String, String)

  var errorDescription: String? {
    switch self {
    case .fileNotFound(let path):
      return """
        Configuration file not found: \(path)

        Create a daemon-config.json with the following structure:
        {
            "name": "my-daemon",
            "serviceLabel": "com.example.my-daemon",
            "products": ["my-daemon-server"],
            "daemonProduct": "my-daemon-server",
            "defaultPort": 50052
        }
        """
    case .readFailed(let path, let reason):
      return "Failed to read \(path): \(reason)"
    case .parseFailed(let path, let reason):
      return "Failed to parse \(path): \(reason)"
    case .binaryNotFound(let name, let path):
      return """
        Binary '\(name)' not found at \(path)

        Either:
        1. Run 'swift build -c release' first, then use --skip-build
        2. Remove --skip-build to build as part of installation
        """
    }
  }
}
