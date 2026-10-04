//
//  ComponentSDKPackagingTests.swift
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

/// `scripts/copy-component-sdk-c-modules.py` puts the C modules into the app bundle. It is run
/// here on build folders shaped like the real ones: what it ships has to be what a packaged
/// editor then passes to the compiler, and the same modules `ComponentSDKBuildLayout` finds for
/// an editor run from source.
///
/// Skipped, never failed, where python3 is not installed.
final class ComponentSDKPackagingTests: XCTestCase {
    private struct Packaged {
        let sdkRoot: URL
        /// What the script printed: the names that go into `sdk.json`.
        let modules: [String]
        let warnings: String

        func files() throws -> [String] {
            try FileManager.default.subpathsOfDirectory(atPath: sdkRoot.path)
                .filter { path in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: sdkRoot.appendingPathComponent(path).path, isDirectory: &isDirectory)
                        && isDirectory.boolValue == false
                }
                .sorted()
        }

        func moduleMap(of module: String) throws -> String {
            try String(contentsOf: sdkRoot.appendingPathComponent("\(module)/module.modulemap"), encoding: .utf8)
        }
    }

    private func package(products: URL, in scratch: ScratchDirectory) throws -> Packaged {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/copy-component-sdk-c-modules.py")
        let sdkRoot = try scratch.directory("App.app/Contents/Resources/ComponentSDK")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, products.path, sdkRoot.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw XCTSkip("python3 could not be started: \(error.localizedDescription)")
        }
        let printed = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let warnings = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        if process.terminationStatus == 127 {
            throw XCTSkip("python3 is not installed")
        }
        XCTAssertEqual(process.terminationStatus, 0, warnings)
        return Packaged(sdkRoot: sdkRoot, modules: printed.split(separator: "\n").map(String.init), warnings: warnings)
    }

    /// The modules an editor run from this build folder passes a module map for, by the name
    /// each module map declares.
    private func modulesOfSourceBuild(products: URL) throws -> [String] {
        let sdk = try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))
        return try sdk.cModuleMaps.map {
            try XCTUnwrap(ComponentSDKBuildLayout.topLevelModules(inModuleMap: String(contentsOf: $0, encoding: .utf8)).first)
        }
    }

    /// The modules a packaged editor passes a module map for, once `sdk.json` lists `modules`.
    private func modulesOfBundledSDK(_ packaged: Packaged) throws -> [String] {
        let modules = packaged.sdkRoot.appendingPathComponent("Modules", isDirectory: true)
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        for module in ["UntoldEngine", "UntoldComponentKit"] {
            try Data().write(to: modules.appendingPathComponent("\(module).swiftmodule"))
        }
        let manifest = ComponentSDK.Manifest(
            swiftCompilerVersion: "Apple Swift version 6.4",
            target: "arm64-apple-macosx14.0",
            languageMode: "5",
            providedModules: ["UntoldComponentKit", "UntoldEngine"],
            cModules: packaged.modules
        )
        try JSONEncoder().encode(manifest).write(to: packaged.sdkRoot.appendingPathComponent("sdk.json"))
        let sdk = try XCTUnwrap(ComponentSDK.resolveBundled(at: packaged.sdkRoot))
        return sdk.cModuleMaps.map { $0.deletingLastPathComponent().lastPathComponent }
    }

    func test_theEngineAsItIs_shipsCShaderTypesAndNothingElse() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit"],
            generatedCTargets: ["CShaderTypes"]
        )

        let packaged = try package(products: products, in: scratch)

        XCTAssertEqual(packaged.modules, ["CShaderTypes"])
        XCTAssertEqual(try packaged.files(), ["CShaderTypes/CShaderTypes.h", "CShaderTypes/module.modulemap"], "the headers, without the sources beside them")
        XCTAssertEqual(try packaged.moduleMap(of: "CShaderTypes"), "module CShaderTypes {\n    umbrella \".\"\n    export *\n}\n")
        XCTAssertEqual(packaged.warnings, "")
    }

    func test_swiftBuild_everyCModuleOfTheBuildIsShippedWithARelocatableModuleMap() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics"],
            generatedCTargets: ["CShaderTypes", "CEngineAtomics"],
            otherCTargets: ["_AtomicsShims", "CNIOAtomics"]
        )
        try scratch.addAtomicsPackage()
        // The other module map SwiftPM generates: an umbrella header instead of a folder.
        let umbrellaHeader = try scratch.write("// CNIOAtomics.h", to: "build/checkouts/swift-nio/Sources/CNIOAtomics/include/CNIOAtomics.h")
        try scratch.write("// cpp_magic.h", to: "build/checkouts/swift-nio/Sources/CNIOAtomics/include/cpp_magic.h")
        try scratch.write(
            "module CNIOAtomics {\numbrella header \"\(umbrellaHeader.path)\"\nexport *\n}\n",
            to: "build/out/Intermediates.noindex/GeneratedModuleMaps/CNIOAtomics.modulemap"
        )

        let packaged = try package(products: products, in: scratch)

        XCTAssertEqual(packaged.modules, ["CShaderTypes", "CEngineAtomics", "CNIOAtomics", "_AtomicsShims"])
        XCTAssertEqual(try packaged.files(), [
            "CEngineAtomics/CEngineAtomics.h", "CEngineAtomics/module.modulemap",
            "CNIOAtomics/CNIOAtomics.h", "CNIOAtomics/cpp_magic.h", "CNIOAtomics/module.modulemap",
            "CShaderTypes/CShaderTypes.h", "CShaderTypes/module.modulemap",
            "_AtomicsShims/_AtomicsShims.h", "_AtomicsShims/module.modulemap",
        ])
        XCTAssertEqual(try packaged.moduleMap(of: "CEngineAtomics"), "module CEngineAtomics {\n    umbrella \".\"\n    export *\n}\n")
        XCTAssertEqual(try packaged.moduleMap(of: "CNIOAtomics"), "module CNIOAtomics {\n    umbrella header \"CNIOAtomics.h\"\n    export *\n}\n")
        XCTAssertEqual(try packaged.moduleMap(of: "_AtomicsShims"), ScratchDirectory.atomicsShimsModuleMap, "a target's own module map is shipped as it is")
        for module in packaged.modules {
            XCTAssertFalse(try packaged.moduleMap(of: module).contains("\"/"), "\(module) must not name a path of the build machine")
        }

        XCTAssertEqual(try modulesOfSourceBuild(products: products), packaged.modules, "the editor run from source finds the same modules")
        XCTAssertEqual(try modulesOfBundledSDK(packaged), packaged.modules, "and the packaged editor passes every one of them")
    }

    func test_native_shipsTheSameModules_andNotATargetTheEditorDoesNotUse() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeNativeProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics", "UntoldEditor"],
            generatedCTargets: ["CShaderTypes", "CEngineAtomics"],
            otherCTargets: ["_AtomicsShims"],
            declaredOnlyCTargets: ["UntoldEngineShaderSupport"]
        )
        try scratch.addAtomicsPackage()

        let packaged = try package(products: products, in: scratch)

        XCTAssertEqual(packaged.modules, ["CShaderTypes", "CEngineAtomics", "_AtomicsShims"])
        XCTAssertEqual(try modulesOfSourceBuild(products: products), packaged.modules)
        XCTAssertEqual(try modulesOfBundledSDK(packaged), packaged.modules)
    }

    func test_aPackageUsedByPath_isShippedToo() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics"],
            generatedCTargets: ["CShaderTypes"],
            otherCTargets: ["_AtomicsShims"]
        )
        try scratch.write("// _AtomicsShims.h, as the package used by path has it", to: "Elsewhere/swift-atomics/Sources/_AtomicsShims/include/_AtomicsShims.h")
        try scratch.write(ScratchDirectory.atomicsShimsModuleMap, to: "Elsewhere/swift-atomics/Sources/_AtomicsShims/include/module.modulemap")
        // The clone from before the package was used by path: SwiftPM leaves it, and no longer lists it.
        try scratch.addAtomicsPackage()
        try scratch.writeWorkspaceState(packagesUsedByPath: ["Elsewhere/swift-atomics"])

        let packaged = try package(products: products, in: scratch)

        XCTAssertEqual(packaged.modules, ["CShaderTypes", "_AtomicsShims"])
        XCTAssertEqual(
            try String(contentsOf: packaged.sdkRoot.appendingPathComponent("_AtomicsShims/_AtomicsShims.h"), encoding: .utf8),
            "// _AtomicsShims.h, as the package used by path has it"
        )
        XCTAssertEqual(try modulesOfSourceBuild(products: products), packaged.modules)
    }

    func test_aBuiltCTargetWithoutAnyModuleMap_isLeftOut_andABuildWithoutCShaderTypesIsReported() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit"],
            generatedCTargets: ["CShaderTypes", "CStale"],
            otherCTargets: ["CNowhere"]
        )
        // The build folder was used with an engine that had CStale; this one does not.
        try FileManager.default.removeItem(at: scratch.url.appendingPathComponent("engine/Sources/CStale"))

        let leftOut = try package(products: products, in: scratch)
        XCTAssertEqual(leftOut.modules, ["CShaderTypes"])
        XCTAssertTrue(leftOut.warnings.contains("CStale is not shipped"), leftOut.warnings)
        XCTAssertTrue(leftOut.warnings.contains("no module map found for the C target CNowhere"), leftOut.warnings)
        XCTAssertEqual(try modulesOfSourceBuild(products: products), leftOut.modules)

        let empty = try ScratchDirectory()
        let packaged = try package(products: empty.directory("build/out/Products/Debug"), in: empty)
        XCTAssertEqual(packaged.modules, [])
        XCTAssertTrue(packaged.warnings.contains("CShaderTypes module map not found"), packaged.warnings)
    }
}
