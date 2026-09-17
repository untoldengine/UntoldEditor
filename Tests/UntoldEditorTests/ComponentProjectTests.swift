//
//  ComponentProjectTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
@testable import UntoldEditor
import XCTest

final class ComponentProjectTests: XCTestCase {
    /// `<scratch>/SplatTwin/Sources/SplatTwin/GameData`, the layout the editor opens.
    private func makeProject(in scratch: ScratchDirectory, name: String = "SplatTwin") throws -> URL {
        try scratch.directory("\(name)/Sources/\(name)/GameData")
    }

    func test_projectRootIsThreeLevelsAboveTheAssetFolder() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        XCTAssertEqual(ComponentSourceLocator.projectRoot(forAssetBasePath: basePath).lastPathComponent, "SplatTwin")
    }

    func test_defaultLayout_compilesTheProjectsPluginsFolder() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write("// b", to: "SplatTwin/Sources/SplatTwinPlugins/Nested/B.swift")
        try scratch.write("// a", to: "SplatTwin/Sources/SplatTwinPlugins/A.swift")
        try scratch.write("notes", to: "SplatTwin/Sources/SplatTwinPlugins/README.md")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())

        XCTAssertEqual(layout.projectName, "SplatTwin")
        XCTAssertTrue(layout.pluginsDirectoryExists)
        XCTAssertTrue(layout.problems.isEmpty)
        XCTAssertEqual(layout.units.count, 1)
        let unit = try XCTUnwrap(layout.units.first)
        XCTAssertEqual(unit.role, .project)
        XCTAssertEqual(unit.moduleBaseName, "SplatTwinPlugins")
        XCTAssertEqual(unit.sources.map(\.lastPathComponent), ["A.swift", "B.swift"], "sorted, recursive, Swift only")
        XCTAssertTrue(unit.reloadableImports.isEmpty)
    }

    func test_projectWithoutAPluginsFolder_hasNothingToBuild() throws {
        let scratch = try ScratchDirectory()
        let layout = try ComponentSourceLocator.layout(forAssetBasePath: makeProject(in: scratch), sdk: makeTestSDK())

        XCTAssertTrue(layout.units.isEmpty)
        XCTAssertFalse(layout.pluginsDirectoryExists)
        XCTAssertEqual(layout.pluginsDirectory.lastPathComponent, "SplatTwinPlugins")
    }

    func test_manifestCanMoveThePluginsFolder() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write(#"{ "pluginsFolder": "Gameplay/Code" }"#, to: "SplatTwin/UntoldEditor.json")
        try scratch.write("// c", to: "SplatTwin/Gameplay/Code/C.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())

        XCTAssertEqual(layout.units.first?.moduleBaseName, "Code")
        XCTAssertEqual(layout.units.first?.sources.map(\.lastPathComponent), ["C.swift"])
    }

    func test_pluginTheEditorAlreadyLinks_contributesOnlyItsEditorSources() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write(#"{ "pluginPackages": [ { "path": "../Twins" } ] }"#, to: "SplatTwin/UntoldEditor.json")
        try scratch.write(#"{ "id": "com.miolabs.twins", "module": "UntoldGaussianTwins", "runtimeSources": "Sources/Runtime", "editorSources": "Sources/Editor" }"#, to: "Twins/untold-package.json")
        try scratch.write("// runtime", to: "Twins/Sources/Runtime/System.swift")
        try scratch.write("// editor", to: "Twins/Sources/Editor/TwinsEditor.swift")
        try scratch.write("// project", to: "SplatTwin/Sources/SplatTwinPlugins/P.swift")

        let sdk = makeTestSDK(providedModules: ["UntoldComponentKit", "UntoldEngine", "UntoldGaussianTwins"])
        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: sdk)

        XCTAssertEqual(layout.units.map(\.role), [.packageEditor, .project], "a second copy of a linked plugin would mean two singletons")
        XCTAssertEqual(layout.units[0].moduleBaseName, "UntoldGaussianTwinsEditor")
        XCTAssertTrue(layout.units[0].reloadableImports.isEmpty)
        XCTAssertTrue(layout.units[1].reloadableImports.isEmpty)
        XCTAssertEqual(layout.watchedDirectories.count, 2)
    }

    func test_pluginTheEditorDoesNotLink_buildsRuntimeFirstAndIsImportedByAlias() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write(#"{ "pluginPackages": [ { "path": "../Twins" } ] }"#, to: "SplatTwin/UntoldEditor.json")
        try scratch.write(#"{ "id": "com.example.twins", "module": "Twins", "runtimeSources": "Sources/Runtime", "editorSources": "Sources/Editor" }"#, to: "Twins/untold-package.json")
        try scratch.write("// runtime", to: "Twins/Sources/Runtime/System.swift")
        try scratch.write("// editor", to: "Twins/Sources/Editor/TwinsEditor.swift")
        try scratch.write("// project", to: "SplatTwin/Sources/SplatTwinPlugins/P.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())

        XCTAssertEqual(layout.units.map(\.role), [.packageRuntime, .packageEditor, .project])
        XCTAssertEqual(layout.units.map(\.moduleBaseName), ["Twins", "TwinsEditor", "SplatTwinPlugins"])
        XCTAssertEqual(layout.units[1].reloadableImports, ["Twins"])
        XCTAssertEqual(layout.units[2].reloadableImports, ["Twins"])
    }

    func test_brokenManifestsAreReportedNotFatal() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write(#"{ "pluginPackages": [ { "path": "../Nowhere" } ] }"#, to: "SplatTwin/UntoldEditor.json")
        try scratch.write("// project", to: "SplatTwin/Sources/SplatTwinPlugins/P.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())

        XCTAssertEqual(layout.units.map(\.role), [.project], "the project still builds")
        XCTAssertEqual(layout.problems.count, 1)
        XCTAssertTrue(layout.problems[0].contains("untold-package.json"))
    }

    func test_aProjectMadeBeforeTheRenameStillBuildsAndIsToldToRename() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write("// old", to: "SplatTwin/Sources/SplatTwinComponents/Old.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())

        XCTAssertEqual(layout.pluginsDirectory.lastPathComponent, "SplatTwinComponents", "the old folder is used while it is the only one")
        XCTAssertEqual(layout.units.map(\.moduleBaseName), ["SplatTwinComponents"])
        XCTAssertEqual(layout.problems.count, 1)
        XCTAssertTrue(layout.problems[0].contains("Rename it to SplatTwinPlugins"))

        // Once the new folder exists it wins, and the note goes away.
        try scratch.write("// new", to: "SplatTwin/Sources/SplatTwinPlugins/New.swift")
        let updated = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())
        XCTAssertEqual(updated.pluginsDirectory.lastPathComponent, "SplatTwinPlugins")
        XCTAssertTrue(updated.problems.isEmpty)
    }

    func test_oldManifestKeysAndFileNameStillWorkAndAreReported() throws {
        let scratch = try ScratchDirectory()
        let basePath = try makeProject(in: scratch)
        try scratch.write(#"{ "components": "Gameplay/Code", "plugins": [ { "path": "../Twins" } ] }"#, to: "SplatTwin/UntoldEditor.json")
        try scratch.write(#"{ "id": "com.example.twins", "module": "Twins", "editorSources": "Sources/Editor" }"#, to: "Twins/untold-plugin.json")
        try scratch.write("// editor", to: "Twins/Sources/Editor/E.swift")
        try scratch.write("// project", to: "SplatTwin/Gameplay/Code/P.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: makeTestSDK())

        XCTAssertEqual(layout.units.map(\.moduleBaseName), ["TwinsEditor", "Code"], "everything is still found")
        XCTAssertEqual(layout.problems.count, 3)
        XCTAssertTrue(layout.problems.contains { $0.contains("\"components\" is now \"pluginsFolder\"") })
        XCTAssertTrue(layout.problems.contains { $0.contains("\"plugins\" is now \"pluginPackages\"") })
        XCTAssertTrue(layout.problems.contains { $0.contains("untold-plugin.json is now untold-package.json") })
    }

    func test_moduleIdentifiersAreValidSwiftIdentifiers() {
        XCTAssertEqual(ComponentSourceLocator.moduleIdentifier(from: "SplatTwinPlugins"), "SplatTwinPlugins")
        XCTAssertEqual(ComponentSourceLocator.moduleIdentifier(from: "My Game-Components"), "My_Game_Components")
        XCTAssertEqual(ComponentSourceLocator.moduleIdentifier(from: "3DComponents"), "_3DComponents")
        XCTAssertEqual(ComponentSourceLocator.moduleIdentifier(from: ""), "Plugins")
    }
}
