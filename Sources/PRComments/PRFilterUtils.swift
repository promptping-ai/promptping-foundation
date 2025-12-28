import Foundation

/// Filter reviews by thread resolution status
///
/// - Parameters:
///   - pr: The pull request to filter
///   - showUnresolved: If true, show only unresolved threads; if false, show only resolved
/// - Returns: Filtered pull request with only matching review threads
package func filterByResolutionStatus(_ pr: PullRequest, showUnresolved: Bool) -> PullRequest {
  let filteredReviews = pr.reviews.compactMap { review -> Review? in
    guard let comments = review.comments else { return nil }

    let filteredComments = comments.filter { comment in
      // Include comments with unknown resolution status (non-GitHub or no GraphQL data)
      guard let isResolved = comment.isResolved else { return true }
      return showUnresolved ? !isResolved : isResolved
    }

    // Skip reviews with no matching comments
    guard !filteredComments.isEmpty else { return nil }

    return Review(
      id: review.id,
      author: review.author,
      authorAssociation: review.authorAssociation,
      body: review.body,
      submittedAt: review.submittedAt,
      state: review.state,
      comments: filteredComments
    )
  }

  return PullRequest(
    body: pr.body,
    comments: pr.comments,  // General comments are not filtered (no thread resolution)
    reviews: filteredReviews,
    files: pr.files,
    number: pr.number
  )
}
