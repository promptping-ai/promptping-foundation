import Foundation

/// Resolves and installs plugin dependencies (e.g., MCP server binaries)
public actor DependencyResolver {
  private let tempDirectory: URL

  public init() {
    self.tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("plugin-install-\(UUID().uuidString)")
  }

  /// Check which dependencies are missing
  public func checkMissingDependencies(
    _ dependencies: [String: PluginManifest.Dependency]
  ) -> [(name: String, dependency: PluginManifest.Dependency)] {
    dependencies.compactMap { name, dep in
      dep.isSatisfied() ? nil : (name, dep)
    }
  }

  /// Install a single dependency via SPM
  public func installDependency(
    name: String,
    dependency: PluginManifest.Dependency,
    progressHandler: @Sendable (String) -> Void
  ) async throws {
    progressHandler("Installing \(name) from \(dependency.repository)...")

    // Clone the repository
    let repoURL = "https://\(dependency.repository)"
    let cloneDir = tempDirectory.appendingPathComponent(name)

    try FileManager.default.createDirectory(
      at: tempDirectory,
      withIntermediateDirectories: true
    )

    // Run git clone
    progressHandler("Cloning \(repoURL)...")
    try await runCommand("git", arguments: ["clone", "--depth", "1", repoURL, cloneDir.path])

    // Run SPM install
    let installCommand = dependency.installCommand ?? "swift package experimental-install"
    let parts = installCommand.split(separator: " ").map(String.init)

    guard parts.count >= 2 else {
      throw DependencyError.invalidInstallCommand(installCommand)
    }

    progressHandler("Building and installing...")
    try await runCommand(
      parts[0],
      arguments: Array(parts.dropFirst()),
      workingDirectory: cloneDir
    )

    // Verify installation
    if let binaryName = dependency.binaryName {
      let binaryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".swiftpm/bin")
        .appendingPathComponent(binaryName)

      guard FileManager.default.fileExists(atPath: binaryPath.path) else {
        throw DependencyError.installationFailed(name, "Binary not found at \(binaryPath.path)")
      }

      progressHandler("✅ \(name) installed successfully at \(binaryPath.path)")
    }

    // Cleanup
    try? FileManager.default.removeItem(at: cloneDir)
  }

  /// Install all missing dependencies
  public func installMissingDependencies(
    _ dependencies: [String: PluginManifest.Dependency],
    progressHandler: @Sendable (String) -> Void
  ) async throws {
    let missing = checkMissingDependencies(dependencies)

    if missing.isEmpty {
      progressHandler("All dependencies are satisfied.")
      return
    }

    progressHandler("Missing dependencies: \(missing.map(\.name).joined(separator: ", "))")

    for (name, dep) in missing {
      try await installDependency(name: name, dependency: dep, progressHandler: progressHandler)
    }
  }

  private func runCommand(
    _ command: String,
    arguments: [String],
    workingDirectory: URL? = nil
  ) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments

    if let workingDirectory = workingDirectory {
      process.currentDirectoryURL = workingDirectory
    }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
      throw DependencyError.commandFailed(command, output ?? "Unknown error")
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: tempDirectory)
  }
}

public enum DependencyError: Error, LocalizedError {
  case invalidInstallCommand(String)
  case installationFailed(String, String)
  case commandFailed(String, String)

  public var errorDescription: String? {
    switch self {
    case .invalidInstallCommand(let cmd):
      return "Invalid install command: \(cmd)"
    case .installationFailed(let name, let reason):
      return "Failed to install \(name): \(reason)"
    case .commandFailed(let cmd, let output):
      return "Command '\(cmd)' failed: \(output)"
    }
  }
}
