import Foundation

/// Manages reading and writing Version.swift files in Swift packages
public struct VersionFileManager: Sendable {

  public init() {}

  /// Find Version.swift file in a package directory
  /// Searches Sources/*/Version.swift pattern
  public func findVersionFile(in packageDirectory: URL) throws -> URL? {
    let sourcesDir = packageDirectory.appendingPathComponent("Sources")

    guard FileManager.default.fileExists(atPath: sourcesDir.path) else {
      return nil
    }

    let contents = try FileManager.default.contentsOfDirectory(
      at: sourcesDir,
      includingPropertiesForKeys: [.isDirectoryKey]
    )

    for item in contents {
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue
      else {
        continue
      }

      // Check for Version.swift in this target
      let versionFile = item.appendingPathComponent("Version.swift")
      if FileManager.default.fileExists(atPath: versionFile.path) {
        return versionFile
      }
    }

    return nil
  }

  /// Read current version from Version.swift file
  public func readVersion(from file: URL) throws -> SemanticVersion {
    let content = try String(contentsOf: file, encoding: .utf8)

    // Parse current version from: public static let current = "X.Y.Z"
    guard let match = content.range(of: #"current\s*=\s*"([^"]+)""#, options: .regularExpression),
      let versionMatch = content[match].range(of: #""[^"]+""#, options: .regularExpression)
    else {
      throw VersionFileError.cannotParseVersion(file.path)
    }

    let versionString = String(content[versionMatch]).trimmingCharacters(
      in: CharacterSet(charactersIn: "\""))
    guard let version = SemanticVersion.parse(versionString) else {
      throw VersionFileError.invalidVersionFormat(versionString)
    }

    return version
  }

  /// Generate Version.swift content for a given version and module name
  public func generateVersionFile(version: SemanticVersion, moduleName: String) -> String {
    let prereleaseValue = version.isPreRelease ? "\"\(version.preRelease)\"" : "nil"

    return """
      /// Auto-generated version file. Do not edit manually.
      /// Use `bump-version` to update.
      public enum \(moduleName)Version {
        public static let current = "\(version)"
        public static let major = \(version.major)
        public static let minor = \(version.minor)
        public static let patch = \(version.patch)
        public static let prerelease: String? = \(prereleaseValue)
      }

      """
  }

  /// Write version to Version.swift file
  public func writeVersion(_ version: SemanticVersion, to file: URL, moduleName: String) throws {
    let content = generateVersionFile(version: version, moduleName: moduleName)
    do {
      try content.write(to: file, atomically: true, encoding: .utf8)
    } catch {
      throw VersionFileError.fileWriteFailed(file.path, error)
    }
  }

  /// Create a new Version.swift file in the appropriate target
  public func createVersionFile(
    version: SemanticVersion,
    packageDirectory: URL,
    targetName: String
  ) throws -> URL {
    let targetDir =
      packageDirectory
      .appendingPathComponent("Sources")
      .appendingPathComponent(targetName)

    // Create target directory if needed
    if !FileManager.default.fileExists(atPath: targetDir.path) {
      try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
    }

    let versionFile = targetDir.appendingPathComponent("Version.swift")
    try writeVersion(version, to: versionFile, moduleName: targetName)

    return versionFile
  }

  /// Extract module name from Version.swift file path
  public func extractModuleName(from file: URL) -> String {
    // Path like: Sources/MyModule/Version.swift -> MyModule
    let parent = file.deletingLastPathComponent().lastPathComponent
    return parent
  }
}

/// Errors from version file operations
public enum VersionFileError: Error, Sendable, CustomStringConvertible {
  case cannotParseVersion(String)
  case invalidVersionFormat(String)
  case noVersionFileFound
  case fileWriteFailed(String, any Error)

  public var description: String {
    switch self {
    case .cannotParseVersion(let path):
      return "Cannot parse version from file: \(path)"
    case .invalidVersionFormat(let version):
      return "Invalid version format: \(version)"
    case .noVersionFileFound:
      return "No Version.swift file found in Sources/*/"
    case .fileWriteFailed(let path, let error):
      return "Failed to write version file at \(path): \(error)"
    }
  }
}
