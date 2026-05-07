//
//  EditorUndoManagerTests.swift
//  UntoldEditorTests
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class EditorUndoManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        scene = Scene()
        EditorUndoManager.shared.clear()
        EditorUndoManager.shared.onStateRestored = nil
    }

    override func tearDown() {
        EditorUndoManager.shared.clear()
        EditorUndoManager.shared.onStateRestored = nil
        super.tearDown()
    }

    func test_nameChangeUndoRedo_restoresEntityName() {
        let entity = createEntity()
        setEntityName(entityId: entity, name: "Before")

        setEntityName(entityId: entity, name: "After")
        EditorUndoManager.shared.registerNameChange(entityId: entity, oldName: "Before", newName: "After")

        XCTAssertTrue(EditorUndoManager.shared.canUndo)
        XCTAssertFalse(EditorUndoManager.shared.canRedo)

        EditorUndoManager.shared.undo()

        XCTAssertEqual(getEntityName(entityId: entity), "Before")
        XCTAssertFalse(EditorUndoManager.shared.canUndo)
        XCTAssertTrue(EditorUndoManager.shared.canRedo)

        EditorUndoManager.shared.redo()

        XCTAssertEqual(getEntityName(entityId: entity), "After")
        XCTAssertTrue(EditorUndoManager.shared.canUndo)
        XCTAssertFalse(EditorUndoManager.shared.canRedo)
    }

    func test_transformChangeUndoRedo_restoresPositionRotationAndScale() {
        let entity = createEntity()
        registerTransformComponent(entityId: entity)

        translateTo(entityId: entity, position: simd_float3(1, 2, 3))
        applyAxisRotations(entityId: entity, axis: simd_float3(10, 20, 30))
        scaleTo(entityId: entity, scale: simd_float3(1, 1, 1))
        let before = EditorTransformSnapshot(entityId: entity)

        translateTo(entityId: entity, position: simd_float3(4, 5, 6))
        applyAxisRotations(entityId: entity, axis: simd_float3(40, 50, 60))
        scaleTo(entityId: entity, scale: simd_float3(2, 3, 4))
        EditorUndoManager.shared.registerTransformChange(
            entityId: entity,
            before: before,
            after: EditorTransformSnapshot(entityId: entity)
        )

        EditorUndoManager.shared.undo()

        XCTAssertEqual(getLocalPosition(entityId: entity), simd_float3(1, 2, 3))
        XCTAssertEqual(getAxisRotations(entityId: entity), simd_float3(10, 20, 30))
        XCTAssertEqual(getScale(entityId: entity), simd_float3(1, 1, 1))

        EditorUndoManager.shared.redo()

        XCTAssertEqual(getLocalPosition(entityId: entity), simd_float3(4, 5, 6))
        XCTAssertEqual(getAxisRotations(entityId: entity), simd_float3(40, 50, 60))
        XCTAssertEqual(getScale(entityId: entity), simd_float3(2, 3, 4))
    }

    func test_beginAndCommitTransformEdit_coalescesToSingleCommand() {
        let entity = createEntity()
        registerTransformComponent(entityId: entity)

        translateTo(entityId: entity, position: .zero)
        EditorUndoManager.shared.beginTransformEdit(entityId: entity)
        translateTo(entityId: entity, position: simd_float3(1, 0, 0))
        translateTo(entityId: entity, position: simd_float3(2, 0, 0))
        translateTo(entityId: entity, position: simd_float3(3, 0, 0))
        EditorUndoManager.shared.commitTransformEdit(entityId: entity)

        EditorUndoManager.shared.undo()

        XCTAssertEqual(getLocalPosition(entityId: entity), .zero)

        EditorUndoManager.shared.redo()

        XCTAssertEqual(getLocalPosition(entityId: entity), simd_float3(3, 0, 0))
    }

    func test_valueChangeUndoRedo_supportsSSAOStyleSettings() {
        SSAOParams.shared.radius = 0.25

        SSAOParams.shared.radius = 0.75
        EditorUndoManager.shared.registerValueChange(
            name: "Change SSAO Radius",
            oldValue: Float(0.25),
            newValue: Float(0.75)
        ) { value in
            SSAOParams.shared.radius = value
        }

        EditorUndoManager.shared.undo()
        XCTAssertEqual(SSAOParams.shared.radius, 0.25, accuracy: 0.0001)

        EditorUndoManager.shared.redo()
        XCTAssertEqual(SSAOParams.shared.radius, 0.75, accuracy: 0.0001)
    }

    func test_valueChangeUndoRedo_supportsOtherEffectSettings() {
        BloomThresholdParams.shared.intensity = 0.2

        BloomThresholdParams.shared.intensity = 3.5
        EditorUndoManager.shared.registerValueChange(
            name: "Change Bloom Intensity",
            oldValue: Float(0.2),
            newValue: Float(3.5)
        ) { value in
            BloomThresholdParams.shared.intensity = value
        }

        EditorUndoManager.shared.undo()
        XCTAssertEqual(BloomThresholdParams.shared.intensity, 0.2, accuracy: 0.0001)

        EditorUndoManager.shared.redo()
        XCTAssertEqual(BloomThresholdParams.shared.intensity, 3.5, accuracy: 0.0001)
    }

    func test_postFXSnapshotUndoRedo_restoresPresetWideChanges() {
        ColorGradingParams.shared.enabled = false
        ColorGradingParams.shared.exposure = 0.0
        ColorGradingParams.shared.brightness = 0.0
        ColorGradingParams.shared.contrast = 1.0
        ColorGradingParams.shared.saturation = 1.0
        ColorGradingParams.shared.temperature = 0.0
        ColorGradingParams.shared.tint = 0.0
        BloomThresholdParams.shared.enabled = false
        BloomThresholdParams.shared.threshold = 0.5
        BloomThresholdParams.shared.intensity = 0.0
        VignetteParams.shared.enabled = false
        ChromaticAberrationParams.shared.enabled = false
        DepthOfFieldParams.shared.enabled = false
        SSAOParams.shared.enabled = false
        SSAOParams.shared.radius = 0.5
        SSAOParams.shared.bias = 0.025
        SSAOParams.shared.intensity = 0.0

        let before = EditorPostFXSnapshot()
        PostFX.apply(.cinematic)
        EditorUndoManager.shared.registerPostFXChange(
            name: "Apply Cinematic Preset",
            before: before,
            after: EditorPostFXSnapshot()
        )

        XCTAssertTrue(ColorGradingParams.shared.enabled)
        XCTAssertTrue(SSAOParams.shared.enabled)
        XCTAssertEqual(ColorGradingParams.shared.exposure, -0.2, accuracy: 0.0001)

        EditorUndoManager.shared.undo()

        XCTAssertFalse(ColorGradingParams.shared.enabled)
        XCTAssertFalse(SSAOParams.shared.enabled)
        XCTAssertEqual(ColorGradingParams.shared.exposure, 0.0, accuracy: 0.0001)
        XCTAssertEqual(SSAOParams.shared.radius, 0.5, accuracy: 0.0001)

        EditorUndoManager.shared.redo()

        XCTAssertTrue(ColorGradingParams.shared.enabled)
        XCTAssertTrue(SSAOParams.shared.enabled)
        XCTAssertEqual(ColorGradingParams.shared.exposure, -0.2, accuracy: 0.0001)
        XCTAssertEqual(SSAOParams.shared.intensity, PostFXPreset.cinematic.ssaoIntensity, accuracy: 0.0001)
    }

    func test_noopChangesAreNotRegistered() {
        let entity = createEntity()
        setEntityName(entityId: entity, name: "Same")

        EditorUndoManager.shared.registerNameChange(entityId: entity, oldName: "Same", newName: "Same")

        XCTAssertFalse(EditorUndoManager.shared.canUndo)
        XCTAssertFalse(EditorUndoManager.shared.canRedo)
    }
}
