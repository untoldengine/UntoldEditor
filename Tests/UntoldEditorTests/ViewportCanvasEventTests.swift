//
//  ViewportCanvasEventTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Sends the viewport's view the events AppKit would: the mouse, its buttons
//  and the keys arrive at the one view and reach the scene through it.
//

import AppKit
import MetalKit
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

private final class CanvasSelectionRecorder: SelectionDelegate {
    var clearCount = 0
    var selected: [EntityID] = []

    func didSelectEntity(_ entityId: EntityID) {
        selected.append(entityId)
    }

    func didInspectEntity(_: EntityID) {}
    func didInspectMesh(_: EntityID, meshIndex _: Int) {}
    func didClearSelection() {
        clearCount += 1
    }

    func resetActiveAxis() {}
}

@MainActor
final class ViewportCanvasEventTests: XCTestCase {
    private var originalScene: Scene!
    private var savedActiveCamera: EntityID?
    private var savedGameMode = false
    private var savedDelegate: SelectionDelegate?
    private var savedController: EditorController?
    private var savedActiveEntity: EntityID!
    private var savedKeyState = KeyState()
    private let recorder = CanvasSelectionRecorder()
    private var window: NSWindow!
    private var canvas: EditorViewportHostView!
    private var camera: EntityID = .invalid

    override func setUp() {
        super.setUp()
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()

        originalScene = scene
        savedActiveCamera = CameraSystem.shared.activeCamera
        savedGameMode = gameMode
        savedDelegate = selectionDelegate
        savedController = editorController
        savedActiveEntity = activeEntity
        savedKeyState = InputSystem.shared.keyState

        scene = Scene()
        gameMode = false
        camera = createEntity()
        createSceneCamera(entityId: camera)
        cameraLookAt(entityId: camera, eye: simd_float3(0, 2, 3), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = camera
        activeEntity = .invalid
        InputSystem.shared.keyState = KeyState()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        canvas = EditorViewportHostView(metalView: MTKView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), device: device))
        canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        window.contentView = canvas
    }

    override func tearDown() {
        InputSystem.shared.canvasLostTheKeyboard()
        InputSystem.shared.keyState = savedKeyState
        InputSystem.shared.cameraControlMode = .idle
        selectionDelegate = savedDelegate
        editorController = savedController
        activeEntity = savedActiveEntity
        gameMode = savedGameMode
        CameraSystem.shared.activeCamera = savedActiveCamera
        scene = originalScene
        canvas = nil
        window = nil
        super.tearDown()
    }

    // MARK: - Events

    /// A mouse event at a point of the canvas, with the step the pointer made.
    private func mouse(
        _ type: NSEvent.EventType,
        at point: NSPoint = NSPoint(x: 200, y: 150),
        step: (x: CGFloat, y: CGFloat) = (0, 0),
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        let placed = try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        return StepEvent.make(from: placed, stepX: step.x, stepY: step.y)
    }

    private func key(_ type: NSEvent.EventType, _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        ))
    }

    private var position: simd_float3 {
        scene.get(component: CameraComponent.self, for: camera)?.localPosition ?? .zero
    }

    private var target: simd_float3 {
        getCameraTarget(entityId: camera)
    }

    // MARK: - The view

    func test_theCanvasTakesTheEvents_notTheMetalViewInIt() {
        XCTAssertTrue(canvas.acceptsFirstResponder)
        XCTAssertTrue(canvas.hitTest(NSPoint(x: 200, y: 150)) === canvas)
        XCTAssertNil(canvas.hitTest(NSPoint(x: 500, y: 150)))
        XCTAssertTrue(canvas.gestureRecognizers.isEmpty)
        XCTAssertTrue(canvas.metalView.gestureRecognizers.isEmpty)
    }

    func test_hoverTakesTheKeyboard_butNotFromATextFieldBeingTypedIn() {
        XCTAssertTrue(EditorViewportHostView.canTakeKeyboardOnHover(from: nil))
        XCTAssertTrue(EditorViewportHostView.canTakeKeyboardOnHover(from: window))
        XCTAssertFalse(EditorViewportHostView.canTakeKeyboardOnHover(from: NSTextView()))
    }

    func test_aPressOnTheCanvas_bringsTheKeyboardToIt() throws {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        canvas.addSubview(field)
        window.makeFirstResponder(field)
        XCTAssertFalse(window.firstResponder === canvas)

        try canvas.rightMouseDown(with: mouse(.rightMouseDown))

        XCTAssertTrue(window.firstResponder === canvas)
        try canvas.rightMouseUp(with: mouse(.rightMouseUp))
    }

    // MARK: - The right button and the keys

    func test_rightDrag_looksAround_whereTheCameraStands() throws {
        let before = position

        try canvas.rightMouseDown(with: mouse(.rightMouseDown))
        try canvas.rightMouseDragged(with: mouse(.rightMouseDragged, step: (100, 0)))
        try canvas.rightMouseUp(with: mouse(.rightMouseUp))

        XCTAssertEqual(simd_length(position - before), 0, accuracy: 1e-4)
        XCTAssertGreaterThan(target.x, 0.5, "a drag to the right turns the view to the right")
        XCTAssertFalse(InputSystem.shared.keyState.rightMousePressed)
    }

    func test_rightDragDownTheScreen_tiltsTheViewDown() throws {
        let before = target

        try canvas.rightMouseDown(with: mouse(.rightMouseDown))
        // The event's Y grows down the screen.
        try canvas.rightMouseDragged(with: mouse(.rightMouseDragged, step: (0, 60)))
        try canvas.rightMouseUp(with: mouse(.rightMouseUp))

        XCTAssertLessThan(target.y, before.y - 0.3)
    }

    func test_aKeyPressedAndReleased_whileTheRightButtonLooksAround() throws {
        try canvas.rightMouseDown(with: mouse(.rightMouseDown))
        try canvas.rightMouseDragged(with: mouse(.rightMouseDragged, step: (40, 0)))

        try canvas.keyDown(with: key(.keyDown, 13))
        XCTAssertTrue(InputSystem.shared.keyState.wPressed, "W flies while the mouse looks")

        try canvas.rightMouseDragged(with: mouse(.rightMouseDragged, step: (40, 0)))
        try canvas.keyUp(with: key(.keyUp, 13))
        XCTAssertFalse(InputSystem.shared.keyState.wPressed, "and stops when it is released")

        try canvas.rightMouseUp(with: mouse(.rightMouseUp))
    }

    func test_shiftHeldWhenTheDragBegins_pans() throws {
        let before = position, targetBefore = target

        try canvas.rightMouseDown(with: mouse(.rightMouseDown, modifiers: .shift))
        try canvas.rightMouseDragged(with: mouse(.rightMouseDragged, step: (100, 0), modifiers: .shift))
        try canvas.rightMouseUp(with: mouse(.rightMouseUp))

        XCTAssertGreaterThan(simd_length(position - before), 0.01)
        XCTAssertEqual(simd_length((position - before) - (target - targetBefore)), 0, accuracy: 1e-3)
    }

    func test_losingTheKeyboard_letsGoOfEveryKeyAndButton() throws {
        window.makeFirstResponder(canvas)
        try canvas.rightMouseDown(with: mouse(.rightMouseDown))
        try canvas.keyDown(with: key(.keyDown, 13))
        try canvas.keyDown(with: key(.keyDown, 2))
        XCTAssertTrue(InputSystem.shared.keyState.wPressed)

        window.makeFirstResponder(nil)

        XCTAssertFalse(InputSystem.shared.keyState.wPressed)
        XCTAssertFalse(InputSystem.shared.keyState.dPressed)
        XCTAssertFalse(InputSystem.shared.keyState.rightMousePressed)
        XCTAssertEqual(InputSystem.shared.cameraControlMode, .idle)
        XCTAssertFalse(InputSystem.shared.canvasOwnsKeys)
    }

    func test_optionAndADigit_pickTheTool() throws {
        let picked = expectation(forNotification: .editorSelectTool, object: nil) { note in
            note.userInfo?["tool"] as? String == TransformTool.rotate.rawValue
        }

        try canvas.keyDown(with: key(.keyDown, 20, .option))

        wait(for: [picked], timeout: 1)
        XCTAssertTrue(InputSystem.shared.keyState.altPressed, "the modifiers come with the event")
    }

    // MARK: - The left button

    func test_leftClickOnEmptySpace_clearsTheSelection() throws {
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = true
        selectionDelegate = recorder
        activeEntity = createEntity()

        try canvas.mouseDown(with: mouse(.leftMouseDown))
        try canvas.mouseUp(with: mouse(.leftMouseUp))

        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertEqual(recorder.clearCount, 1)
        XCTAssertFalse(InputSystem.shared.keyState.leftMousePressed)
    }

    func test_leftDrag_isNotAClick_andLeavesTheCameraAlone() throws {
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = true
        selectionDelegate = recorder
        let selected = createEntity()
        activeEntity = selected
        let before = position, targetBefore = target

        try canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 200, y: 150)))
        try canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 240, y: 150), step: (40, 0)))
        try canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 240, y: 150)))

        XCTAssertEqual(recorder.clearCount, 0, "a drag selects nothing and clears nothing")
        XCTAssertEqual(activeEntity, selected)
        XCTAssertEqual(simd_length(position - before), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }

    func test_aPressThatBarelyMoves_isStillAClick() throws {
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = true
        selectionDelegate = recorder
        activeEntity = createEntity()

        try canvas.mouseDown(with: mouse(.leftMouseDown, at: NSPoint(x: 200, y: 150)))
        try canvas.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: 201, y: 151), step: (1, 1)))
        try canvas.mouseUp(with: mouse(.leftMouseUp, at: NSPoint(x: 201, y: 151)))

        XCTAssertEqual(recorder.clearCount, 1)
    }

    // MARK: - A locked preview

    func test_inALockedPreview_thePointerMovesNothing() throws {
        let gameCamera = createEntity()
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        XCTAssertTrue(ViewportCameras.show(.game(gameCamera)))
        let before = position, targetBefore = target

        try canvas.rightMouseDown(with: mouse(.rightMouseDown))
        try canvas.rightMouseDragged(with: mouse(.rightMouseDragged, step: (100, 40)))
        try canvas.rightMouseUp(with: mouse(.rightMouseUp))

        XCTAssertEqual(simd_length(position - before), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(target - targetBefore), 0, accuracy: 1e-6)
    }
}

/// A mouse event that reports the step it is given: AppKit computes the step
/// of a real event itself and offers no way to set it on a made one.
private final class StepEvent: NSEvent {
    private var base: NSEvent!
    private var stepX: CGFloat = 0
    private var stepY: CGFloat = 0

    static func make(from base: NSEvent, stepX: CGFloat, stepY: CGFloat) -> NSEvent {
        let event = StepEvent()
        event.base = base
        event.stepX = stepX
        event.stepY = stepY
        return event
    }

    override var type: NSEvent.EventType {
        base.type
    }

    override var modifierFlags: NSEvent.ModifierFlags {
        base.modifierFlags
    }

    override var timestamp: TimeInterval {
        base.timestamp
    }

    override var window: NSWindow? {
        base.window
    }

    override var windowNumber: Int {
        base.windowNumber
    }

    override var locationInWindow: NSPoint {
        base.locationInWindow
    }

    override var buttonNumber: Int {
        base.buttonNumber
    }

    override var clickCount: Int {
        base.clickCount
    }

    override var deltaX: CGFloat {
        stepX
    }

    override var deltaY: CGFloat {
        stepY
    }
}
