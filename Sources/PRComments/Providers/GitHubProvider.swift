import Foundation

/// GitHub provider using `gh` CLI
public struct GitHubProvider: PRProvider {
  public var name: String { "GitHub" }

  private let cli = CLIHelper()

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let ghPath = try await cli.findExecutable(name: "gh")

    // Build gh command
    var args: [String] = ["pr", "view"]
    if !identifier.isEmpty {
      args.append(identifier)
    }
    args.append(contentsOf: ["--json", "body,comments,reviews,files"])

    if let repo = repo {
      args.append(contentsOf: ["--repo", repo])
    }

    // Execute command
    let output = try await cli.execute(executable: ghPath, arguments: args)

    // Parse JSON response
    let decoder = JSONDecoder()
    return try decoder.decode(PullRequest.self, from: Data(output))
  }

  public func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws {
    let ghPath = try await cli.findExecutable(name: "gh")

    // Validate repo format if provided
    var owner: String?
    var repoName: String?
    if let repo = repo {
      let parts = repo.split(separator: "/", maxSplits: 1)
      guard parts.count == 2 else {
        throw PRProviderError.invalidConfiguration(
          "Invalid repo format '\(repo)'. Expected 'owner/repo'")
      }
      owner = String(parts[0])
      repoName = String(parts[1])
    }

    // Use gh api to post a comment reply
    // GitHub API: POST /repos/{owner}/{repo}/pulls/comments/{comment_id}/replies
    var args = [
      "api",
      "-X", "POST",
    ]

    if let owner = owner, let repoName = repoName {
      args.append("repos/\(owner)/\(repoName)/pulls/comments/\(commentId)/replies")
    } else {
      // Use placeholder syntax when repo not specified (gh will resolve from current repo)
      args.append("repos/{owner}/{repo}/pulls/comments/\(commentId)/replies")
    }

    args.append(contentsOf: ["-f", "body=\(body)"])

    _ = try await cli.execute(executable: ghPath, arguments: args)
  }

  public func resolveThread(
    prIdentifier: String,
    threadId: String,
    repo: String?
  ) async throws {
    // GitHub doesn't have a direct "resolve" API, threads are resolved by replying
    // This would require fetching the thread and marking it as resolved via GraphQL
    throw PRProviderError.unsupportedOperation("GitHub thread resolution requires GraphQL API")
  }

  public func isAvailable() async -> Bool {
    return await cli.isInstalled("gh")
  }
}
