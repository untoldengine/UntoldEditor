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

        let location = runtimeExportLocation(for: source, category: .models, assetBasePath: nil)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/GameData/Models/Tower")
    }

    func test_sourceOutsideAFolderOfItsOwnCooksBesideItself() {
        let source = URL(fileURLWithPath: "/Project/GameData/Models/Props/Crate.usdz")

        let location = runtimeExportLocation(for: source, category: .models, assetBasePath: nil)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models/Props")
        XCTAssertNil(location.assetsFolder)
    }

    func test_sourceUnderResourcesCooksIntoGameDataNamedAfterTheSourceAlone() {
        // Resources/ is free-form -- the source's own location inside it (however the
        // user organized it) never factors in. Only the chosen category + filename do.
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Resources/SomeFolder/Deep/Tower.blend")

        let location = runtimeExportLocation(for: source, category: .models, assetBasePath: assetBasePath)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/GameData/Models/Tower")
    }

    func test_sameResourcesSourceCooksIntoWhicheverCategoryWasChosen() {
        // The exact point of deciding the category at cook time, not import time: the
        // same source file can become a Model or an Animation depending on the action
        // the user picks.
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Resources/Walk.blend")

        let asModel = runtimeExportLocation(for: source, category: .models, assetBasePath: assetBasePath)
        let asAnimation = runtimeExportLocation(for: source, category: .animations, assetBasePath: assetBasePath)

        XCTAssertEqual(asModel.outputFolder.path, "/Project/GameData/Models")
        XCTAssertEqual(asAnimation.outputFolder.path, "/Project/GameData/Animations")
    }

    func test_sourceOutsideResourcesOnRootLevelLayoutFallsBackToCookingBesideItself() {
        // A legacy-layout project, or a source dropped in from outside the project
        // entirely, has nothing to mirror -- cook beside the source like before.
        let assetBasePath = URL(fileURLWithPath: "/Project/Sources/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Sources/Project/GameData/Models/Tower/Tower.blend")

        let location = runtimeExportLocation(for: source, category: .models, assetBasePath: assetBasePath)

        XCTAssertEqual(location.outputFolder.path, "/Project/Sources/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/Sources/Project/GameData/Models/Tower")
    }

    func test_isUnderResourcesMatchesAnythingBelowTheResourcesRoot() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")

        XCTAssertTrue(isUnderResources(URL(fileURLWithPath: "/Project/Resources/Walk.blend"), assetBasePath: assetBasePath))
        XCTAssertTrue(isUnderResources(URL(fileURLWithPath: "/Project/Resources/Deep/Nested/Walk.blend"), assetBasePath: assetBasePath))
        XCTAssertFalse(isUnderResources(URL(fileURLWithPath: "/Project/GameData/Models/Walk.blend"), assetBasePath: assetBasePath))
    }

    func test_isUnderResourcesIsFalseOnTheLegacyLayout() {
        let assetBasePath = URL(fileURLWithPath: "/Project/Sources/Project/GameData")
        XCTAssertFalse(isUnderResources(URL(fileURLWithPath: "/Project/Resources/Walk.blend"), assetBasePath: assetBasePath))
    }

    func test_resourcesImportFolderUsesTheBrowsedFolderWhenAlreadyUnderResources() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let browsing = URL(fileURLWithPath: "/Project/Resources/Characters")

        let destination = resourcesImportFolder(forBaseName: "Hero", browsing: browsing, assetBasePath: assetBasePath)

        XCTAssertEqual(destination?.path, "/Project/Resources/Characters/Hero")
    }

    func test_resourcesImportFolderDefaultsToTheResourcesRootWhenBrowsingGameData() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let browsing = URL(fileURLWithPath: "/Project/GameData/Models")

        let destination = resourcesImportFolder(forBaseName: "Hero", browsing: browsing, assetBasePath: assetBasePath)

        XCTAssertEqual(destination?.path, "/Project/Resources/Hero")
    }

    func test_resourcesImportFolderIsNilOnTheLegacyLayout() {
        let assetBasePath = URL(fileURLWithPath: "/Project/Sources/Project/GameData")
        XCTAssertNil(resourcesImportFolder(forBaseName: "Hero", browsing: nil, assetBasePath: assetBasePath))
    }

    func test_tilesExportDestinationFolderNamesTheFolderAfterTheSourceUnderResources() {
        let assetBasePath = URL(fileURLWithPath: "/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Resources/City/City.usdz")

        XCTAssertEqual(
            tilesExportDestinationFolder(for: source, assetBasePath: assetBasePath).path,
            "/Project/GameData/StreamModels/City"
        )
    }

    func test_tilesExportDestinationFolderIsBesideTheSourceOutsideResources() {
        let assetBasePath = URL(fileURLWithPath: "/Project/Sources/Project/GameData")
        let source = URL(fileURLWithPath: "/Project/Sources/Project/GameData/StreamModels/City/City.usdz")

        XCTAssertEqual(
            tilesExportDestinationFolder(for: source, assetBasePath: assetBasePath).path,
            "/Project/Sources/Project/GameData/StreamModels/City"
        )
    }

    func test_sourceFolderCandidateResolvesAPackViaItsManifestSourceAssetField() throws {
        let scratch = try ScratchDirectory()
        let projectRoot = try scratch.directory("MyGame")
        let assetBasePath = projectRoot.appendingPathComponent("GameData")
        let packDir = try scratch.directory("MyGame/GameData/Models")
        let sourceDir = try scratch.directory("MyGame/Resources/Characters/Hero")
        // Mirrors how the exporter writes it: relative to the pack's own directory.
        let packJSON = """
        {"formatVersion": 1, "sourceAsset": "../../Resources/Characters/Hero/Hero.blend", "models": [
          {"displayName": "Hero", "path": "Hero.untold", "transform": [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]}
        ]}
        """
        let packURL = packDir.appendingPathComponent("Hero.untoldpack")
        try Data(packJSON.utf8).write(to: packURL)
        _ = sourceDir // directory just needs to exist; the manifest points at it

        let found = sourceFolderCandidate(for: packURL, assetBasePath: assetBasePath)

        XCTAssertEqual(found?.standardizedFileURL.path, sourceDir.standardizedFileURL.path)
    }

    func test_sourceFolderCandidateSearchesResourcesForAPlainUntoldWithNoManifest() throws {
        let scratch = try ScratchDirectory()
        let projectRoot = try scratch.directory("MyGame")
        let assetBasePath = projectRoot.appendingPathComponent("GameData")
        let assetURL = try scratch.directory("MyGame/GameData/Models").appendingPathComponent("Hero.untold")
        let sourceDir = try scratch.directory("MyGame/Resources/Characters/Hero")

        let found = sourceFolderCandidate(for: assetURL, assetBasePath: assetBasePath)

        XCTAssertEqual(found?.standardizedFileURL.path, sourceDir.standardizedFileURL.path)
    }

    func test_sourceFolderCandidateFallsBackToTheLegacySameFolderLocation() throws {
        let scratch = try ScratchDirectory()
        let projectRoot = try scratch.directory("MyGame")
        let assetBasePath = projectRoot.appendingPathComponent("GameData")
        let modelsFolder = assetBasePath.appendingPathComponent("Models")
        let assetURL = modelsFolder.appendingPathComponent("Tower.untold")
        try scratch.directory("MyGame/GameData/Models/Tower")
        // No Resources/ folder at all -- legacy layout.

        let found = sourceFolderCandidate(for: assetURL, assetBasePath: assetBasePath)

        XCTAssertEqual(found?.path, modelsFolder.appendingPathComponent("Tower").path)
    }

    func test_sourceFolderCandidateReturnsNilWhenNothingIsFound() throws {
        let scratch = try ScratchDirectory()
        let projectRoot = try scratch.directory("MyGame")
        let assetBasePath = projectRoot.appendingPathComponent("GameData")
        let assetURL = assetBasePath.appendingPathComponent("Models/Tower.untold")

        XCTAssertNil(sourceFolderCandidate(for: assetURL, assetBasePath: assetBasePath))
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
