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
    abstract: "View and interact with GitHub PR comments",
    discussion: """
      View, reply to, and resolve GitHub PR comments, including inline code review comments.
      Uses the `gh` CLI to fetch and update PR data.
      
      Examples:
        pr-comments 29                         # View comments for PR #29
        pr-comments 29 --with-body             # Include PR description
        pr-comments --current                  # View current branch's PR
        pr-comments 29 --provider github       # Use specific provider
      """,
    subcommands: [View.self],
    defaultSubcommand: View.self
  )
}

// MARK: - View Subcommand

struct View: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "view",
    abstract: "View PR comments in a readable format"
  )
  
  @Argument(help: "PR number or URL")
  var prNumber: String?
  
  @Flag(name: .long, help: "Use PR from current branch")
  var current: Bool = false
  
  @Flag(name: .long, help: "Include PR body/description")
  var withBody: Bool = false
  
  @Option(name: .shortAndLong, help: "Repository (owner/repo)")
  var repo: String?
  
  @Option(name: .long, help: "Provider to use (github, gitlab, azure)")
  var provider: String?
  
  func run() async throws {
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

    // Create provider
    let factory = ProviderFactory()
    let providerType: ProviderType?
    if let providerStr = provider {
      providerType = ProviderType(rawValue: providerStr.capitalized)
    } else {
      providerType = nil
    }
    
    let prProvider = try await factory.createProvider(manualType: providerType)
    print("Using \(prProvider.name) provider")

    // Fetch PR data
    let pr = try await prProvider.fetchPR(identifier: prIdentifier, repo: repo)

    // Format and print
    let formatter = PRCommentsFormatter()
    let output = formatter.format(pr, includeBody: withBody)
    print(output)
  }
}

