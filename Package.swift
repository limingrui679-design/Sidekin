// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CainiaoPet",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CainiaoPetCore", targets: ["CainiaoPetCore"]),
        .library(name: "CainiaoPetCreator", targets: ["CainiaoPetCreator"]),
        .executable(name: "CainiaoPet", targets: ["CainiaoPetApp"]),
        .executable(name: "CainiaoPetBridge", targets: ["CainiaoPetBridge"]),
        .executable(name: "CainiaoPetSelfTest", targets: ["CainiaoPetSelfTest"]),
        .executable(name: "CainiaoPetAPISelfTest", targets: ["CainiaoPetAPISelfTest"])
    ],
    targets: [
        .target(
            name: "CainiaoPetCore",
            path: "Sources/CainiaoPetCore"
        ),
        .target(
            name: "CainiaoPetCreator",
            dependencies: ["CainiaoPetCore"],
            path: "Sources/CainiaoPetCreator",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CainiaoPetApp",
            dependencies: ["CainiaoPetCore", "CainiaoPetCreator"],
            path: "Sources/CainiaoPetApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "CainiaoPetBridge",
            dependencies: ["CainiaoPetCore"],
            path: "Sources/CainiaoPetBridge"
        ),
        .executableTarget(
            name: "CainiaoPetSelfTest",
            dependencies: ["CainiaoPetCore", "CainiaoPetCreator"],
            path: "Sources/CainiaoPetSelfTest"
        ),
        .executableTarget(
            name: "CainiaoPetAPISelfTest",
            dependencies: ["CainiaoPetCore", "CainiaoPetCreator"],
            path: "Sources/CainiaoPetAPISelfTest"
        )
    ]
)
