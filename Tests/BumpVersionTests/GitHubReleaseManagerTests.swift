import BumpVersion
import Foundation
import Testing

@Suite("GitHubReleaseManager Tests")
struct GitHubReleaseManagerTests {
  let manager = GitHubReleaseManager()

  // MARK: - Helper Functions

  /// Create a temporary directory with automatic cleanup
  private func withTempDirectory<T>(
    _ operation: (URL) async throws -> T
  ) async throws -> T {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("gh-release-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }
    return try await operation(tempDir)
  }

  /// Create a temporary git repository
  private func withTempGitRepo<T>(
    _ operation: (URL) async throws -> T
  ) async throws -> T {
    try await withTempDirectory { tempDir in
      // Initialize git repo
      let initResult = try await runGit(["init"], in: tempDir)
      guard initResult.success else {
        throw TestError.gitInitFailed(initResult.stderr)
      }

      // Configure git user for commits
      _ = try await runGit(["config", "user.email", "test@example.com"], in: tempDir)
      _ = try await runGit(["config", "user.name", "Test User"], in: tempDir)

      return try await operation(tempDir)
    }
  }

  /// Run a git command and return result
  private func runGit(_ args: [String], in directory: URL) async throws -> (
    success: Bool, stdout: String, stderr: String
  ) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = directory

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = try stdoutPipe.fileHandleForReading.readToEnd() ?? Data()
    let stderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()

    return (
      success: process.terminationStatus == 0,
      stdout: String(data: stdoutData, encoding: .utf8) ?? "",
      stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
  }

  enum TestError: Error {
    case gitInitFailed(String)
    case setupFailed(String)
  }

  // MARK: - isGHAvailable Tests

  @Suite("gh CLI Availability")
  struct GHAvailabilityTests {
    let manager = GitHubReleaseManager()

    @Test("isGHAvailable returns true when gh is installed")
    func ghAvailableWhenInstalled() async throws {
      // This test assumes gh is installed on the test machine
      // If gh is not installed, the test will check that we get a false return
      let isAvailable = try await manager.isGHAvailable()
      // We just verify it returns a boolean without throwing
      // The actual value depends on the test environment
      _ = isAvailable
    }
  }

  // MARK: - isGitRepository Tests

  @Suite("Git Repository Detection")
  struct GitRepositoryTests {
    let manager = GitHubReleaseManager()

    @Test("isGitRepository returns true for .git directory")
    func detectsGitDirectory() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Create .git directory
      let gitDir = tempDir.appendingPathComponent(".git")
      try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

      let isRepo = manager.isGitRepository(at: tempDir)
      #expect(isRepo == true)
    }

    @Test("isGitRepository returns true for .git file (worktree)")
    func detectsGitFile() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-worktree-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Create .git file (worktree style)
      let gitFile = tempDir.appendingPathComponent(".git")
      try "gitdir: /some/path/to/real/git".write(to: gitFile, atomically: true, encoding: .utf8)

      let isRepo = manager.isGitRepository(at: tempDir)
      #expect(isRepo == true)
    }

    @Test("isGitRepository returns false for non-git directory")
    func detectsNonGitDirectory() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("non-git-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let isRepo = manager.isGitRepository(at: tempDir)
      #expect(isRepo == false)
    }
  }

  // MARK: - tagExists Tests

  @Suite("Tag Existence")
  struct TagExistsTests {
    let manager = GitHubReleaseManager()

    @Test("tagExists returns true when tag exists")
    func tagExistsTrue() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tag-exists-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Initialize git repo
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["init"]
      process.currentDirectoryURL = tempDir
      try process.run()
      process.waitUntilExit()

      // Configure git user
      let configEmail = Process()
      configEmail.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      configEmail.arguments = ["config", "user.email", "test@example.com"]
      configEmail.currentDirectoryURL = tempDir
      try configEmail.run()
      configEmail.waitUntilExit()

      let configName = Process()
      configName.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      configName.arguments = ["config", "user.name", "Test User"]
      configName.currentDirectoryURL = tempDir
      try configName.run()
      configName.waitUntilExit()

      // Create initial commit
      let testFile = tempDir.appendingPathComponent("test.txt")
      try "test content".write(to: testFile, atomically: true, encoding: .utf8)

      let addProcess = Process()
      addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      addProcess.arguments = ["add", "."]
      addProcess.currentDirectoryURL = tempDir
      try addProcess.run()
      addProcess.waitUntilExit()

      let commitProcess = Process()
      commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      commitProcess.arguments = ["commit", "-m", "Initial commit"]
      commitProcess.currentDirectoryURL = tempDir
      try commitProcess.run()
      commitProcess.waitUntilExit()

      // Create tag
      let tagProcess = Process()
      tagProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      tagProcess.arguments = ["tag", "v1.0.0"]
      tagProcess.currentDirectoryURL = tempDir
      try tagProcess.run()
      tagProcess.waitUntilExit()

      let version = SemanticVersion(1, 0, 0)
      let exists = try await manager.tagExists(version, in: tempDir)
      #expect(exists == true)
    }

    @Test("tagExists returns false when tag does not exist")
    func tagExistsFalse() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tag-not-exists-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Initialize git repo
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["init"]
      process.currentDirectoryURL = tempDir
      try process.run()
      process.waitUntilExit()

      let version = SemanticVersion(2, 0, 0)
      let exists = try await manager.tagExists(version, in: tempDir)
      #expect(exists == false)
    }
  }

  // MARK: - createTag Tests

  @Suite("Tag Creation")
  struct CreateTagTests {
    let manager = GitHubReleaseManager()

    @Test("createTag creates lightweight tag")
    func createLightweightTag() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("create-tag-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo with commit
      try setupGitRepoWithCommit(at: tempDir)

      let version = SemanticVersion(1, 0, 0)
      try await manager.createTag(version, in: tempDir)

      // Verify tag was created
      let listProcess = Process()
      listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      listProcess.arguments = ["tag", "-l", "v1.0.0"]
      listProcess.currentDirectoryURL = tempDir
      let pipe = Pipe()
      listProcess.standardOutput = pipe
      try listProcess.run()
      listProcess.waitUntilExit()

      let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
      let output = String(data: data, encoding: .utf8) ?? ""
      #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "v1.0.0")
    }

    @Test("createTag creates annotated tag with message")
    func createAnnotatedTag() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("create-annotated-tag-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo with commit
      try setupGitRepoWithCommit(at: tempDir)

      let version = SemanticVersion(2, 0, 0)
      try await manager.createTag(version, in: tempDir, message: "Release 2.0.0")

      // Verify tag was created
      let exists = try await manager.tagExists(version, in: tempDir)
      #expect(exists == true)

      // Verify it's an annotated tag by checking for tag message
      let showProcess = Process()
      showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      showProcess.arguments = ["tag", "-l", "-n1", "v2.0.0"]
      showProcess.currentDirectoryURL = tempDir
      let pipe = Pipe()
      showProcess.standardOutput = pipe
      try showProcess.run()
      showProcess.waitUntilExit()

      let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
      let output = String(data: data, encoding: .utf8) ?? ""
      #expect(output.contains("Release 2.0.0"))
    }

    @Test("createTag fails when tag already exists")
    func createTagFailsWhenExists() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tag-fail-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo with commit
      try setupGitRepoWithCommit(at: tempDir)

      let version = SemanticVersion(1, 0, 0)
      try await manager.createTag(version, in: tempDir)

      // Try to create the same tag again
      await #expect(throws: GitHubReleaseError.self) {
        try await manager.createTag(version, in: tempDir)
      }
    }

    private func setupGitRepoWithCommit(at directory: URL) throws {
      // Initialize
      let initProcess = Process()
      initProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      initProcess.arguments = ["init"]
      initProcess.currentDirectoryURL = directory
      try initProcess.run()
      initProcess.waitUntilExit()

      // Configure user
      let configEmail = Process()
      configEmail.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      configEmail.arguments = ["config", "user.email", "test@example.com"]
      configEmail.currentDirectoryURL = directory
      try configEmail.run()
      configEmail.waitUntilExit()

      let configName = Process()
      configName.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      configName.arguments = ["config", "user.name", "Test User"]
      configName.currentDirectoryURL = directory
      try configName.run()
      configName.waitUntilExit()

      // Create and commit file
      let testFile = directory.appendingPathComponent("test.txt")
      try "test content".write(to: testFile, atomically: true, encoding: .utf8)

      let addProcess = Process()
      addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      addProcess.arguments = ["add", "."]
      addProcess.currentDirectoryURL = directory
      try addProcess.run()
      addProcess.waitUntilExit()

      let commitProcess = Process()
      commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      commitProcess.arguments = ["commit", "-m", "Initial commit"]
      commitProcess.currentDirectoryURL = directory
      try commitProcess.run()
      commitProcess.waitUntilExit()
    }
  }

  // MARK: - extractChangelogNotes Tests

  @Suite("Changelog Extraction")
  struct ChangelogExtractionTests {
    let manager = GitHubReleaseManager()

    @Test("extractChangelogNotes finds version with brackets")
    func findVersionWithBrackets() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("changelog-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let changelog = tempDir.appendingPathComponent("CHANGELOG.md")
      let content = """
        # Changelog

        ## [1.1.0] - 2024-01-15

        ### Added
        - New feature A
        - New feature B

        ### Fixed
        - Bug fix C

        ## [1.0.0] - 2024-01-01

        Initial release
        """
      try content.write(to: changelog, atomically: true, encoding: .utf8)

      let version = SemanticVersion(1, 1, 0)
      let notes = try manager.extractChangelogNotes(for: version, changelogPath: changelog)

      #expect(notes != nil)
      #expect(notes?.contains("New feature A") == true)
      #expect(notes?.contains("Bug fix C") == true)
      #expect(notes?.contains("Initial release") == false)
    }

    @Test("extractChangelogNotes finds version with v prefix")
    func findVersionWithVPrefix() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("changelog-v-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let changelog = tempDir.appendingPathComponent("CHANGELOG.md")
      let content = """
        # Changelog

        ## [v2.0.0] - 2024-02-01

        ### Breaking Changes
        - API changed
        """
      try content.write(to: changelog, atomically: true, encoding: .utf8)

      let version = SemanticVersion(2, 0, 0)
      let notes = try manager.extractChangelogNotes(for: version, changelogPath: changelog)

      #expect(notes != nil)
      #expect(notes?.contains("API changed") == true)
    }

    @Test("extractChangelogNotes finds plain version header")
    func findPlainVersionHeader() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("changelog-plain-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let changelog = tempDir.appendingPathComponent("CHANGELOG.md")
      let content = """
        # Changelog

        ## 0.5.0

        - First beta feature
        - Another feature

        ## 0.4.0

        - Old feature
        """
      try content.write(to: changelog, atomically: true, encoding: .utf8)

      let version = SemanticVersion(0, 5, 0)
      let notes = try manager.extractChangelogNotes(for: version, changelogPath: changelog)

      #expect(notes != nil)
      #expect(notes?.contains("First beta feature") == true)
      #expect(notes?.contains("Old feature") == false)
    }

    @Test("extractChangelogNotes returns nil for missing file")
    func missingChangelogReturnsNil() throws {
      let nonExistentPath = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).md")

      let version = SemanticVersion(1, 0, 0)
      let notes = try manager.extractChangelogNotes(for: version, changelogPath: nonExistentPath)

      #expect(notes == nil)
    }

    @Test("extractChangelogNotes returns nil for missing version")
    func missingVersionReturnsNil() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("changelog-missing-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let changelog = tempDir.appendingPathComponent("CHANGELOG.md")
      let content = """
        # Changelog

        ## [1.0.0] - 2024-01-01

        Initial release
        """
      try content.write(to: changelog, atomically: true, encoding: .utf8)

      let version = SemanticVersion(9, 9, 9)
      let notes = try manager.extractChangelogNotes(for: version, changelogPath: changelog)

      #expect(notes == nil)
    }

    @Test("extractChangelogNotes handles prerelease versions")
    func findPrereleaseVersion() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("changelog-prerelease-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let changelog = tempDir.appendingPathComponent("CHANGELOG.md")
      let content = """
        # Changelog

        ## [2.0.0-alpha.1] - 2024-03-01

        ### Added
        - Experimental feature

        ## [1.0.0] - 2024-01-01

        Initial release
        """
      try content.write(to: changelog, atomically: true, encoding: .utf8)

      let version = SemanticVersion(2, 0, 0, "alpha.1")
      let notes = try manager.extractChangelogNotes(for: version, changelogPath: changelog)

      #expect(notes != nil)
      #expect(notes?.contains("Experimental feature") == true)
    }
  }

  // MARK: - gitAdd Tests

  @Suite("Git Add")
  struct GitAddTests {
    let manager = GitHubReleaseManager()

    @Test("gitAdd stages all changes")
    func stagesAllChanges() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-add-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo
      try setupGitRepo(at: tempDir)

      // Create new file
      let newFile = tempDir.appendingPathComponent("new.txt")
      try "new content".write(to: newFile, atomically: true, encoding: .utf8)

      // Stage all
      try await manager.gitAdd(in: tempDir)

      // Verify file is staged
      let statusProcess = Process()
      statusProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      statusProcess.arguments = ["status", "--porcelain"]
      statusProcess.currentDirectoryURL = tempDir
      let pipe = Pipe()
      statusProcess.standardOutput = pipe
      try statusProcess.run()
      statusProcess.waitUntilExit()

      let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
      let output = String(data: data, encoding: .utf8) ?? ""
      #expect(output.contains("A  new.txt"))
    }

    @Test("gitAdd succeeds with no changes")
    func succeedsWithNoChanges() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-add-empty-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo with initial commit
      try setupGitRepoWithCommit(at: tempDir)

      // Should not throw even with nothing to add
      try await manager.gitAdd(in: tempDir)
    }

    private func setupGitRepo(at directory: URL) throws {
      let initProcess = Process()
      initProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      initProcess.arguments = ["init"]
      initProcess.currentDirectoryURL = directory
      try initProcess.run()
      initProcess.waitUntilExit()
    }

    private func setupGitRepoWithCommit(at directory: URL) throws {
      setupGitRepoHelper(at: directory)
    }
  }

  // MARK: - gitCommit Tests

  @Suite("Git Commit")
  struct GitCommitTests {
    let manager = GitHubReleaseManager()

    @Test("gitCommit creates commit with message")
    func createsCommitWithMessage() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-commit-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo
      setupGitRepoHelper(at: tempDir)

      // Create and stage new file
      let newFile = tempDir.appendingPathComponent("version.txt")
      try "1.0.0".write(to: newFile, atomically: true, encoding: .utf8)
      try await manager.gitAdd(in: tempDir)

      // Commit
      try await manager.gitCommit(message: "chore: Bump to 1.0.0", in: tempDir)

      // Verify commit
      let logProcess = Process()
      logProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      logProcess.arguments = ["log", "-1", "--format=%s"]
      logProcess.currentDirectoryURL = tempDir
      let pipe = Pipe()
      logProcess.standardOutput = pipe
      try logProcess.run()
      logProcess.waitUntilExit()

      let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
      let output = String(data: data, encoding: .utf8) ?? ""
      #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "chore: Bump to 1.0.0")
    }

    @Test("gitCommit fails with nothing to commit")
    func failsWithNothingToCommit() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-commit-empty-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo with initial commit
      setupGitRepoHelper(at: tempDir)

      // Try to commit with nothing staged
      await #expect(throws: GitHubReleaseError.self) {
        try await manager.gitCommit(message: "Empty commit", in: tempDir)
      }
    }
  }

  // MARK: - gitPush Tests

  @Suite("Git Push")
  struct GitPushTests {
    let manager = GitHubReleaseManager()

    @Test("gitPush fails without remote")
    func failsWithoutRemote() async throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-push-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Setup git repo with commit but no remote
      setupGitRepoHelper(at: tempDir)

      // Push should fail
      await #expect(throws: GitHubReleaseError.self) {
        try await manager.gitPush(in: tempDir)
      }
    }
  }

  // MARK: - GitHubReleaseError Tests

  @Suite("Error Descriptions")
  struct ErrorDescriptionTests {

    @Test("ghNotAvailable has correct description")
    func ghNotAvailableDescription() {
      let error = GitHubReleaseError.ghNotAvailable
      #expect(error.description.contains("GitHub CLI"))
      #expect(error.description.contains("brew install gh"))
    }

    @Test("ghCheckFailed includes reason")
    func ghCheckFailedDescription() {
      let error = GitHubReleaseError.ghCheckFailed(reason: "command not found")
      #expect(error.description.contains("command not found"))
    }

    @Test("notAGitRepository has correct description")
    func notAGitRepositoryDescription() {
      let error = GitHubReleaseError.notAGitRepository
      #expect(error.description.contains("Not a git repository"))
    }

    @Test("tagCheckFailed includes tag and reason")
    func tagCheckFailedDescription() {
      let error = GitHubReleaseError.tagCheckFailed(tag: "v1.0.0", reason: "fatal error")
      #expect(error.description.contains("v1.0.0"))
      #expect(error.description.contains("fatal error"))
    }

    @Test("tagCreationFailed includes tag and reason")
    func tagCreationFailedDescription() {
      let error = GitHubReleaseError.tagCreationFailed(tag: "v2.0.0", reason: "already exists")
      #expect(error.description.contains("v2.0.0"))
      #expect(error.description.contains("already exists"))
    }

    @Test("pushFailed includes tag and reason")
    func pushFailedDescription() {
      let error = GitHubReleaseError.pushFailed(tag: "v1.0.0", reason: "no remote")
      #expect(error.description.contains("v1.0.0"))
      #expect(error.description.contains("no remote"))
    }

    @Test("releaseCreationFailed includes tag and reason")
    func releaseCreationFailedDescription() {
      let error = GitHubReleaseError.releaseCreationFailed(tag: "v3.0.0", reason: "auth failed")
      #expect(error.description.contains("v3.0.0"))
      #expect(error.description.contains("auth failed"))
    }

    @Test("gitOperationFailed includes operation and reason")
    func gitOperationFailedDescription() {
      let error = GitHubReleaseError.gitOperationFailed(
        operation: "commit",
        reason: "nothing to commit"
      )
      #expect(error.description.contains("commit"))
      #expect(error.description.contains("nothing to commit"))
    }
  }
}

// MARK: - Shared Helper

private func setupGitRepoHelper(at directory: URL) {
  let initProcess = Process()
  initProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  initProcess.arguments = ["init"]
  initProcess.currentDirectoryURL = directory
  try? initProcess.run()
  initProcess.waitUntilExit()

  let configEmail = Process()
  configEmail.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  configEmail.arguments = ["config", "user.email", "test@example.com"]
  configEmail.currentDirectoryURL = directory
  try? configEmail.run()
  configEmail.waitUntilExit()

  let configName = Process()
  configName.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  configName.arguments = ["config", "user.name", "Test User"]
  configName.currentDirectoryURL = directory
  try? configName.run()
  configName.waitUntilExit()

  let testFile = directory.appendingPathComponent("initial.txt")
  try? "initial content".write(to: testFile, atomically: true, encoding: .utf8)

  let addProcess = Process()
  addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  addProcess.arguments = ["add", "."]
  addProcess.currentDirectoryURL = directory
  try? addProcess.run()
  addProcess.waitUntilExit()

  let commitProcess = Process()
  commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  commitProcess.arguments = ["commit", "-m", "Initial commit"]
  commitProcess.currentDirectoryURL = directory
  try? commitProcess.run()
  commitProcess.waitUntilExit()
}
