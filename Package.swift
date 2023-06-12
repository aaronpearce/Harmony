// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Harmony",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(
            name: "Harmony",
            targets: ["Harmony"]),
    ],
    dependencies: [
        .package(name: "GRDB", url: "https://github.com/groue/GRDB.swift", from: "6.15.0"),
    ],
    targets: [
        .target(
            name: "Harmony",
            dependencies: ["GRDB"]
        ),
        .testTarget(
            name: "HarmonyTests",
            dependencies: ["Harmony"]),
    ]
)
