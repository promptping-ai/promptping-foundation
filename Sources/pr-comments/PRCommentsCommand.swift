import ArgumentParser
import Foundation
import PRComments
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

@main
struct PRCommentsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pr-comments",
    abstract: "View GitHub PR comments in a readable format",
    discussion: """
      Fetches and formats GitHub PR comments, including inline code review comments.
      Uses the `gh` CLI to fetch PR data.

      Examples:
        pr-comments 29                    # View comments for PR #29
        pr-comments 29 --with-body        # Include PR description
        pr-comments --current             # View comments for current branch's PR
      """
  )

  @Argument(help: "PR number or URL")
  var prNumber: String?

  @Flag(name: .long, help: "Use PR from current branch")
  var current: Bool = false

  @Flag(name: .long, help: "Include PR body/description")
  var withBody: Bool = false

  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?

  func run() async throws {
    // Validate gh CLI availability
    let ghPath = try await findExecutable(name: "gh")

    // Determine PR identifier
    let prIdentifier: String
    if current {
      if prNumber != nil {
        throw ValidationError("Cannot specify both PR number and --current flag")
      }
      prIdentifier = ""  // Empty means current branch
    } else if let number = prNumber {
      prIdentifier = number
    } else {
      throw ValidationError("Must specify either a PR number or use --current flag")
    }

    // Build gh command
    var args: [String] = ["pr", "view"]
    if !prIdentifier.isEmpty {
      args.append(prIdentifier)
    }
    args.append(contentsOf: ["--json", "body,comments,reviews,files"])

    if let repo = repo {
      args.append(contentsOf: ["--repo", repo])
    }

    // Execute gh command
    let result = try await Subprocess.run(
      ghPath,
      arguments: Arguments(args),
      output: .bytes(limit: 10 * 1024 * 1024),  // 10MB limit
      error: .bytes(limit: 1024 * 1024)  // 1MB limit
    )

    guard result.terminationStatus.isSuccess else {
      let stderr = String(decoding: result.standardError, as: UTF8.self)
      throw PRCommentsError.ghCommandFailed(stderr)
    }

    // Parse JSON response
    let jsonData = Data(result.standardOutput)
    let decoder = JSONDecoder()
    let pr = try decoder.decode(PullRequest.self, from: jsonData)

    // Format and print
    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: withBody)
    print(output)
  }

  private func findExecutable(name: String) async throws -> Subprocess.Executable {
    // Try common paths
    let commonPaths = [
      "/usr/local/bin/\(name)",
      "/opt/homebrew/bin/\(name)",
      "/usr/bin/\(name)",
    ]

    for path in commonPaths {
      if FileManager.default.fileExists(atPath: path) {
        return .path(FilePath(path))
      }
    }

    // Try using `which`
    let whichResult = try await Subprocess.run(
      .name("which"),
      arguments: Arguments([name]),
      output: .bytes(limit: 1024),
      error: .discarded
    )

    if whichResult.terminationStatus.isSuccess {
      let path = String(decoding: whichResult.standardOutput, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !path.isEmpty {
        return .path(FilePath(path))
      }
    }

    throw PRCommentsError.executableNotFound(name)
  }
}

enum PRCommentsError: Error, CustomStringConvertible {
  case executableNotFound(String)
  case ghCommandFailed(String)

  var description: String {
    switch self {
    case .executableNotFound(let name):
      return "\(name) not found. Please install GitHub CLI: https://cli.github.com/"
    case .ghCommandFailed(let stderr):
      return "gh command failed: \(stderr)"
    }
  }
}
