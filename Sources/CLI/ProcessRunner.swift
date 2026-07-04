import Foundation
import Subprocess

// `FilePath` for the working directory — matching how Subprocess itself imports
// it (the OS `System` framework on Apple platforms, the `swift-system` package
// elsewhere) so we pass the same `FilePath` type its API expects.
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// A CLI-level error with a user-facing message.
struct CLIError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

/// Runs external commands via swift-subprocess — the modern, cross-platform way
/// to spawn processes. Replaces `Foundation.Process`, whose pipe I/O needed
/// platform-specific handling to capture output reliably on Linux.
enum ProcessRunner {
    /// Run `swift` with the given arguments in `directory` (default: cwd),
    /// inheriting our stdout/stderr so swift's coloured diagnostics stream
    /// straight through. Throws ``CLIError`` on a non-zero exit.
    static func runSwift(_ arguments: [String], in directory: URL? = nil) async throws {
        let result = try await run(
            .name("swift"),
            arguments: Arguments(arguments),
            workingDirectory: directory.map { FilePath($0.path) },
            output: .standardOutput,
            error: .standardError
        )
        guard result.terminationStatus.isSuccess else {
            throw CLIError(
                message: "`swift \(arguments.joined(separator: " "))` failed (\(result.terminationStatus))."
            )
        }
    }

    /// The captured output and exit code of a command run via ``runCommand(_:in:)``.
    struct CommandResult {
        var exitCode: Int32
        /// Combined stdout + stderr, captured while also being streamed live.
        var output: String
    }

    /// Run an arbitrary shell command (e.g. `"npm run build"`), streaming its
    /// combined stdout/stderr to the terminal live *and* capturing it so callers
    /// can surface warnings/errors afterwards.
    ///
    /// Throws ``CLIError`` on a non-zero exit.
    @discardableResult
    static func runCommand(_ command: String, in directory: URL? = nil) async throws -> CommandResult {
        // Merge stderr into stdout (`2>&1`, via `.combinedWithOutput`) so the
        // streamed order matches what the tool writes (webpack reports warnings on
        // stderr). The closure streams each line live while accumulating it.
        let outcome = try await run(
            .name("sh"),
            arguments: ["-c", command],
            workingDirectory: directory.map { FilePath($0.path) },
            error: .combinedWithOutput
        ) { _, standardOutput in
            var captured = ""
            for try await line in standardOutput.lines() {
                print(line)
                captured += line
                captured += "\n"
            }
            return captured
        }

        guard outcome.terminationStatus.isSuccess else {
            throw CLIError(message: "`\(command)` failed (\(outcome.terminationStatus)).")
        }
        let exitCode: Int32
        switch outcome.terminationStatus {
        case .exited(let code): exitCode = code
        case .signaled(let signal): exitCode = 128 + signal
        }
        return CommandResult(exitCode: exitCode, output: outcome.value)
    }
}
