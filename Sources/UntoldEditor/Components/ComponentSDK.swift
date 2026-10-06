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

/// The modules a component library compiles against.
///
/// Compiling against the editor's own modules, and linking nothing, is what makes loaded code
/// share the editor's engine: one `scene`, one registry. A packaged editor ships them in
/// `Contents/Resources/ComponentSDK`; an editor run from source finds them in the build
/// directory next to its executable.
struct ComponentSDK: Equatable {
    /// `sdk.json` of a packaged SDK.
    struct Manifest: Codable, Equatable {
        var swiftCompilerVersion: String
        /// Where the engine package lives; with `engineRevision`, what new projects pin.
        var engineURL: String?
        var engineRevision: String?
        var target: String
        var languageMode: String
        var providedModules: [String]
        /// The C modules shipped beside `Modules`, each a folder of headers with a
        /// `module.modulemap`. An SDK packaged before the list existed has CShaderTypes alone.
        var cModules: [String]?
    }

    static let bundleDirectoryName = "ComponentSDK"
    static let manifestFileName = "sdk.json"
    /// A development app bundle (`scripts/dev-app.sh`) links the build products it wraps here,
    /// beside its resources: its executable is a copy that sits apart from them.
    static let buildProductsLinkName = "BuildProducts"
    /// The engine's own C module: every SDK has it.
    static let cShaderTypesModule = "CShaderTypes"

    let modulesDirectory: URL
    /// The module map of every C module the modules in `modulesDirectory` import: CShaderTypes
    /// first, then any other the engine was built with. The compiler does not find these by
    /// itself, and cannot import `UntoldEngine` without them.
    let cModuleMaps: [URL]
    /// C targets the editor was built with whose module map was not found. Always empty for a
    /// packaged editor, where the packaging check has compiled against the SDK.
    let cModulesWithoutModuleMap: [String]
    /// Modules the editor itself links, which a plugin must therefore never bring a second copy of.
    let providedModules: [String]
    let targetTriple: String
    /// The compiler that built the editor. `nil` for a source build, where the same toolchain
    /// builds both and the check is moot.
    let recordedCompilerVersion: String?
    let engineURL: String?
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
        if let products = developmentBuildProducts(resourceURL: resourceURL, fileManager: fileManager) {
            return resolveFromBuildProducts(productsDirectory: products, fileManager: fileManager)
        }
        guard let executableURL else { return nil }
        // `.build/debug` is a symlink; the module maps are found relative to the real directory.
        let products = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
        return resolveFromBuildProducts(productsDirectory: products, fileManager: fileManager)
    }

    /// The build products a development app bundle wraps, from the link beside its resources;
    /// nil for a packaged app and for an executable run from the build folder.
    static func developmentBuildProducts(resourceURL: URL?, fileManager: FileManager = .default) -> URL? {
        guard let link = resourceURL?.appendingPathComponent(buildProductsLinkName, isDirectory: true) else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: link.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return link.resolvingSymlinksInPath()
    }

    static func resolveBundled(at sdkRoot: URL, fileManager: FileManager = .default) -> ComponentSDK? {
        let modules = sdkRoot.appendingPathComponent("Modules", isDirectory: true)
        let manifestURL = sdkRoot.appendingPathComponent(manifestFileName)
        guard hasRequiredModules(in: modules, fileManager: fileManager),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        let moduleMaps = (manifest.cModules ?? [cShaderTypesModule])
            .map { sdkRoot.appendingPathComponent("\($0)/module.modulemap") }
        guard moduleMaps.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else { return nil }

        return ComponentSDK(
            modulesDirectory: modules,
            cModuleMaps: moduleMaps,
            cModulesWithoutModuleMap: [],
            providedModules: manifest.providedModules,
            targetTriple: manifest.target,
            recordedCompilerVersion: manifest.swiftCompilerVersion,
            engineURL: manifest.engineURL,
            engineRevision: manifest.engineRevision,
            isBundled: true
        )
    }

    /// SwiftPM has two layouts, and Xcode's matches the newer one: modules beside the products
    /// with generated module maps under `Intermediates.noindex`, or modules in `Modules/` with
    /// the module map in `CShaderTypes.build/`.
    static func resolveFromBuildProducts(productsDirectory: URL, fileManager: FileManager = .default) -> ComponentSDK? {
        let moduleCandidates = [productsDirectory, productsDirectory.appendingPathComponent("Modules", isDirectory: true)]
        guard let modules = moduleCandidates.first(where: { hasRequiredModules(in: $0, fileManager: fileManager) }),
              let layout = ComponentSDKBuildLayout.allCases.first(where: {
                  let moduleMap = $0.generatedModuleMap(of: cShaderTypesModule, productsDirectory: productsDirectory)
                  return fileManager.fileExists(atPath: moduleMap.path)
              })
        else { return nil }
        let swiftModules = moduleNames(in: modules, fileManager: fileManager)
        let cModules = layout.cModules(productsDirectory: productsDirectory, swiftModules: swiftModules, fileManager: fileManager)

        return ComponentSDK(
            modulesDirectory: modules,
            cModuleMaps: cModules.moduleMaps,
            cModulesWithoutModuleMap: cModules.withoutModuleMap,
            providedModules: swiftModules,
            targetTriple: defaultTargetTriple,
            recordedCompilerVersion: nil,
            engineURL: nil,
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
