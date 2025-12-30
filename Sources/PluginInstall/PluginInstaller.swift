import Foundation

/// Installs Claude Code plugins to ~/.claude/plugins/
public actor PluginInstaller {
  private let pluginsBaseDirectory: URL
  private let cacheDirectory: URL
  private let installedPluginsFile: URL
  private let dependencyResolver: DependencyResolver

  public init(pluginsDirectory: URL? = nil) {
    let base =
      pluginsDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/plugins")
    self.pluginsBaseDirectory = base
    self.cacheDirectory = base.appendingPathComponent("cache/promptping-marketplace")
    self.installedPluginsFile = base.appendingPathComponent("installed_plugins.json")
    self.dependencyResolver = DependencyResolver()
  }

  /// List installed plugins from Claude Code's installed_plugins.json
  public func listInstalledPlugins() throws -> [InstalledPlugin] {
    guard FileManager.default.fileExists(atPath: installedPluginsFile.path) else {
      return []
    }

    let data = try Data(contentsOf: installedPluginsFile)
    let registry = try JSONDecoder().decode(InstalledPluginsRegistry.self, from: data)

    return registry.plugins.flatMap { (key, installs) -> [InstalledPlugin] in
      installs.compactMap { install -> InstalledPlugin? in
        // Try to load manifest from install path
        let manifestURL = URL(fileURLWithPath: install.installPath)
          .appendingPathComponent("plugin.json")
        let manifest = try? PluginManifest.load(from: manifestURL)

        let name = key.split(separator: "@").first.map(String.init) ?? key
        return InstalledPlugin(
          name: name,
          version: install.version,
          path: install.installPath,
          description: manifest?.description
        )
      }
    }
  }

  /// Registry format for installed_plugins.json
  private struct InstalledPluginsRegistry: Codable {
    let version: Int
    let plugins: [String: [PluginInstallInfo]]
  }

  private struct PluginInstallInfo: Codable {
    let scope: String
    let installPath: String
    let version: String
    let installedAt: String
    let lastUpdated: String
    let gitCommitSha: String?
    let isLocal: Bool?
  }

  /// Install a plugin from a local directory
  public func installFromPath(
    _ sourcePath: URL,
    progressHandler: @Sendable (String) -> Void
  ) async throws -> InstallResult {
    // Load manifest
    progressHandler("Loading plugin manifest...")
    let manifest = try PluginManifest.load(fromDirectory: sourcePath)

    progressHandler("Installing \(manifest.name) v\(manifest.version)...")

    // Check/install dependencies
    if let dependencies = manifest.dependencies, !dependencies.isEmpty {
      progressHandler("Checking dependencies...")
      try await dependencyResolver.installMissingDependencies(
        dependencies,
        progressHandler: progressHandler
      )
    }

    // Create plugins cache directory if needed
    // Structure: ~/.claude/plugins/cache/promptping-marketplace/{plugin}/{version}/
    let pluginCacheDir = cacheDirectory
      .appendingPathComponent(manifest.name)
      .appendingPathComponent(manifest.version)

    try FileManager.default.createDirectory(
      at: pluginCacheDir,
      withIntermediateDirectories: true
    )

    // Destination path
    let destinationPath = pluginCacheDir

    // Copy plugin files (excluding .git)
    progressHandler("Copying plugin files...")
    let sourceContents = try FileManager.default.contentsOfDirectory(
      at: sourcePath,
      includingPropertiesForKeys: nil
    )

    for item in sourceContents {
      let itemName = item.lastPathComponent
      if itemName == ".git" || itemName == ".build" {
        continue  // Skip git and build directories
      }
      let dest = destinationPath.appendingPathComponent(itemName)
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.copyItem(at: item, to: dest)
    }

    progressHandler("✅ \(manifest.name) v\(manifest.version) installed successfully!")

    return InstallResult(
      pluginName: manifest.name,
      version: manifest.version,
      installPath: destinationPath.path,
      dependenciesInstalled: manifest.dependencies?.keys.map { String($0) } ?? []
    )
  }

  /// Install a plugin from a GitHub repository
  public func installFromGitHub(
    repository: String,
    version: String? = nil,
    progressHandler: @Sendable (String) -> Void
  ) async throws -> InstallResult {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("plugin-install-\(UUID().uuidString)")

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    // Clone repository
    let repoURL = repository.hasPrefix("https://") ? repository : "https://github.com/\(repository)"

    progressHandler("Cloning \(repoURL)...")

    var cloneArgs = ["clone", "--depth", "1"]
    if let version = version {
      cloneArgs += ["--branch", version]
    }
    cloneArgs += [repoURL, tempDir.path]

    try await runCommand("git", arguments: cloneArgs)

    // Install from the cloned directory
    return try await installFromPath(tempDir, progressHandler: progressHandler)
  }

  /// Install a known plugin from the marketplace
  public func installFromMarketplace(
    pluginName: String,
    version: String? = nil,
    progressHandler: @Sendable (String) -> Void
  ) async throws -> InstallResult {
    // Map known plugins to their repositories
    let knownPlugins: [String: String] = [
      "agentPing": "promptping-ai/agentPing",
      "edgeprompt": "promptping-ai/edgeprompt",
      "semantickit": "promptping-ai/semantickit",
    ]

    guard let repo = knownPlugins[pluginName] else {
      throw PluginInstallError.unknownPlugin(pluginName, Array(knownPlugins.keys))
    }

    let tag = version.map { "v\($0)" }
    return try await installFromGitHub(
      repository: repo,
      version: tag,
      progressHandler: progressHandler
    )
  }

  private func runCommand(_ command: String, arguments: [String]) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
      throw PluginInstallError.commandFailed(command, output ?? "Unknown error")
    }
  }
}

public struct InstalledPlugin: Sendable {
  public let name: String
  public let version: String
  public let path: String
  public let description: String?
}

public struct InstallResult: Sendable {
  public let pluginName: String
  public let version: String
  public let installPath: String
  public let dependenciesInstalled: [String]
}

public enum PluginInstallError: Error, LocalizedError {
  case unknownPlugin(String, [String])
  case commandFailed(String, String)
  case manifestNotFound(String)

  public var errorDescription: String? {
    switch self {
    case .unknownPlugin(let name, let known):
      return "Unknown plugin '\(name)'. Known plugins: \(known.joined(separator: ", "))"
    case .commandFailed(let cmd, let output):
      return "Command '\(cmd)' failed: \(output)"
    case .manifestNotFound(let path):
      return "No plugin.json found at \(path)"
    }
  }
}
