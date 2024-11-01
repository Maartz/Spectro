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
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.0.0")
    ],
    targets: [
        .target(name: "Spectro", dependencies: [
            .product(name: "PostgresKit", package: "postgres-kit")
        ]),
        .testTarget(name: "SpectroTests", dependencies: ["Spectro"])
    ]
)
