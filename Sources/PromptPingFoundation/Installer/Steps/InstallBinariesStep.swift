import Foundation
import Logging

/// Step 4: Install binaries atomically
///
/// Copies the built binaries to the SwiftPM bin directory
/// using atomic file operations with rollback support.
public struct InstallBinariesStep: InstallStep {
  public let name = "Install Binaries"

  public init() {}

  public func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError) {
    let swiftpmBin = PathResolver.StandardPath.swiftpmBin.url

    // Ensure destination directory exists
    do {
      try await context.fileManager.ensureDirectory(at: swiftpmBin)
    } catch {
      throw .binaryNotFound("Failed to create bin directory: \(error)")
    }

    // Prepare install operations
    let operations = config.binaries.map { binary in
      (source: binary.sourcePath, destination: swiftpmBin.appendingPathComponent(binary.name))
    }

    // Execute atomic install
    do {
      try await context.fileManager.atomicInstall(operations)
    } catch {
      throw .binaryNotFound("Failed to install binaries: \(error)")
    }

    result.binariesInstalled = config.binaries.map(\.name)
    context.logger.info("Installed binaries: \(result.binariesInstalled.joined(separator: ", "))")
  }
}
