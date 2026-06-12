// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "easySvn",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SvnKit", targets: ["SvnKit"]),
        .executable(name: "EasySvnApp", targets: ["EasySvnApp"])
    ],
    targets: [
        .target(
            name: "SvnKit",
            path: "Sources/SvnKit"
        ),
        .executableTarget(
            name: "EasySvnApp",
            dependencies: ["SvnKit"],
            path: "Sources/EasySvnApp"
        ),
        .testTarget(
            name: "SvnKitTests",
            dependencies: ["SvnKit"],
            path: "Tests/SvnKitTests"
        )
    ]
)
