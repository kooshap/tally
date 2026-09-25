// swift-tools-version: 6.0

// Pins swift-format, which publishes no binaries, to one exact version so the
// hook, CI, and every Mac format alike whatever Xcode each has. `BuildTools/tool`
// builds it from here; `Package.resolved` pins its dependencies too.
import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-format.git", exact: "604.0.0")
    ],
    targets: [
        // SwiftPM wants a target; the tools are built with `--product`.
        .target(name: "BuildTools")
    ]
)
