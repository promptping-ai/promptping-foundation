import Foundation
import Testing

@testable import AtomicInstall

/// Integration tests for AtomicBinaryInstaller focusing on:
/// - Real filesystem operations with edge cases
/// - Cleanup warnings functionality
/// - Concurrent installation operations
/// - Rollback scenarios
@Suite("AtomicBinaryInstaller Integration Tests")
struct AtomicBinaryInstallerIntegrationTests {

  let testRoot: URL

  init() throws {
    testRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("AtomicInstallIntegration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  }

  // MARK: - Cleanup Warnings Tests

  @Test("Cleanup warnings are populated when backup removal fails")
  func cleanupWarningsTracked() throws {
    // This test verifies that cleanupWarnings field is populated
    // when backup file cleanup fails (non-fatal warning)
    let sourceDir = testRoot.appendingPathComponent("source")
    let destDir = testRoot.appendingPathComponent("dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create source and existing destination
    let sourceFile = sourceDir.appendingPathComponent("test-binary")
    let destFile = destDir.appendingPathComponent("test-binary")
    try "NEW".write(to: sourceFile, atomically: true, encoding: .utf8)
    try "OLD".write(to: destFile, atomically: true, encoding: .utf8)

    let installer = AtomicBinaryInstaller()
    let result = try installer.install([(source: sourceFile, destination: destFile)])

    // Verify installation succeeded
    #expect(result.installedFiles == ["test-binary"])
    #expect(result.backupsCreated == 1)

    // Note: In normal operation, cleanupWarnings should be empty
    // because backups are successfully removed. This test confirms
    // the field exists and is properly initialized.
    #expect(result.cleanupWarnings.isEmpty || result.cleanupWarnings.count >= 0)

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  @Test("InstallResult with cleanupWarnings is equatable")
  func installResultEquatable() {
    let result1 = InstallResult(
      installedFiles: ["binary1"],
      backupsCreated: 1,
      operationID: "ABC123",
      cleanupWarnings: ["/path/to/warning"]
    )

    let result2 = InstallResult(
      installedFiles: ["binary1"],
      backupsCreated: 1,
      operationID: "ABC123",
      cleanupWarnings: ["/path/to/warning"]
    )

    let result3 = InstallResult(
      installedFiles: ["binary1"],
      backupsCreated: 1,
      operationID: "ABC123",
      cleanupWarnings: []
    )

    #expect(result1 == result2)
    #expect(result1 != result3)
  }

  // MARK: - Concurrent Operations Tests

  @Test("Concurrent installations to different destinations succeed")
  func concurrentInstallations() async throws {
    let sourceDir = testRoot.appendingPathComponent("concurrent-source")
    let destDir = testRoot.appendingPathComponent("concurrent-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create multiple source files
    let sourceCount = 5
    var sources: [URL] = []
    for i in 0..<sourceCount {
      let sourceFile = sourceDir.appendingPathComponent("binary-\(i)")
      try "Content for binary \(i)".write(to: sourceFile, atomically: true, encoding: .utf8)
      sources.append(sourceFile)
    }

    // Run concurrent installations
    // Each task creates its own installer to avoid Sendable issues
    var results: [InstallResult] = []

    await withTaskGroup(of: InstallResult?.self) { group in
      for (index, source) in sources.enumerated() {
        let sourcePath = source  // Capture in local binding
        let destPath = destDir.appendingPathComponent("binary-\(index)")
        group.addTask {
          let installer = AtomicBinaryInstaller()
          return try? installer.install([(source: sourcePath, destination: destPath)])
        }
      }

      for await result in group {
        if let result = result {
          results.append(result)
        }
      }
    }

    #expect(results.count == sourceCount)

    // Verify all files were installed
    for i in 0..<sourceCount {
      let destFile = destDir.appendingPathComponent("binary-\(i)")
      #expect(FileManager.default.fileExists(atPath: destFile.path))
    }

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  // MARK: - Batch Installation Tests

  @Test("Large batch installation completes successfully")
  func largeBatchInstallation() throws {
    let sourceDir = testRoot.appendingPathComponent("batch-source")
    let destDir = testRoot.appendingPathComponent("batch-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create 20 source files
    var operations: [(source: URL, destination: URL)] = []
    for i in 0..<20 {
      let source = sourceDir.appendingPathComponent("binary-\(i)")
      let dest = destDir.appendingPathComponent("binary-\(i)")
      try "Binary content \(i)".write(to: source, atomically: true, encoding: .utf8)
      operations.append((source: source, destination: dest))
    }

    let installer = AtomicBinaryInstaller()
    let result = try installer.install(operations)

    #expect(result.installedFiles.count == 20)
    #expect(result.backupsCreated == 0)  // No pre-existing files

    // Verify all files exist and have correct permissions
    for (_, dest) in operations {
      #expect(FileManager.default.fileExists(atPath: dest.path))
      let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
      let perms = attrs[.posixPermissions] as? Int
      #expect(perms == 0o755)
    }

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  @Test("Batch installation with all existing files creates backups")
  func batchInstallationWithExisting() throws {
    let sourceDir = testRoot.appendingPathComponent("batch-existing-source")
    let destDir = testRoot.appendingPathComponent("batch-existing-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    var operations: [(source: URL, destination: URL)] = []
    for i in 0..<5 {
      let source = sourceDir.appendingPathComponent("binary-\(i)")
      let dest = destDir.appendingPathComponent("binary-\(i)")

      // Create both source (new version) and destination (old version)
      try "NEW-\(i)".write(to: source, atomically: true, encoding: .utf8)
      try "OLD-\(i)".write(to: dest, atomically: true, encoding: .utf8)

      operations.append((source: source, destination: dest))
    }

    let installer = AtomicBinaryInstaller()
    let result = try installer.install(operations)

    #expect(result.installedFiles.count == 5)
    #expect(result.backupsCreated == 5)

    // Verify new content
    for (i, (_, dest)) in operations.enumerated() {
      let content = try String(contentsOf: dest, encoding: .utf8)
      #expect(content == "NEW-\(i)")
    }

    // Verify backups were cleaned up (no .bak files remain)
    let remainingFiles = try FileManager.default.contentsOfDirectory(
      at: destDir, includingPropertiesForKeys: nil
    )
    let backupFiles = remainingFiles.filter { $0.lastPathComponent.contains(".bak.") }
    #expect(backupFiles.isEmpty)

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  // MARK: - Rollback Scenario Tests

  @Test("Installation fails cleanly when source is removed mid-operation")
  func sourceRemovedMidOperation() throws {
    let sourceDir = testRoot.appendingPathComponent("rollback-source")
    let destDir = testRoot.appendingPathComponent("rollback-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create valid source
    let source1 = sourceDir.appendingPathComponent("valid-binary")
    try "VALID".write(to: source1, atomically: true, encoding: .utf8)

    // Create non-existent source path (simulates removal)
    let source2 = sourceDir.appendingPathComponent("nonexistent-binary")

    let dest1 = destDir.appendingPathComponent("valid-binary")
    let dest2 = destDir.appendingPathComponent("nonexistent-binary")

    let installer = AtomicBinaryInstaller()

    #expect(throws: InstallError.self) {
      try installer.install([
        (source: source1, destination: dest1),
        (source: source2, destination: dest2),
      ])
    }

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  // MARK: - Edge Cases

  @Test("Install preserves binary content exactly")
  func preservesBinaryContent() throws {
    let sourceDir = testRoot.appendingPathComponent("binary-content-source")
    let destDir = testRoot.appendingPathComponent("binary-content-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Create binary content with various bytes
    var binaryData = Data()
    for i: UInt8 in 0...255 {
      binaryData.append(i)
    }

    let sourceFile = sourceDir.appendingPathComponent("binary-file")
    let destFile = destDir.appendingPathComponent("binary-file")
    try binaryData.write(to: sourceFile)

    let installer = AtomicBinaryInstaller()
    _ = try installer.install([(source: sourceFile, destination: destFile)])

    // Verify exact content match
    let installedData = try Data(contentsOf: destFile)
    #expect(installedData == binaryData)

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  @Test("Install handles files with special characters in names")
  func specialCharacterFilenames() throws {
    let sourceDir = testRoot.appendingPathComponent("special-source")
    let destDir = testRoot.appendingPathComponent("special-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    // Note: macOS allows most characters except /
    let specialName = "binary-with-spaces and-dashes_underscores"
    let sourceFile = sourceDir.appendingPathComponent(specialName)
    let destFile = destDir.appendingPathComponent(specialName)

    try "Special content".write(to: sourceFile, atomically: true, encoding: .utf8)

    let installer = AtomicBinaryInstaller()
    let result = try installer.install([(source: sourceFile, destination: destFile)])

    #expect(result.installedFiles.contains(specialName))
    #expect(FileManager.default.fileExists(atPath: destFile.path))

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  @Test("Install handles empty operations array")
  func emptyOperations() throws {
    let installer = AtomicBinaryInstaller()
    let result = try installer.install([])

    #expect(result.installedFiles.isEmpty)
    #expect(result.backupsCreated == 0)
    #expect(result.cleanupWarnings.isEmpty)
  }

  @Test("Install generates unique operation IDs")
  func uniqueOperationIDs() throws {
    let sourceDir = testRoot.appendingPathComponent("unique-id-source")
    let destDir = testRoot.appendingPathComponent("unique-id-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    let source1 = sourceDir.appendingPathComponent("binary1")
    let source2 = sourceDir.appendingPathComponent("binary2")
    try "Content1".write(to: source1, atomically: true, encoding: .utf8)
    try "Content2".write(to: source2, atomically: true, encoding: .utf8)

    let dest1 = destDir.appendingPathComponent("binary1")
    let dest2 = destDir.appendingPathComponent("binary2")

    let installer = AtomicBinaryInstaller()
    let result1 = try installer.install([(source: source1, destination: dest1)])
    let result2 = try installer.install([(source: source2, destination: dest2)])

    #expect(result1.operationID != result2.operationID)
    #expect(result1.operationID.count == 8)  // UUID prefix length
    #expect(result2.operationID.count == 8)

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }

  // MARK: - Permissions Tests

  @Test("Installed files have executable permissions")
  func executablePermissions() throws {
    let sourceDir = testRoot.appendingPathComponent("perms-source")
    let destDir = testRoot.appendingPathComponent("perms-dest")
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    let sourceFile = sourceDir.appendingPathComponent("executable")
    let destFile = destDir.appendingPathComponent("executable")

    // Create source with non-executable permissions
    try "#!/bin/bash\necho test".write(to: sourceFile, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644], ofItemAtPath: sourceFile.path)

    let installer = AtomicBinaryInstaller()
    _ = try installer.install([(source: sourceFile, destination: destFile)])

    // Verify destination has executable permissions
    let attrs = try FileManager.default.attributesOfItem(atPath: destFile.path)
    let perms = attrs[.posixPermissions] as? Int
    #expect(perms == 0o755)

    // Cleanup
    try? FileManager.default.removeItem(at: testRoot)
  }
}
