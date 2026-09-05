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
        let handle = importAssetTracked(destination: destination, detail: "→ Gaussians/") { staging in
            XCTAssertFalse(Thread.isMainThread, "the copy must not run on the main thread")
            stagingSeen = staging
            destinationExistedDuringWork = FileManager.default.fileExists(atPath: destination.path)
            try FileManager.default.copyItem(at: source, to: staging)
        } completion: { result in
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
        XCTAssertNil(task.progress)
        XCTAssertFalse(task.isCancellable)
    }

    func test_trackedImportFailureLeavesNoStagingAndNoDestination() async throws {
        struct Boom: LocalizedError { var errorDescription: String? {
            "disk on fire"
        } }
        let hdr = base.appendingPathComponent("HDR", isDirectory: true)
        let destination = hdr.appendingPathComponent("sky.hdr")

        let finished = expectation(description: "completion on main")
        var completionResult: Result<URL, Error>?
        let handle = importAssetTracked(destination: destination) { staging in
            FileManager.default.createFile(atPath: staging.path, contents: Data("half".utf8))
            throw Boom()
        } completion: { result in
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
        XCTAssertEqual(assetImportPlaceholderDelay, 5)
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
