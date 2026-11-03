// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QRReader",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "QRCore"),
        .executableTarget(
            name: "QRReader",
            dependencies: ["QRCore"]
        ),
        .testTarget(
            name: "QRCoreTests",
            dependencies: ["QRCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
