//
//  PlayModeInputTests.swift
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

/// From Play to Stop the keys and the mouse steer the camera the viewport
/// shows, and edit nothing: a click selects no entity and the gizmo moves none.
final class PlayModeInputTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false
    private var originalActiveEntity: EntityID = .invalid
    private var originalPlayback: EditorPlaybackSettings!
    private var originalController: EditorController?
    private var originalDelegate: SelectionDelegate?
    private var originalKeyState = KeyState()
    private var originalStyle: CameraNavigationStyle!

    private var playback: EditorPlaybackSettings!
    private var selectionManager: SelectionManager!
    private var editorCamera: EntityID = .invalid
    private var gameCamera: EntityID = .invalid
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
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalGameMode = gameMode
        originalActiveEntity = activeEntity
        originalPlayback = ViewportCameras.playback
        originalController = editorController
        originalDelegate = selectionDelegate
        originalKeyState = InputSystem.shared.keyState
        originalStyle = EditorNavigationSettings.shared.style

        scene = Scene()
        gameMode = false
        activeEntity = .invalid
        InputSystem.shared.keyState = KeyState()
        playback = EditorPlaybackSettings(defaults: nil)
        ViewportCameras.playback = playback
        selectionManager = SelectionManager()
        editorController = EditorController(selectionManager: selectionManager)
        editorController?.isEnabled = true

        editorCamera = findSceneCamera()
        cameraLookAt(entityId: editorCamera, eye: simd_float3(0, 2, 3), target: .zero, up: simd_float3(0, 1, 0))
        gameCamera = createEntity()
        setEntityName(entityId: gameCamera, name: "Game Camera")
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        cameraLookAt(entityId: gameCamera, eye: simd_float3(4, 1, 6), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = editorCamera
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func tearDown() {
        InputSystem.shared.canvasLostTheKeyboard()
        InputSystem.shared.cameraControlMode = .idle
        InputSystem.shared.keyState = originalKeyState
        EditorNavigationSettings.shared.style = originalStyle
        ViewportCameras.playback = originalPlayback
        editorController = originalController
        selectionDelegate = originalDelegate
        activeEntity = originalActiveEntity
        gameMode = originalGameMode
        CameraSystem.shared.activeCamera = originalActiveCamera
        scene = originalScene
        originalScene = nil
        selectionManager = nil
        playback = nil
        view = nil
        super.tearDown()
    }

    /// Play on the game's camera, as the toolbar's button starts it.
    private func play(onTheEditorCamera: Bool = false) {
        gameMode = true
        playback.isSessionActive = true
        CameraSystem.shared.activeCamera = onTheEditorCamera ? editorCamera : gameCamera
    }

    private func place(of camera: EntityID) -> CameraPlacement? {
        CameraPlacement.capture(of: camera)
    }

    private func position(of camera: EntityID) -> simd_float3 {
        scene.get(component: CameraComponent.self, for: camera)?.localPosition ?? .zero
    }

    private func rightDrag(by delta: simd_float2) {
        InputSystem.shared.beginCameraDrag()
        InputSystem.shared.moveCameraDrag(by: delta)
        InputSystem.shared.endCameraDrag()
    }

    // MARK: - Which camera is steered

    func test_whileEditing_theEditorsCameraIsSteered() {
        XCTAssertEqual(ViewportCameras.steered, editorCamera)
        XCTAssertFalse(ViewportCameras.isPlaying)
    }

    func test_overALockedPreview_noCameraIsSteered() {
        CameraSystem.shared.activeCamera = gameCamera

        XCTAssertTrue(ViewportCameras.isLockedPreview)
        XCTAssertNil(ViewportCameras.steered)
    }

    func test_whilePlaying_theGamesCameraIsSteered() {
        play()

        XCTAssertEqual(ViewportCameras.steered, gameCamera)
        XCTAssertFalse(ViewportCameras.isLockedPreview, "a play session is no preview")
    }

    func test_whilePlaying_withTheSteeringOff_theGameSteersItsCameraAlone() {
        playback.steersCameraWhilePlaying = false
        play()

        XCTAssertNil(ViewportCameras.steered)
    }

    func test_whilePlayingOnTheEditorsCamera_thatOneIsSteered() {
        play(onTheEditorCamera: true)

        XCTAssertEqual(ViewportCameras.steered, editorCamera)
    }

    func test_aPausedSession_isStillPlay() {
        play()
        gameMode = false

        XCTAssertTrue(ViewportCameras.isPlaying)
        XCTAssertFalse(ViewportCameras.isLockedPreview)
        XCTAssertEqual(ViewportCameras.steered, gameCamera)
    }

    func test_theSteering_isOnUntilItIsSwitchedOff_andTheChoiceIsKept() throws {
        let suite = "PlayModeInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = EditorPlaybackSettings(defaults: defaults)
        XCTAssertTrue(settings.steersCameraWhilePlaying)

        settings.steersCameraWhilePlaying = false
        XCTAssertFalse(EditorPlaybackSettings(defaults: defaults).steersCameraWhilePlaying)
    }

    // MARK: - The keys and the mouse while playing

    func test_aRightDrag_looksAroundWithTheGamesCamera_andLeavesTheEditorsAlone() throws {
        play()
        let editorBefore = try XCTUnwrap(place(of: editorCamera))
        let gameBefore = try XCTUnwrap(place(of: gameCamera))

        rightDrag(by: simd_float2(100, 0))

        let gameAfter = try XCTUnwrap(place(of: gameCamera))
        XCTAssertEqual(place(of: editorCamera), editorBefore)
        XCTAssertEqual(simd_length(gameAfter.position - gameBefore.position), 0, accuracy: 1e-4, "looking around moves no camera")
        XCTAssertGreaterThan(simd_length(gameAfter.target - gameBefore.target), 0.01, "the view turned")
    }

    func test_aRightDragWithShift_pansTheGamesCamera() {
        play()
        InputSystem.shared.keyState.shiftPressed = true
        let before = position(of: gameCamera)

        rightDrag(by: simd_float2(100, 0))

        XCTAssertGreaterThan(simd_length(position(of: gameCamera) - before), 0.01)
    }

    func test_theWheel_steersTheGamesCamera_andLeavesTheEditorsAlone() throws {
        play()
        EditorNavigationSettings.shared.style = .blender
        let editorBefore = try XCTUnwrap(place(of: editorCamera))
        let before = position(of: gameCamera)

        InputSystem.shared.reanchorSceneCameraTarget()
        InputSystem.shared.orbitSceneCamera(byScroll: simd_float2(30, 0), precise: true)

        XCTAssertGreaterThan(simd_length(position(of: gameCamera) - before), 0.01)
        XCTAssertEqual(place(of: editorCamera), editorBefore)
    }

    func test_withTheSteeringOff_theMouseMovesNoCamera() throws {
        playback.steersCameraWhilePlaying = false
        play()
        let editorBefore = try XCTUnwrap(place(of: editorCamera))
        let gameBefore = try XCTUnwrap(place(of: gameCamera))

        rightDrag(by: simd_float2(100, 40))
        InputSystem.shared.orbitSceneCamera(byScroll: simd_float2(30, 0), precise: true)
        InputSystem.shared.panSceneCamera(byScroll: simd_float2(30, 10), precise: true)

        XCTAssertEqual(place(of: editorCamera), editorBefore)
        XCTAssertEqual(place(of: gameCamera), gameBefore)
    }

    func test_theButtonsAndTheKeys_stillReachTheGame() throws {
        playback.steersCameraWhilePlaying = false
        play()

        let press = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        InputSystem.shared.canvasRightMouseDown(press)
        XCTAssertTrue(InputSystem.shared.keyState.rightMousePressed, "a script reads the button")

        // The pointer counts as over the canvas, where the keys are the scene's.
        InputSystem.shared.pointerIsOverViewportControl(true)
        defer { InputSystem.shared.pointerIsOverViewportControl(false) }
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13
        ))
        XCTAssertTrue(InputSystem.shared.canvasKeyDown(key))
        XCTAssertTrue(InputSystem.shared.keyState.wPressed, "and the keys")
    }

    // MARK: - Nothing is edited while playing

    private func click(at location: NSPoint) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            if type == .leftMouseDown {
                InputSystem.shared.canvasLeftMouseDown(event, at: location)
            } else {
                InputSystem.shared.canvasLeftMouseUp(event, at: location, in: view)
            }
        }
    }

    func test_aClick_selectsNothing_andKeepsTheSelection_whilePlaying() throws {
        let crate = createEntity()
        setEntityName(entityId: crate, name: "Crate")
        registerTransformComponent(entityId: crate)
        selectionManager.selectedEntity = crate
        activeEntity = crate
        play()

        // Over empty space, where a click while editing clears the selection.
        try click(at: NSPoint(x: 5, y: 5))

        XCTAssertEqual(activeEntity, crate)
        XCTAssertEqual(selectionManager.selectedEntity, crate)
    }

    func test_aClick_selectsNothing_whileTheSessionIsPaused() throws {
        let crate = createEntity()
        registerTransformComponent(entityId: crate)
        activeEntity = crate
        play()
        gameMode = false

        try click(at: NSPoint(x: 5, y: 5))

        XCTAssertEqual(activeEntity, crate)
    }

    func test_aClickOverEmptySpace_clearsTheSelection_whileEditing() throws {
        let crate = createEntity()
        registerTransformComponent(entityId: crate)
        activeEntity = crate

        try click(at: NSPoint(x: 5, y: 5))

        XCTAssertEqual(activeEntity, .invalid, "the same click, while editing")
    }

    func test_aLeftDrag_takesNoGizmoHandle_whilePlaying() {
        let crate = createEntity()
        registerTransformComponent(entityId: crate)
        activeEntity = crate
        createGizmo(mode: .translate)
        defer { removeGizmo() }
        play()
        let before = getLocalPosition(entityId: crate)

        let start = NSPoint(x: 200, y: 150)
        InputSystem.shared.beginObjectDrag(at: start, in: view)
        InputSystem.shared.continueObjectDrag(to: NSPoint(x: 260, y: 150), translation: NSPoint(x: 60, y: 0), in: view)
        InputSystem.shared.endObjectDrag()

        XCTAssertEqual(activeHitGizmoEntity, .invalid)
        XCTAssertEqual(getLocalPosition(entityId: crate), before)
    }

    func test_aLeftDrag_stillTellsTheGameHowFarItWent() {
        play()

        let start = NSPoint(x: 200, y: 150)
        InputSystem.shared.beginObjectDrag(at: start, in: view)
        InputSystem.shared.continueObjectDrag(to: NSPoint(x: 260, y: 150), translation: NSPoint(x: 60, y: 0), in: view)

        XCTAssertNotEqual(InputSystem.shared.panDelta, .zero)
        InputSystem.shared.endObjectDrag()
    }

    func test_theToolShortcuts_areTheGames_fromPlayToStop() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0,
            context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19
        ))
        XCTAssertEqual(InputSystem.shared.toolShortcut(for: event), .move)

        play()
        XCTAssertNil(InputSystem.shared.toolShortcut(for: event))

        gameMode = false
        XCTAssertNil(InputSystem.shared.toolShortcut(for: event), "paused is still play")
    }
}
