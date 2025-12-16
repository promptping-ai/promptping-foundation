import Foundation

/// Typed errors for atomic binary installation with full context preservation.
/// Each error case captures exactly what failed and the rollback status.
public enum InstallError: Error, Sendable, CustomStringConvertible {

  /// Source file validation failed before installation started
  case sourceNotFound(path: String)

  /// Failed to create destination directory
  case destinationDirectoryFailed(path: String, underlying: String)

  /// Phase 1: Failed to stage (copy) a new file to temporary location
  case stagingFailed(file: String, underlying: String)

  /// Phase 2: Failed to backup an existing file
  case backupFailed(file: String, underlying: String)

  /// Phase 3: Failed to swap staged file to final destination
  case swapFailed(file: String, underlying: String)

  /// Phase 3: Failed to set executable permissions
  case permissionsFailed(file: String, underlying: String)

  /// Installation failed at some phase, with rollback result
  case installationFailed(
    phase: String,
    file: String,
    underlying: String,
    rollbackResult: RollbackResult
  )

  public var description: String {
    switch self {
    case .sourceNotFound(let path):
      return "Source file not found: \(path)"

    case .destinationDirectoryFailed(let path, let underlying):
      return "Failed to create destination directory '\(path)': \(underlying)"

    case .stagingFailed(let file, let underlying):
      return "Staging failed for '\(file)': \(underlying)"

    case .backupFailed(let file, let underlying):
      return "Backup failed for '\(file)': \(underlying)"

    case .swapFailed(let file, let underlying):
      return "Swap failed for '\(file)': \(underlying)"

    case .permissionsFailed(let file, let underlying):
      return "Failed to set permissions on '\(file)': \(underlying)"

    case .installationFailed(let phase, let file, let underlying, let rollbackResult):
      var lines = [
        "INSTALLATION FAILED",
        "  Phase: \(phase)",
        "  File: \(file)",
        "  Error: \(underlying)",
        "",
        "ROLLBACK STATUS: \(rollbackResult.summary)",
      ]

      if !rollbackResult.successes.isEmpty {
        lines.append("")
        lines.append("SUCCESSFULLY RESTORED:")
        for restoration in rollbackResult.successes {
          lines.append("  - \(restoration.originalPath)")
        }
      }

      if !rollbackResult.failures.isEmpty {
        lines.append("")
        lines.append("FAILED TO RESTORE:")
        for restoration in rollbackResult.failures {
          if case .failed(let error) = restoration.status {
            lines.append("  - \(restoration.originalPath)")
            lines.append("    Backup at: \(restoration.backupPath)")
            lines.append("    Error: \(error)")
          }
        }

        lines.append("")
        lines.append("MANUAL RECOVERY COMMANDS:")
        for command in rollbackResult.manualFixCommands {
          lines.append("  \(command)")
        }
      }

      return lines.joined(separator: "\n")
    }
  }
}

extension InstallError: LocalizedError {
  public var errorDescription: String? {
    description
  }
}
