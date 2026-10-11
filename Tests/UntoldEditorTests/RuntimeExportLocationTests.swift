//
//  RuntimeExportLocationTests.swift
//  UntoldEditorTests
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
@testable import UntoldEditor
import XCTest

final class RuntimeExportLocationTests: XCTestCase {
    func test_importedSourceCooksIntoTheFolderItWasImportedInto() {
        let source = URL(fileURLWithPath: "/Project/GameData/Models/Tower/Tower.blend")

        let location = runtimeExportLocation(for: source, assetBasePath: nil)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/GameData/Models/Tower")
    }

    func test_sourceOutsideAFolderOfItsOwnCooksBesideItself() {
        let source = URL(fileURLWithPath: "/Project/GameData/Models/Props/Crate.usdz")

        let location = runtimeExportLocation(for: source, assetBasePath: nil)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models/Props")
        XCTAssertNil(location.assetsFolder)
    }

    func test_sourceUnderResourcesCooksIntoTheMirroredGameDataFolder() {
        // Root-level layout: Resources/Models/Tower/Tower.blend mirrors to
        // GameData/Models/Tower/Tower.blend, and the output location is computed
        // from there -- the pack sits beside the per-asset folder in GameData/Models/.
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Resources/Models/Tower/Tower.blend")

        let location = runtimeExportLocation(for: source, assetBasePath: assetBasePath)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/GameData/Models/Tower")
    }

    func test_sourceUnderResourcesWithNoOwnFolderCooksIntoTheMirroredFolder() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Resources/Models/Props/Crate.usdz")

        let location = runtimeExportLocation(for: source, assetBasePath: assetBasePath)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models/Props")
        XCTAssertNil(location.assetsFolder)
    }

    func test_sourceOutsideResourcesOnRootLevelLayoutFallsBackToCookingBesideItself() {
        // A legacy-layout project, or a source dropped in from outside the project
        // entirely, has nothing to mirror -- cook beside the source like before.
        let assetBasePath = URL(fileURLWithPath: "/Project/Sources/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Sources/Project/GameData/Models/Tower/Tower.blend")

        let location = runtimeExportLocation(for: source, assetBasePath: assetBasePath)

        XCTAssertEqual(location.outputFolder.path, "/Project/Sources/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/Sources/Project/GameData/Models/Tower")
    }

    func test_mirroredResourcesPathMapsGameDataToResources() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let gameDataURL = URL(fileURLWithPath: "/Project/GameData/Models/Tower")

        XCTAssertEqual(
            mirroredResourcesPath(for: gameDataURL, assetBasePath: assetBasePath)?.path,
            "/Project/Resources/Models/Tower"
        )
    }

    func test_mirroredGameDataPathMapsResourcesToGameData() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let resourcesURL = URL(fileURLWithPath: "/Project/Resources/Models/Tower/Tower.blend")

        XCTAssertEqual(
            mirroredGameDataPath(for: resourcesURL, assetBasePath: assetBasePath)?.path,
            "/Project/GameData/Models/Tower/Tower.blend"
        )
    }

    func test_mirroringReturnsNilOnLegacyLayout() {
        let assetBasePath = URL(fileURLWithPath: "/Project/Sources/Project/GameData")
        let gameDataURL = URL(fileURLWithPath: "/Project/Sources/Project/GameData/Models/Tower")

        XCTAssertNil(mirroredResourcesPath(for: gameDataURL, assetBasePath: assetBasePath))
    }

    func test_mirroringReturnsNilWhenURLIsOutsideEitherTree() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let elsewhere = URL(fileURLWithPath: "/Elsewhere/Tower.blend")

        XCTAssertNil(mirroredResourcesPath(for: elsewhere, assetBasePath: assetBasePath))
        XCTAssertNil(mirroredGameDataPath(for: elsewhere, assetBasePath: assetBasePath))
    }

    func test_scriptOptionSupportIsReadFromTheScript() throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeExportLocationTests-\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: script) }
        try #"parser.add_argument("--assets-dir", default=None)"#.write(to: script, atomically: true, encoding: .utf8)

        XCTAssertTrue(engineScript(script, acceptsOption: "--assets-dir"))
        XCTAssertFalse(engineScript(script, acceptsOption: "--include-hidden"))
        XCTAssertFalse(engineScript(script.appendingPathExtension("missing"), acceptsOption: "--assets-dir"))
    }

    func test_exporterPythonScriptSitsBesideTheWrapper() {
        let wrapper = URL(fileURLWithPath: "/Engine/scripts/export-untold")

        XCTAssertEqual(exporterPythonScript(besideExportScript: wrapper).path, "/Engine/scripts/untoldexplorer.py")
    }
}
