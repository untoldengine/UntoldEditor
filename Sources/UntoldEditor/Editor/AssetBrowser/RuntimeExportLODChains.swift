//
//  RuntimeExportLODChains.swift
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
import UntoldEngineMeshCook

/// The `.untoldpack` manifest a cook writes beside its `.untold` output when the source holds
/// more than one model, or nil when the cook wrote a single model.
func exportedPackManifest(besideOutput outputURL: URL, fileManager: FileManager = .default) -> URL? {
    let packURL = outputURL.deletingPathExtension().appendingPathExtension("untoldpack")
    return fileManager.fileExists(atPath: packURL.path) ? packURL : nil
}

/// Builds the LOD chains of the pack a cook wrote, as `untoldengine export` does: simplified
/// copies of every model big enough for them, recorded in the manifest, so that a large scene
/// draws its far placements with fewer triangles. Returns the Console lines about it.
///
/// A pack whose chains cannot be built keeps working without them, so a failure here is a
/// warning, not a failed cook: its line is how the task comes to point at the Console.
/// `progress` is called after each model, from any thread, with the number done and the total.
func buildExportedLODChains(forPackAt packURL: URL, progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void) -> [ToolOutputLine] {
    #if DEBUG
        DispatchQueue.main.async {
            Logger.log(message: "Building the LOD chains of \(packURL.lastPathComponent) in a debug build of the editor: a large pack takes minutes (a release build, or `untoldengine bake-lods`, is many times faster)")
        }
    #endif
    do {
        let report = try UntoldMeshLODCooker.cookChains(forPackAt: packURL, progress: progress)
        return lodChainLines(
            packName: packURL.lastPathComponent,
            modelCount: report.modelCount,
            chainCount: report.chainCount,
            levelCount: report.levelCount,
            levelBytes: report.levelBytes,
            blockedPaths: report.blockedPaths,
            failures: report.failures.map { (path: $0.path, reason: $0.reason) }
        )
    } catch {
        return [ToolOutputLine(level: .warning, text: "⚠️ The LOD chains of \(packURL.lastPathComponent) were not built: \(error)")]
    }
}

/// The Console lines of a pack's LOD chains: what was built, and a warning for each model
/// that was left without a chain by something other than its size.
func lodChainLines(
    packName: String,
    modelCount: Int,
    chainCount: Int,
    levelCount: Int,
    levelBytes: Int64,
    blockedPaths: [String],
    failures: [(path: String, reason: String)]
) -> [ToolOutputLine] {
    var lines: [ToolOutputLine] = []
    if modelCount == 0 {
        lines.append(ToolOutputLine(level: .info, text: "LOD chains of \(packName): the pack places no model"))
    } else if chainCount == 0 {
        lines.append(ToolOutputLine(level: .info, text: "LOD chains of \(packName): none of its \(modelCount) models is big enough for one"))
    } else {
        lines.append(ToolOutputLine(level: .info, text: "LOD chains of \(packName): \(chainCount) of \(modelCount) models, \(levelCount) level files, \(levelSize(levelBytes))"))
    }
    for path in blockedPaths {
        lines.append(ToolOutputLine(level: .warning, text: "⚠️ \(path): no LOD chain, a file that is not one of its levels has a level's name"))
    }
    for failure in failures {
        lines.append(ToolOutputLine(level: .warning, text: "⚠️ \(failure.path): no LOD chain, \(failure.reason)"))
    }
    return lines
}

private func levelSize(_ bytes: Int64) -> String {
    if bytes >= 1_048_576 {
        return "\(Int((Double(bytes) / 1_048_576).rounded())) MB"
    }
    return "\(Int((Double(bytes) / 1024).rounded())) KB"
}
