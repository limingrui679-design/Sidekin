// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sidekin",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SidekinCore", targets: ["SidekinCore"]),
        .library(name: "SidekinCreator", targets: ["SidekinCreator"]),
        .executable(name: "Sidekin", targets: ["SidekinApp"]),
        .executable(name: "SidekinBridge", targets: ["SidekinBridge"]),
        .executable(name: "SidekinAssetPrep", targets: ["SidekinAssetPrep"]),
        .executable(name: "SidekinSelfTest", targets: ["SidekinSelfTest"]),
        .executable(name: "SidekinAPISelfTest", targets: ["SidekinAPISelfTest"])
    ],
    targets: [
        .target(
            name: "SidekinCore",
            path: "Sources/SidekinCore"
        ),
        .target(
            name: "SidekinCreator",
            dependencies: ["SidekinCore"],
            path: "Sources/SidekinCreator",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "SidekinApp",
            dependencies: ["SidekinCore", "SidekinCreator"],
            path: "Sources/SidekinApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SidekinBridge",
            dependencies: ["SidekinCore"],
            path: "Sources/SidekinBridge"
        ),
        .executableTarget(
            name: "SidekinAssetPrep",
            dependencies: ["SidekinCreator"],
            path: "Sources/SidekinAssetPrep"
        ),
        .executableTarget(
            name: "SidekinSelfTest",
            dependencies: ["SidekinCore", "SidekinCreator"],
            path: "Sources/SidekinSelfTest"
        ),
        .executableTarget(
            name: "SidekinAPISelfTest",
            dependencies: ["SidekinCore", "SidekinCreator"],
            path: "Sources/SidekinAPISelfTest"
        )
    ]
)
