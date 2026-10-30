// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForgeMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ForgeCore", targets: ["ForgeCore"]),
        .executable(name: "ForgeMac", targets: ["ForgeMac"]),
        .executable(name: "ForgeCoreChecks", targets: ["ForgeCoreChecks"])
    ],
    targets: [
        .target(name: "ForgeCore", resources: [.process("Resources")]),
        .executableTarget(name: "ForgeMac", dependencies: ["ForgeCore"]),
        .target(name: "ForgeCheckSupport", dependencies: ["ForgeCore"], path: "Tests/ForgeCheckSupport"),
        .executableTarget(name: "ForgeCoreChecks", dependencies: ["ForgeCheckSupport"], path: "Tests/ForgeCoreChecks"),
        .testTarget(name: "ForgeCoreTests", dependencies: ["ForgeCheckSupport"])
    ]
)
