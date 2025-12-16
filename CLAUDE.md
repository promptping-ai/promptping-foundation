# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PromptPingFoundation is a Swift 6.1 library for daemon installation, macOS launchd service management, and atomic file operations. It targets macOS 15+ and provides reusable infrastructure for installing MCP servers and other background services.

## Build Commands

```bash
# Build
swift build

# Build with swiftbuild (cross-platform)
swift build --build-system swiftbuild

# Test
swift test

# Format (lint check)
swift format lint -s -p -r Sources Tests Package.swift

# Format (auto-fix)
swift format format -p -r -i Sources Tests Package.swift
```

## Architecture

### Core Components (all actors for thread safety)

**SubprocessRunner** - Modern async subprocess execution using Swift Subprocess API
- Wraps `swift-subprocess` with typed `Executable` enum for common tools (launchctl, lsof, swift, git)
- Factory methods `Executable.absolutePath()` and `Executable.executableName()` with validation

**AtomicFileManager** - Transactional file operations with rollback
- 4-phase algorithm: Stage (`.new.<UUID>`) → Backup (`.bak.<UUID>`) → Swap → Cleanup
- On failure: automatic rollback restores backups

**PortManager** - Port detection and allocation via lsof

**LaunchAgentManager** - macOS launchd service lifecycle
- Uses `gui/<uid>` domain for user LaunchAgents
- Operations: bootstrap, bootout, kickstart, kill

**DaemonInstaller** - High-level orchestrator using Strategy pattern
- Pipeline of `InstallStep` implementations: Build → Port → Stop → Install Binaries → Plist → Bootstrap
- Custom steps via `DaemonInstaller(context:steps:logger:)`

### SPM Plugin

**InstallDaemonPlugin** (`Plugins/InstallDaemon/`)
- Command plugin invoked via `swift package install-daemon`
- Reads `daemon-config.json` from package root for configuration
- Options: `--port`, `--skip-build`, `--uninstall`, `--log-level`

### Configuration Types

```swift
DaemonConfig       // Name, label, binaries, build options, port/service config
BinaryConfig       // Name, source path, isDaemon flag
PortConfig         // Default port, range, exclusions
ServiceConfig      // Plist generation (label, executable, args, env, keepAlive)
InstallContext     // Shared managers passed to InstallStep implementations
```

### Error Handling

Each domain has typed errors (Swift 6 typed throws):
- `SubprocessError` - Execution failures, non-zero exits
- `FileSystemError` - Atomic operation failures with rollback status
- `LaunchAgentError` - Bootstrap/bootout/kill failures
- `PortError` - Allocation failures
- `InstallerError` - High-level install failures

## Key Patterns

- **Actors everywhere** - All managers are actors for Sendable compliance
- **Typed throws** - `throws(ErrorType)` syntax throughout
- **Strategy pattern** - `InstallStep` protocol for extensible installation pipeline
- **@_exported imports** - Re-exports `Logging` for consumers

## Testing

Tests use Swift Testing framework (`@Test`, `#expect`), not XCTest.

```bash
# Run all tests
swift test

# Run specific test
swift test --filter "TestName"
```
