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
import UntoldEngine

/// `<ProjectRoot>/UntoldEditor.json`. Optional: without it the editor compiles the project's
/// plugins folder, `Sources/<Project>Plugins`, and no plugin packages.
///
/// Two places hold plugins, and the words are kept apart on purpose. The *plugins folder* is
/// the project's own: part of the app, like an application-local extension. A *plugin package*
/// is a Swift package of its own that several projects share, listed here so the editor
/// compiles and loads it too. Either can hold component, entity and editor menu plugins.
struct EditorProjectManifest: Codable, Equatable {
    static let fileName = "UntoldEditor.json"

    struct PluginPackage: Codable, Equatable {
        /// Path to the plugin package, absolute or relative to the project root.
        var path: String
    }

    /// The project's plugins folder, relative to the project root, when it is not the default.
    var pluginsFolder: String?
    /// The plugin packages the project uses.
    var pluginPackages: [PluginPackage]?
    /// Keys from before the rename that the file still uses. They are honored, and reported
    /// so the file gets updated.
    var legacyKeys: [String] = []

    init(pluginsFolder: String? = nil, pluginPackages: [PluginPackage]? = nil) {
        self.pluginsFolder = pluginsFolder
        self.pluginPackages = pluginPackages
    }

    private enum CodingKeys: String, CodingKey {
        case pluginsFolder
        case pluginPackages
        // Before the rename.
        case components
        case plugins
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pluginsFolder = try container.decodeIfPresent(String.self, forKey: .pluginsFolder)
        pluginPackages = try container.decodeIfPresent([PluginPackage].self, forKey: .pluginPackages)
        if pluginsFolder == nil, let legacy = try container.decodeIfPresent(String.self, forKey: .components) {
            pluginsFolder = legacy
            legacyKeys.append("\"components\" is now \"pluginsFolder\"")
        }
        if pluginPackages == nil, let legacy = try container.decodeIfPresent([PluginPackage].self, forKey: .plugins) {
            pluginPackages = legacy
            legacyKeys.append("\"plugins\" is now \"pluginPackages\"")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(pluginsFolder, forKey: .pluginsFolder)
        try container.encodeIfPresent(pluginPackages, forKey: .pluginPackages)
    }
}

/// `<PackageRoot>/untold-package.json`: what the editor needs to know about a plugin package.
/// `Package.swift`, next to it, is what games depend on.
struct PluginPackageManifest: Codable, Equatable {
    static let fileName = "untold-package.json"
    /// What the file was called before the rename; still read, and reported.
    static let legacyFileName = "untold-plugin.json"

    var id: String
    /// The module name games import, e.g. `UntoldGaussianTwins`.
    var module: String
    /// The package's runtime sources, relative to the package root. Compiled by the editor only
    /// when the editor does not already link `module`.
    var runtimeSources: String?
    /// Editor-only sources (menu plugins), relative to the package root.
    var editorSources: String?
}

/// One folder of Swift sources compiled into one library.
struct ComponentSourceUnit: Equatable {
    enum Role: String, Equatable {
        /// A plugin package's runtime, loaded globally so later units resolve its symbols.
        case packageRuntime
        /// A plugin package's editor-only sources.
        case packageEditor
        /// The project's own plugins folder.
        case project
    }

    let role: Role
    /// A valid Swift identifier; the real module name appends `_r<revision>`.
    let moduleBaseName: String
    let directory: URL
    let sources: [URL]
    /// Plugin package runtimes built in the same pass that this unit may `import` by their
    /// stable names; each is mapped to its revisioned module with `-module-alias`.
    let reloadableImports: [String]
}

struct ComponentProjectLayout: Equatable {
    let projectRoot: URL
    let projectName: String
    /// The project's own plugins folder.
    let pluginsDirectory: URL
    /// In build order: package runtimes, package editor sources, then the project's folder.
    let units: [ComponentSourceUnit]
    /// Manifest and plugin package problems, shown in the Plugins panel.
    let problems: [String]

    var pluginsDirectoryExists: Bool {
        FileManager.default.fileExists(atPath: pluginsDirectory.path)
    }

    var watchedDirectories: [URL] {
        var directories = units.map(\.directory)
        if directories.contains(pluginsDirectory) == false {
            directories.append(pluginsDirectory)
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

        for legacyKey in manifest?.legacyKeys ?? [] {
            problems.append("\(EditorProjectManifest.fileName) uses an old key: \(legacyKey).")
        }

        let pluginsDirectory: URL
        if let custom = manifest?.pluginsFolder, custom.isEmpty == false {
            pluginsDirectory = resolve(custom, relativeTo: root)
        } else {
            let current = root.appendingPathComponent("Sources/\(BuildSystem.pluginsFolderName(forProject: projectName))", isDirectory: true)
            let legacyName = BuildSystem.legacyPluginsFolderName(forProject: projectName)
            let legacy = root.appendingPathComponent("Sources/\(legacyName)", isDirectory: true)
            // A project made before the folder was renamed keeps working, and says so.
            if fileManager.fileExists(atPath: current.path) == false, fileManager.fileExists(atPath: legacy.path) {
                pluginsDirectory = legacy
                problems.append("The plugins folder is still called \(legacyName). Rename it to \(current.lastPathComponent), in project.yml too if it is listed there.")
            } else {
                pluginsDirectory = current
            }
        }

        var runtimeUnits: [ComponentSourceUnit] = []
        var editorUnits: [ComponentSourceUnit] = []
        for package in manifest?.pluginPackages ?? [] {
            let pluginRoot = resolve(package.path, relativeTo: root)
            var pluginManifestURL = pluginRoot.appendingPathComponent(PluginPackageManifest.fileName)
            if fileManager.fileExists(atPath: pluginManifestURL.path) == false {
                let legacyURL = pluginRoot.appendingPathComponent(PluginPackageManifest.legacyFileName)
                if fileManager.fileExists(atPath: legacyURL.path) {
                    pluginManifestURL = legacyURL
                    problems.append("Plugin package at \(package.path): \(PluginPackageManifest.legacyFileName) is now \(PluginPackageManifest.fileName).")
                }
            }
            guard let data = try? Data(contentsOf: pluginManifestURL),
                  let pluginManifest = try? JSONDecoder().decode(PluginPackageManifest.self, from: data)
            else {
                problems.append("Plugin package at \(package.path): no readable \(PluginPackageManifest.fileName).")
                continue
            }

            let module = moduleIdentifier(from: pluginManifest.module)
            let editorLinksIt = sdk?.providedModules.contains(pluginManifest.module) ?? false
            var reloadableRuntime: [String] = []

            if editorLinksIt == false, let runtimePath = pluginManifest.runtimeSources {
                let directory = resolve(runtimePath, relativeTo: pluginRoot)
                let sources = swiftSources(in: directory, fileManager: fileManager)
                if sources.isEmpty {
                    problems.append("Plugin package \(pluginManifest.module): no Swift sources in \(runtimePath).")
                } else {
                    runtimeUnits.append(ComponentSourceUnit(role: .packageRuntime, moduleBaseName: module, directory: directory, sources: sources, reloadableImports: []))
                    reloadableRuntime = [module]
                }
            }

            if let editorPath = pluginManifest.editorSources {
                let directory = resolve(editorPath, relativeTo: pluginRoot)
                let sources = swiftSources(in: directory, fileManager: fileManager)
                if sources.isEmpty == false {
                    editorUnits.append(ComponentSourceUnit(role: .packageEditor, moduleBaseName: module + "Editor", directory: directory, sources: sources, reloadableImports: reloadableRuntime))
                }
            }
        }

        var units = runtimeUnits + editorUnits
        let projectSources = swiftSources(in: pluginsDirectory, fileManager: fileManager)
        if projectSources.isEmpty == false {
            units.append(ComponentSourceUnit(
                role: .project,
                moduleBaseName: moduleIdentifier(from: pluginsDirectory.lastPathComponent),
                directory: pluginsDirectory,
                sources: projectSources,
                reloadableImports: runtimeUnits.map(\.moduleBaseName)
            ))
        }

        return ComponentProjectLayout(
            projectRoot: root,
            projectName: projectName,
            pluginsDirectory: pluginsDirectory,
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

    /// `My Game-Plugins` → `My_Game_Plugins`; a leading digit gets an underscore.
    static func moduleIdentifier(from name: String) -> String {
        var identifier = String(name.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII ? Character(scalar) : "_"
        })
        if identifier.isEmpty {
            identifier = "Plugins"
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
