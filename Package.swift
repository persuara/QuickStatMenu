// swift-tools-version:5.9
// persuara

import PackageDescription

let package = Package(
    name: "MenuStats",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MenuStats", path: "Sources/MenuStats")
    ]
)
