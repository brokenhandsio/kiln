---
description: Install the kiln CLI with Homebrew or from source, or add Kiln to your SwiftPM project as a dependency.
---
# Installation

There are two ways to use Kiln, and most projects use both:

1. The **`kiln` command-line tool** — to scaffold, build, and preview sites.
2. The **`Kiln` Swift library** — the dependency your docs project builds against.

## Install the CLI

With [Homebrew](https://brew.sh) (macOS, Apple Silicon):

```sh
brew install brokenhandsio/tap/kiln
```

Or build it from source (any platform with a Swift toolchain, including Intel
Macs and Linux):

```sh
git clone https://github.com/brokenhandsio/kiln.git
cd kiln
swift build -c release
cp .build/release/kiln /usr/local/bin/   # or anywhere on your PATH
```

Check it works:

```sh
kiln --version
```

!!! tip
    The fastest way to start a new project is [`kiln new`](cli.md#kiln-new),
    which scaffolds the SwiftPM package, content directory, and a starter
    configuration for you.

## Add the library

A Kiln site is a small SwiftPM executable that depends on the `Kiln` library.
Add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/brokenhandsio/kiln.git", from: "1.0.0"),
],
targets: [
    .executableTarget(
        name: "Docs",
        dependencies: [
            .product(name: "Kiln", package: "kiln"),
        ]
    ),
]
```

## Requirements

| Requirement | Version                          |
| ----------- | -------------------------------- |
| Swift       | 6.2+                             |
| macOS       | 13+ (Ventura)                    |
| Linux       | ✅ (any distribution Swift supports) |

!!! note
    Kiln uses [swift-markdown](https://github.com/apple/swift-markdown) for
    parsing and [Leaf](https://github.com/vapor/leaf-kit) for templating. The
    bundled default theme ships as a package resource, so there's nothing extra
    to install.

Next: build your first site in the [Quick Start](quick-start.md).
