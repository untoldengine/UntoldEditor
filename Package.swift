// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UntoldEditor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "UntoldEditor", targets: ["UntoldEditor"]),
    ],
    dependencies: [
        // Use a branch during active development:
        // .package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "develop"),
        // Or pin to a release:
        // .package(url: "https://github.com/untoldengine/UntoldEngine.git", exact: "0.19.1"),
        // Until the engine pull request that adds UntoldComponentKit is merged, the editor follows
        // that branch: upstream develop plus the kit. Point back at develop afterwards.
        .package(url: "https://github.com/miolabs/UntoldEngine.git", branch: "feature/component_kit-upstream"),
    ],
    targets: [
        .executableTarget(
            name: "UntoldEditor",
            dependencies: [
                .product(name: "UntoldEngine", package: "UntoldEngine"),
                .product(name: "UntoldComponentKit", package: "UntoldEngine"),
            ],
            path: "Sources/UntoldEditor",
            resources: [
                .process("Resources/Thumbnails"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),

        // ✅ Add this new test target
        .testTarget(
            name: "UntoldEditorTests",
            dependencies: [
                "UntoldEditor",
                .product(name: "UntoldComponentKit", package: "UntoldEngine"),
            ],
            path: "Tests/UntoldEditorTests",
            resources: [
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
