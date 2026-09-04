//
//  AssetPlacementTests.swift
//  UntoldEditorTests
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  The pure parts of asset drag-and-drop: the drag payload round trip, which
//  browser rows resolve to a placeable model or Gaussian splat (including the
//  progressive tier detection), the message for everything else, and the
//  ground-plane hit that positions a viewport drop. The gestures themselves are
//  not unit-tested.
//

import simd
import UniformTypeIdentifiers
@testable import UntoldEditor
import UntoldEngine
import XCTest

final class AssetPlacementTests: XCTestCase {
    private var temporaryDirectory: URL?

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetPlacementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        return directory
    }

    private func touch(_ url: URL) throws {
        try Data("x".utf8).write(to: url)
    }

    // MARK: - Drag payload

    func test_dragPayloadRoundTripsThroughJSON() throws {
        let asset = Asset(
            name: "chair.untold",
            category: AssetCategory.models.rawValue,
            path: URL(fileURLWithPath: "/tmp/Project/Models/chair.untold"),
            isFolder: false
        )
        let payload = AssetDragPayload(asset: asset)

        let decoded = try AssetDragPayload.decode(payload.encoded())

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.asset.name, "chair.untold")
        XCTAssertEqual(decoded.asset.category, AssetCategory.models.rawValue)
        XCTAssertEqual(decoded.asset.path, asset.path)
        XCTAssertFalse(decoded.asset.isFolder)
    }

    func test_dragPayloadKeepsFolderFlag() throws {
        let folder = Asset(
            name: "Chair",
            category: AssetCategory.models.rawValue,
            path: URL(fileURLWithPath: "/tmp/Project/Models/Chair", isDirectory: true),
            isFolder: true
        )

        let decoded = try AssetDragPayload.decode(AssetDragPayload(asset: folder).encoded())

        XCTAssertTrue(decoded.asset.isFolder)
    }

    func test_dragPayloadTravelsAsStandardJSON() throws {
        // A declared system type, not a custom exported one: the SwiftPM binary has
        // no Info.plist to declare a custom type in and undeclared types never match
        // at the drop. The hierarchy's entity-id plain text must not be mistaken
        // for a payload.
        XCTAssertEqual(AssetDragPayload.contentType, .json)
        XCTAssertFalse(UTType.utf8PlainText.conforms(to: AssetDragPayload.contentType))

        let payload = AssetDragPayload(name: "a.ply", category: AssetCategory.gaussians.rawValue, path: URL(fileURLWithPath: "/tmp/a.ply"))
        let object = try JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any]
        XCTAssertEqual(object?["name"] as? String, "a.ply")
    }

    // MARK: - Placeable dispatch

    func test_modelRuntimeAssetIsPlaceable() {
        let url = URL(fileURLWithPath: "/tmp/Project/Models/chair.untold")
        let asset = Asset(name: "chair.untold", category: AssetCategory.models.rawValue, path: url)

        XCTAssertEqual(placeableAsset(for: asset), .model(url))
    }

    func test_modelFolderResolvesToItsPrimaryRuntimeAsset() throws {
        let directory = try makeTemporaryDirectory()
        let folder = directory.appendingPathComponent("Chair", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let primary = folder.appendingPathComponent("Chair.untold")
        try touch(primary)
        try touch(folder.appendingPathComponent("Chair_shadow.untold"))
        let asset = Asset(name: "Chair", category: AssetCategory.models.rawValue, path: folder, isFolder: true)

        guard case let .model(url)? = placeableAsset(for: asset) else {
            return XCTFail("Expected the folder to resolve to a model")
        }
        // Directory listings come back with /var resolved to /private/var.
        XCTAssertEqual(url.resolvingSymlinksInPath(), primary.resolvingSymlinksInPath())
    }

    func test_modelFolderWithoutPrimaryIsNotPlaceable() throws {
        let directory = try makeTemporaryDirectory()
        let folder = directory.appendingPathComponent("Props", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try touch(folder.appendingPathComponent("a.untold"))
        try touch(folder.appendingPathComponent("b.untold"))
        let asset = Asset(name: "Props", category: AssetCategory.models.rawValue, path: folder, isFolder: true)

        XCTAssertNil(placeableAsset(for: asset))
        XCTAssertEqual(unsupportedAssetDropMessage(for: asset), "No primary .untold found in Props")
    }

    func test_gaussianSourceAndSingleBakedFileArePlaceable() throws {
        let directory = try makeTemporaryDirectory()
        let ply = directory.appendingPathComponent("room.ply")
        let baked = directory.appendingPathComponent("room.untoldgs")
        try touch(ply)
        try touch(baked)

        XCTAssertEqual(
            placeableAsset(for: Asset(name: "room.ply", category: AssetCategory.gaussians.rawValue, path: ply)),
            .gaussian(ply)
        )
        XCTAssertEqual(
            placeableAsset(for: Asset(name: "room.untoldgs", category: AssetCategory.gaussians.rawValue, path: baked)),
            .gaussian(baked)
        )
    }

    func test_progressiveTierStandsForTheWholeSet() throws {
        let directory = try makeTemporaryDirectory()
        for level in 0 ..< 3 {
            try touch(directory.appendingPathComponent("room_lod\(level).untoldgs"))
        }
        let tier = directory.appendingPathComponent("room_lod2.untoldgs")
        let asset = Asset(name: "room_lod2.untoldgs", category: AssetCategory.gaussians.rawValue, path: tier)

        XCTAssertEqual(
            placeableAsset(for: asset),
            .progressiveGaussian(baseURL: directory.appendingPathComponent("room"), levelCount: 3)
        )
    }

    func test_extensionMatchingIgnoresCase() {
        let url = URL(fileURLWithPath: "/tmp/Project/Models/CHAIR.UNTOLD")
        let asset = Asset(name: "CHAIR.UNTOLD", category: AssetCategory.models.rawValue, path: url)

        XCTAssertEqual(placeableAsset(for: asset), .model(url))
    }

    func test_otherAssetKindsAreNotPlaceable() throws {
        let directory = try makeTemporaryDirectory()
        let unsupported: [(String, String)] = [
            (AssetCategory.scripts.rawValue, "spin.uscript"),
            (AssetCategory.scenes.rawValue, "level.untoldscene"),
            (AssetCategory.hdr.rawValue, "sky.hdr"),
            (AssetCategory.animations.rawValue, "walk.untold"),
            (AssetCategory.materials.rawValue, "wood.png"),
            (AssetCategory.models.rawValue, "thumb.png"),
            (AssetCategory.gaussians.rawValue, "notes.json"),
            // A .untold outside Models, or a Gaussian file outside Gaussians, is not placed either.
            (AssetCategory.gaussians.rawValue, "chair.untold"),
            (AssetCategory.models.rawValue, "room.ply"),
        ]
        for (category, filename) in unsupported {
            let url = directory.appendingPathComponent(filename)
            try touch(url)
            let asset = Asset(name: filename, category: category, path: url)
            XCTAssertNil(placeableAsset(for: asset), "\(category)/\(filename) should not be placeable")
            XCTAssertEqual(
                unsupportedAssetDropMessage(for: asset),
                "Only models (.untold) and Gaussian splats (.ply, .untoldgs) can be dropped into the scene"
            )
        }

        let gaussianFolder = Asset(name: "Scans", category: AssetCategory.gaussians.rawValue, path: directory, isFolder: true)
        XCTAssertNil(placeableAsset(for: gaussianFolder))
    }

    // MARK: - Ground-plane hit

    private let viewportSize = CGSize(width: 800, height: 600)
    private let cameraPosition = simd_float3(0, 5, 5)

    private var viewSpace: simd_float4x4 {
        matrix_look_at_right_hand(cameraPosition, simd_float3(0, 0, 0), simd_float3(0, 1, 0))
    }

    private var perspectiveSpace: simd_float4x4 {
        matrixPerspectiveRightHand(fovyRadians: .pi / 3, aspectRatio: 800 / 600, nearZ: 0.1, farZ: 1000)
    }

    private func hit(at location: CGPoint, maxDistance: Float = maximumAssetDropDistance) -> simd_float3? {
        groundPlaneHit(
            atViewportLocation: location,
            viewportSize: viewportSize,
            cameraPosition: cameraPosition,
            viewSpace: viewSpace,
            perspectiveSpace: perspectiveSpace,
            maxDistance: maxDistance
        )
    }

    func test_viewportCentreHitsTheLookAtPointOnTheGround() throws {
        let position = try XCTUnwrap(hit(at: CGPoint(x: 400, y: 300)))

        XCTAssertEqual(position.x, 0, accuracy: 0.01)
        XCTAssertEqual(position.y, 0, accuracy: 0.01)
        XCTAssertEqual(position.z, 0, accuracy: 0.01)
    }

    func test_lowerScreenPointsLandNearerTheCamera() throws {
        // The camera looks down at the ground, so a point below the viewport centre
        // (larger SwiftUI y) meets the plane closer to the camera than the centre does.
        let centre = try XCTUnwrap(hit(at: CGPoint(x: 400, y: 300)))
        let lower = try XCTUnwrap(hit(at: CGPoint(x: 400, y: 500)))
        let right = try XCTUnwrap(hit(at: CGPoint(x: 700, y: 300)))

        XCTAssertLessThan(simd_distance(lower, cameraPosition), simd_distance(centre, cameraPosition))
        XCTAssertGreaterThan(lower.z, centre.z)
        XCTAssertGreaterThan(right.x, centre.x)
        XCTAssertEqual(lower.y, 0, accuracy: 0.001)
    }

    func test_rayMissingTheGroundGivesNoHit() {
        // Camera looking straight ahead along the ground: the centre ray runs
        // parallel to the plane and the top of the viewport looks at the sky.
        let horizontalView = matrix_look_at_right_hand(cameraPosition, simd_float3(0, 5, 0), simd_float3(0, 1, 0))
        for location in [CGPoint(x: 400, y: 300), CGPoint(x: 400, y: 0)] {
            XCTAssertNil(groundPlaneHit(
                atViewportLocation: location,
                viewportSize: viewportSize,
                cameraPosition: cameraPosition,
                viewSpace: horizontalView,
                perspectiveSpace: perspectiveSpace
            ))
        }
        // Below the centre the same camera does see the ground.
        XCTAssertNotNil(groundPlaneHit(
            atViewportLocation: CGPoint(x: 400, y: 550),
            viewportSize: viewportSize,
            cameraPosition: cameraPosition,
            viewSpace: horizontalView,
            perspectiveSpace: perspectiveSpace
        ))
    }

    func test_hitBeyondTheDistanceLimitGivesNoHit() {
        // A valid hit farther than the limit is dropped, so the caller falls back to the origin.
        XCTAssertNil(hit(at: CGPoint(x: 400, y: 300), maxDistance: 1))
        XCTAssertNotNil(hit(at: CGPoint(x: 400, y: 300), maxDistance: 10))
    }

    func test_emptyViewportGivesNoHit() {
        XCTAssertNil(groundPlaneHit(
            atViewportLocation: .zero,
            viewportSize: .zero,
            cameraPosition: cameraPosition,
            viewSpace: viewSpace,
            perspectiveSpace: perspectiveSpace
        ))
    }
}
