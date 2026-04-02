// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenJandi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenJandi",
            path: "TokenJandi",
            exclude: ["Resources"]
        )
    ]
)
