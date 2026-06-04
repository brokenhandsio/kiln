import ArgumentParser

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the documentation site by running the project's Swift executable."
    )

    @Argument(help: "The executable target to run (defaults to the package's only executable).")
    var target: String?

    @Flag(name: .long, help: "Build in release configuration.")
    var release = false

    func run() async throws {
        print("Building documentation…")
        try ProcessRunner.runSwift(swiftRunArguments(target: target, release: release))
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
