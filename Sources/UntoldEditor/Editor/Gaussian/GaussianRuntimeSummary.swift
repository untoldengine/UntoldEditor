//
//  GaussianRuntimeSummary.swift
//  UntoldEditor
//
//  What a Gaussian asset costs the engine on this Mac, from its `.untoldgs` index alone (the
//  header, chunk index and tree; the payload is never read): the path the load takes (whole
//  resident or paged through a pool), the pool the residency budget leaves it, the coarse
//  levels the file carries and the working set the frame draws from. The placement task, the
//  Inspector's Gaussian section and the Splat Debug menu read it; the numbers mirror the
//  engine's public policy (`GaussianPagingPolicy`, `GaussianRuntimeLimits`) so what the
//  editor says is what the engine does at the next load.
//

import Foundation
import UntoldEngine

struct GaussianRuntimeSummary: Equatable {
    var splatCount: Int
    var chunkCount: Int
    var splatsPerChunk: Int
    var shDegree: Int
    /// The packed records: 16 bytes plus the SH block per splat — what the residency budget is
    /// measured against.
    var packedBytes: Int
    /// Per-chunk coarse levels the file carries and their section's bytes.
    var coarseLevels: Int
    var coarseBytes: Int
    /// Whether the engine pages the asset at the next load (above the threshold, paging not
    /// disabled) or holds it whole.
    var isPaged: Bool
    var thresholdBytes: Int
    var residencyBudgetBytes: Int
    /// The pool a paged load is given (what the residency budget leaves after the pools already
    /// allocated, capped by the asset and the platform), or the packed bytes when whole.
    var poolBytes: Int
    var pagesPerChunk: Int
    /// The frame's working set in splats: the editor's override, else the engine's platform figure.
    var workingSetSplats: Int

    /// Reads the index of `url` (a bounded read: header, chunk index, tree) and sizes the load
    /// the way `GaussianChunkLoader` will, against the current budgets and the pools already
    /// allocated (`GaussianPagePoolRegistry.shared.allocatedBytes`; pass 0 to size a lone load).
    static func read(
        url: URL,
        allocatedBytes: Int = GaussianPagePoolRegistry.shared.allocatedBytes,
        disablePaging: Bool = GaussianDebugOptions.shared.disablePaging
    ) throws -> GaussianRuntimeSummary {
        let header = try UntoldGSFile(url: url).header
        return GaussianRuntimeSummary(header: header, allocatedBytes: allocatedBytes, disablePaging: disablePaging)
    }

    init(
        header: UntoldGSHeaderV3,
        allocatedBytes: Int = 0,
        disablePaging: Bool = false,
        residencyBudgetBytes: Int = GaussianPagingPolicy.residencyBudgetBytes(),
        pagePoolMaxBytes: Int = GaussianPagingPolicy.pagePoolMaxBytes,
        workingSetSplats: Int = GaussianRuntimeLimits.workingSetSplatsOverride ?? GaussianRuntimeLimits.workingSetSplats
    ) {
        splatCount = Int(header.splatCount)
        chunkCount = Int(header.chunkCount)
        splatsPerChunk = header.splatsPerChunk
        shDegree = header.hasSphericalHarmonics ? Int(header.shDegree) : 0
        let shBytesPerSplat = header.shBytesPerSplat
        packedBytes = GaussianPagingPolicy.assetBytes(splatCount: splatCount, shBytesPerSplat: shBytesPerSplat)
        coarseLevels = header.hasCoarseLevels ? Int(header.coarseLevelCount) : 0
        coarseBytes = header.hasCoarseLevels && header.coarsePayloadOffset > 0 && header.fileSize > header.coarsePayloadOffset
            ? Int(header.fileSize - header.coarsePayloadOffset)
            : 0
        self.residencyBudgetBytes = residencyBudgetBytes
        thresholdBytes = GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: residencyBudgetBytes)
        isPaged = GaussianPagingPolicy.shouldPage(assetBytes: packedBytes, thresholdBytes: thresholdBytes, allowPaging: true, disablePaging: disablePaging)
        let ranksPerPage = GaussianPagingPolicy.ranksPerPage(splatsPerChunk: header.splatsPerChunk)
        pagesPerChunk = GaussianPagingPolicy.pagesPerChunk(splatsPerChunk: header.splatsPerChunk)
        if isPaged {
            let slotBytes = ranksPerPage * (UntoldGSFormat.coreRecordSize + shBytesPerSplat)
            let slots = GaussianPagingPolicy.poolSlotCount(
                assetBytes: packedBytes,
                slotBytes: slotBytes,
                residencyBudgetBytes: residencyBudgetBytes,
                allocatedBytes: allocatedBytes,
                poolMaxBytes: pagePoolMaxBytes
            )
            poolBytes = slots * slotBytes
        } else {
            poolBytes = packedBytes
        }
        self.workingSetSplats = workingSetSplats
    }

    /// Whether a paged load has the whole asset in its pool (paging only lazy-loads then).
    var poolHoldsWholeAsset: Bool {
        poolBytes >= packedBytes
    }

    /// One line for the placement task and the status bar: what the file is and how it loads.
    var placementDetail: String {
        var line = "\(GaussianSplatBudget.formatted(splatCount)) splats in \(GaussianSplatBudget.formatted(chunkCount)) chunk\(chunkCount == 1 ? "" : "s"), \(gaussianCookFormatBytes(packedBytes)) packed: "
        if isPaged {
            line += "pages through a \(gaussianCookFormatBytes(poolBytes)) pool"
            if poolHoldsWholeAsset {
                line += " (holds the whole asset)"
            }
        } else {
            line += "loads whole"
        }
        if coarseLevels > 0 {
            line += ", \(coarseLevels) coarse level\(coarseLevels == 1 ? "" : "s") (\(gaussianCookFormatBytes(coarseBytes)))"
        }
        return line
    }

    /// The Inspector's read-only rows: label and value.
    var inspectorRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        rows.append(("Splats", "\(GaussianSplatBudget.formatted(splatCount)) in \(GaussianSplatBudget.formatted(chunkCount)) chunk\(chunkCount == 1 ? "" : "s") of \(splatsPerChunk), SH \(shDegree)"))
        rows.append(("Packed", "\(gaussianCookFormatBytes(packedBytes)) (paging threshold \(gaussianCookFormatBytes(thresholdBytes)))"))
        if isPaged {
            rows.append(("Path", "paged, \(pagesPerChunk) page\(pagesPerChunk == 1 ? "" : "s") per chunk"))
            rows.append(("Pool", "\(gaussianCookFormatBytes(poolBytes)) of a \(gaussianCookFormatBytes(residencyBudgetBytes)) residency budget\(poolHoldsWholeAsset ? ", holds the whole asset" : "")"))
        } else {
            rows.append(("Path", "whole resident"))
        }
        rows.append(("Coarse levels", coarseLevels > 0 ? "\(coarseLevels) (\(gaussianCookFormatBytes(coarseBytes)))" : "none"))
        rows.append(("Working set", "\(GaussianSplatBudget.formatted(workingSetSplats)) splats per frame"))
        return rows
    }
}

/// The placement line for a source the summary cannot describe: an uncooked `.ply`, which the
/// engine parses on the CPU into one whole buffer — no chunks, no paging, no levels, capped at
/// `GaussianRuntimeLimits.maxWholeBufferSplatsPerEntity` — or a file whose index could not be read.
func gaussianPlacementDetail(for url: URL) -> String {
    if url.pathExtension.lowercased() == "ply" {
        return "Uncooked .ply: whole-buffer path, capped at \(GaussianSplatBudget.formatted(GaussianRuntimeLimits.maxWholeBufferSplatsPerEntity)) splats; cook it to .untoldgs for chunk culling, paging and coarse levels"
    }
    if let summary = try? GaussianRuntimeSummary.read(url: url) {
        return summary.placementDetail
    }
    return "Reading \(url.lastPathComponent)"
}

/// The status-bar line for a drop or double-click of `url`: a queued import, with the whole-
/// buffer warning for an uncooked `.ply`, or the refusal.
func gaussianPlacementStatusMessage(url: URL, entityName: String, accepted: Bool) -> String {
    guard accepted else {
        return "Unsupported Gaussian asset: \(url.lastPathComponent)"
    }
    if url.pathExtension.lowercased() == "ply" {
        return "Queued Gaussian import: \(entityName) — an uncooked .ply takes the slow whole-buffer path; cook it to .untoldgs from its context menu"
    }
    return "Queued Gaussian import: \(entityName) (see Tasks)"
}

/// The live line under the Inspector's runtime rows, from what the engine exposes: the
/// entity's GPU bytes (`GaussianComponent.estimatedGPUBytes`: the pool of a paged entity, the
/// whole records otherwise) and the scene-wide pool and coarse bytes the residency budget is
/// charged with (`GaussianPagePoolRegistry`). Nil for an entity without splats.
func gaussianRuntimeLiveLine(
    entityId: EntityID,
    allocatedBytes: Int = GaussianPagePoolRegistry.shared.allocatedBytes,
    coarseBytes: Int = GaussianPagePoolRegistry.shared.coarseBytes
) -> String? {
    guard let component = scene.get(component: GaussianComponent.self, for: entityId) else { return nil }
    var line = "GPU \(gaussianCookFormatBytes(component.estimatedGPUBytes))"
    if allocatedBytes > 0 || coarseBytes > 0 {
        line += " · scene pools \(gaussianCookFormatBytes(allocatedBytes))"
        if coarseBytes > 0 {
            line += ", coarse \(gaussianCookFormatBytes(coarseBytes))"
        }
    }
    return line
}
