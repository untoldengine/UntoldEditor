//
//  EditorEnginePackageTests.swift
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
import UntoldEngine
import XCTest

final class EditorEnginePackageTests: XCTestCase {
    private let resolvedFile = """
    { "originHash": "x", "version": 3, "pins": [
      { "identity": "untoldgaussiantwins", "kind": "remoteSourceControl", "location": "https://github.com/miolabs/UntoldGaussianTwins.git", "state": { "branch": "fork-engine", "revision": "twins000" } },
      { "identity": "untoldengine", "kind": "remoteSourceControl", "location": "https://github.com/miolabs/UntoldEngine.git", "state": { "branch": "develop", "revision": "engine123" } }
    ] }
    """

    func test_packagedEditor_readsItsEngineFromTheSDK() {
        let sdk = ComponentSDK(
            modulesDirectory: URL(fileURLWithPath: "/sdk/Modules"),
            cShaderTypesModuleMap: URL(fileURLWithPath: "/sdk/CShaderTypes/module.modulemap"),
            providedModules: [],
            targetTriple: "arm64-apple-macosx14.0",
            recordedCompilerVersion: "Apple Swift version 6.4",
            engineURL: "https://github.com/miolabs/UntoldEngine.git",
            engineRevision: "bundled456",
            isBundled: true
        )

        let reference = EditorEnginePackage.resolve(sdk: sdk, executableURL: nil)

        XCTAssertEqual(reference, EnginePackageReference(url: "https://github.com/miolabs/UntoldEngine.git", requirement: .revision("bundled456")))
    }

    func test_editorRunFromSource_findsThePackageResolvedAboveItsExecutable() throws {
        let scratch = try ScratchDirectory("EditorEnginePackage")
        try scratch.write(resolvedFile, to: "UntoldEditor/Package.resolved")
        let executable = try scratch.write("", to: "UntoldEditor/.build/out/Products/Debug/UntoldEditor")

        let reference = EditorEnginePackage.resolve(sdk: makeTestSDK(), executableURL: executable)

        XCTAssertEqual(reference, EnginePackageReference(url: "https://github.com/miolabs/UntoldEngine.git", requirement: .revision("engine123")))
    }

    func test_withoutAnyRecord_thereIsNoReference() throws {
        let scratch = try ScratchDirectory("EditorEnginePackage")
        let executable = try scratch.write("", to: "Somewhere/UntoldEditor")
        XCTAssertNil(EditorEnginePackage.resolve(sdk: nil, executableURL: executable))
        XCTAssertNil(EditorEnginePackage.reference(fromResolvedFile: scratch.url.appendingPathComponent("missing.resolved")))
    }
}
