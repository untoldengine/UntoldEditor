//
//  ViewportOverlayStoreTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// What the navigation gizmo reads from the scene: only over the editor's
/// camera, and published only when it changed.
final class ViewportOverlayStoreTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false
    private var store: ViewportOverlayStore!
    private var sceneCamera: EntityID = .invalid
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalGameMode = gameMode

        scene = Scene()
        gameMode = false
        sceneCamera = findSceneCamera()
        cameraLookAt(entityId: sceneCamera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = sceneCamera

        store = ViewportOverlayStore()
    }

    override func tearDown() {
        cancellables.removeAll()
        store = nil
        scene = originalScene
        CameraSystem.shared.activeCamera = originalActiveCamera
        gameMode = originalGameMode
        originalScene = nil
        super.tearDown()
    }

    private func makeGameCamera() -> EntityID {
        let camera = createEntity()
        setEntityName(entityId: camera, name: "Game Camera")
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        return camera
    }

    func test_overTheEditorsCamera_theAxesAreRead() {
        store.sample()

        XCTAssertEqual(store.handles.count, 6)
        XCTAssertEqual(store.handles, NavigationGizmoGeometry.handles(
            viewSpace: scene.get(component: CameraComponent.self, for: sceneCamera)?.viewSpace ?? matrix_identity_float4x4
        ))
    }

    func test_overAGameCamera_nothingIsRead() {
        store.sample()
        CameraSystem.shared.activeCamera = makeGameCamera()

        store.sample()

        XCTAssertTrue(store.handles.isEmpty)
    }

    func test_whileTheGamePlays_nothingIsRead() {
        store.sample()
        gameMode = true

        store.sample()

        XCTAssertTrue(store.handles.isEmpty)
    }

    func test_withoutACamera_nothingIsRead_andNoneIsCreated() {
        CameraSystem.shared.activeCamera = nil
        let entitiesBefore = scene.getAllEntities()

        store.sample()

        XCTAssertTrue(store.handles.isEmpty)
        XCTAssertEqual(scene.getAllEntities(), entitiesBefore)
    }

    func test_aSceneThatStands_isPublishedOnce() {
        var published = 0
        store.objectWillChange.sink { published += 1 }.store(in: &cancellables)

        store.sample()
        let afterTheFirst = published
        store.sample()
        store.sample()

        XCTAssertGreaterThan(afterTheFirst, 0)
        XCTAssertEqual(published, afterTheFirst)
    }

    func test_aCameraThatMoved_isPublishedAgain() {
        store.sample()
        let before = store.handles
        var published = 0
        store.objectWillChange.sink { published += 1 }.store(in: &cancellables)

        cameraLookAt(entityId: sceneCamera, eye: simd_float3(5, 0, 0), target: .zero, up: simd_float3(0, 1, 0))
        store.sample()

        XCTAssertGreaterThan(published, 0)
        XCTAssertNotEqual(store.handles, before)
    }

    func test_framesThatComeFaster_areReadSixtyTimesASecondAtMost() {
        XCTAssertTrue(store.frameWasDrawn(at: 100))
        XCTAssertFalse(store.frameWasDrawn(at: 100.004))
        XCTAssertFalse(store.frameWasDrawn(at: 100.008))
        XCTAssertTrue(store.frameWasDrawn(at: 100.017))
    }

    func test_aChangeTooSmallToSee_isNoChange() {
        let handle = NavigationGizmoHandle(axis: .x, isPositive: true, offset: simd_float2(0.5, 0.5), depth: 0.2)
        let nudged = NavigationGizmoHandle(axis: .x, isPositive: true, offset: simd_float2(0.5005, 0.5), depth: 0.2)
        let moved = NavigationGizmoHandle(axis: .x, isPositive: true, offset: simd_float2(0.51, 0.5), depth: 0.2)
        XCTAssertFalse(ViewportOverlayStore.differ([handle], [nudged]))
        XCTAssertTrue(ViewportOverlayStore.differ([handle], [moved]))
        XCTAssertTrue(ViewportOverlayStore.differ([handle], []))
    }
}
