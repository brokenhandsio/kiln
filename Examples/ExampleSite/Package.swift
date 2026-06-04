// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ExampleSite",
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
            name: "ExampleSite",
            dependencies: [
                .product(name: "Kiln", package: "kiln"),
            ]
        ),
    ]
)
