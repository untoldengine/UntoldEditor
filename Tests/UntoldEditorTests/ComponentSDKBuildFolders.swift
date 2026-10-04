//
//  ComponentSDKBuildFolders.swift
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

/// Build folders shaped like the ones SwiftPM and Xcode leave, for the tests of what the
/// Component SDK finds in one and of what the bundle script packages from one.
extension ScratchDirectory {
    static let atomicsShimsModuleMap = """
    module _AtomicsShims {
      header "_AtomicsShims.h"
    }
    """

    /// A C target of the engine, in `engine/Sources`, and the module map a build system generates
    /// for it: its headers folder as an umbrella, named by absolute path. CShaderTypes keeps its
    /// headers beside its sources, as the engine's does.
    func generatedModuleMap(ofEngineCTarget target: String) throws -> String {
        var headers = "engine/Sources/\(target)"
        try write("// \(target).c", to: "\(headers)/\(target).c")
        if target != ComponentSDK.cShaderTypesModule {
            headers += "/include"
        }
        try write("// \(target).h", to: "\(headers)/\(target).h")
        return "module \(target) {\numbrella \"\(url.appendingPathComponent(headers).path)\"\nexport *\n}\n"
    }

    /// What a build system generates for a Swift target, for Objective-C to import it.
    private func swiftHeaderModuleMap(_ target: String) -> String {
        "module \(target) {\nheader \"\(target)-Swift.h\"\nexport *\n}\n"
    }

    /// `<root>/out/Products/Debug` as Swift Build leaves it, where `root` is SwiftPM's scratch
    /// folder. `otherCTargets` are built and get no generated module map: they bring their own.
    func makeSwiftBuildProducts(
        root: String = "build",
        products: String = "out/Products/Debug",
        intermediates: String = "out/Intermediates.noindex",
        swiftTargets: [String],
        generatedCTargets: [String],
        otherCTargets: [String] = []
    ) throws -> URL {
        let productsDirectory = try directory("\(root)/\(products)")
        for target in swiftTargets {
            try write("", to: "\(root)/\(products)/\(target).swiftmodule")
            try write(swiftHeaderModuleMap(target), to: "\(root)/\(intermediates)/GeneratedModuleMaps/\(target).modulemap")
        }
        for target in generatedCTargets {
            try write(generatedModuleMap(ofEngineCTarget: target), to: "\(root)/\(intermediates)/GeneratedModuleMaps/\(target).modulemap")
        }
        for target in swiftTargets + generatedCTargets + otherCTargets {
            try write("", to: "\(root)/\(products)/\(target).o")
        }
        // What else sits beside the products.
        try write("", to: "\(root)/\(products)/UntoldEditor")
        _ = try directory("\(root)/\(products)/PackageFrameworks")
        return productsDirectory
    }

    /// `<root>/arm64-apple-macosx/debug` as SwiftPM's native build system leaves it.
    /// `declaredOnlyCTargets` are targets of a package that the editor does not use: they get a
    /// generated module map and are not compiled.
    func makeNativeProducts(
        root: String = "build",
        swiftTargets: [String],
        generatedCTargets: [String],
        otherCTargets: [String] = [],
        declaredOnlyCTargets: [String] = []
    ) throws -> URL {
        let products = "\(root)/arm64-apple-macosx/debug"
        for target in swiftTargets {
            try write("", to: "\(products)/Modules/\(target).swiftmodule")
            try write("", to: "\(products)/\(target).build/Source.swift.o")
            try write(swiftHeaderModuleMap(target), to: "\(products)/\(target).build/include/module.modulemap")
        }
        for target in generatedCTargets {
            try write(generatedModuleMap(ofEngineCTarget: target), to: "\(products)/\(target).build/module.modulemap")
            try write("", to: "\(products)/\(target).build/\(target).c.o")
        }
        for target in otherCTargets {
            try write("", to: "\(products)/\(target).build/src/\(target).c.o")
        }
        for target in declaredOnlyCTargets {
            try write(generatedModuleMap(ofEngineCTarget: target), to: "\(products)/\(target).build/module.modulemap")
        }
        return url.appendingPathComponent(products)
    }

    /// swift-atomics as SwiftPM clones it: a C target with its own module map.
    @discardableResult
    func addAtomicsPackage(at path: String = "build/checkouts/swift-atomics") throws -> URL {
        try write("// _AtomicsShims.h", to: "\(path)/Sources/_AtomicsShims/include/_AtomicsShims.h")
        try write("// _AtomicsShims.c", to: "\(path)/Sources/_AtomicsShims/src/_AtomicsShims.c")
        return try write(Self.atomicsShimsModuleMap, to: "\(path)/Sources/_AtomicsShims/include/module.modulemap")
    }

    /// SwiftPM's record of the packages of a build, in its scratch folder `root`: the engine
    /// cloned from its URL, and each of `packagesUsedByPath` where it is.
    func writeWorkspaceState(root: String = "build", packagesUsedByPath: [String]) throws {
        let cloned = """
        { "basedOn": null, "subpath": "UntoldEngine",
          "packageRef": { "identity": "untoldengine", "kind": "remoteSourceControl", "location": "https://github.com/untoldengine/UntoldEngine.git", "name": "UntoldEngine" },
          "state": { "name": "sourceControlCheckout", "checkoutState": { "branch": "develop", "revision": "abc" } } }
        """
        let byPath = packagesUsedByPath.map { path -> String in
            let location = url.appendingPathComponent(path).path
            let name = (path as NSString).lastPathComponent
            return """
            { "basedOn": null, "subpath": "\(name)",
              "packageRef": { "identity": "\(name)", "kind": "fileSystem", "location": "\(location)", "name": "\(name)" },
              "state": { "name": "fileSystem", "path": "\(location)" } }
            """
        }
        let dependencies = ([cloned] + byPath).joined(separator: ",\n")
        try write("{ \"version\": 7, \"object\": { \"artifacts\": [], \"dependencies\": [\n\(dependencies)\n] } }\n", to: "\(root)/workspace-state.json")
    }
}
