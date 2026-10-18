// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Satsuma",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SatsumaCore"),
        .executableTarget(name: "Satsuma", dependencies: ["SatsumaCore"]),
        .testTarget(name: "SatsumaCoreTests", dependencies: ["SatsumaCore"]),
    ]
)
