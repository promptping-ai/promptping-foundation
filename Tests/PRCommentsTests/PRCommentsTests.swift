import Foundation
import Testing

@testable import PRComments

@Suite("PR Comments Parsing and Formatting")
struct PRCommentsTests {

  @Test("Parse valid PR JSON")
  func testParsePullRequest() throws {
    let json = """
      {
        "body": "Test PR body",
        "comments": [
          {
            "id": "IC_123",
            "author": {"login": "testuser"},
            "authorAssociation": "MEMBER",
            "body": "Test comment",
            "createdAt": "2025-12-18T10:00:00Z",
            "url": "https://github.com/test/pr/1#comment-123"
          }
        ],
        "reviews": [],
        "files": []
      }
      """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let pr = try decoder.decode(PullRequest.self, from: data)

    #expect(pr.body == "Test PR body")
    #expect(pr.comments.count == 1)
    #expect(pr.comments[0].author.login == "testuser")
  }

  @Test("Parse PR with reviews and inline comments")
  func testParseReviewComments() throws {
    let json = """
      {
        "body": "PR with reviews",
        "comments": [],
        "reviews": [
          {
            "id": "PRR_123",
            "author": {"login": "reviewer"},
            "authorAssociation": "MEMBER",
            "body": "Overall looks good",
            "submittedAt": "2025-12-18T11:00:00Z",
            "state": "APPROVED",
            "comments": [
              {
                "id": "RC_456",
                "path": "src/test.swift",
                "line": 42,
                "body": "Consider using let instead of var",
                "createdAt": "2025-12-18T11:00:00Z"
              }
            ]
          }
        ]
      }
      """

    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    let pr = try decoder.decode(PullRequest.self, from: data)

    #expect(pr.reviews.count == 1)
    #expect(pr.reviews[0].state == "APPROVED")
    #expect(pr.reviews[0].comments?.count == 1)
    #expect(pr.reviews[0].comments?[0].path == "src/test.swift")
    #expect(pr.reviews[0].comments?[0].line == 42)
  }

  @Test("Format PR without body")
  func testFormatWithoutBody() {
    let pr = PullRequest(
      body: "PR Description",
      comments: [
        Comment(
          id: "1",
          author: Author(login: "user1"),
          authorAssociation: "MEMBER",
          body: "Great work!",
          createdAt: "2025-12-18T10:00:00Z",
          url: "https://test.com"
        )
      ],
      reviews: []
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    #expect(output.contains("💬 Comments"))
    #expect(output.contains("@user1"))
    #expect(output.contains("Great work!"))
    #expect(!output.contains("PR Description"))
  }

  @Test("Format PR with body")
  func testFormatWithBody() {
    let pr = PullRequest(
      body: "PR Description",
      comments: [],
      reviews: []
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: true)

    #expect(output.contains("📄 PR Description"))
    #expect(output.contains("PR Description"))
  }

  @Test("Format review with different states")
  func testFormatReviewStates() {
    let states = [
      ("APPROVED", "✅"),
      ("CHANGES_REQUESTED", "❌"),
      ("COMMENTED", "💭"),
      ("PENDING", "⏳"),
    ]

    for (state, expectedEmoji) in states {
      let pr = PullRequest(
        body: "",
        comments: [],
        reviews: [
          Review(
            id: "1",
            author: Author(login: "reviewer"),
            authorAssociation: "MEMBER",
            body: "Review comment",
            submittedAt: "2025-12-18T10:00:00Z",
            state: state
          )
        ]
      )

      let formatter = PRCommentsFormatter()
      let output = formatter.format(pr, includeBody: false)

      #expect(output.contains(expectedEmoji))
      #expect(output.contains("@reviewer"))
    }
  }

  @Test("Format inline code comments")
  func testFormatInlineComments() {
    let pr = PullRequest(
      body: "",
      comments: [],
      reviews: [
        Review(
          id: "1",
          author: Author(login: "reviewer"),
          authorAssociation: "MEMBER",
          body: nil,
          submittedAt: "2025-12-18T10:00:00Z",
          state: "COMMENTED",
          comments: [
            ReviewComment(
              id: "1",
              path: "Sources/Test.swift",
              line: 100,
              body: "This needs refactoring",
              createdAt: "2025-12-18T10:00:00Z"
            )
          ]
        )
      ]
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    #expect(output.contains("📝 Code Comments"))
    #expect(output.contains("📍 Sources/Test.swift:100"))
    #expect(output.contains("This needs refactoring"))
  }

  @Test("Handle empty PR")
  func testEmptyPR() {
    let pr = PullRequest(
      body: "",
      comments: [],
      reviews: []
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    #expect(output == "No comments found.")
  }

  @Test("Handle multiline comment body")
  func testMultilineComment() {
    let pr = PullRequest(
      body: "",
      comments: [
        Comment(
          id: "1",
          author: Author(login: "user"),
          authorAssociation: "MEMBER",
          body: "Line 1\nLine 2\nLine 3",
          createdAt: "2025-12-18T10:00:00Z",
          url: "https://test.com"
        )
      ],
      reviews: []
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    #expect(output.contains("Line 1"))
    #expect(output.contains("Line 2"))
    #expect(output.contains("Line 3"))
  }

  @Test("Formatter displays comment IDs")
  func testCommentIDDisplay() {
    let pr = PullRequest(
      body: "",
      comments: [
        Comment(
          id: "IC_kwDOKtest_c5aXYZ",
          author: Author(login: "user"),
          authorAssociation: "MEMBER",
          body: "Test comment",
          createdAt: "2025-12-18T10:00:00Z",
          url: "https://test.com"
        )
      ],
      reviews: []
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    #expect(output.contains("ID: IC_kwDOKtest_c5aXYZ"))
  }

  @Test("Formatter displays thread IDs for review comments")
  func testThreadIDDisplay() {
    // Thread IDs (PRRT_xxx) come from GraphQL and are attached to individual comments
    // Review IDs (PRR_xxx) should NOT be shown as "Thread:" since they're different
    let pr = PullRequest(
      body: "",
      comments: [],
      reviews: [
        Review(
          id: "PRR_kwDOKtest_review123",
          author: Author(login: "reviewer"),
          authorAssociation: "MEMBER",
          body: nil,
          submittedAt: "2025-12-18T10:00:00Z",
          state: "COMMENTED",
          comments: [
            ReviewComment(
              id: "12345",
              path: "src/main.swift",
              line: 42,
              body: "This needs work",
              createdAt: "2025-12-18T10:00:00Z",
              threadId: "PRRT_kwDOKtest_thread456"
            )
          ]
        )
      ]
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    // Thread ID should appear on the comment line, not the review line
    #expect(output.contains("Thread: PRRT_kwDOKtest_thread456"))
    // Review ID should NOT appear as "Thread:"
    #expect(!output.contains("Thread: PRR_"))
  }

  @Test("Formatter displays review comment IDs")
  func testReviewCommentIDDisplay() {
    let pr = PullRequest(
      body: "",
      comments: [],
      reviews: [
        Review(
          id: "1",
          author: Author(login: "reviewer"),
          authorAssociation: "MEMBER",
          body: nil,
          submittedAt: "2025-12-18T10:00:00Z",
          state: "COMMENTED",
          comments: [
            ReviewComment(
              id: "PRRC_kwDOKtest_inlineABC",
              path: "Sources/Test.swift",
              line: 42,
              body: "Consider refactoring",
              createdAt: "2025-12-18T10:00:00Z"
            )
          ]
        )
      ]
    )

    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: false)

    #expect(output.contains("ID: PRRC_kwDOKtest_inlineABC"))
    #expect(output.contains("Sources/Test.swift:42"))
  }
}
