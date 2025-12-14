import Foundation

/// Errors that can occur during launch agent operations
public enum LaunchAgentError: Error, LocalizedError, Sendable {
  /// Service is not loaded in launchd
  case serviceNotLoaded(label: String)

  /// Failed to bootstrap (load) the service
  case bootstrapFailed(label: String, reason: String)

  /// Failed to bootout (unload) the service
  case bootoutFailed(label: String, reason: String)

  /// Failed to kickstart the service
  case kickstartFailed(label: String, reason: String)

  /// Failed to send signal to service
  case killFailed(label: String, signal: String, reason: String)

  /// Plist file does not exist at the specified path
  case plistNotFound(path: String)

  /// Failed to write plist file
  case plistWriteFailed(path: String, reason: String)

  /// Invalid service configuration
  case invalidConfiguration(reason: String)

  /// Failed to get current user ID
  case userIdUnavailable

  public var errorDescription: String? {
    switch self {
    case .serviceNotLoaded(let label):
      return "Service '\(label)' is not loaded in launchd"
    case .bootstrapFailed(let label, let reason):
      return "Failed to bootstrap service '\(label)': \(reason)"
    case .bootoutFailed(let label, let reason):
      return "Failed to bootout service '\(label)': \(reason)"
    case .kickstartFailed(let label, let reason):
      return "Failed to kickstart service '\(label)': \(reason)"
    case .killFailed(let label, let signal, let reason):
      return "Failed to send \(signal) to service '\(label)': \(reason)"
    case .plistNotFound(let path):
      return "Plist file not found at: \(path)"
    case .plistWriteFailed(let path, let reason):
      return "Failed to write plist to '\(path)': \(reason)"
    case .invalidConfiguration(let reason):
      return "Invalid service configuration: \(reason)"
    case .userIdUnavailable:
      return "Failed to get current user ID"
    }
  }
}
