//
//  MarqueeInputTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

private final class SelectionRecorder: SelectionDelegate {
    var clearCount = 0
    var selectedOne: [EntityID] = []
    var inspectedMeshes: [EntityID] = []
    var selectedSeveral: [[EntityID]] = []
    var toggled: [EntityID] = []

    func didSelectEntity(_ entityId: EntityID) {
        selectedOne.append(entityId)
    }

    func didInspectEntity(_: EntityID) {}
    func didInspectMesh(_ entityId: EntityID, meshIndex _: Int) {
        inspectedMeshes.append(entityId)
    }

    func didClearSelection() {
        clearCount += 1
    }

    func resetActiveAxis() {}

    func didSelectEntities(_ entityIds: [EntityID]) {
        selectedSeveral.append(entityIds)
    }

    func didToggleEntity(_ entityId: EntityID) {
        toggled.append(entityId)
    }
}

/// The left button on the canvas: a drag draws the rectangle and selects what
/// is inside it, a ⇧ click adds to the selection, and a click on another
/// entity selects it though a gizmo shows.
///
/// The camera stands five units in front of the origin over a canvas of 400
/// by 300 points: a unit of the world at the origin is 30 points, and the
/// middle is (200, 150), measured from the bottom left.
final class MarqueeInputTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false
    private var originalActiveEntity: EntityID = .invalid
    private var originalPlayback: EditorPlaybackSettings!
    private var originalController: EditorController?
    private var originalDelegate: SelectionDelegate?
    private var originalKeyState = KeyState()
    private var originalPerspective = matrix_identity_float4x4
    private var originalOctree = false
    private var originalVisible: [EntityID] = []
    private var originalTool: TransformTool!
    private var originalBoxBuffer: MTLBuffer?

    private let recorder = SelectionRecorder()
    private var playback: EditorPlaybackSettings!
    private var selectionManager: SelectionManager!
    private var view: NSView!
    private let input = InputSystem.shared

    override func setUp() {
        super.setUp()
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()
        originalBoxBuffer = bufferResources.boundingBoxBuffer
        bufferResources.boundingBoxBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4>.stride * boundingBoxVertexCount,
            options: .storageModeShared
        )

        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalGameMode = gameMode
        originalActiveEntity = activeEntity
        originalPlayback = ViewportCameras.playback
        originalController = editorController
        originalDelegate = selectionDelegate
        originalKeyState = input.keyState
        originalPerspective = renderInfo.perspectiveSpace
        originalOctree = OctreeSystem.shared.enabled
        originalVisible = visibleEntityIds
        originalTool = EditorViewportSettings.shared.tool

        scene = Scene()
        gameMode = false
        activeEntity = .invalid
        gizmoTargets = []
        input.keyState = KeyState()
        EditorViewportSettings.shared.tool = .move
        playback = EditorPlaybackSettings(defaults: nil)
        ViewportCameras.playback = playback
        selectionManager = SelectionManager()
        editorController = EditorController(selectionManager: selectionManager)
        editorController?.isEnabled = true
        selectionDelegate = recorder

        let camera = findSceneCamera()
        cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = camera
        renderInfo.perspectiveSpace = matrixPerspectiveRightHand(fovyRadians: .pi / 2, aspectRatio: 4.0 / 3.0, nearZ: 0.1, farZ: 100)
        // A click picks by the boxes here: the renderer that fills the tree
        // and the list of what is seen does not run in a test.
        OctreeSystem.shared.enabled = false
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func tearDown() {
        input.canvasLostTheKeyboard()
        input.cameraControlMode = .idle
        input.keyState = originalKeyState
        selectionManager.clearSelection()
        selectionManager = nil
        removeGizmo()
        gizmoTargets = []
        SelectionHighlights.shared.boxes = []
        ViewportMarqueeStore.shared.hide()
        EditorViewportSettings.shared.tool = originalTool
        OctreeSystem.shared.enabled = originalOctree
        visibleEntityIds = originalVisible
        renderInfo.perspectiveSpace = originalPerspective
        ViewportCameras.playback = originalPlayback
        selectionDelegate = originalDelegate
        editorController = originalController
        activeEntity = originalActiveEntity
        gameMode = originalGameMode
        CameraSystem.shared.activeCamera = originalActiveCamera
        bufferResources.boundingBoxBuffer = originalBoxBuffer
        scene = originalScene
        originalScene = nil
        view = nil
        super.tearDown()
    }

    // MARK: - Helpers

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
        visibleEntityIds.append(entity)
        return entity
    }

    /// A drag of the left button from one point of the canvas to another,
    /// through a point between them, and its release.
    private func drag(from start: NSPoint, to end: NSPoint, release: Bool = true) {
        let between = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        input.beginObjectDrag(at: start, in: view)
        input.continueObjectDrag(to: between, translation: NSPoint(x: between.x - start.x, y: between.y - start.y), in: view)
        input.continueObjectDrag(to: end, translation: NSPoint(x: end.x - start.x, y: end.y - start.y), in: view)
        if release {
            input.endObjectDrag()
        }
    }

    // MARK: - The rectangle

    func test_aDrag_drawsTheRectangle_asTheViewportMeasuresIt() {
        drag(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 300, y: 250), release: false)

        XCTAssertTrue(input.isMarqueeActive)
        // From the bottom left it is 100 to 250 high; from the top, 50 to 200.
        XCTAssertEqual(ViewportMarqueeStore.shared.rect, CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    func test_theRectangle_followsADragThatGoesBackOverItsStart() {
        drag(from: NSPoint(x: 200, y: 150), to: NSPoint(x: 120, y: 200), release: false)

        XCTAssertEqual(ViewportMarqueeStore.shared.rect, CGRect(x: 120, y: 100, width: 80, height: 50))
    }

    func test_releasing_selectsWhatIsInsideTheRectangle_andTakesItAway() {
        let left = makeBox("Left", at: simd_float3(-2, 0, 0))
        let middle = makeBox("Middle", at: .zero)
        _ = makeBox("Right", at: simd_float3(3, 0, 0))

        // The left one reaches from 117 to 159 points, the middle one to 217.
        drag(from: NSPoint(x: 105, y: 125), to: NSPoint(x: 230, y: 175))

        XCTAssertEqual(recorder.selectedSeveral.count, 1)
        XCTAssertEqual(Set(recorder.selectedSeveral.first ?? []), [left, middle])
        XCTAssertNil(ViewportMarqueeStore.shared.rect)
        XCTAssertFalse(input.isMarqueeActive)
        XCTAssertEqual(recorder.clearCount, 0)
    }

    func test_aRectangleThatOnlyTouchesAnEntity_selectsNothing() {
        let box = makeBox("Box", at: .zero)
        _ = makeBox("Floor", at: simd_float3(0, -1, 0), halfExtent: 4)
        selectionManager.inspectEntity(entityId: box)

        // Over the right half of the box, and over the floor under it.
        drag(from: NSPoint(x: 200, y: 100), to: NSPoint(x: 300, y: 200))

        XCTAssertTrue(recorder.selectedSeveral.isEmpty, "neither the box it cuts nor the floor that reaches out of it")
        XCTAssertEqual(recorder.clearCount, 1, "with nothing inside, the selection is cleared")
    }

    func test_aRectangleOverNothing_clearsTheSelection() {
        let box = makeBox("Box", at: .zero)
        selectionManager.inspectEntity(entityId: box)
        XCTAssertEqual(activeEntity, box)

        drag(from: NSPoint(x: 10, y: 10), to: NSPoint(x: 60, y: 60))

        XCTAssertEqual(recorder.clearCount, 1)
        XCTAssertTrue(recorder.selectedSeveral.isEmpty)
        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertFalse(gizmoActive)
    }

    func test_withCommandHeld_theRectangleSelectsTheAssets() {
        let chair = createEntity()
        let seat = makeBox("Seat", at: simd_float3(-0.5, 0, 0))
        let back = makeBox("Back", at: simd_float3(0.5, 0, 0))
        for node in [seat, back] {
            registerComponent(entityId: node, componentType: DerivedAssetNodeComponent.self)
            scene.get(component: DerivedAssetNodeComponent.self, for: node)?.assetRootEntityId = chair
        }
        input.keyState.commandPressed = true

        drag(from: NSPoint(x: 150, y: 130), to: NSPoint(x: 250, y: 170))

        XCTAssertEqual(recorder.selectedSeveral, [[chair]])
    }

    func test_aLockedEntity_isLeftOutOfTheRectangle() {
        let free = makeBox("Free", at: simd_float3(-1, 0, 0))
        let locked = makeBox("Locked", at: simd_float3(1, 0, 0))
        selectionManager.setLocked(locked, true)

        drag(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 300, y: 200))

        XCTAssertEqual(recorder.selectedSeveral, [[free]])
    }

    // MARK: - When no rectangle is drawn

    func test_whilePlaying_aDragDrawsNoRectangle() {
        _ = makeBox("Box", at: .zero)
        playback.isSessionActive = true

        drag(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 300, y: 200), release: false)
        XCTAssertFalse(input.isMarqueeActive)
        XCTAssertNil(ViewportMarqueeStore.shared.rect)

        input.endObjectDrag()
        XCTAssertTrue(recorder.selectedSeveral.isEmpty)
        XCTAssertEqual(recorder.clearCount, 0)
    }

    func test_whileTheEditorIsDisabled_aDragDrawsNoRectangle() {
        _ = makeBox("Box", at: .zero)
        editorController?.isEnabled = false

        drag(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 300, y: 200))

        XCTAssertNil(ViewportMarqueeStore.shared.rect)
        XCTAssertTrue(recorder.selectedSeveral.isEmpty)
        XCTAssertEqual(recorder.clearCount, 0)
    }

    func test_overALockedPreview_aDragDrawsNoRectangle() {
        _ = makeBox("Box", at: .zero)
        let gameCamera = createEntity()
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        XCTAssertTrue(ViewportCameras.show(.game(gameCamera)))

        // The canvas hands a drag over only while it takes the pointer.
        let event = NSEvent()
        input.canvasLeftMouseDown(event, at: NSPoint(x: 100, y: 100))
        input.canvasLeftMouseDragged(event, to: NSPoint(x: 300, y: 200), in: view)

        XCTAssertFalse(input.isMarqueeActive)
        XCTAssertNil(ViewportMarqueeStore.shared.rect)
    }

    func test_shiftWithASelection_movesThatEntity_andDrawsNoRectangle() {
        let box = makeBox("Box", at: .zero)
        selectionManager.inspectEntity(entityId: box)
        input.keyState.shiftPressed = true

        drag(from: NSPoint(x: 10, y: 10), to: NSPoint(x: 60, y: 60))

        XCTAssertNil(ViewportMarqueeStore.shared.rect)
        XCTAssertEqual(recorder.clearCount, 0)
        XCTAssertEqual(activeEntity, box)
    }

    func test_losingTheKeyboard_takesTheRectangleAway_andSelectsNothing() {
        _ = makeBox("Box", at: .zero)
        let event = NSEvent()
        input.canvasLeftMouseDown(event, at: NSPoint(x: 100, y: 100))
        input.canvasLeftMouseDragged(event, to: NSPoint(x: 300, y: 200), in: view)
        XCTAssertNotNil(ViewportMarqueeStore.shared.rect)

        input.canvasLostTheKeyboard()

        XCTAssertNil(ViewportMarqueeStore.shared.rect)
        XCTAssertFalse(input.isMarqueeActive)
        XCTAssertTrue(recorder.selectedSeveral.isEmpty)
        XCTAssertEqual(recorder.clearCount, 0)
    }

    // MARK: - Through the editor's controller

    func test_theControllerSelectsWhatStoodInsideTheRectangle() {
        let first = makeBox("First", at: simd_float3(-1, 0, 0))
        let second = makeBox("Second", at: simd_float3(1, 0, 0))
        selectionDelegate = editorController

        drag(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 300, y: 200))

        let selected = expectation(description: "the selection follows on the main queue")
        DispatchQueue.main.async { selected.fulfill() }
        wait(for: [selected], timeout: 1)
        XCTAssertEqual(Set(selectionManager.selectedEntities), [first, second])
        XCTAssertEqual(Set(gizmoTargets), [first, second])
        XCTAssertTrue(gizmoActive)
    }

    // MARK: - Clicks

    func test_aShiftClick_togglesWhatIsUnderThePointer() {
        let box = makeBox("Box", at: .zero)
        input.keyState.shiftPressed = true

        input.selectEntity(at: NSPoint(x: 200, y: 150), in: view)

        XCTAssertEqual(recorder.toggled, [box])
        XCTAssertTrue(recorder.selectedOne.isEmpty)
        XCTAssertEqual(recorder.clearCount, 0)
    }

    func test_aShiftClick_onEmptySpace_changesNothing() {
        let box = makeBox("Box", at: .zero)
        selectionManager.inspectEntity(entityId: box)
        input.keyState.shiftPressed = true

        input.selectEntity(at: NSPoint(x: 20, y: 20), in: view)

        XCTAssertTrue(recorder.toggled.isEmpty)
        XCTAssertEqual(recorder.clearCount, 0)
        XCTAssertEqual(activeEntity, box)
        XCTAssertTrue(gizmoActive, "the gizmo stays where it is")
    }

    func test_aShiftCommandClick_togglesTheAsset() {
        let chair = createEntity()
        registerTransformComponent(entityId: chair)
        let seat = makeBox("Seat", at: .zero)
        registerComponent(entityId: seat, componentType: DerivedAssetNodeComponent.self)
        scene.get(component: DerivedAssetNodeComponent.self, for: seat)?.assetRootEntityId = chair
        input.keyState.shiftPressed = true
        input.keyState.commandPressed = true

        input.selectEntity(at: NSPoint(x: 200, y: 150), in: view)

        XCTAssertEqual(recorder.toggled, [chair])
    }

    func test_aClickOnAnotherEntity_selectsIt_thoughAGizmoShows() {
        let selected = makeBox("Selected", at: simd_float3(-2, 0, 0))
        let other = makeBox("Other", at: simd_float3(2, 0, 0))
        selectionManager.inspectEntity(entityId: selected)
        XCTAssertTrue(gizmoActive)

        // Two units to the right of the middle: 60 points.
        input.selectEntity(at: NSPoint(x: 260, y: 150), in: view)

        XCTAssertEqual(recorder.clearCount, 0, "it used to find nothing and clear the selection")
        XCTAssertEqual(recorder.selectedOne + recorder.inspectedMeshes, [other])
        XCTAssertEqual(activeEntity, other)
    }

    func test_aClickOnEmptySpace_stillClearsTheSelection_whileAGizmoShows() {
        let selected = makeBox("Selected", at: simd_float3(-2, 0, 0))
        selectionManager.inspectEntity(entityId: selected)

        input.selectEntity(at: NSPoint(x: 380, y: 280), in: view)

        XCTAssertEqual(recorder.clearCount, 1)
        XCTAssertEqual(activeEntity, .invalid)
    }
}
