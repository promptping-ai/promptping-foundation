import Foundation

/// Configuration for a launchd service plist
public struct ServiceConfig: Sendable, Equatable {
    public let label: String
    public let executable: String
    public var arguments: [String]
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var standardOutPath: String?
    public var standardErrorPath: String?
    public var environment: [String: String]
    public var workingDirectory: String?
    public var throttleInterval: Int
    public var processType: ProcessType

    public enum ProcessType: String, Sendable, Equatable {
        case standard = "Standard"
        case background = "Background"
        case adaptive = "Adaptive"
        case interactive = "Interactive"
    }

    public init(
        label: String,
        executable: String,
        arguments: [String] = [],
        runAtLoad: Bool = true,
        keepAlive: Bool = true,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        throttleInterval: Int = 10,
        processType: ProcessType = .background
    ) {
        self.label = label
        self.executable = executable
        self.arguments = arguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.throttleInterval = throttleInterval
        self.processType = processType
    }

    public func generatePlist() -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">"#,
            #"<plist version="1.0">"#,
            "<dict>",
            "    <key>Label</key>",
            "    <string>\(escapeXML(label))</string>",
            "    <key>ProgramArguments</key>",
            "    <array>",
            "        <string>\(escapeXML(executable))</string>",
        ]

        for arg in arguments {
            lines.append("        <string>\(escapeXML(arg))</string>")
        }

        lines.append(contentsOf: [
            "    </array>",
            "    <key>RunAtLoad</key>",
            "    <\(runAtLoad)/>",
            "    <key>KeepAlive</key>",
            "    <\(keepAlive)/>",
        ])

        if let stdoutPath = standardOutPath {
            lines.append(contentsOf: [
                "    <key>StandardOutPath</key>",
                "    <string>\(escapeXML(stdoutPath))</string>",
            ])
        }

        if let stderrPath = standardErrorPath {
            lines.append(contentsOf: [
                "    <key>StandardErrorPath</key>",
                "    <string>\(escapeXML(stderrPath))</string>",
            ])
        }

        if !environment.isEmpty {
            lines.append(contentsOf: [
                "    <key>EnvironmentVariables</key>",
                "    <dict>",
            ])
            for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
                lines.append(contentsOf: [
                    "        <key>\(escapeXML(key))</key>",
                    "        <string>\(escapeXML(value))</string>",
                ])
            }
            lines.append("    </dict>")
        }

        if let workDir = workingDirectory {
            lines.append(contentsOf: [
                "    <key>WorkingDirectory</key>",
                "    <string>\(escapeXML(workDir))</string>",
            ])
        }

        lines.append(contentsOf: [
            "    <key>ThrottleInterval</key>",
            "    <integer>\(throttleInterval)</integer>",
            "    <key>ProcessType</key>",
            "    <string>\(processType.rawValue)</string>",
            "</dict>",
            "</plist>",
        ])

        return lines.joined(separator: "\n")
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Status of a launchd service
public enum ServiceStatus: Sendable, Equatable {
    case notLoaded
    case loaded
    case running(pid: Int32)
    case unknown
}
