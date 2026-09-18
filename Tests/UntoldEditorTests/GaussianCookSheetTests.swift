//
//  GaussianCookSheetTests.swift
//  UntoldEditorTests
//
//  The "Cook to .untoldgs" path: settings → engine cook options, the bake beside the
//  source .ply/.spz, the Tasks-panel wrapper the browser runs cooks through, progressive
//  tier detection for placement, and the sheet's empty state (nothing selected).
//

import Compression
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

    /// Same cook path as `test_cookWritesTiersBesideTheSource`, but from a `.spz` source --
    /// confirms `cookGaussianPLY` dispatches to the engine's `spzURL:` overload correctly,
    /// not just the `.ply` one.
    func test_cookWritesTiersBesideTheSourceSPZ() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let spzURL = directory.appendingPathComponent("chair.spz")
        try makeTestSPZ(splatCount: 200).write(to: spzURL)

        var settings = GaussianCookSettings()
        settings.levelCount = 2
        let result = try cookGaussianPLY(plyURL: spzURL, settings: settings)

        XCTAssertEqual(result.tiers.count, 2)
        XCTAssertEqual(result.tiers.map(\.url.lastPathComponent), ["chair_lod0.untoldgs", "chair_lod1.untoldgs"])
        XCTAssertEqual(result.cookReport.inputSplatCount, 200)
        for tier in result.tiers {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tier.url.path))
            XCTAssertNoThrow(try UntoldGSFormat.readHeader(from: tier.url))
        }
    }

    func test_sourceBoundsComeFromTheSpzSplatCentres() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let spzURL = directory.appendingPathComponent("grid.spz")
        try makeTestSPZ(splatCount: 200).write(to: spzURL)

        // Bounds must come back finite and non-degenerate; unlike the .ply fixture (whose
        // grid coordinates are asserted exactly in test_sourceBoundsComeFromTheSplatCentres),
        // .spz's RUB->RDF flip and 24-bit position quantization make an exact-value
        // comparison pointless here -- SPZReader's own byte-level correctness is covered by
        // UntoldEngine's SPZReaderTest. This only checks gaussianSourceBounds dispatches to
        // the .spz reader at all instead of throwing or silently reading nothing.
        let bounds = try gaussianSourceBounds(plyURL: spzURL)
        XCTAssertTrue(bounds.min.x.isFinite && bounds.max.x.isFinite)
        XCTAssertLessThanOrEqual(bounds.min.x, bounds.max.x)
        XCTAssertLessThanOrEqual(bounds.min.y, bounds.max.y)
        XCTAssertLessThanOrEqual(bounds.min.z, bounds.max.z)
    }

    func test_importBatchHelpers() {
        let ply = URL(fileURLWithPath: "/tmp/Gaussians/room.PLY")
        let spz = URL(fileURLWithPath: "/tmp/Gaussians/room.SPZ")
        let baked = URL(fileURLWithPath: "/tmp/Gaussians/room.untoldgs")
        XCTAssertEqual(gaussianSourcesToCook(in: [baked, ply]), [ply], "only .ply/.spz sources are cooked, any case")
        XCTAssertEqual(gaussianSourcesToCook(in: [baked, spz]), [spz])
        XCTAssertEqual(gaussianSourcesToCook(in: [baked, ply, spz]), [ply, spz])
        XCTAssertEqual(gaussianSourcesToCook(in: [baked]), [])

        XCTAssertEqual(gaussianCookSheetSourceName(for: [ply]), "room.PLY")
        XCTAssertEqual(gaussianCookSheetSourceName(for: [ply, ply]), "2 Gaussian splat files")

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

        XCTAssertEqual(gaussianCookSheetTitle(for: []), "Select .ply/.spz files to cook")
        XCTAssertEqual(gaussianCookSheetTitle(for: [ply]), "Cook room.PLY to .untoldgs")
        XCTAssertEqual(gaussianCookSheetTitle(for: [ply, ply]), "Cook 2 Gaussian splat files to .untoldgs")

        XCTAssertFalse(gaussianCookSheetCanCook(sourceURLs: [], settings: settings), "nothing to cook")
        XCTAssertTrue(gaussianCookSheetCanCook(sourceURLs: [ply], settings: settings))
        var collapsed = settings
        collapsed.scale = 0
        XCTAssertFalse(gaussianCookSheetCanCook(sourceURLs: [ply], settings: collapsed), "a zero scale still blocks the cook")

        XCTAssertEqual(
            gaussianCookSourceCaption(sourceURLs: [], sourceSplatCount: nil, maxSplatCount: settings.cookOptions.maxSplatCount),
            "No .ply/.spz file selected; nothing to cook."
        )
        XCTAssertEqual(
            gaussianCookSourceCaption(sourceURLs: [ply], sourceSplatCount: 1000, maxSplatCount: 5000),
            gaussianBudgetCaption(sourceCount: 1000, maxSplatCount: 5000)
        )

        // The browser presents the sheet for a request, and a request needs a .ply/.spz.
        XCTAssertNil(GaussianCookRequest(sources: []))
        XCTAssertNil(GaussianCookRequest(sources: [baked]), "baked files are imported as they are")
        XCTAssertEqual(GaussianCookRequest(sources: [baked, ply])?.sourceURLs, [ply])
        let spz = URL(fileURLWithPath: "/tmp/Gaussians/room.spz")
        XCTAssertEqual(GaussianCookRequest(sources: [baked, spz])?.sourceURLs, [spz])
    }

    func test_trackedCookSucceedsAsATask() async throws {
        let plyURL = try makeTemporaryPLY(named: "chair.ply", splatCount: 200)
        var settings = GaussianCookSettings()
        settings.levelCount = 2

        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let reports = GaussianCookReportLog()
        let handle = cookGaussianPLYTracked(plyURL: plyURL, settings: settings, control: UntoldGSCookControl(progress: { reports.append($0) })) { result in
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
        XCTAssertEqual(task.progress, 1, "the engine's reports drive the row's bar to the end")
        XCTAssertFalse(task.isCancellable)
        XCTAssertEqual(task.detail, "Kept 200 of 200 splats")

        // The engine reported every phase in order, once per tier past the cook, and its
        // overall fraction never went back.
        let progress = reports.entries
        XCTAssertEqual(progress.first?.phase, .read)
        XCTAssertEqual(progress.last?.phase, .write)
        XCTAssertEqual(progress.last?.overall, 1)
        XCTAssertEqual(progress.last?.tierIndex, 1)
        XCTAssertEqual(Set(progress.map(\.tierCount)), [2])
        XCTAssertTrue(progress.contains { $0.phase == .cook })
        XCTAssertTrue(progress.contains { $0.phase == .chunk && $0.tierIndex == 0 })
        XCTAssertTrue(progress.contains { $0.phase == .chunk && $0.tierIndex == 1 })
        for (earlier, later) in zip(progress, progress.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.overall, later.overall, "\(earlier) then \(later)")
        }
    }

    /// Same Tasks-panel wiring as `test_trackedCookSucceedsAsATask`, from a `.spz` source --
    /// `cookGaussianPLYTracked` is format-agnostic (it delegates to `cookGaussianPLY`), so a
    /// `.spz` cook should report through `TaskCenter` identically to a `.ply` one: same
    /// title/detail shape, the engine's reports on the row's bar (the `.spz` is decoded whole,
    /// so its read reports once, then the cook and every tier), succeeded state.
    func test_trackedCookSucceedsAsATaskSPZ() async throws {
        let directory = try temporaryDirectory ?? {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            temporaryDirectory = url
            return url
        }()
        let spzURL = directory.appendingPathComponent("chair.spz")
        try makeTestSPZ(splatCount: 200).write(to: spzURL)
        var settings = GaussianCookSettings()
        settings.levelCount = 2

        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let reports = GaussianCookReportLog()
        let handle = cookGaussianPLYTracked(plyURL: spzURL, settings: settings, control: UntoldGSCookControl(progress: { reports.append($0) })) { result in
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
        XCTAssertEqual(task.title, "Cooking chair.spz")
        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.progress, 1, "the engine's spz overload reports through the control too")
        XCTAssertFalse(task.isCancellable)
        XCTAssertEqual(task.detail, "Kept 200 of 200 splats")

        let progress = reports.entries
        XCTAssertEqual(progress.first?.phase, .read)
        XCTAssertEqual(progress.last?.phase, .write)
        XCTAssertEqual(progress.last?.overall, 1)
        XCTAssertEqual(progress.last?.tierIndex, 1)
        XCTAssertTrue(progress.contains { $0.phase == .cook })
        for (earlier, later) in zip(progress, progress.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.overall, later.overall, "\(earlier) then \(later)")
        }
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

    func test_trackedCookCanBeCancelledWhileQueued() async throws {
        let plyURL = try makeTemporaryPLY(named: "queued.ply", splatCount: 20)
        let queue = DispatchQueue(label: "GaussianCookSheetTests.blocked")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() } // holds the queue as a running cook would

        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let handle = cookGaussianPLYTracked(plyURL: plyURL, settings: GaussianCookSettings(), queue: queue) { result in
            completionResult = result
            finished.fulfill()
        }
        await settleTaskCenter()
        let queuedTask = await trackedTask(handle.id)
        let queued = try XCTUnwrap(queuedTask)
        XCTAssertEqual(queued.state, .running)
        XCTAssertTrue(queued.isCancellable, "a cook waiting for the queue can be cancelled")
        XCTAssertEqual(queued.detail, "Waiting for the cook queue → .untoldgs")

        await MainActor.run { TaskCenter.shared.cancel(handle.id) }
        gate.signal()
        await fulfillment(of: [finished], timeout: 30)
        await settleTaskCenter()

        guard case let .failure(error)? = completionResult else {
            return XCTFail("expected the cancelled cook to complete with an error")
        }
        XCTAssertEqual(error as? GaussianCookCancelledError, GaussianCookCancelledError(stage: .queued))
        XCTAssertEqual(gaussianCookFailureDetail(error), "Cancelled before it started")
        let cancelledTask = await trackedTask(handle.id)
        let cancelled = try XCTUnwrap(cancelledTask)
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.detail, "Cancelled before it started")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plyURL.deletingPathExtension().appendingPathExtension("untoldgs").path), "nothing was written")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plyURL.path))
    }

    func test_runningCookCancelledFromTheTasksPanelLeavesNothingWritten() async throws {
        // Two tiers: the cancel lands at the first report of the second, when the first tier
        // is already complete in its temporary file — the engine must remove it.
        let plyURL = try makeTemporaryPLY(named: "running.ply", splatCount: 200)
        var settings = GaussianCookSettings()
        settings.levelCount = 2
        let queue = DispatchQueue(label: "GaussianCookSheetTests.running")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() } // the row is registered before the bake can start

        let cancelRequests = GaussianCookReportLog()
        let cancelOnSecondTier = UntoldGSCookControl(progress: { progress in
            guard progress.tierIndex == 1, cancelRequests.entries.isEmpty else { return }
            cancelRequests.append(progress)
            // What the Tasks panel's cancel button does, from the cooking thread.
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    for task in TaskCenter.shared.tasks where task.title == "Cooking running.ply" && task.isActive {
                        TaskCenter.shared.cancel(task.id)
                    }
                }
            }
        })

        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let handle = cookGaussianPLYTracked(plyURL: plyURL, settings: settings, queue: queue, control: cancelOnSecondTier) { result in
            completionResult = result
            finished.fulfill()
        }
        await settleTaskCenter()
        gate.signal()
        await fulfillment(of: [finished], timeout: 30)
        await settleTaskCenter()

        XCTAssertEqual(cancelRequests.entries.count, 1, "the cancel was requested while the bake ran")
        guard case let .failure(error)? = completionResult else {
            return XCTFail("expected the cancelled cook to complete with an error")
        }
        XCTAssertEqual(error as? GaussianCookCancelledError, GaussianCookCancelledError(stage: .running))
        XCTAssertEqual(gaussianCookFailureDetail(error), "Cancelled; nothing was written")
        let taskID = handle.id
        let cancelledTask = await MainActor.run { TaskCenter.shared.tasks.first { $0.id == taskID } }
        let cancelled = try XCTUnwrap(cancelledTask)
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.detail, "Cancelled; nothing was written")
        XCTAssertLessThan(cancelled.progress ?? 1, 1, "the bar stopped short of the end")
        // Neither a tier nor a staged temporary is left beside the source.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: plyURL.deletingLastPathComponent().path), ["running.ply"])
    }

    func test_cancelledCookLeavesNoFileBehind() throws {
        // The direct call with the engine's control: cancelled in the second tier's chunk phase
        // — the first tier staged, nothing published — it throws the engine's error and the
        // directory holds the source alone.
        let plyURL = try makeTemporaryPLY(named: "direct.ply", splatCount: 200)
        var settings = GaussianCookSettings()
        settings.levelCount = 2
        let seen = GaussianCookReportLog()
        let control = UntoldGSCookControl(
            progress: { seen.append($0) },
            isCancelled: { seen.entries.contains { $0.tierIndex == 1 } }
        )
        XCTAssertThrowsError(try cookGaussianPLY(plyURL: plyURL, settings: settings, control: control)) { error in
            XCTAssertEqual(error as? UntoldGSCookError, .cancelled)
        }
        XCTAssertTrue(seen.entries.contains { $0.tierIndex == 1 && $0.phase == .chunk }, "the bake reached the second tier")
        XCTAssertFalse(seen.entries.contains { $0.tierIndex == 1 && $0.phase == .write && $0.fraction == 1 }, "and stopped before writing it")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: plyURL.deletingLastPathComponent().path), ["direct.ply"])
    }

    func test_runningDetailNamesTheSizeAndTheSettings() {
        var settings = GaussianCookSettings()
        XCTAssertEqual(gaussianCookRunningDetail(settings: settings, sourceSplatCount: 10_000_000), "Cooking 10,000,000 splats → .untoldgs")
        settings.levelCount = 2
        settings.recenter = true
        XCTAssertEqual(gaussianCookRunningDetail(settings: settings, sourceSplatCount: 200), "Cooking 200 splats 2 progressive tiers → .untoldgs, recentred")
        XCTAssertEqual(gaussianCookRunningDetail(settings: GaussianCookSettings(), sourceSplatCount: nil), "Cooking → .untoldgs")
        XCTAssertEqual(gaussianCookTaskDetailSuffix(settings: settings), "→ .untoldgs, recentred")
        XCTAssertEqual(gaussianCookTaskDetail(settings: settings), "2 progressive tiers → .untoldgs, recentred")
    }

    func test_progressDetailNamesThePhaseAndTheTier() {
        var settings = GaussianCookSettings()
        func detail(_ phase: UntoldGSCookPhase, tier: Int = 0, of tierCount: Int = 1, splats: Int? = 10_000_000) -> String {
            gaussianCookProgressDetail(
                UntoldGSCookProgress(phase: phase, fraction: 0.5, overall: 0.5, tierIndex: tier, tierCount: tierCount),
                settings: settings,
                sourceSplatCount: splats
            )
        }
        XCTAssertEqual(detail(.read), "Reading 10,000,000 splats → .untoldgs")
        XCTAssertEqual(detail(.cook), "Cooking 10,000,000 splats → .untoldgs")
        XCTAssertEqual(detail(.read, splats: nil), "Reading → .untoldgs", "a header the reader could not count")
        XCTAssertEqual(detail(.chunk), "Chunking → .untoldgs", "a single tier is not numbered")
        XCTAssertEqual(detail(.coarsen), "Coarsening → .untoldgs")
        XCTAssertEqual(detail(.write), "Writing → .untoldgs")

        settings.levelCount = 3
        settings.coarseLevels = .two
        XCTAssertEqual(detail(.read, of: 3), "Reading 10,000,000 splats → .untoldgs, 2 coarse levels", "the source phases name no tier")
        XCTAssertEqual(detail(.chunk, tier: 0, of: 3), "Chunking tier 1 of 3 → .untoldgs, 2 coarse levels")
        XCTAssertEqual(detail(.coarsen, tier: 1, of: 3), "Coarsening tier 2 of 3 → .untoldgs, 2 coarse levels")
        XCTAssertEqual(detail(.write, tier: 2, of: 3), "Writing tier 3 of 3 → .untoldgs, 2 coarse levels")

        settings = GaussianCookSettings()
        settings.recenter = true
        settings.splatBudget = .visionPro
        XCTAssertEqual(detail(.write), "Writing → .untoldgs, recentred, budget \(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMobile))")
    }

    func test_progressReporterThrottlesAndKeepsTheFractionMonotonic() {
        var clock: TimeInterval = 100
        var delivered: [(fraction: Double, detail: String)] = []
        let reporter = GaussianCookProgressReporter(
            now: { clock },
            detail: { "\($0.phase.rawValue) \($0.tierIndex)" },
            deliver: { delivered.append(($0, $1)) }
        )
        func report(_ phase: UntoldGSCookPhase, _ fraction: Float, overall: Float, tier: Int = 0, at time: TimeInterval) -> Bool {
            clock = time
            return reporter.report(UntoldGSCookProgress(phase: phase, fraction: fraction, overall: overall, tierIndex: tier, tierCount: 2))
        }

        XCTAssertTrue(report(.read, 0, overall: 0, at: 100), "the first report goes through")
        XCTAssertFalse(report(.read, 0.2, overall: 0.07, at: 100.03), "too soon after the last")
        XCTAssertFalse(report(.read, 0.4, overall: 0.14, at: 100.09))
        XCTAssertTrue(report(.read, 0.6, overall: 0.21, at: 100.125), "the interval has passed")
        XCTAssertTrue(report(.read, 1, overall: 0.35, at: 100.13), "the end of a phase always does")
        XCTAssertTrue(report(.cook, 0, overall: 0.35, at: 100.14), "so does a new phase")
        XCTAssertFalse(report(.cook, 0.5, overall: 0.375, at: 100.15))
        XCTAssertTrue(report(.cook, 1, overall: 0.4, at: 100.16))
        XCTAssertTrue(report(.chunk, 0, overall: 0.4, at: 100.17))
        XCTAssertTrue(report(.chunk, 0, overall: 0.7, tier: 1, at: 100.18), "and a new tier of the same phase")
        XCTAssertFalse(report(.chunk, 0.1, overall: 0.6, tier: 1, at: 100.19))
        XCTAssertTrue(report(.chunk, 0.2, overall: 0.65, tier: 1, at: 100.375), "a lower overall after the interval")
        XCTAssertEqual(reporter.fraction, 0.7, accuracy: 1e-6, "is shown as the highest so far")
        XCTAssertTrue(report(.write, 1, overall: 1, tier: 1, at: 100.38))

        XCTAssertEqual(delivered.map(\.detail), ["read 0", "read 0", "read 0", "cook 0", "cook 0", "chunk 0", "chunk 1", "chunk 1", "write 1"])
        for (earlier, later) in zip(delivered, delivered.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier.fraction, later.fraction)
        }
        XCTAssertEqual(delivered.last?.fraction, 1)
        XCTAssertEqual(GaussianCookProgressReporter.minimumInterval, 0.1, "about ten redraws a second")
    }

    // MARK: - Helpers

    /// The engine's reports as a cook makes them, from the cooking thread.
    private final class GaussianCookReportLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _entries: [UntoldGSCookProgress] = []

        var entries: [UntoldGSCookProgress] {
            lock.lock(); defer { lock.unlock() }
            return _entries
        }

        func append(_ progress: UntoldGSCookProgress) {
            lock.lock(); defer { lock.unlock() }
            _entries.append(progress)
        }
    }

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

    // MARK: - Coarse levels

    func test_coarseLevelsMapToTheEnginePolicy() {
        var settings = GaussianCookSettings()
        XCTAssertEqual(settings.coarseLevels, .automatic, "the engine's default: levels for large captures only")
        XCTAssertEqual(settings.cookOptions.coarseLevels, .automatic)
        XCTAssertFalse(gaussianCookTaskDetail(settings: settings).contains("coarse"), "the default is not named in the task row")

        settings.coarseLevels = .off
        XCTAssertEqual(settings.cookOptions.coarseLevels, .off)
        XCTAssertTrue(gaussianCookTaskDetail(settings: settings).hasSuffix(", no coarse levels"))

        settings.coarseLevels = .one
        XCTAssertEqual(settings.cookOptions.coarseLevels, .levels(count: 1))
        XCTAssertTrue(gaussianCookTaskDetail(settings: settings).hasSuffix(", 1 coarse level"))

        settings.coarseLevels = .two
        XCTAssertEqual(settings.cookOptions.coarseLevels, .levels(count: 2))
        XCTAssertTrue(gaussianCookTaskDetail(settings: settings).hasSuffix(", 2 coarse levels"))

        XCTAssertEqual(GaussianCoarseLevelChoice.allCases.map(\.label), ["Auto", "Off", "1", "2"])
        XCTAssertTrue(GaussianCoarseLevelChoice.summary.contains("\(UntoldGSFormat.coarseLevelsAutomaticMinimumChunks) chunks"))
    }

    func test_cookSummaryReportsTheCoarseLevelsBaked() {
        let report = UntoldGSCookReport(inputSplatCount: 200, keptSplatCount: 200, prunedByOpacity: 0, prunedByDegenerateGeometry: 0, prunedByCrop: 0, shDegree: 0)
        XCTAssertEqual(gaussianCookSummary(report), "Kept 200 of 200 splats", "without tier reports the summary is unchanged")
        XCTAssertEqual(gaussianCookSummary(report, coarse: [nil]), "Kept 200 of 200 splats", "a bake without a section keeps the short row")

        let coarse = UntoldGSCoarseLevelReport(levelCount: 2, ratioLog2: [3, 6], recordsPerLevel: [1_249_000, 156_000], bytes: 22_500_000, chunksWithoutLevels: 0)
        XCTAssertEqual(gaussianCookSummary(report, coarse: [coarse]), "Kept 200 of 200 splats; 2 coarse levels (21.46 MiB)")
        XCTAssertEqual(
            gaussianCookSummary(report, coarse: [coarse, nil]),
            "Kept 200 of 200 splats; 2 coarse levels on 1 of 2 tiers (21.46 MiB)",
            "a progressive bake resolves the policy per tier"
        )
        var single = coarse
        single.levelCount = 1
        single.bytes = 4096
        XCTAssertEqual(gaussianCookSummary(report, coarse: [single]), "Kept 200 of 200 splats; 1 coarse level (4.00 KiB)")

        XCTAssertEqual(gaussianCookFormatBytes(512), "512 B")
        XCTAssertEqual(gaussianCookFormatBytes(1536), "1.50 KiB")
    }

    func test_forcedCoarseLevelsBakeOnASmallCapture() async throws {
        // One chunk of 200 splats is far below Auto's 64-chunk threshold, so Auto and Off bake
        // no section and only a forced choice does: level 1 holds 200 >> 3 = 25 merged records.
        let plyURL = try makeTemporaryPLY(named: "chair.ply", splatCount: 200)
        var settings = GaussianCookSettings()
        XCTAssertNil(try cookGaussianPLY(plyURL: plyURL, settings: settings).tiers[0].coarseReport, "Auto: below the threshold")
        settings.coarseLevels = .off
        XCTAssertNil(try cookGaussianPLY(plyURL: plyURL, settings: settings).tiers[0].coarseReport)

        settings.coarseLevels = .one
        let finished = expectation(description: "completion on main")
        var completionResult: Result<GaussianProgressiveBakeResult, Error>?
        let handle = cookGaussianPLYTracked(plyURL: plyURL, settings: settings) { result in
            completionResult = result
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 30)
        await settleTaskCenter()

        let bake = try XCTUnwrap(completionResult?.get())
        let coarse = try XCTUnwrap(bake.tiers[0].coarseReport, "a forced level is baked whatever the size")
        XCTAssertEqual(coarse.levelCount, 1)
        XCTAssertEqual(coarse.recordsPerLevel, [25])
        XCTAssertEqual(coarse.chunksWithoutLevels, 0)
        XCTAssertGreaterThan(coarse.bytes, 0)

        let tracked = await trackedTask(handle.id)
        let task = try XCTUnwrap(tracked)
        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.detail, "Kept 200 of 200 splats; 1 coarse level (\(gaussianCookFormatBytes(coarse.bytes)))")
        XCTAssertEqual(gaussianCookTaskDetail(settings: settings), "→ .untoldgs, 1 coarse level")
    }

    // MARK: - Cost captions

    func test_sourceInfoReadsTheHeaderOnly() throws {
        let plyURL = try makeTemporaryPLY(named: "chair.ply", splatCount: 200)
        let info = try GaussianCookSourceInfo.read(from: plyURL)
        XCTAssertEqual(info.splatCount, 200)
        XCTAssertEqual(info.shDegree, 0, "the fixture carries no f_rest_* block")

        func header(rest: Int) -> Data {
            var text = "ply\nformat binary_little_endian 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n"
            for index in 0 ..< rest {
                text += "property float f_rest_\(index)\n"
            }
            text += "property float opacity\nend_header\n"
            return Data(text.utf8)
        }
        XCTAssertEqual(GaussianCookSourceInfo.shDegree(fromHeaderPrefix: header(rest: 0)), 0)
        XCTAssertEqual(GaussianCookSourceInfo.shDegree(fromHeaderPrefix: header(rest: 9)), 1)
        XCTAssertEqual(GaussianCookSourceInfo.shDegree(fromHeaderPrefix: header(rest: 24)), 2)
        XCTAssertEqual(GaussianCookSourceInfo.shDegree(fromHeaderPrefix: header(rest: 45)), 3)
    }

    func test_sourceInfoDecodesTheSpzWhole() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let spzURL = directory.appendingPathComponent("chair.spz")
        try makeTestSPZ(splatCount: 200).write(to: spzURL)

        // No header-only path for .spz: the count and degree come out of the whole decode,
        // the same the sheet's task pays for its captions.
        let info = try GaussianCookSourceInfo.read(from: spzURL)
        XCTAssertEqual(info.splatCount, 200)
        XCTAssertEqual(info.shDegree, 0, "the fixture is a degree-0 legacy payload")
        XCTAssertNotNil(gaussianCookMemoryCaption(splatCount: info.splatCount, shDegree: info.shDegree))
    }

    func test_memoryCaptionSizesTheCompactStore() {
        // The 10 M-splat degree-3 capture: 56 + 45 bytes per splat in the store, half as much
        // again in flight — about 1.4 GB, where the whole-file reader peaked at 9.9 GiB.
        XCTAssertEqual(gaussianCookStoreBytesPerSplat, 56)
        XCTAssertEqual(gaussianCookEstimatedPeakBytes(splatCount: 10_000_000, shDegree: 3), 10_000_000 * 101 * 3 / 2)
        XCTAssertEqual(gaussianCookEstimatedPeakBytes(splatCount: 1_000_000, shDegree: 0), 1_000_000 * 56 * 3 / 2)
        XCTAssertEqual(gaussianCookEstimatedPeakBytes(splatCount: 1000, shDegree: 1), 1000 * 65 * 3 / 2)
        XCTAssertEqual(gaussianCookEstimatedPeakBytes(splatCount: 1000, shDegree: 7), 1000 * 101 * 3 / 2, "clamped to the format's top degree")
        XCTAssertEqual(
            gaussianCookMemoryCaption(splatCount: 10_000_000, shDegree: 3, physicalMemory: 128 << 30),
            "The cook needs about 1.4 GB of memory (this Mac has 128.0 GB)."
        )
        XCTAssertEqual(
            gaussianCookMemoryCaption(splatCount: 10_000_000, shDegree: 3, physicalMemory: 8 << 30),
            "The cook needs about 1.4 GB of memory (this Mac has 8.0 GB).",
            "an 8 GB Mac cooks the capture without swapping"
        )
        XCTAssertEqual(
            gaussianCookMemoryCaption(splatCount: 10_000_000, shDegree: 3, physicalMemory: 1 << 30),
            "The cook needs about 1.4 GB of memory (this Mac has 1.0 GB); expect heavy swapping — close other apps or cook on a Mac with more memory."
        )
        XCTAssertEqual(
            gaussianCookMemoryCaption(splatCount: 1_000_000, shDegree: 0, physicalMemory: 8 << 30),
            "The cook needs about 80 MB of memory (this Mac has 8.0 GB)."
        )
        XCTAssertNil(gaussianCookMemoryCaption(splatCount: 0, shDegree: 3, physicalMemory: 8 << 30))
        XCTAssertEqual(gaussianCookFormatGiB(512 << 20), "512 MB")
    }

    func test_runtimeCaptionTellsPagedFromWholeLoads() {
        // 10 M kept splats at degree 3: 16 + 45 bytes each, 582 MiB, above the Mac threshold.
        let paged = gaussianCookRuntimeCaption(keptSplatCount: 10_000_000, shDegree: 3, residencyBudgetBytes: 1 << 30, pagePoolMaxBytes: 1 << 30, workingSetSplats: 6_000_000)
        XCTAssertEqual(paged, "About 582 MB of packed splats at runtime: pages from disk (above 512 MB) through a 582 MB pool; the frame draws at most 6,000,000 splats.")
        // The pool is capped by the residency budget (a quarter of the geometry budget).
        let smallBudget = gaussianCookRuntimeCaption(keptSplatCount: 10_000_000, shDegree: 3, residencyBudgetBytes: 300 << 20, pagePoolMaxBytes: 1 << 30, workingSetSplats: 3_000_000)
        XCTAssertTrue(smallBudget.contains("pages from disk (above 300 MB) through a 300 MB pool; the frame draws at most 3,000,000 splats."), smallBudget)
        // 1 M splats without SH: 16 MiB, loads whole.
        let whole = gaussianCookRuntimeCaption(keptSplatCount: 1_000_000, shDegree: 0, residencyBudgetBytes: 1 << 30, pagePoolMaxBytes: 1 << 30, workingSetSplats: 6_000_000)
        XCTAssertEqual(whole, "About 15 MB of packed splats at runtime: loads whole (below 512 MB); the frame draws at most 6,000,000 splats.")
        // View > Splat Debug > Force Splat Paging zeroes the threshold: the same file pages.
        let savedOverride = GaussianPagingPolicy.pagingThresholdBytesOverride
        defer { GaussianPagingPolicy.pagingThresholdBytesOverride = savedOverride }
        GaussianPagingPolicy.pagingThresholdBytesOverride = 0
        let forced = gaussianCookRuntimeCaption(keptSplatCount: 1_000_000, shDegree: 0, residencyBudgetBytes: 1 << 30, pagePoolMaxBytes: 1 << 30, workingSetSplats: 6_000_000)
        XCTAssertEqual(forced, "About 15 MB of packed splats at runtime: pages from disk (Force Splat Paging is on) through a 15 MB pool; the frame draws at most 6,000,000 splats.")
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

        // The same box the engine's streamed pass reports, and its cull: a source with no
        // splat left is refused the way the bake refuses it.
        let streamed = try XCTUnwrap(PLYReader.readGaussianCenterBounds(from: plyURL))
        XCTAssertEqual(streamed.min, bounds.min)
        XCTAssertEqual(streamed.max, bounds.max)
        let emptyURL = directory.appendingPathComponent("empty.ply")
        try makeTestPLY(splatCount: 0).write(to: emptyURL)
        XCTAssertThrowsError(try gaussianSourceBounds(plyURL: emptyURL)) { error in
            XCTAssertEqual((error as? UntoldGSError)?.description, UntoldGSError.sizeMismatch("source .ply contains no splats").description)
        }
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

    /// A minimal legacy SPZ v2 fixture (gzip-wrapped, first-three quaternion, degree-0 SH,
    /// no fractional bits so raw position ints are the float values directly) on the same
    /// grid `makeTestPLY` uses. Only exercises the cook path's format dispatch -- SPZReader's
    /// own byte-level decode correctness is covered by UntoldEngine's SPZReaderTest, so this
    /// doesn't need real capture data, just something that decodes to `splatCount` splats.
    private func makeTestSPZ(splatCount: Int) -> Data {
        var positions: [UInt8] = []
        var alphas: [UInt8] = []
        var colors: [UInt8] = []
        var scales: [UInt8] = []
        var rotations: [UInt8] = []
        positions.reserveCapacity(splatCount * 9)
        for index in 0 ..< splatCount {
            for value in [Int32(index % 10), Int32(index / 10 % 10), Int32(index / 100)] {
                let unsigned = UInt32(bitPattern: value) & 0x00FF_FFFF
                positions.append(UInt8(unsigned & 0xFF))
                positions.append(UInt8((unsigned >> 8) & 0xFF))
                positions.append(UInt8((unsigned >> 16) & 0xFF))
            }
            alphas.append(255)
            colors.append(contentsOf: [128, 128, 128] as [UInt8])
            scales.append(contentsOf: [160, 160, 160] as [UInt8])
            rotations.append(contentsOf: [127, 127, 127] as [UInt8]) // v2 first-three, near-identity
        }

        var payload: [UInt8] = []
        func appendUInt32LE(_ value: UInt32) {
            payload.append(UInt8(value & 0xFF))
            payload.append(UInt8((value >> 8) & 0xFF))
            payload.append(UInt8((value >> 16) & 0xFF))
            payload.append(UInt8((value >> 24) & 0xFF))
        }
        appendUInt32LE(0x5053_474E) // "NGSP"
        appendUInt32LE(2) // version 2 (first-three quaternion)
        appendUInt32LE(UInt32(splatCount))
        payload.append(contentsOf: [0, 0, 0, 0] as [UInt8]) // shDegree, fractionalBits, flags, reserved
        payload.append(contentsOf: positions)
        payload.append(contentsOf: alphas)
        payload.append(contentsOf: colors)
        payload.append(contentsOf: scales)
        payload.append(contentsOf: rotations)

        let deflateCapacity = payload.count * 2 + 128
        var deflated = [UInt8](repeating: 0, count: deflateCapacity)
        let written = deflated.withUnsafeMutableBytes { destBuffer -> Int in
            payload.withUnsafeBytes { sourceBuffer -> Int in
                compression_encode_buffer(
                    destBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    deflateCapacity,
                    sourceBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        deflated = Array(deflated.prefix(written))

        var gzip: [UInt8] = [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]
        gzip.append(contentsOf: deflated)
        gzip.append(contentsOf: [0, 0, 0, 0] as [UInt8]) // CRC32, unchecked by SPZReader
        let isize = UInt32(payload.count) // ISIZE: the file's final 4 bytes
        gzip.append(UInt8(isize & 0xFF))
        gzip.append(UInt8((isize >> 8) & 0xFF))
        gzip.append(UInt8((isize >> 16) & 0xFF))
        gzip.append(UInt8((isize >> 24) & 0xFF))
        return Data(gzip)
    }
}
