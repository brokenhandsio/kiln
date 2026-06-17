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
            // Kiln's custom tags layered on top of Leaf's built-ins: `#t("key")`
            // resolves theme-defined localised strings (see ``TranslateTag``).
            tags: defaultTags.merging(["t": TranslateTag()]) { _, new in new },
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

    func shutdown() {
        try? threadPool.syncShutdownGracefully()
        try? eventLoopGroup.syncShutdownGracefully()
    }

    deinit {
        shutdown()
    }
}
