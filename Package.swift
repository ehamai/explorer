// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Explorer",
            path: "Explorer/Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
