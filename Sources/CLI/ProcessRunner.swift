import Foundation

/// A CLI-level error with a user-facing message.
struct CLIError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

/// Runs external commands (specifically `swift`), inheriting the terminal's
/// standard I/O so build output streams straight through.
enum ProcessRunner {
    /// Run `swift` with the given arguments in `directory` (default: cwd).
    /// Throws ``CLIError`` on a non-zero exit.
    static func runSwift(_ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments
        if let directory { process.currentDirectoryURL = directory }
        // Process inherits the parent's stdout/stderr/stdin by default.
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CLIError(message: "`swift \(arguments.joined(separator: " "))` failed (exit \(process.terminationStatus)).")
        }
    }
}
