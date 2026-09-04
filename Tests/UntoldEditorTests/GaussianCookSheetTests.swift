//
//  GaussianCookSheetTests.swift
//  UntoldEditorTests
//
//  The "Cook to .untoldgs" path: settings → engine cook options, the bake beside the
//  source .ply, the Tasks-panel wrapper the browser runs cooks through, and
//  progressive tier detection for placement.
//

import simd
@testable import UntoldEditor
import UntoldEngine
import XCTest

final class GaussianCookSheetTests: XCTestCase {
    private var temporaryDirectory: URL?

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func test_settingsMapToEngineCookOptions() {
        var settings = GaussianCookSettings()
        settings.chunkSplats = 4096
        settings.shDegree = 2
        settings.flipYZ = true
        settings.scale = 0.5
        settings.minimumOpacity = 0.01

        let options = settings.cookOptions
        XCTAssertEqual(options.log2ChunkSplats, 12)
        XCTAssertEqual(options.shDegree, 2)
        XCTAssertEqual(options.minimumOpacity, 0.01)
        // Scale 0.5 with the Y/Z flip: diagonal (0.5, -0.5, -0.5).
        XCTAssertEqual(options.transform.columns.0.x, 0.5)
        XCTAssertEqual(options.transform.columns.1.y, -0.5)
        XCTAssertEqual(options.transform.columns.2.z, -0.5)

        XCTAssertNil(GaussianCookSettings().shDegree)
        XCTAssertEqual(GaussianCookSettings().cookOptions.log2ChunkSplats, 10)
    }

    func test_cookWritesTiersBesideTheSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let plyURL = directory.appendingPathComponent("chair.ply")
        try makeTestPLY(splatCount: 200).write(to: plyURL)

        var settings = GaussianCookSettings()
        settings.levelCount = 2
        let result = try cookGaussianPLY(plyURL: plyURL, settings: settings)

        XCTAssertEqual(result.tiers.count, 2)
        XCTAssertEqual(result.tiers.map(\.url.lastPathComponent), ["chair_lod0.untoldgs", "chair_lod1.untoldgs"])
        XCTAssertEqual(result.cookReport.inputSplatCount, 200)
        for tier in result.tiers {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tier.url.path))
            XCTAssertNoThrow(try UntoldGSFormat.readHeader(from: tier.url))
        }

        let tiers = try XCTUnwrap(progressiveGaussianTiers(for: result.tiers[1].url))
        XCTAssertEqual(tiers.levelCount, 2)
        XCTAssertEqual(tiers.baseURL.lastPathComponent, "chair")
        XCTAssertEqual(defaultGaussianLODDistances(levelCount: 2), [5, .greatestFiniteMagnitude])

        // A single-tier cook writes one file and is not progressive.
        settings.levelCount = 1
        let single = try cookGaussianPLY(plyURL: plyURL, settings: settings)
        XCTAssertEqual(single.tiers.map(\.url.lastPathComponent), ["chair.untoldgs"])
        XCTAssertNil(progressiveGaussianTiers(for: single.tiers[0].url))
    }

    func test_importBatchHelpers() {
        let ply = URL(fileURLWithPath: "/tmp/Gaussians/room.PLY")
        let baked = URL(fileURLWithPath: "/tmp/Gaussians/room.untoldgs")
        XCTAssertEqual(gaussianSourcesToCook(in: [baked, ply]), [ply], "only .ply sources are cooked, any case")
        XCTAssertEqual(gaussianSourcesToCook(in: [baked]), [])

        XCTAssertEqual(gaussianCookSheetSourceName(for: [ply]), "room.PLY")
        XCTAssertEqual(gaussianCookSheetSourceName(for: [ply, ply]), "2 .ply files")

        var settings = GaussianCookSettings()
        XCTAssertEqual(gaussianCookTaskDetail(settings: settings), "→ .untoldgs")
        settings.levelCount = 3
        XCTAssertEqual(gaussianCookTaskDetail(settings: settings), "3 progressive tiers → .untoldgs")

        let report = UntoldGSCookReport(inputSplatCount: 10, keptSplatCount: 7, prunedByOpacity: 3, prunedByDegenerateGeometry: 0, prunedByCrop: 0, shDegree: 0)
        XCTAssertEqual(gaussianCookSummary(report), "Kept 7 of 10 splats")
        XCTAssertEqual(gaussianCookFailureDetail(UntoldGSCookError.noSplatsLeftAfterPruning(report)), UntoldGSCookError.noSplatsLeftAfterPruning(report).description)
        XCTAssertEqual(gaussianCookFailureDetail(CocoaError(.fileNoSuchFile)), CocoaError(.fileNoSuchFile).localizedDescription)
    }

    func test_trackedCookSucceedsAsATask() async throws {
        let plyURL = try makeTemporaryPLY(named: "chair.ply", splatCount: 200)
        var settings = GaussianCookSettings()
        settings.levelCount = 2

        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let handle = cookGaussianPLYTracked(plyURL: plyURL, settings: settings) { result in
            XCTAssertTrue(Thread.isMainThread)
            completionResult = result
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 30)
        await settleTaskCenter()

        let bake = try XCTUnwrap(completionResult?.get())
        XCTAssertEqual(bake.tiers.map(\.url.lastPathComponent), ["chair_lod0.untoldgs", "chair_lod1.untoldgs"])

        let tracked = await trackedTask(handle.id)
        let task = try XCTUnwrap(tracked)
        XCTAssertEqual(task.title, "Cooking chair.ply")
        XCTAssertEqual(task.state, .succeeded)
        XCTAssertNil(task.progress, "the baker reports no progress; the row stays indeterminate")
        XCTAssertFalse(task.isCancellable)
        XCTAssertEqual(task.detail, "Kept 200 of 200 splats")
    }

    func test_trackedCookFailureMarksTaskFailedAndKeepsTheSource() async throws {
        let plyURL = try makeTemporaryPLY(named: "empty.ply", splatCount: 50)
        var settings = GaussianCookSettings()
        settings.minimumOpacity = 1.5 // above every opacity: nothing survives pruning

        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let handle = cookGaussianPLYTracked(plyURL: plyURL, settings: settings) { result in
            completionResult = result
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 30)
        await settleTaskCenter()

        guard case let .failure(error)? = completionResult else {
            return XCTFail("expected the cook to fail")
        }
        guard case let .noSplatsLeftAfterPruning(report)? = error as? UntoldGSCookError else {
            return XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(report.prunedByOpacity, 50)

        let tracked = await trackedTask(handle.id)
        let task = try XCTUnwrap(tracked)
        XCTAssertEqual(task.state, .failed)
        XCTAssertEqual(task.detail, gaussianCookFailureDetail(error))
        XCTAssertTrue(task.detail.hasPrefix("no splats left after pruning"))

        let directory = plyURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: plyURL.path), "a failed cook leaves the .ply in place")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("empty.untoldgs").path))
    }

    func test_trackedCooksRunInOrderOnTheirQueue() async throws {
        let first = try makeTemporaryPLY(named: "a.ply", splatCount: 20)
        let second = try makeTemporaryPLY(named: "b.ply", splatCount: 20)
        let queue = DispatchQueue(label: "GaussianCookSheetTests.serial")

        var order: [String] = []
        let done = expectation(description: "both cooks reported")
        done.expectedFulfillmentCount = 2
        for url in [first, second] {
            cookGaussianPLYTracked(plyURL: url, settings: GaussianCookSettings(), queue: queue) { _ in
                order.append(url.lastPathComponent)
                done.fulfill()
            }
        }
        await fulfillment(of: [done], timeout: 30)
        XCTAssertEqual(order, ["a.ply", "b.ply"])
    }

    // MARK: - Helpers

    /// `TaskCenter` applies every update on the main actor via `Task {}`; give those a
    /// moment to land before reading the task back.
    private func settleTaskCenter() async {
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    @MainActor
    private func trackedTask(_ id: UUID) -> EditorTask? {
        TaskCenter.shared.tasks.first { $0.id == id }
    }

    private func makeTemporaryPLY(named name: String, splatCount: Int) throws -> URL {
        let directory = try temporaryDirectory ?? {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            temporaryDirectory = url
            return url
        }()
        let plyURL = directory.appendingPathComponent(name)
        try makeTestPLY(splatCount: splatCount).write(to: plyURL)
        return plyURL
    }

    private func makeTestPLY(splatCount: Int) -> Data {
        var body = ""
        for index in 0 ..< splatCount {
            let x = Float(index % 10) * 0.1
            let y = Float(index / 10 % 10) * 0.1
            let z = Float(index / 100) * 0.1
            body += "\(x) \(y) \(z) 0 0 1 0.2 0.1 -0.1 2.0 -4 -4 -4 1 0 0 0\n"
        }
        let header = """
        ply
        format ascii 1.0
        element vertex \(splatCount)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header

        """
        return Data((header + body).utf8)
    }
}
