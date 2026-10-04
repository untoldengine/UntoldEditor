//
//  ComponentSDKBuildLayoutTests.swift
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

/// The C modules an editor run from source compiles components with: the build folders here are
/// shaped like the ones SwiftPM and Xcode leave, for the engine as it is and for an engine with a
/// C target of its own (`CEngineAtomics`) and a package that brings one (`swift-atomics`).
final class ComponentSDKBuildLayoutTests: XCTestCase {
    private func moduleMapPaths(productsDirectory: URL) throws -> [String] {
        try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: productsDirectory)).cModuleMaps.map(\.path)
    }

    // MARK: The engine as it is

    func test_swiftBuild_theEngineAsItIs_passesTheCShaderTypesModuleMapAndNothingElse() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit"],
            generatedCTargets: ["CShaderTypes"]
        )

        XCTAssertEqual(try moduleMapPaths(productsDirectory: products), [
            scratch.url.appendingPathComponent("build/out/Intermediates.noindex/GeneratedModuleMaps/CShaderTypes.modulemap").path,
        ])
    }

    func test_native_theEngineAsItIs_passesTheCShaderTypesModuleMapAndNothingElse() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeNativeProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "UntoldEditor"],
            generatedCTargets: ["CShaderTypes"],
            // The engine declares it, the editor does not use it: a module map and no objects.
            declaredOnlyCTargets: ["UntoldEngineShaderSupport"]
        )

        XCTAssertEqual(try moduleMapPaths(productsDirectory: products), [
            products.appendingPathComponent("CShaderTypes.build/module.modulemap").path,
        ])
    }

    // MARK: An engine with more C modules

    func test_swiftBuild_anEngineCTargetAndAPackageWithItsOwnModuleMap_areBothPassed() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics"],
            generatedCTargets: ["CShaderTypes", "CEngineAtomics"],
            otherCTargets: ["_AtomicsShims"]
        )
        let ownModuleMap = try scratch.addAtomicsPackage()

        let sdk = try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))

        let generated = scratch.url.appendingPathComponent("build/out/Intermediates.noindex/GeneratedModuleMaps")
        XCTAssertEqual(sdk.cModuleMaps.map(\.path), [
            generated.appendingPathComponent("CShaderTypes.modulemap").path,
            generated.appendingPathComponent("CEngineAtomics.modulemap").path,
            ownModuleMap.path,
        ], "CShaderTypes first, and never the module map of a Swift module's generated header")
        XCTAssertEqual(sdk.providedModules, ["Atomics", "UntoldComponentKit", "UntoldEngine"])
    }

    func test_native_anEngineCTargetAndAPackageWithItsOwnModuleMap_areBothPassed() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeNativeProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics", "UntoldEditor"],
            generatedCTargets: ["CShaderTypes", "CEngineAtomics"],
            otherCTargets: ["_AtomicsShims"],
            declaredOnlyCTargets: ["UntoldEngineShaderSupport"]
        )
        let ownModuleMap = try scratch.addAtomicsPackage()

        XCTAssertEqual(try moduleMapPaths(productsDirectory: products), [
            products.appendingPathComponent("CShaderTypes.build/module.modulemap").path,
            products.appendingPathComponent("CEngineAtomics.build/module.modulemap").path,
            ownModuleMap.path,
        ])
    }

    func test_xcode_findsThePackagesInTheDerivedDataFolder() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            root: "DerivedData/UntoldEditor-abc",
            products: "Build/Products/Debug",
            intermediates: "Build/Intermediates.noindex",
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics"],
            generatedCTargets: ["CShaderTypes"],
            otherCTargets: ["_AtomicsShims"]
        )
        let ownModuleMap = try scratch.addAtomicsPackage(at: "DerivedData/UntoldEditor-abc/SourcePackages/checkouts/swift-atomics")

        XCTAssertEqual(try moduleMapPaths(productsDirectory: products), [
            scratch.url.appendingPathComponent("DerivedData/UntoldEditor-abc/Build/Intermediates.noindex/GeneratedModuleMaps/CShaderTypes.modulemap").path,
            ownModuleMap.path,
        ])
    }

    func test_aPackageUsedByPath_isFoundThroughTheWorkspaceState() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit", "Atomics"],
            generatedCTargets: ["CShaderTypes"],
            otherCTargets: ["_AtomicsShims"]
        )
        let ownModuleMap = try scratch.addAtomicsPackage(at: "Elsewhere/swift-atomics")
        // The clone from before the package was used by path: SwiftPM leaves it, and no longer lists it.
        try scratch.addAtomicsPackage()
        try scratch.writeWorkspaceState(packagesUsedByPath: ["Elsewhere/swift-atomics"])

        XCTAssertEqual(try moduleMapPaths(productsDirectory: products).last, ownModuleMap.path)
    }

    func test_aBuiltCTargetWithoutAnyModuleMap_isLeftOutAndReported() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit"],
            generatedCTargets: ["CShaderTypes", "CEngineAtomics"],
            otherCTargets: ["CNowhere"]
        )

        let sdk = try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))

        XCTAssertEqual(sdk.cModuleMaps.map(\.lastPathComponent), ["CShaderTypes.modulemap", "CEngineAtomics.modulemap"])
        XCTAssertEqual(sdk.cModulesWithoutModuleMap, ["CNowhere"])

        // The Plugins tab and the console say so: the compiler would only name a missing module.
        let basePath = try scratch.directory("Game/Sources/Game/GameData")
        let problems = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: sdk).problems
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems.first?.contains("CNowhere") == true, "\(problems)")
    }

    func test_aTargetThatIsGoneFromItsPackage_andLeftItsObjectsBehind_isLeftOut() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.makeSwiftBuildProducts(
            swiftTargets: ["UntoldEngine", "UntoldComponentKit"],
            generatedCTargets: ["CShaderTypes", "CEngineAtomics", "CStale"]
        )
        // The build folder was used with an engine that had CStale; this one does not.
        try FileManager.default.removeItem(at: scratch.url.appendingPathComponent("engine/Sources/CStale"))

        let sdk = try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))

        XCTAssertEqual(
            sdk.cModuleMaps.map(\.lastPathComponent), ["CShaderTypes.modulemap", "CEngineAtomics.modulemap"],
            "the compiler warns about a module map whose headers are missing, in every build"
        )
        XCTAssertEqual(sdk.cModulesWithoutModuleMap, [], "nothing to report: the target is not part of this engine")
    }

    // MARK: A target's own module map

    func test_ownModuleMap_outsideTheDefaultFolder_isTheOneNearestThePackageRootThatDeclaresTheModule() throws {
        let scratch = try ScratchDirectory()
        let package = try scratch.directory("checkouts/vendor-kit")
        // Declares the module only as a part of another.
        try scratch.write("module Umbrella {\n    module CVendor { header \"a.h\" }\n}", to: "checkouts/vendor-kit/module.modulemap")
        // A copy for the package's benchmarks.
        try scratch.write("module CVendor { header \"a.h\" }", to: "checkouts/vendor-kit/Benchmarks/Sources/CVendor/include/module.modulemap")
        try scratch.write("module CVendorOther { header \"b.h\" }", to: "checkouts/vendor-kit/Vendor/other/module.modulemap")
        let expected = try scratch.write("module CVendor [system] { header \"a.h\" }", to: "checkouts/vendor-kit/Vendor/shims/module.modulemap")

        XCTAssertEqual(ComponentSDKBuildLayout.ownModuleMap(of: "CVendor", inPackages: [package])?.path, expected.path)
        XCTAssertNil(ComponentSDKBuildLayout.ownModuleMap(of: "CAbsent", inPackages: [package]))
    }

    func test_ownModuleMap_theDefaultFolderWinsOverAnyOtherPackage() throws {
        let scratch = try ScratchDirectory()
        let first = try scratch.directory("checkouts/a-kit")
        let second = try scratch.directory("checkouts/b-kit")
        try scratch.write("module CShim { header \"a.h\" }", to: "checkouts/a-kit/Fixtures/module.modulemap")
        let expected = try scratch.write("module CShim { header \"a.h\" }", to: "checkouts/b-kit/Sources/CShim/include/module.modulemap")

        XCTAssertEqual(ComponentSDKBuildLayout.ownModuleMap(of: "CShim", inPackages: [first, second])?.path, expected.path)
    }

    func test_topLevelModules_readsNamesAndSkipsCommentsStringsAndSubmodules() {
        let moduleMap = """
        // module Commented {}
        /* module AlsoCommented {
        } */
        framework module Alpha [system] {
            umbrella header "module Quoted.h" // { not a brace
            explicit module Part { header "part.h" }
            module * { export * }
        }
        module Beta { link "beta" }
        extern module Gamma "Gamma.modulemap"
        module "Delta-Kit" {}
        """

        XCTAssertEqual(ComponentSDKBuildLayout.topLevelModules(inModuleMap: moduleMap), ["Alpha", "Beta", "Gamma", "Delta-Kit"])
        XCTAssertEqual(ComponentSDKBuildLayout.topLevelModules(inModuleMap: ""), [])
    }
}
