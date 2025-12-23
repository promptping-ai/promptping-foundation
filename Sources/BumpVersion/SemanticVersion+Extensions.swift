// Re-export SPI's SemanticVersion so consumers only need to import BumpVersion
@_exported import SemanticVersion

/// Prerelease version types for bump operations
public enum PrereleaseType: String, Sendable, CaseIterable {
  case alpha
  case beta
  case rc

  public var displayName: String {
    switch self {
    case .alpha: return "Alpha"
    case .beta: return "Beta"
    case .rc: return "Release Candidate"
    }
  }
}

// MARK: - Bump Operations

extension SemanticVersion {

  /// Bump major version (resets minor and patch)
  public func bumpMajor() -> SemanticVersion {
    SemanticVersion(major + 1, 0, 0)
  }

  /// Bump minor version (resets patch)
  public func bumpMinor() -> SemanticVersion {
    SemanticVersion(major, minor + 1, 0)
  }

  /// Bump patch version
  public func bumpPatch() -> SemanticVersion {
    SemanticVersion(major, minor, patch + 1)
  }

  /// Add or update prerelease suffix
  public func withPrerelease(_ type: PrereleaseType, number: Int = 1) -> SemanticVersion {
    SemanticVersion(major, minor, patch, "\(type.rawValue).\(number)")
  }

  /// Remove prerelease suffix (for release)
  public func release() -> SemanticVersion {
    SemanticVersion(major, minor, patch)
  }

  /// Increment the prerelease number if same type, or start at 1
  public func bumpPrerelease(_ type: PrereleaseType) -> SemanticVersion {
    if preRelease.hasPrefix(type.rawValue),
      let dotIndex = preRelease.lastIndex(of: "."),
      let number = Int(preRelease[preRelease.index(after: dotIndex)...])
    {
      return withPrerelease(type, number: number + 1)
    }
    return withPrerelease(type, number: 1)
  }
}

// MARK: - Convenience Initializers

extension SemanticVersion {

  /// Parse a version string, handling optional "v" prefix
  /// - Parameter versionString: String like "1.2.3", "v1.2.3", or "1.2.3-alpha.1"
  /// - Returns: SemanticVersion or nil if parsing fails
  public static func parse(_ versionString: String) -> SemanticVersion? {
    let trimmed = versionString.trimmingCharacters(in: .whitespaces)
    let normalized = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    return SemanticVersion(normalized)
  }
}
