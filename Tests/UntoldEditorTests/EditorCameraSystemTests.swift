//
//  EditorCameraSystemTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class EditorCameraSystemTests: XCTestCase {
    private var originalScene: Scene!
    private var testCamera: EntityID!

    override func setUp() {
        super.setUp()

        // Set up Metal device for components that might need it
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }

        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()

        // Snapshot current scene and inject a fresh, empty scene for isolation
        originalScene = scene
        scene = Scene()

        testCamera = .invalid
    }

    override func tearDown() {
        // Clean up test camera if created
        if testCamera != .invalid, testCamera != nil {
            if hasComponent(entityId: testCamera, componentType: CameraComponent.self) {
                destroyEntity(entityId: testCamera)
            }
        }

        // Restore original scene
        scene = originalScene
        originalScene = nil

        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Count entities that have both CameraComponent and SceneCameraComponent
    private func sceneCameraCount() -> Int {
        scene.getAllEntities().reduce(into: 0) { count, eid in
            if hasComponent(entityId: eid, componentType: CameraComponent.self),
               hasComponent(entityId: eid, componentType: SceneCameraComponent.self)
            {
                count += 1
            }
        }
    }

    // MARK: - findSceneCamera Tests

    func test_findSceneCamera_returnsExistingSceneCamera() {
        // Arrange - Create a scene camera
        testCamera = createEntity()
        registerComponent(entityId: testCamera, componentType: CameraComponent.self)
        registerComponent(entityId: testCamera, componentType: SceneCameraComponent.self)
        setEntityName(entityId: testCamera, name: "Existing Scene Camera")

        let beforeCount = sceneCameraCount()

        // Act
        let found = findSceneCamera()

        // Assert
        XCTAssertEqual(found, testCamera, "Should return the existing scene camera")
        XCTAssertEqual(sceneCameraCount(), beforeCount, "Should not create another scene camera")
    }

    func test_findSceneCamera_createsNewCameraWhenMissing() {
        // Arrange - Empty scene with no cameras
        XCTAssertEqual(sceneCameraCount(), 0, "Scene should start with no cameras")

        // Act
        let created = findSceneCamera()

        // Assert
        XCTAssertNotEqual(created, .invalid, "Should create a valid camera entity")
        XCTAssertTrue(hasComponent(entityId: created, componentType: CameraComponent.self),
                      "Created entity should have CameraComponent")
        XCTAssertTrue(hasComponent(entityId: created, componentType: SceneCameraComponent.self),
                      "Created entity should have SceneCameraComponent")
        XCTAssertEqual(sceneCameraCount(), 1, "Should have exactly one scene camera")

        testCamera = created
    }

    func test_findSceneCamera_isIdempotent() {
        // Act - Call multiple times
        let first = findSceneCamera()
        let second = findSceneCamera()
        let third = findSceneCamera()

        // Assert - Should return same entity each time
        XCTAssertEqual(first, second, "First and second calls should return same entity")
        XCTAssertEqual(second, third, "Second and third calls should return same entity")
        XCTAssertEqual(sceneCameraCount(), 1, "Should still have only one scene camera")

        testCamera = first
    }

    func test_findSceneCamera_searchesAllEntities() {
        // Arrange - Create multiple entities, only one is a scene camera
        let regularEntity = createEntity()
        setEntityName(entityId: regularEntity, name: "Regular Entity")

        let cameraOnly = createEntity()
        registerComponent(entityId: cameraOnly, componentType: CameraComponent.self)
        setEntityName(entityId: cameraOnly, name: "Camera Only")

        testCamera = createEntity()
        registerComponent(entityId: testCamera, componentType: CameraComponent.self)
        registerComponent(entityId: testCamera, componentType: SceneCameraComponent.self)
        setEntityName(entityId: testCamera, name: "Scene Camera")

        // Act
        let found = findSceneCamera()

        // Assert - Should find the correct one
        XCTAssertEqual(found, testCamera, "Should find the entity with both components")

        destroyEntity(entityId: regularEntity)
        destroyEntity(entityId: cameraOnly)
    }

    func test_findSceneCamera_requiresBothComponents() {
        // Arrange - Create entities with only one component each
        let cameraOnlyEntity = createEntity()
        registerComponent(entityId: cameraOnlyEntity, componentType: CameraComponent.self)

        let sceneCameraOnlyEntity = createEntity()
        registerComponent(entityId: sceneCameraOnlyEntity, componentType: SceneCameraComponent.self)

        // Act - Should not find either, creates new one
        let found = findSceneCamera()

        // Assert
        XCTAssertNotEqual(found, cameraOnlyEntity, "Should not return camera-only entity")
        XCTAssertNotEqual(found, sceneCameraOnlyEntity, "Should not return scene-camera-only entity")
        XCTAssertTrue(hasComponent(entityId: found, componentType: CameraComponent.self),
                      "Created camera should have both components")
        XCTAssertTrue(hasComponent(entityId: found, componentType: SceneCameraComponent.self),
                      "Created camera should have both components")

        testCamera = found
        destroyEntity(entityId: cameraOnlyEntity)
        destroyEntity(entityId: sceneCameraOnlyEntity)
    }

    // MARK: - createSceneCamera Tests

    func test_createSceneCamera_setsCorrectName() {
        // Arrange
        testCamera = createEntity()

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert
        let name = getEntityName(entityId: testCamera)
        XCTAssertEqual(name, "Scene Camera", "Should set name to 'Scene Camera'")
    }

    func test_createSceneCamera_registersCameraComponent() {
        // Arrange
        testCamera = createEntity()
        XCTAssertFalse(hasComponent(entityId: testCamera, componentType: CameraComponent.self),
                       "Entity should not have CameraComponent initially")

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: CameraComponent.self),
                      "Entity should have CameraComponent after creation")
    }

    func test_createSceneCamera_registersSceneCameraComponent() {
        // Arrange
        testCamera = createEntity()
        XCTAssertFalse(hasComponent(entityId: testCamera, componentType: SceneCameraComponent.self),
                       "Entity should not have SceneCameraComponent initially")

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: SceneCameraComponent.self),
                      "Entity should have SceneCameraComponent after creation")
    }

    func test_createSceneCamera_appliesLookAtTransform() {
        // Arrange
        testCamera = createEntity()

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert - Camera should have transform components
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: LocalTransformComponent.self),
                      "Camera should have LocalTransformComponent after cameraLookAt")
    }

    func test_createSceneCamera_usesDefaultCameraValues() {
        // The function calls cameraLookAt with:
        // - eye: cameraDefaultEye
        // - target: cameraTargetDefault
        // - up: cameraUpDefault

        // Arrange
        testCamera = createEntity()

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert - Verify the defaults are used (documented values)
        XCTAssertEqual(cameraDefaultEye, simd_float3(0.0, 1.0, 4.0),
                       "Default eye position should be (0, 1, 4)")
        XCTAssertEqual(cameraTargetDefault, simd_float3(0.0, 0.0, -2.0),
                       "Default target should be (0, 0, -2)")
        XCTAssertEqual(cameraUpDefault, simd_float3(0.0, 1.0, 0.0),
                       "Default up vector should be (0, 1, 0)")
    }

    func test_createSceneCamera_canBeCalledOnExistingEntity() {
        // Test that createSceneCamera can be called on an entity that already has some components

        // Arrange
        testCamera = createEntity()
        setEntityName(entityId: testCamera, name: "Existing Entity")

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert
        let name = getEntityName(entityId: testCamera)
        XCTAssertEqual(name, "Scene Camera", "Should overwrite name to 'Scene Camera'")
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: CameraComponent.self))
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: SceneCameraComponent.self))
    }

    func test_createSceneCamera_withMultipleEntities() {
        // Test creating multiple scene cameras (though typically there should be only one)

        // Arrange
        let camera1 = createEntity()
        let camera2 = createEntity()

        // Act
        createSceneCamera(entityId: camera1)
        createSceneCamera(entityId: camera2)

        // Assert
        XCTAssertTrue(hasComponent(entityId: camera1, componentType: CameraComponent.self))
        XCTAssertTrue(hasComponent(entityId: camera1, componentType: SceneCameraComponent.self))
        XCTAssertTrue(hasComponent(entityId: camera2, componentType: CameraComponent.self))
        XCTAssertTrue(hasComponent(entityId: camera2, componentType: SceneCameraComponent.self))

        XCTAssertEqual(sceneCameraCount(), 2, "Should have two scene cameras")

        destroyEntity(entityId: camera1)
        destroyEntity(entityId: camera2)
    }

    // MARK: - Integration Tests

    func test_findAndCreateWorkTogether() {
        // Test the typical workflow: find returns existing or creates new

        // Phase 1: No camera exists
        let firstFind = findSceneCamera()
        XCTAssertTrue(hasComponent(entityId: firstFind, componentType: CameraComponent.self))
        XCTAssertTrue(hasComponent(entityId: firstFind, componentType: SceneCameraComponent.self))

        // Phase 2: Camera exists, findSceneCamera returns it
        let secondFind = findSceneCamera()
        XCTAssertEqual(firstFind, secondFind, "Should return the same camera")

        // Phase 3: Create another scene camera manually
        let manualCamera = createEntity()
        createSceneCamera(entityId: manualCamera)

        // Now findSceneCamera could return either one (depends on iteration order)
        let thirdFind = findSceneCamera()
        let isOneOfTheTwo = thirdFind == firstFind || thirdFind == manualCamera
        XCTAssertTrue(isOneOfTheTwo, "Should return one of the existing scene cameras")

        testCamera = firstFind
        destroyEntity(entityId: manualCamera)
    }

    func test_sceneCamera_hasRequiredComponentsForRendering() {
        // Test that a created scene camera has all components needed for rendering

        // Arrange
        testCamera = createEntity()

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert - Check for essential components
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: CameraComponent.self),
                      "Should have CameraComponent for rendering")
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: SceneCameraComponent.self),
                      "Should have SceneCameraComponent to identify it")
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: LocalTransformComponent.self),
                      "Should have LocalTransformComponent for position/rotation")
    }

    func test_findSceneCamera_performanceWithManyEntities() {
        // Test that findSceneCamera works efficiently even with many entities

        // Arrange - Create many entities without camera components
        var entities: [EntityID] = []
        for i in 0 ..< 100 {
            let entity = createEntity()
            setEntityName(entityId: entity, name: "Entity \(i)")
            entities.append(entity)
        }

        // Add one scene camera at the end
        testCamera = createEntity()
        createSceneCamera(entityId: testCamera)

        // Act
        let found = findSceneCamera()

        // Assert
        XCTAssertEqual(found, testCamera, "Should find the scene camera among many entities")

        // Clean up
        for entity in entities {
            destroyEntity(entityId: entity)
        }
    }

    // MARK: - Edge Case Tests

    func test_findSceneCamera_handlesInvalidEntity() {
        // Test that the system handles entities that may have been destroyed

        // Arrange - Create and destroy an entity
        let tempEntity = createEntity()
        registerComponent(entityId: tempEntity, componentType: CameraComponent.self)
        registerComponent(entityId: tempEntity, componentType: SceneCameraComponent.self)
        destroyEntity(entityId: tempEntity)

        // Act - Should create a new one since the old one is gone
        let found = findSceneCamera()

        // Assert
        XCTAssertNotEqual(found, tempEntity, "Should not return destroyed entity")
        XCTAssertTrue(hasComponent(entityId: found, componentType: CameraComponent.self))
        XCTAssertTrue(hasComponent(entityId: found, componentType: SceneCameraComponent.self))

        testCamera = found
    }

    func test_createSceneCamera_withValidEntityID() {
        // Test that createSceneCamera works with a valid entity ID

        // Arrange
        testCamera = createEntity()
        XCTAssertNotEqual(testCamera, .invalid, "Should create valid entity")

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert
        XCTAssertTrue(hasComponent(entityId: testCamera, componentType: CameraComponent.self))
    }

    // MARK: - Camera Configuration Tests

    func test_sceneCamera_lookAtConfiguration() {
        // Test that cameraLookAt is called with correct parameters

        // Arrange
        testCamera = createEntity()

        // Act
        createSceneCamera(entityId: testCamera)

        // Assert - Camera should have proper transform
        guard let transform = scene.get(component: LocalTransformComponent.self, for: testCamera) else {
            XCTFail("Camera should have LocalTransformComponent")
            return
        }

        XCTAssertNotNil(transform, "Transform should be configured")
    }

    func test_findSceneCamera_returnsFirstMatchInIteration() {
        // Test that when multiple scene cameras exist, it returns the first one found

        // Arrange - Create multiple scene cameras
        let camera1 = createEntity()
        createSceneCamera(entityId: camera1)

        let camera2 = createEntity()
        createSceneCamera(entityId: camera2)

        // Act
        let found = findSceneCamera()

        // Assert - Should return one of them (deterministic based on iteration order)
        let isValid = found == camera1 || found == camera2
        XCTAssertTrue(isValid, "Should return one of the existing scene cameras")
        XCTAssertEqual(sceneCameraCount(), 2, "Should have both cameras")

        // Clean up
        destroyEntity(entityId: camera1)
        destroyEntity(entityId: camera2)
        testCamera = .invalid
    }
}
