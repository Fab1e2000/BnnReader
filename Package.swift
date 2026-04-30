// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Banana_Reader",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "Banana_Reader",
            targets: ["Banana_Reader"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Banana_Reader",
            dependencies: [],
            path: "Sources/Banana_Reader",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
