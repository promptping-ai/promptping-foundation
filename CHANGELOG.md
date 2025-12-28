# Changelog

All notable changes to promptping-foundation will be documented in this file.

## [0.2.1] - 2025-12-28

### Added

- **Resolution Status Filtering** - Filter PR comments by thread resolution status
  - `--unresolved` flag shows only unresolved review threads
  - `--resolved` flag shows only resolved review threads
  - Status indicators: ✅ (resolved) and 🔴 (unresolved) displayed on comments
  - `isResolved` field added to `ReviewComment` model

- **Package-scoped Filter Utility**
  - `filterByResolutionStatus()` function with `package` access level
  - Graceful handling of unknown resolution status (includes by default)

### Changed

- `ReviewComment` now includes `isResolved: Bool?` field propagated from GraphQL thread data

## [0.2.0] - 2025-12-27

### Added

- **GitHub GraphQL Thread Resolution** - Full support for resolving PR review threads
  - `pr-comments resolve <pr> <thread-id>` command now works for GitHub
  - Uses `resolveReviewThread` GraphQL mutation
  - Thread IDs (`PRRT_xxx`) displayed on individual comments for easy copying
  - Validates thread ID format with helpful error messages

- **GraphQL Integration for GitHub Provider**
  - `CLIHelper.executeGraphQL()` for running GraphQL queries via `gh api graphql`
  - Fetches thread IDs from GraphQL and merges with REST API data
  - Graceful degradation if GraphQL fails (REST-only mode)

### Fixed

- **reply-to command** - Fixed 404 error when replying to review comments
  - GitHub API requires `POST /pulls/{pr}/comments` with `in_reply_to` parameter
  - Previously used non-existent `/pulls/comments/{id}/replies` endpoint

- **Thread ID display** - Removed confusing `Thread: PRR_xxx` from review headers
  - Review IDs (`PRR_`) are NOT thread IDs (`PRRT_`)
  - Thread IDs now shown only on individual comments where they're actionable

### Changed

- `ReviewComment.path` is now optional to support comments without file context
- `ReviewComment` has new `threadId` field for GraphQL thread resolution

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
  - `resolve` - Resolve a discussion thread (GitHub, GitLab, Azure)

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
