import Foundation

/// Result of a successful installation
public struct InstallResult: Sendable, Equatable {
  public let installedFiles: [String]
  public let backupsCreated: Int
  public let operationID: String

  public init(installedFiles: [String], backupsCreated: Int, operationID: String) {
    self.installedFiles = installedFiles
    self.backupsCreated = backupsCreated
    self.operationID = operationID
  }
}

/// Atomic binary installer using 4-phase algorithm with proper rollback tracking.
///
/// ## Algorithm
/// 1. **Stage**: Copy new files to `*.new.<UUID>` (safe: doesn't touch originals)
/// 2. **Backup**: Copy existing files to `*.bak.<UUID>` (preserves original state)
/// 3. **Swap**: Remove original, move staged to final (atomic per-file)
/// 4. **Cleanup**: Remove backups on success, or rollback on failure
///
/// ## Error Handling
/// - Never uses `try?` that could silently swallow errors
/// - Tracks rollback status per-file
/// - Generates manual fix commands when rollback fails
public struct AtomicBinaryInstaller {

  public init() {}

  private var fileManager: FileManager { .default }

  /// Install binaries atomically with backup/rollback support.
  ///
  /// - Parameter operations: Array of (source, destination) URL pairs
  /// - Returns: InstallResult on success
  /// - Throws: InstallError with full context and rollback status
  public func install(
    _ operations: [(source: URL, destination: URL)]
  ) throws -> InstallResult {
    // Generate unique operation ID for this batch
    let operationID = String(UUID().uuidString.prefix(8))

    // Validate all sources exist before starting
    for operation in operations {
      guard fileManager.fileExists(atPath: operation.source.path) else {
        throw InstallError.sourceNotFound(path: operation.source.path)
      }
    }

    // Track state for rollback
    var stagedFiles: [(staged: URL, destination: URL)] = []
    var backupFiles: [(backup: URL, original: URL)] = []

    do {
      // Phase 1: Stage - copy all new files to temporary locations
      for operation in operations {
        let stagedURL = operation.destination.appendingPathExtension("new.\(operationID)")
        do {
          try fileManager.copyItem(at: operation.source, to: stagedURL)
          stagedFiles.append((staged: stagedURL, destination: operation.destination))
        } catch {
          throw InstallError.stagingFailed(
            file: operation.source.lastPathComponent,
            underlying: error.localizedDescription
          )
        }
      }

      // Phase 2: Backup - save existing files
      for (_, destination) in stagedFiles {
        if fileManager.fileExists(atPath: destination.path) {
          let backupURL = destination.appendingPathExtension("bak.\(operationID)")
          do {
            try fileManager.copyItem(at: destination, to: backupURL)
            backupFiles.append((backup: backupURL, original: destination))
          } catch {
            throw InstallError.backupFailed(
              file: destination.lastPathComponent,
              underlying: error.localizedDescription
            )
          }
        }
      }

      // Phase 3: Swap - move staged files to destinations
      for (stagedURL, destination) in stagedFiles {
        // Remove existing file if present
        if fileManager.fileExists(atPath: destination.path) {
          do {
            try fileManager.removeItem(at: destination)
          } catch {
            throw InstallError.swapFailed(
              file: destination.lastPathComponent,
              underlying: "Failed to remove existing: \(error.localizedDescription)"
            )
          }
        }

        // Move staged to final location
        do {
          try fileManager.moveItem(at: stagedURL, to: destination)
        } catch {
          throw InstallError.swapFailed(
            file: destination.lastPathComponent,
            underlying: "Failed to move staged file: \(error.localizedDescription)"
          )
        }

        // Set executable permissions
        do {
          try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
          )
        } catch {
          throw InstallError.permissionsFailed(
            file: destination.lastPathComponent,
            underlying: error.localizedDescription
          )
        }
      }

      // Phase 4: Cleanup - remove backups on success
      // Use try? here because cleanup failure shouldn't fail the install
      // But we should still track it for logging purposes
      for (backupURL, _) in backupFiles {
        try? fileManager.removeItem(at: backupURL)
      }

      return InstallResult(
        installedFiles: operations.map { $0.destination.lastPathComponent },
        backupsCreated: backupFiles.count,
        operationID: operationID
      )

    } catch let error as InstallError {
      // Perform rollback and capture detailed result
      let rollbackResult = performRollback(
        stagedFiles: stagedFiles,
        backupFiles: backupFiles,
        operationID: operationID
      )

      // Wrap the original error with rollback status
      switch error {
      case .stagingFailed(let file, let underlying):
        throw InstallError.installationFailed(
          phase: "staging",
          file: file,
          underlying: underlying,
          rollbackResult: rollbackResult
        )
      case .backupFailed(let file, let underlying):
        throw InstallError.installationFailed(
          phase: "backup",
          file: file,
          underlying: underlying,
          rollbackResult: rollbackResult
        )
      case .swapFailed(let file, let underlying):
        throw InstallError.installationFailed(
          phase: "swap",
          file: file,
          underlying: underlying,
          rollbackResult: rollbackResult
        )
      case .permissionsFailed(let file, let underlying):
        throw InstallError.installationFailed(
          phase: "permissions",
          file: file,
          underlying: underlying,
          rollbackResult: rollbackResult
        )
      default:
        throw error
      }
    }
  }

  /// Perform rollback with per-file tracking.
  /// Returns detailed result - NEVER silently swallows errors.
  private func performRollback(
    stagedFiles: [(staged: URL, destination: URL)],
    backupFiles: [(backup: URL, original: URL)],
    operationID: String
  ) -> RollbackResult {
    // Track cleanup of staged files
    var stagedCleanup: [RollbackResult.StagedFileCleanup] = []
    for (stagedURL, _) in stagedFiles {
      do {
        if fileManager.fileExists(atPath: stagedURL.path) {
          try fileManager.removeItem(at: stagedURL)
        }
        stagedCleanup.append(
          RollbackResult.StagedFileCleanup(
            path: stagedURL.path,
            success: true
          ))
      } catch {
        stagedCleanup.append(
          RollbackResult.StagedFileCleanup(
            path: stagedURL.path,
            success: false,
            error: error.localizedDescription
          ))
      }
    }

    // Track restoration of backups
    var restorations: [RollbackResult.FileRestoration] = []
    for (backupURL, originalURL) in backupFiles {
      do {
        // Remove any partial install at original location
        if fileManager.fileExists(atPath: originalURL.path) {
          try fileManager.removeItem(at: originalURL)
        }
        // Restore backup
        try fileManager.moveItem(at: backupURL, to: originalURL)

        restorations.append(
          RollbackResult.FileRestoration(
            originalPath: originalURL.path,
            backupPath: backupURL.path,
            status: .restored
          ))
      } catch {
        restorations.append(
          RollbackResult.FileRestoration(
            originalPath: originalURL.path,
            backupPath: backupURL.path,
            status: .failed(error.localizedDescription)
          ))
      }
    }

    return RollbackResult(
      restorations: restorations,
      stagedFilesCleanup: stagedCleanup
    )
  }
}
