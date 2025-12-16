import Foundation
import Testing

@testable import AtomicInstall

@Suite("AtomicBinaryInstaller Tests")
struct AtomicBinaryInstallerTests {

  let tempDir: URL

  init() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("AtomicInstallTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  // MARK: - Success Cases

  @Test("Install new binary when destination doesn't exist")
  func installNewBinary() throws {
    let sourceDir = tempDir.appendingPathComponent("source")
    let destDir = tempDir.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create source file
    let sourceFile = sourceDir.appendingPathComponent("my-binary")
    try "#!/bin/bash\necho hello".write(to: sourceFile, atomically: true, encoding: .utf8)

    let destFile = destDir.appendingPathComponent("my-binary")

    let installer = AtomicBinaryInstaller()
    let result = try installer.install([(source: sourceFile, destination: destFile)])

    #expect(result.installedFiles == ["my-binary"])
    #expect(result.backupsCreated == 0)
    #expect(FileManager.default.fileExists(atPath: destFile.path))

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
  }

  @Test("Install binary with existing file creates backup")
  func installWithExistingBinary() throws {
    let sourceDir = tempDir.appendingPathComponent("source")
    let destDir = tempDir.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create source file (new version)
    let sourceFile = sourceDir.appendingPathComponent("my-binary")
    try "NEW VERSION".write(to: sourceFile, atomically: true, encoding: .utf8)

    // Create existing destination file (old version)
    let destFile = destDir.appendingPathComponent("my-binary")
    try "OLD VERSION".write(to: destFile, atomically: true, encoding: .utf8)

    let installer = AtomicBinaryInstaller()
    let result = try installer.install([(source: sourceFile, destination: destFile)])

    #expect(result.installedFiles == ["my-binary"])
    #expect(result.backupsCreated == 1)

    // Verify new content
    let content = try String(contentsOf: destFile, encoding: .utf8)
    #expect(content == "NEW VERSION")

    // Verify backup was cleaned up
    let backupFiles = try FileManager.default.contentsOfDirectory(
      at: destDir, includingPropertiesForKeys: nil
    )
    .filter { $0.lastPathComponent.contains(".bak.") }
    #expect(backupFiles.isEmpty)

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
  }

  @Test("Install multiple binaries atomically")
  func installMultipleBinaries() throws {
    let sourceDir = tempDir.appendingPathComponent("source")
    let destDir = tempDir.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create source files
    let source1 = sourceDir.appendingPathComponent("binary1")
    let source2 = sourceDir.appendingPathComponent("binary2")
    try "BINARY1".write(to: source1, atomically: true, encoding: .utf8)
    try "BINARY2".write(to: source2, atomically: true, encoding: .utf8)

    let dest1 = destDir.appendingPathComponent("binary1")
    let dest2 = destDir.appendingPathComponent("binary2")

    let installer = AtomicBinaryInstaller()
    let result = try installer.install([
      (source: source1, destination: dest1),
      (source: source2, destination: dest2),
    ])

    #expect(result.installedFiles.count == 2)
    #expect(FileManager.default.fileExists(atPath: dest1.path))
    #expect(FileManager.default.fileExists(atPath: dest2.path))

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
  }

  // MARK: - Error Cases

  @Test("Source not found throws appropriate error")
  func sourceNotFound() throws {
    let nonExistentSource = tempDir.appendingPathComponent("nonexistent")
    let destFile = tempDir.appendingPathComponent("dest/binary")

    let installer = AtomicBinaryInstaller()

    #expect(throws: InstallError.self) {
      try installer.install([(source: nonExistentSource, destination: destFile)])
    }

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
  }

  // MARK: - RollbackResult Tests

  @Test("RollbackResult correctly identifies all succeeded")
  func rollbackResultAllSucceeded() {
    let result = RollbackResult(
      restorations: [
        RollbackResult.FileRestoration(
          originalPath: "/path/to/file1",
          backupPath: "/path/to/file1.bak",
          status: .restored
        ),
        RollbackResult.FileRestoration(
          originalPath: "/path/to/file2",
          backupPath: "/path/to/file2.bak",
          status: .noBackupNeeded
        ),
      ],
      stagedFilesCleanup: [
        RollbackResult.StagedFileCleanup(path: "/staged1", success: true)
      ]
    )

    #expect(result.allSucceeded == true)
    #expect(result.failures.isEmpty)
    #expect(result.successes.count == 1)
  }

  @Test("RollbackResult correctly identifies failures")
  func rollbackResultWithFailures() {
    let result = RollbackResult(
      restorations: [
        RollbackResult.FileRestoration(
          originalPath: "/path/to/file1",
          backupPath: "/path/to/file1.bak",
          status: .restored
        ),
        RollbackResult.FileRestoration(
          originalPath: "/path/to/file2",
          backupPath: "/path/to/file2.bak",
          status: .failed("Permission denied")
        ),
      ],
      stagedFilesCleanup: []
    )

    #expect(result.allSucceeded == false)
    #expect(result.failures.count == 1)
    #expect(result.successes.count == 1)
  }

  @Test("RollbackResult generates manual fix commands")
  func rollbackResultManualCommands() {
    let result = RollbackResult(
      restorations: [
        RollbackResult.FileRestoration(
          originalPath: "/usr/local/bin/my-daemon",
          backupPath: "/usr/local/bin/my-daemon.bak.ABC123",
          status: .failed("Permission denied")
        )
      ],
      stagedFilesCleanup: []
    )

    let commands = result.manualFixCommands
    #expect(commands.count == 3)
    #expect(commands[0].contains("rm -f"))
    #expect(commands[1].contains("mv"))
    #expect(commands[2].contains("chmod 755"))
  }

  @Test("RollbackResult summary describes status correctly")
  func rollbackResultSummary() {
    let successResult = RollbackResult(
      restorations: [
        RollbackResult.FileRestoration(
          originalPath: "/path/file",
          backupPath: "/path/file.bak",
          status: .restored
        )
      ],
      stagedFilesCleanup: []
    )
    #expect(successResult.summary.contains("complete"))

    let failureResult = RollbackResult(
      restorations: [
        RollbackResult.FileRestoration(
          originalPath: "/path/file",
          backupPath: "/path/file.bak",
          status: .failed("Error")
        )
      ],
      stagedFilesCleanup: []
    )
    #expect(failureResult.summary.contains("PARTIAL"))
  }

  // MARK: - InstallError Tests

  @Test("InstallError description includes rollback status")
  func installErrorWithRollbackStatus() {
    let rollbackResult = RollbackResult(
      restorations: [
        RollbackResult.FileRestoration(
          originalPath: "/path/to/restored",
          backupPath: "/path/to/restored.bak",
          status: .restored
        ),
        RollbackResult.FileRestoration(
          originalPath: "/path/to/failed",
          backupPath: "/path/to/failed.bak",
          status: .failed("Permission denied")
        ),
      ],
      stagedFilesCleanup: []
    )

    let error = InstallError.installationFailed(
      phase: "swap",
      file: "my-daemon",
      underlying: "File exists",
      rollbackResult: rollbackResult
    )

    let description = error.description
    #expect(description.contains("INSTALLATION FAILED"))
    #expect(description.contains("swap"))
    #expect(description.contains("SUCCESSFULLY RESTORED"))
    #expect(description.contains("FAILED TO RESTORE"))
    #expect(description.contains("MANUAL RECOVERY COMMANDS"))
    #expect(description.contains("rm -f"))
    #expect(description.contains("mv"))
  }
}
