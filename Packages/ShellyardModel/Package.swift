// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellyardModel",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ShellyardModel", targets: ["ShellyardModel"]),
    ],
    targets: [
        .target(name: "ShellyardModel"),
        .testTarget(name: "ShellyardModelTests", dependencies: ["ShellyardModel"]),
    ]
)
