//
//  GaussianCook.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UntoldEngine

/// Translation that moves a capture's bounding box, after `transform` has been applied to
/// it, where `mode` says. The box is transformed corner by corner so a flip or scale is
/// accounted for before the offset is measured.
func gaussianRecenterTranslation(
    boundsMin: simd_float3,
    boundsMax: simd_float3,
    transform: simd_float4x4,
    mode: GaussianRecenterMode
) -> simd_float3 {
    var transformedMin = simd_float3(repeating: .greatestFiniteMagnitude)
    var transformedMax = simd_float3(repeating: -.greatestFiniteMagnitude)
    for corner in 0 ..< 8 {
        let source = simd_float3(
            corner & 1 == 0 ? boundsMin.x : boundsMax.x,
            corner & 2 == 0 ? boundsMin.y : boundsMax.y,
            corner & 4 == 0 ? boundsMin.z : boundsMax.z
        )
        let moved = simd_mul(transform, simd_float4(source, 1))
        let point = simd_float3(moved.x, moved.y, moved.z)
        transformedMin = simd_min(transformedMin, point)
        transformedMax = simd_max(transformedMax, point)
    }
    let centre = (transformedMin + transformedMax) / 2
    switch mode {
    case .baseOnGround:
        return -simd_float3(centre.x, transformedMin.y, centre.z)
    case .centreAtOrigin:
        return -centre
    }
}

/// Bounds of the splat centres in a source `.ply` or `.spz`, in capture space. A `.ply` is
/// measured in one streamed pass over the positions (`PLYReader.readGaussianCenterBounds`)
/// with nothing resident but the running box, so a recentred cook of a multi-gigabyte capture
/// costs a second read of the file and no memory. A `.spz` has no streamed reader: it is
/// decoded whole (`SPZReader.readGaussianAsset`, as the bake decodes it again) and the box
/// is taken over the decoded centres. The bake's own `centerBounds` cannot serve either way:
/// they are of the cooked splats, and the recenter translation has to be in the transform
/// before the cook.
func gaussianSourceBounds(plyURL: URL) throws -> (min: simd_float3, max: simd_float3) {
    if plyURL.pathExtension.lowercased() == "spz" {
        let splats = try SPZReader.readGaussianAsset(from: plyURL).splats
        guard let first = splats.first else {
            throw UntoldGSError.sizeMismatch("source .spz contains no splats")
        }
        var boundsMin = simd_float3(first.center.x, first.center.y, first.center.z)
        var boundsMax = boundsMin
        for splat in splats.dropFirst() {
            let centre = simd_float3(splat.center.x, splat.center.y, splat.center.z)
            boundsMin = simd_min(boundsMin, centre)
            boundsMax = simd_max(boundsMax, centre)
        }
        return (boundsMin, boundsMax)
    }
    guard let bounds = try PLYReader.readGaussianCenterBounds(from: plyURL) else {
        throw UntoldGSError.sizeMismatch("source .ply contains no splats")
    }
    return bounds
}

/// Writes `<name>.untoldgs` (or `<name>_lodN.untoldgs` tiers) beside `plyURL` (a `.ply` or
/// `.spz` source), or inside `outputDirectory` when the editor is organizing the asset as a
/// folder package. A recentred cook reads the source bounds first and bakes the offset into
/// the transform. `control` follows and stops the bake (`UntoldGSCookControl`): it is
/// polled before and after the bounds read, then the engine reports its phase and fraction
/// through it and polls its cancellation between windows and chunk batches (a `.spz` is
/// decoded whole, so its read reports once and the polling starts with the cook); a
/// cancelled bake throws `UntoldGSCookError.cancelled` with nothing written, its tiers
/// staged in temporary files until the last one is complete.
func cookGaussianPLY(
    plyURL: URL,
    settings: GaussianCookSettings,
    outputDirectory: URL? = nil,
    control: UntoldGSCookControl? = nil
) throws -> GaussianProgressiveBakeResult {
    if let outputDirectory {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }
    let outputBaseURL = outputDirectory?
        .appendingPathComponent(plyURL.deletingPathExtension().lastPathComponent)
        .appendingPathExtension("untoldgs")
        ?? plyURL.deletingPathExtension().appendingPathExtension("untoldgs")
    try control?.checkCancelled()
    let bounds = settings.recenter ? try gaussianSourceBounds(plyURL: plyURL) : nil
    // The bounds pass is the whole streamed `.ply` (or a whole `.spz` decode) with no poll of
    // its own, and the engine's first poll comes with its first report -- past a second whole
    // decode for a `.spz`. A cancel that arrived meanwhile stops here instead.
    try control?.checkCancelled()
    let cookOptions = settings.cookOptions(recenteringBounds: bounds)
    let levelCount = max(1, settings.levelCount)
    if plyURL.pathExtension.lowercased() == "spz" {
        return try bakeGaussianSplatProgressiveTiers(
            spzURL: plyURL,
            outputBaseURL: outputBaseURL,
            levelCount: levelCount,
            cookOptions: cookOptions,
            control: control
        )
    }
    return try bakeGaussianSplatProgressiveTiers(
        plyURL: plyURL,
        outputBaseURL: outputBaseURL,
        levelCount: levelCount,
        cookOptions: cookOptions,
        control: control
    )
}

/// Bakes run one at a time: the engine baker saturates the cores on its own, and an
/// import batch of several `.ply` files should queue up rather than contend.
let gaussianCookQueue = DispatchQueue(label: "com.untoldengine.editor.gaussian-cook", qos: .userInitiated)

/// The files an import batch should cook: `.ply` or `.spz` sources. Baked `.untoldgs` files
/// are imported as they are.
func gaussianSourcesToCook(in urls: [URL]) -> [URL] {
    urls.filter { ["ply", "spz"].contains($0.pathExtension.lowercased()) }
}

func gaussianPackageName(for sourceURL: URL) -> String {
    let stem = sourceURL.deletingPathExtension().lastPathComponent
    guard sourceURL.pathExtension.lowercased() == "untoldgs",
          let range = stem.range(of: #"_lod\d+$"#, options: .regularExpression)
    else {
        return stem
    }
    return String(stem[..<range.lowerBound])
}

func gaussianPackageFolder(for sourceURL: URL, in categoryRoot: URL) -> URL {
    categoryRoot.appendingPathComponent(gaussianPackageName(for: sourceURL), isDirectory: true)
}

func importGaussianAsset(
    sourceURL: URL,
    destinationFolder: URL,
    fileManager fm: FileManager = .default,
    copy: ((URL, URL) throws -> Void)? = nil
) throws -> URL {
    let copyFile = copy ?? { try fm.copyItem(at: $0, to: $1) }
    try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

    let sources: [URL]
    if sourceURL.pathExtension.lowercased() == "untoldgs",
       let tiers = progressiveGaussianTiers(for: sourceURL)
    {
        sources = (0 ..< tiers.levelCount).map {
            tiers.baseURL.deletingLastPathComponent()
                .appendingPathComponent("\(tiers.baseURL.lastPathComponent)_lod\($0).untoldgs")
        }
    } else {
        sources = [sourceURL]
    }

    for source in sources {
        let destinationURL = destinationFolder.appendingPathComponent(source.lastPathComponent)
        if destinationURL.standardizedFileURL.path == source.standardizedFileURL.path {
            continue
        }
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try copyFile(source, destinationURL)
    }

    return primaryGaussianAsset(in: destinationFolder, fileManager: fm)
        ?? destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
}

func primaryGaussianAsset(in folder: URL, fileManager fm: FileManager = .default) -> URL? {
    guard let contents = try? fm.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let untoldGSFiles = contents
        .filter { $0.pathExtension.lowercased() == "untoldgs" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

    if let progressiveEntry = untoldGSFiles.first(where: { progressiveGaussianTiers(for: $0) != nil }) {
        return progressiveEntry
    }

    let folderName = folder.lastPathComponent
    if let namedSingle = untoldGSFiles.first(where: { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folderName) == .orderedSame }) {
        return namedSingle
    }
    if untoldGSFiles.count == 1 {
        return untoldGSFiles[0]
    }

    let plyFiles = contents
        .filter { $0.pathExtension.lowercased() == "ply" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    return plyFiles.first { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folderName) == .orderedSame }
        ?? (plyFiles.count == 1 ? plyFiles.first : nil)
}
