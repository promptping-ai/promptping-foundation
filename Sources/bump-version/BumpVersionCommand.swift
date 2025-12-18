import ArgumentParser
import BumpVersion
import Foundation

@main
struct BumpVersionCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bump-version",
    abstract: "Bump semantic version in Swift packages",
    discussion: """
      A generic version bump tool for Swift packages. Updates Version.swift files
      and optionally creates GitHub releases.

      Examples:
        bump-version patch                    # 1.0.0 -> 1.0.1
        bump-version minor                    # 1.0.0 -> 1.1.0
        bump-version major                    # 1.0.0 -> 2.0.0
        bump-version patch --alpha            # 1.0.0 -> 1.0.1-alpha.1
        bump-version --release                # 1.0.1-alpha.1 -> 1.0.1
        bump-version patch --release --tag    # Bump, commit, tag, push
        bump-version patch --gh-release       # Create GitHub release
      """,
    version: "1.0.0"
  )

  // MARK: - Version Bump Type

  @Argument(help: "Version component to bump: major, minor, or patch")
  var component: VersionComponent?

  enum VersionComponent: String, ExpressibleByArgument, CaseIterable {
    case major
    case minor
    case patch
  }

  // MARK: - Prerelease Options

  @Flag(name: .long, help: "Create alpha prerelease (e.g., 1.0.0-alpha.1)")
  var alpha = false

  @Flag(name: .long, help: "Create beta prerelease (e.g., 1.0.0-beta.1)")
  var beta = false

  @Flag(name: .long, help: "Create release candidate (e.g., 1.0.0-rc.1)")
  var rc = false

  @Flag(name: .long, help: "Remove prerelease suffix for final release")
  var release = false

  // MARK: - Git Options

  @Flag(name: .long, help: "Create and push git tag")
  var tag = false

  @Flag(name: .long, help: "Commit version changes")
  var commit = false

  @Flag(name: .long, help: "Push commits and tags to remote")
  var push = false

  // MARK: - GitHub Release Options

  @Flag(name: .long, help: "Create GitHub release (implies --tag)")
  var ghRelease = false

  @Flag(name: .long, help: "Create as draft release")
  var draft = false

  @Flag(name: .long, help: "Auto-generate release notes from commits")
  var generateNotes = false

  @Option(name: .long, help: "Release title (default: 'Release vX.Y.Z')")
  var title: String?

  @Option(name: .long, help: "Release notes (or use --notes-file)")
  var notes: String?

  @Option(name: .long, help: "File containing release notes")
  var notesFile: String?

  // MARK: - Other Options

  @Flag(name: .long, help: "Show what would be done without making changes")
  var dryRun = false

  @Flag(name: .shortAndLong, help: "Show current version and exit")
  var version = false

  @Option(name: .long, help: "Package directory (default: current directory)")
  var directory: String?

  @Option(name: .long, help: "Target name for new Version.swift (if none exists)")
  var targetName: String?

  // MARK: - Run

  func run() async throws {
    let workDir =
      directory.map { URL(fileURLWithPath: $0) }
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    // Validate directory exists
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: workDir.path, isDirectory: &isDir),
      isDir.boolValue
    else {
      throw ValidationError("Directory does not exist: \(workDir.path)")
    }

    let versionManager = VersionFileManager()
    let releaseManager = GitHubReleaseManager()

    // Find existing version file
    let versionFile = try versionManager.findVersionFile(in: workDir)

    // If --version flag, just show current version
    if version {
      if let file = versionFile {
        let currentVersion = try versionManager.readVersion(from: file)
        print(currentVersion)
      } else {
        print("No Version.swift found")
      }
      return
    }

    // Determine current version
    let currentVersion: SemanticVersion
    if let file = versionFile {
      currentVersion = try versionManager.readVersion(from: file)
    } else if component != nil || release {
      // Need to create new version file
      currentVersion = SemanticVersion(0, 0, 0)
    } else {
      throw ValidationError("No Version.swift found. Specify --target-name to create one.")
    }

    print("Current version: \(currentVersion)")

    // Calculate new version
    var newVersion = currentVersion

    // Apply component bump if specified
    if let component {
      switch component {
      case .major:
        newVersion = newVersion.bumpMajor()
      case .minor:
        newVersion = newVersion.bumpMinor()
      case .patch:
        newVersion = newVersion.bumpPatch()
      }
    }

    // Apply prerelease modifier
    if alpha {
      newVersion = newVersion.bumpPrerelease(.alpha)
    } else if beta {
      newVersion = newVersion.bumpPrerelease(.beta)
    } else if rc {
      newVersion = newVersion.bumpPrerelease(.rc)
    } else if release {
      newVersion = newVersion.release()
    }

    // Validate we actually changed something
    if newVersion == currentVersion && component == nil && !release {
      throw ValidationError(
        "No version change specified. Use major/minor/patch, --alpha/--beta/--rc, or --release.")
    }

    print("New version: \(newVersion)")

    if dryRun {
      print("[dry-run] Would update version to \(newVersion)")
      if commit { print("[dry-run] Would commit changes") }
      if tag || ghRelease { print("[dry-run] Would create tag v\(newVersion)") }
      if push { print("[dry-run] Would push to remote") }
      if ghRelease { print("[dry-run] Would create GitHub release") }
      return
    }

    // Update or create version file
    let targetFile: URL
    let moduleName: String

    if let file = versionFile {
      targetFile = file
      moduleName = versionManager.extractModuleName(from: file)
    } else if let name = targetName {
      targetFile = try versionManager.createVersionFile(
        version: newVersion,
        packageDirectory: workDir,
        targetName: name
      )
      moduleName = name
      print("Created new Version.swift at \(targetFile.path)")
    } else {
      throw ValidationError(
        "No Version.swift found. Use --target-name to specify where to create one.")
    }

    try versionManager.writeVersion(newVersion, to: targetFile, moduleName: moduleName)
    print("Updated \(targetFile.path)")

    // Git operations
    if commit || tag || ghRelease || push {
      guard releaseManager.isGitRepository(at: workDir) else {
        throw ValidationError("Not a git repository")
      }
    }

    if commit {
      try await releaseManager.gitAdd(in: workDir)
      try await releaseManager.gitCommit(
        message: "chore: Bump version to \(newVersion)",
        in: workDir
      )
      print("Committed version bump")
    }

    if tag || ghRelease {
      // Check if tag already exists (idempotent retry support)
      if try await releaseManager.tagExists(newVersion, in: workDir) {
        print("Tag v\(newVersion) already exists, skipping creation")
      } else {
        let tagMessage = "Release \(newVersion)"
        try await releaseManager.createTag(newVersion, in: workDir, message: tagMessage)
        print("Created tag v\(newVersion)")
      }
    }

    if push {
      try await releaseManager.gitPush(in: workDir)
      print("Pushed commits")

      if tag || ghRelease {
        try await releaseManager.pushTag(newVersion, in: workDir)
        print("Pushed tag v\(newVersion)")
      }
    }

    // GitHub release
    if ghRelease {
      // Ensure tag is pushed
      if !push {
        try await releaseManager.pushTag(newVersion, in: workDir)
        print("Pushed tag v\(newVersion)")
      }

      // Get release notes
      var releaseNotes = notes
      var notesFileURL: URL?

      if let notesFilePath = notesFile {
        let fileURL = URL(fileURLWithPath: notesFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          throw ValidationError("Notes file does not exist: \(notesFilePath)")
        }
        notesFileURL = fileURL
      } else if releaseNotes == nil && !generateNotes {
        // Try to extract from CHANGELOG.md
        let changelogPath = workDir.appendingPathComponent("CHANGELOG.md")
        do {
          releaseNotes = try releaseManager.extractChangelogNotes(
            for: newVersion,
            changelogPath: changelogPath
          )
          if releaseNotes == nil {
            print("Warning: No section found for version \(newVersion) in CHANGELOG.md")
            print("         Using default release notes: 'Release \(newVersion)'")
          }
        } catch {
          print("Warning: Failed to read CHANGELOG.md: \(error.localizedDescription)")
          print("         Using default release notes: 'Release \(newVersion)'")
        }
      }

      let releaseURL = try await releaseManager.createRelease(
        version: newVersion,
        title: title,
        notes: releaseNotes,
        notesFile: notesFileURL,
        isDraft: draft,
        generateNotes: generateNotes && releaseNotes == nil && notesFileURL == nil,
        in: workDir
      )

      print("Created GitHub release: \(releaseURL)")
    }

    print("Done! Version bumped to \(newVersion)")
  }
}
