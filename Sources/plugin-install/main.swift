import ArgumentParser
import Foundation
import PluginInstall

@main
struct PluginInstallCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "plugin-install",
    abstract: "Install Claude Code plugins with dependency management",
    discussion: """
      Install plugins from the promptping marketplace or local paths.

      Examples:
        plugin-install agentPing              # Install from marketplace
        plugin-install agentPing --version 1.3.0
        plugin-install --from-path ./my-plugin
        plugin-install --list
      """,
    version: "1.0.0"
  )

  @Argument(help: "Plugin name from marketplace (e.g., 'agentPing')")
  var pluginName: String?

  @Option(name: .shortAndLong, help: "Specific version to install (e.g., '1.3.0')")
  var version: String?

  @Option(name: .long, help: "Install from local path instead of marketplace")
  var fromPath: String?

  @Option(name: .long, help: "Install from GitHub repository (e.g., 'owner/repo')")
  var fromGitHub: String?

  @Flag(name: .shortAndLong, help: "List installed plugins")
  var list: Bool = false

  @Flag(name: .long, help: "Show verbose output")
  var verbose: Bool = false

  mutating func validate() throws {
    // Ensure we have either a plugin name, --from-path, --from-github, or --list
    let hasSource = pluginName != nil || fromPath != nil || fromGitHub != nil || list
    guard hasSource else {
      throw ValidationError(
        "Please provide a plugin name, --from-path, --from-github, or --list")
    }
  }

  func run() async throws {
    let installer = PluginInstaller()

    if list {
      try await listPlugins(installer)
      return
    }

    let progressHandler: @Sendable (String) -> Void = { message in
      print(message)
    }

    let result: InstallResult

    if let path = fromPath {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      result = try await installer.installFromPath(url, progressHandler: progressHandler)
    } else if let repo = fromGitHub {
      result = try await installer.installFromGitHub(
        repository: repo,
        version: version,
        progressHandler: progressHandler
      )
    } else if let name = pluginName {
      result = try await installer.installFromMarketplace(
        pluginName: name,
        version: version,
        progressHandler: progressHandler
      )
    } else {
      throw ValidationError("No installation source specified")
    }

    // Print summary
    print("")
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║  Installation Complete                                       ║")
    print("╠══════════════════════════════════════════════════════════════╣")
    print("║  Plugin: \(result.pluginName.padding(toLength: 49, withPad: " ", startingAt: 0)) ║")
    print("║  Version: \(result.version.padding(toLength: 48, withPad: " ", startingAt: 0)) ║")
    print("║  Path: \(result.installPath.padding(toLength: 51, withPad: " ", startingAt: 0)) ║")
    if !result.dependenciesInstalled.isEmpty {
      print(
        "║  Dependencies: \(result.dependenciesInstalled.joined(separator: ", ").padding(toLength: 43, withPad: " ", startingAt: 0)) ║"
      )
    }
    print("╚══════════════════════════════════════════════════════════════╝")
    print("")
    print("Restart Claude Code to load the plugin.")
  }

  private func listPlugins(_ installer: PluginInstaller) async throws {
    let plugins = try await installer.listInstalledPlugins()

    if plugins.isEmpty {
      print("No plugins installed.")
      print("")
      print("Install a plugin with:")
      print("  plugin-install agentPing")
      return
    }

    print("Installed plugins:")
    print("")
    for plugin in plugins {
      print("  \(plugin.name) v\(plugin.version)")
      if let desc = plugin.description {
        print("    \(desc)")
      }
      print("    Path: \(plugin.path)")
      print("")
    }
  }
}
