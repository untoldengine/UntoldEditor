//
//  ComponentSDKBuildLayout.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// How the build of an editor run from source laid out its folder, and with it the C modules
/// that build has.
///
/// The engine is built without library evolution, so a component that imports `UntoldEngine`
/// makes the compiler load every module the engine imports. A Swift module it finds by itself in
/// the modules folder. A C module it does not: CShaderTypes, a C target the engine adds, or one
/// that comes with a package the engine depends on each need their module map on the command
/// line, as the build system passed it when it built the editor.
enum ComponentSDKBuildLayout: CaseIterable {
    /// Swift Build, which Xcode uses too: a `<Target>.o` beside the products for every target,
    /// and the module maps it generates together under `Intermediates.noindex`.
    case swiftBuild
    /// SwiftPM's native build system: a `<Target>.build` folder beside the products for every
    /// target, with the target's objects and the module map generated for it.
    case native

    /// The C modules of a build.
    struct CModules: Equatable {
        /// The module map of every C target that was built with the editor, CShaderTypes first.
        var moduleMaps: [URL]
        /// The targets that were built with the editor and whose module map was not found.
        var withoutModuleMap: [String] = []
    }

    /// Where the build system writes the module map of a C target that has none of its own.
    func generatedModuleMap(of target: String, productsDirectory: URL) -> URL {
        switch self {
        case .swiftBuild:
            return productsDirectory
                .appendingPathComponent("../../Intermediates.noindex/GeneratedModuleMaps/\(target).modulemap")
                .standardizedFileURL
        case .native:
            return productsDirectory.appendingPathComponent("\(target).build/module.modulemap")
        }
    }

    /// The C targets that were built with the editor, with the module map of each.
    ///
    /// Only what was compiled counts, told by the objects it left: the native build system also
    /// writes a module map for a target the package declares and the editor does not use. And
    /// only what is still in its package: a build folder keeps the objects and the module map of
    /// a target that is gone, and the compiler warns about such a module map in every build.
    func cModules(productsDirectory: URL, swiftModules: [String], fileManager: FileManager = .default) -> CModules {
        let cShaderTypes = ComponentSDK.cShaderTypesModule
        var modules = CModules(moduleMaps: [generatedModuleMap(of: cShaderTypes, productsDirectory: productsDirectory)])
        // Searched only for a target that brings its own module map.
        var packages: [URL]?
        for target in builtTargets(productsDirectory: productsDirectory, except: swiftModules + [cShaderTypes], fileManager: fileManager) {
            let generated = generatedModuleMap(of: target, productsDirectory: productsDirectory)
            if fileManager.fileExists(atPath: generated.path) {
                if Self.headersExist(ofGeneratedModuleMap: generated, fileManager: fileManager) {
                    modules.moduleMaps.append(generated)
                }
                continue
            }
            let searched = packages ?? packageDirectories(productsDirectory: productsDirectory, fileManager: fileManager)
            packages = searched
            if let own = Self.ownModuleMap(of: target, inPackages: searched, fileManager: fileManager) {
                modules.moduleMaps.append(own)
            } else {
                modules.withoutModuleMap.append(target)
            }
        }
        return modules
    }

    /// The targets that left objects in this build, without the ones in `excluded`.
    func builtTargets(productsDirectory: URL, except excluded: [String], fileManager: FileManager = .default) -> [String] {
        let entries = (try? fileManager.contentsOfDirectory(atPath: productsDirectory.path)) ?? []
        let suffix = self == .swiftBuild ? ".o" : ".build"
        let targets = entries
            .filter { $0.hasSuffix(suffix) }
            .map { String($0.dropLast(suffix.count)) }
            .filter { excluded.contains($0) == false }
            .sorted()
        guard self == .native else { return targets }
        return targets.filter { target in
            let folder = productsDirectory.appendingPathComponent("\(target).build", isDirectory: true)
            guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil) else { return false }
            return enumerator.contains { ($0 as? URL)?.pathExtension == "o" }
        }
    }

    /// A generated module map names the target's headers, a folder or one header, by absolute
    /// path.
    static func headersExist(ofGeneratedModuleMap moduleMap: URL, fileManager: FileManager = .default) -> Bool {
        guard let text = try? String(contentsOf: moduleMap, encoding: .utf8),
              let umbrella = try? NSRegularExpression(pattern: #"umbrella\s+(?:header\s+)?"([^"]+)""#)
        else { return false }
        return umbrella.matches(in: text, range: NSRange(text.startIndex..., in: text)).allSatisfy { match in
            guard let path = Range(match.range(at: 1), in: text) else { return true }
            return fileManager.fileExists(atPath: String(text[path]))
        }
    }

    /// The folders of the packages the build was made from.
    ///
    /// SwiftPM clones them into `checkouts` of its scratch folder, Xcode into
    /// `SourcePackages/checkouts` of its derived data folder. A package used by path stays where
    /// it is. The `workspace-state.json` beside `checkouts` is SwiftPM's record of both, and
    /// leaves out a clone the build no longer uses; without it, every clone counts.
    func packageDirectories(productsDirectory: URL, fileManager: FileManager = .default) -> [URL] {
        let twoUp = productsDirectory.appendingPathComponent("../..").standardizedFileURL
        let workspaces: [URL]
        switch self {
        case .swiftBuild:
            // `<scratch>/out/Products/<Configuration>`, or `<DerivedData>/Build/Products/<Configuration>`.
            let root = twoUp.deletingLastPathComponent()
            workspaces = [root, root.appendingPathComponent("SourcePackages", isDirectory: true)]
        case .native:
            // `<scratch>/<triple>/<configuration>`.
            workspaces = [twoUp]
        }

        return workspaces.flatMap { workspace -> [URL] in
            let checkouts = workspace.appendingPathComponent("checkouts", isDirectory: true)
            if let recorded = Self.recordedPackages(workspaceState: workspace.appendingPathComponent("workspace-state.json"), checkouts: checkouts) {
                return recorded
            }
            let cloned = (try? fileManager.contentsOfDirectory(atPath: checkouts.path)) ?? []
            return cloned.filter { $0.hasPrefix(".") == false }.sorted().map { checkouts.appendingPathComponent($0, isDirectory: true) }
        }
    }

    /// The packages `workspace-state.json` lists: a cloned one in `checkouts`, one used by path
    /// where it is. `nil` when the file is not there or is not one this code can read.
    private static func recordedPackages(workspaceState: URL, checkouts: URL) -> [URL]? {
        struct State: Decodable {
            struct Object: Decodable {
                struct Dependency: Decodable {
                    struct PackageRef: Decodable {
                        let kind: String
                        let location: String
                    }

                    let packageRef: PackageRef
                    let subpath: String
                }

                let dependencies: [Dependency]
            }

            let object: Object
        }
        guard let data = try? Data(contentsOf: workspaceState),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return nil }
        return state.object.dependencies.map { dependency in
            dependency.packageRef.kind == "fileSystem"
                ? URL(fileURLWithPath: dependency.packageRef.location, isDirectory: true)
                : checkouts.appendingPathComponent(dependency.subpath, isDirectory: true)
        }
    }

    /// The `module.modulemap` a C target brings itself, which the build system then uses as it
    /// is: in the target's `include` folder by default, somewhere else in its package when the
    /// target says so.
    static func ownModuleMap(of module: String, inPackages packages: [URL], fileManager: FileManager = .default) -> URL? {
        for package in packages {
            let conventional = package.appendingPathComponent("Sources/\(module)/include/module.modulemap")
            if moduleMap(at: conventional, declares: module) {
                return conventional
            }
        }
        for package in packages {
            guard let enumerator = fileManager.enumerator(atPath: package.path) else { continue }
            var declaring: [String] = []
            while let path = enumerator.nextObject() as? String {
                let name = (path as NSString).lastPathComponent
                if name.hasPrefix(".") {
                    // `.build`, `.git`: nothing of the package's own.
                    enumerator.skipDescendants()
                } else if name == "module.modulemap", moduleMap(at: package.appendingPathComponent(path), declares: module) {
                    declaring.append(path)
                }
            }
            // A copy kept deeper in the package (a benchmark, a fixture) is not the target's.
            let nearest = declaring.min { ($0.components(separatedBy: "/").count, $0) < ($1.components(separatedBy: "/").count, $1) }
            if let nearest {
                return package.appendingPathComponent(nearest)
            }
        }
        return nil
    }

    static func moduleMap(at url: URL, declares module: String) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return topLevelModules(inModuleMap: text).contains(module)
    }

    /// The modules a module map declares itself: `framework module A { module B {} }` declares A,
    /// and B only as a part of it.
    static func topLevelModules(inModuleMap text: String) -> [String] {
        // A comment, a string, a word or a brace. Comments and strings are matched so that what
        // is inside them is not read as a word or a brace.
        let pattern = #"//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_]*|[{}]"#
        guard let tokens = try? NSRegularExpression(pattern: pattern) else { return [] }
        var modules: [String] = []
        var depth = 0
        var nameFollows = false
        for match in tokens.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            switch token.first {
            case "/":
                continue
            case "{":
                depth += 1
                nameFollows = false
            case "}":
                depth -= 1
            default:
                if nameFollows {
                    nameFollows = false
                    if depth == 0 {
                        modules.append(token.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                    }
                } else if token == "module" {
                    nameFollows = true
                }
            }
        }
        return modules
    }
}
