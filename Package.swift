// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lilt",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Lilt", targets: ["Lilt"])],
    targets: [
        .executableTarget(name: "Lilt"),
        .testTarget(name: "LiltTests", dependencies: ["Lilt"])
    ]
)
