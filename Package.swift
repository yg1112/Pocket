// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pocket",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Pocket",
            targets: ["Pocket"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Pocket",
            dependencies: [],
            path: "Pocket",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PocketTests",
            dependencies: ["Pocket"],
            path: "PocketTests"
        )
    ]
)
