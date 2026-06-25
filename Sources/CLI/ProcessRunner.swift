import Foundation

/// A CLI-level error with a user-facing message.
struct CLIError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

/// Runs external commands, inheriting the terminal's standard I/O so build
/// output streams straight through.
enum ProcessRunner {
    /// Run `swift` with the given arguments in `directory` (default: cwd).
    /// Throws ``CLIError`` on a non-zero exit.
    static func runSwift(_ arguments: [String], in directory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments
        if let directory { process.currentDirectoryURL = directory }
        // Process inherits the parent's stdout/stderr/stdin by default, which
        // keeps swift's coloured diagnostics intact.
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CLIError(message: "`swift \(arguments.joined(separator: " "))` failed (exit \(process.terminationStatus)).")
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
    static func runCommand(_ command: String, in directory: URL? = nil) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // Run through `sh -c` so the command parses naturally.
        process.arguments = ["sh", "-c", command]
        if let directory { process.currentDirectoryURL = directory }

        // Merge stdout and stderr into one pipe so the live stream preserves the
        // order tools write in (webpack reports warnings on stderr).
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = OutputBuffer()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            try? FileHandle.standardOutput.write(contentsOf: data)
            buffer.append(data)
        }

        try process.run()
        process.waitUntilExit()
        handle.readabilityHandler = nil
        // Drain anything buffered after the final readability callback.
        if let remaining = try? handle.readToEnd(), !remaining.isEmpty {
            try? FileHandle.standardOutput.write(contentsOf: remaining)
            buffer.append(remaining)
        }

        if process.terminationStatus != 0 {
            throw CLIError(message: "`\(command)` failed (exit \(process.terminationStatus)).")
        }
        return CommandResult(exitCode: process.terminationStatus, output: buffer.string())
    }
}

/// A small thread-safe byte accumulator for capturing process output from the
/// pipe's background readability callbacks.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
