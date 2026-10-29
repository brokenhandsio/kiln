#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

public enum FavIconType: Sendable, Equatable {
    case svg
    case png(PNGSize)
    case ico

    public enum PNGSize: Int, Sendable {
        case xUnknown = 0
        case x16 = 16
        case x32 = 32
        case x180 = 180
    }

    public func ext() -> String {
        switch self {
            case .svg: return "svg"
            case .png: return "png"
            case .ico: return "ico"
        }
    }

    public func defaultPath() -> String {
        switch self {
            case .svg: return "assets/favicon.svg"
            case .png(let size): return "assets/favicon-\(size.rawValue).png"
            case .ico: return "assets/favicon.ico"
        }
    }

    public func rel() -> String {
        switch self {
            case .png(.x180): return "apple-touch-icon"
            case .svg, .ico, .png: return "icon"
        }
    }

    public func sizes() -> String? {
        switch self {
            case .svg, .ico: return "any"
            case .png(.xUnknown): return nil
            case .png(let size): return "\(size.rawValue)x\(size.rawValue)"
        }
    }

    public func mimeType() -> String? {
        switch self {
            case .svg: return "image/svg+xml"
            case .png(.x180), .ico: return nil
            case .png: return "image/png"
        }
    }

    public static func guessFrom(file name: String) -> Self {
        let ext = name.components(separatedBy: ".").last?.lowercased()

        switch ext {
            case "svg": return .svg
            case "ico": return .ico
            default: return .png(.xUnknown)
        }
    }
}

