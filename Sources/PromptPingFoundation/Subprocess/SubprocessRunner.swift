import Foundation
import Logging
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

/// Async subprocess execution with modern Swift Subprocess API
public actor SubprocessRunner {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "promptping.subprocess")) {
        self.logger = logger
    }

    /// Run a subprocess and collect output
    ///
    /// - Parameters:
    ///   - executable: Executable specification (path or name)
    ///   - arguments: Command arguments
    ///   - workingDirectory: Working directory for the process
    /// - Returns: SubprocessResult with output, error, and exit status
    /// - Throws: SubprocessError if execution fails
    public func run(
        _ executable: Executable,
        arguments: [String] = [],
        workingDirectory: String? = nil
    ) async throws(SubprocessError) -> SubprocessResult {
        logger.debug("Running: \(executable.description) \(arguments.joined(separator: " "))")

        let executableArg: Subprocess.Executable = switch executable {
        case .path(let path):
            .path(FilePath(path))
        case .name(let name):
            .name(name)
        }

        let workDir = workingDirectory.map { FilePath($0) }

        do {
            let result = try await Subprocess.run(
                executableArg,
                arguments: Arguments(arguments),
                environment: .inherit,
                workingDirectory: workDir,
                output: .string(limit: 10 * 1024 * 1024),
                error: .string(limit: 10 * 1024 * 1024)
            )

            let stdout = result.standardOutput ?? ""
            let stderr = result.standardError ?? ""

            let exitCode: Int32 = switch result.terminationStatus {
            case .exited(let code):
                code
            case .unhandledException(let code):
                Int32(128) + Int32(code)
            }

            logger.debug("Exit code: \(exitCode)")

            return SubprocessResult(
                output: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                error: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                exitCode: exitCode,
                pid: result.processIdentifier.value
            )
        } catch {
            throw .executionFailed(
                command: "\(executable.description) \(arguments.joined(separator: " "))",
                underlying: error
            )
        }
    }

    /// Run a subprocess and check for success (exit code 0)
    ///
    /// - Parameters:
    ///   - executable: Executable specification (path or name)
    ///   - arguments: Command arguments
    ///   - workingDirectory: Working directory for the process
    /// - Throws: SubprocessError.nonZeroExit if the command fails
    public func runChecked(
        _ executable: Executable,
        arguments: [String] = [],
        workingDirectory: String? = nil
    ) async throws(SubprocessError) {
        let result = try await run(
            executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )

        guard result.succeeded else {
            throw .nonZeroExit(
                command: "\(executable.description) \(arguments.joined(separator: " "))",
                exitCode: result.exitCode,
                stderr: result.error
            )
        }
    }
}

/// Result of subprocess execution
public struct SubprocessResult: Sendable {
    public let output: String
    public let error: String
    public let exitCode: Int32
    public let pid: Int32

    public var succeeded: Bool { exitCode == 0 }

    public init(output: String, error: String, exitCode: Int32, pid: Int32) {
        self.output = output
        self.error = error
        self.exitCode = exitCode
        self.pid = pid
    }
}

/// Executable specification (path or name lookup)
public enum Executable: Sendable, CustomStringConvertible {
    case path(String)
    case name(String)

    public var description: String {
        switch self {
        case .path(let path): path
        case .name(let name): name
        }
    }

    /// Common executables
    public static let launchctl = Executable.path("/bin/launchctl")
    public static let lsof = Executable.path("/usr/sbin/lsof")
    public static let swift = Executable.name("swift")
    public static let git = Executable.path("/usr/bin/git")
    public static let cp = Executable.path("/bin/cp")
    public static let mv = Executable.path("/bin/mv")
    public static let rm = Executable.path("/bin/rm")
    public static let mkdir = Executable.path("/bin/mkdir")
    public static let chmod = Executable.path("/bin/chmod")
}
