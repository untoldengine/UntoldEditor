//
//  VisionProPlacementTests.swift
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
@testable import UntoldEngine
import XCTest

/// Where the headset stands in the scene: at the editor's camera when the
/// preview begins, and from there wherever it walks and turns.
final class VisionProPlacementTests: XCTestCase {
    private func point(_ matrix: simd_float4x4, _ p: simd_float3) -> simd_float3 {
        let moved = simd_mul(matrix, simd_float4(p, 1))
        return simd_float3(moved.x, moved.y, moved.z)
    }

    private func direction(_ matrix: simd_float4x4, _ d: simd_float3) -> simd_float3 {
        let turned = simd_mul(matrix, simd_float4(d, 0))
        return simd_float3(turned.x, turned.y, turned.z)
    }

    private func assertNearlyEqual(_ lhs: simd_float3, _ rhs: simd_float3, accuracy: Float = 0.001, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, message, file: file, line: line)
    }

    /// A pose of the headset: where it is and the turn about the vertical
    /// axis, with a tilt down when asked.
    private func pose(at position: simd_float3, yaw: Float, pitch: Float = 0) -> simd_float4x4 {
        let turn = simd_mul(simd_quatf(angle: yaw, axis: simd_float3(0, 1, 0)), simd_quatf(angle: pitch, axis: simd_float3(1, 0, 0)))
        return simd_mul(matrix4x4Translation(position.x, position.y, position.z), simd_float4x4(turn))
    }

    func test_theLevelYaw_isZeroLookingForward_andAQuarterTurnLookingLeft() {
        XCTAssertEqual(VisionProPlacement.levelYaw(of: simd_float3(0, 0, -1)), 0, accuracy: 0.0001)
        XCTAssertEqual(VisionProPlacement.levelYaw(of: simd_float3(-1, 0, 0)), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(VisionProPlacement.levelYaw(of: simd_float3(1, 0, 0)), -.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(VisionProPlacement.levelYaw(of: simd_float3(-1, -3, -1)), .pi / 4, accuracy: 0.0001, "the tilt does not count")
        XCTAssertEqual(VisionProPlacement.levelYaw(of: simd_float3(0, -1, 0)), 0, "straight down has no yaw")
    }

    func test_theHeadsetBegins_whereTheCameraStood_facingItsWay() {
        let eye = simd_float3(3, 1.6, -2)
        let placed = VisionProPlacement.sceneFromOrigin(
            cameraEye: eye,
            cameraForward: simd_float3(1, 0, 0),
            originFromDevice: pose(at: simd_float3(0, 1.5, 0), yaw: 0)
        )

        assertNearlyEqual(point(placed, simd_float3(0, 1.5, 0)), eye, "the headset stands at the camera's eye")
        assertNearlyEqual(direction(placed, simd_float3(0, 0, -1)), simd_float3(1, 0, 0), "and looks where it looked")
        assertNearlyEqual(direction(placed, simd_float3(0, 1, 0)), simd_float3(0, 1, 0), "the floor stays level")
    }

    func test_howTheHeadsetWasTurnedAtTheStart_doesNotCount_butItsTiltDoes() {
        let placed = VisionProPlacement.sceneFromOrigin(
            cameraEye: .zero,
            cameraForward: simd_float3(0, 0, -1),
            originFromDevice: pose(at: simd_float3(2, 1.5, 1), yaw: .pi / 2, pitch: -0.3)
        )
        let start = pose(at: simd_float3(2, 1.5, 1), yaw: .pi / 2, pitch: -0.3)
        let lookingAt = direction(simd_mul(placed, start), simd_float3(0, 0, -1))

        assertNearlyEqual(point(placed, simd_float3(2, 1.5, 1)), .zero)
        XCTAssertEqual(lookingAt.x, 0, accuracy: 0.001, "the turn to the left at the start is taken out")
        XCTAssertEqual(lookingAt.y, sin(-0.3), accuracy: 0.001, "the tilt down stays")
        XCTAssertLessThan(lookingAt.z, 0, "it looks the camera's way")
    }

    func test_walkingForward_goesTheCamerasWay_andTurningTurnsTheView() {
        let placed = VisionProPlacement.sceneFromOrigin(
            cameraEye: simd_float3(10, 1.6, 10),
            cameraForward: simd_float3(-1, 0, 0),
            originFromDevice: pose(at: simd_float3(0, 1.5, 0), yaw: 0)
        )

        // One step along the headset's own forward, which was -Z.
        let stepped = pose(at: simd_float3(0, 1.5, -1), yaw: 0)
        assertNearlyEqual(point(simd_mul(placed, stepped), .zero), simd_float3(9, 1.6, 10), "a metre along the camera's way")

        // A quarter turn to the left: the view turns from -X to +Z.
        let turned = pose(at: simd_float3(0, 1.5, 0), yaw: .pi / 2)
        assertNearlyEqual(direction(simd_mul(placed, turned), simd_float3(0, 0, -1)), simd_float3(0, 0, 1))
    }

    func test_theMirrorFitsTheEye_keepingItsProportions() {
        XCTAssertEqual(VisionProMirror.fit(eye: CGSize(width: 200, height: 100), in: CGSize(width: 100, height: 100)), simd_float2(1, 0.5))
        XCTAssertEqual(VisionProMirror.fit(eye: CGSize(width: 100, height: 200), in: CGSize(width: 100, height: 100)), simd_float2(0.5, 1))
        XCTAssertEqual(VisionProMirror.fit(eye: CGSize(width: 400, height: 300), in: CGSize(width: 800, height: 600)), simd_float2(1, 1))
        XCTAssertEqual(VisionProMirror.fit(eye: .zero, in: CGSize(width: 100, height: 100)), simd_float2(1, 1))
    }
}
