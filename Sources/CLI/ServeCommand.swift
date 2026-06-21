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

    func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let servedDirectory = URL(fileURLWithPath: directory, relativeTo: cwd)
        let runArguments = swiftRunArguments(target: target, release: release)

        if !noBuild {
            emit("Building documentation…")
            try ProcessRunner.runSwift(runArguments)
        }

        let indexPath = servedDirectory.appendingPathComponent("index.html").path
        if !FileManager.default.fileExists(atPath: indexPath) {
            emit("⚠️  No index.html found in \(directory)/. Is that the right output directory? (override with --directory)")
        }

        var watcher: DirectoryWatcher?
        if !noWatch {
            let directoryName = directory
            let w = DirectoryWatcher(root: cwd, outputDirectoryName: directoryName)
            w.start {
                emit("\nChange detected — rebuilding…")
                do {
                    try ProcessRunner.runSwift(runArguments)
                    emit("Rebuilt. Reload your browser.")
                } catch {
                    emit("Build failed: \(error)")
                }
            }
            watcher = w
            emit("Watching for changes (skipping .build, .git, .swiftpm, \(directory)/)…")
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
