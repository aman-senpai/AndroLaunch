// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AndroLaunchCLI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "androlaunch", targets: ["AndroLaunchCLI"]),
        .library(name: "AndroLaunchCore", targets: ["AndroLaunchCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "AndroLaunchCore",
            path: "Sources/AndroLaunchCore",
            swiftSettings: [
                .define("CLI_BUILD")
            ]
        ),
        .executableTarget(
            name: "AndroLaunchCLI",
            dependencies: [
                "AndroLaunchCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AndroLaunchCLI",
            swiftSettings: [
                .define("CLI_BUILD")
            ]
        ),
    ]
)
