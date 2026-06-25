import Foundation

/// A simple cross-platform file watcher that polls modification times and
/// invokes a callback when anything under `root` changes.
///
/// Polling (rather than FSEvents/inotify) keeps it dependency-free and
/// identical on macOS and Linux — fine for a local preview server.
final class DirectoryWatcher: @unchecked Sendable {
    private let roots: [URL]
    private let ignoredDirectories: Set<String>
    private let pollInterval: TimeInterval
    private var lastSignature: Int = 0
    private var running = false

    /// - Parameters:
    ///   - root: directory to watch recursively.
    ///   - outputDirectoryName: the build output dir name to ignore (e.g. `site`).
    ///   - additionalRoots: extra directories to watch, e.g. asset sources that
    ///     live outside the project tree (a shared design repo).
    ///   - pollInterval: seconds between scans.
    init(root: URL, outputDirectoryName: String, additionalRoots: [URL] = [], pollInterval: TimeInterval = 0.5) {
        self.roots = [root] + additionalRoots
        // `node_modules` is ignored for performance (it's large and irrelevant);
        // the build output dir and SwiftPM/git metadata are ignored so the build
        // doesn't observe its own artefacts.
        self.ignoredDirectories = [".build", ".git", ".swiftpm", "node_modules", outputDirectoryName]
        self.pollInterval = pollInterval
        self.lastSignature = signature()
    }

    /// Begin polling on a background thread. `onChange` runs on that thread,
    /// debounced so a burst of edits triggers a single rebuild.
    func start(onChange: @escaping @Sendable () -> Void) {
        running = true
        let thread = Thread { [weak self] in
            guard let self else { return }
            while self.running {
                Thread.sleep(forTimeInterval: self.pollInterval)
                guard self.running else { break }
                let current = self.signature()
                if current != self.lastSignature {
                    self.lastSignature = current
                    // Debounce: let a burst of writes settle, then re-check.
                    Thread.sleep(forTimeInterval: self.pollInterval)
                    self.lastSignature = self.signature()
                    onChange()
                    // Re-baseline AFTER the build so the files it generated (e.g.
                    // webpack assets, the swift output) don't trigger another
                    // rebuild on the next scan — otherwise an asset pre-build
                    // step would loop forever.
                    self.lastSignature = self.signature()
                }
            }
        }
        thread.name = "kiln-watcher"
        thread.start()
    }

    func stop() {
        running = false
    }

    /// A hash of (path, modification time) for every watched file across all roots.
    private func signature() -> Int {
        let fileManager = FileManager.default
        var hasher = Hasher()
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if ignoredDirectories.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if values?.isDirectory == true { continue }
                hasher.combine(url.path)
                if let modified = values?.contentModificationDate {
                    hasher.combine(modified)
                }
            }
        }
        return hasher.finalize()
    }
}
