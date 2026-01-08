// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SortAI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "SortAI", targets: ["SortAI"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "SortAI",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/SortAI",
            cSettings: [
                .headerSearchPath("/opt/homebrew/opt/sqlite/include")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags(["-L/opt/homebrew/opt/sqlite/lib"])
            ]
        ),
        .testTarget(
            name: "SortAITests",
            dependencies: ["SortAI"],
            path: "Tests/SortAITests"
        )
    ],
    swiftLanguageModes: [.v6]
)
