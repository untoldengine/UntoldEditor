//
//  CameraNavigationDragTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Drives the drags by their phases to check what the right button does to
//  the scene camera, and that the left one leaves it alone.
//

import AppKit
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class CameraNavigationDragTests: XCTestCase {
    private var originalScene: Scene!
    private var savedStyle: CameraNavigationStyle!
    private var savedActiveEntity: EntityID!
    private var savedActiveCamera: EntityID?
    private var savedGameMode = false
    private var view: NSView!

    override func setUp() {
        super.setUp()
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()

        originalScene = scene
        scene = Scene()
        let camera = createEntity()
        createSceneCamera(entityId: camera)
        // Within the pivot range of the origin, so re-anchoring keeps the origin as the target.
        cameraLookAt(entityId: camera, eye: simd_float3(0, 2, 3), target: .zero, up: simd_float3(0, 1, 0))

        // Editing, with the viewport on the editor's camera.
        savedGameMode = gameMode
        savedActiveCamera = CameraSystem.shared.activeCamera
        gameMode = false
        CameraSystem.shared.activeCamera = camera

        savedStyle = EditorNavigationSettings.shared.style
        savedActiveEntity = activeEntity
        activeEntity = .invalid
        InputSystem.shared.keyState.shiftPressed = false
        InputSystem.shared.keyState.commandPressed = false
        InputSystem.shared.keyState.altPressed = false
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func tearDown() {
        EditorNavigationSettings.shared.style = savedStyle
        activeEntity = savedActiveEntity
        InputSystem.shared.keyState.shiftPressed = false
        InputSystem.shared.keyState.commandPressed = false
        InputSystem.shared.keyState.altPressed = false
        InputSystem.shared.cameraControlMode = .idle
        gameMode = savedGameMode
        CameraSystem.shared.activeCamera = savedActiveCamera
        scene = originalScene
        super.tearDown()
    }

    /// A drag with the right button, the camera's. `translation` has Y up.
    private func drag(translation: NSPoint) {
        InputSystem.shared.beginCameraDrag()
        InputSystem.shared.moveCameraDrag(by: simd_float2(Float(translation.x), Float(translation.y)))
        InputSystem.shared.endCameraDrag()
    }

    /// A drag with the left button, which works on the selection.
    private func leftDrag(translation: NSPoint) {
        let start = NSPoint(x: 200, y: 150)
        InputSystem.shared.beginObjectDrag(at: start, in: view)
        InputSystem.shared.continueObjectDrag(
            to: NSPoint(x: start.x + translation.x, y: start.y + translation.y),
            translation: translation,
            in: view
        )
        InputSystem.shared.endObjectDrag()
    }

    private var eye: simd_float3 {
        getCameraEye(entityId: findSceneCamera())
    }

    private var target: simd_float3 {
        getCameraTarget(entityId: findSceneCamera())
    }

    // MARK: - The right button

    func test_plainDragLooksAroundWhereTheCameraStands() {
        let eyeBefore = eye
        let distanceBefore = simd_length(eye - target)

        drag(translation: NSPoint(x: 100, y: 0))

        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-4, "looking around never moves the camera")
        XCTAssertEqual(simd_length(eye - target), distanceBefore, accuracy: 1e-3, "the target stays as far ahead")
        // The camera faced -Z; a drag to the right turns the view to the right, toward +X.
        XCTAssertGreaterThan(target.x, 0.5)
    }

    func test_lookDragUpTiltsTheViewUp() {
        let targetBefore = target

        drag(translation: NSPoint(x: 0, y: 60))

        XCTAssertGreaterThan(target.y, targetBefore.y + 0.5)
        XCTAssertEqual(target.x, targetBefore.x, accuracy: 1e-3, "a vertical drag does not turn the view sideways")
    }

    func test_lookStopsShortOfStraightUpAndDown() {
        drag(translation: NSPoint(x: 0, y: 5000))
        let up = simd_normalize(target - eye)
        XCTAssertEqual(up.y, sin(InputSystem.lookPitchLimit), accuracy: 1e-3)

        drag(translation: NSPoint(x: 0, y: -10000))
        let down = simd_normalize(target - eye)
        XCTAssertEqual(down.y, -sin(InputSystem.lookPitchLimit), accuracy: 1e-3)
        // Still heading the way it was: the view tilted, it did not flip over.
        XCTAssertLessThan(down.z, 0)
    }

    func test_lookDirection_turnsAboutTheWorldUpAxis() {
        let ahead = simd_float3(0, 0, -1)
        let quarterTurn = Float.pi / 2 / InputSystem.lookSpeed

        let right = InputSystem.lookDirection(from: ahead, up: simd_float3(0, 1, 0), delta: simd_float2(quarterTurn, 0))
        XCTAssertEqual(simd_distance(right, simd_float3(1, 0, 0)), 0, accuracy: 1e-3)

        let left = InputSystem.lookDirection(from: ahead, up: simd_float3(0, 1, 0), delta: simd_float2(-quarterTurn, 0))
        XCTAssertEqual(simd_distance(left, simd_float3(-1, 0, 0)), 0, accuracy: 1e-3)

        let still = InputSystem.lookDirection(from: simd_float3(3, -2, -5), up: simd_float3(0, 1, 0), delta: .zero)
        XCTAssertEqual(simd_distance(still, simd_normalize(simd_float3(3, -2, -5))), 0, accuracy: 1e-4)
    }

    func test_lookDirection_fromStraightDown_takesItsHeadingFromTheTopOfTheView() {
        // The Top view: looking down with -Z at the top of the screen.
        let fromTop = InputSystem.lookDirection(from: simd_float3(0, -1, 0), up: simd_float3(0, 0, -1), delta: .zero)
        XCTAssertLessThan(fromTop.z, 0, "tilting up from the Top view heads toward -Z")
        XCTAssertEqual(fromTop.x, 0, accuracy: 1e-4)

        // Looking straight up, the top of the view points behind the camera.
        let fromBelow = InputSystem.lookDirection(from: simd_float3(0, 1, 0), up: simd_float3(0, 0, 1), delta: .zero)
        XCTAssertLessThan(fromBelow.z, 0)

        let broken = InputSystem.lookDirection(from: .zero, up: simd_float3(0, 1, 0), delta: simd_float2(10, 10))
        XCTAssertEqual(broken, .zero, "no direction to turn")
    }

    func test_shiftDragPansEyeAndTargetTogether() {
        InputSystem.shared.keyState.shiftPressed = true
        let eyeBefore = eye, targetBefore = target

        drag(translation: NSPoint(x: 100, y: 0))

        let eyeOffset = eye - eyeBefore
        let targetOffset = target - targetBefore
        XCTAssertGreaterThan(simd_length(eyeOffset), 0.01, "eye did not move")
        XCTAssertEqual(simd_length(eyeOffset - targetOffset), 0, accuracy: 1e-4, "pan must move eye and target by the same offset")
        XCTAssertEqual(simd_length(eye - target), simd_length(eyeBefore - targetBefore), accuracy: 1e-3)
    }

    func test_commandDragMovesTowardTheTarget() {
        InputSystem.shared.keyState.commandPressed = true
        let distanceBefore = simd_length(eye - target)

        drag(translation: NSPoint(x: 0, y: 40))

        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-4, "moving keeps the target")
        XCTAssertLessThan(simd_length(eye - target), distanceBefore, "dragging up should move the camera in")
    }

    func test_optionDragOrbits() {
        InputSystem.shared.keyState.altPressed = true
        let eyeBefore = eye
        let distanceBefore = simd_length(eye - target)

        drag(translation: NSPoint(x: 60, y: 0))

        XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01)
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-3, "orbit keeps the target")
        XCTAssertEqual(simd_length(eye - target), distanceBefore, accuracy: 1e-3, "orbit keeps the distance")
    }

    func test_theNavigationStyleDoesNotChangeWhatADragDoes() {
        for style in CameraNavigationStyle.allCases {
            EditorNavigationSettings.shared.style = style
            let camera = findSceneCamera()
            cameraLookAt(entityId: camera, eye: simd_float3(0, 2, 3), target: .zero, up: simd_float3(0, 1, 0))
            InputSystem.shared.keyState.shiftPressed = true
            let eyeBefore = eye, targetBefore = target

            drag(translation: NSPoint(x: 100, y: 0))

            XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01, "\(style.title): ⇧ pans")
            XCTAssertEqual(simd_length((eye - eyeBefore) - (target - targetBefore)), 0, accuracy: 1e-4, style.title)
        }
    }

    func test_onlyAnOrbitHoldsTheFlyKeysBack() {
        InputSystem.shared.beginCameraDrag()
        XCTAssertEqual(InputSystem.shared.cameraControlMode, .moving, "the keys fly while the mouse looks")
        InputSystem.shared.endCameraDrag()
        XCTAssertEqual(InputSystem.shared.cameraControlMode, .idle)

        InputSystem.shared.keyState.altPressed = true
        InputSystem.shared.beginCameraDrag()
        XCTAssertEqual(InputSystem.shared.cameraControlMode, .orbiting)
        InputSystem.shared.endCameraDrag()
        XCTAssertEqual(InputSystem.shared.cameraControlMode, .idle)
    }

    func test_aModifierReleasedHalfway_doesNotChangeWhatTheDragDoes() {
        InputSystem.shared.keyState.shiftPressed = true
        let eyeBefore = eye, targetBefore = target
        InputSystem.shared.beginCameraDrag()
        InputSystem.shared.keyState.shiftPressed = false

        InputSystem.shared.moveCameraDrag(by: simd_float2(100, 0))
        InputSystem.shared.endCameraDrag()

        XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01, "it began as a pan and stays one")
        XCTAssertEqual(simd_length((eye - eyeBefore) - (target - targetBefore)), 0, accuracy: 1e-4)
    }

    func test_movingWithNoDragBegun_doesNothing() {
        let eyeBefore = eye, targetBefore = target

        InputSystem.shared.moveCameraDrag(by: simd_float2(100, 40))

        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }

    func test_whileAGamePlaysOnItsOwnCamera_theDragLeavesTheSceneCameraAlone() {
        let gameCamera = createEntity()
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        CameraSystem.shared.activeCamera = gameCamera
        gameMode = true
        let eyeBefore = eye, targetBefore = target

        drag(translation: NSPoint(x: 100, y: 40))

        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }

    // MARK: - The navigation controls over the viewport

    /// A drag on a navigation control, which says itself what it does.
    private func controlDrag(_ action: CameraDragAction, translation: NSPoint) {
        let handlers = NavigationDragHandlers.camera(action)
        handlers.began()
        handlers.moved(simd_float2(Float(translation.x), Float(translation.y)))
        handlers.ended()
    }

    func test_theGizmosDrag_orbitsAsTheRightButtonDoesWithOption() {
        let eyeBefore = eye
        let distanceBefore = simd_length(eye - target)

        controlDrag(.orbit, translation: NSPoint(x: 60, y: 0))
        let byTheControl = eye

        XCTAssertGreaterThan(simd_length(byTheControl - eyeBefore), 0.01)
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-3, "orbit keeps the target")
        XCTAssertEqual(simd_length(byTheControl - target), distanceBefore, accuracy: 1e-3, "orbit keeps the distance")

        cameraLookAt(entityId: findSceneCamera(), eye: eyeBefore, target: .zero, up: simd_float3(0, 1, 0))
        InputSystem.shared.keyState.altPressed = true
        drag(translation: NSPoint(x: 60, y: 0))
        XCTAssertEqual(simd_length(eye - byTheControl), 0, accuracy: 1e-4, "the same turn either way")
    }

    func test_thePanButton_movesEyeAndTargetTogether() {
        let eyeBefore = eye, targetBefore = target

        controlDrag(.pan, translation: NSPoint(x: 100, y: 0))

        XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01)
        XCTAssertEqual(simd_length((eye - eyeBefore) - (target - targetBefore)), 0, accuracy: 1e-4)
    }

    func test_theZoomButton_draggedUp_movesTheCameraIn() {
        let distanceBefore = simd_length(eye - target)

        controlDrag(.zoom, translation: NSPoint(x: 0, y: 40))

        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-4, "zooming keeps the target")
        XCTAssertLessThan(simd_length(eye - target), distanceBefore)
    }

    func test_aControl_doesWhatItSays_whateverKeyIsHeld() {
        InputSystem.shared.keyState.shiftPressed = true
        let distanceBefore = simd_length(eye - target)

        controlDrag(.zoom, translation: NSPoint(x: 0, y: 40))

        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-4, "⇧ would have panned, and moved the target")
        XCTAssertLessThan(simd_length(eye - target), distanceBefore)
    }

    func test_overALockedPreview_aControlMovesNothing() {
        let gameCamera = createEntity()
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        CameraSystem.shared.activeCamera = gameCamera
        let eyeBefore = eye, targetBefore = target

        controlDrag(.pan, translation: NSPoint(x: 100, y: 40))

        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }

    // MARK: - The left button

    func test_leftDragLeavesTheCameraAlone() {
        for (shift, command) in [(false, false), (true, false), (false, true)] {
            InputSystem.shared.keyState.shiftPressed = shift
            InputSystem.shared.keyState.commandPressed = command
            let eyeBefore = eye, targetBefore = target

            leftDrag(translation: NSPoint(x: 100, y: 40))

            XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
            XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
        }
        XCTAssertEqual(InputSystem.shared.cameraControlMode, .idle)
    }

    // MARK: - Scrolling

    func test_scrollOrbitKeepsTargetAndDistance() {
        let eyeBefore = eye
        let distanceBefore = simd_length(eye - target)

        InputSystem.shared.orbitSceneCamera(byScroll: simd_float2(-3, 0), precise: false)

        XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01, "a wheel notch should orbit")
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-3, "orbit keeps the target")
        XCTAssertEqual(simd_length(eye - target), distanceBefore, accuracy: 1e-3, "orbit keeps the distance")
        XCTAssertEqual(eye.y, eyeBefore.y, accuracy: 1e-3, "a horizontal scroll yaws around the world up axis")
    }

    func test_scrollOrbitAfterPanOrbitsAroundTheNewTarget() {
        InputSystem.shared.keyState.shiftPressed = true
        drag(translation: NSPoint(x: 100, y: 0))
        InputSystem.shared.keyState.shiftPressed = false
        let pannedTarget = target
        XCTAssertGreaterThan(simd_length(pannedTarget), 0.01)

        InputSystem.shared.orbitSceneCamera(byScroll: simd_float2(0, 40), precise: true)

        XCTAssertEqual(simd_length(target - pannedTarget), 0, accuracy: 1e-3, "orbit re-anchors on the panned target")
    }

    func test_scrollPanMovesEyeAndTargetTogether() {
        let eyeBefore = eye, targetBefore = target

        InputSystem.shared.panSceneCamera(byScroll: simd_float2(20, -10), precise: true)

        let eyeOffset = eye - eyeBefore
        let targetOffset = target - targetBefore
        XCTAssertGreaterThan(simd_length(eyeOffset), 0.01, "a swipe should pan")
        XCTAssertEqual(simd_length(eyeOffset - targetOffset), 0, accuracy: 1e-4, "pan moves eye and target by the same offset")
        XCTAssertEqual(simd_length(eye - target), simd_length(eyeBefore - targetBefore), accuracy: 1e-3)
        // The scene follows the scroll (right, and up for a negative document Y),
        // so the camera itself moves the opposite way.
        XCTAssertLessThan(eyeOffset.x, 0)
        XCTAssertLessThan(eyeOffset.y, 0)
    }

    func test_wheelPanIsScaledUpFromTrackpadPan() {
        let eyeBefore = eye
        InputSystem.shared.panSceneCamera(byScroll: simd_float2(2, 0), precise: true)
        let preciseOffset = simd_length(eye - eyeBefore)

        InputSystem.shared.panSceneCamera(byScroll: simd_float2(2, 0), precise: false)
        let wheelOffset = simd_length(eye - eyeBefore) - preciseOffset

        XCTAssertEqual(wheelOffset / preciseOffset, InputSystem.scrollWheelPanMultiplier, accuracy: 0.05)
    }

    // MARK: - Orbit pivot

    func test_orbitPivotIsTheGroundHitOnTheViewRay() {
        let pivot = InputSystem.orbitPivot(
            eye: simd_float3(0, 2, 3),
            forward: simd_float3(0, -2, -3),
            currentTarget: simd_float3(50, 0, 50)
        )
        XCTAssertEqual(simd_length(pivot), 0, accuracy: 1e-4)
    }

    func test_orbitPivotKeepsThePreviousDepthWhenLookingAtTheSky() {
        // Looking up: no ground hit. The old target sits 8 ahead but off to the
        // side; only its depth is kept so adopting the pivot does not turn the view.
        let eye = simd_float3(0, 5, 0)
        let forward = simd_float3(0, 1, -1)
        let pivot = InputSystem.orbitPivot(eye: eye, forward: forward, currentTarget: eye + simd_normalize(forward) * 8 + simd_float3(2, 0, 0))
        XCTAssertEqual(simd_distance(pivot, eye + simd_normalize(forward) * 8), 0, accuracy: 1e-4)
    }

    func test_orbitPivotFallsBackToTheDefaultDepth() {
        // Sky ahead and the old target behind the camera.
        let eye = simd_float3(0, 5, 0)
        let forward = simd_float3(0, 1, -1)
        let pivot = InputSystem.orbitPivot(eye: eye, forward: forward, currentTarget: simd_float3(0, 5, 20))
        XCTAssertEqual(simd_distance(pivot, eye), InputSystem.defaultOrbitPivotDistance, accuracy: 1e-4)

        // Ground so far away that a notch would sweep a huge arc.
        let grazing = InputSystem.orbitPivot(eye: eye, forward: simd_float3(0, -0.01, -1), currentTarget: simd_float3(0, 5, 20))
        XCTAssertEqual(simd_distance(grazing, eye), InputSystem.defaultOrbitPivotDistance, accuracy: 1e-4)
    }

    func test_orbitPivotTakesTheNearestCandidateInRange() {
        // Zoomed in to 1.5 ahead, ground 5 away, an object at 3: the zoom wins.
        let eye = simd_float3(0, 3, 0)
        let forward = simd_normalize(simd_float3(0, -3, -4))
        let zoomed = InputSystem.orbitPivot(eye: eye, forward: forward, currentTarget: eye + forward * 1.5, sceneHitDistance: 3)
        XCTAssertEqual(simd_distance(zoomed, eye), 1.5, accuracy: 1e-4)

        // Skimming over an object to ground far behind it: the object wins over
        // the ground and over a stale target that is far ahead.
        let level = simd_float3(0, 1, 0)
        let grazing = simd_normalize(simd_float3(0, -0.02, -1))
        let object = InputSystem.orbitPivot(eye: level, forward: grazing, currentTarget: level + grazing * 80, sceneHitDistance: 2)
        XCTAssertEqual(simd_distance(object, level), 2, accuracy: 1e-4)

        // Out-of-range candidates are ignored: a hit right at the lens and a target
        // past the limit leave the ground, 50 away, as the only valid candidate.
        let ignored = InputSystem.orbitPivot(eye: level, forward: grazing, currentTarget: level + grazing * 500, sceneHitDistance: 0.1)
        XCTAssertEqual(simd_distance(ignored, level), 50, accuracy: 0.05)
    }

    func test_gaussianBoundsUnderTheViewCentreSetThePivot() {
        // A splat box 1 unit across, sitting on the ground at the origin, between the
        // camera and the ground hit: the pivot lands on the box, not the ground behind it.
        let splat = createEntity()
        registerComponent(entityId: splat, componentType: GaussianComponent.self)
        scene.get(component: LocalTransformComponent.self, for: splat)?.boundingBox = (
            min: simd_float3(-0.5, -0.5, -0.5), max: simd_float3(0.5, 0.5, 0.5)
        )
        translateTo(entityId: splat, position: simd_float3(0, 0.5, 0))

        let forward = simd_normalize(simd_float3(0, -2, -3))
        let hit = InputSystem.gaussianBoundsHit(rayOrigin: eye, rayDirection: forward)
        XCTAssertEqual(hit?.entityId, splat)
        XCTAssertEqual(hit?.distance ?? -1, 3.0, accuracy: 0.01, "ray enters the box on its front face")
        XCTAssertEqual(
            InputSystem.gaussianBoundsDepth(rayOrigin: eye, rayDirection: forward) ?? -1,
            hit?.distance ?? -2,
            accuracy: 0.0001
        )

        InputSystem.shared.reanchorSceneCameraTarget()

        XCTAssertEqual(simd_distance(target, simd_float3(0, 1.0 / 3.0, 0.5)), 0, accuracy: 0.01)
        XCTAssertNil(InputSystem.gaussianBoundsDepth(rayOrigin: eye, rayDirection: simd_float3(0, 1, 0)), "looking up misses the box")
    }

    func test_reanchorAfterFlyingMovesTheTargetNotTheCamera() throws {
        // Fly sideways and closer, with the target left behind at the origin, as WASD does.
        let camera = findSceneCamera()
        translateTo(entityId: camera, position: simd_float3(6, 2, 4))
        // Still looking along (0, -2, -3): from here the view ray meets the ground at (6, 0, 1).
        let cameraComponent = try XCTUnwrap(scene.get(component: CameraComponent.self, for: camera))
        let viewBefore = cameraComponent.viewSpace
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-4, "target is stale after flying")

        InputSystem.shared.reanchorSceneCameraTarget()

        XCTAssertEqual(simd_distance(eye, simd_float3(6, 2, 4)), 0, accuracy: 1e-4, "re-anchoring never moves the camera")
        XCTAssertEqual(simd_distance(target, simd_float3(6, 0, 1)), 0, accuracy: 1e-3, "target lands where the view ray meets the ground")
        for column in 0 ..< 4 {
            XCTAssertEqual(simd_length(cameraComponent.viewSpace[column] - viewBefore[column]), 0, accuracy: 1e-4, "re-anchoring never turns the camera")
        }
    }

    func test_zeroScrollLeavesCameraAlone() {
        let eyeBefore = eye
        InputSystem.shared.orbitSceneCamera(byScroll: .zero, precise: true)
        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
    }

    func test_shiftLeftDragWithSelectionTakesNoGizmoHandle() {
        // A selection only counts while an enabled editor controller exists, as in the app.
        let savedController = editorController
        let savedGizmoActive = gizmoActive
        let savedHitGizmo = activeHitGizmoEntity
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = true
        defer {
            editorController = savedController
            gizmoActive = savedGizmoActive
            activeHitGizmoEntity = savedHitGizmo
        }
        InputSystem.shared.keyState.shiftPressed = true
        activeEntity = createEntity()
        activeHitGizmoEntity = .invalid
        let eyeBefore = eye, targetBefore = target

        leftDrag(translation: NSPoint(x: 100, y: 0))

        XCTAssertEqual(activeHitGizmoEntity, .invalid, "the drag is left to the entity's own ⇧-drag")
        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }
}
