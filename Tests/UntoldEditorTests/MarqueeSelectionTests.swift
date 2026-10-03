//
//  MarqueeSelectionTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// Which entities of a scene the rectangle selects. The camera stands five
/// units in front of the origin over a viewport of 400 points each way, so a
/// unit of the world at the origin is 40 points and the middle is (200, 200).
/// A box of one unit at the origin reaches 22 points from the middle.
final class MarqueeSelectionTests: XCTestCase {
    private var originalScene: Scene!
    private var selectionManager: SelectionManager!
    private var view: MarqueeGeometry.View!

    /// The whole viewport.
    private let everything = CGRect(x: 0, y: 0, width: 400, height: 400)

    override func setUp() {
        super.setUp()
        originalScene = scene
        scene = Scene()
        selectionManager = SelectionManager()

        let camera = createEntity()
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        view = MarqueeGeometry.View(
            viewSpace: scene.get(component: CameraComponent.self, for: camera)?.viewSpace ?? matrix_identity_float4x4,
            perspectiveSpace: matrixPerspectiveRightHand(fovyRadians: .pi / 2, aspectRatio: 1, nearZ: 0.1, farZ: 100),
            size: CGSize(width: 400, height: 400)
        )
    }

    override func tearDown() {
        selectionManager = nil
        view = nil
        SelectionHighlights.shared.boxes = []
        gizmoTargets = []
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    private func makeBox(_ name: String, at position: simd_float3, halfExtent: Float = 0.5) -> EntityID {
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

    private func makeLight(_ name: String, at position: simd_float3) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        registerComponent(entityId: entity, componentType: LightComponent.self)
        translateTo(entityId: entity, position: position)
        return entity
    }

    private func inside(_ rect: CGRect) -> [EntityID] {
        MarqueeSelection.entities(inside: rect, view: view, selectionManager: selectionManager)
    }

    // MARK: - What is inside

    func test_theRectangle_selectsWhatIsInsideIt_andLeavesTheRest() {
        let left = makeBox("Left", at: simd_float3(-2, 0, 0))
        let middle = makeBox("Middle", at: .zero)
        _ = makeBox("Right", at: simd_float3(2, 0, 0))

        // From left of the left one to right of the middle one.
        let selected = inside(CGRect(x: 80, y: 170, width: 150, height: 60))

        XCTAssertEqual(Set(selected), [left, middle])
    }

    func test_anEntityOnlyPartlyInTheRectangle_isLeftOut() {
        let box = makeBox("Box", at: .zero)

        XCTAssertEqual(inside(CGRect(x: 215, y: 215, width: 100, height: 100)), [], "one corner of it")
        XCTAssertEqual(inside(CGRect(x: 100, y: 180, width: 100, height: 40)), [], "half of it")
        XCTAssertEqual(inside(CGRect(x: 150, y: 150, width: 100, height: 100)), [box], "all of it")
    }

    func test_theFloorUnderWhatIsSelected_isLeftOut() {
        let crate = makeBox("Crate", at: .zero)
        let floor = makeBox("Floor", at: simd_float3(0, -0.6, 0))
        scene.get(component: LocalTransformComponent.self, for: floor)?.boundingBox = (
            min: simd_float3(-10, -0.05, -10), max: simd_float3(10, 0.05, 10)
        )

        // The floor shows in the rectangle, under the crate, and reaches out of it.
        XCTAssertEqual(inside(CGRect(x: 150, y: 150, width: 100, height: 100)), [crate])
        XCTAssertEqual(inside(everything), [crate], "not even the whole viewport holds the floor")
    }

    func test_theNearestToTheCamera_comesLast() {
        let far = makeBox("Far", at: simd_float3(0, 0, -6))
        let near = makeBox("Near", at: simd_float3(0, 0, 2))
        let between = makeBox("Between", at: simd_float3(0, 0, -1))

        XCTAssertEqual(inside(everything), [far, between, near])
    }

    func test_withoutThePassThatTellsWhatIsSeen_whatStandsBehindAnotherIsSelectedToo() {
        let wall = makeBox("Wall", at: simd_float3(0, 0, 1), halfExtent: 1)
        let behind = makeBox("Behind", at: simd_float3(0, 0, -3), halfExtent: 0.25)

        // The wall reaches 67 points from the middle.
        XCTAssertEqual(Set(inside(CGRect(x: 120, y: 120, width: 160, height: 160))), [wall, behind])
        XCTAssertEqual(inside(CGRect(x: 190, y: 190, width: 20, height: 20)), [behind], "a rectangle on the wall holds what is behind it, not the wall")
    }

    func test_aRectangleOverNothing_selectsNothing() {
        _ = makeBox("Box", at: .zero)

        XCTAssertEqual(inside(CGRect(x: 10, y: 10, width: 40, height: 40)), [])
    }

    func test_aChildIsInsideWhereItStandsInTheWorld() {
        let parent = makeBox("Parent", at: simd_float3(-2, 0, 0))
        let child = makeBox("Child", at: .zero)
        setParent(childId: child, parentId: parent)
        translateTo(entityId: child, position: simd_float3(4, 0, 0))

        // The child is two units right of the origin: 80 points right of the middle.
        XCTAssertEqual(inside(CGRect(x: 250, y: 170, width: 70, height: 60)), [child])
    }

    // MARK: - What is left out

    func test_aHiddenEntity_isNotSelected() {
        let shown = makeBox("Shown", at: simd_float3(-1, 0, 0))
        let hidden = makeBox("Hidden", at: simd_float3(1, 0, 0))
        selectionManager.setHidden(hidden, true)

        XCTAssertEqual(inside(everything), [shown])
    }

    func test_aLockedEntity_isNotSelected_norWhatIsUnderIt() {
        let free = makeBox("Free", at: simd_float3(-1, 0, 0))
        let locked = makeBox("Locked", at: simd_float3(1, 0, 0))
        let under = makeBox("Under", at: .zero)
        setParent(childId: under, parentId: locked)
        selectionManager.setLocked(locked, true)

        XCTAssertEqual(inside(everything), [free])
    }

    func test_anEntityThePickingLeavesOut_isNotSelected() {
        let picked = makeBox("Picked", at: simd_float3(-1, 0, 0))
        let left = makeBox("Left out", at: simd_float3(1, 0, 0))
        setEntityPickParticipation(entityId: left, enabled: false)

        XCTAssertEqual(inside(everything), [picked])
    }

    func test_camerasAndTheGizmo_areNotSelected() {
        let box = makeBox("Box", at: .zero)
        let gameCamera = makeBox("Camera", at: simd_float3(1, 0, 0))
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        let handle = makeBox("Handle", at: simd_float3(-1, 0, 0))
        registerComponent(entityId: handle, componentType: GizmoComponent.self)

        XCTAssertEqual(inside(everything), [box])
    }

    func test_anEntityThatDrawsNothing_andShowsNowhere_isNotSelected() {
        let empty = createEntity()
        registerTransformComponent(entityId: empty)
        registerSceneGraphComponent(entityId: empty)

        XCTAssertEqual(inside(everything), [])
    }

    // MARK: - Lights

    func test_aLight_isInsideWhereItStands() {
        let light = makeLight("Light", at: simd_float3(2, 0, 0))

        XCTAssertEqual(inside(CGRect(x: 270, y: 190, width: 20, height: 20)), [light])
        XCTAssertEqual(inside(CGRect(x: 286, y: 190, width: 20, height: 20)), [], "six points beside it is not on it")
    }

    // MARK: - With ⌘, the assets

    func test_theAssetsOfWhatIsInside_eachOnce_theNearestLast() {
        let chair = createEntity(), table = createEntity()
        let seat = makeBox("Seat", at: simd_float3(0, 0, -2))
        let back = makeBox("Back", at: simd_float3(0, 0, 1))
        let top = makeBox("Top", at: .zero)
        let alone = makeBox("Alone", at: simd_float3(0, 0, 2))
        for (node, root) in [(seat, chair), (back, chair), (top, table)] {
            registerComponent(entityId: node, componentType: DerivedAssetNodeComponent.self)
            scene.get(component: DerivedAssetNodeComponent.self, for: node)?.assetRootEntityId = root
        }

        let roots = MarqueeSelection.assetRoots(of: [seat, top, back, alone])

        XCTAssertEqual(roots, [table, chair, alone], "the chair stands where its nearest part does")
    }
}
