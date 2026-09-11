//
//  GaussianTwinInspectorModelTests.swift
//  UntoldEditorTests
//
//  The Splat Twin section's model: assign / remove write at once, field edits apply live and
//  persist after a pause, every change is undoable, errors surface as status text.
//

import Foundation
@testable import UntoldEditor
@testable import UntoldEngine
import UntoldGaussianTwins
import XCTest

final class GaussianTwinInspectorModelTests: XCTestCase {
    private var directory: URL!
    private var untold: URL!
    private var payload: URL!
    private var entity: EntityID = .invalid
    private var undoManager: EditorUndoManager!
    /// Actions handed to the injected scheduler, oldest first, with their delay.
    private var scheduled: [(delay: TimeInterval, action: () -> Void)] = []
    private var cancelledCount = 0
    private var previewEnabled = true

    override func setUpWithError() throws {
        try super.setUpWithError()
        scene = Scene()
        directory = try GaussianTwinTestFixtures.makeTemporaryDirectory()
        untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"), splatCount: 4)
        entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)
        undoManager = EditorUndoManager()
        scheduled = []
        cancelledCount = 0
        previewEnabled = true
        GaussianTwinLinkPersistence.previewEnabled = { [unowned self] in previewEnabled }
    }

    override func tearDown() {
        GaussianTwinLinkPersistence.previewEnabled = { GaussianTwinPreviewSettings.shared.isEnabled }
        if let directory {
            // A test may have locked the asset folder to make a write fail.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        undoManager = nil
        super.tearDown()
    }

    private func makeModel(entityId: EntityID? = nil) -> GaussianTwinInspectorModel {
        GaussianTwinInspectorModel(
            entityId: entityId ?? entity,
            scheduler: { [unowned self] delay, action in
                scheduled.append((delay, action))
                return { [unowned self] in cancelledCount += 1 }
            },
            undoManager: undoManager
        )
    }

    private func storedLink() throws -> UntoldAssetPatcher.GaussianAssetLink? {
        try UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold))[0]
    }

    // MARK: - Assign / remove

    func test_freshModel_resolvesTargetAndShowsNoTwin() {
        let model = makeModel()
        XCTAssertEqual(model.target, GaussianTwinLinkTarget(untoldURL: untold.standardizedFileURL, entityRecordId: 0))
        XCTAssertNil(model.link)
        XCTAssertEqual(model.payloadDisplay, GaussianTwinInspectorModel.noTwinTitle)
        XCTAssertNil(model.status)
        XCTAssertFalse(model.hasPendingPersist)
    }

    func test_assign_writesAtOnceAndRegistersUndo() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)

        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs")
        XCTAssertEqual(model.link?.lodSplatCounts, [4])
        XCTAssertEqual(model.payloadDisplay, "Chair.untoldgs")
        XCTAssertEqual(try storedLink(), model.link, "assign persists immediately")
        XCTAssertTrue(scheduled.isEmpty, "no debounce for assign")
        XCTAssertEqual(model.status?.isError, false)
        XCTAssertTrue(model.status?.message.contains("4 splats") == true, model.status?.message ?? "")
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertNil(try storedLink(), "undo removes the record from the file")
        XCTAssertNil(model.link, "the model follows the file")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))

        undoManager.redo()
        XCTAssertEqual(try storedLink()?.payloadPath, "Chair.untoldgs")
        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs")
    }

    func test_assign_keepsTheSettingsOfTheReplacedLink() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(6)
        model.flushPendingPersist()

        let other = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair_v2.untoldgs"), splatCount: 9)
        model.assign(payloadURL: other)
        XCTAssertEqual(model.link?.payloadPath, "Chair_v2.untoldgs")
        XCTAssertEqual(model.link?.swapDistanceMeters, 6)
        XCTAssertEqual(model.link?.lodSplatCounts, [9])
        XCTAssertEqual(try storedLink(), model.link)
    }

    func test_assign_fromTheProjectsGaussiansFolderStoresAResolvablePath() throws {
        // GameData/Models/Chair/Chair.untold + GameData/Gaussians/chair.untoldgs: the browser's layout.
        let models = directory.appendingPathComponent("GameData/Models/Chair", isDirectory: true)
        let gaussians = directory.appendingPathComponent("GameData/Gaussians", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gaussians, withIntermediateDirectories: true)
        let projectUntold = try GaussianTwinTestFixtures.writeUntold(to: models)
        let capture = try GaussianTwinTestFixtures.writeUntoldGS(to: gaussians.appendingPathComponent("chair.untoldgs"))
        let chair = GaussianTwinTestFixtures.makeMeshEntity(assetURL: projectUntold)

        let model = makeModel(entityId: chair)
        model.assignSelectedAsset(Asset(name: "chair", category: AssetCategory.gaussians.rawValue, path: capture))

        XCTAssertEqual(model.link?.payloadPath, "../../Gaussians/chair.untoldgs")
        XCTAssertEqual(model.status?.isError, false)
        XCTAssertFalse(model.status?.message.contains("file name only") == true, "a relative path needs no warning")
        let component = try XCTUnwrap(scene.get(component: GaussianAssetLinkComponent.self, for: chair))
        let mirrored = try XCTUnwrap(component.payloadURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mirrored.path), "the mirrored URL points at the picked file")
        XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: chair)?.payloadURL, capture.standardizedFileURL)
        XCTAssertEqual(model.payloadURL, capture.standardizedFileURL)
    }

    func test_assignSelectedAsset_acceptsOnlyCookedGaussians() {
        let model = makeModel()
        model.assignSelectedAsset(Asset(name: "Chair", category: AssetCategory.models.rawValue, path: untold))
        XCTAssertNil(model.link)
        XCTAssertEqual(model.status?.isError, true)

        model.assignSelectedAsset(Asset(name: "capture", category: AssetCategory.gaussians.rawValue, path: directory.appendingPathComponent("capture.ply")))
        XCTAssertNil(model.link, ".ply must be cooked first")

        model.assignSelectedAsset(Asset(name: "Chair", category: AssetCategory.gaussians.rawValue, path: payload))
        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs")
    }

    func test_remove_writesAtOnceAndIsUndoable() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let linked = model.link

        model.removeLink()
        XCTAssertNil(model.link)
        XCTAssertNil(try storedLink())
        XCTAssertEqual(model.payloadDisplay, GaussianTwinInspectorModel.noTwinTitle)

        undoManager.undo()
        XCTAssertEqual(model.link, linked)
        XCTAssertEqual(try storedLink(), linked)
    }

    // MARK: - Fields

    func test_fieldEdit_appliesLiveAndPersistsAfterTheDebounce() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)

        model.setSwapDistance(5)
        XCTAssertEqual(model.link?.swapDistanceMeters, 5)
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: entity)?.swapDistanceMeters, 5, "live on the scene")
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0, "not on disk yet")
        XCTAssertTrue(model.hasPendingPersist)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].delay, GaussianTwinInspectorModel.persistDelay)
        XCTAssertEqual(scheduled[0].delay, 0.4, accuracy: 0.0001)

        model.setOccluderShrink(0.05)
        XCTAssertEqual(cancelledCount, 1, "a second edit restarts the timer")
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0)

        scheduled.last?.action()
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 5)
        XCTAssertEqual(try storedLink()?.occluderShrinkMeters, 0.05)

        // Each edit is one undo step carrying the whole link.
        undoManager.undo()
        XCTAssertEqual(model.link?.occluderShrinkMeters, 0.02)
        XCTAssertEqual(model.link?.swapDistanceMeters, 5)
        XCTAssertEqual(try storedLink()?.occluderShrinkMeters, 0.02, "undo writes through")
        undoManager.undo()
        XCTAssertEqual(model.link?.swapDistanceMeters, 0)
        undoManager.undo()
        XCTAssertNil(model.link, "back to the unassigned asset")
        XCTAssertFalse(undoManager.canUndo)
    }

    func test_flushPendingPersist_writesNowAndCancelsTheTimer() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setExposureOffset(-1.5)
        XCTAssertTrue(model.hasPendingPersist)

        model.flushPendingPersist()
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertEqual(cancelledCount, 1)
        XCTAssertEqual(try storedLink()?.exposureOffsetEV, -1.5)

        scheduled.last?.action()
        XCTAssertEqual(try storedLink()?.exposureOffsetEV, -1.5, "a late timer is a no-op")
    }

    func test_fieldEdit_withThePreviewOffStillReachesTheTwinTheSystemKept() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let twin = try XCTUnwrap(scene.get(component: GaussianTwinComponent.self, for: entity))

        // View > Preview Splat Twins off: `uninstall()` keeps the twin. Edits made now must
        // land on it, since re-adoption on enable skips entities that already have one.
        previewEnabled = false
        model.setSwapDistance(10)
        XCTAssertTrue(scene.get(component: GaussianTwinComponent.self, for: entity) === twin)
        XCTAssertEqual(twin.options.swapDistanceMeters, 10, "live edit")
        scheduled.last?.action()
        XCTAssertEqual(twin.options.swapDistanceMeters, 10, "and after the persist")

        let other = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair_v2.untoldgs"))
        model.assign(payloadURL: other)
        XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: entity)?.payloadURL?.standardizedFileURL, other.standardizedFileURL)

        previewEnabled = true
        let component = try XCTUnwrap(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: entity)?.options, GaussianTwinOptions(link: component), "nothing to catch up on when the preview comes back")
    }

    func test_failedDebouncedWrite_snapsTheSceneAndModelBackToTheFile() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let second = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        model.setSwapDistance(2)
        scheduled.last?.action()
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 2)

        // The asset folder becomes read-only: the atomic write cannot create its temp file.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        try XCTSkipIf(FileManager.default.isWritableFile(atPath: directory.path), "the folder cannot be locked here (running as root?)")

        model.setSwapDistance(8)
        XCTAssertEqual(model.link?.swapDistanceMeters, 8)
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: entity)?.swapDistanceMeters, 8, "live until the write")
        scheduled.last?.action()

        XCTAssertEqual(model.status?.isError, true)
        XCTAssertTrue(model.status?.message.contains("Could not write Chair.untold") == true, model.status?.message ?? "")
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 2, "the file is what it was")
        XCTAssertEqual(model.link?.swapDistanceMeters, 2, "the model follows the file, not the edit")
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: entity)?.swapDistanceMeters, 2, "so do the components")
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: second)?.swapDistanceMeters, 2, "on every placement")
        XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: entity)?.options.swapDistanceMeters, 2, "and the preview")
        XCTAssertFalse(model.hasPendingPersist)
    }

    func test_releasingTheModel_flushesThePendingEditAndLeavesNoCycle() throws {
        var model: GaussianTwinInspectorModel? = makeModel()
        model?.assign(payloadURL: payload)
        model?.setSwapDistance(5)
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0, "pending")

        weak var released = model
        model = nil
        XCTAssertNil(released, "no retain cycle through the observer or the scheduler")
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 5, "deinit writes the pending edit")

        scheduled.last?.action()
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 5, "the late timer is a no-op on the freed model")
    }

    func test_undo_outlivesTheModelThatRegisteredIt() throws {
        var model: GaussianTwinInspectorModel? = makeModel()
        model?.assign(payloadURL: payload)
        model = nil

        undoManager.undo()
        XCTAssertNil(try storedLink(), "the closure carries the target, not the model")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        undoManager.redo()
        XCTAssertEqual(try storedLink()?.payloadPath, "Chair.untoldgs")
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
    }

    func test_undo_afterTheEntityIsGoneStillRestoresTheFile() throws {
        var model: GaussianTwinInspectorModel? = makeModel()
        model?.assign(payloadURL: payload)
        model = nil

        destroyEntity(entityId: entity)
        finalizePendingDestroys()
        let light = createEntity()
        registerComponent(entityId: light, componentType: LocalTransformComponent.self)
        registerComponent(entityId: light, componentType: DirectionalLightComponent.self)

        undoManager.undo()
        XCTAssertNil(try storedLink(), "undo removes the record although nothing in the scene is backed by it")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: light))
        undoManager.redo()
        XCTAssertEqual(try storedLink()?.payloadPath, "Chair.untoldgs")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: light), "a reused slot gets nothing")
    }

    func test_undoDuringAPendingEdit_dropsThePendingWrite() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(7)
        XCTAssertTrue(model.hasPendingPersist)

        undoManager.undo()
        XCTAssertEqual(model.link?.swapDistanceMeters, 0)
        XCTAssertFalse(model.hasPendingPersist, "the file now says what the undo wrote")
        scheduled.last?.action()
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0)
    }

    func test_fieldValues_areClampedToTheirRanges() {
        let model = makeModel()
        model.assign(payloadURL: payload)

        model.setSwapDistance(-3)
        XCTAssertEqual(model.link?.swapDistanceMeters, 0)
        model.setOccluderShrink(-1)
        XCTAssertEqual(model.link?.occluderShrinkMeters, 0)
        model.setExposureOffset(9)
        XCTAssertEqual(model.link?.exposureOffsetEV, 4)
        model.setExposureOffset(-9)
        XCTAssertEqual(model.link?.exposureOffsetEV, -4)
        model.setExposureOffset(.nan)
        XCTAssertEqual(model.link?.exposureOffsetEV, -4, "non-finite input keeps the value")

        XCTAssertEqual(GaussianTwinInspector.clampedSwapDistance(2.5, previous: 0), 2.5)
        XCTAssertEqual(GaussianTwinInspector.clampedExposureOffset(.infinity, previous: 1), 1)
    }

    func test_fieldEdit_withoutALinkIsIgnored() {
        let model = makeModel()
        model.setSwapDistance(3)
        XCTAssertNil(model.link)
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertFalse(undoManager.canUndo)
    }

    // MARK: - Errors

    func test_assign_nonV3Payload_showsErrorAndChangesNothing() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let stale = try GaussianTwinTestFixtures.writeStalePayload(to: directory.appendingPathComponent("stale.untoldgs"))
        undoManager.clear()

        model.assign(payloadURL: stale)
        XCTAssertEqual(model.status?.isError, true)
        XCTAssertTrue(model.status?.message.contains("stale.untoldgs is not a usable .untoldgs payload") == true, model.status?.message ?? "")
        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs", "the previous link stays")
        XCTAssertEqual(try storedLink()?.payloadPath, "Chair.untoldgs")
        XCTAssertFalse(undoManager.canUndo, "a failed assign registers no undo step")
    }

    func test_entityWithoutARecord_reportsTheFileInTheStatus() throws {
        let hierarchy = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "Table", hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: hierarchy, nodePath: "Root/root_entity#0/gone#5")

        let model = makeModel(entityId: placed.node)
        XCTAssertNil(model.target)
        XCTAssertEqual(model.status?.isError, true)
        XCTAssertTrue(model.status?.message.contains("Table.untold") == true, model.status?.message ?? "")
        model.assign(payloadURL: payload)
        XCTAssertNil(model.link)
    }

    // MARK: - Preview line

    func test_liveTwinDescription_reportsTheTwinState() throws {
        let model = makeModel()
        XCTAssertNil(model.liveTwinDescription(), "no twin, no line")

        setEntityGaussianTwin(entityId: entity, payloadURL: payload)
        let description = try XCTUnwrap(model.liveTwinDescription())
        XCTAssertTrue(description.hasPrefix("armed"), description)
        XCTAssertEqual(GaussianTwinInspector.stateTitle(.crossFading), "cross-fading")
        XCTAssertEqual(GaussianTwinInspector.stateTitle(.swapped), "swapped")
        removeEntityGaussianTwin(entityId: entity)
    }
}
