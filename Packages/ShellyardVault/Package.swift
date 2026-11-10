// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellyardVault",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ShellyardVault", targets: ["ShellyardVault"]),
    ],
    dependencies: [
        .package(path: "../ShellyardModel"),
    ],
    targets: [
        .target(name: "ShellyardVault", dependencies: ["ShellyardModel"]),
        .testTarget(name: "ShellyardVaultTests", dependencies: ["ShellyardVault", "ShellyardModel"]),
    ]
)
