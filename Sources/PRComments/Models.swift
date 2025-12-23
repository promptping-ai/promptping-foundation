import Foundation

// MARK: - GitHub PR Response Models

public struct PullRequest: Codable, Sendable {
  public let body: String
  public let comments: [Comment]
  public let reviews: [Review]
  public let files: [FileChange]?
  public let number: Int?

  public init(
    body: String, comments: [Comment], reviews: [Review], files: [FileChange]? = nil,
    number: Int? = nil
  ) {
    self.body = body
    self.comments = comments
    self.reviews = reviews
    self.files = files
    self.number = number
  }
}

public struct Comment: Codable, Sendable {
  public let id: String
  public let author: Author
  public let authorAssociation: String
  public let body: String
  public let createdAt: String
  public let url: String

  public init(
    id: String,
    author: Author,
    authorAssociation: String,
    body: String,
    createdAt: String,
    url: String
  ) {
    self.id = id
    self.author = author
    self.authorAssociation = authorAssociation
    self.body = body
    self.createdAt = createdAt
    self.url = url
  }
}

public struct Review: Codable, Sendable {
  public let id: String
  public let author: Author
  public let authorAssociation: String
  public let body: String?
  public let submittedAt: String?
  public let state: String
  public let comments: [ReviewComment]?

  enum CodingKeys: String, CodingKey {
    case id, author, authorAssociation, body, submittedAt, state, comments
  }

  public init(
    id: String,
    author: Author,
    authorAssociation: String,
    body: String?,
    submittedAt: String?,
    state: String,
    comments: [ReviewComment]? = nil
  ) {
    self.id = id
    self.author = author
    self.authorAssociation = authorAssociation
    self.body = body
    self.submittedAt = submittedAt
    self.state = state
    self.comments = comments
  }
}

public struct ReviewComment: Codable, Sendable {
  public let id: String
  public let path: String
  public let line: Int?
  public let body: String
  public let createdAt: String

  public init(id: String, path: String, line: Int?, body: String, createdAt: String) {
    self.id = id
    self.path = path
    self.line = line
    self.body = body
    self.createdAt = createdAt
  }
}

public struct Author: Codable, Sendable {
  public let login: String

  public init(login: String) {
    self.login = login
  }
}

public struct FileChange: Codable, Sendable {
  public let path: String
  public let additions: Int
  public let deletions: Int

  public init(path: String, additions: Int, deletions: Int) {
    self.path = path
    self.additions = additions
    self.deletions = deletions
  }
}
