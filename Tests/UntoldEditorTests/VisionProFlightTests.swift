//
//  VisionProFlightTests.swift
//  UntoldEditorTests
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

/// The keys fly the camera the headset rides level: ahead and aside along the
/// floor whatever the camera's tilt, Q and E straight up and down.
final class VisionProFlightTests: XCTestCase {
    private func assertEqual(_ a: simd_float3, _ b: simd_float3, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(simd_distance(a, b), 0, accuracy: 0.001, "\(message) \(a) vs \(b)", line: line)
    }

    func test_theLevelAxes_followTheCamerasYaw_notItsTilt() {
        let ahead = VisionProFlight.levelAxes(forward: simd_float3(0, 0, -1))
        assertEqual(ahead.ahead, simd_float3(0, 0, -1))
        assertEqual(ahead.right, simd_float3(1, 0, 0))

        let leftAndDown = VisionProFlight.levelAxes(forward: simd_normalize(simd_float3(-1, -1, 0)))
        assertEqual(leftAndDown.ahead, simd_float3(-1, 0, 0), "the tilt down is left out")
        assertEqual(leftAndDown.right, simd_float3(0, 0, -1))
    }

    func test_theKeys_moveAlongTheFloor_andQAndEStraightUpAndDown() {
        let tiltedDown = simd_normalize(simd_float3(0, -1, -1))
        let speed: Float = 2
        let deltaTime: Float = 0.5
        let aStep = speed * VisionProFlight.unitsPerSecondPerSpeed * deltaTime

        assertEqual(VisionProFlight.displacement(keys: .init(w: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), simd_float3(0, 0, -aStep), "W keeps the height")
        assertEqual(VisionProFlight.displacement(keys: .init(s: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), simd_float3(0, 0, aStep))
        assertEqual(VisionProFlight.displacement(keys: .init(d: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), simd_float3(aStep, 0, 0))
        assertEqual(VisionProFlight.displacement(keys: .init(a: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), simd_float3(-aStep, 0, 0))
        assertEqual(VisionProFlight.displacement(keys: .init(q: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), simd_float3(0, aStep, 0), "Q rises")
        assertEqual(VisionProFlight.displacement(keys: .init(e: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), simd_float3(0, -aStep, 0), "E sinks")
        assertEqual(VisionProFlight.displacement(keys: .init(w: true, s: true), forward: tiltedDown, speed: speed, deltaTime: deltaTime), .zero, "opposite keys cancel")
        assertEqual(VisionProFlight.displacement(keys: .init(), forward: tiltedDown, speed: speed, deltaTime: deltaTime), .zero)
    }

    func test_thePointersMovement_turnsAsALookDragDoes() {
        XCTAssertEqual(VisionProPointerCapture.turn(forPointerDelta: simd_float2(3, -2)), simd_float2(3, 2), "a move up looks up")
        XCTAssertEqual(VisionProPointerCapture.turn(forPointerDelta: simd_float2(.infinity, 0)), .zero)
    }
}
