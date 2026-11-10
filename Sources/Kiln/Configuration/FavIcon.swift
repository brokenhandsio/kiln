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

    public init?(
        type: FavIconType? = nil,
        path: String? = nil
    ) {
        guard type != nil || path != nil else {
            return nil
        }

        if let path = path, let type = type {
            self.type = type
            self.path = path
            return
        }

        if let path = path, let type = FavIconType.guessFrom(file: path) {
            self.type = type
            self.path = path
            return
        }

        if let type = type {
            self.type = type
            self.path = type.defaultPath()
            return
        }

        return nil
    }
}