import LeafKit
import NIOCore

/// A `LeafSource` that resolves templates from an ordered list of sources,
/// trying each in turn until one succeeds.
///
/// Kiln uses this so a user's custom theme directory takes priority over the
/// bundled default theme: you only override the templates you want to change,
/// and everything else falls back to the built-in theme.
struct LayeredLeafSource: LeafSource, Sendable {
    let sources: [any LeafSource & Sendable]

    func file(template: String, escape: Bool, on eventLoop: any EventLoop) throws -> EventLoopFuture<ByteBuffer> {
        let sources = self.sources
        return eventLoop.makeFutureWithTask {
            for source in sources {
                do {
                    return try await source.file(template: template, escape: escape, on: eventLoop).get()
                } catch {
                    // Surface access violations immediately; otherwise this
                    // source simply doesn't have the file, so try the next.
                    if Self.isIllegalAccess(error) { throw error }
                    continue
                }
            }
            throw LeafError(.noTemplateExists(template))
        }
    }

    private static func isIllegalAccess(_ error: any Error) -> Bool {
        if let leafError = error as? LeafError, case .illegalAccess = leafError.reason {
            return true
        }
        return false
    }
}
