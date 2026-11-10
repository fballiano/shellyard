// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellyardSFTP",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ShellyardSFTP", targets: ["ShellyardSFTP"]),
    ],
    targets: [
        .target(name: "ShellyardSFTP"),
        .testTarget(name: "ShellyardSFTPTests", dependencies: ["ShellyardSFTP"]),
    ]
)
