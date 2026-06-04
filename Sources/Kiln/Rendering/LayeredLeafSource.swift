import LeafKit
import NIOCore

/// A `LeafSource` that resolves templates from an ordered list of sources,
/// trying each in turn until one succeeds.
///
/// Kiln uses this so a user's custom theme directory takes priority over the
/// bundled default theme: you only override the templates you want to change,
/// and everything else falls back to the built-in theme.
struct LayeredLeafSource: LeafSource {
    let sources: [any LeafSource]

    func file(template: String, escape: Bool, on eventLoop: any EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        try resolve(template: template, escape: escape, on: eventLoop, startingAt: 0)
    }

    private func resolve(template: String, escape: Bool, on eventLoop: any EventLoop, startingAt index: Int) throws -> EventLoopFuture<ByteBuffer> {
        guard index < sources.count else {
            return eventLoop.makeFailedFuture(LeafError(.noTemplateExists(template)))
        }
        let source = sources[index]
        let future: EventLoopFuture<ByteBuffer>
        do {
            future = try source.file(template: template, escape: escape, on: eventLoop)
        } catch {
            // This source can't serve it; try the next.
            return try resolve(template: template, escape: escape, on: eventLoop, startingAt: index + 1)
        }
        return future.flatMapError { _ in
            // Not found in this source; fall back to the next one.
            (try? self.resolve(template: template, escape: escape, on: eventLoop, startingAt: index + 1))
                ?? eventLoop.makeFailedFuture(LeafError(.noTemplateExists(template)))
        }
    }
}
