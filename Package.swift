// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "Explorer",
            path: "Explorer/Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .testTarget(
            name: "ExplorerTests",
            dependencies: [
                "Explorer",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Explorer/Tests"
        )
    ]
)
