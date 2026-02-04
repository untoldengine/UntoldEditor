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
        .package(url: "https://github.com/untoldengine/UntoldEngine.git", exact: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "UntoldEditor",
            dependencies: [
                .product(name: "UntoldEngine", package: "UntoldEngine"),
            ],
            path: "Sources/UntoldEditor",
            resources: [
                // .process("Resources")
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
