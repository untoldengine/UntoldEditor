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
        XCTAssertEqual(ViewportProjection.allCases, [.perspective, .top, .front, .right])
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
