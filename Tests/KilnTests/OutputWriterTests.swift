import Testing
import Foundation
@testable import Kiln

@Suite("OutputWriter.reset")
struct OutputWriterTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kiln-reset-\(UUID().uuidString)")
    }

    @Test("Creates the output directory when it doesn't exist")
    func createsFresh() throws {
        let output = tempDir()
        defer { try? FileManager.default.removeItem(at: output) }

        try OutputWriter(outputDirectory: output).reset()
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test("Clears existing content and leaves a clean directory (no trash behind)")
    func clearsExisting() throws {
        let fm = FileManager.default
        let output = tempDir()
        defer { try? fm.removeItem(at: output) }

        // Seed the output with a nested file that a previous build would have left.
        try fm.createDirectory(at: output.appendingPathComponent("old/nested"), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: output.appendingPathComponent("old/nested/page.html"))

        try OutputWriter(outputDirectory: output).reset()

        // The directory exists and is empty; the stale content is gone.
        #expect(fm.fileExists(atPath: output.path))
        #expect(!fm.fileExists(atPath: output.appendingPathComponent("old/nested/page.html").path))
        #expect(try fm.contentsOfDirectory(atPath: output.path).isEmpty)

        // The move-aside trash sibling was cleaned up (nothing named ".<name>.trash-*").
        let siblings = try fm.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        #expect(!siblings.contains { $0.hasPrefix(".\(output.lastPathComponent).trash-") })
    }
}
