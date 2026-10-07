// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SSHConfigKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SSHConfigKit", targets: ["SSHConfigKit"]),
    ],
    targets: [
        .target(name: "SSHConfigKit"),
        .testTarget(name: "SSHConfigKitTests", dependencies: ["SSHConfigKit"]),
    ]
)
