/// [Carbon Ads](https://www.carbonads.net) configuration.
///
/// When set on a ``KilnSite``, the default theme loads a single Carbon ad into
/// the right-hand table-of-contents sidebar on wide (desktop) viewports.
///
/// ```swift
/// KilnSite(name: "Docs", url: "https://example.com",
///          carbonAds: .init(serve: "CK7DT2QW", placement: "vaporcodes")) { … }
/// ```
public struct CarbonAds: Sendable {
    /// The Carbon `serve` identifier from your ad zone.
    public var serve: String
    /// The Carbon `placement` identifier (usually your site name).
    public var placement: String

    public init(serve: String, placement: String) {
        self.serve = serve
        self.placement = placement
    }
}
