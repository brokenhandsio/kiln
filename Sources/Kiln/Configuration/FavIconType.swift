#if canImport(FoundationEssentials)
internal import FoundationEssentials
#else
internal import Foundation
#endif

import RegexBuilder

@nonexhaustive
public enum FavIconType: Sendable, Equatable {
    case unknown
    case svg
    case png(Size)
    case ico

    @nonexhaustive
    public enum Size: Int, Sendable, CaseIterable {
        case xUnknown = 0
        case x16 = 16
        case x32 = 32
        case x180 = 180

        public init(rawValue: Int) {
            self = Self.allCases.first { $0.rawValue == rawValue } ?? .xUnknown
        }
    }

    public func defaultPath() -> String {
        switch self {
            case .svg: return "assets/favicon.svg"
            case .png(.xUnknown): return "assets/favicon.png"
            case .png(let size): return "assets/favicon-\(size.rawValue).png"
            case .ico: return "assets/favicon.ico"
            case .unknown: return ""
        }
    }

    public func rel() -> String {
        switch self {
            case .png(.x180): return "apple-touch-icon"
            case .svg, .ico, .png, .unknown: return "icon"
        }
    }

    public func sizes() -> String? {
        switch self {
            case .svg, .ico: return "any"
            case .png(.xUnknown), .unknown: return nil
            case .png(let size): return "\(size.rawValue)x\(size.rawValue)"
        }
    }

    public func mimeType() -> String? {
        switch self {
            case .svg: return "image/svg+xml"
            case .png(.x180), .ico, .unknown: return nil
            case .png: return "image/png"
        }
    }

    public static func guessFrom(file name: String) -> Self? {
        guard let ext = name.components(separatedBy: ".").last?.lowercased() else {
            return nil
        }

        switch ext {
            case "svg": return .svg
            case "ico": return .ico
            case "png":
                let iconSizeGuessingPattern = Regex {
                    ZeroOrMore(.any, .reluctant)
                    Capture { OneOrMore(.digit) }
                    OneOrMore {
                        "."
                        CharacterClass.word
                    }
                }

                let size = ext.firstMatch(of: iconSizeGuessingPattern)
                    .flatMap { match in
                        Int(match.1).flatMap(Size.init(rawValue:))
                    } ?? .xUnknown
                
                return .png(size)
            default: return .unknown
        }
    }
}

