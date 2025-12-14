import Foundation
import Logging

/// Actor-based port manager for detecting port availability and finding free ports
///
/// Uses `lsof` for port detection on macOS. Thread-safe through actor isolation.
///
/// ## Example Usage
///
/// ```swift
/// let portManager = PortManager()
///
/// // Check if a specific port is in use
/// if await portManager.isPortInUse(50052) {
///     print("Port 50052 is occupied")
/// }
///
/// // Find a free port in a range
/// let freePort = try await portManager.findFreePort(in: 50000...50100)
///
/// // Get info about what's using a port
/// if let info = await portManager.processUsingPort(50052) {
///     print("Port used by \(info.command) (PID: \(info.pid))")
/// }
/// ```
public actor PortManager {
    private let runner: SubprocessRunner
    private let logger: Logger

    /// Creates a new PortManager
    public init(
        runner: SubprocessRunner = SubprocessRunner(),
        logger: Logger = Logger(label: "promptping.port")
    ) {
        self.runner = runner
        self.logger = logger
    }

    /// Check if a port is currently in use (has a process listening on it)
    public func isPortInUse(_ port: Int) async -> Bool {
        logger.debug("Checking if port \(port) is in use")

        do {
            let result = try await runner.run(
                .lsof,
                arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
            )

            let inUse = result.succeeded && !result.output.isEmpty
            logger.debug("Port \(port) is \(inUse ? "in use" : "available")")
            return inUse
        } catch {
            logger.warning("Failed to check port \(port): \(error)")
            return false
        }
    }

    /// Find the first free port in a range
    public func findFreePort(
        in range: ClosedRange<Int>,
        excluding: Set<Int> = []
    ) async throws(PortError) -> Int {
        logger.debug("Finding free port in range \(range.lowerBound)-\(range.upperBound)")

        for port in range where !excluding.contains(port) {
            if await !isPortInUse(port) {
                logger.info("Found free port: \(port)")
                return port
            }
        }

        logger.error("No free port found in range \(range.lowerBound)-\(range.upperBound)")
        throw .noFreePort(range: range)
    }

    /// Get information about the process using a specific port
    public func processUsingPort(_ port: Int) async -> ProcessInfo? {
        logger.debug("Getting process info for port \(port)")

        do {
            let result = try await runner.run(
                .lsof,
                arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpcn"]
            )

            guard result.succeeded, !result.output.isEmpty else {
                logger.debug("No process found on port \(port)")
                return nil
            }

            return parseLsofOutput(result.output, port: port)
        } catch {
            logger.warning("Failed to get process info for port \(port): \(error)")
            return nil
        }
    }

    /// Parse lsof -F output format
    private func parseLsofOutput(_ output: String, port: Int) -> ProcessInfo? {
        var pid: Int32?
        var command: String?

        for line in output.split(separator: "\n") where !line.isEmpty {
            let prefix = line.prefix(1)
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                pid = Int32(value)
            case "c":
                command = value
            default:
                break
            }
        }

        guard let pid, let command else {
            logger.debug("Could not parse lsof output: missing PID or command")
            return nil
        }

        logger.debug("Found process on port \(port): \(command) (PID: \(pid))")
        return ProcessInfo(pid: pid, command: command, port: port)
    }
}
