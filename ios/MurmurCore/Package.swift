// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MurmurCore",
    products: [
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
    ],
    targets: [
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "MurmurCore",
            dependencies: ["CSQLite"]
        ),
        .testTarget(
            name: "MurmurCoreTests",
            dependencies: ["MurmurCore"]
        ),
    ]
)
