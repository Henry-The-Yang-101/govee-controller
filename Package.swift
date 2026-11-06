// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoveeControllerCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "GoveeCore", targets: ["GoveeCore"])],
    targets: [
        .target(name: "GoveeCore", path: "Sources/Core"),
        .testTarget(name: "GoveeCoreTests", dependencies: ["GoveeCore"], path: "Tests")
    ]
)
