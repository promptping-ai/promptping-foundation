import Foundation

/// Represents a Claude Code plugin manifest (plugin.json)
public struct PluginManifest: Codable, Sendable {
  public let name: String
  public let version: String
  public let description: String?
  public let author: Author?
  public let repository: Repository?
  public let license: String?
  public let category: String?
  public let tags: [String]?
  public let namespace: String?
  public let mcpServers: [String: MCPServer]?
  public let agents: [String]?
  public let skills: [String]?
  public let hooks: [String]?
  public let dependencies: [String: Dependency]?
  public let marketplace: Marketplace?

  public struct Author: Codable, Sendable {
    public let name: String
    public let url: String?
  }

  public struct Repository: Codable, Sendable {
    public let type: String
    public let url: String
  }

  public struct MCPServer: Codable, Sendable {
    public let command: String
    public let args: [String]?
    public let env: [String: String]?
  }

  public struct Dependency: Codable, Sendable {
    public let repository: String
    public let minVersion: String?
    public let binaryName: String?
    public let installCommand: String?

    /// Check if this dependency is satisfied
    public func isSatisfied() -> Bool {
      guard let binaryName = binaryName else { return true }
      let binaryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".swiftpm/bin")
        .appendingPathComponent(binaryName)
      return FileManager.default.fileExists(atPath: binaryPath.path)
    }
  }

  public struct Marketplace: Codable, Sendable {
    public let namespace: String?
    public let keywords: [String]?
    public let minClaudeVersion: String?
  }
}

extension PluginManifest {
  /// Load manifest from a plugin.json file
  public static func load(from url: URL) throws -> PluginManifest {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(PluginManifest.self, from: data)
  }

  /// Load manifest from a directory containing plugin.json
  public static func load(fromDirectory directory: URL) throws -> PluginManifest {
    let manifestURL = directory.appendingPathComponent("plugin.json")
    return try load(from: manifestURL)
  }
}
