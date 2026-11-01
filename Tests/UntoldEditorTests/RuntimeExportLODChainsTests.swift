//
//  RuntimeExportLODChainsTests.swift
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

/// The LOD chains a cook builds for the pack it wrote.
final class RuntimeExportLODChainsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lod-chains-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func test_thePackManifestACookWritesBesideItsOutputIsFound() throws {
        let output = folder.appendingPathComponent("site.untold")
        let pack = folder.appendingPathComponent("site.untoldpack")
        try Data("{}".utf8).write(to: pack)

        XCTAssertEqual(exportedPackManifest(besideOutput: output), pack)
    }

    func test_aCookOfASingleModelHasNoPackManifest() throws {
        let output = folder.appendingPathComponent("crate.untold")
        try Data().write(to: output)

        XCTAssertNil(exportedPackManifest(besideOutput: output))
    }

    func test_theLinesOfAPackWithChainsSayWhatWasBuilt() {
        let lines = lodChainLines(packName: "site.untoldpack", modelCount: 274, chainCount: 60, levelCount: 180, levelBytes: 37 * 1_048_576, blockedPaths: [], failures: [])

        XCTAssertEqual(lines, [ToolOutputLine(level: .info, text: "LOD chains of site.untoldpack: 60 of 274 models, 180 level files, 37 MB")])
        XCTAssertEqual(taskDetail("Wrote site.untoldpack", warningsIn: lines), "Wrote site.untoldpack")
    }

    func test_smallLevelsAreCountedInKilobytes() {
        let lines = lodChainLines(packName: "props.untoldpack", modelCount: 3, chainCount: 1, levelCount: 3, levelBytes: 30 * 1024, blockedPaths: [], failures: [])

        XCTAssertEqual(lines.first?.text, "LOD chains of props.untoldpack: 1 of 3 models, 3 level files, 30 KB")
    }

    func test_aPackOfSmallModelsGetsNoChainsAndNoWarning() {
        let lines = lodChainLines(packName: "props.untoldpack", modelCount: 12, chainCount: 0, levelCount: 0, levelBytes: 0, blockedPaths: [], failures: [])

        XCTAssertEqual(lines, [ToolOutputLine(level: .info, text: "LOD chains of props.untoldpack: none of its 12 models is big enough for one")])
    }

    func test_anEmptyPackIsSaidSo() {
        let lines = lodChainLines(packName: "empty.untoldpack", modelCount: 0, chainCount: 0, levelCount: 0, levelBytes: 0, blockedPaths: [], failures: [])

        XCTAssertEqual(lines, [ToolOutputLine(level: .info, text: "LOD chains of empty.untoldpack: the pack places no model")])
    }

    func test_aModelLeftWithoutAChainIsAWarningTheTaskCounts() {
        let lines = lodChainLines(
            packName: "site.untoldpack", modelCount: 10, chainCount: 7, levelCount: 21, levelBytes: 2_000_000,
            blockedPaths: ["Tree/Tree.untold"], failures: [(path: "Car/Car.untold", reason: "the file could not be read")]
        )

        XCTAssertEqual(lines.map(\.level), [.info, .warning, .warning])
        XCTAssertEqual(lines[1].text, "⚠️ Tree/Tree.untold: no LOD chain, a file that is not one of its levels has a level's name")
        XCTAssertEqual(lines[2].text, "⚠️ Car/Car.untold: no LOD chain, the file could not be read")
        XCTAssertEqual(taskDetail("Wrote site.untoldpack", warningsIn: lines), "Wrote site.untoldpack (2 warnings, see Console)")
    }

    func test_aPackWhoseManifestCannotBeReadLeavesAWarningNotAFailure() throws {
        let pack = folder.appendingPathComponent("broken.untoldpack")
        try Data("not json".utf8).write(to: pack)
        var progressCalls = 0

        let lines = buildExportedLODChains(forPackAt: pack) { _, _ in progressCalls += 1 }

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].level, .warning)
        XCTAssertTrue(lines[0].text.hasPrefix("⚠️ The LOD chains of broken.untoldpack were not built: "), lines[0].text)
        XCTAssertEqual(progressCalls, 0)
        XCTAssertEqual(try Data(contentsOf: pack), Data("not json".utf8), "the manifest is left as it was")
    }

    func test_aPackWithoutModelsIsChainedWithoutAWarning() throws {
        let pack = folder.appendingPathComponent("empty.untoldpack")
        try Data(#"{"formatVersion": 1, "models": []}"#.utf8).write(to: pack)

        let lines = buildExportedLODChains(forPackAt: pack) { _, _ in }

        XCTAssertEqual(lines, [ToolOutputLine(level: .info, text: "LOD chains of empty.untoldpack: the pack places no model")])
    }
}
