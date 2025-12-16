import Foundation
import Subprocess
import System

/// Manages GitHub releases via the gh CLI
/// Uses swift-subprocess for proper async execution and timeout support
public actor GitHubReleaseManager {

  public init() {}

  /// Check if gh CLI is available
  /// - Throws: `GitHubReleaseError.ghCheckFailed` if the check itself fails
  /// - Returns: `true` if gh is installed and available, `false` if not found
  public func isGHAvailable() async throws -> Bool {
    do {
      let result = try await run(
        .name("which"),
        arguments: ["gh"],
        output: .string(limit: 1024)
      )
      return result.terminationStatus.isSuccess
    } catch {
      throw GitHubReleaseError.ghCheckFailed(reason: error.localizedDescription)
    }
  }

  /// Check if we're in a git repository
  /// This is nonisolated because it's a pure file-system check with no actor state
  public nonisolated func isGitRepository(at directory: URL) -> Bool {
    let gitPath = directory.appendingPathComponent(".git")
    // .git can be a directory (normal repo) or file (worktree/submodule)
    return FileManager.default.fileExists(atPath: gitPath.path)
  }

  /// Check if a git tag exists for the version
  public func tagExists(_ version: SemanticVersion, in directory: URL) async throws -> Bool {
    let tag = "v\(version)"
    let result = try await runGit(
      arguments: ["tag", "-l", tag],
      workingDirectory: directory
    )

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.tagCheckFailed(tag: tag, reason: result.standardError)
    }

    return !result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Create a git tag for the version
  public func createTag(_ version: SemanticVersion, in directory: URL, message: String? = nil)
    async throws
  {
    let tag = "v\(version)"
    var arguments = ["tag"]

    if let message {
      arguments += ["-a", tag, "-m", message]
    } else {
      arguments.append(tag)
    }

    let result = try await runGit(arguments: arguments, workingDirectory: directory)

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.tagCreationFailed(tag: tag, reason: result.standardError)
    }
  }

  /// Push tag to remote
  public func pushTag(_ version: SemanticVersion, in directory: URL) async throws {
    let tag = "v\(version)"
    let result = try await runGit(
      arguments: ["push", "origin", tag],
      workingDirectory: directory
    )

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.pushFailed(tag: tag, reason: result.standardError)
    }
  }

  /// Create a GitHub release using gh CLI
  public func createRelease(
    version: SemanticVersion,
    title: String? = nil,
    notes: String? = nil,
    notesFile: URL? = nil,
    isPrerelease: Bool? = nil,
    isDraft: Bool = false,
    generateNotes: Bool = false,
    in directory: URL
  ) async throws -> String {
    guard try await isGHAvailable() else {
      throw GitHubReleaseError.ghNotAvailable
    }

    let tag = "v\(version)"
    var arguments = ["release", "create", tag]

    // Title
    if let title {
      arguments += ["--title", title]
    } else {
      arguments += ["--title", "Release \(version)"]
    }

    // Notes
    if let notesFile {
      arguments += ["--notes-file", notesFile.path]
    } else if let notes {
      arguments += ["--notes", notes]
    } else if generateNotes {
      arguments.append("--generate-notes")
    } else {
      arguments += ["--notes", "Release \(version)"]
    }

    // Prerelease (auto-detect from version if not specified)
    let prerelease = isPrerelease ?? version.isPreRelease
    if prerelease {
      arguments.append("--prerelease")
    }

    // Draft
    if isDraft {
      arguments.append("--draft")
    }

    let result = try await runGH(arguments: arguments, workingDirectory: directory)

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.releaseCreationFailed(tag: tag, reason: result.standardError)
    }

    return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Extract release notes from CHANGELOG.md for a specific version
  /// This is nonisolated because it's a pure file-reading operation with no actor state
  public nonisolated func extractChangelogNotes(
    for version: SemanticVersion,
    changelogPath: URL
  ) throws -> String? {
    guard FileManager.default.fileExists(atPath: changelogPath.path) else {
      return nil
    }

    let content = try String(contentsOf: changelogPath, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)

    var inVersion = false
    var notes: [String] = []
    let versionHeader = "## [\(version)]"
    let altVersionHeader = "## [v\(version)]"
    let plainHeader = "## \(version)"

    for line in lines {
      if line.hasPrefix(versionHeader) || line.hasPrefix(altVersionHeader)
        || line.hasPrefix(plainHeader)
      {
        inVersion = true
        continue
      }

      if inVersion {
        // Stop at next version header
        if line.hasPrefix("## [") || (line.hasPrefix("## ") && !line.hasPrefix("### ")) {
          break
        }
        notes.append(line)
      }
    }

    let result = notes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }

  // MARK: - Git Operations for Command

  /// Stage all changes
  public func gitAdd(in directory: URL) async throws {
    let result = try await runGit(arguments: ["add", "-A"], workingDirectory: directory)

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.gitOperationFailed(
        operation: "add",
        reason: result.standardError
      )
    }
  }

  /// Commit staged changes
  public func gitCommit(message: String, in directory: URL) async throws {
    let result = try await runGit(
      arguments: ["commit", "-m", message],
      workingDirectory: directory
    )

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.gitOperationFailed(
        operation: "commit",
        reason: result.standardError
      )
    }
  }

  /// Push to remote
  public func gitPush(in directory: URL) async throws {
    let result = try await runGit(arguments: ["push"], workingDirectory: directory)

    guard result.terminationStatus.isSuccess else {
      throw GitHubReleaseError.gitOperationFailed(
        operation: "push",
        reason: result.standardError
      )
    }
  }

  // MARK: - Private Helpers

  private struct ProcessResult {
    let standardOutput: String
    let standardError: String
    let terminationStatus: TerminationStatus
  }

  private func runGit(arguments: [String], workingDirectory: URL) async throws -> ProcessResult {
    let result = try await run(
      .path("/usr/bin/git"),
      arguments: Arguments(arguments),
      workingDirectory: FilePath(workingDirectory.path),
      output: .string(limit: 1024 * 1024),  // 1MB limit
      error: .string(limit: 1024 * 1024)
    )

    return ProcessResult(
      standardOutput: result.standardOutput ?? "",
      standardError: result.standardError ?? "",
      terminationStatus: result.terminationStatus
    )
  }

  private func runGH(arguments: [String], workingDirectory: URL) async throws -> ProcessResult {
    let result = try await run(
      .name("gh"),
      arguments: Arguments(arguments),
      workingDirectory: FilePath(workingDirectory.path),
      output: .string(limit: 1024 * 1024),  // 1MB limit
      error: .string(limit: 1024 * 1024)
    )

    return ProcessResult(
      standardOutput: result.standardOutput ?? "",
      standardError: result.standardError ?? "",
      terminationStatus: result.terminationStatus
    )
  }
}

// MARK: - TerminationStatus Extension

extension TerminationStatus {
  var isSuccess: Bool {
    switch self {
    case .exited(let code):
      return code == 0
    default:
      return false
    }
  }
}

/// Errors from GitHub release operations
public enum GitHubReleaseError: Error, Sendable, CustomStringConvertible {
  case ghNotAvailable
  case ghCheckFailed(reason: String)
  case notAGitRepository
  case tagCheckFailed(tag: String, reason: String)
  case tagCreationFailed(tag: String, reason: String)
  case pushFailed(tag: String, reason: String)
  case releaseCreationFailed(tag: String, reason: String)
  case gitOperationFailed(operation: String, reason: String)

  public var description: String {
    switch self {
    case .ghNotAvailable:
      return "GitHub CLI (gh) is not available. Install with: brew install gh"
    case .ghCheckFailed(let reason):
      return "Failed to check for GitHub CLI: \(reason)"
    case .notAGitRepository:
      return "Not a git repository"
    case .tagCheckFailed(let tag, let reason):
      return "Failed to check if tag \(tag) exists: \(reason)"
    case .tagCreationFailed(let tag, let reason):
      return "Failed to create tag \(tag): \(reason)"
    case .pushFailed(let tag, let reason):
      return "Failed to push tag \(tag): \(reason)"
    case .releaseCreationFailed(let tag, let reason):
      return "Failed to create release \(tag): \(reason)"
    case .gitOperationFailed(let operation, let reason):
      return "Git \(operation) failed: \(reason)"
    }
  }
}
