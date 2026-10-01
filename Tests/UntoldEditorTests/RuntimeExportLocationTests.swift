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

        let location = runtimeExportLocation(for: source)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models")
        XCTAssertEqual(location.assetsFolder?.path, "/Project/GameData/Models/Tower")
    }

    func test_sourceOutsideAFolderOfItsOwnCooksBesideItself() {
        let source = URL(fileURLWithPath: "/Project/GameData/Models/Props/Crate.usdz")

        let location = runtimeExportLocation(for: source)

        XCTAssertEqual(location.outputFolder.path, "/Project/GameData/Models/Props")
        XCTAssertNil(location.assetsFolder)
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
