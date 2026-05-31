// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTextEngine",
    products: [
        .library(name: "TextEngineCore", targets: ["TextEngineCore"])
    ],
    targets: [
        .target(name: "TextEngineCore"),
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        )
    ]
)
