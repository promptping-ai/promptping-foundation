import Foundation

/// Tracks the outcome of rollback operations with per-file granularity.
/// Never use `Bool` for rollback status - we need to know exactly what succeeded/failed.
public struct RollbackResult: Sendable, Equatable {

  /// Status of restoring a single file from backup
  public enum RestorationStatus: Sendable, Equatable {
    /// Backup was successfully restored to original location
    case restored
    /// Failed to restore backup (with underlying error)
    case failed(String)
    /// File didn't exist before, no backup was needed
    case noBackupNeeded
  }

  /// Tracks the restoration of a single file
  public struct FileRestoration: Sendable, Equatable {
    public let originalPath: String
    public let backupPath: String
    public let status: RestorationStatus

    public init(originalPath: String, backupPath: String, status: RestorationStatus) {
      self.originalPath = originalPath
      self.backupPath = backupPath
      self.status = status
    }
  }

  /// Tracks cleanup of a staged file
  public struct StagedFileCleanup: Sendable, Equatable {
    public let path: String
    public let success: Bool
    public let error: String?

    public init(path: String, success: Bool, error: String? = nil) {
      self.path = path
      self.success = success
      self.error = error
    }
  }

  /// Results of restoring each backup
  public let restorations: [FileRestoration]

  /// Results of cleaning up staged files
  public let stagedFilesCleanup: [StagedFileCleanup]

  public init(restorations: [FileRestoration], stagedFilesCleanup: [StagedFileCleanup]) {
    self.restorations = restorations
    self.stagedFilesCleanup = stagedFilesCleanup
  }

  /// True only if ALL operations succeeded
  public var allSucceeded: Bool {
    let restorationsOK = restorations.allSatisfy { restoration in
      switch restoration.status {
      case .restored, .noBackupNeeded:
        return true
      case .failed:
        return false
      }
    }
    let cleanupOK = stagedFilesCleanup.allSatisfy(\.success)
    return restorationsOK && cleanupOK
  }

  /// Files that failed to restore
  public var failures: [FileRestoration] {
    restorations.filter { restoration in
      if case .failed = restoration.status {
        return true
      }
      return false
    }
  }

  /// Files that were successfully restored
  public var successes: [FileRestoration] {
    restorations.filter { restoration in
      if case .restored = restoration.status {
        return true
      }
      return false
    }
  }

  /// Generate shell commands for manual recovery
  public var manualFixCommands: [String] {
    failures.flatMap { restoration -> [String] in
      [
        "rm -f '\(restoration.originalPath)'",
        "mv '\(restoration.backupPath)' '\(restoration.originalPath)'",
        "chmod 755 '\(restoration.originalPath)'",
      ]
    }
  }

  /// Human-readable summary for logging
  public var summary: String {
    let total = restorations.count
    let succeeded = successes.count
    let failed = failures.count

    if allSucceeded {
      return "Rollback complete: \(succeeded) of \(total) files restored"
    } else {
      return "Rollback PARTIAL: \(succeeded) restored, \(failed) FAILED of \(total) total"
    }
  }
}
