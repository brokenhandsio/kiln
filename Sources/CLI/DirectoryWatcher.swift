import Foundation
import NIOPosix

/// A simple cross-platform file watcher that polls modification times and
/// invokes a callback when anything under `root` changes.
///
/// Polling (rather than FSEvents/inotify) keeps it simple and identical on macOS
/// and Linux — fine for a local preview server. The (blocking) directory scan
/// runs on NIO's dedicated blocking-I/O thread pool, so it never occupies a
/// Swift-concurrency cooperative thread.
final class DirectoryWatcher: @unchecked Sendable {
    private let roots: [URL]
    private let ignoredDirectories: Set<String>
    private let pollInterval: TimeInterval
    private var lastSignature: Int = 0
    private var task: Task<Void, Never>?

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

    /// Begin polling in a background `Task`. The (async) `onChange` build runs to
    /// completion before the next scan, debounced so a burst of edits triggers a
    /// single rebuild. Each scan is offloaded to NIO's blocking-I/O pool, so the
    /// only work on the cooperative pool is the lightweight orchestration and the
    /// (already async) build.
    func start(onChange: @escaping @Sendable () async -> Void) {
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // `sleep` throws on cancellation → exit the loop.
                do { try await Task.sleep(for: .seconds(self.pollInterval)) } catch { break }

                let current = await self.scanSignature()
                if current != self.lastSignature {
                    self.lastSignature = current
                    // Debounce: let a burst of writes settle, then re-check.
                    try? await Task.sleep(for: .seconds(self.pollInterval))
                    self.lastSignature = await self.scanSignature()
                    await onChange()
                    // Re-baseline AFTER the build so the files it generated (e.g.
                    // webpack assets, the swift output) don't trigger another
                    // rebuild on the next scan — otherwise an asset pre-build
                    // step would loop forever.
                    self.lastSignature = await self.scanSignature()
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Compute the tree signature on NIO's dedicated blocking-I/O thread pool so
    /// the blocking `FileManager` enumeration never runs on a cooperative thread.
    /// On failure (pool inactive) it returns the last signature, so a transient
    /// error is treated as "no change" rather than a spurious rebuild.
    private func scanSignature() async -> Int {
        (try? await NIOThreadPool.singleton.runIfActive { self.signature() }) ?? lastSignature
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
