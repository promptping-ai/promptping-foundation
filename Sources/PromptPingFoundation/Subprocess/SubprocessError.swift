import Foundation

/// Errors that can occur during subprocess execution
public enum SubprocessError: Error, LocalizedError, Sendable {
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)
    case executionFailed(command: String, underlying: String)
    case timeout(command: String, timeoutSeconds: Int)
    case environmentNotSupported

    public var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, let exitCode, let stderr):
            var message = "Command '\(command)' exited with code \(exitCode)"
            if !stderr.isEmpty {
                message += ": \(stderr)"
            }
            return message
        case .executionFailed(let command, let underlying):
            return "Failed to execute '\(command)': \(underlying)"
        case .timeout(let command, let seconds):
            return "Command '\(command)' timed out after \(seconds) seconds"
        case .environmentNotSupported:
            return "Custom environment variables are not supported. Use the system's environment instead."
        }
    }
}
