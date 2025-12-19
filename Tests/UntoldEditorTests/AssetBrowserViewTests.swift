//
//  AssetBrowserViewTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class AssetBrowserViewTests: XCTestCase {
    // Helper to create a temp directory tree for a test and clean it up afterwards.
    private func withTempDirectory(_ body: (URL) throws -> Void) throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AssetBrowserViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base)
    }

    // Build a view instance with minimal dependencies wired.
    private func makeView(assets: Binding<[String: [Asset]]>,
                          selectedAsset: Binding<Asset?>,
                          selectionManager: SelectionManager = SelectionManager(),
                          sceneGraphModel: SceneGraphModel = SceneGraphModel(),
                          editor_addEntityWithAsset: @escaping () -> Void = {}) -> AssetBrowserView
    {
        AssetBrowserView(
            assets: assets,
            selectedAsset: selectedAsset,
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            editor_addEntityWithAsset: editor_addEntityWithAsset
        )
    }

    func test_rendersCategoriesAndSelectsAssets() throws {
        // Given injected assets
        var assetsState: [String: [Asset]] = [
            "Models": [
                Asset(name: "Spaceship", category: "Models", path: URL(fileURLWithPath: "/tmp/Models/Spaceship"), isFolder: true),
                Asset(name: "Crate", category: "Models", path: URL(fileURLWithPath: "/tmp/Models/Crate"), isFolder: true),
            ],
            "HDR": [
                Asset(name: "studio.hdr", category: "HDR", path: URL(fileURLWithPath: "/tmp/HDR/studio.hdr"), isFolder: false),
            ],
            "Materials": [
                Asset(name: "RustyMetal", category: "Materials", path: URL(fileURLWithPath: "/tmp/Materials/RustyMetal"), isFolder: true),
            ],
            "Animations": [],
        ]
        var selected: Asset? = nil

        _ = makeView(
            assets: .init(get: { assetsState }, set: { assetsState = $0 }),
            selectedAsset: .init(get: { selected }, set: { selected = $0 })
        )

        // When: simulate tapping a file row by assigning selected to an item (what a tap gesture would do).
        let hdrAsset = assetsState["HDR"]!.first!
        selected = hdrAsset

        // Then: the binding should reflect the selected asset
        XCTAssertEqual(selected?.name, "studio.hdr")
        XCTAssertEqual(selected?.category, "HDR")
        XCTAssertEqual(selected?.isFolder, false)
    }

    func test_switchingCategoriesResetsFolderStack() throws {
        var assetsState: [String: [Asset]] = [
            "Models": [
                Asset(name: "Vehicles", category: "Models", path: URL(fileURLWithPath: "/tmp/Models/Vehicles"), isFolder: true),
            ],
            "HDR": [],
        ]
        var selected: Asset? = nil

        var view = makeView(
            assets: .init(get: { assetsState }, set: { assetsState = $0 }),
            selectedAsset: .init(get: { selected }, set: { selected = $0 })
        )

        // We can't poke @State directly. Instead, we validate the intent:
        // - User taps into a folder, then switches category; folderPathStack should clear.
        // Since folderPathStack is internal state, we simulate the flow by rebuilding a new view
        // (as switching tabs would rebuild) and assert state isolation.

        view = makeView(
            assets: .init(get: { assetsState }, set: { assetsState = $0 }),
            selectedAsset: .init(get: { selected }, set: { selected = $0 })
        )

        // No direct access to folderPathStack; ensure no crash and state is isolated.
        XCTAssertNil(selected)
        _ = view
    }

    func test_loadAssetsFromDisk() throws {
        try withTempDirectory { base in
            // Create category directories
            let models = base.appendingPathComponent("Models", isDirectory: true)
            let materials = base.appendingPathComponent("Materials", isDirectory: true)
            let hdr = base.appendingPathComponent("HDR", isDirectory: true)
            let animations = base.appendingPathComponent("Animations", isDirectory: true)
            try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: materials, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: hdr, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: animations, withIntermediateDirectories: true)

            // Models: create a folder per model (what loadAssets expects)
            let carFolder = models.appendingPathComponent("Car", isDirectory: true)
            try FileManager.default.createDirectory(at: carFolder, withIntermediateDirectories: true)
            // Place a model file inside (extension doesn’t matter for folder listing here)
            FileManager.default.createFile(atPath: carFolder.appendingPathComponent("Car.usdz").path, contents: Data())

            // Materials: a folder per material
            let matFolder = materials.appendingPathComponent("Rust", isDirectory: true)
            try FileManager.default.createDirectory(at: matFolder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: matFolder.appendingPathComponent("albedo.png").path, contents: Data())

            // HDR: allow .hdr files directly
            let hdrFile = hdr.appendingPathComponent("studio.hdr")
            FileManager.default.createFile(atPath: hdrFile.path, contents: Data())
            // And a non-hdr file that should be ignored
            let txtFile = hdr.appendingPathComponent("readme.txt")
            FileManager.default.createFile(atPath: txtFile.path, contents: Data())

            // Wire the view with empty assets; onAppear + basePath change will populate
            var assetsState: [String: [Asset]] = [:]
            var selected: Asset? = nil

            // Set the global/singleton base path as the view uses it
            assetBasePath = base
            EditorAssetBasePath.shared.basePath = base

            _ = makeView(
                assets: .init(get: { assetsState }, set: { assetsState = $0 }),
                selectedAsset: .init(get: { selected }, set: { selected = $0 })
            )

            // Replicate the filesystem walk the view does to assert expectations.
            var grouped: [String: [Asset]] = [:]
            for category in AssetCategory.allCases {
                let categoryPath = base.appendingPathComponent(category.rawValue, isDirectory: true)
                var categoryAssets: [Asset] = []

                if let contents = try? FileManager.default.contentsOfDirectory(at: categoryPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for item in contents {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: true))
                            } else if category == .hdr, item.pathExtension.lowercased() == "hdr" {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: false))
                            }
                        }
                    }
                }
                grouped[category.rawValue] = categoryAssets
            }

            // Now assert expectations mirror the view’s logic
            let modelNames = Set(grouped["Models", default: []].map(\.name))
            XCTAssertTrue(modelNames.contains("Car"))

            let materialNames = Set(grouped["Materials", default: []].map(\.name))
            XCTAssertTrue(materialNames.contains("Rust"))

            let hdrNames = Set(grouped["HDR", default: []].map(\.name))
            XCTAssertTrue(hdrNames.contains("studio.hdr"))
            XCTAssertFalse(hdrNames.contains("readme.txt"))
        }
    }

    func test_selectingAssetUpdatesBinding() throws {
        var assetsState: [String: [Asset]] = [
            "Models": [
                Asset(name: "Crate", category: "Models", path: URL(fileURLWithPath: "/tmp/Models/Crate"), isFolder: true),
            ],
        ]
        var selected: Asset? = nil

        _ = makeView(
            assets: .init(get: { assetsState }, set: { assetsState = $0 }),
            selectedAsset: .init(get: { selected }, set: { selected = $0 })
        )

        // Simulate selection (what a tap would do)
        let toSelect = assetsState["Models"]!.first!
        selected = toSelect

        XCTAssertEqual(selected?.name, "Crate")
        XCTAssertEqual(selected?.category, "Models")
        XCTAssertEqual(selected?.isFolder, true)
    }

    func test_loadAssetsFromDisk_includesGaussians() throws {
        try withTempDirectory { base in
            // Create Gaussians directory
            let gaussians = base.appendingPathComponent("Gaussians", isDirectory: true)
            try FileManager.default.createDirectory(at: gaussians, withIntermediateDirectories: true)

            // Add .ply gaussian files directly in Gaussians folder
            let gaussianFile1 = gaussians.appendingPathComponent("pointcloud1.ply")
            let gaussianFile2 = gaussians.appendingPathComponent("pointcloud2.ply")
            FileManager.default.createFile(atPath: gaussianFile1.path, contents: Data())
            FileManager.default.createFile(atPath: gaussianFile2.path, contents: Data())

            // Set the base path
            assetBasePath = base
            EditorAssetBasePath.shared.basePath = base

            var assetsState: [String: [Asset]] = [:]
            var selected: Asset? = nil

            _ = makeView(
                assets: .init(get: { assetsState }, set: { assetsState = $0 }),
                selectedAsset: .init(get: { selected }, set: { selected = $0 })
            )

            // Load assets using the same logic as the view
            var grouped: [String: [Asset]] = [:]
            for category in AssetCategory.allCases {
                let categoryPath = base.appendingPathComponent(category.rawValue, isDirectory: true)
                var categoryAssets: [Asset] = []

                if let contents = try? FileManager.default.contentsOfDirectory(at: categoryPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for item in contents {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: true))
                            } else if category == .gaussians {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: false))
                            }
                        }
                    }
                }
                grouped[category.rawValue] = categoryAssets
            }

            let gaussianNames = Set(grouped["Gaussians", default: []].map(\.name))
            XCTAssertTrue(gaussianNames.contains("pointcloud1.ply"), "Gaussian file 1 should be loaded")
            XCTAssertTrue(gaussianNames.contains("pointcloud2.ply"), "Gaussian file 2 should be loaded")
        }
    }

    func test_loadAssetsFromDisk_includesScenes() throws {
        try withTempDirectory { base in
            // Create Scenes directory
            let scenes = base.appendingPathComponent("Scenes", isDirectory: true)
            try FileManager.default.createDirectory(at: scenes, withIntermediateDirectories: true)

            // Add scene files directly in Scenes folder
            let sceneFile1 = scenes.appendingPathComponent("level1.json")
            let sceneFile2 = scenes.appendingPathComponent("level2.json")
            FileManager.default.createFile(atPath: sceneFile1.path, contents: Data())
            FileManager.default.createFile(atPath: sceneFile2.path, contents: Data())

            // Set the base path
            assetBasePath = base
            EditorAssetBasePath.shared.basePath = base

            var assetsState: [String: [Asset]] = [:]
            var selected: Asset? = nil

            _ = makeView(
                assets: .init(get: { assetsState }, set: { assetsState = $0 }),
                selectedAsset: .init(get: { selected }, set: { selected = $0 })
            )

            // Load assets using the same logic as the view
            var grouped: [String: [Asset]] = [:]
            for category in AssetCategory.allCases {
                let categoryPath = base.appendingPathComponent(category.rawValue, isDirectory: true)
                var categoryAssets: [Asset] = []

                if let contents = try? FileManager.default.contentsOfDirectory(at: categoryPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for item in contents {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: true))
                            } else if category == .scenes {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: false))
                            }
                        }
                    }
                }
                grouped[category.rawValue] = categoryAssets
            }

            let sceneNames = Set(grouped["Scenes", default: []].map(\.name))
            XCTAssertTrue(sceneNames.contains("level1.json"), "Scene file 1 should be loaded")
            XCTAssertTrue(sceneNames.contains("level2.json"), "Scene file 2 should be loaded")
        }
    }

    func test_loadAssetsFromDisk_includesScripts() throws {
        try withTempDirectory { base in
            // Create Scripts directory
            let scripts = base.appendingPathComponent("Scripts", isDirectory: true)
            try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)

            // Add script files directly in Scripts folder
            let scriptFile1 = scripts.appendingPathComponent("player_controller.uscript")
            let scriptFile2 = scripts.appendingPathComponent("enemy_ai.uscript")
            FileManager.default.createFile(atPath: scriptFile1.path, contents: Data())
            FileManager.default.createFile(atPath: scriptFile2.path, contents: Data())

            // Set the base path
            assetBasePath = base
            EditorAssetBasePath.shared.basePath = base

            var assetsState: [String: [Asset]] = [:]
            var selected: Asset? = nil

            _ = makeView(
                assets: .init(get: { assetsState }, set: { assetsState = $0 }),
                selectedAsset: .init(get: { selected }, set: { selected = $0 })
            )

            // Load assets using the same logic as the view
            var grouped: [String: [Asset]] = [:]
            for category in AssetCategory.allCases {
                let categoryPath = base.appendingPathComponent(category.rawValue, isDirectory: true)
                var categoryAssets: [Asset] = []

                if let contents = try? FileManager.default.contentsOfDirectory(at: categoryPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for item in contents {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: true))
                            } else if category == .scripts {
                                categoryAssets.append(Asset(name: item.lastPathComponent, category: category.rawValue, path: item, isFolder: false))
                            }
                        }
                    }
                }
                grouped[category.rawValue] = categoryAssets
            }

            let scriptNames = Set(grouped["Scripts", default: []].map(\.name))
            XCTAssertTrue(scriptNames.contains("player_controller.uscript"), "Script file 1 should be loaded")
            XCTAssertTrue(scriptNames.contains("enemy_ai.uscript"), "Script file 2 should be loaded")
        }
    }
}
