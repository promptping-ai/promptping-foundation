import Foundation
import Logging

/// Step 1: Build Swift products
///
/// Executes `swift build` with the configured options to compile
/// the daemon binaries. Can be skipped via `DaemonConfig.skipBuild`.
public struct BuildStep: InstallStep {
  public let name = "Build"

  public init() {}

  public func execute(
    config: DaemonConfig,
    context: InstallContext,
    result: inout InstallResult
  ) async throws(InstallerError) {
    guard !config.skipBuild else {
      context.logger.info("Skipping build (skipBuild=true)")
      return
    }

    context.logger.info("Building products...")

    var args =
      config.useSwiftBuild
      ? ["build", "--build-system", "swiftbuild", "-c", "release"]
      : ["build", "-c", "release"]

    if let jobs = config.buildJobs {
      args += ["-j", String(jobs)]
    }

    do {
      let buildResult = try await context.subprocess.run(.swift, arguments: args)
      guard buildResult.succeeded else {
        throw InstallerError.buildFailed(buildResult.error)
      }
    } catch let error as InstallerError {
      throw error
    } catch {
      throw .buildFailed(error.localizedDescription)
    }

    let buildDir = Foundation.FileManager.default.currentDirectoryPath
    result.buildPath = URL(fileURLWithPath: buildDir).appendingPathComponent(".build/release")
    context.logger.info("Build completed: \(result.buildPath?.path ?? "unknown")")
  }
}
