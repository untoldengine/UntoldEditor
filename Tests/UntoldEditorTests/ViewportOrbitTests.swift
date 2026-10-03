//
//  ViewportOrbitTests.swift
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

/// The editor's orbit step: the engine's feel away from the poles, and a
/// camera that stands straight over or under its pivot, as the Top and Bottom
/// presets leave it, orbits on instead of becoming NaN.
final class ViewportOrbitTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false
    private var originalSpeed = 1

    override func setUp() {
        super.setUp()
        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalGameMode = gameMode
        originalSpeed = EditorViewportSettings.shared.cameraSpeed
        scene = Scene()
        gameMode = false
        CameraSystem.shared.activeCamera = nil
        EditorViewportSettings.shared.cameraSpeed = 1
    }

    override func tearDown() {
        EditorViewportSettings.shared.cameraSpeed = originalSpeed
        gameMode = originalGameMode
        CameraSystem.shared.activeCamera = originalActiveCamera
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    private func isFinite(_ v: simd_float3) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    private func assertEqual(_ a: simd_float3, _ b: simd_float3, accuracy: Float, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: - The step itself

    func test_awayFromThePoles_theStepIsTheEnginesOrbit() throws {
        // The engine's orbitAround on a camera, from the same state.
        let camera = findSceneCamera()
        let pivot = simd_float3(2, 0, -5)
        for (eye, angles) in [
            (simd_float3(2, 3, 3), simd_float2(0.3, 0)),
            (simd_float3(2, 3, 3), simd_float2(0, -0.2)),
            (simd_float3(-4, 1, -5), simd_float2(-0.25, 0.15)),
            (simd_float3(2, -2, -1), simd_float2(0.1, 0.1)),
        ] {
            cameraLookAt(entityId: camera, eye: eye, target: pivot, up: simd_float3(0, 1, 0))
            setOrbitOffset(entityId: camera, uTargetOffset: simd_length(eye - pivot))
            let cameraUp = try XCTUnwrap(scene.get(component: CameraComponent.self, for: camera)).yAxis

            orbitAround(entityId: camera, uPosition: angles)
            let byTheEngine = try XCTUnwrap(scene.get(component: CameraComponent.self, for: camera))

            let step = try XCTUnwrap(InputSystem.orbitStep(eye: eye, pivot: pivot, cameraUp: cameraUp, angles: angles))
            assertEqual(step.eye, byTheEngine.localPosition, accuracy: 1e-4, "eye for \(eye) by \(angles)")
            // The same view: looking at the pivot with the same up gives the same frame.
            cameraLookAt(entityId: camera, eye: step.eye, target: pivot, up: step.up)
            let byTheStep = try XCTUnwrap(scene.get(component: CameraComponent.self, for: camera))
            assertEqual(byTheStep.xAxis, byTheEngine.xAxis, accuracy: 1e-4, "right axis for \(eye) by \(angles)")
            assertEqual(byTheStep.yAxis, byTheEngine.yAxis, accuracy: 1e-4, "up axis for \(eye) by \(angles)")
        }
    }

    func test_straightOverThePivot_aTurnSpinsAndATiltLeavesThePole() throws {
        // The Top preset: the eye over the pivot, the top of the view towards -Z.
        let pivot = simd_float3(5, 0, -20)
        let eye = pivot + simd_float3(0, 8, 0)
        let cameraUp = simd_float3(0, 0, -1)

        let turn = try XCTUnwrap(InputSystem.orbitStep(eye: eye, pivot: pivot, cameraUp: cameraUp, angles: simd_float2(0.5, 0)))
        XCTAssertTrue(isFinite(turn.eye) && isFinite(turn.up))
        assertEqual(turn.eye, eye, accuracy: 1e-4, "a turn about the vertical leaves the eye where it stands")
        XCTAssertEqual(simd_dot(turn.up, simd_float3(0, 1, 0)), 0, accuracy: 1e-4, "and spins the view: the up stays horizontal")
        XCTAssertNotEqual(turn.up.x, 0, accuracy: 0.1, "turned by half a radian")

        let tilt = try XCTUnwrap(InputSystem.orbitStep(eye: eye, pivot: pivot, cameraUp: cameraUp, angles: simd_float2(0, 0.3)))
        XCTAssertTrue(isFinite(tilt.eye) && isFinite(tilt.up))
        XCTAssertEqual(simd_length(tilt.eye - pivot), 8, accuracy: 1e-3, "the distance is kept")
        XCTAssertLessThan(tilt.eye.y - pivot.y, 8 - 0.3, "and the eye came down off the pole")
        XCTAssertEqual(tilt.up, simd_float3(0, 1, 0), "away from the pole the world's up levels the view")
    }

    func test_theTilt_stopsAtThePole_andDoesNotPassOver() throws {
        let pivot = simd_float3(0, 0, 0)
        let eye = simd_float3(0, sin(Float(1.4)), cos(Float(1.4))) * 6 // 80° up, in front
        let camera = findSceneCamera()
        cameraLookAt(entityId: camera, eye: eye, target: pivot, up: simd_float3(0, 1, 0))
        let cameraUp = try XCTUnwrap(scene.get(component: CameraComponent.self, for: camera)).yAxis

        // A tilt of 0.6 rad upwards, where only 0.17 rad are left to the pole.
        let step = try XCTUnwrap(InputSystem.orbitStep(eye: eye, pivot: pivot, cameraUp: cameraUp, angles: simd_float2(0, -0.6)))
        XCTAssertTrue(isFinite(step.eye) && isFinite(step.up))
        XCTAssertEqual(step.eye.y, 6, accuracy: 1e-3, "the eye reached the pole")
        XCTAssertEqual(step.eye.z, 0, accuracy: 1e-3, "and not the far side")
        XCTAssertEqual(simd_dot(step.up, simd_float3(0, 1, 0)), 0, accuracy: 1e-3, "with a horizontal up to look down with")
        XCTAssertLessThan(step.up.z, -0.9, "the top of the view still towards -Z, as it was")
    }

    func test_theStep_refusesWhatItCannotOrbit() {
        XCTAssertNil(InputSystem.orbitStep(eye: .zero, pivot: .zero, cameraUp: simd_float3(0, 1, 0), angles: simd_float2(0.1, 0)), "an eye on the pivot")
        XCTAssertNil(InputSystem.orbitStep(eye: simd_float3(1, 0, 0), pivot: .zero, cameraUp: .zero, angles: simd_float2(0.1, 0)), "no up to work with")
        XCTAssertNil(InputSystem.orbitStep(eye: simd_float3(1, 0, 0), pivot: .zero, cameraUp: simd_float3(0, 1, 0), angles: simd_float2(.nan, 0)), "a step that is no number")
    }

    // MARK: - In the editor

    func test_afterTheTopView_theCameraStillOrbits() {
        let camera = findSceneCamera()
        CameraSystem.shared.activeCamera = camera
        let pivot = simd_float3(5, 0, -20)
        cameraLookAt(entityId: camera, eye: pivot + simd_float3(0, 3, 8), target: pivot, up: simd_float3(0, 1, 0))

        ViewportProjection.top.applyToSceneCamera()
        InputSystem.shared.beginCameraDrag(as: .orbit)
        InputSystem.shared.moveCameraDrag(by: simd_float2(0, -12))
        InputSystem.shared.moveCameraDrag(by: simd_float2(-10, 0))
        InputSystem.shared.endCameraDrag()

        guard let component = scene.get(component: CameraComponent.self, for: camera) else {
            return XCTFail("no camera")
        }
        XCTAssertTrue(isFinite(component.localPosition), "the camera is still somewhere")
        XCTAssertTrue(component.rotation.real.isFinite && isFinite(component.rotation.imag), "and still turned")
        XCTAssertEqual(simd_length(component.localPosition - pivot), simd_length(simd_float3(0, 3, 8)), accuracy: 1e-2, "at its distance from the pivot")
        XCTAssertLessThan(component.localPosition.y, pivot.y + simd_length(simd_float3(0, 3, 8)) - 0.01, "and off the pole")

        ViewportProjection.bottom.applyToSceneCamera()
        InputSystem.shared.orbitSceneCamera(byScroll: simd_float2(-3, 0), precise: false)
        InputSystem.shared.orbitSceneCamera(byScroll: simd_float2(0, 3), precise: false)
        XCTAssertTrue(isFinite(getCameraEye(entityId: camera)), "the same from below, by the wheel")
    }
}
