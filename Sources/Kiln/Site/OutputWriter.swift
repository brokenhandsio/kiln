// Full Foundation (not FoundationEssentials): reset() uses Thread.sleep and
// ProcessInfo, which live in Foundation proper.
import Foundation

/// Writes generated files to the output directory, creating intermediate
/// directories as needed.
struct OutputWriter {
    let outputDirectory: URL

    /// Remove and recreate the output directory so each build is clean.
    ///
    /// Rather than deleting the existing output in place, this **renames it aside**
    /// first (a fast directory-entry move) and then deletes the moved-aside copy.
    /// On macOS, Spotlight (`mdworker`) can hold files in a large output open while
    /// indexing, so a direct recursive remove intermittently fails with `EPERM`
    /// ("Operation not permitted"). A rename sidesteps that — it touches only the
    /// directory entry, not the indexed files — so the build can proceed, and the
    /// aside copy is cleaned up best-effort with a short retry.
    func reset() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: outputDirectory.path) else {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            return
        }

        // A sibling "trash" path, keyed by PID so concurrent builds don't collide.
        let trash = outputDirectory.deletingLastPathComponent()
            .appendingPathComponent(".\(outputDirectory.lastPathComponent).trash-\(ProcessInfo.processInfo.processIdentifier)")
        try? Self.removeWithRetry(trash, fileManager: fileManager) // clear any stale trash from a prior crash

        do {
            try fileManager.moveItem(at: outputDirectory, to: trash)
        } catch {
            // The rename failed (e.g. output on a different volume than its parent,
            // where a move isn't atomic) — fall back to a retrying in-place remove.
            try Self.removeWithRetry(outputDirectory, fileManager: fileManager)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            return
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // Best-effort: a leftover trash directory doesn't affect the build output.
        try? Self.removeWithRetry(trash, fileManager: fileManager)
    }

    /// Remove a directory, retrying with backoff to ride out a transient `EPERM`
    /// from a macOS indexer holding a file open. Returns quietly if the item is
    /// already gone.
    private static func removeWithRetry(_ url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var lastError: (any Error)?
        for backoffMilliseconds in [0, 100, 300, 900] {
            if backoffMilliseconds > 0 {
                Thread.sleep(forTimeInterval: Double(backoffMilliseconds) / 1000)
            }
            do {
                try fileManager.removeItem(at: url)
                return
            } catch {
                if !fileManager.fileExists(atPath: url.path) { return }
                lastError = error
            }
        }
        if let lastError { throw lastError }
    }

    func write(_ contents: String, to file: URL) throws {
        try write(Data(contents.utf8), to: file)
    }

    func write(_ data: Data, to file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file)
    }
}
