#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Writes generated files to the output directory, creating intermediate
/// directories as needed.
struct OutputWriter {
    let outputDirectory: URL

    /// Remove and recreate the output directory so each build is clean.
    func reset() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.removeItem(at: outputDirectory)
        }
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
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
