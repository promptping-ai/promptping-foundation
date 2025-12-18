import Foundation
import Subprocess

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

    // Fetch discussions separately to get threaded comments
    let discussions = try await fetchDiscussions(
      mrIdentifier: identifier,
      repo: repo,
      glabPath: glabPath
    )

    return gitlabMR.toPullRequest(discussions: discussions)
  }

  private func fetchDiscussions(
    mrIdentifier: String,
    repo: String?,
    glabPath: Subprocess.Executable
  ) async throws -> [GitLabDiscussion] {
    // Build glab API command to fetch discussions
    var args = ["api", "projects/:id/merge_requests/\(mrIdentifier)/discussions"]

    if let repo = repo {
      args.append(contentsOf: ["--repo", repo])
    }

    // Execute command
    let output = try await cli.execute(executable: glabPath, arguments: args)

    // Parse discussions
    let decoder = JSONDecoder()
    return try decoder.decode([GitLabDiscussion].self, from: Data(output))
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

/// GitLab Merge Request structure
private struct GitLabMR: Codable {
  let title: String
  let description: String?
  let webURL: String
  let notes: [GitLabNote]?

  enum CodingKeys: String, CodingKey {
    case title
    case description
    case webURL = "web_url"
    case notes
  }

  func toPullRequest(discussions: [GitLabDiscussion]) -> PullRequest {
    // Separate general comments from inline code comments
    var generalComments: [Comment] = []
    var reviews: [Review] = []

    for discussion in discussions {
      for note in discussion.notes {
        if note.system {
          continue  // Skip system notes
        }

        if let position = note.position {
          // Inline code comment - add to reviews
          let reviewComment = ReviewComment(
            id: String(note.id),
            path: position.newPath ?? position.oldPath ?? "",
            line: position.newLine ?? position.oldLine,
            body: note.body,
            createdAt: note.createdAt
          )

          // Group by discussion ID to create reviews
          if let existingReviewIndex = reviews.firstIndex(where: { $0.id == discussion.id }) {
            let existingReview = reviews[existingReviewIndex]
            var comments = existingReview.comments ?? []
            comments.append(reviewComment)
            reviews[existingReviewIndex] = Review(
              id: existingReview.id,
              author: existingReview.author,
              authorAssociation: existingReview.authorAssociation,
              body: existingReview.body,
              submittedAt: existingReview.submittedAt,
              state: existingReview.state,
              comments: comments
            )
          } else {
            reviews.append(
              Review(
                id: discussion.id,
                author: Author(login: note.author.username),
                authorAssociation: "MEMBER",
                body: nil,
                submittedAt: note.createdAt,
                state: "COMMENTED",
                comments: [reviewComment]
              )
            )
          }
        } else {
          // General comment
          generalComments.append(note.toComment())
        }
      }
    }

    return PullRequest(
      body: description ?? "",
      comments: generalComments,
      reviews: reviews,
      files: nil
    )
  }
}

/// GitLab Discussion (thread) structure
private struct GitLabDiscussion: Codable {
  let id: String
  let notes: [GitLabNote]
}

/// GitLab Note (comment) structure
private struct GitLabNote: Codable {
  let id: Int
  let author: GitLabUser
  let body: String
  let createdAt: String
  let system: Bool
  let noteableType: String?
  let position: GitLabPosition?

  enum CodingKeys: String, CodingKey {
    case id
    case author
    case body
    case createdAt = "created_at"
    case system
    case noteableType = "noteable_type"
    case position
  }

  func toComment() -> Comment {
    return Comment(
      id: String(id),
      author: Author(login: author.username),
      authorAssociation: "MEMBER",  // GitLab doesn't have this concept
      body: body,
      createdAt: createdAt,
      url: ""  // Would need to construct from MR URL
    )
  }
}

/// GitLab User structure
private struct GitLabUser: Codable {
  let username: String
  let name: String?
}

/// GitLab Position (for inline code comments)
private struct GitLabPosition: Codable {
  let newPath: String?
  let newLine: Int?
  let oldPath: String?
  let oldLine: Int?

  enum CodingKeys: String, CodingKey {
    case newPath = "new_path"
    case newLine = "new_line"
    case oldPath = "old_path"
    case oldLine = "old_line"
  }
}
