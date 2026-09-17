//
//  ComponentCompilerTests.swift
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

final class ComponentCompilerTests: XCTestCase {
    private let toolchain = ComponentToolchain(swiftcPath: "/toolchain/swiftc", macOSSDKPath: "/sdks/MacOSX.sdk", compilerVersion: "Apple Swift version 6.4")

    private func request(role: ComponentSourceUnit.Role, module: String, imports: [String] = [], revision: Int = 7) -> ComponentCompileRequest {
        let unit = ComponentSourceUnit(
            role: role,
            moduleBaseName: module,
            directory: URL(fileURLWithPath: "/project/Sources/\(module)"),
            sources: [URL(fileURLWithPath: "/project/Sources/\(module)/A.swift"), URL(fileURLWithPath: "/project/Sources/\(module)/B.swift")],
            reloadableImports: imports
        )
        return ComponentCompileRequest(unit: unit, revision: revision, outputDirectory: URL(fileURLWithPath: "/cache"), sdk: makeTestSDK(), toolchain: toolchain)
    }

    func test_projectUnit_exactArguments() {
        let arguments = ComponentCompiler.arguments(for: request(role: .project, module: "SplatTwinComponents"))

        XCTAssertEqual(arguments, [
            "-emit-library", "-parse-as-library",
            "-o", "/cache/SplatTwinComponents_r7.dylib",
            "-module-name", "SplatTwinComponents_r7",
            "-swift-version", "5", "-Onone", "-g",
            "-D", "UNTOLD_EDITOR",
            "-target", "arm64-apple-macosx14.0",
            "-sdk", "/sdks/MacOSX.sdk",
            "-I", "/sdk/Modules",
            "-Xcc", "-fmodule-map-file=/sdk/CShaderTypes/module.modulemap",
            "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
            "/project/Sources/SplatTwinComponents/A.swift",
            "/project/Sources/SplatTwinComponents/B.swift",
        ])
    }

    func test_moduleNameIsUniquePerRevision() {
        XCTAssertEqual(request(role: .project, module: "Game", revision: 1).moduleName, "Game_r1")
        XCTAssertEqual(request(role: .project, module: "Game", revision: 2).moduleName, "Game_r2")
    }

    func test_pluginRuntime_emitsItsModuleSoLaterUnitsCanImportIt() {
        let arguments = ComponentCompiler.arguments(for: request(role: .pluginRuntime, module: "Twins"))

        let emitIndex = try? XCTUnwrap(arguments.firstIndex(of: "-emit-module-path"))
        XCTAssertTrue(arguments.contains("-emit-module"))
        XCTAssertEqual(emitIndex.map { arguments[$0 + 1] }, "/cache/Twins_r7.swiftmodule")
        XCTAssertFalse(arguments.contains("-module-alias"))
    }

    func test_unitImportingAReloadablePlugin_aliasesItAndSearchesTheCache() {
        let arguments = ComponentCompiler.arguments(for: request(role: .project, module: "Game", imports: ["Twins", "Audio"]))

        let aliases = zip(arguments, arguments.dropFirst()).filter { $0.0 == "-module-alias" }.map(\.1)
        XCTAssertEqual(aliases, ["Audio=Audio_r7", "Twins=Twins_r7"])
        let searchPaths = zip(arguments, arguments.dropFirst()).filter { $0.0 == "-I" }.map(\.1)
        XCTAssertEqual(searchPaths, ["/sdk/Modules", "/cache"])
        XCTAssertFalse(arguments.contains("-emit-module"), "only runtimes are imported by others")
    }

    func test_diagnosticsAreParsedAndExcerptsIgnored() {
        let output = """
        /project/Sources/Game/Player.swift:12:9: error: cannot find 'speeed' in scope
        10 |     override func onUpdate(deltaTime: Float) {
        12 |         speeed += 1
           |         `- error: cannot find 'speeed' in scope
        /project/Sources/Game/Player.swift:3:8: warning: unused import
        /project/Sources/Game/Player.swift:12:9: note: did you mean 'speed'?
        /project/Sources/Game/Player.swift:12:9: error: cannot find 'speeed' in scope
        error: fatalError
        """

        let diagnostics = ComponentCompiler.parseDiagnostics(output)

        XCTAssertEqual(diagnostics.map(\.severity), [.error, .warning, .note], "the repeated error is kept once")
        XCTAssertEqual(diagnostics[0].file, "/project/Sources/Game/Player.swift")
        XCTAssertEqual(diagnostics[0].line, 12)
        XCTAssertEqual(diagnostics[0].column, 9)
        XCTAssertEqual(diagnostics[0].message, "cannot find 'speeed' in scope")
        XCTAssertEqual(diagnostics[0].fileName, "Player.swift")
    }

    func test_messagesThatContainColonsSurvive() {
        let diagnostics = ComponentCompiler.parseDiagnostics("/a/B.swift:1:2: error: expected ':' after label: see docs")
        XCTAssertEqual(diagnostics.first?.message, "expected ':' after label: see docs")
    }
}
