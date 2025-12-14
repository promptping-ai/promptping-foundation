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
            Diagnostics.remark("""
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

        // Build all products once and collect artifacts
        var allArtifacts: [PackageManager.BuildResult.BuiltArtifact] = []

        for product in config.products {
            if skipBuild {
                Diagnostics.remark("  Skipping build for: \(product)")
            } else {
                Diagnostics.remark("  Building: \(product)")
            }

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
            allArtifacts.append(contentsOf: productArtifacts)

            if !skipBuild {
                Diagnostics.remark("  Built: \(product)")
            }
        }

        // Deduplicate artifacts by URL
        let uniqueArtifacts = Dictionary(grouping: allArtifacts, by: \.url)
            .compactMapValues(\.first)
            .values

        guard !uniqueArtifacts.isEmpty else {
            throw PluginError.artifactsNotFound
        }

        let artifacts = Array(uniqueArtifacts)

        // Install binaries
        let swiftpmBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftpm/bin")

        try FileManager.default.createDirectory(
            at: swiftpmBin,
            withIntermediateDirectories: true
        )

        for artifact in artifacts {
            let source = artifact.url
            let destination = swiftpmBin.appendingPathComponent(artifact.url.lastPathComponent)

            // Remove existing
            try? FileManager.default.removeItem(at: destination)

            // Copy new
            try FileManager.default.copyItem(at: source, to: destination)

            // Make executable
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )

            Diagnostics.remark("  Installed: \(artifact.url.lastPathComponent)")
        }

        // Generate and install plist (if daemon product specified)
        if let daemonProduct = config.daemonProduct {
            let plist = generatePlist(
                config: config,
                daemonProduct: daemonProduct,
                swiftpmBin: swiftpmBin.path,
                port: port,
                logLevel: logLevel
            )

            let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents")

            try FileManager.default.createDirectory(
                at: launchAgentsDir,
                withIntermediateDirectories: true
            )

            let plistPath = launchAgentsDir.appendingPathComponent("\(config.serviceLabel).plist")
            try plist.write(to: plistPath, atomically: true, encoding: .utf8)

            Diagnostics.remark("  Installed plist: \(plistPath.path)")

            // Bootstrap service
            let uid = getuid()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["bootstrap", "gui/\(uid)", plistPath.path]

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    Diagnostics.remark("  Service loaded successfully")
                } else {
                    Diagnostics.warning("  Service may require manual loading")
                }
            } catch {
                Diagnostics.warning("  Could not load service: \(error)")
            }
        }

        Diagnostics.remark("")
        Diagnostics.remark("Installation complete!")
        Diagnostics.remark("")
        Diagnostics.remark("Add to ~/.claude/settings.json:")
        Diagnostics.remark("""
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

        try? process.run()
        process.waitUntilExit()

        // Remove plist
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(config.serviceLabel).plist")
        try? FileManager.default.removeItem(at: plistPath)

        Diagnostics.remark("  Service unloaded and plist removed")
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

enum PluginError: Error, CustomStringConvertible {
    case configNotFound
    case buildFailed(String)
    case artifactsNotFound
    case scriptFailed

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
        }
    }
}
