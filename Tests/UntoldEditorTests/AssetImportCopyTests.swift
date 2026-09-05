//
//  AssetImportCopyTests.swift
//  UntoldEditorTests
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
@testable import UntoldEditor
import XCTest

final class AssetImportCopyTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetImportCopyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    func test_stagingURLIsAHiddenSiblingOfTheDestination() {
        let destination = base.appendingPathComponent("Models/robot", isDirectory: true)
        let staging = assetImportStagingURL(for: destination)

        XCTAssertEqual(staging.deletingLastPathComponent().path, destination.deletingLastPathComponent().path)
        XCTAssertTrue(staging.lastPathComponent.hasPrefix(".importing-"))
        XCTAssertTrue(staging.lastPathComponent.hasSuffix("-robot"))
        XCTAssertNotEqual(assetImportStagingURL(for: destination), staging, "each import gets its own staging item")
    }

    func test_trackedImportCopiesThroughStagingAndSucceedsAsATask() async throws {
        let source = base.appendingPathComponent("Downloads/scan.ply")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data("ply".utf8))
        let gaussians = base.appendingPathComponent("Gaussians", isDirectory: true)
        let destination = gaussians.appendingPathComponent("scan.ply")

        let finished = expectation(description: "completion on main")
        var completionResult: Result<URL, Error>?
        var stagingSeen: URL?
        var destinationExistedDuringWork = true
        var progressOnMain: [AssetCopyProgress] = []
        let handle = importAssetTracked(destination: destination, detail: "→ Gaussians/", onProgress: { progress in
            XCTAssertTrue(Thread.isMainThread)
            progressOnMain.append(progress)
        }, work: { ctx in
            XCTAssertFalse(Thread.isMainThread, "the copy must not run on the main thread")
            stagingSeen = ctx.stagingURL
            destinationExistedDuringWork = FileManager.default.fileExists(atPath: destination.path)
            try ctx.copy(source, to: ctx.stagingURL)
        }) { result in
            XCTAssertTrue(Thread.isMainThread)
            completionResult = result
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
        await settleTaskCenter()

        XCTAssertEqual(try completionResult?.get(), destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("ply".utf8))
        XCTAssertFalse(destinationExistedDuringWork, "the item is invisible until the copy is complete")
        XCTAssertEqual(try XCTUnwrap(stagingSeen).deletingLastPathComponent().path, gaussians.path)
        XCTAssertTrue(try XCTUnwrap(stagingSeen).lastPathComponent.hasPrefix("."), "staging is hidden from listings")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: gaussians.path)
        XCTAssertEqual(leftovers, ["scan.ply"], "no staging item is left behind")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "importing copies, it never moves the source")

        let tracked = await trackedTask(handle.id)
        let task = try XCTUnwrap(tracked)
        XCTAssertEqual(task.title, "Importing scan.ply")
        XCTAssertEqual(task.state, .succeeded)
        XCTAssertEqual(task.detail, "Copied scan.ply")
        XCTAssertEqual(task.progress, 1, "the row is a progress bar that ends full")
        XCTAssertFalse(task.isCancellable, "cancel is offered while running, not once finished")
        XCTAssertEqual(progressOnMain.last, AssetCopyProgress(copied: 3, total: 3))
    }

    func test_trackedImportFailureLeavesNoStagingAndNoDestination() async throws {
        struct Boom: LocalizedError { var errorDescription: String? {
            "disk on fire"
        } }
        let hdr = base.appendingPathComponent("HDR", isDirectory: true)
        let destination = hdr.appendingPathComponent("sky.hdr")

        let finished = expectation(description: "completion on main")
        var completionResult: Result<URL, Error>?
        let handle = importAssetTracked(destination: destination, work: { ctx in
            FileManager.default.createFile(atPath: ctx.stagingURL.path, contents: Data("half".utf8))
            throw Boom()
        }) { result in
            completionResult = result
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
        await settleTaskCenter()

        XCTAssertThrowsError(try completionResult?.get())
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: hdr.path), [], "the half-copied staging item is removed")

        let tracked = await trackedTask(handle.id)
        let task = try XCTUnwrap(tracked)
        XCTAssertEqual(task.state, .failed)
        XCTAssertEqual(task.detail, "disk on fire")
    }

    func test_commitMergesAStagedFolderIntoAnExistingOne() throws {
        // Re-importing robot.usdz into Models/robot must keep the robot.untold already cooked there.
        let destination = base.appendingPathComponent("Models/robot", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destination.appendingPathComponent("robot.untold").path, contents: Data("cooked".utf8))
        FileManager.default.createFile(atPath: destination.appendingPathComponent("robot.usdz").path, contents: Data("old".utf8))

        let staging = assetImportStagingURL(for: destination)
        try FileManager.default.createDirectory(at: staging.appendingPathComponent("Textures"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: staging.appendingPathComponent("robot.usdz").path, contents: Data("new".utf8))

        try commitStagedImport(from: staging, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("robot.untold")), Data("cooked".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("robot.usdz")), Data("new".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Textures").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func test_commitReplacesAnExistingFile() throws {
        let destination = base.appendingPathComponent("sky.hdr")
        FileManager.default.createFile(atPath: destination.path, contents: Data("old".utf8))
        let staging = assetImportStagingURL(for: destination)
        FileManager.default.createFile(atPath: staging.path, contents: Data("new".utf8))

        try commitStagedImport(from: staging, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func test_placeholdersAreOnlyThoseInTheFolderAndPastTheDelay() {
        let models = base.appendingPathComponent("Models", isDirectory: true)
        var slow = PendingAssetImport(destinationURL: models.appendingPathComponent("robot", isDirectory: true), isFolder: true)
        slow.showsPlaceholder = true
        let fast = PendingAssetImport(destinationURL: models.appendingPathComponent("chair", isDirectory: true), isFolder: true)
        var elsewhere = PendingAssetImport(destinationURL: base.appendingPathComponent("HDR/sky.hdr"), isFolder: false)
        elsewhere.showsPlaceholder = true

        let shown = placeholderImports([slow, fast, elsewhere], in: models)

        XCTAssertEqual(shown.map(\.name), ["robot"], "a fast copy shows no placeholder; other folders keep their own")
        XCTAssertEqual(placeholderImports([slow, fast, elsewhere], in: base.appendingPathComponent("HDR")).map(\.name), ["sky.hdr"])
        XCTAssertEqual(assetImportPlaceholderDelay, 1)
    }

    func test_cancelledImportIsMarkedCancelledAndLeavesNothing() async throws {
        let hdr = base.appendingPathComponent("HDR", isDirectory: true)
        let destination = hdr.appendingPathComponent("sky.hdr")

        let finished = expectation(description: "completion on main")
        var completionResult: Result<URL, Error>?
        let handle = importAssetTracked(destination: destination, work: { ctx in
            FileManager.default.createFile(atPath: ctx.stagingURL.path, contents: Data("half".utf8))
            throw CancellationError() // what `ctx.copy` throws once the user hit cancel
        }) { result in
            completionResult = result
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
        await settleTaskCenter()

        XCTAssertThrowsError(try completionResult?.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: hdr.path), [])
        let tracked = await trackedTask(handle.id)
        XCTAssertEqual(try XCTUnwrap(tracked).state, .cancelled)
    }

    func test_copyAssetItemStreamsWithProgressAndKeepsTheModificationDate() throws {
        let source = base.appendingPathComponent("big.ply")
        let payload = Data(repeating: 7, count: 9 << 20) // 9 MB: three 4 MB chunks
        try payload.write(to: source)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: source.path)
        let destination = base.appendingPathComponent("copy.ply")

        var reports: [AssetCopyProgress] = []
        try copyAssetItem(from: source, to: destination, allowClone: false) { reports.append($0) }

        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(reports.last, AssetCopyProgress(copied: Int64(payload.count), total: Int64(payload.count)))
        XCTAssertTrue(reports.allSatisfy { $0.total == Int64(payload.count) })
        XCTAssertEqual(reports.map(\.copied), reports.map(\.copied).sorted(), "progress only grows")
        let copiedDate = try FileManager.default.attributesOfItem(atPath: destination.path)[.modificationDate] as? Date
        XCTAssertEqual(copiedDate?.timeIntervalSince1970 ?? 0, stamp.timeIntervalSince1970, accuracy: 1)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        XCTAssertEqual(
            assetCopyProgressDetail(AssetCopyProgress(copied: 12_300_000, total: 744_000_000)),
            "\(formatter.string(fromByteCount: 12_300_000)) of \(formatter.string(fromByteCount: 744_000_000))"
        )
    }

    func test_copyAssetItemCopiesAFolderTreeAndHonoursCancellation() throws {
        let source = base.appendingPathComponent("material", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Textures"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: source.appendingPathComponent("material.json"))
        try Data("bb".utf8).write(to: source.appendingPathComponent("Textures/albedo.png"))
        let destination = base.appendingPathComponent("copy", isDirectory: true)

        var last: AssetCopyProgress?
        try copyAssetItem(from: source, to: destination, allowClone: false) { last = $0 }

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Textures/albedo.png")), Data("bb".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("material.json")), Data("a".utf8))
        XCTAssertEqual(last, AssetCopyProgress(copied: 3, total: 3))
        XCTAssertEqual(assetItemByteCount(at: source), 3)

        let cancelled = base.appendingPathComponent("cancelled", isDirectory: true)
        XCTAssertThrowsError(try copyAssetItem(from: source, to: cancelled, allowClone: false, isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    // MARK: - Helpers

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
}
