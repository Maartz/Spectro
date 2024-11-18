// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "Spectro",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "SpectroCore", targets: ["SpectroCore"]),
        .library(name: "SpectroKit", targets: ["Spectro"]),
        .executable(name: "spectro", targets: ["SpectroCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.7.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.30.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/vapor/async-kit.git", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.34.0"),
    ],
    targets: [
        .target(
            name: "SpectroCore",
            dependencies: []
        ),
        .target(
            name: "Spectro",
            dependencies: [
                "SpectroCore",
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "AsyncKit", package: "async-kit"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/Spectro"
        ),
        .executableTarget(
            name: "SpectroCLI",
            dependencies: [
                "SpectroCore",
                "Spectro",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SpectroCLI"
        ),
        .testTarget(
            name: "SpectroTests",
            dependencies: [
                "SpectroCore",
                "Spectro",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tests/SpectroTests"
        ),
    ]
)
