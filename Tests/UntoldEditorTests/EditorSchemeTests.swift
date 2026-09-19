//
//  EditorSchemeTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import SwiftUI
@testable import UntoldEditor
import XCTest

/// The palette tokens carry the values of the redesign spec (`EditorUIRedesign`
/// proposal, §3). Each test resolves a token to sRGB and compares it with the hex
/// literal of the spec, so a re-theme that drifts from the mockups is caught.
final class EditorSchemeTests: XCTestCase {
    private func assertHex(
        _ color: Color,
        _ hex: UInt32,
        opacity: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("color does not resolve to sRGB", file: file, line: line)
            return
        }
        XCTAssertEqual(Int((resolved.redComponent * 255).rounded()), Int((hex >> 16) & 0xFF), "red", file: file, line: line)
        XCTAssertEqual(Int((resolved.greenComponent * 255).rounded()), Int((hex >> 8) & 0xFF), "green", file: file, line: line)
        XCTAssertEqual(Int((resolved.blueComponent * 255).rounded()), Int(hex & 0xFF), "blue", file: file, line: line)
        XCTAssertEqual(Double(resolved.alphaComponent), opacity, accuracy: 0.01, "opacity", file: file, line: line)
    }

    func test_surfaces_matchTheSpec() {
        assertHex(.editorBackground, 0x2A2C35)
        assertHex(.editorPanelBackground, 0x2E3039)
        assertHex(.editorChromeBackground, 0x30323D)
        assertHex(.editorViewportHeader, 0x2E3039)
        assertHex(.editorTabStrip, 0x242630)
        assertHex(.editorBarDark, 0x1F2028)
        assertHex(.editorControlActive, 0x3F414D)
        assertHex(.editorSurface, 0x3F414D)
    }

    func test_controlFillsAreTranslucentBlack() {
        assertHex(.editorControlFill, 0x000000, opacity: 0.28)
        assertHex(.editorHairline, 0x000000, opacity: 0.40)
        assertHex(.editorBadgeBackground, 0x000000, opacity: 0.25)
    }

    func test_accentAndText_matchTheSpec() {
        assertHex(.editorAccent, 0xF39C3D)
        assertHex(.editorAccentSoft, 0xF39C3D, opacity: 0.22)
        assertHex(.editorTextPrimary, 0xE6E7EC)
        assertHex(.editorTextSecondary, 0xC8CAD2)
        assertHex(.editorTextTertiary, 0x8A8C97)
        assertHex(.editorTextDisabled, 0x5F616C)
        assertHex(.editorTextSelected, 0xFFD9AD)
    }

    func test_status_matchTheSpec() {
        assertHex(.editorError, 0xFF7B7B)
        assertHex(.editorWarning, 0xF5C451)
        assertHex(.editorSuccess, 0x5CE08C)
        assertHex(.editorErrorText, 0xFFB3B3)
        assertHex(.editorWarningText, 0xF0D9A0)
        assertHex(.editorErrorRowBackground, 0xE5484D, opacity: 0.12)
        assertHex(.editorBadge, 0xE5484D)
    }

    func test_axesNavigationAndModes_matchTheSpec() {
        assertHex(.editorAxisX, 0xFF5A5A)
        assertHex(.editorAxisY, 0x5CE08C)
        assertHex(.editorAxisZ, 0x4C8DFF)
        assertHex(.editorNavX, 0xE0574F)
        assertHex(.editorNavY, 0x8BC34A)
        assertHex(.editorNavZ, 0x4F8DE0)
        assertHex(.editorModeObject, 0xE6E7EC)
        assertHex(.editorModeEdit, 0xF39C3D)
        assertHex(.editorModeAnimate, 0x4F8DE0)
        assertHex(.editorModePaint, 0xB53F7A)
    }

    func test_scrimIsTheSpecScrim() {
        assertHex(.editorScrim, 0x14151C, opacity: 0.55)
        assertHex(.editorShadowStrong, 0x000000, opacity: 0.50)
    }
}
