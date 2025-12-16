// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "promptping-foundation",
  platforms: [.macOS(.v15)],
  products: [
    .library(
      name: "PromptPingFoundation",
      targets: ["PromptPingFoundation"]
    ),
    .plugin(
      name: "InstallDaemon",
      targets: ["InstallDaemonPlugin"]
    ),
  ],
  dependencies: [
    // Modern async subprocess execution
    .package(
      url: "https://github.com/swiftlang/swift-subprocess.git",
      from: "0.1.0"
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

    // Tests
    .testTarget(
      name: "PromptPingFoundationTests",
      dependencies: ["PromptPingFoundation"]
    ),
    .testTarget(
      name: "AtomicInstallTests",
      dependencies: ["AtomicInstall"]
    ),
  ]
)
