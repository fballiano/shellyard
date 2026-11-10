// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShellyardSSH",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ShellyardSSH", targets: ["ShellyardSSH"]),
    ],
    dependencies: [
        .package(path: "../ShellyardModel"),
        // Test only: proves the SFTP client works on a real SSH channel.
        .package(path: "../ShellyardSFTP"),
    ],
    targets: [
        .target(name: "ShellyardSSH", dependencies: ["ShellyardModel"]),
        .testTarget(
            name: "ShellyardSSHTests",
            dependencies: ["ShellyardSSH", "ShellyardModel", "ShellyardSFTP"]
        ),
    ]
)
