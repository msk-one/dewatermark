// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dewatermark",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DewatermarkCore", targets: ["DewatermarkCore"]),
        .executable(name: "Dewatermark", targets: ["Dewatermark"]),
    ],
    targets: [
        .target(
            name: "DewatermarkCore",
            path: "Sources/DewatermarkCore"
        ),
        .executableTarget(
            name: "Dewatermark",
            dependencies: ["DewatermarkCore"],
            path: "Sources/Dewatermark"
        ),
        .testTarget(
            name: "DewatermarkCoreTests",
            dependencies: ["DewatermarkCore"],
            path: "Tests/DewatermarkCoreTests"
        ),
    ]
)
