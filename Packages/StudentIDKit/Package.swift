// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudentIDKit",
    platforms: [
        .iOS(.v18),
        // macOS 15 is the floor for the Swift Vision API (DetectBarcodesRequest,
        // RecognizeTextRequest, DetectFaceRectanglesRequest) and lets the whole
        // suite — barcode round-trips included — run via plain `swift test`.
        .macOS(.v15),
    ],
    products: [
        .library(name: "StudentIDKit", targets: ["StudentIDKit"])
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
