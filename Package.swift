// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhysioKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "PhysioKit", targets: ["PhysioKit"])
    ],
    targets: [
        .target(name: "PhysioKit"),
        .testTarget(name: "PhysioKitTests", dependencies: ["PhysioKit"])
    ]
)
