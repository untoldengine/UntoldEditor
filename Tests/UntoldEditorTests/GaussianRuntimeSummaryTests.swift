//
//  GaussianRuntimeSummaryTests.swift
//  UntoldEditorTests
//
//  What the editor says a `.untoldgs` costs the engine on this Mac — the path (whole or
//  paged), the pool, the coarse levels, the working set — read from the file's index and
//  sized with the engine's public policy, plus the placement lines built from it.
//

@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

@MainActor
final class GaussianRuntimeSummaryTests: XCTestCase {
    private var temporaryDirectory: URL?

    override func tearDown() async throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try await super.tearDown()
    }

    private func cookFixture(coarseLevels: GaussianCoarseLevelChoice = .automatic) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianRuntimeSummaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let plyURL = directory.appendingPathComponent("chair.ply")
        try GaussianLargeCaptureTests.makeFixturePLY(splatCount: 200).write(to: plyURL)
        var settings = GaussianCookSettings()
        settings.coarseLevels = coarseLevels
        return try cookGaussianPLY(plyURL: plyURL, settings: settings).tiers[0].url
    }

    func test_smallFileLoadsWholeBelowTheThreshold() throws {
        let url = try cookFixture()
        let summary = try GaussianRuntimeSummary.read(url: url, allocatedBytes: 0, disablePaging: false)
        XCTAssertEqual(summary.splatCount, 200)
        XCTAssertEqual(summary.chunkCount, 1)
        XCTAssertEqual(summary.splatsPerChunk, 1024)
        XCTAssertEqual(summary.shDegree, 0)
        XCTAssertEqual(summary.packedBytes, 200 * UntoldGSFormat.coreRecordSize)
        XCTAssertEqual(summary.coarseLevels, 0, "one chunk is below Auto's threshold")
        XCTAssertFalse(summary.isPaged)
        XCTAssertEqual(summary.poolBytes, summary.packedBytes, "a whole load holds its packed bytes")
        XCTAssertEqual(summary.thresholdBytes, GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: GaussianPagingPolicy.residencyBudgetBytes()))
        XCTAssertEqual(summary.workingSetSplats, GaussianRuntimeLimits.workingSetSplatsOverride ?? GaussianRuntimeLimits.workingSetSplats)
        XCTAssertEqual(summary.placementDetail, "200 splats in 1 chunk, 3.12 KiB packed: loads whole")
        XCTAssertEqual(summary.inspectorRows.map(\.label), ["Splats", "Packed", "Path", "Coarse levels", "Working set"])
        XCTAssertEqual(summary.inspectorRows[0].value, "200 in 1 chunk of 1024, SH 0")
        XCTAssertEqual(summary.inspectorRows[2].value, "whole resident")
        XCTAssertEqual(summary.inspectorRows[3].value, "none")
        XCTAssertEqual(gaussianPlacementDetail(for: url), summary.placementDetail)
    }

    func test_forcedLevelsShowInTheSummary() throws {
        let url = try cookFixture(coarseLevels: .one)
        let summary = try GaussianRuntimeSummary.read(url: url, allocatedBytes: 0)
        XCTAssertEqual(summary.coarseLevels, 1)
        XCTAssertGreaterThan(summary.coarseBytes, 0)
        XCTAssertTrue(summary.placementDetail.hasSuffix(", 1 coarse level (\(gaussianCookFormatBytes(summary.coarseBytes)))"), summary.placementDetail)
        XCTAssertEqual(summary.inspectorRows[3].value, "1 (\(gaussianCookFormatBytes(summary.coarseBytes)))")
    }

    func test_largeFilePagesThroughThePoolTheBudgetLeaves() throws {
        // The 10 M-splat degree-3 capture, sized by hand against a 1 GiB residency budget.
        let fixture = try cookFixture()
        var header = try UntoldGSFile(url: fixture).header
        header.splatCount = 10_000_000
        header.chunkCount = 9766
        header.shDegree = 3
        header.flags |= UntoldGSFlags.hasSphericalHarmonics | UntoldGSFlags.hasCoarseLevels
        header.coarseLevelCount = 2
        header.coarsePayloadOffset = 640 << 20
        header.fileSize = (640 << 20) + (22 << 20)

        let summary = GaussianRuntimeSummary(header: header, allocatedBytes: 0, disablePaging: false, residencyBudgetBytes: 1 << 30, pagePoolMaxBytes: 1 << 30, workingSetSplats: 3_000_000)
        XCTAssertEqual(summary.packedBytes, 10_000_000 * 61)
        XCTAssertTrue(summary.isPaged, "582 MiB is above the 512 MiB Mac threshold")
        XCTAssertEqual(summary.thresholdBytes, 512 << 20)
        XCTAssertEqual(summary.pagesPerChunk, 4, "1024 splats per chunk, 256 ranks per page")
        XCTAssertTrue(summary.poolHoldsWholeAsset, "the budget leaves room for the whole asset")
        XCTAssertGreaterThanOrEqual(summary.poolBytes, summary.packedBytes)
        XCTAssertEqual(summary.coarseLevels, 2)
        XCTAssertEqual(summary.coarseBytes, 22 << 20)
        XCTAssertEqual(summary.placementDetail, "10,000,000 splats in 9,766 chunks, 581.74 MiB packed: pages through a \(gaussianCookFormatBytes(summary.poolBytes)) pool (holds the whole asset), 2 coarse levels (22.00 MiB)")
        XCTAssertEqual(summary.inspectorRows[2].value, "paged, 4 pages per chunk")
        XCTAssertEqual(summary.inspectorRows[3].label, "Pool")
        XCTAssertTrue(summary.inspectorRows[3].value.hasSuffix("of a 1024.00 MiB residency budget, holds the whole asset"), summary.inspectorRows[3].value)
        XCTAssertEqual(summary.inspectorRows[5].value, "3,000,000 splats per frame")

        // A smaller budget (an 8 GB Mac: 325 MiB) caps the pool below the asset.
        let small = GaussianRuntimeSummary(header: header, allocatedBytes: 0, disablePaging: false, residencyBudgetBytes: 325 << 20, pagePoolMaxBytes: 1 << 30, workingSetSplats: 3_000_000)
        XCTAssertTrue(small.isPaged)
        XCTAssertEqual(small.thresholdBytes, 325 << 20, "the threshold never exceeds the budget")
        XCTAssertFalse(small.poolHoldsWholeAsset)
        XCTAssertLessThanOrEqual(small.poolBytes, 325 << 20)
        XCTAssertTrue(small.placementDetail.contains("pages through a \(gaussianCookFormatBytes(small.poolBytes)) pool,"), small.placementDetail)

        // Pools already allocated shrink the next one; the debug switch loads whole.
        let crowded = GaussianRuntimeSummary(header: header, allocatedBytes: 900 << 20, disablePaging: false, residencyBudgetBytes: 1 << 30, pagePoolMaxBytes: 1 << 30, workingSetSplats: 3_000_000)
        XCTAssertLessThan(crowded.poolBytes, summary.poolBytes)
        let whole = GaussianRuntimeSummary(header: header, allocatedBytes: 0, disablePaging: true, residencyBudgetBytes: 1 << 30, pagePoolMaxBytes: 1 << 30, workingSetSplats: 3_000_000)
        XCTAssertFalse(whole.isPaged)
        XCTAssertEqual(whole.poolBytes, whole.packedBytes)
    }

    func test_liveLineReadsTheEntityAndTheSceneWidePools() {
        let savedScene = scene
        defer { scene = savedScene }
        scene = Scene()
        let entity = createEntity()
        XCTAssertNil(gaussianRuntimeLiveLine(entityId: entity, allocatedBytes: 0, coarseBytes: 0), "no splats, no line")

        let component = try? XCTUnwrap(scene.assign(to: entity, component: GaussianComponent.self))
        component?.estimatedGPUBytes = 610 << 20
        XCTAssertEqual(gaussianRuntimeLiveLine(entityId: entity, allocatedBytes: 0, coarseBytes: 0), "GPU 610.00 MiB")
        XCTAssertEqual(gaussianRuntimeLiveLine(entityId: entity, allocatedBytes: 582 << 20, coarseBytes: 0), "GPU 610.00 MiB · scene pools 582.00 MiB")
        XCTAssertEqual(gaussianRuntimeLiveLine(entityId: entity, allocatedBytes: 582 << 20, coarseBytes: 22 << 20), "GPU 610.00 MiB · scene pools 582.00 MiB, coarse 22.00 MiB")
    }

    func test_placementLinesSteerAwayFromTheUncookedPLY() {
        let ply = URL(fileURLWithPath: "/tmp/room.ply")
        let baked = URL(fileURLWithPath: "/tmp/room.untoldgs")
        XCTAssertEqual(
            gaussianPlacementStatusMessage(url: ply, entityName: "Entity_3", accepted: true),
            "Queued Gaussian import: Entity_3 — an uncooked .ply takes the slow whole-buffer path; cook it to .untoldgs from its context menu"
        )
        XCTAssertEqual(gaussianPlacementStatusMessage(url: baked, entityName: "Entity_3", accepted: true), "Queued Gaussian import: Entity_3 (see Tasks)")
        XCTAssertEqual(gaussianPlacementStatusMessage(url: baked, entityName: "Entity_3", accepted: false), "Unsupported Gaussian asset: room.untoldgs")
        XCTAssertEqual(
            gaussianPlacementDetail(for: ply),
            "Uncooked .ply: whole-buffer path, capped at \(GaussianSplatBudget.formatted(GaussianRuntimeLimits.maxWholeBufferSplatsPerEntity)) splats; cook it to .untoldgs for chunk culling, paging and coarse levels"
        )
        XCTAssertEqual(gaussianPlacementDetail(for: baked), "Reading room.untoldgs", "a missing file falls back to the file name")
    }
}
