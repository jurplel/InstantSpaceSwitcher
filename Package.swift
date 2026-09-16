// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InstantSpaceSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "InstantSpaceSwitcher", targets: ["InstantSpaceSwitcher"]),
        .executable(name: "ISSCli", targets: ["ISSCli"])
    ],
    targets: [
        .target(
            name: "ISS",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "SpaceTransition",
            dependencies: []
        ),
        .executableTarget(
            name: "InstantSpaceSwitcher",
            dependencies: ["ISS", "SpaceTransition"]
        ),
        .executableTarget(
            name: "ISSCli",
            dependencies: ["ISS"],
            path: "Sources/ISSCli"
        ),
        .testTarget(
            name: "ISSTests",
            dependencies: ["ISS", "SpaceTransition"]
        )
    ]
)
