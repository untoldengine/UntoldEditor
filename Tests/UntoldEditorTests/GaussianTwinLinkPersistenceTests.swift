//
//  GaussianTwinLinkPersistenceTests.swift
//  UntoldEditorTests
//
//  The Splat Twin link's home on disk: the `.untold` file's gaussianAsset record, read and
//  written through the engine patcher, mirrored onto the scene's link components.
//

import Foundation
@testable import UntoldEditor
@testable import UntoldEngine
import UntoldGaussianTwins
import XCTest

final class GaussianTwinLinkPersistenceTests: XCTestCase {
    private var directory: URL!
    private var previewEnabled = true

    override func setUpWithError() throws {
        try super.setUpWithError()
        scene = Scene()
        directory = try GaussianTwinTestFixtures.makeTemporaryDirectory()
        previewEnabled = true
        GaussianTwinLinkPersistence.previewEnabled = { [unowned self] in previewEnabled }
    }

    override func tearDown() {
        GaussianTwinLinkPersistence.previewEnabled = { GaussianTwinPreviewSettings.shared.isEnabled }
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        super.tearDown()
    }

    // MARK: - Target resolution

    func test_resolveTarget_singleNodeRootMapsToTheMeshRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: entity)
        XCTAssertEqual(target, GaussianTwinLinkTarget(untoldURL: untold.standardizedFileURL, entityRecordId: 0))
    }

    func test_resolveTarget_derivedMeshNodeMapsToItsOwnRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.node)
        XCTAssertEqual(target.untoldURL, untold.standardizedFileURL)
        XCTAssertEqual(target.entityRecordId, 1, "the child's record, not the root's")
    }

    func test_resolveTarget_multiNodeRootAndMeshlessNodeAreNotTargets() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath, withMesh: false)

        XCTAssertNil(GaussianTwinLinkPersistence.resolveUntoldURL(entityId: placed.root), "a multi-node root has no mesh of its own")
        XCTAssertNil(GaussianTwinLinkPersistence.resolveTarget(entityId: placed.root))
        XCTAssertNil(GaussianTwinLinkPersistence.resolveTarget(entityId: placed.node), "a transform-only node is not a target")
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.root)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .notBackedByUntold)
        }
    }

    func test_resolveTarget_lightAndPrimitiveAreNotTargets() {
        let light = createEntity()
        registerComponent(entityId: light, componentType: LocalTransformComponent.self)
        registerComponent(entityId: light, componentType: DirectionalLightComponent.self)
        XCTAssertNil(GaussianTwinLinkPersistence.resolveTarget(entityId: light))

        let primitive = GaussianTwinTestFixtures.makeMeshEntity(name: "Cube", assetURL: URL(fileURLWithPath: "/dev/null/cube.usdc"))
        XCTAssertNil(GaussianTwinLinkPersistence.resolveUntoldURL(entityId: primitive), "only .untold-backed meshes")
    }

    func test_resolveTarget_recordMismatchIsReportedNotSwallowed() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: "Root/root_entity#0/renamed#7")

        XCTAssertThrowsError(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.node)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .noEntityRecord(untold.standardizedFileURL))
        }
    }

    func test_resolveTarget_namelessRecordMatchesTheLoadersNodePath() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, layout: .hierarchy(namelessChild: true))
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyNamelessChildNodePath)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.node)
        XCTAssertEqual(target.entityRecordId, 1, "a record without a name is `entity_<id>` to the loader and to us")
    }

    func test_resolveTarget_plainEntityOfAMultiMeshFileNeedsAUniqueNamedRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, layout: .twoRootMeshes)

        // The engine put the node named after the entity on it (named-node load).
        let seat = GaussianTwinTestFixtures.makeMeshEntity(name: "seat", assetURL: untold)
        XCTAssertEqual(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: seat).entityRecordId, 1, "not the first mesh record")
        let legs = GaussianTwinTestFixtures.makeMeshEntity(name: "legs", assetURL: untold)
        XCTAssertEqual(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: legs).entityRecordId, 0)

        let renamed = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair", assetURL: untold)
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: renamed)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .ambiguousEntityRecord(untold.standardizedFileURL), "no guessing")
        }
        XCTAssertTrue(GaussianTwinLinkError.ambiguousEntityRecord(untold).localizedDescription.contains("Chair.untold"))

        // The seat's link is the seat's alone, whatever the other entities of the file are.
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("seat.untoldgs"))
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: seat, link: GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold))
        XCTAssertEqual(try Array(UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold)).keys), [1])
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: legs))
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: renamed))
    }

    func test_resolveTarget_streamedStubIsNotATarget() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: "Root/child#0#0")
        registerComponent(entityId: placed.node, componentType: StreamingComponent.self)

        XCTAssertNil(GaussianTwinLinkPersistence.resolveUntoldURL(entityId: placed.node), "the streamer's node path names no record")
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.node)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .notBackedByUntold)
        }
    }

    // MARK: - Round trip

    func test_writeReadRemove_roundTripsThroughTheUntoldFile() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"), splatCount: 5)
        let entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)
        XCTAssertNil(GaussianTwinLinkPersistence.readTwinLink(entityId: entity))

        let link = try GaussianTwinLinkPersistence.makeLink(
            payloadURL: payload,
            untoldURL: untold,
            swapDistanceMeters: 8,
            occluderShrinkMeters: 0.03,
            exposureOffsetEV: -0.5
        )
        XCTAssertEqual(link.payloadPath, "Chair.untoldgs")
        XCTAssertEqual(link.lodCount, 1)
        XCTAssertEqual(link.lodSplatCounts, [5])
        XCTAssertEqual(link.lodSwitchScreenHeights, [0])
        XCTAssertEqual(link.flags, UntoldGaussianAssetFlags.meshTwin)

        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: link)

        // The file carries the record and still reads (hash valid, alignment kept).
        let decoded = try UntoldReader().readAsset(from: Data(contentsOf: untold))
        XCTAssertEqual(decoded.gaussianAssets.count, 1)
        XCTAssertEqual(decoded.gaussianAssets.first?.entityId, 0)
        XCTAssertEqual(decoded.gaussianAssets.first?.swapDistanceMeters, 8)
        XCTAssertEqual(GaussianTwinLinkPersistence.readTwinLink(entityId: entity), link)

        // Mirrored onto the entity as the loader would have attached it.
        let component = try XCTUnwrap(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertTrue(component.isMeshTwin)
        XCTAssertEqual(component.payloadURL?.standardizedFileURL, payload.standardizedFileURL)
        XCTAssertEqual(component.swapDistanceMeters, 8)
        XCTAssertEqual(component.occluderShrinkMeters, 0.03)
        XCTAssertEqual(component.exposureOffsetEV, -0.5)
        XCTAssertEqual(component.lodSplatCounts, [5])

        // And previewed: a twin with the record's payload and settings.
        let twin = try XCTUnwrap(scene.get(component: GaussianTwinComponent.self, for: entity))
        XCTAssertEqual(twin.payloadURL?.standardizedFileURL, payload.standardizedFileURL)
        XCTAssertEqual(twin.options, GaussianTwinOptions(link: component))
        XCTAssertEqual(twin.options.swapDistanceMeters, 8)
        XCTAssertEqual(twin.options.exposureOffsetEV, -0.5)

        // A second write replaces the record; the same payload keeps the twin (no reload).
        var tweaked = link
        tweaked.swapDistanceMeters = 3
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: tweaked)
        XCTAssertEqual(try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.count, 1)
        XCTAssertEqual(GaussianTwinLinkPersistence.readTwinLink(entityId: entity)?.swapDistanceMeters, 3)
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: entity)?.swapDistanceMeters, 3)
        XCTAssertTrue(scene.get(component: GaussianTwinComponent.self, for: entity) === twin, "same payload keeps the twin")
        XCTAssertEqual(twin.options.swapDistanceMeters, 3)

        // A new payload relinks.
        let other = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair_v2.untoldgs"), splatCount: 2)
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: GaussianTwinLinkPersistence.makeLink(payloadURL: other, untoldURL: untold))
        XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: entity)?.payloadURL?.standardizedFileURL, other.standardizedFileURL)

        try GaussianTwinLinkPersistence.removeTwinLink(entityId: entity)
        XCTAssertNil(GaussianTwinLinkPersistence.readTwinLink(entityId: entity))
        XCTAssertTrue(try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.isEmpty)
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity), "the previewed twin goes with the link")
    }

    func test_previewOff_createsNoTwinButKeepsAnExistingOneInStep() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))
        let entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)

        previewEnabled = false
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold))
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity), "the link component does not depend on the preview")
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity), "no twin while the preview is off")

        // Preview on: the twin appears. Off again: the system keeps it, so the edits made
        // while off must still reach it — re-adoption skips entities that have a twin.
        previewEnabled = true
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold))
        let twin = try XCTUnwrap(scene.get(component: GaussianTwinComponent.self, for: entity))
        XCTAssertEqual(twin.options.swapDistanceMeters, 0)

        previewEnabled = false
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold, swapDistanceMeters: 8))
        XCTAssertTrue(scene.get(component: GaussianTwinComponent.self, for: entity) === twin)
        XCTAssertEqual(twin.options.swapDistanceMeters, 8, "options follow the record with the preview off")

        let other = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair_v2.untoldgs"))
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: GaussianTwinLinkPersistence.makeLink(payloadURL: other, untoldURL: untold))
        XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: entity)?.payloadURL?.standardizedFileURL, other.standardizedFileURL, "a new payload relinks with the preview off")

        try GaussianTwinLinkPersistence.removeTwinLink(entityId: entity)
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity), "a stale twin is dropped with the preview off")
    }

    func test_write_mirrorsOntoEveryPlacementOfTheSameRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))
        let first = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair", assetURL: untold)
        let second = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        let otherAsset = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "Table")
        let unrelated = GaussianTwinTestFixtures.makeMeshEntity(name: "Table", assetURL: otherAsset)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: first)
        XCTAssertEqual(Set(GaussianTwinLinkPersistence.entitiesBacked(by: target)), [first, second])

        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: first, link: link)
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: second))
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: unrelated))
        XCTAssertNil(GaussianTwinLinkPersistence.readTwinLink(entityId: unrelated), "the other file is untouched")
    }

    func test_write_onDerivedNodeSetsTheChildRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("child.untoldgs"))
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)

        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: placed.node, link: link)

        let links = try UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold))
        XCTAssertEqual(Array(links.keys), [1])
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: placed.node))
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: placed.root))
    }

    func test_write_onOneMeshNodeLeavesItsSiblingsAloneAndReachesOtherPlacements() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "Table", layout: .hierarchy(secondChild: true))
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("leg.untoldgs"))
        let first = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)
        let firstSibling = GaussianTwinTestFixtures.addDerivedMeshNode(root: first.root, nodePath: GaussianTwinTestFixtures.hierarchySecondChildNodePath)
        let second = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)
        let secondSibling = GaussianTwinTestFixtures.addDerivedMeshNode(root: second.root, nodePath: GaussianTwinTestFixtures.hierarchySecondChildNodePath)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: first.node)
        XCTAssertEqual(target.entityRecordId, 1)
        XCTAssertEqual(Set(GaussianTwinLinkPersistence.entitiesBacked(by: target)), [first.node, second.node], "same record in both placements, siblings excluded")
        XCTAssertEqual(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: firstSibling).entityRecordId, 2)

        try GaussianTwinLinkPersistence.writeTwinLink(entityId: first.node, link: GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold))
        XCTAssertEqual(try Array(UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold)).keys), [1])
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: first.node))
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: second.node), "the other placement's node follows")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: firstSibling), "a sibling mesh node of the same file is another record")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: secondSibling))
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: firstSibling))
        XCTAssertNotNil(scene.get(component: GaussianTwinComponent.self, for: second.node))
    }

    // MARK: - Payload path and validation

    func test_storedPayloadPath_isRelativeToTheUntoldsDirectoryElseTheBasename() throws {
        let models = directory.appendingPathComponent("GameData/Models/Chair", isDirectory: true)
        let gaussians = directory.appendingPathComponent("GameData/Gaussians", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gaussians, withIntermediateDirectories: true)
        let untold = models.appendingPathComponent("Chair.untold")

        let beside = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: models.appendingPathComponent("Chair.untoldgs"), untoldURL: untold)
        XCTAssertEqual(beside.path, "Chair.untoldgs")
        XCTAssertTrue(beside.isRelative)

        let nested = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: models.appendingPathComponent("splats/Chair.untoldgs"), untoldURL: untold)
        XCTAssertEqual(nested.path, "splats/Chair.untoldgs")
        XCTAssertTrue(nested.isRelative)

        // The project's Gaussians folder, seen from Models/Chair: the layout every
        // "Assign Selected" from the browser produces.
        let sibling = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: gaussians.appendingPathComponent("chair_capture.untoldgs"), untoldURL: untold)
        XCTAssertEqual(sibling.path, "../../Gaussians/chair_capture.untoldgs")
        XCTAssertTrue(sibling.isRelative)

        // The stored path resolves the way the loader resolves it (appended, then fileExists).
        let capture = try GaussianTwinTestFixtures.writeUntoldGS(to: gaussians.appendingPathComponent("chair_capture.untoldgs"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untold.deletingLastPathComponent().appendingPathComponent(sibling.path).path))
        XCTAssertEqual(GaussianTwinLinkPersistence.resolvedPayloadURL(path: sibling.path, untoldURL: untold), capture.standardizedFileURL)

        // Another volume shares nothing but the root: the bare name (the caller warns).
        let elsewhere = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: URL(fileURLWithPath: "/Volumes/Captures/chair.untoldgs"), untoldURL: untold)
        XCTAssertEqual(elsewhere.path, "chair.untoldgs")
        XCTAssertFalse(elsewhere.isRelative)
    }

    func test_resolvedPayloadURL_followsTheLoaderRules() throws {
        let untold = directory.appendingPathComponent("Chair.untold")
        try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))

        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "Chair.untoldgs", untoldURL: untold),
            directory.appendingPathComponent("Chair.untoldgs").standardizedFileURL
        )
        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "moved/away/Chair.untoldgs", untoldURL: untold),
            directory.appendingPathComponent("Chair.untoldgs").standardizedFileURL,
            "a relative path that no longer exists falls back to the basename beside the file"
        )
        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "/abs/Chair.untoldgs", untoldURL: untold),
            directory.appendingPathComponent("Chair.untoldgs").standardizedFileURL,
            "the loader treats a bare /abs path as relative (no scheme) and falls back to the basename"
        )
        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "file:///abs/Chair.untoldgs", untoldURL: untold).path,
            "/abs/Chair.untoldgs",
            "a URL with a scheme is absolute, as for the loader"
        )
        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "gone/Chair_missing.untoldgs", untoldURL: untold),
            directory.appendingPathComponent("gone/Chair_missing.untoldgs").standardizedFileURL,
            "nothing found: the relative URL, as the loader returns it"
        )
    }

    func test_makeLink_rejectsMissingAndNonV3Payloads() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let missing = directory.appendingPathComponent("missing.untoldgs")
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.makeLink(payloadURL: missing, untoldURL: untold)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .payloadNotFound(missing))
        }

        let stale = try GaussianTwinTestFixtures.writeStalePayload(to: directory.appendingPathComponent("stale.untoldgs"))
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.makeLink(payloadURL: stale, untoldURL: untold)) { error in
            guard case let .invalidPayload(url, reason)? = error as? GaussianTwinLinkError else {
                return XCTFail("expected invalidPayload, got \(error)")
            }
            XCTAssertEqual(url, stale)
            XCTAssertTrue(reason.contains("version"), reason)
            XCTAssertTrue(error.localizedDescription.contains("not a usable .untoldgs payload"), "user-visible message")
        }

        let ply = directory.appendingPathComponent("raw.ply")
        try Data("ply\nformat binary_little_endian 1.0\n".utf8).write(to: ply)
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.makeLink(payloadURL: ply, untoldURL: untold)) { error in
            guard case .invalidPayload? = error as? GaussianTwinLinkError else {
                return XCTFail("expected invalidPayload, got \(error)")
            }
        }
    }

    func test_write_reportsUnknownRecordAsPatchFailure() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))
        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        let bogus = GaussianTwinLinkTarget(untoldURL: untold, entityRecordId: 42)

        XCTAssertThrowsError(try GaussianTwinLinkPersistence.writeTwinLink(target: bogus, link: link)) { error in
            guard case let .patchFailed(reason)? = error as? GaussianTwinLinkError else {
                return XCTFail("expected patchFailed, got \(error)")
            }
            XCTAssertTrue(reason.contains("42"), reason)
        }
        XCTAssertTrue(try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.isEmpty, "the file is left alone")
    }
}
