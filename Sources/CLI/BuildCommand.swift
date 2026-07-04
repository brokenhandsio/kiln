import ArgumentParser
import Foundation

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the documentation site by running the project's Swift executable."
    )

    @Argument(help: "The executable target to run (defaults to the package's only executable).")
    var target: String?

    @Flag(name: .long, help: "Build in release configuration.")
    var release = false

    @Option(name: .long, help: "Run this command to build assets before generating the site (overrides kiln.json).")
    var preBuild: String?

    @Flag(name: .long, help: "Skip the asset pre-build step even if one is configured.")
    var noPreBuild = false

    func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let config = try KilnCLIConfig.load(in: cwd)
        if let command = resolvePreBuildCommand(configured: config?.preBuild?.command, override: preBuild, disabled: noPreBuild) {
            print("Building assets (\(command))…")
            try await ProcessRunner.runCommand(command, in: cwd)
        }
        print("Building documentation…")
        try await ProcessRunner.runSwift(swiftRunArguments(target: target, release: release))
        print("Done.")
    }
}

/// Build the `swift run` argument list shared by `build` and `serve`.
func swiftRunArguments(target: String?, release: Bool) -> [String] {
    var arguments = ["run"]
    if release { arguments += ["-c", "release"] }
    if let target { arguments.append(target) }
    return arguments
}
