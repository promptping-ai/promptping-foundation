import Foundation
import PackagePlugin

@main
struct InstallDaemonPlugin: CommandPlugin {
  func performCommand(
    context: PluginContext,
    arguments: [String]
  ) async throws {
    var args = ArgumentExtractor(arguments)

    let port = args.extractOption(named: "port").first.flatMap(Int.init) ?? 50052
    let skipBuild = args.extractFlag(named: "skip-build") > 0
    let uninstall = args.extractFlag(named: "uninstall") > 0
    let logLevel = args.extractOption(named: "log-level").first ?? "info"

    let configURL = context.package.directoryURL.appendingPathComponent("daemon-config.json")

    guard FileManager.default.fileExists(atPath: configURL.path) else {
      Diagnostics.error("daemon-config.json not found in package root")
      Diagnostics.remark("Create a configuration file with the following structure:")
      Diagnostics.remark(
        """
        {
            "name": "my-daemon",
            "serviceLabel": "com.example.my-daemon",
            "products": ["my-daemon-server", "my-daemon-client"],
            "daemonProduct": "my-daemon-server",
            "defaultPort": 50052,
            "portRange": [50052, 50102]
        }
        """)
      throw PluginError.configNotFound
    }

    let configData = try Data(contentsOf: configURL)
    let config = try JSONDecoder().decode(DaemonPluginConfig.self, from: configData)

    if uninstall {
      try await performUninstall(context: context, config: config)
    } else {
      try await performInstall(
        context: context,
        config: config,
        port: port,
        skipBuild: skipBuild,
        logLevel: logLevel
      )
    }
  }

  private func performInstall(
    context: PluginContext,
    config: DaemonPluginConfig,
    port: Int,
    skipBuild: Bool,
    logLevel: String
  ) async throws {
    Diagnostics.remark("Installing daemon: \(config.name)")
    Diagnostics.remark("  Service label: \(config.serviceLabel)")
    Diagnostics.remark("  Port: \(port)")
    Diagnostics.remark("  Products: \(config.products.joined(separator: ", "))")

    // Build products or use existing artifacts
    var artifactURLs: [URL] = []

    if skipBuild {
      // Use pre-built artifacts from .build/release/ directly
      // This avoids triggering build plugins (like gRPC) that may have sandbox issues
      let releaseDir = context.package.directoryURL
        .appendingPathComponent(".build/release")

      Diagnostics.remark("  Using pre-built artifacts from .build/release/")

      for product in config.products {
        let artifactPath = releaseDir.appendingPathComponent(product)
        if FileManager.default.fileExists(atPath: artifactPath.path) {
          artifactURLs.append(artifactPath)
          Diagnostics.remark("    Found: \(product)")
        } else {
          Diagnostics.error("  Pre-built artifact not found: \(product)")
          Diagnostics.error("  Run 'swift build -c release' first, then retry with --skip-build")
          throw PluginError.artifactsNotFound
        }
      }
    } else {
      // Build all products and collect artifacts
      for product in config.products {
        Diagnostics.remark("  Building: \(product)")

        let result = try packageManager.build(
          .product(product),
          parameters: .init(configuration: .release)
        )

        guard result.succeeded else {
          Diagnostics.error("Build failed for \(product)")
          throw PluginError.buildFailed(product)
        }

        let productArtifacts = result.builtArtifacts.filter { artifact in
          config.products.contains(artifact.url.lastPathComponent)
        }
        artifactURLs.append(contentsOf: productArtifacts.map(\.url))

        Diagnostics.remark("    Built: \(product)")
      }
    }

    // Deduplicate by path
    let uniqueArtifacts = Array(Set(artifactURLs))

    guard !uniqueArtifacts.isEmpty else {
      throw PluginError.artifactsNotFound
    }

    // Install binaries to package's bin/ directory (sandbox-safe)
    // User creates symlinks to ~/.swiftpm/bin/ for PATH access
    let packageBin = context.package.directoryURL.appendingPathComponent("bin")

    do {
      try FileManager.default.createDirectory(
        at: packageBin,
        withIntermediateDirectories: true
      )
    } catch {
      throw PluginError.installationFailed(
        "Failed to create directory \(packageBin.path): \(error.localizedDescription)"
      )
    }

    // Atomic binary installation using atomic-install-tool
    // (Plugins can't import library targets directly - SE-0303)
    Diagnostics.remark("  Installing binaries to package bin/ directory...")

    let tool = try context.tool(named: "atomic-install-tool")

    // Build operations JSON - install to package bin/
    let operations = uniqueArtifacts.map { artifactURL -> [String: String] in
      let destination = packageBin.appendingPathComponent(artifactURL.lastPathComponent)
      return [
        "source": artifactURL.path,
        "destination": destination.path,
      ]
    }

    let operationsJSON: String
    do {
      let jsonData = try JSONSerialization.data(withJSONObject: operations, options: [])
      operationsJSON = String(data: jsonData, encoding: .utf8) ?? "[]"
    } catch {
      throw PluginError.installationFailed("Failed to encode operations: \(error)")
    }

    // Run the atomic install tool
    let process = Process()
    process.executableURL = tool.url
    process.arguments = ["install", "--operations", operationsJSON, "--json"]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      throw PluginError.installationFailed("Failed to run atomic-install-tool: \(error)")
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    if process.terminationStatus != 0 {
      // Tool failed - parse JSON output for detailed error
      if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
        // The tool outputs the full error message with rollback status
        Diagnostics.error(output)
      }
      if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
        Diagnostics.error(errorOutput)
      }
      throw PluginError.installationFailed("Binary installation failed (see above for details)")
    }

    // Parse success output
    if let output = String(data: outputData, encoding: .utf8),
      let jsonData = output.data(using: .utf8),
      let result = try? JSONDecoder().decode(InstallToolOutput.self, from: jsonData)
    {
      for file in result.installedFiles {
        Diagnostics.remark("    Installed: \(file)")
      }
      if result.backupsCreated > 0 {
        Diagnostics.remark("    Backups created: \(result.backupsCreated)")
      }
    }

    // Generate plist to package directory (sandbox-safe)
    // User copies to ~/Library/LaunchAgents/ manually
    let swiftpmBin = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".swiftpm/bin")

    if let daemonProduct = config.daemonProduct {
      let plist = generatePlist(
        config: config,
        daemonProduct: daemonProduct,
        swiftpmBin: swiftpmBin.path,  // Plist references symlinked location
        port: port,
        logLevel: logLevel
      )

      let plistPath = packageBin.appendingPathComponent("\(config.serviceLabel).plist")
      try plist.write(to: plistPath, atomically: true, encoding: .utf8)

      Diagnostics.remark("  Generated plist: \(plistPath.path)")
    }

    // Print setup instructions
    Diagnostics.remark("")
    Diagnostics.remark("═══════════════════════════════════════════════════════════")
    Diagnostics.remark("  BUILD COMPLETE - Manual setup required (one-time)")
    Diagnostics.remark("═══════════════════════════════════════════════════════════")
    Diagnostics.remark("")
    Diagnostics.remark("Step 1: Create symlinks to ~/.swiftpm/bin/")
    Diagnostics.remark("  cd \(context.package.directoryURL.path)")
    Diagnostics.remark("  ln -sf $(pwd)/bin/* ~/.swiftpm/bin/")
    Diagnostics.remark("")

    if config.daemonProduct != nil {
      Diagnostics.remark("Step 2: Install LaunchAgent plist")
      Diagnostics.remark("  cp bin/\(config.serviceLabel).plist ~/Library/LaunchAgents/")
      Diagnostics.remark("  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/\(config.serviceLabel).plist")
      Diagnostics.remark("")
    }

    Diagnostics.remark("Step 3: Add to ~/.claude/settings.json:")
    Diagnostics.remark(
      """
      {
        "mcpServers": {
          "\(config.name)": {
            "command": "\(config.products.first ?? config.name)",
            "args": ["--log-level", "\(logLevel)"],
            "env": {
              "PATH": "\(swiftpmBin.path):/usr/local/bin:/usr/bin:/bin"
            }
          }
        }
      }
      """)
    Diagnostics.remark("")
    Diagnostics.remark("Future rebuilds will automatically update via symlinks!")
  }

  private func performUninstall(
    context: PluginContext,
    config: DaemonPluginConfig
  ) async throws {
    Diagnostics.remark("Uninstalling daemon: \(config.name)")

    // Stop and unload service
    let uid = getuid()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["bootout", "gui/\(uid)/\(config.serviceLabel)"]

    do {
      try process.run()
      process.waitUntilExit()
      if process.terminationStatus == 0 {
        Diagnostics.remark("  Service unloaded successfully")
      } else {
        Diagnostics.warning(
          "  Service may not have been loaded (exit code: \(process.terminationStatus))")
      }
    } catch {
      Diagnostics.warning("  Could not unload service: \(error.localizedDescription)")
    }

    // Remove plist
    let plistPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(config.serviceLabel).plist")
    do {
      try FileManager.default.removeItem(at: plistPath)
      Diagnostics.remark("  Plist removed: \(plistPath.path)")
    } catch {
      Diagnostics.warning("  Could not remove plist: \(error.localizedDescription)")
    }
    Diagnostics.remark("  Note: Binaries left in ~/.swiftpm/bin/ (remove manually if needed)")
  }

  private func generatePlist(
    config: DaemonPluginConfig,
    daemonProduct: String,
    swiftpmBin: String,
    port: Int,
    logLevel: String
  ) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path

    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>\(config.serviceLabel)</string>

          <key>ProgramArguments</key>
          <array>
              <string>\(swiftpmBin)/\(daemonProduct)</string>
              <string>--port</string>
              <string>\(port)</string>
              <string>--log-level</string>
              <string>\(logLevel)</string>
          </array>

          <key>RunAtLoad</key>
          <true/>

          <key>KeepAlive</key>
          <dict>
              <key>SuccessfulExit</key>
              <false/>
          </dict>

          <key>ThrottleInterval</key>
          <integer>10</integer>

          <key>ProcessType</key>
          <string>Background</string>

          <key>StandardOutPath</key>
          <string>\(home)/Library/Logs/\(config.name)/daemon.log</string>

          <key>StandardErrorPath</key>
          <string>\(home)/Library/Logs/\(config.name)/daemon.err</string>

          <key>EnvironmentVariables</key>
          <dict>
              <key>PATH</key>
              <string>\(swiftpmBin):/usr/local/bin:/usr/bin:/bin</string>
              <key>HOME</key>
              <string>\(home)</string>
          </dict>

          <key>WorkingDirectory</key>
          <string>\(home)/.cache/\(config.name)</string>
      </dict>
      </plist>
      """

    return plist
  }
}

struct DaemonPluginConfig: Codable {
  let name: String
  let serviceLabel: String
  let products: [String]
  let daemonProduct: String?
  let defaultPort: Int?
  let portRange: [Int]?
  let logDirectory: String?
  let cacheDirectory: String?
}

/// Output from atomic-install-tool for JSON parsing
struct InstallToolOutput: Codable {
  let success: Bool
  let installedFiles: [String]
  let backupsCreated: Int
  let operationID: String
  let error: String?
}

enum PluginError: Error, CustomStringConvertible {
  case configNotFound
  case buildFailed(String)
  case artifactsNotFound
  case scriptFailed
  case installationFailed(String)

  var description: String {
    switch self {
    case .configNotFound:
      return "daemon-config.json not found"
    case .buildFailed(let product):
      return "Build failed for \(product)"
    case .artifactsNotFound:
      return "No build artifacts found"
    case .scriptFailed:
      return "Installation script failed"
    case .installationFailed(let message):
      return "Binary installation failed: \(message)"
    }
  }
}
