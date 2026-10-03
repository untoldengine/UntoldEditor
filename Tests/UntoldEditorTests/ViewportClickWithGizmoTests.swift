//
//  ViewportClickWithGizmoTests.swift
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

private final class ClickRecorder: SelectionDelegate {
    var clearCount = 0
    var selected: [EntityID] = []

    func didSelectEntity(_ entityId: EntityID) {
        selected.append(entityId)
    }

    func didInspectEntity(_: EntityID) {}
    func didInspectMesh(_ entityId: EntityID, meshIndex _: Int) {
        selected.append(entityId)
    }

    func didClearSelection() {
        clearCount += 1
    }

    func resetActiveAxis() {}
}

/// A click while a gizmo shows: on another entity it selects that entity, on
/// empty space it clears the selection, and on a handle it takes nothing.
///
/// The camera stands five units in front of the origin over a canvas of 400
/// by 300 points: a unit of the world at the origin is 30 points, and the
/// middle is (200, 150), measured from the bottom left.
final class ViewportClickWithGizmoTests: XCTestCase {
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
    private let recorder = ClickRecorder()
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
        input.keyState = KeyState()
        EditorViewportSettings.shared.tool = .move
        ViewportCameras.playback = EditorPlaybackSettings(defaults: nil)
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
        visibleEntityIds = []
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func tearDown() {
        input.keyState = originalKeyState
        selectionManager.clearSelection()
        selectionManager = nil
        removeGizmo()
        EditorViewportSettings.shared.tool = originalTool
        visibleEntityIds = originalVisible
        OctreeSystem.shared.enabled = originalOctree
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

    func test_aClickOnAnotherEntity_selectsIt_thoughAGizmoShows() {
        let selected = makeBox("Selected", at: simd_float3(-2, 0, 0))
        let other = makeBox("Other", at: simd_float3(2, 0, 0))
        selectionManager.inspectEntity(entityId: selected)
        XCTAssertTrue(gizmoActive, "the Move tool puts a gizmo on the selection")

        // Two units to the right of the middle: 60 points.
        input.selectEntity(at: NSPoint(x: 260, y: 150), in: view)

        XCTAssertEqual(recorder.clearCount, 0, "it used to find nothing and clear the selection")
        XCTAssertEqual(recorder.selected, [other])
        XCTAssertEqual(activeEntity, other)
    }

    func test_aClickOnEmptySpace_stillClearsTheSelection_whileAGizmoShows() {
        let selected = makeBox("Selected", at: simd_float3(-2, 0, 0))
        selectionManager.inspectEntity(entityId: selected)
        XCTAssertTrue(gizmoActive)

        input.selectEntity(at: NSPoint(x: 380, y: 280), in: view)

        XCTAssertEqual(recorder.clearCount, 1)
        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertFalse(gizmoActive)
    }

    func test_aClickOnTheSelectedEntity_keepsIt() {
        let selected = makeBox("Selected", at: simd_float3(-2, 0, 0))
        selectionManager.inspectEntity(entityId: selected)

        // Two units to the left of the middle, away from the handles.
        input.selectEntity(at: NSPoint(x: 140, y: 150), in: view)

        XCTAssertEqual(recorder.clearCount, 0)
        XCTAssertEqual(activeEntity, selected)
    }
}
