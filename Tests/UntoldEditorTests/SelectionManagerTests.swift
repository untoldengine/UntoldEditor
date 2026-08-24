//
//  SelectionManagerTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Combine
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class SelectionManagerTests: XCTestCase {
    private var selectionManager: SelectionManager!
    private var sceneGraphModel: SceneGraphModel!

    override func setUp() {
        super.setUp()

        // Create fresh scene
        scene = Scene()

        // Initialize managers
        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createEntityWithTransform(name: String = "Test Entity") -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerComponent(entityId: entity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: entity, componentType: WorldTransformComponent.self)
        return entity
    }

    // MARK: - SceneGraphModel Tests

    func test_sceneGraphModel_refreshHierarchy_buildsCorrectMapping() {
        // Arrange
        let root1 = createEntityWithTransform(name: "Root1")
        let root2 = createEntityWithTransform(name: "Root2")
        registerComponent(entityId: root1, componentType: ScenegraphComponent.self)
        registerComponent(entityId: root2, componentType: ScenegraphComponent.self)

        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert: Both entities should appear at root level
        let rootChildren = sceneGraphModel.getChildren(entityId: nil)
        XCTAssertTrue(rootChildren.contains(root1), "Root1 should be at root level")
        XCTAssertTrue(rootChildren.contains(root2), "Root2 should be at root level")
    }

    func test_sceneGraphModel_refreshHierarchy_handlesEntitiesWithoutScenegraphComponent() {
        // Arrange: Create entity without ScenegraphComponent (like cameras)
        let camera = createEntityWithTransform(name: "Camera")
        // Don't register ScenegraphComponent

        let regularEntity = createEntityWithTransform(name: "Regular")
        registerComponent(entityId: regularEntity, componentType: ScenegraphComponent.self)

        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert: Both should appear at root level
        let rootChildren = sceneGraphModel.getChildren(entityId: nil)
        XCTAssertTrue(rootChildren.contains(camera), "Camera without ScenegraphComponent should be at root")
        XCTAssertTrue(rootChildren.contains(regularEntity), "Regular entity should be at root")
    }

    func test_sceneGraphModel_getChildren_returnsEmptyForNonexistentParent() {
        // Arrange
        sceneGraphModel.refreshHierarchy()

        // Act
        let children = sceneGraphModel.getChildren(entityId: EntityID(9999))

        // Assert
        XCTAssertTrue(children.isEmpty, "Should return empty array for nonexistent parent")
    }

    func test_sceneGraphModel_refreshHierarchy_handlesEmptyScene() {
        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert
        let rootChildren = sceneGraphModel.getChildren(entityId: nil)
        XCTAssertTrue(rootChildren.isEmpty, "Empty scene should have no root children")
    }

    func test_sceneGraphModel_refreshHierarchy_withMultipleEntities() {
        // Arrange: Create several entities
        let entities = (0 ..< 10).map { i in
            let e = createEntityWithTransform(name: "Entity\(i)")
            registerComponent(entityId: e, componentType: ScenegraphComponent.self)
            return e
        }

        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert
        let rootChildren = sceneGraphModel.getChildren(entityId: nil)
        XCTAssertEqual(rootChildren.count, entities.count, "All entities should be at root level")
    }

    func test_sceneGraphModel_refreshHierarchy_afterEntityDestruction() {
        // Arrange
        let entity1 = createEntityWithTransform(name: "Entity1")
        let entity2 = createEntityWithTransform(name: "Entity2")
        registerComponent(entityId: entity1, componentType: ScenegraphComponent.self)
        registerComponent(entityId: entity2, componentType: ScenegraphComponent.self)

        sceneGraphModel.refreshHierarchy()
        let beforeCount = sceneGraphModel.getChildren(entityId: nil).count

        // Act: Destroy one entity and refresh
        destroyEntity(entityId: entity1)
        sceneGraphModel.refreshHierarchy()

        // Assert
        let afterCount = sceneGraphModel.getChildren(entityId: nil).count
        XCTAssertEqual(afterCount, beforeCount - 1, "Destroyed entity should not appear in hierarchy")
    }

    func test_sceneGraphModel_childrenMap_isPublished() {
        // Arrange
        var mapUpdateCount = 0
        let cancellable = sceneGraphModel.$childrenMap.sink { _ in
            mapUpdateCount += 1
        }

        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert
        XCTAssertGreaterThan(mapUpdateCount, 0, "childrenMap should publish updates")

        cancellable.cancel()
    }

    // MARK: - SelectionManager Basic State Tests (No Gizmo Creation)

    func test_selectionManager_selectedEntity_canBeSet() {
        // Arrange
        let entity = createEntityWithTransform(name: "TestEntity")

        // Act
        selectionManager.selectedEntity = entity

        // Assert
        XCTAssertEqual(selectionManager.selectedEntity, entity, "Selected entity should be set")
    }

    func test_selectionManager_selectedEntity_canBeCleared() {
        // Arrange
        let entity = createEntityWithTransform(name: "TestEntity")
        selectionManager.selectedEntity = entity

        // Act
        selectionManager.selectedEntity = nil

        // Assert
        XCTAssertNil(selectionManager.selectedEntity, "Selected entity should be cleared")
    }

    func test_selectionManager_selectedEntity_isPublished() {
        // Arrange
        var receivedValues: [EntityID?] = []
        let cancellable = selectionManager.$selectedEntity.sink { entityId in
            receivedValues.append(entityId)
        }

        let entity = createEntityWithTransform(name: "Test")

        // Act
        selectionManager.selectedEntity = entity

        // Assert
        XCTAssertTrue(receivedValues.contains(entity), "Should receive entity ID in published updates")

        cancellable.cancel()
    }

    func test_selectionManager_selectedEntity_publishes_objectWillChange() {
        // Arrange
        var changeCount = 0
        let cancellable = selectionManager.objectWillChange.sink { _ in
            changeCount += 1
        }

        let entity = createEntityWithTransform(name: "Test")

        // Act
        selectionManager.selectedEntity = entity

        // Assert
        XCTAssertGreaterThan(changeCount, 0, "Should publish objectWillChange")

        cancellable.cancel()
    }

    func test_selectionManager_multipleSelections_updatesPublisher() {
        // Arrange
        var receivedValues: [EntityID?] = []
        let cancellable = selectionManager.$selectedEntity.sink { entityId in
            receivedValues.append(entityId)
        }

        let entity1 = createEntityWithTransform(name: "First")
        let entity2 = createEntityWithTransform(name: "Second")

        // Act
        selectionManager.selectedEntity = entity1
        selectionManager.selectedEntity = entity2

        // Assert
        XCTAssertEqual(receivedValues.count, 3, "Should receive initial + 2 updates")
        XCTAssertEqual(receivedValues[1], entity1, "First update should be entity1")
        XCTAssertEqual(receivedValues[2], entity2, "Second update should be entity2")

        cancellable.cancel()
    }

    func test_selectionManager_invalidEntity_canBeSelected() {
        // Act
        selectionManager.selectedEntity = .invalid

        // Assert
        XCTAssertEqual(selectionManager.selectedEntity, .invalid, "Invalid entity can be set")
    }

    func test_selectionManager_selectingDestroyedEntity_doesNotCrash() {
        // Arrange
        let entity = createEntityWithTransform(name: "ToBeDestroyed")
        destroyEntity(entityId: entity)

        // Act & Assert: Should not crash
        selectionManager.selectedEntity = entity
        XCTAssertEqual(selectionManager.selectedEntity, entity, "Destroyed entity can be set")
    }

    // MARK: - Integration Tests

    func test_selectionManager_withSceneGraphModel_bothPublishUpdates() {
        // Arrange
        var selectionUpdates = 0
        var hierarchyUpdates = 0

        let selectionCancellable = selectionManager.objectWillChange.sink { _ in
            selectionUpdates += 1
        }

        let hierarchyCancellable = sceneGraphModel.$childrenMap.sink { _ in
            hierarchyUpdates += 1
        }

        let entity = createEntityWithTransform(name: "Entity")
        registerComponent(entityId: entity, componentType: ScenegraphComponent.self)

        // Act
        sceneGraphModel.refreshHierarchy()
        selectionManager.selectedEntity = entity

        // Assert
        XCTAssertGreaterThan(selectionUpdates, 0, "Selection should publish updates")
        XCTAssertGreaterThan(hierarchyUpdates, 0, "Hierarchy should publish updates")

        selectionCancellable.cancel()
        hierarchyCancellable.cancel()
    }

    // MARK: - SceneGraphModel Edge Cases

    func test_sceneGraphModel_getChildren_withNilEntityId_returnsRootEntities() {
        // Arrange
        let entity = createEntityWithTransform(name: "Root")
        registerComponent(entityId: entity, componentType: ScenegraphComponent.self)

        sceneGraphModel.refreshHierarchy()

        // Act
        let rootChildren = sceneGraphModel.getChildren(entityId: nil)

        // Assert
        XCTAssertTrue(rootChildren.contains(entity), "Nil entity ID should return root entities")
    }

    func test_sceneGraphModel_refreshHierarchy_idempotent() {
        // Arrange
        let entity = createEntityWithTransform(name: "Entity")
        registerComponent(entityId: entity, componentType: ScenegraphComponent.self)

        // Act: Refresh multiple times
        sceneGraphModel.refreshHierarchy()
        let firstResult = sceneGraphModel.getChildren(entityId: nil)

        sceneGraphModel.refreshHierarchy()
        let secondResult = sceneGraphModel.getChildren(entityId: nil)

        // Assert: Results should be the same
        XCTAssertEqual(firstResult.count, secondResult.count, "Multiple refreshes should produce same results")
        XCTAssertEqual(Set(firstResult), Set(secondResult), "Entity sets should match")
    }

    // MARK: - SelectionManager State Transitions

    func test_selectionManager_fromNilToEntity() {
        // Arrange
        XCTAssertEqual(selectionManager.selectedEntity, .invalid, "Should start as invalid")

        let entity = createEntityWithTransform(name: "Selected")

        // Act
        selectionManager.selectedEntity = entity

        // Assert
        XCTAssertEqual(selectionManager.selectedEntity, entity, "Should transition to selected entity")
    }

    func test_selectionManager_fromEntityToNil() {
        // Arrange
        let entity = createEntityWithTransform(name: "Selected")
        selectionManager.selectedEntity = entity

        // Act
        selectionManager.selectedEntity = nil

        // Assert
        XCTAssertNil(selectionManager.selectedEntity, "Should transition to nil")
    }

    func test_selectionManager_fromEntityToEntity() {
        // Arrange
        let entity1 = createEntityWithTransform(name: "First")
        let entity2 = createEntityWithTransform(name: "Second")
        selectionManager.selectedEntity = entity1

        // Act
        selectionManager.selectedEntity = entity2

        // Assert
        XCTAssertEqual(selectionManager.selectedEntity, entity2, "Should transition to second entity")
    }

    func test_selectionManager_selectingSameEntityTwice_stillPublishes() {
        // Arrange
        var updateCount = 0
        let cancellable = selectionManager.objectWillChange.sink { _ in
            updateCount += 1
        }

        let entity = createEntityWithTransform(name: "Same")

        // Act
        selectionManager.selectedEntity = entity
        let afterFirstSelect = updateCount

        selectionManager.selectedEntity = entity
        let afterSecondSelect = updateCount

        // Assert
        XCTAssertGreaterThan(afterSecondSelect, afterFirstSelect, "Should publish even when selecting same entity")

        cancellable.cancel()
    }
}
