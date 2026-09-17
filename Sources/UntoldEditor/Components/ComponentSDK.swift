//
//  ComponentSDK.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The Swift modules a component library compiles against.
///
/// Compiling against the editor's own modules, and linking nothing, is what makes loaded code
/// share the editor's engine: one `scene`, one registry. A packaged editor ships them in
/// `Contents/Resources/ComponentSDK`; an editor run from source finds them in the build
/// directory next to its executable.
struct ComponentSDK: Equatable {
    /// `sdk.json` of a packaged SDK.
    struct Manifest: Codable, Equatable {
        var swiftCompilerVersion: String
        var engineRevision: String?
        var target: String
        var languageMode: String
        var providedModules: [String]
    }

    static let bundleDirectoryName = "ComponentSDK"
    static let manifestFileName = "sdk.json"

    let modulesDirectory: URL
    let cShaderTypesModuleMap: URL
    /// Modules the editor itself links, which a plugin must therefore never bring a second copy of.
    let providedModules: [String]
    let targetTriple: String
    /// The compiler that built the editor. `nil` for a source build, where the same toolchain
    /// builds both and the check is moot.
    let recordedCompilerVersion: String?
    let engineRevision: String?
    let isBundled: Bool

    static var defaultTargetTriple: String {
        #if arch(arm64)
            return "arm64-apple-macosx14.0"
        #else
            return "x86_64-apple-macosx14.0"
        #endif
    }

    static func resolve(
        resourceURL: URL? = Bundle.main.resourceURL,
        executableURL: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default
    ) -> ComponentSDK? {
        if let resourceURL,
           let bundled = resolveBundled(at: resourceURL.appendingPathComponent(bundleDirectoryName, isDirectory: true), fileManager: fileManager)
        {
            return bundled
        }
        guard let executableURL else { return nil }
        // `.build/debug` is a symlink; the module maps are found relative to the real directory.
        let products = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        return resolveFromBuildProducts(productsDirectory: products, fileManager: fileManager)
    }

    static func resolveBundled(at sdkRoot: URL, fileManager: FileManager = .default) -> ComponentSDK? {
        let modules = sdkRoot.appendingPathComponent("Modules", isDirectory: true)
        let moduleMap = sdkRoot.appendingPathComponent("CShaderTypes/module.modulemap")
        let manifestURL = sdkRoot.appendingPathComponent(manifestFileName)
        guard hasRequiredModules(in: modules, fileManager: fileManager),
              fileManager.fileExists(atPath: moduleMap.path),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }

        return ComponentSDK(
            modulesDirectory: modules,
            cShaderTypesModuleMap: moduleMap,
            providedModules: manifest.providedModules,
            targetTriple: manifest.target,
            recordedCompilerVersion: manifest.swiftCompilerVersion,
            engineRevision: manifest.engineRevision,
            isBundled: true
        )
    }

    /// SwiftPM has two layouts, and Xcode's matches the newer one: modules beside the products
    /// with generated module maps under `Intermediates.noindex`, or modules in `Modules/` with
    /// the module map in `CShaderTypes.build/`.
    static func resolveFromBuildProducts(productsDirectory: URL, fileManager: FileManager = .default) -> ComponentSDK? {
        let moduleCandidates = [productsDirectory, productsDirectory.appendingPathComponent("Modules", isDirectory: true)]
        let moduleMapCandidates = [
            productsDirectory.appendingPathComponent("../../Intermediates.noindex/GeneratedModuleMaps/CShaderTypes.modulemap").standardizedFileURL,
            productsDirectory.appendingPathComponent("CShaderTypes.build/module.modulemap"),
        ]
        guard let modules = moduleCandidates.first(where: { hasRequiredModules(in: $0, fileManager: fileManager) }),
              let moduleMap = moduleMapCandidates.first(where: { fileManager.fileExists(atPath: $0.path) })
        else { return nil }

        return ComponentSDK(
            modulesDirectory: modules,
            cShaderTypesModuleMap: moduleMap,
            providedModules: moduleNames(in: modules, fileManager: fileManager),
            targetTriple: defaultTargetTriple,
            recordedCompilerVersion: nil,
            engineRevision: nil,
            isBundled: false
        )
    }

    static func moduleNames(in directory: URL, fileManager: FileManager = .default) -> [String] {
        let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return contents
            .filter { $0.hasSuffix(".swiftmodule") }
            .map { String($0.dropLast(".swiftmodule".count)) }
            .sorted()
    }

    private static func hasRequiredModules(in directory: URL, fileManager: FileManager) -> Bool {
        ["UntoldEngine", "UntoldComponentKit"].allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent("\($0).swiftmodule").path)
        }
    }
}
