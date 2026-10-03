//
//  ViewportProjectionCameraTests.swift
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

/// While editing, the viewport is the editor's camera: the projection menu
/// works on it and never on a camera of the game.
final class ViewportProjectionCameraTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?

    override func setUp() {
        super.setUp()
        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        scene = Scene()
        CameraSystem.shared.activeCamera = nil
    }

    override func tearDown() {
        scene = originalScene
        CameraSystem.shared.activeCamera = originalActiveCamera
        originalScene = nil
        super.tearDown()
    }

    private func makeGameCamera() -> EntityID {
        let camera = createEntity()
        setEntityName(entityId: camera, name: "Game Camera")
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        return camera
    }

    func test_theMenu_offersOnlyViewsOfTheEditorCamera() {
        XCTAssertEqual(ViewportProjection.allCases, [.perspective, .top, .front, .right, .bottom, .back, .left])
        XCTAssertEqual(ViewportProjection.presets, [.top, .front, .right, .bottom, .back, .left])
    }

    func test_everyPresetView_looksAtThePivotFromItsSide() throws {
        let sceneCamera = findSceneCamera()
        let pivot = simd_float3(1, 2, 3)
        let sides: [ViewportProjection: simd_float3] = [
            .top: simd_float3(0, 1, 0), .bottom: simd_float3(0, -1, 0),
            .front: simd_float3(0, 0, 1), .back: simd_float3(0, 0, -1),
            .right: simd_float3(1, 0, 0), .left: simd_float3(-1, 0, 0),
        ]

        for projection in ViewportProjection.presets {
            cameraLookAt(entityId: sceneCamera, eye: pivot + simd_float3(0, 0, 5), target: pivot, up: simd_float3(0, 1, 0))

            projection.applyToSceneCamera()

            let eye = getCameraEye(entityId: sceneCamera)
            let expected = try pivot + XCTUnwrap(sides[projection]) * 5
            XCTAssertEqual(eye.x, expected.x, accuracy: 0.001, projection.title)
            XCTAssertEqual(eye.y, expected.y, accuracy: 0.001, projection.title)
            XCTAssertEqual(eye.z, expected.z, accuracy: 0.001, projection.title)
            XCTAssertEqual(getCameraTarget(entityId: sceneCamera), pivot, projection.title)
        }
    }

    func test_oppositeViews_lookFromOppositeSides() throws {
        let pairs: [(ViewportProjection, ViewportProjection)] = [(.top, .bottom), (.front, .back), (.right, .left)]
        for (one, other) in pairs {
            let side = try XCTUnwrap(one.view).direction
            let otherSide = try XCTUnwrap(other.view).direction
            XCTAssertEqual(side, -otherSide)
        }
    }

    func test_fromAboveAndFromBelow_theWorldsXRunsToTheRight() throws {
        for projection in [ViewportProjection.top, .bottom] {
            let view = try XCTUnwrap(projection.view)
            // The camera looks back at the pivot; its right is what it looks along, turned by its up.
            let right = simd_cross(-view.direction, view.up)
            XCTAssertEqual(right, simd_float3(1, 0, 0), projection.title)
        }
    }

    func test_everyProjection_putsTheViewportOnTheEditorCamera_andCreatesNoCamera() {
        let sceneCamera = findSceneCamera()
        let gameCamera = makeGameCamera()
        let entitiesBefore = scene.getAllEntities()

        for projection in ViewportProjection.allCases {
            CameraSystem.shared.activeCamera = gameCamera

            projection.applyToSceneCamera()

            XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera, "\(projection.title)")
        }
        XCTAssertEqual(scene.getAllEntities(), entitiesBefore)
    }

    func test_aPresetView_sendsTheEditorCameraAlongItsAxis_andLeavesTheGameCameraAlone() {
        let sceneCamera = findSceneCamera()
        let gameCamera = makeGameCamera()
        let pivot = simd_float3(1, 2, 3)
        cameraLookAt(entityId: sceneCamera, eye: pivot + simd_float3(0, 0, 5), target: pivot, up: simd_float3(0, 1, 0))
        cameraLookAt(entityId: gameCamera, eye: simd_float3(9, 9, 9), target: .zero, up: simd_float3(0, 1, 0))
        let gameEye = getCameraEye(entityId: gameCamera)

        ViewportProjection.top.applyToSceneCamera()

        let eye = getCameraEye(entityId: sceneCamera)
        XCTAssertEqual(eye.x, 1, accuracy: 0.001)
        XCTAssertEqual(eye.y, 7, accuracy: 0.001)
        XCTAssertEqual(eye.z, 3, accuracy: 0.001)
        XCTAssertEqual(getCameraEye(entityId: gameCamera), gameEye)
    }

    func test_perspective_leavesTheEditorCameraWhereItIs() {
        let sceneCamera = findSceneCamera()
        cameraLookAt(entityId: sceneCamera, eye: simd_float3(4, 5, 6), target: .zero, up: simd_float3(0, 1, 0))
        let eye = getCameraEye(entityId: sceneCamera)

        ViewportProjection.perspective.applyToSceneCamera()

        XCTAssertEqual(getCameraEye(entityId: sceneCamera), eye)
    }
}
