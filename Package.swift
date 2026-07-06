// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WorkMemory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WorkMemory", targets: ["WorkMemory"])
    ],
    targets: [
        .executableTarget(
            name: "WorkMemory",
            path: "Sources/WorkMemory",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
