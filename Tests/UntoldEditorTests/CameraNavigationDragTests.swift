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
