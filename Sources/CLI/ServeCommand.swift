import ArgumentParser
import Foundation
import Kiln

/// Write a line to standard output immediately (unbuffered), so status lines
/// appear promptly even when stdout is piped (logs/CI). Going through
/// `FileHandle` avoids touching the C `stdout` global, which Swift 6 strict
/// concurrency rejects as shared mutable state on Linux.
private func emit(_ message: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data((message + "\n").utf8))
}

/// The current local time as `HH:mm:ss`, for stamping rebuild status lines.
private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: Date())
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Build the site and serve it locally, rebuilding on file changes."
    )

    @Option(name: [.customShort("d"), .long], help: "Directory to serve (the build output).")
    var directory: String = "site"

    @Option(name: .long, help: "Host to bind to.")
    var host: String = "127.0.0.1"

    @Option(name: [.customShort("p"), .long], help: "Port to listen on.")
    var port: Int = 8080

    @Option(name: .long, help: "Serve under this path prefix, matching the site's basePath (e.g. /docs).")
    var basePath: String = ""

    @Argument(help: "The executable target to run when building (defaults to the package's only executable).")
    var target: String?

    @Flag(name: .long, help: "Build in release configuration.")
    var release = false

    @Flag(name: .long, help: "Don't build before serving.")
    var noBuild = false

    @Flag(name: .long, help: "Don't watch for changes / rebuild.")
    var noWatch = false

    @Option(name: .long, help: "Run this command to build assets before generating the site (overrides kiln.json).")
    var preBuild: String?

    @Flag(name: .long, help: "Skip the asset pre-build step even if one is configured.")
    var noPreBuild = false

    func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let servedDirectory = URL(fileURLWithPath: directory, relativeTo: cwd)
        let runArguments = swiftRunArguments(target: target, release: release)

        let config = try KilnCLIConfig.load(in: cwd)
        let preBuildCommand = resolvePreBuildCommand(
            configured: config?.preBuild?.command, override: preBuild, disabled: noPreBuild
        )

        // Run the asset pre-build (if any) then the Swift site build. Used for
        // both the initial build and watch-triggered rebuilds.
        let fullBuild: @Sendable () throws -> Void = {
            if let preBuildCommand {
                emit("Building assets (\(preBuildCommand))…")
                try ProcessRunner.runCommand(preBuildCommand, in: cwd)
            }
            try ProcessRunner.runSwift(runArguments)
        }

        if !noBuild {
            emit("Building documentation…")
            try fullBuild()
        }

        let indexPath = servedDirectory.appendingPathComponent("index.html").path
        if !FileManager.default.fileExists(atPath: indexPath) {
            emit("⚠️  No index.html found in \(directory)/. Is that the right output directory? (override with --directory)")
        }

        var watcher: DirectoryWatcher?
        if !noWatch {
            let directoryName = directory
            // Extra directories to watch (e.g. asset sources in a shared design
            // repo), resolved relative to cwd.
            let additionalRoots = (config?.preBuild?.watch ?? []).map {
                URL(fileURLWithPath: $0, relativeTo: cwd)
            }
            let w = DirectoryWatcher(root: cwd, outputDirectoryName: directoryName, additionalRoots: additionalRoots)
            w.start {
                emit("\nChange detected — rebuilding…")
                do {
                    try fullBuild()
                    emit("Rebuilt at \(timestamp()). Reload your browser.")
                } catch {
                    emit("Build failed at \(timestamp()): \(error)")
                }
            }
            watcher = w
            emit("Watching for changes (skipping .build, .git, .swiftpm, node_modules, \(directory)/)…")
        }

        let mountPath = SiteURLs.normaliseBasePath(basePath)
        let server = StaticFileServer(directory: servedDirectory, host: host, port: port, basePath: mountPath)
        emit("Serving \(directory)/ at http://\(host):\(port)\(mountPath)/ — press Ctrl-C to stop.")
        defer {
            watcher?.stop()
            server.shutdown()
        }
        try server.run()
    }
}
