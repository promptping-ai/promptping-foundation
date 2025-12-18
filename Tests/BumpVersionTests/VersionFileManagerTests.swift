import BumpVersion
import Foundation
import Testing

@Suite("VersionFileManager Tests")
struct VersionFileManagerTests {
  let manager = VersionFileManager()

  @Suite("Generate Version File")
  struct GenerateTests {
    let manager = VersionFileManager()

    @Test("Generate simple version file")
    func generateSimple() {
      let version = SemanticVersion(1, 2, 3)
      let content = manager.generateVersionFile(version: version, moduleName: "MyModule")

      #expect(content.contains("public enum MyModuleVersion"))
      #expect(content.contains("public static let current = \"1.2.3\""))
      #expect(content.contains("public static let major = 1"))
      #expect(content.contains("public static let minor = 2"))
      #expect(content.contains("public static let patch = 3"))
      #expect(content.contains("public static let prerelease: String? = nil"))
    }

    @Test("Generate version file with prerelease")
    func generateWithPrerelease() {
      let version = SemanticVersion(2, 0, 0, "alpha.1")
      let content = manager.generateVersionFile(version: version, moduleName: "TestLib")

      #expect(content.contains("public static let current = \"2.0.0-alpha.1\""))
      #expect(content.contains("public static let prerelease: String? = \"alpha.1\""))
    }

    @Test("Generate includes usage comment")
    func generateIncludesComment() {
      let version = SemanticVersion(1, 0, 0)
      let content = manager.generateVersionFile(version: version, moduleName: "Test")

      #expect(content.contains("Auto-generated version file"))
      #expect(content.contains("bump-version"))
    }
  }

  @Suite("File Operations")
  struct FileOperationTests {
    let manager = VersionFileManager()

    @Test("Find version file in package")
    func findVersionFile() throws {
      // Create temp directory structure
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      let sourcesDir = tempDir.appendingPathComponent("Sources")
      let targetDir = sourcesDir.appendingPathComponent("MyTarget")

      try FileManager.default.createDirectory(
        at: targetDir,
        withIntermediateDirectories: true
      )

      let versionFile = targetDir.appendingPathComponent("Version.swift")
      try "test content".write(to: versionFile, atomically: true, encoding: .utf8)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let found = try manager.findVersionFile(in: tempDir)
      #expect(found?.lastPathComponent == "Version.swift")
    }

    @Test("Read version from file")
    func readVersion() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let versionFile = tempDir.appendingPathComponent("Version.swift")
      let content = """
        public enum TestVersion {
          public static let current = "1.5.2"
          public static let major = 1
          public static let minor = 5
          public static let patch = 2
        }
        """
      try content.write(to: versionFile, atomically: true, encoding: .utf8)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let version = try manager.readVersion(from: versionFile)
      #expect(version.major == 1)
      #expect(version.minor == 5)
      #expect(version.patch == 2)
    }

    @Test("Read version with prerelease from file")
    func readVersionWithPrerelease() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let versionFile = tempDir.appendingPathComponent("Version.swift")
      let content = """
        public enum TestVersion {
          public static let current = "2.0.0-beta.3"
        }
        """
      try content.write(to: versionFile, atomically: true, encoding: .utf8)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let version = try manager.readVersion(from: versionFile)
      #expect(version.major == 2)
      #expect(version.minor == 0)
      #expect(version.patch == 0)
      #expect(version.preRelease == "beta.3")
    }

    @Test("Does not match notCurrent variable")
    func doesNotMatchNotCurrent() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let versionFile = tempDir.appendingPathComponent("Version.swift")
      // File with notCurrent variable but no valid current variable
      let content = """
        public enum TestVersion {
          public static let notCurrent = "9.9.9"
          public static let notCurrentVersion = "8.8.8"
        }
        """
      try content.write(to: versionFile, atomically: true, encoding: .utf8)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Should throw because there's no valid `let current = ...` pattern
      #expect(throws: VersionFileError.self) {
        _ = try manager.readVersion(from: versionFile)
      }
    }

    @Test("Prefers uncommented version over commented version")
    func prefersUncommentedVersion() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let versionFile = tempDir.appendingPathComponent("Version.swift")
      // File with both commented and uncommented version lines
      // The regex should find the first valid match (uncommented)
      let content = """
        public enum TestVersion {
          public static let current = "1.0.0"
          // Old version: public static let current = "9.9.9"
        }
        """
      try content.write(to: versionFile, atomically: true, encoding: .utf8)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Should find the uncommented version (1.0.0), not the commented one (9.9.9)
      let version = try manager.readVersion(from: versionFile)
      #expect(version.major == 1)
      #expect(version.minor == 0)
      #expect(version.patch == 0)
    }

    @Test("Matches valid current with similar named variables present")
    func matchesValidCurrentWithSimilarVariables() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let versionFile = tempDir.appendingPathComponent("Version.swift")
      // File with both notCurrent and valid current
      let content = """
        public enum TestVersion {
          public static let notCurrent = "9.9.9"
          public static let current = "1.2.3"
          public static let notCurrentVersion = "8.8.8"
        }
        """
      try content.write(to: versionFile, atomically: true, encoding: .utf8)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      // Should find the valid current = "1.2.3" and not the notCurrent variants
      let version = try manager.readVersion(from: versionFile)
      #expect(version.major == 1)
      #expect(version.minor == 2)
      #expect(version.patch == 3)
    }

    @Test("Write and read roundtrip")
    func writeAndReadRoundtrip() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let versionFile = tempDir.appendingPathComponent("Version.swift")
      let original = SemanticVersion(3, 2, 1, "rc.1")

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      try manager.writeVersion(original, to: versionFile, moduleName: "TestModule")
      let readBack = try manager.readVersion(from: versionFile)

      #expect(readBack == original)
    }

    @Test("Extract module name from path")
    func extractModuleName() {
      let path = URL(fileURLWithPath: "/path/to/Sources/MyAwesomeModule/Version.swift")
      let moduleName = manager.extractModuleName(from: path)
      #expect(moduleName == "MyAwesomeModule")
    }

    @Test("Create version file in new target")
    func createVersionFile() throws {
      let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
      let sourcesDir = tempDir.appendingPathComponent("Sources")
      try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

      defer {
        try? FileManager.default.removeItem(at: tempDir)
      }

      let version = SemanticVersion(1, 0, 0)
      let created = try manager.createVersionFile(
        version: version,
        packageDirectory: tempDir,
        targetName: "NewTarget"
      )

      #expect(FileManager.default.fileExists(atPath: created.path))
      #expect(created.path.contains("NewTarget/Version.swift"))

      let content = try String(contentsOf: created, encoding: .utf8)
      #expect(content.contains("NewTargetVersion"))
    }
  }
}
