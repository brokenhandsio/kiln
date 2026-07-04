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
    name: "kiln",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Kiln", targets: ["Kiln"]),
        .executable(name: "kiln", targets: ["KilnCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0"),
        .package(url: "https://github.com/vapor/leaf-kit.git", from: "1.14.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "0.4.0")),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Kiln",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "LeafKit", package: "leaf-kit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            resources: [
                .copy("Resources/DefaultTheme"),
            ],
            swiftSettings: extraSettings
        ),
        .executableTarget(
            name: "KilnCLI",
            dependencies: [
                "Kiln",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            path: "Sources/CLI",
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "KilnTests",
            dependencies: ["Kiln", "KilnCLI"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: extraSettings
        ),
    ]
)
