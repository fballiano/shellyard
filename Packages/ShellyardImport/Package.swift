// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellyardImport",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ShellyardImport", targets: ["ShellyardImport"]),
    ],
    dependencies: [
        .package(path: "../ShellyardModel"),
    ],
    targets: [
        .target(name: "ShellyardImport", dependencies: ["ShellyardModel"]),
        .testTarget(name: "ShellyardImportTests", dependencies: ["ShellyardImport", "ShellyardModel"]),
    ]
)
