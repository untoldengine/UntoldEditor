//
//  GaussianCookSourceInfo.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import simd
import UntoldEngine

/// What the sheet knows about a source before it cooks: enough for the captions. A `.ply`
/// gives it up from the header alone, without reading the body. A `.spz` has no header-only
/// path — its count and degree sit inside the gzip payload — so it is decoded whole, as the
/// bake decodes it again.
struct GaussianCookSourceInfo: Equatable {
    var splatCount: Int
    /// Spherical-harmonics degree the file stores (0 when it has no `f_rest_*` properties).
    var shDegree: Int

    /// For a `.ply`, a header-only read: the splat count through the engine's reader and the
    /// degree from the `f_rest_N` property count of the first 100 KB (3 × ((d + 1)² − 1)
    /// coefficients). For a `.spz`, the engine's whole decode (`SPZReader.readGaussianAsset`):
    /// the count is of the splats the reader keeps, past its negligible-opacity cull, and the
    /// degree is the payload's.
    static func read(from url: URL) throws -> GaussianCookSourceInfo {
        if url.pathExtension.lowercased() == "spz" {
            let asset = try SPZReader.readGaussianAsset(from: url)
            return GaussianCookSourceInfo(splatCount: asset.splats.count, shDegree: asset.sphericalHarmonics?.degree ?? 0)
        }
        let splatCount = try PLYReader.readGaussianSplatCount(from: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 100_000) ?? Data()
        return GaussianCookSourceInfo(splatCount: splatCount, shDegree: shDegree(fromHeaderPrefix: prefix))
    }

    static func shDegree(fromHeaderPrefix prefix: Data) -> Int {
        guard let text = String(data: prefix, encoding: .ascii) ?? String(data: prefix, encoding: .isoLatin1) else { return 0 }
        let header = text.components(separatedBy: "end_header").first ?? text
        let rest = header.components(separatedBy: .newlines).filter { line in
            let fields = line.split(separator: " ")
            return fields.count == 3 && fields[0] == "property" && fields[2].hasPrefix("f_rest_")
        }.count
        switch rest {
        case 45...: return 3
        case 24...: return 2
        case 9...: return 1
        default: return 0
        }
    }
}

/// Bytes per splat of the engine's compact cook store (`UntoldGSSplatStore`): the floats of
/// position, scale, rotation, colour and opacity, 56 bytes, plus the spherical harmonics
/// already quantised to the target degree.
let gaussianCookStoreBytesPerSplat = 56

/// Process memory a cook of `splatCount` splats at `shDegree` peaks at, in bytes. The engine
/// streams the source in windows and cooks it into one compact store, so the store is what
/// the cook holds — about 100 bytes per splat at degree 3 — plus the windows in flight, the
/// ranking and the chunk encode, about half as much again: a 10 M-splat degree-3 capture
/// (a 2.25 GiB `.ply`) peaks at about 1.4 GiB. The budget compacts the store in place, so the
/// source count is what counts, not the kept count. A `.spz` is decoded whole before the cook
/// (its reader is not streamed), so the decoded asset sits beside the store through the read;
/// the estimate is a floor there.
func gaussianCookEstimatedPeakBytes(splatCount: Int, shDegree: Int) -> Int {
    let shBytes = shDegree > 0 ? UntoldGSFormat.shCoefficientCount(degree: UInt8(min(shDegree, Int(UntoldGSFormat.maxSHDegree)))) : 0
    return splatCount * (gaussianCookStoreBytesPerSplat + shBytes) * 3 / 2
}

/// Caption under the source row: what the cook costs in memory, and a warning when the
/// estimate does not fit the machine. Nil for an empty or unreadable source.
func gaussianCookMemoryCaption(splatCount: Int, shDegree: Int, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String? {
    guard splatCount > 0 else { return nil }
    let peak = gaussianCookEstimatedPeakBytes(splatCount: splatCount, shDegree: shDegree)
    let text = "The cook needs about \(gaussianCookFormatGiB(peak)) of memory (this Mac has \(gaussianCookFormatGiB(Int(physicalMemory))))"
    if Double(peak) > Double(physicalMemory) * 0.75 {
        return text + "; expect heavy swapping — close other apps or cook on a Mac with more memory."
    }
    return text + "."
}

/// Bytes as a short gibibyte figure for the captions ("9.4 GiB", "512 MiB"), in the units
/// `gaussianCookFormatBytes` and the engine's profile lines use.
func gaussianCookFormatGiB(_ bytes: Int) -> String {
    let value = Double(bytes)
    if bytes >= 1 << 30 {
        return String(format: "%.1f GiB", value / Double(1 << 30))
    }
    return String(format: "%.0f MiB", value / Double(1 << 20))
}

/// Caption under the budget row: what the cooked file costs at runtime on this Mac — the
/// packed records (16 bytes plus the SH block per kept splat) against the engine's paging
/// threshold, so the user knows whether the file loads whole or pages from disk, and the
/// working set the frame draws from.
func gaussianCookRuntimeCaption(
    keptSplatCount: Int,
    shDegree: Int,
    residencyBudgetBytes: Int = GaussianPagingPolicy.residencyBudgetBytes(),
    pagePoolMaxBytes: Int = GaussianPagingPolicy.pagePoolMaxBytes,
    workingSetSplats: Int = GaussianRuntimeLimits.workingSetSplatsOverride ?? GaussianRuntimeLimits.workingSetSplats
) -> String {
    let shBytes = shDegree > 0 ? UntoldGSFormat.shCoefficientCount(degree: UInt8(min(shDegree, Int(UntoldGSFormat.maxSHDegree)))) : 0
    let packed = GaussianPagingPolicy.assetBytes(splatCount: keptSplatCount, shBytesPerSplat: shBytes)
    let threshold = GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: residencyBudgetBytes)
    var caption = "About \(gaussianCookFormatGiB(packed)) of packed splats at runtime: "
    if packed > threshold {
        let pool = min(packed, residencyBudgetBytes, pagePoolMaxBytes)
        // A zero threshold is the View > Splat Debug > Force Splat Paging switch.
        let reason = threshold == 0 ? "Force Splat Paging is on" : "above \(gaussianCookFormatGiB(threshold))"
        caption += "pages from disk (\(reason)) through a \(gaussianCookFormatGiB(pool)) pool"
    } else {
        caption += "loads whole (below \(gaussianCookFormatGiB(threshold)))"
    }
    caption += "; the frame draws at most \(GaussianSplatBudget.formatted(workingSetSplats)) splats."
    return caption
}
