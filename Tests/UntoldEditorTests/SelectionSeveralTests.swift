//
//  SelectionSeveralTests.swift
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

/// A selection of several entities: what is selected, which of them the
/// gizmo moves, where it stands and which boxes are drawn.
final class SelectionSeveralTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveEntity: EntityID!
    private var originalTool: TransformTool!
    private var originalBoxBuffer: MTLBuffer?
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
        scene = Scene()
        activeEntity = .invalid
        gizmoTargets = []
        EditorViewportSettings.shared.tool = .move
        selectionManager = SelectionManager()
    }

    override func tearDown() {
        selectionManager.clearSelection()
        selectionManager = nil
        gizmoTargets = []
        SelectionHighlights.shared.boxes = []
        EditorViewportSettings.shared.tool = originalTool
        activeEntity = originalActiveEntity
        bufferResources.boundingBoxBuffer = originalBoxBuffer
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    /// An entity that draws a box of `halfExtent` around its own origin.
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

    /// An entity with a place in the scene that draws nothing, as a light.
    private func makeEmpty(_ name: String, at position: simd_float3 = .zero) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        translateTo(entityId: entity, position: position)
        return entity
    }

    private func assertNearlyEqual(_ lhs: simd_float3, _ rhs: simd_float3, accuracy: Float = 0.001, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: - One entity is a selection of one

    func test_anEntitySelectedAlone_isASelectionOfOne() {
        let box = makeBox("Box")

        selectionManager.selectedEntity = box

        XCTAssertEqual(selectionManager.selectedEntities, [box])
        XCTAssertFalse(selectionManager.hasSeveralSelected)
        XCTAssertTrue(selectionManager.isSelected(box))
    }

    func test_noEntitySelected_isASelectionOfNone() {
        selectionManager.selectedEntity = makeBox("Box")

        selectionManager.selectedEntity = nil
        XCTAssertEqual(selectionManager.selectedEntities, [])

        selectionManager.selectedEntity = .invalid
        XCTAssertEqual(selectionManager.selectedEntities, [])
    }

    // MARK: - Several

    func test_severalAreSelected_inTheirOrder_andTheLastIsTheOneNamed() {
        let first = makeBox("First"), second = makeBox("Second"), third = makeBox("Third")

        selectionManager.selectEntities([first, second, third])

        XCTAssertEqual(selectionManager.selectedEntities, [first, second, third])
        XCTAssertEqual(selectionManager.selectedEntity, third)
        XCTAssertTrue(selectionManager.hasSeveralSelected)
        XCTAssertNil(selectionManager.inspectedMesh)
    }

    func test_anEntityCountsOnce_andNoneThatIsInvalid() {
        let first = makeBox("First"), second = makeBox("Second")

        selectionManager.selectEntities([first, .invalid, second, first])

        XCTAssertEqual(selectionManager.selectedEntities, [first, second])
    }

    func test_oneOfSeveral_isSelectedAsOneAlone() {
        let box = makeBox("Box")

        selectionManager.selectEntities([box])

        XCTAssertEqual(selectionManager.selectedEntities, [box])
        XCTAssertEqual(selectionManager.selectedEntity, box)
        XCTAssertEqual(activeEntity, box)
        XCTAssertTrue(gizmoTargets.isEmpty)
        XCTAssertTrue(SelectionHighlights.shared.boxes.isEmpty, "one entity's box is drawn as it always was")
    }

    func test_noneOfSeveral_clearsTheSelection() {
        selectionManager.selectEntities([makeBox("First"), makeBox("Second")])

        selectionManager.selectEntities([])

        XCTAssertEqual(selectionManager.selectedEntities, [])
        XCTAssertNil(selectionManager.selectedEntity)
        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertTrue(gizmoTargets.isEmpty)
        XCTAssertTrue(SelectionHighlights.shared.boxes.isEmpty)
    }

    func test_selectingTheScene_orTheProject_leavesNoEntitySelected() {
        selectionManager.selectEntities([makeBox("First"), makeBox("Second")])
        selectionManager.selectScene()
        XCTAssertEqual(selectionManager.selectedEntities, [])
        XCTAssertTrue(SelectionHighlights.shared.boxes.isEmpty)

        selectionManager.selectEntities([makeBox("Third"), makeBox("Fourth")])
        XCTAssertFalse(selectionManager.sceneSelected)
        selectionManager.selectProject()
        XCTAssertEqual(selectionManager.selectedEntities, [])
    }

    // MARK: - Adding and taking out

    func test_toggling_addsAnEntity_whichBecomesTheOneNamed() {
        let first = makeBox("First"), second = makeBox("Second")
        selectionManager.inspectEntity(entityId: first)

        selectionManager.toggleSelection(of: second)

        XCTAssertEqual(selectionManager.selectedEntities, [first, second])
        XCTAssertEqual(selectionManager.selectedEntity, second)
    }

    func test_toggling_takesASelectedEntityOut() {
        let first = makeBox("First"), second = makeBox("Second"), third = makeBox("Third")
        selectionManager.selectEntities([first, second, third])

        selectionManager.toggleSelection(of: second)
        XCTAssertEqual(selectionManager.selectedEntities, [first, third])
        XCTAssertEqual(selectionManager.selectedEntity, third)

        selectionManager.toggleSelection(of: third)
        XCTAssertEqual(selectionManager.selectedEntities, [first], "one is left, selected as one alone")
        XCTAssertTrue(gizmoTargets.isEmpty)

        selectionManager.toggleSelection(of: first)
        XCTAssertEqual(selectionManager.selectedEntities, [])
        XCTAssertEqual(activeEntity, .invalid)
    }

    func test_toggling_withNothingSelected_selectsTheEntity() {
        let box = makeBox("Box")

        selectionManager.toggleSelection(of: box)

        XCTAssertEqual(selectionManager.selectedEntities, [box])
    }

    func test_aPlainSelection_afterSeveral_selectsThatOneAlone() {
        let first = makeBox("First"), second = makeBox("Second"), third = makeBox("Third")
        selectionManager.selectEntities([first, second, third])

        selectionManager.inspectEntity(entityId: second)

        XCTAssertEqual(selectionManager.selectedEntities, [second])
        XCTAssertEqual(activeEntity, second)
        XCTAssertTrue(gizmoTargets.isEmpty)
        XCTAssertTrue(SelectionHighlights.shared.boxes.isEmpty)
    }

    // MARK: - Entities that leave the scene

    func test_anEntityThatLeftTheScene_leavesTheSelection() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        let third = makeBox("Third", at: simd_float3(6, 0, 0))
        selectionManager.selectEntities([first, second, third])

        destroyEntity(entityId: third)
        selectionManager.forgetEntitiesThatLeftTheScene()

        XCTAssertEqual(selectionManager.selectedEntities, [first, second])
        XCTAssertEqual(gizmoTargets, [first, second])
        XCTAssertEqual(SelectionHighlights.shared.boxes.map(\.entityId), [first, second])
        assertNearlyEqual(getPosition(entityId: parentEntityIdGizmo), .zero)
    }

    func test_whenOneIsLeft_itIsSelectedAlone() {
        let first = makeBox("First"), second = makeBox("Second")
        selectionManager.selectEntities([first, second])

        destroyEntity(entityId: second)
        selectionManager.forgetEntitiesThatLeftTheScene()

        XCTAssertEqual(selectionManager.selectedEntities, [first])
        XCTAssertEqual(selectionManager.selectedEntity, first)
        XCTAssertTrue(gizmoTargets.isEmpty)
    }

    func test_whileAllAreInTheScene_theSelectionIsLeftAlone() {
        let first = makeBox("First"), second = makeBox("Second")
        selectionManager.selectEntities([first, second])
        let gizmo = parentEntityIdGizmo

        selectionManager.forgetEntitiesThatLeftTheScene()

        XCTAssertEqual(selectionManager.selectedEntities, [first, second])
        XCTAssertEqual(parentEntityIdGizmo, gizmo, "the gizmo is not made again")
    }

    // MARK: - What the gizmo moves

    func test_theGizmoMoves_everySelectedEntityItMayGoOn() {
        let first = makeBox("First"), second = makeBox("Second")
        let empty = makeEmpty("Empty")

        selectionManager.selectEntities([first, empty, second])

        XCTAssertEqual(selectionManager.transformTargets, [first, second], "what draws nothing takes no gizmo, alone or among several")
        XCTAssertEqual(gizmoTargets, [first, second])
        XCTAssertEqual(activeEntity, second)
    }

    func test_anEntityWithoutItsPlaceInTheWorld_takesNoGizmo() {
        let first = makeBox("First"), second = makeBox("Second"), third = makeBox("Third")
        scene.remove(component: WorldTransformComponent.self, from: second)

        selectionManager.selectEntities([first, second, third])

        XCTAssertFalse(selectionManager.takesGizmo(second))
        XCTAssertEqual(selectionManager.transformTargets, [first, third])
        XCTAssertEqual(gizmoTargets, [first, third])
    }

    func test_anEntityUnderASelectedOne_movesWithItsParent() {
        let parent = makeBox("Parent"), child = makeBox("Child"), other = makeBox("Other")
        setParent(childId: child, parentId: parent)

        selectionManager.selectEntities([child, parent, other])

        XCTAssertEqual(selectionManager.selectedEntities, [child, parent, other], "it is selected all the same")
        XCTAssertEqual(selectionManager.transformTargets, [parent, other])
    }

    func test_aLockedOrHiddenEntity_isNotMoved() {
        let first = makeBox("First"), locked = makeBox("Locked"), hidden = makeBox("Hidden"), last = makeBox("Last")
        selectionManager.setLocked(locked, true)
        selectionManager.setHidden(hidden, true)

        selectionManager.selectEntities([first, locked, hidden, last])

        XCTAssertEqual(selectionManager.transformTargets, [first, last])
    }

    func test_theActiveEntity_isTheLastSelected_orTheLastTheGizmoMoves() {
        let first = makeBox("First"), second = makeBox("Second")
        let empty = makeEmpty("Empty")

        selectionManager.selectEntities([first, second])
        XCTAssertEqual(activeEntity, second)

        selectionManager.selectEntities([first, second, empty])
        XCTAssertEqual(selectionManager.selectedEntity, empty)
        XCTAssertEqual(activeEntity, second)
    }

    func test_severalThatCannotBeMoved_haveNoGizmo() {
        let first = makeEmpty("First"), second = makeEmpty("Second")

        selectionManager.selectEntities([first, second])

        XCTAssertEqual(selectionManager.selectedEntities, [first, second])
        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertEqual(parentEntityIdGizmo, .invalid)
        XCTAssertFalse(gizmoActive)
    }

    // MARK: - Where the gizmo stands

    func test_theGizmo_standsInTheMiddleOfAllOfThem() {
        let first = makeBox("First", at: simd_float3(-4, 0, 0))
        let second = makeBox("Second", at: simd_float3(6, 2, 0), halfExtent: 1)

        selectionManager.selectEntities([first, second])

        XCTAssertTrue(gizmoActive)
        // The box around both runs from (-4.5, -0.5, -1) to (7, 3, 1).
        assertNearlyEqual(getPosition(entityId: parentEntityIdGizmo), simd_float3(1.25, 1.25, 0))
    }

    func test_theSelectTool_showsNoGizmo_onSeveralEither() {
        EditorViewportSettings.shared.tool = .select
        let first = makeBox("First"), second = makeBox("Second")

        selectionManager.selectEntities([first, second])

        XCTAssertFalse(gizmoActive)
        XCTAssertEqual(parentEntityIdGizmo, .invalid)
        XCTAssertEqual(gizmoTargets, [first, second])
    }

    func test_refreshingTheGizmo_keepsSeveralSelected() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0)), second = makeBox("Second", at: simd_float3(2, 0, 0))
        selectionManager.selectEntities([first, second])

        EditorViewportSettings.shared.tool = .rotate
        selectionManager.refreshGizmo()

        XCTAssertEqual(selectionManager.selectedEntities, [first, second])
        XCTAssertEqual(gizmoTargets, [first, second])
        XCTAssertTrue(gizmoActive)
        assertNearlyEqual(getPosition(entityId: parentEntityIdGizmo), .zero)
    }

    func test_hidingOneOfSeveral_takesItFromTheGizmo_andLeavesItSelected() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        let third = makeBox("Third", at: simd_float3(10, 0, 0))
        selectionManager.selectEntities([first, second, third])

        selectionManager.setHidden(third, true)

        XCTAssertEqual(selectionManager.selectedEntities, [first, second, third])
        XCTAssertEqual(gizmoTargets, [first, second])
        XCTAssertEqual(SelectionHighlights.shared.boxes.map(\.entityId), [first, second])
        assertNearlyEqual(getPosition(entityId: parentEntityIdGizmo), .zero)
    }

    // MARK: - The boxes

    func test_everySelectedEntity_hasItsBox_inItsOwnSpace() throws {
        let first = makeBox("First", at: simd_float3(5, 0, 0)), second = makeBox("Second", halfExtent: 2)

        selectionManager.selectEntities([first, second])

        let boxes = SelectionHighlights.shared.boxes
        XCTAssertEqual(boxes.map(\.entityId), [first, second])
        assertNearlyEqual(boxes[0].minimum, simd_float3(repeating: -0.5))
        assertNearlyEqual(boxes[0].maximum, simd_float3(repeating: 0.5))
        assertNearlyEqual(boxes[1].maximum, simd_float3(repeating: 2))

        // Drawn, the first one's box is carried to where the entity stands.
        let placement = try XCTUnwrap(boxes[0].placement())
        let corner = simd_mul(placement.model, simd_float4(placement.size * simd_float3(1, 1, 1), 1))
        assertNearlyEqual(simd_float3(corner.x, corner.y, corner.z), simd_float3(5.5, 0.5, 0.5))
        let origin = simd_mul(placement.model, simd_float4(0, 0, 0, 1))
        assertNearlyEqual(simd_float3(origin.x, origin.y, origin.z), simd_float3(4.5, -0.5, -0.5))
    }

    func test_aBox_holdsWhatIsUnderTheEntity() {
        let parent = makeBox("Parent"), child = makeBox("Child"), other = makeBox("Other")
        setParent(childId: child, parentId: parent)
        translateTo(entityId: child, position: simd_float3(0, 3, 0))
        translateTo(entityId: parent, position: simd_float3(10, 0, 0))

        selectionManager.selectEntities([parent, other])

        let box = SelectionHighlights.shared.boxes[0]
        assertNearlyEqual(box.minimum, simd_float3(-0.5, -0.5, -0.5))
        assertNearlyEqual(box.maximum, simd_float3(0.5, 3.5, 0.5))
    }

    func test_anEntityThatDrawsNothing_hasABoxWhereItStands() throws {
        let box = makeBox("Box"), empty = makeEmpty("Empty", at: simd_float3(3, 4, 5))
        scaleTo(entityId: empty, scale: simd_float3(repeating: 7))

        selectionManager.selectEntities([box, empty])

        let boxes = SelectionHighlights.shared.boxes
        XCTAssertEqual(boxes.map(\.isPoint), [false, true])
        let placement = try XCTUnwrap(boxes[1].placement())
        assertNearlyEqual(placement.size, simd_float3(repeating: SelectionHighlightBox.pointExtent), message: "whatever the entity's scale")
        let origin = simd_mul(placement.model, simd_float4(0, 0, 0, 1))
        assertNearlyEqual(simd_float3(origin.x, origin.y, origin.z), simd_float3(2.75, 3.75, 4.75))
    }

    func test_aBoxFollowsItsEntity_withoutBeingTakenAgain() throws {
        let first = makeBox("First"), second = makeBox("Second")
        selectionManager.selectEntities([first, second])
        let box = SelectionHighlights.shared.boxes[0]

        translateTo(entityId: first, position: simd_float3(0, 8, 0))

        let placement = try XCTUnwrap(box.placement())
        let origin = simd_mul(placement.model, simd_float4(0, 0, 0, 1))
        assertNearlyEqual(simd_float3(origin.x, origin.y, origin.z), simd_float3(-0.5, 7.5, -0.5))
    }

    func test_theUnitBox_isTwelveLines_betweenItsCorners() {
        let lines = SelectionHighlights.unitBoxLines
        XCTAssertEqual(lines.count, 24)
        XCTAssertEqual(lines.count, boundingBoxVertexCount)

        var edges = Set<String>()
        for index in stride(from: 0, to: lines.count, by: 2) {
            let from = lines[index], to = lines[index + 1]
            XCTAssertEqual(simd_length(simd_float3(from.x, from.y, from.z) - simd_float3(to.x, to.y, to.z)), 1, accuracy: 0.0001)
            XCTAssertEqual(from.w, 1)
            let ends = ["\(from.x)\(from.y)\(from.z)", "\(to.x)\(to.y)\(to.z)"].sorted()
            edges.insert(ends.joined(separator: "-"))
        }
        XCTAssertEqual(edges.count, 12, "every edge once")
    }

    // MARK: - Framing

    func test_theBounds_areAroundAllOfThem() throws {
        let first = makeBox("First", at: simd_float3(-4, 0, 0))
        let second = makeBox("Second", at: simd_float3(6, 2, 0), halfExtent: 1)
        selectionManager.selectEntities([first, second])

        let bounds = try XCTUnwrap(selectionManager.selectionBounds())

        assertNearlyEqual(bounds.min, simd_float3(-4.5, -0.5, -1))
        assertNearlyEqual(bounds.max, simd_float3(7, 3, 1))
    }

    func test_framing_takesInWhatDrawsNothing() throws {
        let box = makeBox("Box")
        let empty = makeEmpty("Empty", at: simd_float3(0, 10, 0))
        selectionManager.selectEntities([box, empty])

        let framing = try XCTUnwrap(selectionManager.selectionFramingBounds())

        assertNearlyEqual(framing.min, simd_float3(-0.5, -0.5, -0.5))
        assertNearlyEqual(framing.max, simd_float3(0.5, 10.5, 0.5))
    }
}
