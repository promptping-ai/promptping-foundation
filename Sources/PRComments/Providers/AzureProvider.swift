import Foundation

/// Azure DevOps provider using `az` CLI
public struct AzureProvider: PRProvider {
  public var name: String { "Azure DevOps" }

  private let cli = CLIHelper()

  public init() {}

  public func fetchPR(identifier: String, repo: String?) async throws -> PullRequest {
    let azPath = try await cli.findExecutable(name: "az")

    // Fetch basic PR info - Azure PRs are uniquely identified by ID across the org
    let prArgs: [String] = ["repos", "pr", "show", "--id", identifier, "--output", "json"]
    let prOutput = try await cli.execute(executable: azPath, arguments: prArgs)

    // Parse PR to get project and repository info for thread lookup
    let decoder = JSONDecoder()
    let azurePR = try decoder.decode(AzurePR.self, from: Data(prOutput))

    // Fetch PR threads using devops invoke (REST API)
    // Azure DevOps requires project and repository for thread lookup
    let threadsArgs: [String] = [
      "devops", "invoke",
      "--area", "git",
      "--resource", "pullRequestThreads",
      "--route-parameters",
      "project=\(azurePR.repository.project.name)",
      "repositoryId=\(azurePR.repository.name)",
      "pullRequestId=\(identifier)",
      "--output", "json",
    ]

    var azureThreads: [AzurePRThread] = []
    do {
      let threadsOutput = try await cli.execute(executable: azPath, arguments: threadsArgs)
      let threadsResponse = try decoder.decode(AzureThreadsResponse.self, from: Data(threadsOutput))
      azureThreads = threadsResponse.value
    } catch {
      // If thread fetch fails, continue with empty threads
      // This can happen if user doesn't have permissions
    }

    return azurePR.toPullRequest(threads: azureThreads)
  }

  public func replyToComment(
    prIdentifier: String,
    commentId: String,
    body: String,
    repo: String?
  ) async throws {
    let azPath = try await cli.findExecutable(name: "az")

    // Azure: commentId is the thread ID, use thread comment create
    var args = [
      "repos", "pr", "thread", "comment", "create",
      "--thread-id", commentId,
      "--content", body,
      "--pull-request-id", prIdentifier,
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

    // Azure thread status update - "fixed" marks as resolved
    var args = [
      "repos", "pr", "thread", "update",
      "--thread-id", threadId,
      "--status", "fixed",
      "--pull-request-id", prIdentifier,
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

/// Response wrapper for devops invoke (threads API)
private struct AzureThreadsResponse: Codable {
  let value: [AzurePRThread]
  let count: Int?
}

/// Azure Pull Request structure
private struct AzurePR: Codable {
  let title: String
  let description: String?
  let pullRequestId: Int
  let repository: AzureRepository
}

/// Azure Repository structure
private struct AzureRepository: Codable {
  let name: String
  let project: AzureProject
}

/// Azure Project structure
private struct AzureProject: Codable {
  let name: String
}

extension AzurePR {
  func toPullRequest(threads: [AzurePRThread]) -> PullRequest {
    // Convert Azure threads to our Review model
    let reviews = threads.map { thread in
      Review(
        id: String(thread.id),
        author: Author(login: thread.comments.first?.author.displayName ?? "Unknown"),
        authorAssociation: "CONTRIBUTOR",
        body: thread.comments.first?.content,
        submittedAt: thread.publishedDate?.id,
        state: thread.status == "active" ? "PENDING" : "APPROVED",
        comments: thread.threadContext != nil ? convertToReviewComments(thread: thread) : nil
      )
    }

    // Azure doesn't have separate top-level comments like GitHub
    // All comments are within threads
    return PullRequest(
      body: description ?? "",
      comments: [],
      reviews: reviews,
      files: nil,
      number: pullRequestId
    )
  }

  private func convertToReviewComments(thread: AzurePRThread) -> [ReviewComment] {
    guard let context = thread.threadContext else { return [] }

    return thread.comments.map { comment in
      ReviewComment(
        id: String(comment.id),
        path: context.filePath ?? "",
        line: context.rightFileStart?.line,
        body: comment.content ?? "",
        createdAt: comment.publishedDate?.id ?? ""
      )
    }
  }
}

/// Azure PR Thread structure
private struct AzurePRThread: Codable {
  let id: Int
  let status: String  // "active", "closed", "fixed", etc.
  let comments: [AzurePRComment]
  let threadContext: AzureThreadContext?
  let publishedDate: AzureDateValue?

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case comments
    case threadContext
    case publishedDate
  }
}

/// Azure PR Comment structure
private struct AzurePRComment: Codable {
  let id: Int
  let author: AzureAuthor
  let content: String?
  let publishedDate: AzureDateValue?

  enum CodingKeys: String, CodingKey {
    case id
    case author
    case content
    case publishedDate
  }
}

/// Azure Thread Context (file location info)
private struct AzureThreadContext: Codable {
  let filePath: String?
  let rightFileStart: AzureLinePosition?

  enum CodingKeys: String, CodingKey {
    case filePath
    case rightFileStart
  }
}

/// Azure Line Position
private struct AzureLinePosition: Codable {
  let line: Int
  let offset: Int

  enum CodingKeys: String, CodingKey {
    case line
    case offset
  }
}

/// Azure Author structure
private struct AzureAuthor: Codable {
  let displayName: String

  enum CodingKeys: String, CodingKey {
    case displayName
  }
}

/// Azure Date Value (Azure returns dates as objects with string value)
private struct AzureDateValue: Codable {
  let id: String

  enum CodingKeys: String, CodingKey {
    case id
  }
}
