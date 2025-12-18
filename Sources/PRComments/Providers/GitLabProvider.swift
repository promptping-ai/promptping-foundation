import Foundation

/// GitLab provider using `glab` CLI
public struct GitLabProvider: PRProvider {
  public var name: String { "GitLab" }

  private let cli = CLIHelper()

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let glabPath = try await cli.findExecutable(name: "glab")

    // Build glab command (uses 'mr' instead of 'pr')
    var args: [String] = ["mr", "view"]
    if !identifier.isEmpty {
      args.append(identifier)
    }
    args.append(contentsOf: ["--output", "json"])

    if let repo = repo {
      args.append(contentsOf: ["--repo", repo])
    }

    // Execute command
    let output = try await cli.execute(executable: glabPath, arguments: args)

    // Parse GitLab JSON and convert to our PullRequest format
    let decoder = JSONDecoder()
    let gitlabMR = try decoder.decode(GitLabMR.self, from: Data(output))

    return gitlabMR.toPullRequest()
  }

  public func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws {
    let glabPath = try await cli.findExecutable(name: "glab")

    // Use glab api to post a comment
    var args = [
      "api",
      "projects/:id/merge_requests/\(prIdentifier)/notes",
      "-f", "body=\(body)",
      "--method", "POST",
    ]

    if let repo = repo {
      args.append(contentsOf: ["--repo", repo])
    }

    _ = try await cli.execute(executable: glabPath, arguments: args)
  }

  public func resolveThread(
    prIdentifier: String,
    threadId: String,
    repo: String?
  ) async throws {
    let glabPath = try await cli.findExecutable(name: "glab")

    // GitLab has explicit thread resolution
    var args = [
      "api",
      "projects/:id/merge_requests/\(prIdentifier)/discussions/\(threadId)",
      "-f", "resolved=true",
      "--method", "PUT",
    ]

    if let repo = repo {
      args.append(contentsOf: ["--repo", repo])
    }

    _ = try await cli.execute(executable: glabPath, arguments: args)
  }

  public func isAvailable() async -> Bool {
    return await cli.isInstalled("glab")
  }
}

// MARK: - GitLab-specific models

/// GitLab Merge Request structure (simplified)
private struct GitLabMR: Codable {
  let title: String
  let description: String?
  let webURL: String
  // Note: Full comment/discussion parsing would require additional API calls

  enum CodingKeys: String, CodingKey {
    case title
    case description
    case webURL = "web_url"
  }

  func toPullRequest() -> PullRequest {
    // For now, return basic structure
    // Full implementation would require fetching discussions via API
    return PullRequest(
      body: description ?? "",
      comments: [],
      reviews: [],
      files: nil
    )
  }
}
