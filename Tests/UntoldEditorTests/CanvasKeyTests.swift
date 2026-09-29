//
//  CanvasKeyTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The keys the canvas receives: which of them are the scene's, what ⌘ does
/// during a camera drag, and a key whose release never arrived.
final class CanvasKeyTests: XCTestCase {
    private var originalGameMode = false
    private var originalKeyState = KeyState()
    private var originalPhysicalKeyState: ((UInt16) -> Bool)!
    private var originalTrust = false

    override func setUp() {
        super.setUp()
        originalGameMode = gameMode
        originalKeyState = InputSystem.shared.keyState
        originalPhysicalKeyState = InputSystem.shared.physicalKeyState
        originalTrust = InputSystem.shared.isPhysicalKeyStateTrusted
        gameMode = false
        InputSystem.shared.keyState = KeyState()
        InputSystem.shared.physicalKeyState = { _ in false }
        InputSystem.shared.isPhysicalKeyStateTrusted = false
    }

    override func tearDown() {
        gameMode = originalGameMode
        InputSystem.shared.keyState = originalKeyState
        InputSystem.shared.physicalKeyState = originalPhysicalKeyState
        InputSystem.shared.isPhysicalKeyStateTrusted = originalTrust
        super.tearDown()
    }

    private func keyDown(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    // MARK: - Keys during a drag

    func test_aButtonHeldOnTheCanvas_keepsTheKeys_whereverThePointerWent() throws {
        let savedScene = scene, savedCamera = CameraSystem.shared.activeCamera
        defer {
            InputSystem.shared.canvasLostTheKeyboard()
            scene = savedScene
            CameraSystem.shared.activeCamera = savedCamera
        }
        scene = Scene()
        CameraSystem.shared.activeCamera = findSceneCamera()
        // No key window here, so the pointer counts as off the canvas.
        XCTAssertFalse(InputSystem.shared.canvasOwnsKeys)

        InputSystem.shared.beginCameraDrag()
        XCTAssertTrue(InputSystem.shared.canvasOwnsKeys, "looking around carries the pointer over the panels")
        InputSystem.shared.endCameraDrag()
        XCTAssertFalse(InputSystem.shared.canvasOwnsKeys)

        let press = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        InputSystem.shared.canvasLeftMouseDown(press, at: NSPoint(x: 10, y: 10))
        XCTAssertTrue(InputSystem.shared.canvasOwnsKeys, "dragging a gizmo handle keeps them too")
    }

    func test_commandWithAFlyKey_duringACameraDrag_neverReachesTheMenu() throws {
        InputSystem.shared.keyState.rightMousePressed = true
        // W, A, S, D, Q and E: with ⌘ they would close, select all, save, quit...
        for keyCode: UInt16 in [13, 0, 1, 2, 12, 14] {
            XCTAssertTrue(try InputSystem.shared.takesCommandKeyDuringCameraDrag(keyDown(keyCode, .command)))
            XCTAssertFalse(try InputSystem.shared.takesCommandKeyDuringCameraDrag(keyDown(keyCode)), "without ⌘ the key goes the usual way")
        }
        // ⌘Z stays the undo it is.
        XCTAssertFalse(try InputSystem.shared.takesCommandKeyDuringCameraDrag(keyDown(6, .command)))
        // The keyboard's own state could not be read, so nothing was pressed:
        // macOS sends no key up while ⌘ is down.
        XCTAssertFalse(InputSystem.shared.keyState.wPressed)
        XCTAssertFalse(InputSystem.shared.keyState.qPressed)
    }

    func test_commandWithAFlyKey_flies_whenTheKeyboardCanBeRead() throws {
        InputSystem.shared.keyState.rightMousePressed = true
        InputSystem.shared.physicalKeyState = { $0 == 13 }

        XCTAssertTrue(try InputSystem.shared.takesCommandKeyDuringCameraDrag(keyDown(13, .command)))

        XCTAssertTrue(InputSystem.shared.isPhysicalKeyStateTrusted)
        XCTAssertTrue(InputSystem.shared.keyState.wPressed)
    }

    func test_commandShortcuts_areUntouched_withoutACameraDrag() throws {
        InputSystem.shared.keyState.rightMousePressed = false
        for keyCode: UInt16 in [13, 0, 1, 2, 12, 14] {
            XCTAssertFalse(try InputSystem.shared.takesCommandKeyDuringCameraDrag(keyDown(keyCode, .command)))
        }
    }

    // MARK: - A key released without its key-up event

    func test_aFlyKeyTheKeyboardLetGo_isReleased() {
        InputSystem.shared.isPhysicalKeyStateTrusted = true
        InputSystem.shared.keyState.wPressed = true
        InputSystem.shared.keyState.dPressed = true
        // D is still held; W was released and its key-up never came.
        InputSystem.shared.physicalKeyState = { $0 == 2 }

        InputSystem.shared.releaseFlyKeysTheKeyboardLetGo()

        XCTAssertFalse(InputSystem.shared.keyState.wPressed)
        XCTAssertTrue(InputSystem.shared.keyState.dPressed)
    }

    func test_noKeyIsLetGo_untilTheKeyboardsStateHasAgreedWithAnEvent() {
        InputSystem.shared.keyState.wPressed = true
        InputSystem.shared.physicalKeyState = { _ in false }

        InputSystem.shared.releaseFlyKeysTheKeyboardLetGo()
        XCTAssertTrue(InputSystem.shared.keyState.wPressed, "a state that cannot be read releases nothing")

        // A key-down the keyboard confirms makes its state trusted.
        InputSystem.shared.physicalKeyState = { $0 == 13 }
        InputSystem.shared.noteKeyDown(13)
        XCTAssertTrue(InputSystem.shared.isPhysicalKeyStateTrusted)

        InputSystem.shared.physicalKeyState = { _ in false }
        InputSystem.shared.releaseFlyKeysTheKeyboardLetGo()
        XCTAssertFalse(InputSystem.shared.keyState.wPressed)
    }

    func test_onlyAFlyKeyTheKeyboardConfirms_makesItsStateTrusted() {
        InputSystem.shared.physicalKeyState = { _ in true }
        InputSystem.shared.noteKeyDown(3) // F is a key, not one that flies
        XCTAssertFalse(InputSystem.shared.isPhysicalKeyStateTrusted)

        InputSystem.shared.physicalKeyState = { _ in false }
        InputSystem.shared.noteKeyDown(13) // an event the keyboard does not confirm
        XCTAssertFalse(InputSystem.shared.isPhysicalKeyStateTrusted)
    }
}
