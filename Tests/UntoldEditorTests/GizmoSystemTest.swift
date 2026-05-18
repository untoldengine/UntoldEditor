//
//  GizmoSystemTest.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class GizmoSystemTests: XCTestCase {
    private var originalActiveEntity: EntityID!
    private var originalParentGizmo: EntityID!
    private var originalGizmoActive: Bool!
    private var originalActiveHitGizmoEntity: EntityID!
    private var originalDirectionHandleEntityId: EntityID!

    #if canImport(AppKit)
        /// Editor controller mock up
        final class TestEditorController {
            enum Axis { case x, y, z, none }
            enum Mode { case translate, rotate, scale, lightRotate, none }
            var activeAxis: Axis = .none
            var activeMode: Mode = .none
        }
    #endif

    override func setUp() {
        super.setUp()
        originalActiveEntity = activeEntity
        originalParentGizmo = parentEntityIdGizmo
        originalGizmoActive = gizmoActive
        originalActiveHitGizmoEntity = activeHitGizmoEntity
        originalDirectionHandleEntityId = directionHandleEntityId

        // Put engine in a clean state
        activeEntity = .invalid
        parentEntityIdGizmo = .invalid
        gizmoActive = false
        activeHitGizmoEntity = .invalid
        directionHandleEntityId = .invalid

        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure("Metal device is not available.")
            return
        }

        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()

        let sharedSelectionManager = SelectionManager()
        editorController = EditorController(selectionManager: sharedSelectionManager)
    }

    override func tearDown() {
        if parentEntityIdGizmo != .invalid {
            removeGizmo()
        }
        endGizmoDrag()
        activeEntity = originalActiveEntity
        parentEntityIdGizmo = originalParentGizmo
        gizmoActive = originalGizmoActive
        activeHitGizmoEntity = originalActiveHitGizmoEntity
        directionHandleEntityId = originalDirectionHandleEntityId

        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEntity(name: String? = nil,
                            pos: SIMD3<Float>? = nil,
                            isLight: Bool = false) -> EntityID
    {
        let e = createEntity()
        if !hasComponent(entityId: e, componentType: LocalTransformComponent.self) {
            registerTransformComponent(entityId: e)
        }
        if let name { setEntityName(entityId: e, name: name) }
        if let p = pos { translateTo(entityId: e, position: p) }
        if isLight { registerComponent(entityId: e, componentType: LightComponent.self) }
        return e
    }

    private func makeGizmoHandle(mode: TransformManipulationMode, axis: TransformAxis) -> EntityID {
        let e = makeEntity(name: "metadataHandle")
        registerComponent(entityId: e, componentType: GizmoComponent.self)
        let handle = scene.assign(to: e, component: GizmoHandleComponent.self)
        handle?.mode = mode
        handle?.axis = axis
        return e
    }

    private func findGizmoHandle(mode: TransformManipulationMode, axis: TransformAxis) -> EntityID {
        getEntityChildren(parentId: parentEntityIdGizmo).first(where: {
            guard let handle = scene.get(component: GizmoHandleComponent.self, for: $0) else { return false }
            return handle.mode == mode && handle.axis == axis
        }) ?? .invalid
    }

    private func rayThroughGizmoAxis(_ axis: TransformAxis, amount: Float) -> GizmoDragRay {
        switch axis {
        case .x:
            return GizmoDragRay(origin: SIMD3<Float>(amount, 1.0, 0.0), direction: SIMD3<Float>(0.0, -1.0, 0.0))
        case .y:
            return GizmoDragRay(origin: SIMD3<Float>(1.0, amount, 0.0), direction: SIMD3<Float>(-1.0, 0.0, 0.0))
        case .z:
            return GizmoDragRay(origin: SIMD3<Float>(0.0, 1.0, amount), direction: SIMD3<Float>(0.0, -1.0, 0.0))
        case .none:
            return GizmoDragRay(origin: SIMD3<Float>(0.0, 1.0, 0.0), direction: SIMD3<Float>(0.0, -1.0, 0.0))
        }
    }

    private func vector(for axis: TransformAxis, amount: Float) -> SIMD3<Float> {
        switch axis {
        case .x:
            return SIMD3<Float>(amount, 0.0, 0.0)
        case .y:
            return SIMD3<Float>(0.0, amount, 0.0)
        case .z:
            return SIMD3<Float>(0.0, 0.0, amount)
        case .none:
            return .zero
        }
    }

    private func component(of vector: SIMD3<Float>, along axis: TransformAxis) -> Float {
        switch axis {
        case .x:
            return vector.x
        case .y:
            return vector.y
        case .z:
            return vector.z
        case .none:
            return 0.0
        }
    }

    private func assertNearlyEqual(_ lhs: simd_float3, _ rhs: simd_float3, accuracy: Float = 0.0001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - createGizmo()

    func test_createGizmo_noActiveEntity_doesNothing() {
        activeEntity = .invalid
        createGizmo(name: "translateGizmo")

        XCTAssertEqual(parentEntityIdGizmo, .invalid, "No gizmo should be created without an active entity.")
        XCTAssertFalse(gizmoActive, "gizmoActive should remain false.")
    }

    func test_createGizmo_createsParentAndActivatesAtActiveEntityPosition() {
        // Arrange: active entity at a known spot
        let active = makeEntity(name: "Cube", pos: SIMD3<Float>(1, 2, 3))
        activeEntity = active

        // Act
        createGizmo(name: "translateGizmo")

        // Assert
        XCTAssertNotEqual(parentEntityIdGizmo, .invalid, "Gizmo parent should be created.")
        XCTAssertTrue(gizmoActive, "gizmoActive should be true after creation.")

        // Must have these components
        XCTAssertTrue(hasComponent(entityId: parentEntityIdGizmo, componentType: GizmoComponent.self),
                      "Gizmo parent must have GizmoComponent.")

        XCTAssertTrue(hasComponent(entityId: parentEntityIdGizmo, componentType: LocalTransformComponent.self),
                      "Gizmo parent must have Transform.")
        XCTAssertTrue(hasComponent(entityId: parentEntityIdGizmo, componentType: ScenegraphComponent.self),
                      "Gizmo parent must have SceneGraph.")

        // Position should match active entity
        XCTAssertEqual(getPosition(entityId: parentEntityIdGizmo),
                       getPosition(entityId: active),
                       "Gizmo should be placed at active entity’s position.")
    }

    func test_createGizmo_overridesNameForLightEntities() {
        let light = makeEntity(name: "KeyLight", pos: SIMD3<Float>(0, 0, 0), isLight: true)
        activeEntity = light

        // Passing any name; LightComponent should force "translateGizmo_light" internally.
        createGizmo(name: "translateGizmo")

        XCTAssertNotEqual(parentEntityIdGizmo, .invalid, "Gizmo should be created for lights too.")
        XCTAssertTrue(gizmoActive)
    }

    func test_createGizmo_usesMeshLocalOffsetForAnchorPosition() {
        let active = makeEntity(name: "ImportedChild", pos: SIMD3<Float>(0, 0, 0))
        var meshes = BasicPrimitives.createCube()
        XCTAssertFalse(meshes.isEmpty, "Expected primitive mesh for test setup.")

        let meshOffset = simd_float3(3.0, 4.0, 5.0)
        meshes[0].localSpace = matrix4x4Translation(meshOffset.x, meshOffset.y, meshOffset.z)
        meshes[0].worldSpace = meshes[0].localSpace

        let dummyURL = URL(fileURLWithPath: "/tmp/gizmo-anchor-test")
        associateMeshesToEntity(entityId: active, meshes: meshes)
        registerRenderComponent(entityId: active, meshes: meshes, url: dummyURL, assetName: "ImportedChild")

        activeEntity = active
        createGizmo(name: "translateGizmo")

        XCTAssertEqual(getLocalPosition(entityId: parentEntityIdGizmo), meshOffset,
                       "Gizmo should anchor at rendered mesh pivot when entity transform is zero.")
    }

    func test_createGizmo_usesRenderableChildrenBounds_whenSelectedEntityHasNoRenderComponent() {
        let parent = makeEntity(name: "ImportedRoot", pos: SIMD3<Float>(0, 0, 0))
        let child = makeEntity(name: "ImportedChild", pos: SIMD3<Float>(0, 0, 0))
        setParent(childId: child, parentId: parent)

        var meshes = BasicPrimitives.createCube()
        XCTAssertFalse(meshes.isEmpty, "Expected primitive mesh for test setup.")

        let meshOffset = simd_float3(6.0, 2.0, -3.0)
        meshes[0].localSpace = matrix4x4Translation(meshOffset.x, meshOffset.y, meshOffset.z)
        meshes[0].worldSpace = meshes[0].localSpace

        let dummyURL = URL(fileURLWithPath: "/tmp/gizmo-parent-anchor-test")
        associateMeshesToEntity(entityId: child, meshes: meshes)
        registerRenderComponent(entityId: child, meshes: meshes, url: dummyURL, assetName: "ImportedChild")

        activeEntity = parent
        createGizmo(name: "translateGizmo")

        XCTAssertEqual(getLocalPosition(entityId: parentEntityIdGizmo), meshOffset,
                       "Gizmo should anchor from renderable child bounds when selected entity is a non-render root.")
    }

    // MARK: - hitGizmoToolAxis()

    func test_hitGizmoToolAxis_usesHandleMetadata() {
        let valid = makeGizmoHandle(mode: .translate, axis: .x)
        XCTAssertTrue(hitGizmoToolAxis(entityId: valid), "Expected metadata handle to be recognized.")

        let legacyNameOnly = makeEntity(name: "xAxisTranslate")
        XCTAssertFalse(hitGizmoToolAxis(entityId: legacyNameOnly), "Names alone should not make an entity a gizmo handle.")

        let invalid = makeEntity(name: "randomNode")
        XCTAssertFalse(hitGizmoToolAxis(entityId: invalid), "Non-gizmo nodes should return false.")
        XCTAssertFalse(hitGizmoToolAxis(entityId: .invalid), "Invalid entity must return false.")
    }

    // MARK: - processGizmoAction()

    #if canImport(AppKit)
        private func makeEditorController() -> EditorController {
            let selectionManager = SelectionManager()
            return EditorController(selectionManager: selectionManager)
        }

        func test_processGizmoAction_setsAxisAndModeForKnownHandles() {
            // Use the real controller type
            let controller = makeEditorController()
            editorController = controller

            let cases: [(TransformManipulationMode, TransformAxis)] = [
                (.translate, .x),
                (.translate, .y),
                (.translate, .z),
                (.rotate, .x),
                (.rotate, .y),
                (.rotate, .z),
                (.scale, .x),
                (.scale, .y),
                (.scale, .z),
                (.lightRotate, .none),
            ]

            for (expMode, expAxis) in cases {
                let e = makeGizmoHandle(mode: expMode, axis: expAxis)
                processGizmoAction(entityId: e)

                XCTAssertEqual(controller.activeAxis, expAxis)
                XCTAssertEqual(controller.activeMode, expMode)
            }

            // Unknown handle → reset to none
            let unknown = makeEntity(name: "notAGizmoPart")
            processGizmoAction(entityId: unknown)
            XCTAssertEqual(controller.activeAxis, .none)
            XCTAssertEqual(controller.activeMode, .none)
        }

        func test_processGizmoAction_withoutEditorControllerDoesNotCrash() {
            editorController = nil
            let e = makeGizmoHandle(mode: .translate, axis: .x)

            processGizmoAction(entityId: e)

            XCTAssertTrue(hitGizmoToolAxis(entityId: e))
        }

        func test_processGizmoAction_earlyReturnOnInvalid() {
            // Arrange
            let controller = EditorController(selectionManager: SelectionManager())
            editorController = controller

            // Seed with values that should remain unchanged
            controller.activeAxis = .x
            controller.activeMode = .translate

            // Act
            processGizmoAction(entityId: .invalid)

            // Assert
            XCTAssertEqual(controller.activeAxis, .x, "Should not modify axis when entity is invalid.")
            XCTAssertEqual(controller.activeMode, .translate, "Should not modify mode when entity is invalid.")
        }
    #endif

    // MARK: - removeGizmo()

    func test_removeGizmo_destroysAndResets() {
        // Create an active entity and then a gizmo
        let active = makeEntity(name: "Box", pos: SIMD3<Float>(0, 0, 0))
        activeEntity = active
        createGizmo(name: "translateGizmo")

        let gizmoParent = parentEntityIdGizmo
        XCTAssertNotEqual(gizmoParent, .invalid)

        // Act
        removeGizmo()

        // Assert: back to defaults and parent entity gone
        XCTAssertEqual(parentEntityIdGizmo, .invalid)
        XCTAssertFalse(gizmoActive)
    }

    func test_createGizmo_addsTypedHandleMetadataToChildren() {
        let active = makeEntity(name: "Box", pos: SIMD3<Float>(0, 0, 0))
        activeEntity = active

        createGizmo(mode: .translate)

        let children = getEntityChildren(parentId: parentEntityIdGizmo)
        XCTAssertFalse(children.isEmpty)
        XCTAssertTrue(children.allSatisfy { hitGizmoToolAxis(entityId: $0) })
        XCTAssertTrue(children.contains {
            guard let handle = scene.get(component: GizmoHandleComponent.self, for: $0) else { return false }
            return handle.mode == .translate && handle.axis == .x
        })
    }

    func test_createRotateGizmo_addsHiddenHitProxyHandlesForEveryAxis() {
        let active = makeEntity(name: "RotatableBox", pos: SIMD3<Float>(0, 0, 0))
        activeEntity = active

        createGizmo(mode: .rotate)

        let children = getEntityChildren(parentId: parentEntityIdGizmo)
        for axis in [TransformAxis.x, .y, .z] {
            let proxies = children.filter {
                guard hasComponent(entityId: $0, componentType: GizmoHitProxyComponent.self),
                      let handle = scene.get(component: GizmoHandleComponent.self, for: $0)
                else {
                    return false
                }
                return handle.mode == .rotate && handle.axis == axis
            }

            XCTAssertFalse(proxies.isEmpty, "Expected hidden rotate hit proxies for \(axis)-axis.")
        }
    }

    func test_gizmoRootWorldPosition_usesGizmoParentWhenAvailable() {
        let active = makeEntity(name: "OffsetBox", pos: SIMD3<Float>(1, 2, 3))
        activeEntity = active
        createGizmo(mode: .translate)
        translateTo(entityId: parentEntityIdGizmo, position: SIMD3<Float>(9, 8, 7))

        XCTAssertEqual(gizmoRootWorldPosition(), SIMD3<Float>(9, 8, 7))
    }

    func test_axisGizmoDrag_translatesFromCurrentRayConstraint() {
        let active = makeEntity(name: "DraggedBox", pos: SIMD3<Float>(0, 0, 0))
        activeEntity = active
        createGizmo(mode: .translate)

        let xHandle = findGizmoHandle(mode: .translate, axis: .x)
        guard xHandle != .invalid else {
            XCTFail("Expected x-axis translate handle.")
            return
        }

        activeHitGizmoEntity = xHandle
        beginGizmoDrag(
            ray: GizmoDragRay(
                origin: SIMD3<Float>(0, 1, 0),
                direction: SIMD3<Float>(0, -1, 0)
            )
        )
        updateGizmoDrag(
            ray: GizmoDragRay(
                origin: SIMD3<Float>(2, 1, 0),
                direction: SIMD3<Float>(0, -1, 0)
            )
        )

        XCTAssertEqual(getLocalPosition(entityId: active), SIMD3<Float>(2, 0, 0))
        XCTAssertEqual(getPosition(entityId: parentEntityIdGizmo), SIMD3<Float>(2, 0, 0))
    }

    func test_axisGizmoDrag_translationTracksAbsoluteAxisPositionForAllAxes() {
        let axes: [TransformAxis] = [.x, .y, .z]

        for axis in axes {
            let startPosition = SIMD3<Float>(0.25, -0.5, 1.0)
            let active = makeEntity(name: "AbsoluteTranslate-\(axis)", pos: startPosition)
            activeEntity = active
            createGizmo(mode: .translate)

            let handle = findGizmoHandle(mode: .translate, axis: axis)
            guard handle != .invalid else {
                XCTFail("Expected translate handle for axis \(axis).")
                return
            }

            activeHitGizmoEntity = handle
            let startAxisAmount = component(of: startPosition, along: axis)
            beginGizmoDrag(ray: rayThroughGizmoAxis(axis, amount: startAxisAmount))
            updateGizmoDrag(ray: rayThroughGizmoAxis(axis, amount: startAxisAmount + 1.5))
            updateGizmoDrag(ray: rayThroughGizmoAxis(axis, amount: startAxisAmount - 0.75))

            let expectedEntityPosition = startPosition + vector(for: axis, amount: -0.75)
            let expectedGizmoPosition = startPosition + vector(for: axis, amount: -0.75)
            assertNearlyEqual(getLocalPosition(entityId: active), expectedEntityPosition)
            assertNearlyEqual(getPosition(entityId: parentEntityIdGizmo), expectedGizmoPosition)

            endGizmoDrag()
            removeGizmo()
        }
    }

    func test_axisGizmoDrag_scalesFromCurrentRayConstraint() {
        let active = makeEntity(name: "ScaledBox", pos: SIMD3<Float>(0, 0, 0))
        activeEntity = active
        createGizmo(mode: .scale)

        let xHandle = findGizmoHandle(mode: .scale, axis: .x)
        guard xHandle != .invalid else {
            XCTFail("Expected x-axis scale handle.")
            return
        }

        activeHitGizmoEntity = xHandle
        beginGizmoDrag(
            ray: GizmoDragRay(
                origin: SIMD3<Float>(0, 1, 0),
                direction: SIMD3<Float>(0, -1, 0)
            )
        )
        updateGizmoDrag(
            ray: GizmoDragRay(
                origin: SIMD3<Float>(0.5, 1, 0),
                direction: SIMD3<Float>(0, -1, 0)
            )
        )

        let scale = scene.get(component: LocalTransformComponent.self, for: active)?.scale
        XCTAssertEqual(scale, SIMD3<Float>(1.5, 1.0, 1.0))
    }

    func test_axisGizmoDrag_scaleTracksAbsoluteAxisPositionForAllAxes() {
        let axes: [TransformAxis] = [.x, .y, .z]

        for axis in axes {
            let active = makeEntity(name: "AbsoluteScale-\(axis)", pos: SIMD3<Float>(0, 0, 0))
            activeEntity = active
            createGizmo(mode: .scale)

            let handle = findGizmoHandle(mode: .scale, axis: axis)
            guard handle != .invalid else {
                XCTFail("Expected scale handle for axis \(axis).")
                return
            }

            activeHitGizmoEntity = handle
            beginGizmoDrag(ray: rayThroughGizmoAxis(axis, amount: 0.0))
            updateGizmoDrag(ray: rayThroughGizmoAxis(axis, amount: 0.4))
            updateGizmoDrag(ray: rayThroughGizmoAxis(axis, amount: 1.25))

            let expectedScale = SIMD3<Float>(repeating: 1.0) + vector(for: axis, amount: 1.25)
            guard let scale = scene.get(component: LocalTransformComponent.self, for: active)?.scale else {
                XCTFail("Expected LocalTransformComponent for scaled entity.")
                return
            }
            assertNearlyEqual(scale, expectedScale)

            endGizmoDrag()
            removeGizmo()
        }
    }

    func test_applyGizmoRotationDelta_repeatedYAxisRotationsStayOnYAxis() {
        let active = makeEntity(name: "RepeatedYRotation", pos: SIMD3<Float>(0, 0, 0))

        applyGizmoRotationDelta(entityId: active, axis: SIMD3<Float>(0, 1, 0), degrees: 30)
        applyGizmoRotationDelta(entityId: active, axis: SIMD3<Float>(0, 1, 0), degrees: 15)

        let orientation = getLocalOrientation(entityId: active)
        let forward = simd_normalize(orientation * SIMD3<Float>(0, 0, 1))
        let expectedForward = simd_normalize(
            simd_quatf(angle: Float.pi / 4, axis: SIMD3<Float>(0, 1, 0)).act(SIMD3<Float>(0, 0, 1))
        )

        assertNearlyEqual(forward, expectedForward, accuracy: 0.0002)
        XCTAssertEqual(forward.y, 0.0, accuracy: 0.0002)
    }

    func test_applyGizmoRotationDelta_afterExistingRotationUsesWorldAxis() {
        let active = makeEntity(name: "WorldAxisRotation", pos: SIMD3<Float>(0, 0, 0))

        applyGizmoRotationDelta(entityId: active, axis: SIMD3<Float>(1, 0, 0), degrees: 45)
        let beforeUp = getLocalOrientation(entityId: active) * SIMD3<Float>(0, 1, 0)

        applyGizmoRotationDelta(entityId: active, axis: SIMD3<Float>(0, 1, 0), degrees: 30)
        let afterUp = getLocalOrientation(entityId: active) * SIMD3<Float>(0, 1, 0)

        let expectedAfterUp = simd_quatf(angle: Float.pi / 6, axis: SIMD3<Float>(0, 1, 0)).act(beforeUp)
        assertNearlyEqual(afterUp, expectedAfterUp, accuracy: 0.0002)
    }

    func test_applyGizmoRotationDelta_usesExplicitWorldAxisForEveryAxis() {
        let cases: [(TransformAxis, SIMD3<Float>, Float)] = [
            (.x, SIMD3<Float>(1.0, 0.0, 0.0), 20.0),
            (.y, SIMD3<Float>(0.0, 1.0, 0.0), -35.0),
            (.z, SIMD3<Float>(0.0, 0.0, 1.0), 50.0),
        ]

        for (axisName, axisVector, degrees) in cases {
            let active = makeEntity(name: "WorldRotation-\(axisName)", pos: SIMD3<Float>(0, 0, 0))

            applyGizmoRotationDelta(entityId: active, axis: axisVector, degrees: degrees)

            let orientation = getLocalOrientation(entityId: active)
            let expected = simd_quatf(angle: degreesToRadians(degrees: degrees), axis: axisVector)
            assertNearlyEqual(simd_mul(orientation, SIMD3<Float>(1.0, 0.0, 0.0)), expected.act(SIMD3<Float>(1.0, 0.0, 0.0)), accuracy: 0.0002)
            assertNearlyEqual(simd_mul(orientation, SIMD3<Float>(0.0, 1.0, 0.0)), expected.act(SIMD3<Float>(0.0, 1.0, 0.0)), accuracy: 0.0002)
            assertNearlyEqual(simd_mul(orientation, SIMD3<Float>(0.0, 0.0, 1.0)), expected.act(SIMD3<Float>(0.0, 0.0, 1.0)), accuracy: 0.0002)
        }
    }
}
