import Foundation

// MARK: - GitHub API Models (for fetching inline comments)

/// GitHub review comment from /pulls/{pr}/comments API
struct GitHubReviewComment: Codable {
  let id: Int
  let pullRequestReviewId: Int?
  let path: String
  let line: Int?
  let originalLine: Int?
  let body: String
  let createdAt: String
  let user: GitHubUser

  enum CodingKeys: String, CodingKey {
    case id
    case pullRequestReviewId = "pull_request_review_id"
    case path
    case line
    case originalLine = "original_line"
    case body
    case createdAt = "created_at"
    case user
  }
}

struct GitHubUser: Codable {
  let login: String
}
