// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTokenTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeTokenTracker",
            path: "Sources"
        )
    ]
)
