// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenJandi",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenJandi",
            path: "TokenJandi",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
