import Foundation

/// Errors that can occur during file system operations
public enum FileSystemError: Error, LocalizedError, Sendable {
  /// Failed to create a directory
  case directoryCreationFailed(path: String, underlying: any Error & Sendable)

  /// Failed to copy a file
  case copyFailed(source: String, destination: String, underlying: any Error & Sendable)

  /// Failed to move a file
  case moveFailed(source: String, destination: String, underlying: any Error & Sendable)

  /// Failed to delete a file
  case deleteFailed(path: String, underlying: any Error & Sendable)

  /// Failed to write file contents
  case writeFailed(path: String, underlying: any Error & Sendable)

  /// Failed to read file contents
  case readFailed(path: String, underlying: any Error & Sendable)

  /// Source file does not exist
  case sourceNotFound(path: String)

  /// Destination already exists and overwrite was not requested
  case destinationExists(path: String)

  /// Atomic operation failed, rollback was attempted
  case atomicOperationFailed(
    operation: String,
    underlying: any Error & Sendable,
    rollbackSucceeded: Bool
  )

  /// Rollback failed during recovery
  case rollbackFailed(
    originalError: any Error & Sendable,
    rollbackError: any Error & Sendable
  )

  public var errorDescription: String? {
    switch self {
    case .directoryCreationFailed(let path, let underlying):
      return "Failed to create directory at '\(path)': \(underlying.localizedDescription)"

    case .copyFailed(let source, let destination, let underlying):
      return "Failed to copy '\(source)' to '\(destination)': \(underlying.localizedDescription)"

    case .moveFailed(let source, let destination, let underlying):
      return "Failed to move '\(source)' to '\(destination)': \(underlying.localizedDescription)"

    case .deleteFailed(let path, let underlying):
      return "Failed to delete '\(path)': \(underlying.localizedDescription)"

    case .writeFailed(let path, let underlying):
      return "Failed to write to '\(path)': \(underlying.localizedDescription)"

    case .readFailed(let path, let underlying):
      return "Failed to read '\(path)': \(underlying.localizedDescription)"

    case .sourceNotFound(let path):
      return "Source file not found: '\(path)'"

    case .destinationExists(let path):
      return "Destination already exists: '\(path)'"

    case .atomicOperationFailed(let operation, let underlying, let rollbackSucceeded):
      let rollbackStatus = rollbackSucceeded ? "rollback succeeded" : "rollback failed"
      return "Atomic operation '\(operation)' failed (\(rollbackStatus)): \(underlying.localizedDescription)"

    case .rollbackFailed(let originalError, let rollbackError):
      return "Rollback failed. Original error: \(originalError.localizedDescription). Rollback error: \(rollbackError.localizedDescription)"
    }
  }
}
