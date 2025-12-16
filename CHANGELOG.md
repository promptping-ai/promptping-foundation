# Changelog

All notable changes to promptping-foundation will be documented in this file.

## [0.1.0] - 2025-12-17

### Added

- **AtomicInstall Library** - 4-phase atomic binary installation with rollback support
  - Stage → Backup → Swap → Cleanup algorithm
  - Full rollback tracking with `RollbackResult` type
  - Manual recovery commands generation on failure
  - `cleanupWarnings` field for non-fatal cleanup failures

- **DaemonInstaller** - High-level orchestrator using Strategy pattern
  - Composable `InstallStep` protocol for custom pipelines
  - Built-in steps: Build, Port, Stop, InstallBinaries, Plist, Bootstrap
  - Configurable via `DaemonConfig`, `BinaryConfig`, `ServiceConfig`

- **LaunchAgentManager** - macOS launchd service lifecycle management
  - Bootstrap, bootout, kickstart, kill operations
  - Error 5 handling with kickstart fallback
  - Plist generation and installation
  - Service status checking

- **SubprocessRunner** - Modern async subprocess execution
  - Typed `Executable` enum with validation factory methods
  - `absolutePath()` and `executableName()` for safe executable lookup

- **InstallDaemon Plugin** - SPM command plugin for daemon installation
  - `swift package install-daemon` command
  - Reads `daemon-config.json` for configuration
  - Options: `--port`, `--skip-build`, `--uninstall`, `--log-level`

- **PortManager** - Port detection and allocation via lsof

- **BumpVersion Library & CLI** - Generic version bump tool for Swift packages
  - Semantic versioning support (major/minor/patch)
  - Prerelease versions (alpha/beta/rc)
  - GitHub release creation via `gh` CLI
  - CHANGELOG extraction for release notes
  - Installable globally via `swift package experimental-install`

### Testing

- Comprehensive unit tests for AtomicBinaryInstaller (8 tests)
- Integration tests for concurrent and batch operations (12 tests)
- LaunchAgentManager tests including error 5 handling (8 tests)
- SemanticVersion and VersionFileManager tests (28 tests)

### CI/CD

- Swift rules-check workflow (XCTest ban, Any type ban, stub detection, formatting)
- Claude Code review integration
- Graphite CI optimization

### Technical

- Swift 6.1 with strict concurrency (`Sendable` compliance)
- Typed throws using `any Error & Sendable` pattern
- macOS 15+ target platform
- Re-exports `Logging` framework for consumers
