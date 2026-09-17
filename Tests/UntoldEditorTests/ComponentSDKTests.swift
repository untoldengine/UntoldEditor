//
//  ComponentSDKTests.swift
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

final class ComponentSDKTests: XCTestCase {
    private func addModules(_ names: [String], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try Data().write(to: directory.appendingPathComponent("\(name).swiftmodule"))
        }
    }

    func test_newBuildLayout_modulesBesideProductsAndGeneratedModuleMaps() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.directory("out/Products/Debug")
        try addModules(["UntoldEngine", "UntoldComponentKit", "UntoldGaussianTwins"], to: products)
        let moduleMap = try scratch.write("module CShaderTypes {}", to: "out/Intermediates.noindex/GeneratedModuleMaps/CShaderTypes.modulemap")

        let sdk = try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))

        XCTAssertEqual(sdk.modulesDirectory.path, products.path)
        XCTAssertEqual(sdk.cShaderTypesModuleMap.path, moduleMap.path)
        XCTAssertEqual(sdk.providedModules, ["UntoldComponentKit", "UntoldEngine", "UntoldGaussianTwins"])
        XCTAssertNil(sdk.recordedCompilerVersion, "a source build never needs the compiler check")
        XCTAssertFalse(sdk.isBundled)
    }

    func test_classicBuildLayout_modulesFolderAndTargetModuleMap() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.directory("arm64-apple-macosx/debug")
        try addModules(["UntoldEngine", "UntoldComponentKit"], to: products.appendingPathComponent("Modules"))
        let moduleMap = try scratch.write("module CShaderTypes {}", to: "arm64-apple-macosx/debug/CShaderTypes.build/module.modulemap")

        let sdk = try XCTUnwrap(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))

        XCTAssertEqual(sdk.modulesDirectory.path, products.appendingPathComponent("Modules").path)
        XCTAssertEqual(sdk.cShaderTypesModuleMap.path, moduleMap.path)
    }

    func test_executableReachedThroughTheDebugSymlink_stillFindsTheModuleMap() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.directory("build/out/Products/Debug")
        try addModules(["UntoldEngine", "UntoldComponentKit"], to: products)
        try scratch.write("module CShaderTypes {}", to: "build/out/Intermediates.noindex/GeneratedModuleMaps/CShaderTypes.modulemap")
        try Data().write(to: products.appendingPathComponent("UntoldEditor"))
        let link = scratch.url.appendingPathComponent("build/debug")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: products)

        let sdk = ComponentSDK.resolve(resourceURL: nil, executableURL: link.appendingPathComponent("UntoldEditor"))

        XCTAssertNotNil(sdk, "../.. must be taken from the real products directory, not from the symlink")
    }

    func test_bundledSDK_winsAndCarriesTheRecordedCompiler() throws {
        let scratch = try ScratchDirectory()
        let resources = try scratch.directory("App.app/Contents/Resources")
        try addModules(["UntoldEngine", "UntoldComponentKit"], to: resources.appendingPathComponent("ComponentSDK/Modules"))
        try scratch.write("module CShaderTypes {}", to: "App.app/Contents/Resources/ComponentSDK/CShaderTypes/module.modulemap")
        let manifest = ComponentSDK.Manifest(
            swiftCompilerVersion: "Apple Swift version 6.4",
            engineRevision: "abc123",
            target: "arm64-apple-macosx14.0",
            languageMode: "5",
            providedModules: ["UntoldComponentKit", "UntoldEngine"]
        )
        try JSONEncoder().encode(manifest).write(to: resources.appendingPathComponent("ComponentSDK/sdk.json"))

        let sdk = try XCTUnwrap(ComponentSDK.resolve(resourceURL: resources, executableURL: nil))

        XCTAssertTrue(sdk.isBundled)
        XCTAssertEqual(sdk.recordedCompilerVersion, "Apple Swift version 6.4")
        XCTAssertEqual(sdk.engineRevision, "abc123")
        XCTAssertEqual(sdk.providedModules, ["UntoldComponentKit", "UntoldEngine"])
    }

    func test_missingKitModule_isNotAnSDK() throws {
        let scratch = try ScratchDirectory()
        let products = try scratch.directory("out/Products/Debug")
        try addModules(["UntoldEngine"], to: products)
        try scratch.write("module CShaderTypes {}", to: "out/Intermediates.noindex/GeneratedModuleMaps/CShaderTypes.modulemap")

        XCTAssertNil(ComponentSDK.resolveFromBuildProducts(productsDirectory: products))
        XCTAssertNil(ComponentSDK.resolve(resourceURL: nil, executableURL: nil))
    }
}
