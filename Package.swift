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
        // TEMPORARY: the Splat Debug switches and the runtime limits this branch exposes land in
        // untoldengine/UntoldEngine#1207; this pin follows that branch until it merges, then goes
        // back to develop.
        .package(url: "https://github.com/miolabs/UntoldEngine.git", branch: "feature/gaussian_render_fidelity_upstream"),
    ],
    targets: [
        .executableTarget(
            name: "UntoldEditor",
            dependencies: [
                .product(name: "UntoldEngine", package: "UntoldEngine"),
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
            dependencies: ["UntoldEditor"],
            path: "Tests/UntoldEditorTests",
            resources: [
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
