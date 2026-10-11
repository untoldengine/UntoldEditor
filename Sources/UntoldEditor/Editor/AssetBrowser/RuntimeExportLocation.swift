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

/// The path a URL under `base` would have if `base` were `otherBase` instead --
/// `relativeTo: Resources/Models/Tower/Tower.blend` under `base: Resources/`
/// mirrored `otherBase: GameData/` becomes `GameData/Models/Tower/Tower.blend`.
/// Nil if `url` isn't under `base` at all.
private func mirrored(_ url: URL, from base: URL, to otherBase: URL) -> URL? {
    let basePath = base.standardizedFileURL.path
    let urlPath = url.standardizedFileURL.path
    guard urlPath == basePath || urlPath.hasPrefix(basePath + "/") else { return nil }
    let relative = String(urlPath.dropFirst(basePath.count)).drop { $0 == "/" }
    return relative.isEmpty ? otherBase : otherBase.appendingPathComponent(String(relative))
}

/// Maps a `GameData` URL to its mirrored path under `Resources`, or nil on the legacy
/// layout (no `Resources` to mirror into) or if `url` isn't under `GameData` at all.
func mirroredResourcesPath(for url: URL, assetBasePath: URL) -> URL? {
    let layout = ProjectLayout.detect(gameDataDirectory: assetBasePath)
    guard let resourcesDirectory = layout.resourcesDirectory else { return nil }
    return mirrored(url, from: layout.gameDataDirectory, to: resourcesDirectory)
}

/// Maps a `Resources` URL to its mirrored path under `GameData`, or nil on the legacy
/// layout or if `url` isn't under `Resources` at all.
func mirroredGameDataPath(for url: URL, assetBasePath: URL) -> URL? {
    let layout = ProjectLayout.detect(gameDataDirectory: assetBasePath)
    guard let resourcesDirectory = layout.resourcesDirectory else { return nil }
    return mirrored(url, from: resourcesDirectory, to: layout.gameDataDirectory)
}

/// Where a source import should actually land: `url` unchanged if it's already under
/// `Resources` (the user is browsing there and importing directly into it) or outside
/// both trees (legacy layout), otherwise its mirrored path under `Resources` (the user
/// is browsing `GameData`, e.g. a category root, and importing there as before --
/// `AssetBrowserView+Import.swift` redirects it into `Resources` instead).
func resourcesImportDestination(for url: URL, assetBasePath: URL) -> URL {
    if mirroredGameDataPath(for: url, assetBasePath: assetBasePath) != nil {
        return url
    }
    return mirroredResourcesPath(for: url, assetBasePath: assetBasePath) ?? url
}

/// A source imported by the editor sits in a folder named after it
/// (`Resources/Models/Tower/Tower.blend`, see `importSourceAsset`). Its result goes in
/// the mirrored folder under `GameData` (`GameData/Models/Tower.untoldpack`), and
/// everything the result references stays in the mirrored per-asset folder
/// (`GameData/Models/Tower/`). A source outside `Resources` -- a legacy-layout project,
/// or one dropped in from outside the project entirely -- is cooked beside itself, same
/// as before this split existed.
func runtimeExportLocation(for sourceURL: URL, assetBasePath: URL?) -> RuntimeExportLocation {
    let mirroredSource = assetBasePath.flatMap { mirroredGameDataPath(for: sourceURL, assetBasePath: $0) }
    let effectiveSource = mirroredSource ?? sourceURL

    let sourceFolder = effectiveSource.deletingLastPathComponent()
    let stem = effectiveSource.deletingPathExtension().lastPathComponent
    guard sourceFolder.lastPathComponent == stem else {
        return RuntimeExportLocation(outputFolder: sourceFolder, assetsFolder: nil)
    }
    return RuntimeExportLocation(outputFolder: sourceFolder.deletingLastPathComponent(), assetsFolder: sourceFolder)
}

/// The folder holding a cooked asset's actual source, given it would sit beside the
/// asset as a same-named folder (`categoryFolder/<stem>/`). Prefers the mirrored
/// `Resources/` folder when the project is on the root-level layout and it exists
/// there (that's where import puts sources now, see `AssetBrowserView+Import.swift`);
/// falls back to the legacy same-folder location, for a project not yet converted or
/// a source otherwise left beside its cooked output. Nil if neither exists.
func sourceFolderCandidate(stem: String, in categoryFolder: URL, assetBasePath: URL?, fileManager fm: FileManager = .default) -> URL? {
    func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url
    }

    let legacyCandidate = categoryFolder.appendingPathComponent(stem, isDirectory: true)
    if let assetBasePath,
       let mirroredCandidate = mirroredResourcesPath(for: legacyCandidate, assetBasePath: assetBasePath),
       let found = existingDirectory(mirroredCandidate)
    {
        return found
    }
    return existingDirectory(legacyCandidate)
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
