// PromptPingFoundation
// A reusable Swift package for daemon installation, launchd management,
// and atomic file operations.
//
// Components:
// - SubprocessRunner: Modern async subprocess execution using Swift Subprocess API
// - PathResolver: Tilde expansion and standard path utilities
// - AtomicFileManager: Transactional file operations with rollback
// - PortManager: Port detection and allocation via lsof
// - LaunchAgentManager: macOS launchd service lifecycle management
// - DaemonInstaller: High-level orchestration for daemon installation

@_exported import Logging

/// Version of the PromptPingFoundation library
public enum PromptPingFoundation {
  public static let version = "0.1.0"
}
