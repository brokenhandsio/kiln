import ArgumentParser

/// The CLI version reported by `kiln --version`.
///
/// The release workflow (`.github/workflows/release.yml`) rewrites this line to
/// match the git tag before building the released binary — keep it on one line
/// in the form `let kilnVersion = "X.Y.Z"` so the `sed` replacement keeps working.
let kilnVersion = "0.1.0"

@main
struct KilnCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kiln",
        abstract: "Build, serve, and scaffold Kiln documentation sites.",
        version: kilnVersion,
        subcommands: [Build.self, Serve.self, New.self]
    )
}
