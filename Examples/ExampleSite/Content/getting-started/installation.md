# Installation

Add Kiln as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/brokenhandsio/kiln.git", from: "1.0.0"),
]
```

Then add the `Kiln` product to your target:

```swift
.executableTarget(
    name: "Docs",
    dependencies: [
        .product(name: "Kiln", package: "kiln"),
    ]
)
```

## Requirements

| Requirement | Version |
| ----------- | ------- |
| Swift       | 6.0+    |
| macOS       | 13+     |
| Linux       | ✅      |

!!! note
    Kiln uses [swift-markdown](https://github.com/apple/swift-markdown) for
    parsing and [Leaf](https://github.com/vapor/leaf-kit) for templating.

??? info "Building from source"
    Clone the repository and run `swift build`. The bundled default theme is
    included as a package resource, so no extra setup is required.
