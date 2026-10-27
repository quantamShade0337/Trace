// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkInspectorCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NetworkCore", targets: ["NetworkCore"])],
    targets: [
        .target(name: "NetworkCore", path: "Trace/Engine", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "NetworkCoreTests", dependencies: ["NetworkCore"], path: "Tests/NetworkCoreTests")
    ],
    swiftLanguageModes: [.v6]
)
