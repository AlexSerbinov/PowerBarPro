// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PowerBarPro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PowerBarPro",
            targets: ["PowerBarPro"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PowerBarPro",
            dependencies: [],
            path: "Sources/PowerBarPro",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        ),
        .testTarget(
            name: "PowerBarProTests",
            dependencies: ["PowerBarPro"],
            path: "Tests/PowerBarProTests"
        )
    ]
)
