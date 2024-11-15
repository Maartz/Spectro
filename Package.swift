// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Spectro",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "Spectro", targets: ["Spectro"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.32.0")
    ],
    targets: [
        .target(name: "Spectro", dependencies: [
            .product(name: "PostgresKit", package: "postgres-kit"),
            .product(name: "SQLKit", package: "sql-kit")
        ]),
        .testTarget(name: "SpectroTests", dependencies: ["Spectro"])
    ]
)
