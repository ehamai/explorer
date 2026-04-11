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
            exclude: ["README.md", "Models/README.md", "Views/README.md", "Views/Components/README.md", "Views/Content/README.md", "Views/Sidebar/README.md", "Views/StatusBar/README.md", "Views/Toolbar/README.md", "ViewModels/README.md", "Services/README.md", "Helpers/README.md"],
            resources: [
                .process("../Resources"),
                .process("AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "ExplorerTests",
            dependencies: [
                "Explorer",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Explorer/Tests",
            exclude: ["README.md"]
        )
    ]
)
