// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "rules_xcodeproj",
    dependencies: [
        .package(url: "https://github.com/maxwellE/swift-build.git", branch: "maxwelle/bazel-poc")
    ]
)
