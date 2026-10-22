// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoleTidyNest",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MoleTidyNestCore", targets: ["MoleTidyNestCore"]),
        .executable(name: "MoleTidyNest", targets: ["MoleTidyNest"]),
        .executable(name: "MoleTidyNestBridge", targets: ["MoleTidyNestBridge"]),
        .executable(name: "MoleTidyNestMigration", targets: ["MoleTidyNestMigration"])
    ],
    targets: [
        .target(name: "MoleTidyNestProtocol"),
        .target(name: "MoleTidyNestCore", dependencies: ["MoleTidyNestProtocol"]),
        .target(name: "MoleTidyNestEngine", dependencies: ["MoleTidyNestCore", "MoleTidyNestProtocol"], resources: [.copy("Resources/MoleUpstream")]),
        .executableTarget(name: "MoleTidyNestBridge", dependencies: ["MoleTidyNestEngine", "MoleTidyNestProtocol"]),
        .executableTarget(name: "MoleTidyNest", dependencies: ["MoleTidyNestCore", "MoleTidyNestProtocol"]),
        .executableTarget(name: "MoleTidyNestMigration", dependencies: ["MoleTidyNestCore"]),
        .testTarget(name: "MoleTidyNestCoreTests", dependencies: ["MoleTidyNestCore", "MoleTidyNestProtocol"]),
        .testTarget(name: "MoleTidyNestEngineTests", dependencies: ["MoleTidyNestEngine", "MoleTidyNestProtocol", "MoleTidyNestCore"]),
        .testTarget(name: "MoleTidyNestUITests", dependencies: ["MoleTidyNest", "MoleTidyNestCore", "MoleTidyNestProtocol"])
    ]
)
