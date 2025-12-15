import Foundation
import Testing

@testable import PromptPingFoundation

/// Thread-safe state tracker for test closures
/// Using @unchecked Sendable is acceptable in tests where we control synchronization
private final class TestCallTracker: @unchecked Sendable {
  var kickstartCalled = false
  var kickstartHappened = false
  var printCallCount = 0
}

@Suite("LaunchAgentManager Tests")
struct LaunchAgentManagerTests {

  // MARK: - Bootstrap Error 5 Handling Tests

  @Suite("Bootstrap Error 5 Handling")
  struct BootstrapError5Tests {

    @Test("Bootstrap succeeds normally on exit code 0")
    func bootstrapSucceedsNormally() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let plistURL = tempDir.appendingPathComponent("com.test.success.plist")
      let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.test.success</string>
          <key>ProgramArguments</key>
          <array><string>/usr/bin/true</string></array>
        </dict>
        </plist>
        """
      try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: plistURL) }

      let tracker = TestCallTracker()

      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootstrap") {
            // Success on first try
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 123)
          }
          if args.contains("kickstart") {
            tracker.kickstartCalled = true
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 124)
          }
          if args.contains("print") {
            // Service not loaded initially
            return SubprocessResult(output: "", error: "", exitCode: 113, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should succeed without fallback
      try await manager.bootstrap(plistURL)

      // Kickstart should NOT have been called since bootstrap succeeded
      #expect(!tracker.kickstartCalled, "Kickstart should not be called when bootstrap succeeds")
    }

    @Test("Bootstrap error 5 with service already running succeeds without kickstart")
    func bootstrapError5ServiceAlreadyRunning() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let plistURL = tempDir.appendingPathComponent("com.test.running.plist")
      let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.test.running</string>
          <key>ProgramArguments</key>
          <array><string>/usr/bin/true</string></array>
        </dict>
        </plist>
        """
      try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: plistURL) }

      let tracker = TestCallTracker()

      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootstrap") {
            // Error 5 - I/O error (the quirk)
            return SubprocessResult(
              output: "", error: "Input/output error", exitCode: 5, pid: 123)
          }
          if args.contains("kickstart") {
            tracker.kickstartCalled = true
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 124)
          }
          if args.contains("print") {
            tracker.printCallCount += 1
            // Service is already running (despite error 5)
            return SubprocessResult(output: "pid = 999", error: "", exitCode: 0, pid: 0)
          }
          if args.contains("bootout") {
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should succeed via fallback path
      try await manager.bootstrap(plistURL)

      // Kickstart should NOT have been called because service was already running
      #expect(
        !tracker.kickstartCalled,
        "Kickstart should not be called when service is already running")
    }

    @Test("Bootstrap error 5 triggers kickstart fallback successfully")
    func bootstrapError5TriggersKickstart() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let plistURL = tempDir.appendingPathComponent("com.test.kickstart.plist")
      let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.test.kickstart</string>
          <key>ProgramArguments</key>
          <array><string>/usr/bin/true</string></array>
        </dict>
        </plist>
        """
      try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: plistURL) }

      let tracker = TestCallTracker()

      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootstrap") {
            // Error 5 - I/O error (the quirk)
            return SubprocessResult(
              output: "", error: "Input/output error", exitCode: 5, pid: 123)
          }
          if args.contains("kickstart") {
            tracker.kickstartCalled = true
            tracker.kickstartHappened = true
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 124)
          }
          if args.contains("print") {
            // Service not running initially, running after kickstart
            if tracker.kickstartHappened {
              return SubprocessResult(output: "pid = 124", error: "", exitCode: 0, pid: 0)
            } else {
              return SubprocessResult(output: "", error: "No such process", exitCode: 113, pid: 0)
            }
          }
          if args.contains("bootout") {
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should succeed via kickstart fallback
      try await manager.bootstrap(plistURL)

      // Kickstart SHOULD have been called as fallback
      #expect(tracker.kickstartCalled, "Kickstart should be called as fallback for error 5")
    }

    @Test("Bootstrap error 5 with kickstart failure throws error")
    func bootstrapError5KickstartFails() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let plistURL = tempDir.appendingPathComponent("com.test.fail.plist")
      let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.test.fail</string>
          <key>ProgramArguments</key>
          <array><string>/usr/bin/true</string></array>
        </dict>
        </plist>
        """
      try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: plistURL) }

      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootstrap") {
            // Error 5 - I/O error (the quirk)
            return SubprocessResult(
              output: "", error: "Input/output error", exitCode: 5, pid: 123)
          }
          if args.contains("kickstart") {
            // Kickstart also fails
            return SubprocessResult(
              output: "", error: "Kickstart failed", exitCode: 1, pid: 124)
          }
          if args.contains("print") {
            // Service never starts
            return SubprocessResult(output: "", error: "No such process", exitCode: 113, pid: 0)
          }
          if args.contains("bootout") {
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should throw error
      await #expect(throws: LaunchAgentError.self) {
        try await manager.bootstrap(plistURL)
      }
    }

    @Test("Bootstrap error 5 with kickstart success but service not running throws error")
    func bootstrapError5KickstartSucceedsButServiceNotRunning() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let plistURL = tempDir.appendingPathComponent("com.test.notstarted.plist")
      let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.test.notstarted</string>
          <key>ProgramArguments</key>
          <array><string>/usr/bin/true</string></array>
        </dict>
        </plist>
        """
      try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: plistURL) }

      let tracker = TestCallTracker()

      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootstrap") {
            // Error 5 - I/O error (the quirk)
            return SubprocessResult(
              output: "", error: "Input/output error", exitCode: 5, pid: 123)
          }
          if args.contains("kickstart") {
            tracker.kickstartCalled = true
            // Kickstart returns success (exit code 0)
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 124)
          }
          if args.contains("print") {
            // But service status always shows not running (service failed to start)
            return SubprocessResult(output: "", error: "No such process", exitCode: 113, pid: 0)
          }
          if args.contains("bootout") {
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should throw error because service didn't actually start
      await #expect(throws: LaunchAgentError.self) {
        try await manager.bootstrap(plistURL)
      }

      // Kickstart WAS called (as fallback)
      #expect(
        tracker.kickstartCalled,
        "Kickstart should have been called as fallback")
    }

    @Test("Bootstrap with other error codes throws without fallback")
    func bootstrapOtherErrorsThrowImmediately() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let plistURL = tempDir.appendingPathComponent("com.test.other.plist")
      let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.test.other</string>
          <key>ProgramArguments</key>
          <array><string>/usr/bin/true</string></array>
        </dict>
        </plist>
        """
      try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: plistURL) }

      let tracker = TestCallTracker()

      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootstrap") {
            // Error 3 - not the special error 5 case
            return SubprocessResult(
              output: "", error: "Some other error", exitCode: 3, pid: 123)
          }
          if args.contains("kickstart") {
            tracker.kickstartCalled = true
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 124)
          }
          if args.contains("print") {
            return SubprocessResult(output: "", error: "", exitCode: 113, pid: 0)
          }
          if args.contains("bootout") {
            return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should throw error without attempting kickstart
      await #expect(throws: LaunchAgentError.self) {
        try await manager.bootstrap(plistURL)
      }

      // Kickstart should NOT have been called for non-error-5 cases
      #expect(!tracker.kickstartCalled, "Kickstart should not be called for non-error-5 failures")
    }
  }

  // MARK: - Bootout Regression Tests

  @Suite("Bootout Regression")
  struct BootoutTests {

    @Test("Bootout accepts exit code 3 (service not found)")
    func bootoutAcceptsNotFound() async throws {
      let manager = LaunchAgentManager(
        subprocessRunner: SubprocessRunner(),
        runCommand: {
          @Sendable (executable: Executable, args: [String], _: String?)
            async throws(SubprocessError) -> SubprocessResult in

          if args.contains("bootout") {
            // Exit code 3 = service not found
            return SubprocessResult(
              output: "", error: "No such service", exitCode: 3, pid: 0)
          }
          return SubprocessResult(output: "", error: "", exitCode: 0, pid: 0)
        }
      )

      // Should NOT throw - exit code 3 is acceptable for bootout
      try await manager.bootout("com.nonexistent.service")
    }
  }
}
