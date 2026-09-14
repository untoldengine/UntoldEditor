//
//  GaussianTwinAlignmentTests.swift
//  UntoldEditorTests
//
//  The Splat Twin section's alignment: offset, yaw and scale round-trip through the
//  `.untold` record, reach the scene's link component and the previewed twin live, and the
//  align mode forces the twin over the mesh only for as long as it is on.
//

import Foundation
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import UntoldGaussianTwins
import XCTest

final class GaussianTwinAlignmentTests: XCTestCase {
    private var directory: URL!
    private var untold: URL!
    private var payload: URL!
    private var entity: EntityID = .invalid
    private var undoManager: EditorUndoManager!
    private var scheduled: [(delay: TimeInterval, action: () -> Void)] = []
    private var previewEnabled = true
    private var savedDisableOccluderShell = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        scene = Scene()
        directory = try GaussianTwinTestFixtures.makeTemporaryDirectory("GaussianTwinAlignmentTests")
        untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"), splatCount: 4)
        entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)
        undoManager = EditorUndoManager()
        scheduled = []
        previewEnabled = true
        GaussianTwinLinkPersistence.previewEnabled = { [unowned self] in previewEnabled }
        savedDisableOccluderShell = GaussianDebugOptions.shared.disableOccluderShell
        GaussianDebugOptions.shared.disableOccluderShell = false
    }

    override func tearDown() {
        GaussianTwinAlignMode.shared.leave()
        GaussianDebugOptions.shared.disableOccluderShell = savedDisableOccluderShell
        GaussianTwinLinkPersistence.previewEnabled = { GaussianTwinPreviewSettings.shared.isEnabled }
        if let directory {
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
                return {}
            },
            undoManager: undoManager
        )
    }

    private func storedLink() throws -> UntoldAssetPatcher.GaussianAssetLink? {
        try UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold))[0]
    }

    private func storedRecord() throws -> UntoldGaussianAssetRecordV1? {
        try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.first
    }

    private func linkComponent(_ entityId: EntityID? = nil) -> GaussianAssetLinkComponent? {
        scene.get(component: GaussianAssetLinkComponent.self, for: entityId ?? entity)
    }

    private func twin(_ entityId: EntityID? = nil) -> GaussianTwinComponent? {
        scene.get(component: GaussianTwinComponent.self, for: entityId ?? entity)
    }

    private let sample = GaussianSplatAlignment(translation: SIMD3<Float>(0.12, 0, -0.3), yawDegrees: 12, scale: 1.05)

    // MARK: - Model: values, live apply, persistence, undo

    func test_freshLink_hasNoAlignmentAndReadsAsIdentity() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)

        XCTAssertNil(model.link?.alignment, "a new link stores no alignment")
        XCTAssertFalse(model.hasAlignment)
        XCTAssertEqual(model.alignment, .identity)
        XCTAssertEqual(model.alignmentOffset, .zero)
        XCTAssertEqual(model.alignmentYawDegrees, 0)
        XCTAssertEqual(model.alignmentScale, 1)
        XCTAssertEqual(model.alignmentDescription, "identity")
        XCTAssertEqual(try storedLink()?.flags, UntoldGaussianAssetFlags.meshTwin, "no alignment flag in the record")
        XCTAssertNil(linkComponent()?.alignment)
        XCTAssertNil(twin()?.options.alignment)
    }

    func test_alignmentEdits_applyLiveAndPersistAfterTheDebounce() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let second = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        model.flushPendingPersist()

        model.setAlignmentOffset(SIMD3<Float>(0.12, 0, -0.3))
        model.setAlignmentYawDegrees(12)
        model.setAlignmentScale(1.05)

        XCTAssertEqual(model.link?.alignment, sample)
        XCTAssertTrue(model.hasAlignment)
        XCTAssertEqual(linkComponent()?.alignment, sample, "live on the link component")
        XCTAssertEqual(twin()?.options.alignment, sample, "and on the previewed twin's options")
        XCTAssertEqual(linkComponent(second)?.alignment, sample, "on every placement of the record")
        XCTAssertNil(try storedLink()?.alignment, "not on disk before the debounce")
        XCTAssertTrue(model.hasPendingPersist)
        XCTAssertEqual(scheduled.count, 3)

        scheduled.last?.action()
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertEqual(try storedLink()?.alignment, sample)
        let record = try XCTUnwrap(try storedRecord())
        XCTAssertNotEqual(record.flags & UntoldGaussianAssetFlags.alignment, 0, "the record carries the alignment flag")
        XCTAssertEqual(record.alignmentTranslation, sample.translation)
        XCTAssertEqual(record.alignmentYawDegrees, 12)
        XCTAssertEqual(record.alignmentScale, 1.05)
        XCTAssertEqual(record.flags & UntoldGaussianAssetFlags.meshTwin, UntoldGaussianAssetFlags.meshTwin, "the twin flag stays")

        // Each edit is one undo step carrying the whole link.
        undoManager.undo()
        XCTAssertEqual(model.link?.alignment, GaussianSplatAlignment(translation: SIMD3<Float>(0.12, 0, -0.3), yawDegrees: 12, scale: 1))
        XCTAssertEqual(try storedLink()?.alignment?.scale, 1, "undo writes through")
        undoManager.undo()
        XCTAssertEqual(model.link?.alignment?.yawDegrees, 0)
        undoManager.undo()
        XCTAssertNil(model.link?.alignment, "back to identity: stored as no alignment")
        XCTAssertNil(try storedLink()?.alignment)
        XCTAssertNil(linkComponent()?.alignment)
        XCTAssertNil(twin()?.options.alignment)
        undoManager.redo()
        XCTAssertEqual(model.link?.alignment?.translation, SIMD3<Float>(0.12, 0, -0.3))
    }

    func test_alignment_roundTripsThroughTheFileIntoAFreshModel() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignmentOffset(sample.translation)
        model.setAlignmentYawDegrees(sample.yawDegrees)
        model.setAlignmentScale(sample.scale)
        model.flushPendingPersist()

        let reopened = makeModel()
        XCTAssertEqual(reopened.link, model.link)
        XCTAssertEqual(reopened.alignment, sample)
        XCTAssertEqual(reopened.alignmentOffset, sample.translation)
        XCTAssertEqual(reopened.alignmentYawDegrees, 12)
        XCTAssertEqual(reopened.alignmentScale, 1.05)
        XCTAssertEqual(reopened.alignmentDescription, "offset 0.12, 0, −0.30 m · yaw 12° · scale 1.05")

        // The link component the loader would attach carries it, so the twin system adopting
        // the scene link gets the same options.
        let component = try XCTUnwrap(linkComponent())
        XCTAssertEqual(component.alignment, sample)
        XCTAssertEqual(GaussianTwinOptions(link: component).alignment, sample)
        XCTAssertEqual(twin()?.options, GaussianTwinOptions(link: component))
    }

    func test_reset_dropsTheAlignmentFromTheRecordAndIsUndoable() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignmentYawDegrees(90)
        model.flushPendingPersist()
        XCTAssertEqual(try storedLink()?.alignment?.yawDegrees, 90)

        model.resetAlignment()
        XCTAssertNil(model.link?.alignment)
        XCTAssertFalse(model.hasAlignment)
        XCTAssertEqual(model.alignmentDescription, "identity")
        XCTAssertNil(linkComponent()?.alignment)
        XCTAssertNil(twin()?.options.alignment)
        scheduled.last?.action()
        XCTAssertNil(try storedLink()?.alignment)
        XCTAssertEqual(try storedRecord()?.flags, UntoldGaussianAssetFlags.meshTwin, "flag clear again")
        XCTAssertEqual(try storedRecord()?.alignmentScale, 0, "fields zeroed like a record never aligned")

        undoManager.undo()
        XCTAssertEqual(model.link?.alignment?.yawDegrees, 90)
        XCTAssertEqual(try storedLink()?.alignment?.yawDegrees, 90)

        model.resetAlignment()
        XCTAssertEqual(scheduled.count, 3)
        model.resetAlignment()
        XCTAssertEqual(scheduled.count, 3, "resetting an identity alignment changes nothing")
    }

    func test_editingBackToIdentity_storesNoAlignment() {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignmentScale(2)
        XCTAssertTrue(model.hasAlignment)
        model.setAlignmentScale(1)
        XCTAssertFalse(model.hasAlignment, "identity is stored as none, whichever way it was reached")
        XCTAssertNil(model.link?.alignment)
    }

    func test_assigningAnotherPayload_keepsTheAlignmentAndSaysSo() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignmentOffset(SIMD3<Float>(0, 0.5, 0))
        model.flushPendingPersist()

        let other = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair_v2.untoldgs"), splatCount: 9)
        model.assign(payloadURL: other)
        XCTAssertEqual(model.link?.payloadPath, "Chair_v2.untoldgs")
        XCTAssertEqual(model.link?.alignment?.translation, SIMD3<Float>(0, 0.5, 0), "a re-cook shares the capture's frame")
        XCTAssertEqual(try storedLink()?.alignment?.translation, SIMD3<Float>(0, 0.5, 0))
        XCTAssertEqual(
            model.status,
            GaussianTwinInspectorModel.Status(message: "Linked Chair_v2.untoldgs (9 splats). Keeping the alignment stored for Chair.untoldgs (offset 0, 0.50, 0 m · yaw 0° · scale 1.00); Reset it if this capture has its own frame.", isError: false),
            "another capture is told the alignment came along, as the CLI warns"
        )

        model.assign(payloadURL: other)
        XCTAssertEqual(model.status?.message, "Linked Chair_v2.untoldgs (9 splats).", "the same payload again: nothing to point out")

        model.resetAlignment()
        model.flushPendingPersist()
        model.assign(payloadURL: payload)
        XCTAssertEqual(model.status?.message, "Linked Chair.untoldgs (4 splats).", "and nothing without an alignment to keep")
    }

    /// The record was edited out of process (`untoldengine gaussian-link --in-place` with the
    /// editor open): no notification reaches the editor, but the next model over the entity
    /// (a reselection) reads the file and brings the placements' link components and twins in
    /// line with it, so the fields never show numbers the splat is not drawn with.
    func test_freshModel_mirrorsARecordEditedOutOfProcessOntoTheScene() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let second = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        model.setSwapDistance(5)
        model.flushPendingPersist()
        XCTAssertNil(linkComponent()?.alignment)
        XCTAssertEqual(twin(second)?.options.swapDistanceMeters, 5)

        var edited = try XCTUnwrap(try storedLink())
        edited.alignment = sample
        edited.swapDistanceMeters = 2
        let patched = try UntoldAssetPatcher.settingGaussianAsset(edited, onEntity: 0, in: Data(contentsOf: untold))
        try patched.write(to: untold)
        XCTAssertNil(linkComponent()?.alignment, "nothing in the editor noticed")
        XCTAssertEqual(model.link?.swapDistanceMeters, 5)

        let reopened = makeModel()
        XCTAssertEqual(reopened.link, edited)
        XCTAssertEqual(reopened.alignment, sample)
        for placement in [entity, second] {
            XCTAssertEqual(linkComponent(placement)?.alignment, sample, "the link component follows the file")
            XCTAssertEqual(linkComponent(placement)?.swapDistanceMeters, 2)
            XCTAssertEqual(twin(placement)?.options.alignment, sample, "and so does the previewed twin")
            XCTAssertEqual(twin(placement)?.options.swapDistanceMeters, 2)
        }
        XCTAssertFalse(reopened.hasPendingPersist, "mirroring the file is not an edit")
        XCTAssertNil(reopened.status)

        // An edit from here starts from what is drawn.
        reopened.setAlignmentOffset(.zero)
        XCTAssertEqual(twin()?.options.alignment, GaussianSplatAlignment(yawDegrees: 12, scale: 1.05))
        undoManager.undo()
        XCTAssertEqual(twin()?.options.alignment, sample, "undo lands on the file's alignment, which is what was drawn")

        // A record removed out of process takes the component and the twin with it.
        try UntoldAssetPatcher.removingGaussianAsset(onEntity: 0, in: Data(contentsOf: untold)).write(to: untold)
        let reopenedAgain = makeModel()
        XCTAssertNil(reopenedAgain.link)
        XCTAssertNil(linkComponent())
        XCTAssertNil(twin())
    }

    func test_freshModel_leavesASceneAlreadyInStepAlone() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignmentYawDegrees(30)
        model.flushPendingPersist()
        let before = try XCTUnwrap(twin())
        XCTAssertTrue(GaussianTwinLinkPersistence.linkComponentMatches(model.link, on: entity, untoldURL: untold))

        let reopened = makeModel()
        XCTAssertEqual(reopened.link, model.link)
        XCTAssertTrue(twin() === before, "the running twin is not relinked")
        XCTAssertEqual(before.options.alignment?.yawDegrees, 30)
        XCTAssertFalse(GaussianTwinLinkPersistence.linkComponentMatches(nil, on: entity, untoldURL: untold))
        XCTAssertTrue(GaussianTwinLinkPersistence.linkComponentMatches(nil, on: GaussianTwinTestFixtures.makeMeshEntity(name: "Table", assetURL: untold), untoldURL: untold), "no link, no component: in step")
    }

    func test_alignmentValues_areClampedToTheirRanges() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)

        model.setAlignmentScale(0)
        XCTAssertEqual(model.alignmentScale, GaussianTwinInspector.alignmentScaleRange.lowerBound, "scale stays above zero")
        model.setAlignmentScale(-5)
        XCTAssertEqual(model.alignmentScale, 0.01)
        model.setAlignmentScale(1000)
        XCTAssertEqual(model.alignmentScale, 100)
        model.setAlignmentScale(.nan)
        XCTAssertEqual(model.alignmentScale, 100, "non-finite input keeps the value")
        model.setAlignmentScale(2.5)
        XCTAssertEqual(model.alignmentScale, 2.5)

        model.setAlignmentYawDegrees(.infinity)
        XCTAssertEqual(model.alignmentYawDegrees, 0)
        model.setAlignmentYawDegrees(-450)
        XCTAssertEqual(model.alignmentYawDegrees, -450, "yaw is any finite angle")

        model.setAlignmentOffset(SIMD3<Float>(1, .nan, 3))
        XCTAssertEqual(model.alignmentOffset, SIMD3<Float>(1, 0, 3), "a non-finite component keeps its previous value")

        XCTAssertEqual(GaussianTwinInspector.clampedAlignmentScale(0.5, previous: 1), 0.5)
        XCTAssertEqual(GaussianTwinInspector.clampedAlignmentScale(.infinity, previous: 3), 3)
        XCTAssertEqual(GaussianTwinInspector.clampedAlignmentYaw(.nan, previous: 7), 7)
        XCTAssertTrue(try XCTUnwrap(model.link?.alignment).isValid, "what the patcher accepts")
        model.flushPendingPersist()
        XCTAssertEqual(model.status?.isError, false, "and wrote")
    }

    func test_alignmentEdit_withoutALinkIsIgnored() {
        let model = makeModel()
        model.setAlignmentScale(2)
        model.setAlignmentOffset(SIMD3<Float>(1, 1, 1))
        model.resetAlignment()
        XCTAssertNil(model.link)
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(model.alignmentDescription, "identity")
    }

    func test_alignmentDescription_formatsOffsetYawAndScale() {
        XCTAssertEqual(GaussianTwinInspector.alignmentDescription(nil), "identity")
        XCTAssertEqual(GaussianTwinInspector.alignmentDescription(.identity), "identity", "an explicit identity reads the same")
        XCTAssertEqual(GaussianTwinInspector.alignmentDescription(sample), "offset 0.12, 0, −0.30 m · yaw 12° · scale 1.05")
        XCTAssertEqual(
            GaussianTwinInspector.alignmentDescription(GaussianSplatAlignment(translation: SIMD3<Float>(-1, 2.5, 0), yawDegrees: -22.5, scale: 1)),
            "offset −1, 2.50, 0 m · yaw −22.5° · scale 1.00"
        )
        XCTAssertEqual(
            GaussianTwinInspector.alignmentDescription(GaussianSplatAlignment(scale: 0.5)),
            "offset 0, 0, 0 m · yaw 0° · scale 0.50"
        )
    }

    // MARK: - Persistence: the record's flag and fields

    func test_persistence_writesTheFlagAndFieldsAndReadsThemBack() throws {
        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold, swapDistanceMeters: 4, alignment: sample)
        XCTAssertEqual(link.alignment, sample)
        XCTAssertEqual(link.flags, UntoldGaussianAssetFlags.meshTwin, "the flag is derived on write, never held in the link")

        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: link)
        let record = try XCTUnwrap(try storedRecord())
        XCTAssertEqual(record.flags, UntoldGaussianAssetFlags.meshTwin | UntoldGaussianAssetFlags.alignment)
        XCTAssertEqual(record.alignment, sample)
        XCTAssertEqual(GaussianTwinLinkPersistence.readTwinLink(entityId: entity), link)
        XCTAssertEqual(try GaussianTwinLinkPersistence.readTwinLink(target: GaussianTwinLinkTarget(untoldURL: untold, entityRecordId: 0)), link)

        // Mirrored onto the component and the twin as the loader and the system would have it.
        let component = try XCTUnwrap(linkComponent())
        XCTAssertEqual(component.alignment, sample)
        XCTAssertEqual(component.swapDistanceMeters, 4)
        XCTAssertEqual(twin()?.options.alignment, sample)
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 4)
        XCTAssertFalse(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped), "the preview runs the link's own options")

        // Clearing it clears the flag and the component.
        var cleared = link
        cleared.alignment = nil
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: cleared)
        XCTAssertEqual(try storedRecord()?.flags, UntoldGaussianAssetFlags.meshTwin)
        XCTAssertNil(try storedLink()?.alignment)
        XCTAssertNil(linkComponent()?.alignment)
        XCTAssertNil(twin()?.options.alignment)
    }

    func test_persistence_rejectsAnInvalidAlignment() throws {
        var link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        link.alignment = GaussianSplatAlignment(scale: 0)
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: link)) { error in
            guard case let .patchFailed(reason)? = error as? GaussianTwinLinkError else {
                return XCTFail("expected patchFailed, got \(error)")
            }
            XCTAssertTrue(reason.contains("alignment"), reason)
        }
        XCTAssertNil(try storedLink(), "the file is left alone")
    }

    func test_oldLinkWithoutAlignment_isUnchanged() throws {
        // A record written before alignment existed: no flag, zero words.
        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold, swapDistanceMeters: 2)
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: link)
        let record = try XCTUnwrap(try storedRecord())
        XCTAssertEqual(record.flags, UntoldGaussianAssetFlags.meshTwin)
        XCTAssertNil(record.alignment)
        XCTAssertEqual(record.alignmentTranslation, .zero)
        XCTAssertEqual(record.alignmentScale, 0)

        let model = makeModel()
        XCTAssertEqual(model.link, link)
        XCTAssertNil(model.link?.alignment)
        XCTAssertEqual(model.alignmentDescription, "identity")
        XCTAssertTrue(GaussianTwinInspector.isAvailable(entity), "availability does not depend on the alignment")

        // An unrelated edit rewrites the record without inventing an alignment.
        model.setSwapDistance(6)
        model.flushPendingPersist()
        XCTAssertEqual(try storedRecord()?.flags, UntoldGaussianAssetFlags.meshTwin)
        XCTAssertNil(try storedLink()?.alignment)
    }

    // MARK: - Align mode

    func test_alignMode_forcesThePreviewAndTheShellsOffWhileOn() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let second = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        model.setSwapDistance(5)
        model.flushPendingPersist()
        XCTAssertEqual(twin(second)?.options.swapDistanceMeters, 5)
        XCTAssertFalse(model.isAlignMode)
        XCTAssertFalse(GaussianTwinAlignMode.shared.isActive)

        model.setAlignMode(true)
        XCTAssertTrue(model.isAlignMode)
        XCTAssertTrue(GaussianTwinAlignMode.shared.isActive)
        XCTAssertEqual(GaussianTwinAlignMode.shared.entities, [entity, second], "every placement of the record")
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell, "shells off")
        for placement in [entity, second] {
            let options = try XCTUnwrap(twin(placement)?.options)
            XCTAssertEqual(options.swapDistanceMeters, 0, "the twin shows at any distance")
            XCTAssertTrue(options.showsMeshWhileSwapped, "with the mesh still drawing")
            XCTAssertEqual(linkComponent(placement)?.swapDistanceMeters, 5, "the link component is untouched")
        }
        XCTAssertEqual(model.link?.swapDistanceMeters, 5, "and so is the model's link")
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 5)
        XCTAssertTrue(GaussianTwinInspector.isAvailable(entity), "availability is unchanged")

        // Edits made while aligning keep the override and reach the file without it.
        model.setAlignmentYawDegrees(30)
        XCTAssertEqual(twin()?.options.alignment?.yawDegrees, 30)
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 0)
        XCTAssertTrue(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped))
        scheduled.last?.action()
        let stored = try XCTUnwrap(try storedLink())
        XCTAssertEqual(stored.swapDistanceMeters, 5, "the link on disk keeps its swap distance")
        XCTAssertEqual(stored.alignment?.yawDegrees, 30)
        XCTAssertTrue(GaussianTwinAlignMode.shared.isActive, "a persist does not end the mode")
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 0, "nor does it drop the override")

        model.setAlignMode(false)
        XCTAssertFalse(model.isAlignMode)
        XCTAssertFalse(GaussianTwinAlignMode.shared.isActive)
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell, "shells back")
        for placement in [entity, second] {
            let options = try XCTUnwrap(twin(placement)?.options)
            XCTAssertEqual(options.swapDistanceMeters, 5, "the link's own options again")
            XCTAssertFalse(options.showsMeshWhileSwapped)
            XCTAssertEqual(options.alignment?.yawDegrees, 30, "the alignment stays: it is the link's")
        }
        let component = try XCTUnwrap(linkComponent())
        XCTAssertEqual(twin()?.options, GaussianTwinOptions(link: component))
    }

    /// A placement whose mesh lands after the mode was entered (a drop still loading, a scene
    /// still opening) is not in the set taken on entering; the next live edit finds it, forces
    /// it like the others, and leaving restores it too.
    func test_alignMode_adoptsAPlacementThatArrivesWhileOn() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(5)
        model.flushPendingPersist()
        model.setAlignMode(true)
        XCTAssertEqual(GaussianTwinAlignMode.shared.entities, [entity])
        XCTAssertEqual(GaussianTwinAlignMode.shared.target, model.target)

        // Lands now, with the link the loader attaches from the file, at the link's options.
        let late = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        GaussianTwinLinkPersistence.applyLinkComponent(model.link, to: late, untoldURL: untold)
        GaussianTwinSystem.shared.resetSceneLinkAdoption()
        GaussianTwinSystem.shared.adoptSceneLinks()
        XCTAssertEqual(twin(late)?.options.swapDistanceMeters, 5)
        XCTAssertFalse(try XCTUnwrap(twin(late)?.options.showsMeshWhileSwapped))

        model.setAlignmentYawDegrees(15)
        XCTAssertEqual(GaussianTwinAlignMode.shared.entities, [entity, late], "the edit brought it into the mode")
        XCTAssertEqual(twin(late)?.options.swapDistanceMeters, 0, "forced like the others")
        XCTAssertTrue(try XCTUnwrap(twin(late)?.options.showsMeshWhileSwapped))
        XCTAssertEqual(twin(late)?.options.alignment?.yawDegrees, 15)
        XCTAssertEqual(linkComponent(late)?.swapDistanceMeters, 5, "its link component is the file's")

        model.setAlignMode(false)
        XCTAssertTrue(GaussianTwinAlignMode.shared.entities.isEmpty)
        XCTAssertNil(GaussianTwinAlignMode.shared.target)
        XCTAssertEqual(twin(late)?.options.swapDistanceMeters, 5, "restored with the others")
        XCTAssertFalse(try XCTUnwrap(twin(late)?.options.showsMeshWhileSwapped))
        XCTAssertEqual(twin(late)?.options.alignment?.yawDegrees, 15)
    }

    func test_alignMode_restoresADebugOptionThatWasAlreadyOn() {
        GaussianDebugOptions.shared.disableOccluderShell = true
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignMode(true)
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell)
        model.setAlignMode(false)
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell, "left as it was found")
    }

    func test_alignMode_needsALinkAndEndsWithIt() throws {
        let model = makeModel()
        model.setAlignMode(true)
        XCTAssertFalse(model.isAlignMode, "nothing to align without a link")
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell)

        model.assign(payloadURL: payload)
        model.setAlignMode(true)
        XCTAssertTrue(model.isAlignMode)
        model.removeLink()
        XCTAssertFalse(model.isAlignMode, "removing the link ends it")
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell)
        XCTAssertNil(twin())

        undoManager.undo()
        XCTAssertNotNil(model.link, "the link is back")
        XCTAssertFalse(model.isAlignMode, "but the mode is not: it is session state, not part of the link")
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 0)
        XCTAssertFalse(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped))
    }

    func test_alignMode_endsWhenUndoRemovesTheLink() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(3)
        model.flushPendingPersist()
        model.setAlignMode(true)
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell)

        undoManager.undo() // swap distance
        XCTAssertTrue(model.isAlignMode, "an undo that keeps the link keeps the mode")
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 0, "still forced")
        XCTAssertTrue(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped))

        undoManager.undo() // assign
        XCTAssertNil(model.link)
        XCTAssertFalse(model.isAlignMode, "undo to no link ends it")
        XCTAssertFalse(GaussianTwinAlignMode.shared.isActive)
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell, "shells restored")
        XCTAssertNil(twin())

        undoManager.redo()
        XCTAssertNotNil(model.link)
        XCTAssertFalse(model.isAlignMode)
        XCTAssertFalse(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped), "the link's own options")
    }

    func test_alignMode_endsWhenTheModelGoesAway() throws {
        var model: GaussianTwinInspectorModel? = makeModel()
        model?.assign(payloadURL: payload)
        model?.setSwapDistance(4)
        model?.setAlignMode(true)
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell)
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 0)

        // Deselecting or selecting another entity releases the section's model.
        model = nil
        XCTAssertFalse(GaussianTwinAlignMode.shared.isActive)
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell, "deinit restores the shells")
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 4, "and the link's swap distance (the pending edit was flushed)")
        XCTAssertFalse(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped))
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 4)
    }

    func test_alignMode_endsOnSceneResetAndWhenThePreviewGoesOff() throws {
        let suite = "GaussianTwinAlignmentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = GaussianTwinPreviewSettings(defaults: defaults, installer: .init(install: {}, uninstall: {}, resetAdoption: {}))
        settings.activate()

        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(2)
        model.flushPendingPersist()

        model.setAlignMode(true)
        XCTAssertTrue(model.isAlignMode)
        settings.sceneDidReset()
        XCTAssertFalse(model.isAlignMode, "the scene's entities are gone; their ids will be reused")
        XCTAssertFalse(GaussianTwinAlignMode.shared.isActive)
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell)
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 2, "an entity that is still there gets its own options back")

        model.setAlignMode(true)
        XCTAssertTrue(model.isAlignMode)
        settings.isEnabled = false
        XCTAssertFalse(model.isAlignMode, "no preview, no align mode")
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell)
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 2)
        XCTAssertFalse(try XCTUnwrap(twin()?.options.showsMeshWhileSwapped))

        settings.isEnabled = true
        XCTAssertFalse(model.isAlignMode, "turning the preview back on does not re-enter it")
    }

    func test_alignMode_passesBetweenModelsAndIgnoresAStrangersLeave() {
        let first = makeModel()
        first.assign(payloadURL: payload)
        first.setAlignMode(true)

        let second = makeModel()
        XCTAssertFalse(second.isAlignMode, "the mode belongs to the model that entered")
        second.setAlignMode(false)
        XCTAssertTrue(first.isAlignMode, "a model that did not enter cannot end it")
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell)

        second.setAlignMode(true)
        XCTAssertTrue(second.isAlignMode, "taken over")
        XCTAssertFalse(first.isAlignMode)
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell)
        XCTAssertEqual(twin()?.options.swapDistanceMeters, 0)

        second.setAlignMode(false)
        XCTAssertFalse(GaussianTwinAlignMode.shared.isActive)
        XCTAssertFalse(GaussianDebugOptions.shared.disableOccluderShell, "restored once, to what it was before the first entered")
    }

    func test_alignMode_leavesTheDebugOptionAloneWhenLeftTwice() {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setAlignMode(true)
        model.setAlignMode(false)
        GaussianDebugOptions.shared.disableOccluderShell = true
        model.setAlignMode(false)
        GaussianTwinAlignMode.shared.leave()
        XCTAssertTrue(GaussianDebugOptions.shared.disableOccluderShell, "a leave with nothing to leave changes nothing")
    }
}
