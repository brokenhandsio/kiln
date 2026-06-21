#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import LeafKit
import NIOCore
import NIOPosix

/// Renders Leaf templates to strings, wrapping `LeafKit`'s EventLoop-based
/// `LeafRenderer` behind an async/await API and owning the NIO resources it
/// needs (an event-loop group and a thread pool for file IO).
///
/// Templates resolve from the given directories in order — a custom theme
/// directory first, then Kiln's bundled default theme — via
/// ``LayeredLeafSource``.
final class TemplateRenderer {
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let threadPool: NIOThreadPool
    private let renderer: LeafRenderer
    /// Set once `shutdown()` has released the NIO resources, so `deinit` knows
    /// not to shut them down a second time (a double `syncShutdownGracefully()`
    /// blocks forever — the worker threads have already exited and never
    /// re-signal the condition lock).
    private var didShutdown = false

    /// - Parameter templateDirectories: ordered highest-priority first.
    init(templateDirectories: [URL]) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let pool = NIOThreadPool(numberOfThreads: 2)
        pool.start()
        let fileIO = NonBlockingFileIO(threadPool: pool)

        let leafSources = templateDirectories.map { directory -> NIOLeafFiles in
            // Note: we deliberately do not set `.toVisibleFiles`/`.toSandbox`.
            // The bundled theme lives under a `.build`/`*.bundle` path (hidden
            // components), which those limits would reject. We control the
            // template directories ourselves, so sandboxing buys us nothing.
            NIOLeafFiles(
                fileio: fileIO,
                limits: [.requireExtensions],
                sandboxDirectory: directory.path,
                viewDirectory: directory.path
            )
        }
        let layered = LayeredLeafSource(sources: leafSources)

        let rootDirectory = templateDirectories.last?.path ?? FileManager.default.currentDirectoryPath
        self.eventLoopGroup = group
        self.threadPool = pool
        self.renderer = LeafRenderer(
            configuration: LeafConfiguration(rootDirectory: rootDirectory),
            // Kiln's custom tags layered on top of Leaf's built-ins:
            // `#localise("key")` resolves theme-defined localised strings (see
            // ``LocaliseTag``).
            tags: defaultTags.merging(["localise": LocaliseTag()]) { _, new in new },
            cache: DefaultLeafCache(),
            sources: .singleSource(layered),
            eventLoop: group.next()
        )
    }

    /// Render a template (e.g. `"page"`, `"partials/nav"`) with the given context.
    func render(_ template: String, context: [String: LeafData]) async throws -> String {
        let buffer = try await renderer.render(path: template, context: context).get()
        return String(buffer: buffer)
    }

    /// Release the NIO resources. Async on purpose: the blocking
    /// `syncShutdownGracefully()` parks the calling thread on a `ConditionLock`,
    /// and when called from Swift Concurrency (e.g. `SiteGenerator.build()`) it
    /// blocks a cooperative-pool thread. Under parallel test execution every
    /// build blocks one at once, the pool starves, and the whole run deadlocks.
    /// The async variants suspend instead of blocking, so the pool stays live.
    func shutdown() async {
        guard !didShutdown else { return }
        didShutdown = true
        try? await threadPool.shutdownGracefully()
        try? await eventLoopGroup.shutdownGracefully()
    }

    deinit {
        // Safety net for misuse only: callers are expected to `await shutdown()`,
        // which is the non-blocking path. If they didn't, fall back to the
        // blocking shutdown so NIO's "must shut down before deinit" requirement
        // is met — but never when already shut down (a second shutdown hangs).
        guard !didShutdown else { return }
        try? threadPool.syncShutdownGracefully()
        try? eventLoopGroup.syncShutdownGracefully()
    }
}
