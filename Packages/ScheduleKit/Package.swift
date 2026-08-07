// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScheduleKit",
    platforms: [
        .iOS(.v18),
        // macOS lets the full test suite run via plain `swift test` on the host,
        // with no simulator involved.
        .macOS(.v14),
    ],
    products: [
        .library(name: "ScheduleKit", targets: ["ScheduleKit"])
    ],
    targets: [
        .target(
            name: "ScheduleKit",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ScheduleKitTests",
            dependencies: ["ScheduleKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
