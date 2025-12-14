import Foundation

/// Errors that can occur during port management operations
public enum PortError: Error, LocalizedError, Sendable {
  /// No free port available in the specified range
  case noFreePort(range: ClosedRange<Int>)

  /// The requested port is already in use
  case portInUse(port: Int, by: ProcessInfo?)

  public var errorDescription: String? {
    switch self {
    case .noFreePort(let range):
      return "No free port available in range \(range.lowerBound)-\(range.upperBound)"
    case .portInUse(let port, let process):
      if let process {
        return "Port \(port) is in use by \(process.command) (PID: \(process.pid))"
      } else {
        return "Port \(port) is in use"
      }
    }
  }
}

/// Information about a process
public struct ProcessInfo: Sendable, Equatable {
  /// Process ID
  public let pid: Int32

  /// Command name (executable name)
  public let command: String

  /// Port the process is listening on (if known)
  public let port: Int?

  public init(pid: Int32, command: String, port: Int? = nil) {
    self.pid = pid
    self.command = command
    self.port = port
  }
}
