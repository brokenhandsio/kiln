import Foundation

/// Records what a DocC build produced, so a later build can skip re-rendering
/// modules whose inputs are unchanged (see ``DocCRenderPhase`` incremental mode).
///
/// Persisted at `<output>/_kiln/docc-manifest.json`. `renderInputs` fingerprints
/// everything that affects *every* page's HTML (the executable — which `swift
/// run` recompiles on any config/code change — plus the theme templates); when
/// it matches the previous build, only archives whose own fingerprint changed
/// need re-rendering. CSS/JS are deliberately excluded: they're assets referenced
/// by URL, so changing them never changes a page's HTML — the theme assets are
/// re-copied every build regardless.
struct DocCBuildManifest: Codable, Sendable {
    /// Fingerprint of the global render inputs (executable + templates).
    var renderInputs: String
    /// Per module-version state, keyed `"<Module>@<versionID>"`.
    var modules: [String: Entry]

    struct Entry: Codable, Sendable {
        /// Fingerprint of the module's archive.
        var fingerprint: String
        /// The module-version's output directory, relative to the output root
        /// (e.g. `"routingkit/5-beta"`), so stale/removed modules can be cleaned.
        var outputDir: String
    }

    static let relativePath = "_kiln/docc-manifest.json"

    /// Load the manifest from an output directory, or `nil` if absent/unreadable.
    static func load(from outputDirectory: URL) -> DocCBuildManifest? {
        let url = outputDirectory.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DocCBuildManifest.self, from: data)
    }

    /// Write the manifest into an output directory.
    func write(to outputDirectory: URL) throws {
        let url = outputDirectory.appendingPathComponent(Self.relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}

/// Stable content fingerprints (a small FNV-1a hash — deterministic across
/// process runs, unlike `Hashable`).
enum DocCFingerprint {
    /// Fingerprint the global render inputs: the running executable's mtime (a
    /// proxy for any config/code change, since `swift run` relinks it) plus every
    /// `.leaf` template file's path/mtime/size.
    static func renderInputs(templateDirectories: [URL]) -> String {
        var parts: [String] = []
        if let executable = Bundle.main.executablePath {
            parts.append("exe:\(fileStat(URL(fileURLWithPath: executable)))")
        }
        for directory in templateDirectories {
            for file in leafFiles(in: directory) {
                parts.append("tpl:\(file.lastPathComponent):\(fileStat(file))")
            }
        }
        return hash(parts.sorted().joined(separator: "|"))
    }

    /// Fingerprint a `.doccarchive` from its files' count, total size, and newest
    /// mtime — cheap (one enumeration) and sufficient, since Stage A regenerates
    /// archives wholesale (giving every file a fresh mtime).
    static func archive(_ archiveURL: URL) -> String {
        var count = 0
        var totalSize = 0
        var newest = 0.0
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        if let enumerator = FileManager.default.enumerator(at: archiveURL, includingPropertiesForKeys: Array(keys)) {
            for case let file as URL in enumerator {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                count += 1
                totalSize += values.fileSize ?? 0
                if let mtime = values.contentModificationDate?.timeIntervalSince1970, mtime > newest { newest = mtime }
            }
        }
        return hash("\(count):\(totalSize):\(newest)")
    }

    // MARK: Helpers

    private static func leafFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "leaf" }
    }

    private static func fileStat(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(size):\(mtime)"
    }

    /// FNV-1a 64-bit, hex — small and stable across runs.
    private static func hash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
