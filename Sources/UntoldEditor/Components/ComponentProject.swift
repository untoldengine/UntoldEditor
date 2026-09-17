//
//  ComponentProject.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// `<ProjectRoot>/UntoldEditor.json`. Optional: without it the editor compiles
/// `Sources/<Project>Components` and no plugins.
struct EditorProjectManifest: Codable, Equatable {
    static let fileName = "UntoldEditor.json"

    struct Plugin: Codable, Equatable {
        /// Path to the plugin package, absolute or relative to the project root.
        var path: String
    }

    /// Components folder, relative to the project root.
    var components: String?
    var plugins: [Plugin]?
}

/// `<PluginRoot>/untold-plugin.json`.
struct PluginManifest: Codable, Equatable {
    static let fileName = "untold-plugin.json"

    var id: String
    /// The module name games import, e.g. `UntoldGaussianTwins`.
    var module: String
    /// The plugin's runtime sources, relative to the plugin root. Compiled by the editor only
    /// when the editor does not already link `module`.
    var runtimeSources: String?
    /// Editor-only sources (extensions, menus), relative to the plugin root.
    var editorSources: String?
}

/// One folder of Swift sources compiled into one library.
struct ComponentSourceUnit: Equatable {
    enum Role: String, Equatable {
        /// A plugin's runtime, loaded globally so later units resolve its symbols.
        case pluginRuntime
        case pluginEditor
        case project
    }

    let role: Role
    /// A valid Swift identifier; the real module name appends `_r<revision>`.
    let moduleBaseName: String
    let directory: URL
    let sources: [URL]
    /// Plugin runtime modules built in the same pass that this unit may `import` by their
    /// stable names; each is mapped to its revisioned module with `-module-alias`.
    let reloadableImports: [String]
}

struct ComponentProjectLayout: Equatable {
    let projectRoot: URL
    let projectName: String
    let componentsDirectory: URL
    /// In build order: plugin runtimes, plugin editor sources, then the project.
    let units: [ComponentSourceUnit]
    /// Manifest and plugin problems, shown in the Components panel.
    let problems: [String]

    var componentsDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: componentsDirectory.path)
    }

    var watchedDirectories: [URL] {
        var directories = units.map(\.directory)
        if directories.contains(componentsDirectory) == false {
            directories.append(componentsDirectory)
        }
        return directories
    }
}

enum ComponentSourceLocator {
    /// The editor's asset folder is `<Root>/Sources/<Project>/GameData`.
    static func projectRoot(forAssetBasePath basePath: URL) -> URL {
        basePath.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func layout(
        forAssetBasePath basePath: URL,
        sdk: ComponentSDK?,
        fileManager: FileManager = .default
    ) -> ComponentProjectLayout {
        let root = projectRoot(forAssetBasePath: basePath)
        let projectName = root.lastPathComponent
        var problems: [String] = []

        var manifest: EditorProjectManifest?
        let manifestURL = root.appendingPathComponent(EditorProjectManifest.fileName)
        if fileManager.fileExists(atPath: manifestURL.path) {
            do {
                manifest = try JSONDecoder().decode(EditorProjectManifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                problems.append("\(EditorProjectManifest.fileName) could not be read: \(error.localizedDescription)")
            }
        }

        let componentsDirectory: URL
        if let custom = manifest?.components, custom.isEmpty == false {
            componentsDirectory = resolve(custom, relativeTo: root)
        } else {
            componentsDirectory = root.appendingPathComponent("Sources/\(projectName)Components", isDirectory: true)
        }

        var runtimeUnits: [ComponentSourceUnit] = []
        var editorUnits: [ComponentSourceUnit] = []
        for plugin in manifest?.plugins ?? [] {
            let pluginRoot = resolve(plugin.path, relativeTo: root)
            let pluginManifestURL = pluginRoot.appendingPathComponent(PluginManifest.fileName)
            guard let data = try? Data(contentsOf: pluginManifestURL),
                  let pluginManifest = try? JSONDecoder().decode(PluginManifest.self, from: data)
            else {
                problems.append("Plugin at \(plugin.path): no readable \(PluginManifest.fileName).")
                continue
            }

            let module = moduleIdentifier(from: pluginManifest.module)
            let editorLinksIt = sdk?.providedModules.contains(pluginManifest.module) ?? false
            var reloadableRuntime: [String] = []

            if editorLinksIt == false, let runtimePath = pluginManifest.runtimeSources {
                let directory = resolve(runtimePath, relativeTo: pluginRoot)
                let sources = swiftSources(in: directory, fileManager: fileManager)
                if sources.isEmpty {
                    problems.append("Plugin \(pluginManifest.module): no Swift sources in \(runtimePath).")
                } else {
                    runtimeUnits.append(ComponentSourceUnit(role: .pluginRuntime, moduleBaseName: module, directory: directory, sources: sources, reloadableImports: []))
                    reloadableRuntime = [module]
                }
            }

            if let editorPath = pluginManifest.editorSources {
                let directory = resolve(editorPath, relativeTo: pluginRoot)
                let sources = swiftSources(in: directory, fileManager: fileManager)
                if sources.isEmpty == false {
                    editorUnits.append(ComponentSourceUnit(role: .pluginEditor, moduleBaseName: module + "Editor", directory: directory, sources: sources, reloadableImports: reloadableRuntime))
                }
            }
        }

        var units = runtimeUnits + editorUnits
        let projectSources = swiftSources(in: componentsDirectory, fileManager: fileManager)
        if projectSources.isEmpty == false {
            units.append(ComponentSourceUnit(
                role: .project,
                moduleBaseName: moduleIdentifier(from: componentsDirectory.lastPathComponent),
                directory: componentsDirectory,
                sources: projectSources,
                reloadableImports: runtimeUnits.map(\.moduleBaseName)
            ))
        }

        return ComponentProjectLayout(
            projectRoot: root,
            projectName: projectName,
            componentsDirectory: componentsDirectory,
            units: units,
            problems: problems
        )
    }

    /// Every `.swift` file under `directory`, sorted so the compiler invocation is stable.
    static func swiftSources(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var sources: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            sources.append(url.standardizedFileURL)
        }
        return sources.sorted { $0.path < $1.path }
    }

    /// `My Game-Components` → `My_Game_Components`; a leading digit gets an underscore.
    static func moduleIdentifier(from name: String) -> String {
        var identifier = String(name.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII ? Character(scalar) : "_"
        })
        if identifier.isEmpty {
            identifier = "Components"
        }
        if let first = identifier.first, first.isNumber {
            identifier = "_" + identifier
        }
        return identifier
    }

    private static func resolve(_ path: String, relativeTo base: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return base.appendingPathComponent(expanded).standardizedFileURL
    }
}
