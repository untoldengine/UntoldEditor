//
//  GizmoLocalSpaceLightTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Metal
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// Local space carried through the gizmo's light paths, and the gizmo
/// following a turn of its entity made elsewhere than on the gizmo.
final class GizmoLocalSpaceLightTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveEntity: EntityID = .invalid
    private var originalSpace: TransformSpace!
    private var originalSnap: EditorSnapSettings!
    private var originalIsEditingAllowed: (() -> Bool)!

    override func setUp() {
        super.setUp()
        originalScene = scene
        originalActiveEntity = activeEntity
        originalSpace = EditorViewportSettings.shared.transformSpace
        originalSnap = gizmoSnapSettings
        originalIsEditingAllowed = EditorUndoManager.shared.isEditingAllowed
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        // The gizmo's handles are meshes.
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()
        scene = Scene()
        // World space unless a test says otherwise, whatever an earlier run left.
        EditorViewportSettings.shared.transformSpace = .world
        activeEntity = .invalid
        parentEntityIdGizmo = .invalid
        gizmoActive = false
        activeHitGizmoEntity = .invalid
        directionHandleEntityId = .invalid
        gizmoSnapSettings = EditorSnapSettings(defaults: nil)
        EditorUndoManager.shared.isEditingAllowed = { true }
        EditorUndoManager.shared.clear()
    }

    override func tearDown() {
        endGizmoDrag()
        removeGizmo()
        activeHitGizmoEntity = .invalid
        EditorUndoManager.shared.clear()
        EditorUndoManager.shared.isEditingAllowed = originalIsEditingAllowed
        gizmoSnapSettings = originalSnap
        EditorViewportSettings.shared.transformSpace = originalSpace
        activeEntity = originalActiveEntity
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    private func makeLight(turnedBy degrees: Float, about axis: simd_float3) -> EntityID {
        let light = createEntity()
        registerTransformComponent(entityId: light)
        registerComponent(entityId: light, componentType: LightComponent.self)
        rotateTo(entityId: light, rotation: simd_quatf(angle: degrees * .pi / 180, axis: axis))
        return light
    }

    private func handle(mode: TransformManipulationMode, axis: TransformAxis) -> EntityID {
        getEntityChildren(parentId: parentEntityIdGizmo).first(where: {
            guard let handle = scene.get(component: GizmoHandleComponent.self, for: $0) else { return false }
            return handle.mode == mode && handle.axis == axis && hasComponent(entityId: $0, componentType: GizmoHitProxyComponent.self) == false
        }) ?? .invalid
    }

    private func assertEqual(_ vector: simd_float3, _ expected: simd_float3, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vector.x, expected.x, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(vector.y, expected.y, accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(vector.z, expected.z, accuracy: 0.001, message, file: file, line: line)
    }

    /// Where the direction handle is drawn, from the gizmo root: its offset
    /// in the root's frame, turned as the root is.
    private func directionHandleFromTheRoot() -> simd_float3 {
        let directionHandle = handle(mode: .lightRotate, axis: .none)
        guard directionHandle != .invalid else {
            XCTFail("no direction handle")
            return .zero
        }
        return simd_act(getRotationQuaternion(entityId: parentEntityIdGizmo), getLocalPosition(entityId: directionHandle))
    }

    func test_theDirectionHandle_liesAlongTheEmission_inBothSpaces() {
        // Pitched 45° down: it emits along (0, -0.707, -0.707).
        let light = makeLight(turnedBy: -45, about: simd_float3(1, 0, 0))
        activeEntity = light
        let emission = simd_normalize(simd_float3(0, -1, -1))

        EditorViewportSettings.shared.transformSpace = .world
        createGizmo(mode: .translate)
        assertEqual(directionHandleFromTheRoot(), emission, "World space")

        EditorViewportSettings.shared.transformSpace = .local
        createGizmo(mode: .translate)
        assertEqual(directionHandleFromTheRoot(), emission, "Local space: the root is turned with the light, the offset is not turned again")
        assertEqual(getLocalPosition(entityId: handle(mode: .lightRotate, axis: .none)), simd_float3(0, 0, -1), "along the light's own -Z")
    }

    func test_inLocalSpace_anAreaLightsScaleHandle_changesTheComponentItIsNamedFor() {
        let area = createEntity()
        createAreaLight(entityId: area)
        // Turned 90° about X, as a light that points down is: its Y axis runs along the world's -Z.
        rotateTo(entityId: area, rotation: simd_quatf(angle: -.pi / 2, axis: simd_float3(1, 0, 0)))
        activeEntity = area
        EditorViewportSettings.shared.transformSpace = .local
        createGizmo(mode: .scale)
        activeHitGizmoEntity = handle(mode: .scale, axis: .y)
        XCTAssertNotEqual(activeHitGizmoEntity, .invalid)
        let scaleBefore = getScale(entityId: area)

        // The handle's axis in the world is (0, 0, -1): a drag of two units along it.
        beginGizmoDrag(ray: GizmoDragRay(origin: simd_float3(5, 0, 0), direction: simd_float3(-1, 0, 0)))
        updateGizmoDrag(ray: GizmoDragRay(origin: simd_float3(5, 0, -2), direction: simd_float3(-1, 0, 0)))

        let scale = getScale(entityId: area)
        XCTAssertEqual(scale.y, scaleBefore.y + 2, accuracy: 0.001, "the green handle scales the light's own Y")
        XCTAssertEqual(scale.z, scaleBefore.z, accuracy: 0.001, "and not Z, which the handle's world direction named")
        XCTAssertEqual(scale.x, scaleBefore.x, accuracy: 0.001)
    }

    func test_aTurnTypedInTheInspector_turnsTheGizmoWithTheEntity_inLocalSpace() {
        let entity = createEntity()
        registerTransformComponent(entityId: entity)
        activeEntity = entity
        EditorViewportSettings.shared.transformSpace = .local
        createGizmo(mode: .translate)
        XCTAssertEqual(abs(getRotationQuaternion(entityId: parentEntityIdGizmo).real), 1, accuracy: 0.001, "unturned, as the entity")

        editTransform(of: entity) {
            applyAxisRotations(entityId: entity, axis: simd_float3(0, 90, 0))
        }

        let root = simd_normalize(getRotationQuaternion(entityId: parentEntityIdGizmo))
        let turn = simd_normalize(getRotationQuaternion(entityId: entity))
        XCTAssertEqual(abs(simd_dot(root.vector, turn.vector)), 1, accuracy: 0.001, "the gizmo turned with it")
        XCTAssertEqual(abs(root.vector.y), sin(Float.pi / 4), accuracy: 0.001, "a quarter turn about Y")
        XCTAssertEqual(EditorUndoManager.shared.undoHistory.count, 1)

        EditorViewportSettings.shared.transformSpace = .world
        editTransform(of: entity) {
            applyAxisRotations(entityId: entity, axis: simd_float3(0, 45, 0))
        }
        XCTAssertEqual(abs(getRotationQuaternion(entityId: parentEntityIdGizmo).real), 1, accuracy: 0.001, "in World space the gizmo keeps the world's axes")
    }
}
