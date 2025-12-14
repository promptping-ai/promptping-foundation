import Foundation

/// Resolves and normalizes file system paths with tilde expansion and standard path access.
///
/// `PathResolver` is a stateless, thread-safe utility for path manipulation operations.
/// It handles common path resolution tasks like expanding `~` to the home directory
/// and converting relative paths to absolute paths.
///
/// ## Example Usage
///
/// ```swift
/// let resolver = PathResolver()
///
/// // Tilde expansion
/// let launchAgents = resolver.resolve("~/Library/LaunchAgents")
/// // Returns: URL(fileURLWithPath: "/Users/stijn/Library/LaunchAgents")
///
/// // Relative path resolution
/// let absolute = resolver.resolve("./config/settings.json")
/// // Returns: URL with absolute path from current directory
///
/// // Standard paths via enum
/// let binDir = PathResolver.StandardPath.swiftpmBin.url
/// // Returns: URL to ~/.swiftpm/bin
/// ```
public struct PathResolver: Sendable {

  // MARK: - Standard Paths

  /// Well-known system and user directory paths.
  ///
  /// These paths follow macOS conventions and are commonly used
  /// for tool installation, logging, caching, and service management.
  public enum StandardPath: Sendable, CaseIterable {
    /// SwiftPM binary installation directory (`~/.swiftpm/bin`)
    case swiftpmBin

    /// User LaunchAgents directory (`~/Library/LaunchAgents`)
    case launchAgents

    /// User Logs directory (`~/Library/Logs`)
    case logs

    /// User cache directory (`~/.cache`)
    case cache

    /// The path string with tilde (unexpanded).
    public var tildePath: String {
      switch self {
      case .swiftpmBin:
        "~/.swiftpm/bin"
      case .launchAgents:
        "~/Library/LaunchAgents"
      case .logs:
        "~/Library/Logs"
      case .cache:
        "~/.cache"
      }
    }

    /// The fully resolved URL with tilde expanded.
    public var url: URL {
      if tildePath.hasPrefix("~") {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let relativePath = String(tildePath.dropFirst(tildePath.hasPrefix("~/") ? 2 : 1))
        return relativePath.isEmpty ? home : home.appendingPathComponent(relativePath)
      }
      return URL(fileURLWithPath: tildePath)
    }

    /// The fully resolved path string with tilde expanded.
    public var path: String {
      url.path
    }
  }

  // MARK: - Initialization

  /// Creates a new path resolver.
  public init() {}

  // MARK: - Path Resolution

  /// Resolves a path string to an absolute URL.
  ///
  /// This method handles:
  /// - Tilde expansion (`~` to home directory)
  /// - Relative path resolution (from current working directory)
  /// - Already absolute paths (returned as-is)
  ///
  /// - Parameter path: The path string to resolve. Can be absolute, relative, or tilde-prefixed.
  /// - Returns: A file URL with the fully resolved absolute path.
  ///
  /// ## Examples
  ///
  /// ```swift
  /// let resolver = PathResolver()
  ///
  /// // Tilde expansion
  /// resolver.resolve("~/Documents")
  /// // -> file:///Users/username/Documents
  ///
  /// // Relative path
  /// resolver.resolve("./config")
  /// // -> file:///current/working/directory/config
  ///
  /// // Absolute path (unchanged)
  /// resolver.resolve("/usr/local/bin")
  /// // -> file:///usr/local/bin
  /// ```
  public func resolve(_ path: String) -> URL {
    // Handle tilde expansion using modern Swift Foundation
    let url: URL
    if path.hasPrefix("~") {
      let home = FileManager.default.homeDirectoryForCurrentUser
      let relativePath = String(path.dropFirst(path.hasPrefix("~/") ? 2 : 1))
      url = relativePath.isEmpty ? home : home.appendingPathComponent(relativePath)
    } else {
      url = URL(fileURLWithPath: path)
    }

    // Standardize to remove . and .. components
    return url.standardized
  }

  /// Resolves a path string to an absolute path string.
  ///
  /// Convenience method that returns a `String` instead of `URL`.
  ///
  /// - Parameter path: The path string to resolve.
  /// - Returns: The fully resolved absolute path as a string.
  public func resolvePath(_ path: String) -> String {
    resolve(path).path
  }

  /// Checks if a path string represents an absolute path.
  ///
  /// - Parameter path: The path string to check.
  /// - Returns: `true` if the path is absolute (starts with `/` or `~`).
  public func isAbsolute(_ path: String) -> Bool {
    path.hasPrefix("/") || path.hasPrefix("~")
  }

  /// Returns the user's home directory URL.
  public var homeDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
  }

  /// Returns the current working directory URL.
  public var currentDirectory: URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  }
}
