// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "easySvn",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SvnKit", targets: ["SvnKit"])
    ],
    targets: [
        .target(
            name: "SvnKit",
            path: "Sources/SvnKit"
        ),
        .testTarget(
            name: "SvnKitTests",
            dependencies: ["SvnKit"],
            path: "Tests/SvnKitTests"
        )
    ]
)
