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

    // Use gh api to post a comment reply
    var args = [
      "api",
      "-X", "POST",
      "repos/{owner}/{repo}/pulls/comments/\(commentId)/replies",
      "-f", "body=\(body)",
    ]

    if let repo = repo {
      args.append(contentsOf: [
        "-F", "owner=\(repo.split(separator: "/")[0])", "-F",
        "repo=\(repo.split(separator: "/")[1])",
      ])
    }

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
