import Foundation
import Logging

/// Thread-safe file manager for atomic file operations with rollback support.
///
/// `AtomicFileManager` provides safe file installation operations that either
/// succeed completely or fail with automatic rollback. This is essential for
/// installing multiple related files (like binaries) where partial installation
/// would leave the system in an inconsistent state.
///
/// ## Example
///
/// ```swift
/// let fm = AtomicFileManager()
/// try await fm.atomicInstall([
///     (source: buildDir.appending("code-search-grpc"),
///      destination: swiftpmBin.appending("code-search-grpc")),
///     (source: buildDir.appending("code-search-mcp"),
///      destination: swiftpmBin.appending("code-search-mcp"))
/// ])
/// // Either BOTH succeed or BOTH are rolled back
/// ```
///
/// ## Atomic Install Algorithm
///
/// 1. **Stage**: Copy new files to temp locations (`*.new.<UUID>`)
/// 2. **Backup**: Copy existing files to backup locations (`*.bak.<UUID>`)
/// 3. **Swap**: Move staged files to final destinations
/// 4. **On success**: Delete backups
/// 5. **On failure**: Rollback - restore backups, delete staged files
public actor AtomicFileManager {
  private let fileManager: FileManager
  private let logger: Logger

  /// Initialize with optional custom logger
  ///
  /// - Parameter logger: Logger instance for operation logging
  public init(logger: Logger = Logger(label: "promptping.atomic-file-manager")) {
    self.fileManager = .default
    self.logger = logger
  }

  // MARK: - Public API

  /// Install multiple files atomically with rollback support.
  ///
  /// All files are installed together - either all succeed or all are rolled back.
  /// Existing files at destinations are backed up and restored on failure.
  ///
  /// - Parameter operations: Array of source/destination URL pairs
  /// - Throws: `FileSystemError` if installation fails
  public func atomicInstall(
    _ operations: [(source: URL, destination: URL)]
  ) async throws(FileSystemError) {
    guard !operations.isEmpty else {
      logger.debug("No operations to perform")
      return
    }

    let operationID = String(UUID().uuidString.prefix(8))
    logger.info(
      "Starting atomic install",
      metadata: [
        "operationID": "\(operationID)",
        "fileCount": "\(operations.count)",
      ]
    )

    // Validate all source files exist before starting
    for operation in operations {
      guard fileManager.fileExists(atPath: operation.source.path) else {
        throw .sourceNotFound(path: operation.source.path)
      }
    }

    // Track staged and backup files for cleanup/rollback
    var stagedFiles: [URL] = []
    var backupPairs: [(backup: URL, original: URL)] = []

    do {
      // Phase 1: Stage - copy new files to temporary locations
      logger.debug("Phase 1: Staging files", metadata: ["operationID": "\(operationID)"])
      for operation in operations {
        let stagedURL = operation.destination.appendingPathExtension("new.\(operationID)")

        try createDirectoryIfNeeded(at: operation.destination.deletingLastPathComponent())
        try copyFile(from: operation.source, to: stagedURL)

        stagedFiles.append(stagedURL)
        logger.debug(
          "Staged file",
          metadata: [
            "source": "\(operation.source.lastPathComponent)",
            "staged": "\(stagedURL.lastPathComponent)",
          ]
        )
      }

      // Phase 2: Backup - save existing files
      logger.debug("Phase 2: Creating backups", metadata: ["operationID": "\(operationID)"])
      for operation in operations {
        if fileManager.fileExists(atPath: operation.destination.path) {
          let backupURL = operation.destination.appendingPathExtension("bak.\(operationID)")
          try copyFile(from: operation.destination, to: backupURL)

          backupPairs.append((backup: backupURL, original: operation.destination))
          logger.debug(
            "Backed up file",
            metadata: [
              "original": "\(operation.destination.lastPathComponent)",
              "backup": "\(backupURL.lastPathComponent)",
            ]
          )
        }
      }

      // Phase 3: Swap - move staged files to final destinations
      logger.debug("Phase 3: Swapping files", metadata: ["operationID": "\(operationID)"])
      for (index, operation) in operations.enumerated() {
        let stagedURL = stagedFiles[index]
        try moveFile(from: stagedURL, to: operation.destination, overwrite: true)

        logger.debug(
          "Swapped file",
          metadata: ["destination": "\(operation.destination.lastPathComponent)"]
        )
      }

      // Phase 4: Cleanup - remove backups on success
      logger.debug("Phase 4: Cleaning up backups", metadata: ["operationID": "\(operationID)"])
      for pair in backupPairs {
        try? deleteFile(at: pair.backup)
      }

      logger.info(
        "Atomic install completed successfully",
        metadata: [
          "operationID": "\(operationID)",
          "installedFiles": "\(operations.count)",
        ]
      )

    } catch {
      logger.warning(
        "Atomic install failed, initiating rollback",
        metadata: [
          "operationID": "\(operationID)",
          "error": "\(error)",
        ]
      )

      let rollbackSucceeded = await rollback(
        stagedFiles: stagedFiles,
        backupPairs: backupPairs,
        operationID: operationID
      )

      throw .atomicOperationFailed(
        operation: "atomicInstall",
        underlying: String(describing: error),
        rollbackSucceeded: rollbackSucceeded
      )
    }
  }

  /// Create a directory if it doesn't exist, including intermediate directories.
  ///
  /// - Parameter url: URL of the directory to create
  /// - Throws: `FileSystemError.directoryCreationFailed` if creation fails
  public func ensureDirectory(at url: URL) throws(FileSystemError) {
    try createDirectoryIfNeeded(at: url)
  }

  /// Write content to a file atomically.
  ///
  /// - Parameters:
  ///   - content: String content to write
  ///   - url: Destination URL
  /// - Throws: `FileSystemError.writeFailed` if writing fails
  public func writeAtomic(_ content: String, to url: URL) throws(FileSystemError) {
    try createDirectoryIfNeeded(at: url.deletingLastPathComponent())

    guard let data = content.data(using: .utf8) else {
      throw .writeFailed(path: url.path, underlying: "Failed to encode content as UTF-8")
    }

    do {
      try data.write(to: url, options: .atomic)
      logger.debug("Wrote file atomically", metadata: ["path": "\(url.lastPathComponent)"])
    } catch {
      throw .writeFailed(path: url.path, underlying: error.localizedDescription)
    }
  }

  // MARK: - Private Helpers

  /// Create directory synchronously (called from actor context)
  private func createDirectoryIfNeeded(at url: URL) throws(FileSystemError) {
    // Check if path exists and is already a directory using URL resource values
    if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
      let isDirectory = resourceValues.isDirectory
    {
      if isDirectory {
        return  // Already exists as directory
      }
      throw .directoryCreationFailed(
        path: url.path,
        underlying: "Path exists but is not a directory"
      )
    }

    do {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
      logger.debug("Created directory", metadata: ["path": "\(url.path)"])
    } catch {
      throw .directoryCreationFailed(path: url.path, underlying: error.localizedDescription)
    }
  }

  /// Copy a file from source to destination
  private func copyFile(from source: URL, to destination: URL) throws(FileSystemError) {
    do {
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.copyItem(at: source, to: destination)
    } catch {
      throw .copyFailed(
        source: source.path,
        destination: destination.path,
        underlying: error.localizedDescription
      )
    }
  }

  /// Move a file from source to destination
  private func moveFile(
    from source: URL,
    to destination: URL,
    overwrite: Bool
  ) throws(FileSystemError) {
    do {
      if overwrite, fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: source, to: destination)
    } catch {
      throw .moveFailed(
        source: source.path,
        destination: destination.path,
        underlying: error.localizedDescription
      )
    }
  }

  /// Delete a file at the given URL
  private func deleteFile(at url: URL) throws(FileSystemError) {
    do {
      try fileManager.removeItem(at: url)
    } catch {
      throw .deleteFailed(path: url.path, underlying: error.localizedDescription)
    }
  }

  /// Perform rollback by restoring backups and cleaning up staged files
  private func rollback(
    stagedFiles: [URL],
    backupPairs: [(backup: URL, original: URL)],
    operationID: String
  ) async -> Bool {
    var rollbackSucceeded = true

    for stagedURL in stagedFiles {
      do {
        if fileManager.fileExists(atPath: stagedURL.path) {
          try deleteFile(at: stagedURL)
          logger.debug(
            "Deleted staged file",
            metadata: [
              "operationID": "\(operationID)",
              "file": "\(stagedURL.lastPathComponent)",
            ]
          )
        }
      } catch {
        logger.error(
          "Failed to delete staged file during rollback",
          metadata: [
            "operationID": "\(operationID)",
            "file": "\(stagedURL.lastPathComponent)",
            "error": "\(error)",
          ]
        )
        rollbackSucceeded = false
      }
    }

    for pair in backupPairs {
      do {
        if fileManager.fileExists(atPath: pair.backup.path) {
          try moveFile(from: pair.backup, to: pair.original, overwrite: true)
          logger.debug(
            "Restored backup",
            metadata: [
              "operationID": "\(operationID)",
              "file": "\(pair.original.lastPathComponent)",
            ]
          )
        }
      } catch {
        logger.error(
          "Failed to restore backup during rollback",
          metadata: [
            "operationID": "\(operationID)",
            "original": "\(pair.original.lastPathComponent)",
            "backup": "\(pair.backup.lastPathComponent)",
            "error": "\(error)",
          ]
        )
        rollbackSucceeded = false
      }
    }

    if rollbackSucceeded {
      logger.info("Rollback completed successfully", metadata: ["operationID": "\(operationID)"])
    } else {
      logger.error("Rollback completed with errors", metadata: ["operationID": "\(operationID)"])
    }

    return rollbackSucceeded
  }
}
