# PromptPingFoundation

Swift 6.1 library for daemon installation, macOS launchd service management, and atomic file operations. Targets macOS 15+ and provides reusable infrastructure for installing MCP servers and other background services.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/doozMen/promptping-foundation.git", from: "0.1.0")
]
```

## Components

- **PromptPingFoundation** - Core library with subprocess execution, atomic file operations, port management, and launchd integration
- **BumpVersion** - Generic semantic versioning library for version bumping across projects
- **InstallDaemon** - SPM command plugin for daemon installation

## Plugin Naming Convention

The InstallDaemonPlugin follows Swift Package Manager's plugin naming conventions:

| Aspect | Value | Description |
|--------|-------|-------------|
| Directory | `Plugins/InstallDaemonPlugin/` | Matches target name |
| Target name | `InstallDaemonPlugin` | Internal SPM identifier |
| Product name | `InstallDaemon` | Exposed to consumers |
| Command verb | `install-daemon` | User-facing CLI command |

### Usage

```bash
# Invoke via SPM command
swift package install-daemon --port 50052

# With options
swift package install-daemon --uninstall
swift package install-daemon --skip-build --log-level debug
```

This naming convention ensures the plugin directory matches the target name while the product name (without "Plugin" suffix) is what package consumers reference in their dependencies.

## Build Commands

```bash
# Build
swift build

# Test
swift test

# Format (lint check)
swift format lint -s -p -r Sources Tests Package.swift

# Format (auto-fix)
swift format format -p -r -i Sources Tests Package.swift
```

## License

MIT
