//
//  ToolShortcutTests.swift
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

/// ⌥1 to ⌥4 pick the tools; the letters belong to the camera.
final class ToolShortcutTests: XCTestCase {
    private var originalGameMode = false

    override func setUp() {
        super.setUp()
        originalGameMode = gameMode
        gameMode = false
    }

    override func tearDown() {
        gameMode = originalGameMode
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

    func test_optionWithADigit_picksTheTool() throws {
        XCTAssertEqual(try InputSystem.shared.toolShortcut(for: keyDown(18, .option)), .select)
        XCTAssertEqual(try InputSystem.shared.toolShortcut(for: keyDown(19, .option)), .move)
        XCTAssertEqual(try InputSystem.shared.toolShortcut(for: keyDown(20, .option)), .rotate)
        XCTAssertEqual(try InputSystem.shared.toolShortcut(for: keyDown(21, .option)), .scale)
    }

    func test_aDigitAlone_picksNothing() throws {
        for keyCode: UInt16 in 18 ... 21 {
            XCTAssertNil(try InputSystem.shared.toolShortcut(for: keyDown(keyCode)))
            XCTAssertNil(try InputSystem.shared.toolShortcut(for: keyDown(keyCode, .shift)))
        }
    }

    func test_theLetters_pickNothing_evenWithOption() throws {
        // W, A, S, D, Q, E and R by their macOS virtual key codes.
        for keyCode: UInt16 in [13, 0, 1, 2, 12, 14, 15] {
            XCTAssertNil(try InputSystem.shared.toolShortcut(for: keyDown(keyCode)))
            XCTAssertNil(try InputSystem.shared.toolShortcut(for: keyDown(keyCode, .option)))
        }
    }

    func test_whileTheGameRuns_theKeysAreTheGames() throws {
        gameMode = true
        XCTAssertNil(try InputSystem.shared.toolShortcut(for: keyDown(19, .option)))
    }
}
