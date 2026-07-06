import Foundation

/// Collects the DocC render-JSON constructs Kiln's model didn't recognise while
/// decoding an archive.
///
/// The model is deliberately **lenient**: an unrecognised inline/block content
/// type, section kind, reference type, or node kind decodes to an `.unknown`
/// case instead of throwing, so a newer Swift/DocC release that introduces a new
/// construct degrades gracefully rather than failing the whole build. Each such
/// case is recorded here (when a diagnostics collector is threaded through the
/// decoder's `userInfo`) so the loader can surface a build warning and tests can
/// assert a known corpus decodes with zero unknowns.
public final class DocCDiagnostics: @unchecked Sendable {
    /// One unrecognised construct: what kind of thing it was (`location`, e.g.
    /// `"inline content"`) and the raw discriminator we didn't handle
    /// (`discriminator`, e.g. `"strikethrough"`).
    public struct Unknown: Sendable, Equatable {
        public var location: String
        public var discriminator: String
    }

    private let lock = NSLock()
    private var _unknowns: [Unknown] = []

    public init() {}

    /// Every unrecognised construct seen so far, in encounter order.
    public var unknowns: [Unknown] {
        lock.lock(); defer { lock.unlock() }
        return _unknowns
    }

    /// The set of distinct `"location: discriminator"` strings, for concise logging.
    public var summary: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for u in unknowns {
            let key = "\(u.location): \(u.discriminator)"
            if seen.insert(key).inserted { out.append(key) }
        }
        return out
    }

    func record(_ discriminator: String, at location: String) {
        lock.lock(); defer { lock.unlock() }
        _unknowns.append(Unknown(location: location, discriminator: discriminator))
    }
}

extension CodingUserInfoKey {
    /// `userInfo` slot carrying the ``DocCDiagnostics`` collector through a decode.
    public static let doccDiagnostics = CodingUserInfoKey(rawValue: "io.brokenhands.kiln.docc.diagnostics")!
}

extension Decoder {
    /// Record an unrecognised discriminator, if a ``DocCDiagnostics`` collector is
    /// attached to this decoder's `userInfo`. A no-op otherwise, so decoding
    /// works with or without diagnostics.
    func recordUnknownDocC(_ discriminator: String, at location: String) {
        (userInfo[.doccDiagnostics] as? DocCDiagnostics)?.record(discriminator, at: location)
    }
}
