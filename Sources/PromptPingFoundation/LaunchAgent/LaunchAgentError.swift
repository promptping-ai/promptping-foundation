import Foundation

/// Errors that can occur during launch agent operations
public enum LaunchAgentError: Error, LocalizedError, Sendable {
  /// Service is not loaded in launchd
  case serviceNotLoaded(label: String)

  /// Failed to bootstrap (load) the service
  case bootstrapFailed(label: String, underlying: any Error & Sendable)

  /// Failed to bootout (unload) the service
  case bootoutFailed(label: String, underlying: any Error & Sendable)

  /// Failed to kickstart the service
  case kickstartFailed(label: String, underlying: any Error & Sendable)

  /// Failed to send signal to service
  case killFailed(label: String, signal: String, underlying: any Error & Sendable)

  /// Plist file does not exist at the specified path
  case plistNotFound(path: String)

  /// Failed to write plist file
  case plistWriteFailed(path: String, underlying: any Error & Sendable)

  /// Invalid service configuration
  case invalidConfiguration(reason: String)

  /// Failed to get current user ID
  case userIdUnavailable

  public var errorDescription: String? {
    switch self {
    case .serviceNotLoaded(let label):
      return "Service '\(label)' is not loaded in launchd"
    case .bootstrapFailed(let label, let underlying):
      return "Failed to bootstrap service '\(label)': \(underlying.localizedDescription)"
    case .bootoutFailed(let label, let underlying):
      return "Failed to bootout service '\(label)': \(underlying.localizedDescription)"
    case .kickstartFailed(let label, let underlying):
      return "Failed to kickstart service '\(label)': \(underlying.localizedDescription)"
    case .killFailed(let label, let signal, let underlying):
      return "Failed to send \(signal) to service '\(label)': \(underlying.localizedDescription)"
    case .plistNotFound(let path):
      return "Plist file not found at: \(path)"
    case .plistWriteFailed(let path, let underlying):
      return "Failed to write plist to '\(path)': \(underlying.localizedDescription)"
    case .invalidConfiguration(let reason):
      return "Invalid service configuration: \(reason)"
    case .userIdUnavailable:
      return "Failed to get current user ID"
    }
  }
}
