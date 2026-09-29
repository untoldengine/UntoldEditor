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

/// Where a cook writes its result (the `.untold`, `.untoldpack` or `.untoldanim`) and
/// the files that result references (textures, per-model folders).
struct RuntimeExportLocation: Equatable {
    /// The folder the result file goes in.
    let outputFolder: URL
    /// The folder for the files the result references, or nil to keep them beside it.
    let assetsFolder: URL?
}

/// A source imported by the editor sits in a folder named after it
/// (`Models/Tower/Tower.blend`, see `importSourceAsset`). Its result goes in the folder
/// the user imported into (`Models/Tower.untoldpack`), and everything the result
/// references stays in the source's folder with the source. Any other source is
/// cooked beside itself.
func runtimeExportLocation(for sourceURL: URL) -> RuntimeExportLocation {
    let sourceFolder = sourceURL.deletingLastPathComponent()
    let stem = sourceURL.deletingPathExtension().lastPathComponent
    guard sourceFolder.lastPathComponent == stem else {
        return RuntimeExportLocation(outputFolder: sourceFolder, assetsFolder: nil)
    }
    return RuntimeExportLocation(outputFolder: sourceFolder.deletingLastPathComponent(), assetsFolder: sourceFolder)
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
