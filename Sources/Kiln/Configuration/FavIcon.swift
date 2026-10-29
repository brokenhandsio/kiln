#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

/// Paths (relative to the content directory's assets) to a logo image.
public struct FavIcon: Sendable
{
    public var type: FavIconType
    public var path: String

    public init(
        type: FavIconType = .svg,
        path: String? = nil
    ) {
        self.type = type
        self.path = path ?? type.defaultPath()
    }

    @available(*, deprecated, message: "This initializer guesses the type from a string and is therefore not as reliable as init(type:path:).")
    public init(path: String) {
        self.path = path
        self.type = FavIconType.guessFrom(file: path)
    }
}