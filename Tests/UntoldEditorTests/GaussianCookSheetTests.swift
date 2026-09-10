//
//  GaussianCookSheetTests.swift
//  UntoldEditorTests
//
//  The "Cook to .untoldgs" path: settings → engine cook options, the bake beside the
//  source .ply, the Tasks-panel wrapper the browser runs cooks through, progressive
//  tier detection for placement, and the sheet's empty state (nothing selected).
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
        XCTAssertEqual(GaussianCookSettings().upAxis, .y)
    }

    func test_splatBudgetMapsToTheEngineCap() {
        var settings = GaussianCookSettings()
        XCTAssertEqual(settings.splatBudget, .mac, "the editor runs on a Mac, so the Mac cap is the default")
        XCTAssertEqual(settings.cookOptions.maxSplatCount, UntoldGSCookOptions.splatBudgetMac)
        settings.splatBudget = .visionPro
        XCTAssertEqual(settings.cookOptions.maxSplatCount, UntoldGSCookOptions.splatBudgetMobile)
        settings.splatBudget = .unlimited
        XCTAssertNil(settings.cookOptions.maxSplatCount)
        settings.splatBudget = .custom
        settings.customSplatBudget = 123_456
        XCTAssertEqual(settings.cookOptions.maxSplatCount, 123_456)
        XCTAssertTrue(gaussianCookTaskDetail(settings: settings).contains("budget 123,456"))

        // The presets are the engine's caps, so the captions are checked against those
        // constants rather than against the numbers they happen to be today.
        let mobileCap = UntoldGSCookOptions.splatBudgetMobile
        let overMobileCap = mobileCap + 1
        XCTAssertEqual(mobileCap, GaussianRuntimeLimits.maxSplatsPerEntityMobile)
        XCTAssertEqual(UntoldGSCookOptions.splatBudgetMac, GaussianRuntimeLimits.maxSplatsPerEntityMac)
        XCTAssertEqual(
            gaussianBudgetCaption(sourceCount: overMobileCap, maxSplatCount: mobileCap),
            "\(GaussianSplatBudget.formatted(overMobileCap)) splats in the source; the budget keeps the \(GaussianSplatBudget.formatted(mobileCap)) most important."
        )
        XCTAssertEqual(
            gaussianBudgetCaption(sourceCount: mobileCap, maxSplatCount: mobileCap),
            "\(GaussianSplatBudget.formatted(mobileCap)) splats in the source, within the budget."
        )
        XCTAssertEqual(gaussianBudgetCaption(sourceCount: 1000, maxSplatCount: 5000), "1,000 splats in the source, within the budget.")
        XCTAssertTrue(gaussianBudgetCaption(sourceCount: overMobileCap, maxSplatCount: nil).contains("do not load on Vision Pro"))
        XCTAssertEqual(
            gaussianBudgetCaption(sourceCount: mobileCap, maxSplatCount: nil),
            "\(GaussianSplatBudget.formatted(mobileCap)) splats in the source, all kept."
        )
        XCTAssertEqual(gaussianBudgetCaption(sourceCount: nil, maxSplatCount: nil), "No splat budget.")

        var report = UntoldGSCookReport.passthrough(splatCount: 10, shDegree: 0)
        XCTAssertEqual(gaussianCookSummary(report), "Kept 10 of 10 splats")
        report.prunedByBudget = 4
        report.keptSplatCount = 6
        XCTAssertEqual(gaussianCookSummary(report), "Kept 6 of 10 splats (4 over the budget dropped)")
    }

    func test_upAxisRotatesTheCaptureToYUp() {
        var settings = GaussianCookSettings()
        settings.upAxis = .z
        let zUp = settings.cookOptions.transform * SIMD4<Float>(0, 0, 1, 1)
        XCTAssertEqual(zUp.y, 1, accuracy: 1e-6)
        XCTAssertEqual(zUp.z, 0, accuracy: 1e-6)

        settings.upAxis = .negativeY
        XCTAssertTrue(settings.flipYZ, "the legacy flip spelling maps onto −Y up")
        settings.flipYZ = false
        XCTAssertEqual(settings.upAxis, .y)
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

    func test_cookCanWriteTiersIntoGaussianPackageFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory

        let plyURL = directory.appendingPathComponent("chair.ply")
        let packageFolder = directory.appendingPathComponent("chair", isDirectory: true)
        try makeTestPLY(splatCount: 200).write(to: plyURL)

        var settings = GaussianCookSettings()
        settings.levelCount = 2
        let result = try cookGaussianPLY(plyURL: plyURL, settings: settings, outputDirectory: packageFolder)

        XCTAssertEqual(result.tiers.map(\.url.lastPathComponent), ["chair_lod0.untoldgs", "chair_lod1.untoldgs"])
        XCTAssertEqual(result.tiers.map { $0.url.deletingLastPathComponent() }, [packageFolder, packageFolder])
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

    func test_gaussianPackageHelpers() throws {
        let root = URL(fileURLWithPath: "/tmp/Gaussians", isDirectory: true)
        let ply = root.appendingPathComponent("room.ply")
        let lod0 = root.appendingPathComponent("chair_lod0.untoldgs")
        XCTAssertEqual(gaussianPackageName(for: ply), "room")
        XCTAssertEqual(gaussianPackageName(for: lod0), "chair")
        XCTAssertEqual(gaussianPackageFolder(for: ply, in: root), root.appendingPathComponent("room", isDirectory: true))
        XCTAssertEqual(gaussianPackageFolder(for: lod0, in: root), root.appendingPathComponent("chair", isDirectory: true))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory

        let chairFolder = directory.appendingPathComponent("chair", isDirectory: true)
        try FileManager.default.createDirectory(at: chairFolder, withIntermediateDirectories: true)
        let chairLOD0 = chairFolder.appendingPathComponent("chair_lod0.untoldgs")
        let chairLOD1 = chairFolder.appendingPathComponent("chair_lod1.untoldgs")
        FileManager.default.createFile(atPath: chairLOD0.path, contents: Data())
        FileManager.default.createFile(atPath: chairLOD1.path, contents: Data())
        XCTAssertEqual(primaryGaussianAsset(in: chairFolder)?.standardizedFileURL, chairLOD0.standardizedFileURL)

        let tableFolder = directory.appendingPathComponent("table", isDirectory: true)
        try FileManager.default.createDirectory(at: tableFolder, withIntermediateDirectories: true)
        let table = tableFolder.appendingPathComponent("table.untoldgs")
        FileManager.default.createFile(atPath: table.path, contents: Data())
        XCTAssertEqual(primaryGaussianAsset(in: tableFolder)?.standardizedFileURL, table.standardizedFileURL)
    }

    func test_importGaussianAssetCopiesDetectedProgressiveTierSet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = directory.appendingPathComponent("destination", isDirectory: true)
        temporaryDirectory = directory

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let sourceLOD0 = sourceDirectory.appendingPathComponent("chair_lod0.untoldgs")
        let sourceLOD1 = sourceDirectory.appendingPathComponent("chair_lod1.untoldgs")
        try Data([0]).write(to: sourceLOD0)
        try Data([1]).write(to: sourceLOD1)

        let packageFolder = gaussianPackageFolder(for: sourceLOD0, in: destinationRoot)
        let imported = try importGaussianAsset(sourceURL: sourceLOD0, destinationFolder: packageFolder)

        XCTAssertEqual(imported.standardizedFileURL, packageFolder.appendingPathComponent("chair_lod0.untoldgs").standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageFolder.appendingPathComponent("chair_lod0.untoldgs").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageFolder.appendingPathComponent("chair_lod1.untoldgs").path))
    }

    func test_editorGaussianLoadPlanUsesSingleAsyncInputsForStandaloneFiles() {
        let ply = URL(fileURLWithPath: "/tmp/Gaussians/room.PLY")
        let baked = URL(fileURLWithPath: "/tmp/Gaussians/room.untoldgs")

        XCTAssertEqual(
            editorGaussianLoadPlan(for: ply),
            .single(filename: "/tmp/Gaussians/room", withExtension: "ply")
        )
        XCTAssertEqual(
            editorGaussianLoadPlan(for: baked),
            .single(filename: "/tmp/Gaussians/room", withExtension: "untoldgs")
        )
        XCTAssertNil(editorGaussianLoadPlan(for: URL(fileURLWithPath: "/tmp/Gaussians/room.json")))
    }

    func test_editorGaussianLoadPlanUsesResidentProgressiveForTierSets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory

        let lod0 = directory.appendingPathComponent("chair_lod0.untoldgs")
        let lod1 = directory.appendingPathComponent("chair_lod1.untoldgs")
        FileManager.default.createFile(atPath: lod0.path, contents: Data())
        FileManager.default.createFile(atPath: lod1.path, contents: Data())

        XCTAssertEqual(
            editorGaussianLoadPlan(for: lod1),
            .progressive(
                baseFilename: directory.appendingPathComponent("chair").path,
                levelCount: 2,
                maxDistances: [5, .greatestFiniteMagnitude]
            )
        )
    }

    func test_editorGaussianLoadPlanAcceptsCustomProgressiveDistances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory

        let lod0 = directory.appendingPathComponent("chair_lod0.untoldgs")
        let lod1 = directory.appendingPathComponent("chair_lod1.untoldgs")
        let lod2 = directory.appendingPathComponent("chair_lod2.untoldgs")
        FileManager.default.createFile(atPath: lod0.path, contents: Data())
        FileManager.default.createFile(atPath: lod1.path, contents: Data())
        FileManager.default.createFile(atPath: lod2.path, contents: Data())

        XCTAssertEqual(
            editorGaussianLoadPlan(for: lod0, maxDistances: [8, 20, 99]),
            .progressive(
                baseFilename: directory.appendingPathComponent("chair").path,
                levelCount: 3,
                maxDistances: [8, 20, .greatestFiniteMagnitude]
            )
        )
    }

    func test_editorNormalizedGaussianLODDistancesKeepsFiniteDistancesIncreasingAndLastInfinite() {
        XCTAssertEqual(editorNormalizedGaussianLODDistances([10, 5, 30], levelCount: 3), [10, 10.001, .greatestFiniteMagnitude])
        XCTAssertEqual(editorNormalizedGaussianLODDistances([.infinity], levelCount: 2), [Float.leastNonzeroMagnitude, .greatestFiniteMagnitude])
        XCTAssertEqual(editorNormalizedGaussianLODDistances([], levelCount: 0), [])
    }

    func test_editorNormalizedGaussianStreamingSettingsKeepsUnloadBeyondLoadRadius() {
        let normalized = editorNormalizedGaussianStreamingSettings(
            EditorGaussianStreamingSettings(streamingRadius: 40, unloadRadius: 20, priority: 3)
        )

        XCTAssertEqual(normalized.streamingRadius, 40)
        XCTAssertEqual(normalized.unloadRadius, 40.001, accuracy: 0.0001)
        XCTAssertEqual(normalized.priority, 3)
    }

    func test_sheetWithoutSourcesCannotCook() {
        let ply = URL(fileURLWithPath: "/tmp/Gaussians/room.PLY")
        let baked = URL(fileURLWithPath: "/tmp/Gaussians/room.untoldgs")
        let settings = GaussianCookSettings()

        XCTAssertEqual(gaussianCookSheetTitle(for: []), "Select .ply files to cook")
        XCTAssertEqual(gaussianCookSheetTitle(for: [ply]), "Cook room.PLY to .untoldgs")
        XCTAssertEqual(gaussianCookSheetTitle(for: [ply, ply]), "Cook 2 .ply files to .untoldgs")

        XCTAssertFalse(gaussianCookSheetCanCook(sourceURLs: [], settings: settings), "nothing to cook")
        XCTAssertTrue(gaussianCookSheetCanCook(sourceURLs: [ply], settings: settings))
        var collapsed = settings
        collapsed.scale = 0
        XCTAssertFalse(gaussianCookSheetCanCook(sourceURLs: [ply], settings: collapsed), "a zero scale still blocks the cook")

        XCTAssertEqual(
            gaussianCookSourceCaption(sourceURLs: [], sourceSplatCount: nil, maxSplatCount: settings.cookOptions.maxSplatCount),
            "No .ply file selected; nothing to cook."
        )
        XCTAssertEqual(
            gaussianCookSourceCaption(sourceURLs: [ply], sourceSplatCount: 1000, maxSplatCount: 5000),
            gaussianBudgetCaption(sourceCount: 1000, maxSplatCount: 5000)
        )

        // The browser presents the sheet for a request, and a request needs a .ply.
        XCTAssertNil(GaussianCookRequest(sources: []))
        XCTAssertNil(GaussianCookRequest(sources: [baked]), "baked files are imported as they are")
        XCTAssertEqual(GaussianCookRequest(sources: [baked, ply])?.sourceURLs, [ply])
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

    // MARK: - Recenter

    func test_recenterTranslationFollowsTheMode() {
        let boundsMin = simd_float3(0.8, 0, 0.4)
        let boundsMax = simd_float3(1.3, 0.9, 0.9)

        let grounded = gaussianRecenterTranslation(boundsMin: boundsMin, boundsMax: boundsMax, transform: matrix_identity_float4x4, mode: .baseOnGround)
        XCTAssertEqual(grounded.x, -1.05, accuracy: 1e-6)
        XCTAssertEqual(grounded.y, 0, accuracy: 1e-6)
        XCTAssertEqual(grounded.z, -0.65, accuracy: 1e-6)

        let centred = gaussianRecenterTranslation(boundsMin: boundsMin, boundsMax: boundsMax, transform: matrix_identity_float4x4, mode: .centreAtOrigin)
        XCTAssertEqual(centred.x, -1.05, accuracy: 1e-6)
        XCTAssertEqual(centred.y, -0.45, accuracy: 1e-6)
        XCTAssertEqual(centred.z, -0.65, accuracy: 1e-6)

        // The offset is measured after the flip and scale: diag(0.5, -0.5, -0.5) maps the
        // box to x [0.4, 0.65], y [-0.45, 0], z [-0.45, -0.2].
        let flipped = simd_float4x4(diagonal: [0.5, -0.5, -0.5, 1])
        let groundedFlipped = gaussianRecenterTranslation(boundsMin: boundsMin, boundsMax: boundsMax, transform: flipped, mode: .baseOnGround)
        XCTAssertEqual(groundedFlipped.x, -0.525, accuracy: 1e-6)
        XCTAssertEqual(groundedFlipped.y, 0.45, accuracy: 1e-6)
        XCTAssertEqual(groundedFlipped.z, 0.325, accuracy: 1e-6)
    }

    func test_recenterBakesTheTranslationAfterFlipAndScale() {
        var settings = GaussianCookSettings()
        settings.flipYZ = true
        settings.scale = 0.5
        settings.recenter = true
        settings.recenterMode = .baseOnGround
        let bounds = (min: simd_float3(0.8, 0, 0.4), max: simd_float3(1.3, 0.9, 0.9))

        let transform = settings.cookOptions(recenteringBounds: bounds).transform
        XCTAssertEqual(transform.columns.0.x, 0.5)
        XCTAssertEqual(transform.columns.1.y, -0.5)
        XCTAssertEqual(transform.columns.2.z, -0.5)
        XCTAssertEqual(transform.columns.3.x, -0.525, accuracy: 1e-6)
        XCTAssertEqual(transform.columns.3.y, 0.45, accuracy: 1e-6)
        XCTAssertEqual(transform.columns.3.z, 0.325, accuracy: 1e-6)

        // The lowest corner of the source box lands on the ground, centred on X and Z.
        let lowest = simd_mul(transform, simd_float4(0.8, 0.9, 0.9, 1))
        XCTAssertEqual(lowest.y, 0, accuracy: 1e-6)

        // Off, or without bounds, nothing moves.
        XCTAssertEqual(settings.cookOptions.transform.columns.3, simd_float4(0, 0, 0, 1))
        settings.recenter = false
        XCTAssertEqual(settings.cookOptions(recenteringBounds: bounds).transform.columns.3, simd_float4(0, 0, 0, 1))
        XCTAssertEqual(gaussianCookTaskDetail(settings: settings), "→ .untoldgs")
        settings.recenter = true
        XCTAssertEqual(gaussianCookTaskDetail(settings: settings), "→ .untoldgs, recentred")
    }

    func test_sourceBoundsComeFromTheSplatCentres() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let plyURL = directory.appendingPathComponent("grid.ply")
        try makeTestPLY(splatCount: 200).write(to: plyURL)

        let bounds = try gaussianSourceBounds(plyURL: plyURL)
        XCTAssertEqual(bounds.min, simd_float3(0, 0, 0))
        XCTAssertEqual(bounds.max.x, 0.9, accuracy: 1e-6)
        XCTAssertEqual(bounds.max.y, 0.9, accuracy: 1e-6)
        XCTAssertEqual(bounds.max.z, 0.1, accuracy: 1e-6)
    }

    func test_recentredCookWritesCentredSplats() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let plyURL = directory.appendingPathComponent("grid.ply")
        try makeTestPLY(splatCount: 200).write(to: plyURL)

        var settings = GaussianCookSettings()
        settings.recenter = true
        settings.recenterMode = .baseOnGround
        let result = try cookGaussianPLY(plyURL: plyURL, settings: settings)

        // The stored splat-centre bounds: x and z centred on 0, lowest y on 0.
        let header = try UntoldGSFormat.readHeaderV3(from: XCTUnwrap(result.tiers.first).url)
        XCTAssertEqual((header.boundsMin.x + header.boundsMax.x) / 2, 0, accuracy: 1e-3)
        XCTAssertEqual((header.boundsMin.z + header.boundsMax.z) / 2, 0, accuracy: 1e-3)
        XCTAssertEqual(header.boundsMin.y, 0, accuracy: 1e-3)
        XCTAssertEqual(header.boundsMax.y, 0.9, accuracy: 1e-3)
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
