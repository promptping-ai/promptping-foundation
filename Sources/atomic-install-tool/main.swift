import ArgumentParser
import AtomicInstall
import Foundation

@main
struct AtomicInstallTool: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "atomic-install-tool",
    abstract: "Atomic binary installation with backup/rollback support",
    subcommands: [InstallCommand.self]
  )
}

struct InstallCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Install binaries atomically"
  )

  @Option(name: .long, help: "JSON array of {source, destination} objects")
  var operations: String

  @Flag(name: .long, help: "Output result as JSON")
  var json: Bool = false

  func run() throws {
    // Parse operations JSON
    guard let data = operations.data(using: .utf8),
      let ops = try? JSONDecoder().decode([FileOperation].self, from: data)
    else {
      throw ValidationError("Invalid operations JSON")
    }

    let installer = AtomicBinaryInstaller()
    let urlOps = ops.map { op in
      (source: URL(fileURLWithPath: op.source), destination: URL(fileURLWithPath: op.destination))
    }

    do {
      let result = try installer.install(urlOps)

      if json {
        let output = InstallOutput(
          success: true,
          installedFiles: result.installedFiles,
          backupsCreated: result.backupsCreated,
          operationID: result.operationID,
          error: nil
        )
        let jsonData = try JSONEncoder().encode(output)
        print(String(data: jsonData, encoding: .utf8) ?? "{}")
      } else {
        print("Installation complete!")
        print("  Installed: \(result.installedFiles.joined(separator: ", "))")
        print("  Backups created: \(result.backupsCreated)")
        print("  Operation ID: \(result.operationID)")
      }
    } catch let error as InstallError {
      if json {
        let output = InstallOutput(
          success: false,
          installedFiles: [],
          backupsCreated: 0,
          operationID: "",
          error: error.description
        )
        let jsonData = try JSONEncoder().encode(output)
        print(String(data: jsonData, encoding: .utf8) ?? "{}")
      } else {
        // Print the full error with rollback status and manual commands
        print(error.description)
      }
      throw ExitCode.failure
    }
  }
}

struct FileOperation: Codable {
  let source: String
  let destination: String
}

struct InstallOutput: Codable {
  let success: Bool
  let installedFiles: [String]
  let backupsCreated: Int
  let operationID: String
  let error: String?
}
