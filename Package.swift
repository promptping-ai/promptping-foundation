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
  ],
  targets: [
    .target(
      name: "PromptPingFoundation",
      dependencies: [
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
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
      )
    ),
    .testTarget(
      name: "PromptPingFoundationTests",
      dependencies: ["PromptPingFoundation"]
    ),
  ]
)
