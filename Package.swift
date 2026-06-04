// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "kiln",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Kiln", targets: ["Kiln"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/vapor/leaf-kit.git", from: "1.14.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
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
            ]
        ),
        .testTarget(
            name: "KilnTests",
            dependencies: ["Kiln"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
