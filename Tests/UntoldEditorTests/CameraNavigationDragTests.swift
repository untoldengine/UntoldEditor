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
//  Drives `handlePanGesture` with a stubbed recogniser to check what a
//  left-button drag does to the scene camera in each navigation style.
//

import AppKit
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// A pan recogniser whose state and translation the test sets directly.
private final class StubPanGesture: NSPanGestureRecognizer {
    var stubState: NSGestureRecognizer.State = .possible
    var stubTranslation: NSPoint = .zero
    var stubLocation = NSPoint(x: 200, y: 150)

    override var state: NSGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override func translation(in _: NSView?) -> NSPoint {
        stubTranslation
    }

    override func location(in _: NSView?) -> NSPoint {
        stubLocation
    }
}

final class CameraNavigationDragTests: XCTestCase {
    private var originalScene: Scene!
    private var savedStyle: CameraNavigationStyle!
    private var savedActiveEntity: EntityID!
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
        cameraLookAt(entityId: camera, eye: simd_float3(0, 5, 10), target: .zero, up: simd_float3(0, 1, 0))

        savedStyle = EditorNavigationSettings.shared.style
        savedActiveEntity = activeEntity
        activeEntity = .invalid
        InputSystem.shared.keyState.shiftPressed = false
        InputSystem.shared.keyState.commandPressed = false
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func tearDown() {
        EditorNavigationSettings.shared.style = savedStyle
        activeEntity = savedActiveEntity
        InputSystem.shared.keyState.shiftPressed = false
        InputSystem.shared.keyState.commandPressed = false
        InputSystem.shared.cameraControlMode = .idle
        scene = originalScene
        super.tearDown()
    }

    private func drag(translation: NSPoint) {
        let gesture = StubPanGesture()
        gesture.stubState = .began
        InputSystem.shared.handlePanGesture(gesture, in: view)
        gesture.stubState = .changed
        gesture.stubTranslation = translation
        InputSystem.shared.handlePanGesture(gesture, in: view)
        gesture.stubState = .ended
        InputSystem.shared.handlePanGesture(gesture, in: view)
    }

    private var eye: simd_float3 {
        getCameraEye(entityId: findSceneCamera())
    }

    private var target: simd_float3 {
        getCameraTarget(entityId: findSceneCamera())
    }

    func test_blenderShiftDragPansEyeAndTargetTogether() {
        EditorNavigationSettings.shared.style = .blender
        InputSystem.shared.keyState.shiftPressed = true
        let eyeBefore = eye, targetBefore = target

        drag(translation: NSPoint(x: 100, y: 0))

        let eyeOffset = eye - eyeBefore
        let targetOffset = target - targetBefore
        XCTAssertGreaterThan(simd_length(eyeOffset), 0.01, "eye did not move")
        XCTAssertEqual(simd_length(eyeOffset - targetOffset), 0, accuracy: 1e-4, "pan must move eye and target by the same offset")
        XCTAssertEqual(simd_length(eye - target), simd_length(eyeBefore - targetBefore), accuracy: 1e-3)
    }

    func test_blenderCommandDragZoomsTowardTarget() {
        EditorNavigationSettings.shared.style = .blender
        InputSystem.shared.keyState.commandPressed = true
        let distanceBefore = simd_length(eye - target)

        drag(translation: NSPoint(x: 0, y: 40))

        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-4, "zoom keeps the target")
        XCTAssertLessThan(simd_length(eye - target), distanceBefore, "dragging up should dolly in")
    }

    func test_blenderPlainDragOrbits() {
        EditorNavigationSettings.shared.style = .blender
        let eyeBefore = eye

        drag(translation: NSPoint(x: 60, y: 0))

        XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01)
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-3, "orbit keeps the target")
    }

    func test_classicShiftDragStillOrbits() {
        EditorNavigationSettings.shared.style = .classic
        InputSystem.shared.keyState.shiftPressed = true
        let eyeBefore = eye

        drag(translation: NSPoint(x: 60, y: 0))

        XCTAssertGreaterThan(simd_length(eye - eyeBefore), 0.01)
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-3)
    }

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
        EditorNavigationSettings.shared.style = .blender
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
            eye: simd_float3(0, 5, 10),
            forward: simd_float3(0, -5, -10),
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

    func test_reanchorAfterFlyingMovesTheTargetNotTheCamera() throws {
        // Fly sideways with the target left behind at the origin, as WASD does.
        let camera = findSceneCamera()
        translateTo(entityId: camera, position: simd_float3(6, 5, 10))
        let cameraComponent = try XCTUnwrap(scene.get(component: CameraComponent.self, for: camera))
        let viewBefore = cameraComponent.viewSpace
        XCTAssertEqual(simd_length(target), 0, accuracy: 1e-4, "target is stale after flying")

        InputSystem.shared.reanchorSceneCameraTarget()

        XCTAssertEqual(simd_distance(eye, simd_float3(6, 5, 10)), 0, accuracy: 1e-4, "re-anchoring never moves the camera")
        XCTAssertEqual(simd_distance(target, simd_float3(6, 0, 0)), 0, accuracy: 1e-3, "target lands where the view ray meets the ground")
        for column in 0 ..< 4 {
            XCTAssertEqual(simd_length(cameraComponent.viewSpace[column] - viewBefore[column]), 0, accuracy: 1e-4, "re-anchoring never turns the camera")
        }
    }

    func test_zeroScrollLeavesCameraAlone() {
        let eyeBefore = eye
        InputSystem.shared.orbitSceneCamera(byScroll: .zero, precise: true)
        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
    }

    func test_shiftDragWithSelectionLeavesCameraAlone() {
        // A selection only counts while an enabled editor controller exists, as in the app.
        let savedController = editorController
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = true
        defer { editorController = savedController }
        EditorNavigationSettings.shared.style = .blender
        InputSystem.shared.keyState.shiftPressed = true
        let selected = createEntity()
        activeEntity = selected
        let eyeBefore = eye, targetBefore = target

        drag(translation: NSPoint(x: 100, y: 0))

        XCTAssertEqual(simd_length(eye - eyeBefore), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }
}
