import Foundation

/// Azure DevOps provider using `az` CLI
public struct AzureProvider: PRProvider {
  public var name: String { "Azure DevOps" }

  private let cli = CLIHelper()

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let azPath = try await cli.findExecutable(name: "az")

    // Build az command
    var args: [String] = ["repos", "pr", "show"]
    if !identifier.isEmpty {
      args.append(contentsOf: ["--id", identifier])
    }
    args.append(contentsOf: ["--output", "json"])

    if let repo = repo {
      args.append(contentsOf: ["--repository", repo])
    }

    // Execute command
    let output = try await cli.execute(executable: azPath, arguments: args)

    // Parse Azure JSON and convert to our PullRequest format
    let decoder = JSONDecoder()
    let azurePR = try decoder.decode(AzurePR.self, from: Data(output))

    return azurePR.toPullRequest()
  }

  public func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws {
    let azPath = try await cli.findExecutable(name: "az")

    // Use az repos pr policy to add comment
    var args = [
      "repos", "pr", "policy", "create",
      "--id", prIdentifier,
      "--type", "comment",
      "--comment", body,
      "--parent-comment-id", commentId,
    ]

    if let repo = repo {
      args.append(contentsOf: ["--repository", repo])
    }

    _ = try await cli.execute(executable: azPath, arguments: args)
  }

  public func resolveThread(
    prIdentifier: String,
    threadId: String,
    repo: String?
  ) async throws {
    let azPath = try await cli.findExecutable(name: "az")

    // Azure has thread status management
    var args = [
      "repos", "pr", "update",
      "--id", prIdentifier,
      "--status", "completed",
      "--thread-id", threadId,
    ]

    if let repo = repo {
      args.append(contentsOf: ["--repository", repo])
    }

    _ = try await cli.execute(executable: azPath, arguments: args)
  }

  public func isAvailable() async -> Bool {
    return await cli.isInstalled("az")
  }
}

// MARK: - Azure-specific models

/// Azure Pull Request structure (simplified)
private struct AzurePR: Codable {
  let title: String
  let description: String?
  let pullRequestId: Int
  // Note: Full comment/thread parsing would require additional API calls

  enum CodingKeys: String, CodingKey {
    case title
    case description
    case pullRequestId
  }

  func toPullRequest() -> PullRequest {
    // For now, return basic structure
    // Full implementation would require fetching threads via API
    return PullRequest(
      body: description ?? "",
      comments: [],
      reviews: [],
      files: nil
    )
  }
}
