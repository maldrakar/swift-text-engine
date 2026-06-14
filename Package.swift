// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTextEngine",
    products: [
        .library(name: "TextEngineCore", targets: ["TextEngineCore"]),
        .library(name: "TextEngineReferenceProviders", targets: ["TextEngineReferenceProviders"]),
        .executable(name: "ViewportBenchmarks", targets: ["ViewportBenchmarks"])
    ],
    targets: [
        .target(name: "TextEngineCore"),
        .target(
            name: "TextEngineReferenceProviders",
            dependencies: ["TextEngineCore"]
        ),
        .executableTarget(
            name: "ViewportBenchmarks",
            dependencies: ["TextEngineCore", "TextEngineReferenceProviders"]
        ),
        .testTarget(
            name: "TextEngineCoreTests",
            dependencies: ["TextEngineCore"]
        )
    ]
)
