//
//  ViewportCameraTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The camera the viewport shows while editing: the editor's own, or a game
/// camera of the scene as a locked preview.
final class ViewportCameraTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false

    override func setUp() {
        super.setUp()
        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalGameMode = gameMode
        scene = Scene()
        gameMode = false
        CameraSystem.shared.activeCamera = nil
    }

    override func tearDown() {
        scene = originalScene
        gameMode = originalGameMode
        CameraSystem.shared.activeCamera = originalActiveCamera
        originalScene = nil
        super.tearDown()
    }

    private func makeGameCamera(named name: String) -> EntityID {
        let camera = createEntity()
        setEntityName(entityId: camera, name: name)
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        return camera
    }

    func test_gameCameras_listsEveryGameCameraByName_andNeverTheEditorCamera() {
        _ = findSceneCamera()
        let prop = createEntity()
        setEntityName(entityId: prop, name: "Crate")
        let intro = makeGameCamera(named: "Intro")
        let boss = makeGameCamera(named: "Boss")

        XCTAssertEqual(ViewportCameras.gameCameras(), [
            GameCameraChoice(entityId: intro, name: "Intro"),
            GameCameraChoice(entityId: boss, name: "Boss"),
        ])
    }

    func test_gameCameras_isEmptyAndCreatesNothing_whenTheSceneHasOnlyTheEditorCamera() {
        let sceneCamera = findSceneCamera()
        CameraSystem.shared.activeCamera = sceneCamera
        let entitiesBefore = scene.getAllEntities()

        XCTAssertTrue(ViewportCameras.gameCameras().isEmpty)
        XCTAssertEqual(ViewportCameras.current, .editor)

        XCTAssertEqual(scene.getAllEntities(), entitiesBefore)
        XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera)
    }

    func test_show_aGameCamera_locksTheViewportOnIt_andTheEditorCameraUnlocksIt() {
        let sceneCamera = findSceneCamera()
        let intro = makeGameCamera(named: "Intro")
        let boss = makeGameCamera(named: "Boss")
        ViewportCameras.show(.editor)
        XCTAssertFalse(ViewportCameras.isLockedPreview)

        XCTAssertTrue(ViewportCameras.show(.game(boss)))
        XCTAssertEqual(CameraSystem.shared.activeCamera, boss)
        XCTAssertEqual(ViewportCameras.current, .game(boss))
        XCTAssertTrue(ViewportCameras.isLockedPreview)

        XCTAssertTrue(ViewportCameras.show(.game(intro)))
        XCTAssertEqual(ViewportCameras.current, .game(intro))

        XCTAssertTrue(ViewportCameras.show(.editor))
        XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera)
        XCTAssertEqual(ViewportCameras.current, .editor)
        XCTAssertFalse(ViewportCameras.isLockedPreview)
    }

    func test_whileAHeadsetPreviews_theViewportIsLocked_andTheKeysSteerTheEditorsCamera() {
        let original = ViewportCameras.isPreviewingOnHeadset
        ViewportCameras.isPreviewingOnHeadset = { true }
        defer { ViewportCameras.isPreviewingOnHeadset = original }
        let camera = findSceneCamera()

        XCTAssertEqual(ViewportCameras.current, .editor, "the editor's camera carries the headset")
        XCTAssertTrue(ViewportCameras.isLockedPreview, "clicks select nothing and no overlay is drawn")
        XCTAssertEqual(ViewportCameras.steered, camera, "the keys and the mouse fly the camera the headset rides")
    }

    func test_show_refusesAnEntityThatIsNotAGameCamera() {
        let sceneCamera = findSceneCamera()
        let prop = createEntity()
        ViewportCameras.show(.editor)

        XCTAssertFalse(ViewportCameras.show(.game(prop)))
        XCTAssertFalse(ViewportCameras.show(.game(sceneCamera)))

        XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera)
        XCTAssertEqual(ViewportCameras.current, .editor)
    }

    func test_whileTheGameRuns_theViewportIsNeverAPreview() {
        _ = findSceneCamera()
        let camera = makeGameCamera(named: "Game Camera")
        CameraSystem.shared.activeCamera = camera

        gameMode = true

        XCTAssertEqual(ViewportCameras.current, .editor)
        XCTAssertFalse(ViewportCameras.isLockedPreview)
    }

    func test_deletingThePreviewedCamera_givesTheViewportBackToTheEditor() {
        let sceneCamera = findSceneCamera()
        let rig = createEntity()
        registerTransformComponent(entityId: rig)
        registerSceneGraphComponent(entityId: rig)
        let camera = makeGameCamera(named: "Game Camera")
        registerTransformComponent(entityId: camera)
        registerSceneGraphComponent(entityId: camera)
        setParent(childId: camera, parentId: rig)
        let other = makeGameCamera(named: "Other")
        ViewportCameras.show(.game(camera))

        XCTAssertFalse(ViewportCameras.forget(other), "another entity leaves the preview alone")
        XCTAssertEqual(ViewportCameras.current, .game(camera))

        XCTAssertTrue(ViewportCameras.forget(camera))
        XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera)
        XCTAssertEqual(ViewportCameras.current, .editor)

        // Deleting the rig takes the camera with it.
        ViewportCameras.show(.game(camera))
        XCTAssertTrue(ViewportCameras.forget(rig))
        XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera)

        XCTAssertFalse(ViewportCameras.forget(camera), "on the editor's camera there is nothing to forget")
    }

    func test_theCameraForPlay_isTheScenes_andNoneIsCreated() {
        let sceneCamera = findSceneCamera()
        CameraSystem.shared.activeCamera = sceneCamera
        let entitiesBefore = scene.getAllEntities()

        XCTAssertNil(ViewportCameras.gameCameraForPlay(authored: nil), "a scene without a game camera")
        XCTAssertEqual(scene.getAllEntities(), entitiesBefore, "and none was created for it")

        let first = makeGameCamera(named: "First")
        let second = makeGameCamera(named: "Second")
        XCTAssertEqual(ViewportCameras.gameCameraForPlay(authored: nil), first, "the scene's first")

        CameraSystem.shared.activeCamera = second
        XCTAssertEqual(ViewportCameras.gameCameraForPlay(authored: nil), second, "the one the viewport is on")

        XCTAssertEqual(ViewportCameras.gameCameraForPlay(authored: first), first, "the one the scene was authored with, first of all")
        XCTAssertEqual(ViewportCameras.gameCameraForPlay(authored: sceneCamera), second, "unless it is no game camera")
        XCTAssertEqual(ViewportCameras.gameCameraForPlay(authored: 424_242), second, "or no longer there")
    }

    func test_aProjection_returnsTheViewportToTheEditorCamera() {
        let sceneCamera = findSceneCamera()
        let camera = makeGameCamera(named: "Game Camera")
        ViewportCameras.show(.game(camera))

        ViewportProjection.front.applyToSceneCamera()

        XCTAssertEqual(CameraSystem.shared.activeCamera, sceneCamera)
        XCTAssertFalse(ViewportCameras.isLockedPreview)
    }
}
