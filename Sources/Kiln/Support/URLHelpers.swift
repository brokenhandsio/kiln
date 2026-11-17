#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension URL {
    /// A slash-separated relative path (e.g. `"posts"` or `"archives/api"`)
    /// resolved inside this directory.
    ///
    /// `URL(fileURLWithPath:relativeTo:)` resolves against the base the way a
    /// browser would, so a base without a trailing slash loses its last
    /// component: `posts` relative to `/site/content` is `/site/posts`. A
    /// directory URL only carries that slash if it existed when the URL was
    /// made, so appending components is the only reliable way.
    func appendingDirectoryPath(_ path: String) -> URL {
        var url = self
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
        }
        return url
    }
}
