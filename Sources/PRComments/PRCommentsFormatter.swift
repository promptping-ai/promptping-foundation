import Foundation

public struct PRCommentsFormatter: Sendable {
  public init() {}

  public func format(_ pr: PullRequest, includeBody: Bool = false) -> String {
    var output: [String] = []

    if includeBody && !pr.body.isEmpty {
      output.append("📄 PR Description")
      output.append(String(repeating: "─", count: 80))
      output.append(pr.body)
      output.append("")
    }

    // General comments
    if !pr.comments.isEmpty {
      output.append("💬 Comments (\(pr.comments.count))")
      output.append(String(repeating: "─", count: 80))
      for (index, comment) in pr.comments.enumerated() {
        output.append(formatComment(comment, number: index + 1))
        if index < pr.comments.count - 1 {
          output.append("")
        }
      }
      output.append("")
    }

    // Review comments (inline code comments)
    let reviewsWithComments = pr.reviews.filter { review in
      (review.comments?.isEmpty == false) || (review.body?.isEmpty == false)
    }

    if !reviewsWithComments.isEmpty {
      output.append("🔍 Reviews (\(reviewsWithComments.count))")
      output.append(String(repeating: "─", count: 80))
      for (index, review) in reviewsWithComments.enumerated() {
        output.append(formatReview(review, number: index + 1))
        if index < reviewsWithComments.count - 1 {
          output.append(String(repeating: "─", count: 80))
        }
      }
    }

    // Handle empty PR
    if output.isEmpty {
      return "No comments found."
    }

    return output.joined(separator: "\n")
  }

  private func formatComment(_ comment: Comment, number: Int) -> String {
    var lines: [String] = []

    let date = formatDate(comment.createdAt)
    lines.append("[\(number)] @\(comment.author.login) • \(date) • ID: \(comment.id)")
    lines.append(comment.body)

    return lines.joined(separator: "\n")
  }

  private func formatReview(_ review: Review, number: Int) -> String {
    var lines: [String] = []

    let date = review.submittedAt.flatMap(formatDate) ?? "unknown"
    let stateEmoji = reviewStateEmoji(review.state)
    lines.append(
      "[\(number)] \(stateEmoji) @\(review.author.login) • \(date) • Thread: \(review.id)")

    // Review body (overall comment)
    if let body = review.body, !body.isEmpty {
      lines.append("")
      lines.append(body)
    }

    // Inline code comments
    if let comments = review.comments, !comments.isEmpty {
      lines.append("")
      lines.append("  📝 Code Comments:")
      for comment in comments {
        lines.append("")
        lines.append(formatReviewComment(comment))
      }
    }

    return lines.joined(separator: "\n")
  }

  private func formatReviewComment(_ comment: ReviewComment) -> String {
    var lines: [String] = []

    let location = comment.line.map { ":\($0)" } ?? ""
    lines.append("  📍 \(comment.path)\(location) • ID: \(comment.id)")

    // Indent the comment body
    let indentedBody = comment.body
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { "     \($0)" }
      .joined(separator: "\n")
    lines.append(indentedBody)

    return lines.joined(separator: "\n")
  }

  private func reviewStateEmoji(_ state: String) -> String {
    switch state.uppercased() {
    case "APPROVED": return "✅"
    case "CHANGES_REQUESTED": return "❌"
    case "COMMENTED": return "💭"
    case "DISMISSED": return "🚫"
    case "PENDING": return "⏳"
    default: return "📋"
    }
  }

  private func formatDate(_ isoDate: String) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: isoDate) else {
      return isoDate
    }

    let displayFormatter = DateFormatter()
    displayFormatter.dateStyle = .medium
    displayFormatter.timeStyle = .short
    return displayFormatter.string(from: date)
  }
}
