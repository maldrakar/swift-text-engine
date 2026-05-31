// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTextEngine",
    products: [
        .library(name: "TextEngineCore", targets: ["TextEngineCore"]),
        .executable(name: "ViewportBenchmarks", targets: ["ViewportBenchmarks"])
    ],
    targets: [
        .target(name: "TextEngineCore"),
        .executableTarget(
            name: "ViewportBenchmarks",
            dependencies: ["TextEngineCore"]
        ),
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        )
    ]
)
