//
//  GizmoGroupTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// One gizmo on several entities: it moves them by the same distance, turns
/// them round itself and scales them from itself, and one undo puts them back.
final class GizmoGroupTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveEntity: EntityID!
    private var originalTool: TransformTool!
    private var originalBoxBuffer: MTLBuffer?
    private var originalSpace: TransformSpace!
    private var originalSnap: EditorSnapSettings!
    private var originalController: EditorController?
    private var selectionManager: SelectionManager!

    override func setUp() {
        super.setUp()
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()
        // One entity selected alone writes its box where the renderer keeps it.
        originalBoxBuffer = bufferResources.boundingBoxBuffer
        bufferResources.boundingBoxBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4>.stride * boundingBoxVertexCount,
            options: .storageModeShared
        )

        originalScene = scene
        originalActiveEntity = activeEntity
        originalTool = EditorViewportSettings.shared.tool
        originalSpace = EditorViewportSettings.shared.transformSpace
        originalSnap = gizmoSnapSettings
        originalController = editorController

        scene = Scene()
        activeEntity = .invalid
        gizmoTargets = []
        gizmoSnapSettings = EditorSnapSettings(defaults: nil)
        EditorViewportSettings.shared.tool = .move
        EditorViewportSettings.shared.transformSpace = .world
        selectionManager = SelectionManager()
        editorController = EditorController(selectionManager: selectionManager)
        EditorUndoManager.shared.clear()
    }

    override func tearDown() {
        endGizmoDrag()
        selectionManager.clearSelection()
        selectionManager = nil
        gizmoTargets = []
        SelectionHighlights.shared.boxes = []
        activeHitGizmoEntity = .invalid
        EditorUndoManager.shared.clear()
        editorController = originalController
        gizmoSnapSettings = originalSnap
        EditorViewportSettings.shared.tool = originalTool
        EditorViewportSettings.shared.transformSpace = originalSpace
        activeEntity = originalActiveEntity
        bufferResources.boundingBoxBuffer = originalBoxBuffer
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeBox(_ name: String, at position: simd_float3 = .zero, halfExtent: Float = 0.5) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        registerComponent(entityId: entity, componentType: RenderComponent.self)
        scene.get(component: LocalTransformComponent.self, for: entity)?.boundingBox = (
            min: simd_float3(repeating: -halfExtent),
            max: simd_float3(repeating: halfExtent)
        )
        translateTo(entityId: entity, position: position)
        return entity
    }

    /// A box under a parent turned half around Y and moved away, so that the
    /// parent's X and Z point the other way.
    private func makeBoxUnderATurnedParent(_ name: String, atWorld position: simd_float3) -> EntityID {
        let parent = createEntity()
        registerTransformComponent(entityId: parent)
        registerSceneGraphComponent(entityId: parent)
        translateTo(entityId: parent, position: simd_float3(5, 0, 0))
        rotateTo(entityId: parent, rotation: simd_quatf(angle: .pi, axis: simd_float3(0, 1, 0)))

        let child = makeBox(name)
        setParent(childId: child, parentId: parent)
        translateTo(entityId: child, position: localPosition(ofWorld: position, for: child))
        return child
    }

    private func handle(_ mode: TransformManipulationMode, _ axis: TransformAxis) -> EntityID {
        getEntityChildren(parentId: parentEntityIdGizmo).first(where: {
            guard let handle = scene.get(component: GizmoHandleComponent.self, for: $0) else { return false }
            return handle.mode == mode && handle.axis == axis
        }) ?? .invalid
    }

    /// A ray that meets the X axis through the gizmo at `amount` along it.
    private func rayOnX(at amount: Float) -> GizmoDragRay {
        GizmoDragRay(origin: simd_float3(amount, 50, 0), direction: simd_float3(0, -1, 0))
    }

    private func assertNearlyEqual(_ lhs: simd_float3, _ rhs: simd_float3, accuracy: Float = 0.001, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, message, file: file, line: line)
    }

    /// What an entity's own X axis points along in the world.
    private func worldXAxis(of entityId: EntityID) -> simd_float3 {
        simd_act(entityWorldRotation(entityId: entityId), simd_float3(1, 0, 0))
    }

    // MARK: - What the gizmo works on

    func test_withOneEntity_theGizmoWorksOnTheActiveOne() {
        let box = makeBox("Box")
        activeEntity = box

        XCTAssertEqual(gizmoTransformTargets(), [box])
    }

    func test_withNoActiveEntity_itWorksOnNothing() {
        gizmoTargets = [makeBox("First"), makeBox("Second")]
        activeEntity = .invalid

        XCTAssertEqual(gizmoTransformTargets(), [])
    }

    func test_withSeveral_itWorksOnAllOfThem() {
        let first = makeBox("First"), second = makeBox("Second")
        selectionManager.selectEntities([first, second])

        XCTAssertEqual(gizmoTransformTargets(), [first, second])
    }

    func test_targetsLeftFromAnotherSelection_areNotMoved() {
        let first = makeBox("First"), second = makeBox("Second"), other = makeBox("Other")
        gizmoTargets = [first, second]
        activeEntity = other

        XCTAssertEqual(gizmoTransformTargets(), [other])
    }

    func test_anEntityThatLeftTheScene_isNoTarget() {
        let first = makeBox("First"), second = makeBox("Second"), third = makeBox("Third")
        selectionManager.selectEntities([first, second, third])

        destroyEntity(entityId: first)
        finalizePendingDestroys()

        XCTAssertEqual(gizmoTransformTargets(), [second, third])
    }

    func test_anEntityWithoutItsPlaceInTheWorld_isNoTargetAmongSeveral() {
        let first = makeBox("First"), second = makeBox("Second"), third = makeBox("Third")
        selectionManager.selectEntities([first, second, third])

        // The engine takes an entity's two transforms away together; a turn
        // and a scale of several start from the one taken here.
        scene.remove(component: WorldTransformComponent.self, from: first)

        XCTAssertFalse(hasBothTransforms(first))
        XCTAssertEqual(gizmoTransformTargets(), [second, third])
    }

    func test_anEntityTheEngineMade_hasBothTransforms_untilItLeavesTheScene() {
        let entity = createEntity()
        XCTAssertTrue(hasBothTransforms(entity), "the engine gives an entity the two together")

        destroyEntity(entityId: entity)
        finalizePendingDestroys()

        XCTAssertFalse(hasBothTransforms(entity))
    }

    // MARK: - Moving

    func test_aDragOfTheMoveGizmo_carriesEveryEntityTheSameWay() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 1, 0))
        selectionManager.selectEntities([first, second])
        let gizmoStart = getPosition(entityId: parentEntityIdGizmo)

        activeHitGizmoEntity = handle(.translate, .x)
        XCTAssertNotEqual(activeHitGizmoEntity, .invalid)
        beginGizmoDrag(ray: rayOnX(at: 0))
        updateGizmoDrag(ray: rayOnX(at: 3))
        updateGizmoDrag(ray: rayOnX(at: 1.5))

        assertNearlyEqual(getPosition(entityId: first), simd_float3(-0.5, 0, 0))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(3.5, 1, 0))
        assertNearlyEqual(getPosition(entityId: parentEntityIdGizmo), gizmoStart + simd_float3(1.5, 0, 0))
    }

    func test_anEntityUnderATurnedParent_goesTheSameWayInTheWorld() {
        let root = makeBox("Root", at: simd_float3(-2, 0, 0))
        let child = makeBoxUnderATurnedParent("Child", atWorld: simd_float3(2, 0, 3))
        assertNearlyEqual(getPosition(entityId: child), simd_float3(2, 0, 3))
        selectionManager.selectEntities([root, child])

        activeHitGizmoEntity = handle(.translate, .x)
        beginGizmoDrag(ray: rayOnX(at: 0))
        updateGizmoDrag(ray: rayOnX(at: 2))

        assertNearlyEqual(getPosition(entityId: root), simd_float3(0, 0, 0))
        assertNearlyEqual(getPosition(entityId: child), simd_float3(4, 0, 3))
    }

    func test_movingWithSnapping_landsAllOfThemOnTheSameSteps() {
        gizmoSnapSettings.isEnabled = true
        gizmoSnapSettings.snapsMove = true
        gizmoSnapSettings.gridStep = 0.5
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2.2, 0, 0))
        selectionManager.selectEntities([first, second])

        activeHitGizmoEntity = handle(.translate, .x)
        beginGizmoDrag(ray: rayOnX(at: 0))
        updateGizmoDrag(ray: rayOnX(at: 1.3))

        assertNearlyEqual(getPosition(entityId: first), simd_float3(-0.5, 0, 0), message: "1.3 is nearest to three steps of a half")
        assertNearlyEqual(getPosition(entityId: second), simd_float3(3.7, 0, 0))
    }

    func test_aMoveFromTheKeys_carriesAllOfThem() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBoxUnderATurnedParent("Second", atWorld: simd_float3(2, 0, 0))
        selectionManager.selectEntities([first, second])

        applyGizmoTranslation(byWorld: simd_float3(0, 0, 1.5))

        assertNearlyEqual(getPosition(entityId: first), simd_float3(-2, 0, 1.5))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(2, 0, 1.5))
    }

    func test_aMoveFromTheKeys_withOneEntity_movesThatOne() {
        let box = makeBox("Box", at: simd_float3(1, 0, 0))
        let other = makeBox("Other", at: simd_float3(5, 0, 0))
        selectionManager.inspectEntity(entityId: box)

        applyGizmoTranslation(byWorld: simd_float3(0, 2, 0))

        assertNearlyEqual(getPosition(entityId: box), simd_float3(1, 2, 0))
        assertNearlyEqual(getPosition(entityId: other), simd_float3(5, 0, 0))
    }

    // MARK: - Turning

    func test_aTurn_takesThemRoundTheGizmo_andTurnsEachTheSame() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        EditorViewportSettings.shared.tool = .rotate
        selectionManager.selectEntities([first, second])
        assertNearlyEqual(gizmoRootWorldPosition(), .zero)

        applyGizmoRotation(axis: simd_float3(0, 1, 0), degrees: 90)

        // A quarter turn about Y takes +X to -Z.
        assertNearlyEqual(getPosition(entityId: first), simd_float3(0, 0, 2))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(0, 0, -2))
        assertNearlyEqual(worldXAxis(of: first), simd_float3(0, 0, -1))
        assertNearlyEqual(worldXAxis(of: second), simd_float3(0, 0, -1))
    }

    func test_aTurn_underATurnedParent_isTheSameTurnInTheWorld() {
        let root = makeBox("Root", at: simd_float3(-2, 0, 0))
        let child = makeBoxUnderATurnedParent("Child", atWorld: simd_float3(2, 0, 0))
        let childAxisBefore = worldXAxis(of: child)
        assertNearlyEqual(childAxisBefore, simd_float3(-1, 0, 0))
        EditorViewportSettings.shared.tool = .rotate
        selectionManager.selectEntities([root, child])

        applyGizmoRotation(axis: simd_float3(0, 1, 0), degrees: 90)

        assertNearlyEqual(getPosition(entityId: root), simd_float3(0, 0, 2))
        assertNearlyEqual(getPosition(entityId: child), simd_float3(0, 0, -2))
        assertNearlyEqual(worldXAxis(of: child), simd_float3(0, 0, 1), message: "its own X pointed to -X, and turned a quarter like the rest")
    }

    func test_smallTurns_addUpToTheWholeTurn() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        EditorViewportSettings.shared.tool = .rotate
        selectionManager.selectEntities([first, second])

        for _ in 0 ..< 36 {
            applyGizmoRotation(axis: simd_float3(0, 0, 1), degrees: 5)
        }

        // Half a turn about Z.
        assertNearlyEqual(getPosition(entityId: first), simd_float3(2, 0, 0), accuracy: 0.01)
        assertNearlyEqual(getPosition(entityId: second), simd_float3(-2, 0, 0), accuracy: 0.01)
        XCTAssertEqual(simd_distance(getPosition(entityId: first), getPosition(entityId: second)), 4, accuracy: 0.01, "they keep their distance")
    }

    func test_aTurn_withOneEntity_turnsItWhereItStands() {
        let box = makeBox("Box", at: simd_float3(3, 0, 0))
        EditorViewportSettings.shared.tool = .rotate
        selectionManager.inspectEntity(entityId: box)

        applyGizmoRotation(axis: simd_float3(0, 1, 0), degrees: 90)

        assertNearlyEqual(getPosition(entityId: box), simd_float3(3, 0, 0))
        assertNearlyEqual(worldXAxis(of: box), simd_float3(0, 0, -1))
    }

    // MARK: - Scaling

    func test_theFactor_isOneMoreThanTheDrag_andNeverNothing() {
        XCTAssertEqual(gizmoGroupScaleFactor(forAmount: 0), 1)
        XCTAssertEqual(gizmoGroupScaleFactor(forAmount: 1), 2)
        XCTAssertEqual(gizmoGroupScaleFactor(forAmount: -0.5), 0.5)
        XCTAssertEqual(gizmoGroupScaleFactor(forAmount: -3), gizmoMinimumScale)
        XCTAssertEqual(gizmoGroupScaleFactor(forAmount: .nan), 1)
    }

    func test_aDragOfTheScaleGizmo_growsThem_andTheirDistanceFromIt() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 1, 0))
        EditorViewportSettings.shared.tool = .scale
        selectionManager.selectEntities([first, second])
        let pivot = gizmoRootWorldPosition()
        assertNearlyEqual(pivot, simd_float3(0, 0.5, 0))

        activeHitGizmoEntity = handle(.scale, .x)
        XCTAssertNotEqual(activeHitGizmoEntity, .invalid)
        beginGizmoDrag(ray: rayOnX(at: 0))
        updateGizmoDrag(ray: rayOnX(at: 0.4))
        updateGizmoDrag(ray: rayOnX(at: 1))

        // Twice the size along X, from where they stood: not 1.4 times and then more.
        assertNearlyEqual(getPosition(entityId: first), simd_float3(-4, 0, 0))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(4, 1, 0))
        assertNearlyEqual(getScale(entityId: first), simd_float3(2, 1, 1))
        assertNearlyEqual(getScale(entityId: second), simd_float3(2, 1, 1))
    }

    func test_aTurnedEntity_growsAlongItsOwnAxisThatLiesAlongTheGizmos() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let turned = makeBox("Turned", at: simd_float3(2, 0, 0))
        // A quarter turn about Y: its own Z lies along the world's X.
        rotateTo(entityId: turned, rotation: simd_quatf(angle: .pi / 2, axis: simd_float3(0, 1, 0)))
        EditorViewportSettings.shared.tool = .scale
        selectionManager.selectEntities([first, turned])

        activeHitGizmoEntity = handle(.scale, .x)
        beginGizmoDrag(ray: rayOnX(at: 0))
        updateGizmoDrag(ray: rayOnX(at: 0.5))

        assertNearlyEqual(getScale(entityId: first), simd_float3(1.5, 1, 1))
        assertNearlyEqual(getScale(entityId: turned), simd_float3(1, 1, 1.5))
    }

    func test_aLight_movesWithTheRest_andKeepsItsSize() {
        let box = makeBox("Box", at: simd_float3(-2, 0, 0))
        let light = makeBox("Light", at: simd_float3(2, 0, 0))
        registerComponent(entityId: light, componentType: LightComponent.self)
        EditorViewportSettings.shared.tool = .scale
        selectionManager.selectEntities([box, light])

        activeHitGizmoEntity = handle(.scale, .x)
        beginGizmoDrag(ray: rayOnX(at: 0))
        updateGizmoDrag(ray: rayOnX(at: 1))

        assertNearlyEqual(getPosition(entityId: light), simd_float3(4, 0, 0))
        assertNearlyEqual(getScale(entityId: light), simd_float3(1, 1, 1))
        assertNearlyEqual(getScale(entityId: box), simd_float3(2, 1, 1))
    }

    func test_aScaleFromTheKeys_growsThemFromWhereTheyAre() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        EditorViewportSettings.shared.tool = .scale
        selectionManager.selectEntities([first, second])

        applyGizmoScale(axis: simd_float3(1, 0, 0), amount: 0.5, handle: .x)
        applyGizmoScale(axis: simd_float3(1, 0, 0), amount: 0.5, handle: .x)

        assertNearlyEqual(getScale(entityId: first), simd_float3(2.25, 1, 1))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(4.5, 0, 0))
    }

    func test_aScaleFromTheKeys_withOneEntity_isTheEnginesOwn() {
        let box = makeBox("Box", at: simd_float3(3, 0, 0))
        EditorViewportSettings.shared.tool = .scale
        selectionManager.inspectEntity(entityId: box)

        applyGizmoScale(axis: simd_float3(1, 0, 0), amount: 0.5, handle: .x)

        assertNearlyEqual(getScale(entityId: box), simd_float3(1.5, 1, 1))
        assertNearlyEqual(getPosition(entityId: box), simd_float3(3, 0, 0))
    }

    // MARK: - Where the gizmo stands afterwards

    func test_afterADrag_theGizmoIsBackInTheMiddle() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0), halfExtent: 1)
        EditorViewportSettings.shared.tool = .rotate
        selectionManager.selectEntities([first, second])
        let pivot = gizmoRootWorldPosition()
        assertNearlyEqual(pivot, simd_float3(0.25, 0, 0))

        applyGizmoRotation(axis: simd_float3(0, 1, 0), degrees: 90)
        assertNearlyEqual(gizmoRootWorldPosition(), pivot, message: "during the drag it stays where they turn around")
        endGizmoDrag()

        let bounds = selectionManager.selectionBounds()
        XCTAssertNotNil(bounds)
        if let bounds {
            assertNearlyEqual(gizmoRootWorldPosition(), (bounds.min + bounds.max) * 0.5)
        }
    }

    // MARK: - Undo

    func test_aDragOfSeveral_isOneStepToUndo() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 1, 0))
        selectionManager.selectEntities([first, second])
        let undo = EditorUndoManager.shared

        undo.beginTransformEdit(entityIds: gizmoTransformTargets())
        applyGizmoTranslation(byWorld: simd_float3(0, 0, 3))
        undo.commitTransformEdit(entityIds: gizmoTransformTargets())

        XCTAssertEqual(undo.undoHistory, ["Transform 2 Entities"])
        assertNearlyEqual(getPosition(entityId: second), simd_float3(2, 1, 3))

        undo.undo()
        assertNearlyEqual(getPosition(entityId: first), simd_float3(-2, 0, 0))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(2, 1, 0))

        undo.redo()
        assertNearlyEqual(getPosition(entityId: first), simd_float3(-2, 0, 3))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(2, 1, 3))
    }

    func test_aDragThatMovedOneOfThem_isNamedAsOne() {
        let first = makeBox("First"), second = makeBox("Second", at: simd_float3(2, 0, 0))
        let undo = EditorUndoManager.shared

        undo.beginTransformEdit(entityIds: [first, second])
        translateTo(entityId: second, position: simd_float3(2, 5, 0))
        undo.commitTransformEdit(entityIds: [first, second])

        XCTAssertEqual(undo.undoHistory, ["Transform Entity"])
    }

    func test_aDragThatMovedNothing_leavesNothingToUndo() {
        let first = makeBox("First"), second = makeBox("Second")
        let undo = EditorUndoManager.shared

        undo.beginTransformEdit(entityIds: [first, second])
        undo.commitTransformEdit(entityIds: [first, second])

        XCTAssertFalse(undo.canUndo)
    }

    func test_undoingATurnOfSeveral_putsPlaceAndTurnBack() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        EditorViewportSettings.shared.tool = .rotate
        selectionManager.selectEntities([first, second])
        let undo = EditorUndoManager.shared

        undo.beginTransformEdit(entityIds: gizmoTransformTargets())
        applyGizmoRotation(axis: simd_float3(0, 1, 0), degrees: 90)
        undo.commitTransformEdit(entityIds: gizmoTransformTargets())
        undo.undo()

        assertNearlyEqual(getPosition(entityId: first), simd_float3(-2, 0, 0))
        assertNearlyEqual(getPosition(entityId: second), simd_float3(2, 0, 0))
        assertNearlyEqual(worldXAxis(of: first), simd_float3(1, 0, 0))
    }

    // MARK: - A point as the parent measures it

    func test_aPointOfTheWorld_asTheParentMeasuresIt() {
        let child = makeBoxUnderATurnedParent("Child", atWorld: simd_float3(4, 0, 0))

        // The parent stands at (5, 0, 0), turned half around Y.
        assertNearlyEqual(localPosition(ofWorld: simd_float3(4, 2, 3), for: child), simd_float3(1, 2, -3))

        let root = makeBox("Root")
        assertNearlyEqual(localPosition(ofWorld: simd_float3(4, 2, 3), for: root), simd_float3(4, 2, 3))
    }
}
