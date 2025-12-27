// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "promptping-foundation",
  platforms: [.macOS(.v26)],
  products: [
    .library(
      name: "PromptPingFoundation",
      targets: ["PromptPingFoundation"]
    ),
    .library(
      name: "BumpVersion",
      targets: ["BumpVersion"]
    ),
    .executable(
      name: "bump-version",
      targets: ["bump-version"]
    ),
    .library(
      name: "PRComments",
      targets: ["PRComments"]
    ),
    .executable(
      name: "pr-comments",
      targets: ["pr-comments"]
    ),
    .executable(
      name: "install-daemon",
      targets: ["install-daemon"]
    ),
    .plugin(
      name: "InstallDaemon",
      targets: ["InstallDaemonPlugin"]
    ),
    // Plugin installation library (generic installer for Claude Code plugins)
    .library(
      name: "PluginInstall",
      targets: ["PluginInstall"]
    ),
    .executable(
      name: "plugin-install",
      targets: ["plugin-install"]
    ),
  ],
  dependencies: [
    // Modern async subprocess execution
    .package(
      url: "https://github.com/swiftlang/swift-subprocess.git",
      from: "0.1.0"
    ),
    // Semantic versioning (from Swift Package Index team)
    .package(
      url: "https://github.com/SwiftPackageIndex/SemanticVersion.git",
      from: "0.4.0"
    ),
    // Logging
    .package(
      url: "https://github.com/apple/swift-log.git",
      from: "1.5.0"
    ),
    // CLI argument parsing for atomic-install-tool
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      from: "1.3.0"
    ),
    // Markdown parsing for translation preservation
    .package(
      url: "https://github.com/swiftlang/swift-markdown.git",
      from: "0.5.0"
    ),
  ],
  targets: [
    // Main library
    .target(
      name: "PromptPingFoundation",
      dependencies: [
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    // Atomic installation library (testable, used by plugin via executable)
    .target(
      name: "AtomicInstall",
      dependencies: []
    ),

    // Version bumping library (generic, reusable across org)
    .target(
      name: "BumpVersion",
      dependencies: [
        .product(name: "SemanticVersion", package: "SemanticVersion"),
        .product(name: "Subprocess", package: "swift-subprocess"),
      ]
    ),

    // Generic version bump CLI tool (installable via swift package experimental-install)
    .executableTarget(
      name: "bump-version",
      dependencies: [
        "BumpVersion",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // PR comments library (parses and formats GitHub PR comments)
    .target(
      name: "PRComments",
      dependencies: [
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      linkerSettings: [
        // Translation.framework for neural machine translation (iOS 17.4+ / macOS 14.4+)
        // NOT FoundationModels - Translation has no context limits and is purpose-built
        .linkedFramework("Translation", .when(platforms: [.macOS, .iOS]))
      ]
    ),

    // PR comments CLI tool (installable via swift package experimental-install)
    .executableTarget(
      name: "pr-comments",
      dependencies: [
        "PRComments",
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      exclude: ["README.md"]
    ),

    // Daemon installation CLI tool (installable via swift package experimental-install)
    // Bypasses SPM plugin sandbox limitations for packages with complex build plugins (gRPC)
    .executableTarget(
      name: "install-daemon",
      dependencies: [
        "PromptPingFoundation",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),

    // Executable for plugin to invoke (plugins can't import libraries directly)
    // See SE-0303: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0303-swiftpm-extensible-build-tools.md
    .executableTarget(
      name: "atomic-install-tool",
      dependencies: [
        "AtomicInstall",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // Plugin invokes the executable tool
    .plugin(
      name: "InstallDaemonPlugin",
      capability: .command(
        intent: .custom(
          verb: "install-daemon",
          description: "Install daemon with launchd service"
        ),
        permissions: [
          .writeToPackageDirectory(reason: "Install binaries and plist files")
        ]
      ),
      dependencies: [
        .target(name: "atomic-install-tool")
      ]
    ),

    // Plugin installation library (generic installer for Claude Code plugins)
    .target(
      name: "PluginInstall",
      dependencies: []
    ),

    // Plugin installation CLI tool (installable via swift package experimental-install)
    .executableTarget(
      name: "plugin-install",
      dependencies: [
        "PluginInstall",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),

    // Tests
    .testTarget(
      name: "PromptPingFoundationTests",
      dependencies: ["PromptPingFoundation"]
    ),
    .testTarget(
      name: "AtomicInstallTests",
      dependencies: ["AtomicInstall"]
    ),
    .testTarget(
      name: "BumpVersionTests",
      dependencies: ["BumpVersion"]
    ),
    .testTarget(
      name: "PRCommentsTests",
      dependencies: ["PRComments"]
    ),
  ]
)
