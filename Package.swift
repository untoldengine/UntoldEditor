// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UntoldEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "UntoldEditor", targets: ["UntoldEditor"]),
    ],
    dependencies: [
        // Use a branch during active development:
        //.package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "develop")
        // Or pin to a release:
        // .package(url: "https://github.com/untoldengine/UntoldEngine.git", from: "0.3.0")
        .package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "chores/remove_editor")
    ],
    targets: [
        .executableTarget(
            name: "UntoldEditor",
            dependencies: [
                .product(name: "UntoldEngine", package: "UntoldEngine")
            ],
            path: "Sources/UntoldEditor",
            resources: [
                // .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
            ]
        )
    ]
)

