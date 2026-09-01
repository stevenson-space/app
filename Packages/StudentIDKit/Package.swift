// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudentIDKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "StudentIDKit", targets: ["StudentIDKit"]),
    ],
    targets: [
        .target(
            name: "StudentIDKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StudentIDKitTests",
            dependencies: ["StudentIDKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
