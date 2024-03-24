// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Harmony",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10), .macCatalyst(.v17)],
    products: [
        .library(
            name: "Harmony",
            targets: ["Harmony"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.26.0"),
    ],
    targets: [
        .target(
            name: "Harmony",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Harmony",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "HarmonyTests",
            dependencies: ["Harmony"]
        ),
    ]
)
