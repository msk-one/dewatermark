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
        .executable(name: "SmokeRunner", targets: ["SmokeRunner"]),
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
        .executableTarget(
            name: "SmokeRunner",
            dependencies: ["DewatermarkCore"],
            path: "Sources/SmokeRunner"
        ),
        .testTarget(
            name: "DewatermarkCoreTests",
            dependencies: ["DewatermarkCore"],
            path: "Tests/DewatermarkCoreTests"
        ),
    ]
)
