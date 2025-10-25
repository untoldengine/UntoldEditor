//
//  InputSystemCoreTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

@testable import UntoldEngine
import XCTest

final class InputSystemCoreTests: XCTestCase {
    private final class DelegateSpy: InputSystemDelegate {
        var updateCount = 0
        func didUpdateKeyState() { updateCount += 1 }
    }

    private var originalDelegate: InputSystemDelegate?
    private var originalKeyState: KeyState!

    override func setUp() {
        super.setUp()
        // Snapshot and reset the singleton’s mutable state
        originalDelegate = InputSystem.shared.delegate
        originalKeyState = InputSystem.shared.keyState
        InputSystem.shared.delegate = nil
        InputSystem.shared.keyState = KeyState()
    }

    override func tearDown() {
        // Restore
        InputSystem.shared.delegate = originalDelegate
        InputSystem.shared.keyState = originalKeyState
        super.tearDown()
    }

    func test_keyPressed_setsCorrespondingFlags() {
        let input = InputSystem.shared

        input.keyPressed(input.kVK_ANSI_W)
        XCTAssertTrue(input.keyState.wPressed)

        input.keyPressed(input.kVK_ANSI_A)
        XCTAssertTrue(input.keyState.aPressed)

        input.keyPressed(input.kVK_ANSI_S)
        XCTAssertTrue(input.keyState.sPressed)

        input.keyPressed(input.kVK_ANSI_D)
        XCTAssertTrue(input.keyState.dPressed)

        input.keyPressed(input.kVK_ANSI_Q)
        XCTAssertTrue(input.keyState.qPressed)

        input.keyPressed(input.kVK_ANSI_E)
        XCTAssertTrue(input.keyState.ePressed)

        input.keyPressed(input.kVK_ANSI_Space)
        XCTAssertTrue(input.keyState.spacePressed)
    }

    func test_keyReleased_clearsCorrespondingFlags() {
        let input = InputSystem.shared

        // Prime as pressed
        input.keyState = .init(wPressed: true, aPressed: true, sPressed: true, dPressed: true,
                               qPressed: true, ePressed: true, spacePressed: true,
                               shiftPressed: false, ctrlPressed: false, altPressed: false,
                               leftMousePressed: false, rightMousePressed: false, middleMousePressed: false)

        input.keyReleased(input.kVK_ANSI_W)
        XCTAssertFalse(input.keyState.wPressed)

        input.keyReleased(input.kVK_ANSI_A)
        XCTAssertFalse(input.keyState.aPressed)

        input.keyReleased(input.kVK_ANSI_S)
        XCTAssertFalse(input.keyState.sPressed)

        input.keyReleased(input.kVK_ANSI_D)
        XCTAssertFalse(input.keyState.dPressed)

        input.keyReleased(input.kVK_ANSI_Q)
        XCTAssertFalse(input.keyState.qPressed)

        input.keyReleased(input.kVK_ANSI_E)
        XCTAssertFalse(input.keyState.ePressed)

        input.keyReleased(input.kVK_ANSI_Space)
        XCTAssertFalse(input.keyState.spacePressed)
    }

    func test_delegate_isCalledOnKeyChanges() {
        let input = InputSystem.shared
        let spy = DelegateSpy()
        input.delegate = spy

        input.keyPressed(input.kVK_ANSI_W)
        input.keyReleased(input.kVK_ANSI_W)

        XCTAssertEqual(spy.updateCount, 2, "Delegate should be notified on both press and release.")
    }

    func test_multipleKeyPresses_toggleIndependentFlags() {
        let input = InputSystem.shared

        input.keyPressed(input.kVK_ANSI_W)
        input.keyPressed(input.kVK_ANSI_D)
        XCTAssertTrue(input.keyState.wPressed)
        XCTAssertTrue(input.keyState.dPressed)
        XCTAssertFalse(input.keyState.aPressed)
        XCTAssertFalse(input.keyState.sPressed)

        input.keyReleased(input.kVK_ANSI_W)
        XCTAssertFalse(input.keyState.wPressed)
        XCTAssertTrue(input.keyState.dPressed)
    }
}
