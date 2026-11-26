// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Griswold",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Griswold", targets: ["Griswold"]),
        .library(name: "GriswoldKit", targets: ["GriswoldKit"]),
    ],
    targets: [
        .executableTarget(
            name: "Griswold",
            dependencies: ["GriswoldKit"],
            path: "Sources/Griswold"
        ),
        .target(
            name: "GriswoldKit",
            path: "Sources/GriswoldKit"
        ),
        .testTarget(
            name: "GriswoldKitTests",
            dependencies: ["GriswoldKit"],
            path: "Tests/GriswoldKitTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
