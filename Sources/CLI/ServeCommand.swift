import ArgumentParser
import Foundation

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

    @Argument(help: "The executable target to run when building (defaults to the package's only executable).")
    var target: String?

    @Flag(name: .long, help: "Build in release configuration.")
    var release = false

    @Flag(name: .long, help: "Don't build before serving.")
    var noBuild = false

    @Flag(name: .long, help: "Don't watch for changes / rebuild.")
    var noWatch = false

    func run() async throws {
        // Emit status lines promptly even when stdout is a pipe (logs/CI).
        setvbuf(stdout, nil, _IONBF, 0)

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let servedDirectory = URL(fileURLWithPath: directory, relativeTo: cwd)
        let runArguments = swiftRunArguments(target: target, release: release)

        if !noBuild {
            print("Building documentation…")
            try ProcessRunner.runSwift(runArguments)
        }

        let indexPath = servedDirectory.appendingPathComponent("index.html").path
        if !FileManager.default.fileExists(atPath: indexPath) {
            print("⚠️  No index.html found in \(directory)/. Is that the right output directory? (override with --directory)")
        }

        var watcher: DirectoryWatcher?
        if !noWatch {
            let directoryName = directory
            let w = DirectoryWatcher(root: cwd, outputDirectoryName: directoryName)
            w.start {
                print("\nChange detected — rebuilding…")
                do {
                    try ProcessRunner.runSwift(runArguments)
                    print("Rebuilt. Reload your browser.")
                } catch {
                    print("Build failed: \(error)")
                }
            }
            watcher = w
            print("Watching for changes (skipping .build, .git, .swiftpm, \(directory)/)…")
        }

        let server = StaticFileServer(directory: servedDirectory, host: host, port: port)
        print("Serving \(directory)/ at http://\(host):\(port) — press Ctrl-C to stop.")
        defer {
            watcher?.stop()
            server.shutdown()
        }
        try server.run()
    }
}
