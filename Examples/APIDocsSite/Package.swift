// swift-tools-version:6.0
import PackageDescription

let extraSettings: [SwiftSetting] = [
    .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("LifetimeDependence"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "APIDocsSite",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // In a real project this would be:
        //   .package(url: "https://github.com/brokenhandsio/kiln.git", from: "1.0.0")
        .package(name: "kiln", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "APIDocsSite",
            dependencies: [
                .product(name: "Kiln", package: "kiln"),
            ],
            swiftSettings: extraSettings
        ),
    ]
)
