// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SortAI",
    platforms: [
        .macOS(.v15)  // macOS 26 Tahoe
    ],
    products: [
        .executable(name: "SortAI", targets: ["SortAI"])
    ],
    dependencies: [
        // Use GRDB 6.x for better SPM compatibility
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "SortAI",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/SortAI",
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I.local/sqlite/install"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L.local/sqlite/install", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../.local/sqlite/install"])
            ]
        ),
        .testTarget(
            name: "SortAITests",
            dependencies: ["SortAI"],
            path: "Tests/SortAITests",
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I.local/sqlite/install"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L.local/sqlite/install", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../.local/sqlite/install"])
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
