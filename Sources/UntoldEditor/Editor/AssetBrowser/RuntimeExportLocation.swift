//
//  RuntimeExportLocation.swift
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

/// Where a cook writes its result (the `.untold`, `.untoldpack` or `.untoldanim`) and
/// the files that result references (textures, per-model folders).
struct RuntimeExportLocation: Equatable {
    /// The folder the result file goes in.
    let outputFolder: URL
    /// The folder for the files the result references, or nil to keep them beside it.
    let assetsFolder: URL?
}

/// Whether `url` sits anywhere under the project's `Resources/` folder.
func isUnderResources(_ url: URL, assetBasePath: URL) -> Bool {
    guard let resourcesDirectory = ProjectLayout.detect(gameDataDirectory: assetBasePath).resourcesDirectory else {
        return false
    }
    let resourcesPath = resourcesDirectory.standardizedFileURL.path
    let urlPath = url.standardizedFileURL.path
    return urlPath == resourcesPath || urlPath.hasPrefix(resourcesPath + "/")
}

/// Where a source import should land: wherever the user is already browsing, if that's
/// inside `Resources/` (Finder-style, preserving whatever subfolder they organized it
/// into); otherwise directly in `Resources/<baseName>/` -- no category segment, since
/// `Resources/` is organized freely, not mirrored to `GameData`'s categories (a source
/// can become a Model, an Animation, or a Tiled Stream Model; the choice is made at
/// cook time, see `runtimeExportLocation`, not at import time). Nil on the legacy
/// layout, which has no `Resources/` folder -- the caller falls back to `GameData`.
func resourcesImportFolder(forBaseName baseName: String, browsing destinationOverride: URL?, assetBasePath: URL) -> URL? {
    guard let resourcesDirectory = ProjectLayout.detect(gameDataDirectory: assetBasePath).resourcesDirectory else {
        return nil
    }
    if let destinationOverride, isUnderResources(destinationOverride, assetBasePath: assetBasePath) {
        return destinationOverride.appendingPathComponent(baseName, isDirectory: true)
    }
    return resourcesDirectory.appendingPathComponent(baseName, isDirectory: true)
}

/// Where a cook of `sourceURL` writes its result, for the category the user chose to
/// cook it as (picked at cook time, not at import time -- see the context menu in
/// `AssetBrowserView+Contents.swift`). A source anywhere under `Resources/` always
/// cooks into `GameData/<category>/`, named after the source, independent of how the
/// user organized `Resources/` -- there is no folder to mirror. A source outside
/// `Resources/` (the legacy layout, or one left beside its cooked output from before
/// this split existed) is cooked beside itself, same as always.
func runtimeExportLocation(for sourceURL: URL, category: AssetCategory, assetBasePath: URL?) -> RuntimeExportLocation {
    let stem = sourceURL.deletingPathExtension().lastPathComponent

    if let assetBasePath, isUnderResources(sourceURL, assetBasePath: assetBasePath) {
        let categoryRoot = assetBasePath.appendingPathComponent(category.rawValue, isDirectory: true)
        return RuntimeExportLocation(outputFolder: categoryRoot, assetsFolder: categoryRoot.appendingPathComponent(stem, isDirectory: true))
    }

    let sourceFolder = sourceURL.deletingLastPathComponent()
    guard sourceFolder.lastPathComponent == stem else {
        return RuntimeExportLocation(outputFolder: sourceFolder, assetsFolder: nil)
    }
    return RuntimeExportLocation(outputFolder: sourceFolder.deletingLastPathComponent(), assetsFolder: sourceFolder)
}

/// Where cooking `sourceURL` as a tiled stream model writes its manifest and tiles:
/// `GameData/StreamModels/<stem>/`, the same rule `runtimeExportLocation` uses for
/// Models/Animations. `queueTilesExport` appends `tile_exports/` to whatever folder
/// this returns.
func tilesExportDestinationFolder(for sourceURL: URL, assetBasePath: URL?) -> URL {
    let stem = sourceURL.deletingPathExtension().lastPathComponent
    if let assetBasePath, isUnderResources(sourceURL, assetBasePath: assetBasePath) {
        return assetBasePath.appendingPathComponent(AssetCategory.streamModels.rawValue, isDirectory: true)
            .appendingPathComponent(stem, isDirectory: true)
    }
    return sourceURL.deletingLastPathComponent()
}

/// The folder holding a cooked asset's actual source. For a `.untoldpack`, reads the
/// manifest's own `sourceAsset` field -- authoritative, works regardless of how
/// `Resources/` is organized. A plain `.untold`/`.untoldanim` carries no such field (no
/// manifest exists for a single-model export), so this falls back to a bounded search
/// under `Resources/` for a folder named after the asset's stem, then the legacy
/// same-folder-in-GameData location. Nil if nothing is found.
func sourceFolderCandidate(for assetURL: URL, assetBasePath: URL?, fileManager fm: FileManager = .default) -> URL? {
    let stem = assetURL.deletingPathExtension().lastPathComponent

    if assetURL.pathExtension.lowercased() == "untoldpack",
       let pack = loadUntoldPack(url: assetURL),
       let resolved = pack.resolvedSourceAssetURL(packURL: assetURL)
    {
        let folder = resolved.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
            return folder
        }
    }

    func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url
    }

    if let assetBasePath,
       let resourcesDirectory = ProjectLayout.detect(gameDataDirectory: assetBasePath).resourcesDirectory,
       let found = findDirectory(named: stem, under: resourcesDirectory, maxDepth: 4, fileManager: fm)
    {
        return found
    }

    return existingDirectory(assetURL.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true))
}

/// The cooked-output sibling folder a runtime asset was exported alongside -- what
/// `runtimeExportLocation` calls `assetsFolder` (e.g. `Tower.untoldpack` <- `Tower/`,
/// holding the per-model folders/textures `copyUntoldPackResources` wrote there). This
/// sits next to the asset itself in `GameData/`, so it is distinct from
/// `sourceFolderCandidate`'s result once a project has split out `Resources/` -- that
/// one resolves to the original import, not this cooked copy. Both need removing when
/// the asset is deleted, or one lingers on disk. Nil if no such folder exists.
func cookedAssetsFolder(for assetURL: URL, fileManager fm: FileManager = .default) -> URL? {
    guard allRuntimeAssetExtensions.contains(assetURL.pathExtension.lowercased()) else { return nil }
    let stem = assetURL.deletingPathExtension().lastPathComponent
    let folder = assetURL.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true)
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }
    return folder
}

/// A bounded breadth-first search for a directory named `name` under `root`, since
/// `Resources/` has no fixed shape to compute a path from directly. Shallow on purpose
/// (`maxDepth` default matches the nesting a category-free, per-asset-folder
/// convention realistically produces) -- a cheap best-effort, not an exhaustive scan.
func findDirectory(named name: String, under root: URL, maxDepth: Int, fileManager fm: FileManager = .default) -> URL? {
    var frontier = [(url: root, depth: 0)]
    while !frontier.isEmpty {
        let (url, depth) = frontier.removeFirst()
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            continue
        }
        for item in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if item.lastPathComponent == name {
                return item
            }
            if depth < maxDepth {
                frontier.append((item, depth + 1))
            }
        }
    }
    return nil
}

/// Whether a script accepts a command-line option, read from its source. The editor
/// runs the engine scripts of whichever engine version it was built against, and an
/// older one rejects options it does not know, which fails the whole cook.
func engineScript(_ scriptURL: URL, acceptsOption option: String) -> Bool {
    guard let source = try? String(contentsOf: scriptURL, encoding: .utf8) else { return false }
    return source.contains("\"\(option)\"")
}

/// The Python exporter that `export-untold` runs, which is where its options are defined.
func exporterPythonScript(besideExportScript exportScriptURL: URL) -> URL {
    exportScriptURL.deletingLastPathComponent().appendingPathComponent("untoldexplorer.py")
}
