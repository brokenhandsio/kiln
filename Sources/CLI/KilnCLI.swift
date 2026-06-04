import ArgumentParser

@main
struct KilnCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kiln",
        abstract: "Build, serve, and scaffold Kiln documentation sites.",
        version: "0.1.0",
        subcommands: [Build.self, Serve.self, New.self]
    )
}
