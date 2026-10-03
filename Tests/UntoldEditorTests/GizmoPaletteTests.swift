//
//  GizmoPaletteTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
@testable import UntoldEditor
import XCTest

/// The gizmo's colours are the spec's, handed to the engine as light.
final class GizmoPaletteTests: XCTestCase {
    /// The sRGB curve the other way, from light to what the screen shows.
    private func display(fromLinear value: Float) -> Float {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private func assertShows(_ color: simd_float4, as hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Int((display(fromLinear: color.x) * 255).rounded()), Int((hex >> 16) & 0xFF), "red", file: file, line: line)
        XCTAssertEqual(Int((display(fromLinear: color.y) * 255).rounded()), Int((hex >> 8) & 0xFF), "green", file: file, line: line)
        XCTAssertEqual(Int((display(fromLinear: color.z) * 255).rounded()), Int(hex & 0xFF), "blue", file: file, line: line)
        XCTAssertEqual(color.w, 1, file: file, line: line)
    }

    func test_theColours_areTheSpecsOnTheScreen() {
        assertShows(GizmoPalette.x, as: 0xFF5A5A)
        assertShows(GizmoPalette.y, as: 0x5CE08C)
        assertShows(GizmoPalette.z, as: 0x4C8DFF)
        assertShows(GizmoPalette.center, as: 0xFFFFFF)
    }

    func test_theCurve_holdsAtItsEnds() {
        XCTAssertEqual(GizmoPalette.linear(fromDisplay: 0), 0)
        XCTAssertEqual(GizmoPalette.linear(fromDisplay: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(GizmoPalette.linear(fromDisplay: 0.5), 0.2140, accuracy: 0.0005)
    }

    func test_everyColour_isBrightEnoughForTheEngineToDrawIt() {
        for color in [GizmoPalette.x, GizmoPalette.y, GizmoPalette.z, GizmoPalette.center] {
            XCTAssertGreaterThan(GizmoPalette.engineLuminance(of: color), GizmoPalette.engineLuminanceFloor * 1.5)
        }
    }
}
