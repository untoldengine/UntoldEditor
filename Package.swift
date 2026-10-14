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
        .package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "develop"),
        // Or pin to a release:
        // .package(url: "https://github.com/untoldengine/UntoldEngine.git", exact: "0.22.0"),
    ],
    targets: [
        .executableTarget(
            name: "UntoldEditor",
            dependencies: [
                .product(name: "UntoldEngine", package: "UntoldEngine"),
                .product(name: "UntoldComponentKit", package: "UntoldEngine"),
            ],
            path: "Sources/UntoldEditor",
            exclude: [
                "Info.plist",
            ],
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
                // The identity of the executable run from the build folder (`swift run`, Xcode),
                // which has no app bundle around it: its bundle identifier and name, read from
                // the Info.plist embedded in the binary. The system's device picker of the Apple
                // Vision Pro preview traps without one, and the settings live under it, shared
                // with the packaged app (create_app_bundle.sh writes the bundle's own Info.plist).
                // An incremental build does not notice a change to the file: clean, or touch a source.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", Context.packageDirectory + "/Sources/UntoldEditor/Info.plist",
                ]),
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
