// swift-tools-version: 6.0

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Spectro",
    platforms: [
        .macOS(.v13)
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
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "SpectroCore",
            dependencies: [],
            swiftSettings: [.swiftLanguageVersion(.v6)]
        ),
        .macro(
            name: "SpectroMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/SpectroMacros",
            swiftSettings: [.swiftLanguageVersion(.v6)]
        ),
        .target(
            name: "Spectro",
            dependencies: [
                "SpectroCore",
                "SpectroMacros",
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "AsyncKit", package: "async-kit"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/Spectro",
            swiftSettings: [.swiftLanguageVersion(.v6)]
        ),
        .executableTarget(
            name: "SpectroCLI",
            dependencies: [
                "SpectroCore",
                "Spectro",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SpectroCLI",
            swiftSettings: [.swiftLanguageVersion(.v6)]
        ),
        .testTarget(
            name: "SpectroTests",
            dependencies: [
                "SpectroCore",
                "Spectro",
            ],
            path: "Tests/SpectroTests",
            swiftSettings: [.swiftLanguageVersion(.v6)]
        ),
    ]
)
