import Foundation

/// Result of daemon installation
public struct InstallResult: Sendable {
    /// Name of the daemon that was installed
    public let name: String

    /// Path to the build directory (if build was performed)
    public var buildPath: URL?

    /// List of binaries that were installed
    public var binariesInstalled: [String] = []

    /// Port the daemon is configured to use
    public var port: Int?

    /// Whether the launchd service was installed
    public var serviceInstalled: Bool = false

    /// Path to the installed plist file
    public var plistPath: URL?

    /// Whether a previous service was stopped during installation
    public var previousServiceStopped: Bool = false

    public init(name: String) {
        self.name = name
    }
}

/// Errors that can occur during daemon installation
public enum InstallerError: Error, LocalizedError, Sendable {
    case buildFailed(String)
    case binaryNotFound(String)
    case serviceNotLoaded(String)
    case configurationMissing(String)
    case portAllocationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .buildFailed(let msg):
            return "Build failed: \(msg)"
        case .binaryNotFound(let name):
            return "Binary not found: \(name)"
        case .serviceNotLoaded(let label):
            return "Service not loaded: \(label)"
        case .configurationMissing(let field):
            return "Configuration missing: \(field)"
        case .portAllocationFailed(let msg):
            return "Port allocation failed: \(msg)"
        }
    }
}
