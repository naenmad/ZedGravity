// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZedGravity",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZedGravity", targets: ["ZedGravity"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ZedGravity",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-export_dynamic"])
            ]
        ),
        .testTarget(
            name: "ZedGravityTests",
            dependencies: ["ZedGravity"],
            path: "Tests"
        )
    ]
)
