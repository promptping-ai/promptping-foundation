import Foundation

/// GitHub provider using `gh` CLI
public struct GitHubProvider: PRProvider {
  public var name: String { "GitHub" }

  private let cli = CLIHelper()

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let ghPath = try await cli.findExecutable(name: "gh")

    // Build gh command for PR data
    var prArgs: [String] = ["pr", "view"]
    if !identifier.isEmpty {
      prArgs.append(identifier)
    }
    prArgs.append(contentsOf: ["--json", "body,comments,reviews,files,number"])

    if let repo = repo {
      prArgs.append(contentsOf: ["--repo", repo])
    }

    // Execute command
    let prOutput = try await cli.execute(executable: ghPath, arguments: prArgs)

    // Parse JSON response
    let decoder = JSONDecoder()
    var pr = try decoder.decode(PullRequest.self, from: Data(prOutput))

    // Fetch inline review comments separately (gh pr view doesn't include them)
    // Note: gh api doesn't support --repo flag, so we must expand the repo into the URL
    let prNum = pr.number.map(String.init) ?? identifier
    let apiPath: String
    if let repo = repo {
      // Explicitly use the repo in the URL
      apiPath = "repos/\(repo)/pulls/\(prNum)/comments"
    } else {
      // Let gh resolve {owner}/{repo} from current directory
      apiPath = "repos/{owner}/{repo}/pulls/\(prNum)/comments"
    }
    let apiArgs = ["api", apiPath]

    let commentsOutput = try await cli.execute(executable: ghPath, arguments: apiArgs)
    let inlineComments = try decoder.decode([GitHubReviewComment].self, from: Data(commentsOutput))

    // Merge inline comments into reviews
    pr = mergeInlineComments(pr: pr, inlineComments: inlineComments)

    return pr
  }

  /// Merge inline review comments into their parent reviews
  ///
  /// GitHub's REST API returns `pull_request_review_id` as integers, but
  /// GraphQL returns review IDs as strings (e.g., `PRR_kwDOQo0_Ns...`).
  /// Since they can't be matched directly, we match by author instead.
  private func mergeInlineComments(pr: PullRequest, inlineComments: [GitHubReviewComment])
    -> PullRequest
  {
    guard !inlineComments.isEmpty else { return pr }

    // Group inline comments by author login
    var commentsByAuthor: [String: [ReviewComment]] = [:]
    for ghComment in inlineComments {
      let reviewComment = ReviewComment(
        id: String(ghComment.id),
        path: ghComment.path,
        line: ghComment.line ?? ghComment.originalLine,
        body: ghComment.body,
        createdAt: ghComment.createdAt
      )
      commentsByAuthor[ghComment.user.login, default: []].append(reviewComment)
    }

    // Build a map of reviews by author (most authors have one review)
    // If multiple reviews from same author, use the first one
    var reviewByAuthor: [String: Int] = [:]  // author -> index in reviews
    for (index, review) in pr.reviews.enumerated() {
      if reviewByAuthor[review.author.login] == nil {
        reviewByAuthor[review.author.login] = index
      }
    }

    // Update reviews with their author's inline comments
    var updatedReviews = pr.reviews
    var matchedAuthors: Set<String> = []

    for (authorLogin, comments) in commentsByAuthor {
      if let reviewIndex = reviewByAuthor[authorLogin] {
        // Found a matching review - add comments to it
        let review = updatedReviews[reviewIndex]
        let existingComments = review.comments ?? []
        updatedReviews[reviewIndex] = Review(
          id: review.id,
          author: review.author,
          authorAssociation: review.authorAssociation,
          body: review.body,
          submittedAt: review.submittedAt,
          state: review.state,
          comments: existingComments + comments
        )
        matchedAuthors.insert(authorLogin)
      }
    }

    // Create synthetic reviews for any authors with comments but no review
    for (authorLogin, comments) in commentsByAuthor where !matchedAuthors.contains(authorLogin) {
      // Find earliest comment date for synthetic review timestamp
      let earliestDate = comments.map(\.createdAt).min() ?? ""
      let syntheticReview = Review(
        id: "inline-\(authorLogin)",
        author: Author(login: authorLogin),
        authorAssociation: "NONE",
        body: nil,
        submittedAt: earliestDate,
        state: "COMMENTED",
        comments: comments
      )
      updatedReviews.append(syntheticReview)
    }

    return PullRequest(
      body: pr.body,
      comments: pr.comments,
      reviews: updatedReviews,
      files: pr.files,
      number: pr.number
    )
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
