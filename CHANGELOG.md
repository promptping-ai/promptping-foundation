# Changelog

All notable changes to promptping-foundation will be documented in this file.

## [0.2.0-alpha.1] - 2025-12-23

### Added

- **pr-comments CLI** - Multi-provider CLI tool for viewing and interacting with PR/MR comments
  - Supports GitHub (`gh`), GitLab (`glab`), and Azure DevOps (`az`) providers
  - Auto-detects provider from git remote or manual `--provider` override
  - On-device French↔English translation via Apple's Translation.framework
  - Extracts and displays inline code review comments with context
  - Multiple output formats: terminal (colored), markdown, JSON

- **Subcommands:**
  - `view` - Display PR comments with optional translation
  - `reply` - Reply to a PR with optional translation
  - `reply-to` - Reply to a specific comment or thread
  - `resolve` - Resolve a discussion thread (GitLab/Azure)

- **PRComments Library** - Reusable components for PR comment management
  - `PRProvider` protocol with GitHub, GitLab, Azure implementations
  - `TranslationService` using Translation.framework
  - `MarkdownPreserver` for maintaining formatting during translation
  - `PRCommentsFormatter` for multiple output formats

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

### Testing

- Comprehensive unit tests for AtomicBinaryInstaller (8 tests)
- Integration tests for concurrent and batch operations (12 tests)
- LaunchAgentManager tests including error 5 handling (8 tests)

### CI/CD

- Swift rules-check workflow (XCTest ban, Any type ban, stub detection, formatting)
- Claude Code review integration
- Graphite CI optimization

### Technical

- Swift 6.1 with strict concurrency (`Sendable` compliance)
- Typed throws using `any Error & Sendable` pattern
- macOS 15+ target platform
- Re-exports `Logging` framework for consumers
