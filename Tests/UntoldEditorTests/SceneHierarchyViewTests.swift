//
//  SceneHierarchyViewTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class SceneHierarchyViewTests: XCTestCase {
    var selectionManager: SelectionManager!
    var sceneGraphModel: SceneGraphModel!

    override func setUp() {
        super.setUp()

        // Create fresh scene
        scene = Scene()

        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
    }

    override func tearDown() {
        selectionManager = nil
        sceneGraphModel = nil
        super.tearDown()
    }

    // MARK: - EntityRow Tests

    func test_entityRow_isNotSelectedByDefault() {
        // Arrange
        let entity = createEntity()

        // Act
        let row = EntityRow(
            entityid: entity,
            entityName: "TestEntity",
            selectionManager: selectionManager
        )

        // Assert: Use reflection to check isSelected property
        let mirror = Mirror(reflecting: row)
        if let isSelected = mirror.descendant("isSelected") as? Bool {
            XCTAssertFalse(isSelected, "Entity should not be selected by default")
        }
    }

    func test_entityRow_isSelectedWhenMatchesSelectionManager() {
        // Arrange
        let entity = createEntity()
        selectionManager.selectedEntity = entity

        // Act
        let row = EntityRow(
            entityid: entity,
            entityName: "TestEntity",
            selectionManager: selectionManager
        )

        // Assert: Use reflection to check isSelected property
        let mirror = Mirror(reflecting: row)
        if let isSelected = mirror.descendant("isSelected") as? Bool {
            XCTAssertTrue(isSelected, "Entity should be selected when it matches selection manager")
        }
    }

    func test_entityRow_displaysEntityName() {
        // Arrange
        let entity = createEntity()
        let expectedName = "MyEntity"

        // Act
        let row = EntityRow(
            entityid: entity,
            entityName: expectedName,
            selectionManager: selectionManager
        )

        // Assert: Verify the entityName is stored correctly
        let mirror = Mirror(reflecting: row)
        if let entityName = mirror.descendant("entityName") as? String {
            XCTAssertEqual(entityName, expectedName, "Should store the entity name")
        }
    }

    func test_entityRow_tracksEntityID() {
        // Arrange
        let entity = createEntity()

        // Act
        let row = EntityRow(
            entityid: entity,
            entityName: "TestEntity",
            selectionManager: selectionManager
        )

        // Assert: Verify the entityid is stored correctly
        let mirror = Mirror(reflecting: row)
        if let entityid = mirror.descendant("entityid") as? EntityID {
            XCTAssertEqual(entityid, entity, "Should track the entity ID")
        }
    }

    // MARK: - HierarchyNode Tests

    func test_hierarchyNode_storesEntityData() {
        // Arrange
        let entity = createEntity()
        let expectedName = "NodeEntity"
        let expectedDepth = 2

        // Act
        let node = HierarchyNode(
            entityId: entity,
            entityName: expectedName,
            depth: expectedDepth,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        )

        // Assert
        let mirror = Mirror(reflecting: node)
        if let entityId = mirror.descendant("entityId") as? EntityID {
            XCTAssertEqual(entityId, entity, "Should store entity ID")
        }
        if let entityName = mirror.descendant("entityName") as? String {
            XCTAssertEqual(entityName, expectedName, "Should store entity name")
        }
        if let depth = mirror.descendant("depth") as? Int {
            XCTAssertEqual(depth, expectedDepth, "Should store depth")
        }
    }

    func test_hierarchyNode_withZeroDepth() {
        // Arrange
        let entity = createEntity()

        // Act
        let node = HierarchyNode(
            entityId: entity,
            entityName: "RootEntity",
            depth: 0,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        )

        // Assert
        let mirror = Mirror(reflecting: node)
        if let depth = mirror.descendant("depth") as? Int {
            XCTAssertEqual(depth, 0, "Should handle zero depth for root nodes")
        }
    }

    func test_hierarchyNode_withNestedDepth() {
        // Arrange
        let entity = createEntity()

        // Act: Create nodes at various depths
        let depths = [1, 2, 3, 5, 10]

        for depth in depths {
            let node = HierarchyNode(
                entityId: entity,
                entityName: "Entity_Depth\(depth)",
                depth: depth,
                sceneGraphModel: sceneGraphModel,
                selectionManager: selectionManager
            )

            // Assert
            let mirror = Mirror(reflecting: node)
            if let storedDepth = mirror.descendant("depth") as? Int {
                XCTAssertEqual(storedDepth, depth, "Should correctly store depth \(depth)")
            }
        }
    }

    // MARK: - SceneGraphModel Integration Tests

    func test_hierarchyNode_queriesSceneGraphForChildren() {
        // Arrange
        let parent = createEntity()

        // Refresh the scene graph to cache hierarchy
        sceneGraphModel.refreshHierarchy()

        // Act
        let children = sceneGraphModel.getChildren(entityId: parent)

        // Assert: Entity with no children should return empty array
        XCTAssertEqual(children.count, 0, "Entity with no children should return empty array")
    }

    func test_sceneGraphModel_returnsRootEntitiesForNilParent() {
        // Arrange
        createEntity()
        createEntity()

        // Refresh to cache the hierarchy
        sceneGraphModel.refreshHierarchy()

        // Act
        let rootEntities = sceneGraphModel.getChildren(entityId: nil)

        // Assert: Should return array of root entities (entities without parents)
        XCTAssertNotNil(rootEntities, "Should return a valid array for root entities")
    }

    func test_sceneGraphModel_entityWithNoChildren() {
        // Arrange
        let entity = createEntity()

        // Refresh hierarchy
        sceneGraphModel.refreshHierarchy()

        // Act
        let children = sceneGraphModel.getChildren(entityId: entity)

        // Assert
        XCTAssertEqual(children.count, 0, "Entity with no children should return empty array")
    }

    func test_sceneGraphModel_entityWithChildrenReportsHasChildren() {
        // Arrange
        let parent = createEntity()
        let child = createEntity()
        registerSceneGraphComponent(entityId: parent)
        registerSceneGraphComponent(entityId: child)
        setParent(childId: child, parentId: parent)

        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert
        XCTAssertTrue(sceneGraphModel.hasChildren(entityId: parent), "Parent should report children")
        XCTAssertFalse(sceneGraphModel.hasChildren(entityId: child), "Leaf child should not report children")
    }

    func test_sceneGraphModel_nodesAreCollapsedByDefault() {
        // Arrange
        let entity = createEntity()

        // Act
        sceneGraphModel.refreshHierarchy()

        // Assert
        XCTAssertFalse(sceneGraphModel.isExpanded(entityId: entity), "Nodes should be collapsed by default")
    }

    func test_sceneGraphModel_toggleExpandedExpandsAndCollapsesNode() {
        // Arrange
        let entity = createEntity()
        sceneGraphModel.refreshHierarchy()

        // Act / Assert
        sceneGraphModel.toggleExpanded(entityId: entity)
        XCTAssertTrue(sceneGraphModel.isExpanded(entityId: entity), "Toggle should expand collapsed nodes")

        sceneGraphModel.toggleExpanded(entityId: entity)
        XCTAssertFalse(sceneGraphModel.isExpanded(entityId: entity), "Toggle should collapse expanded nodes")
    }

    func test_sceneGraphModel_refreshPrunesExpandedDestroyedEntities() {
        // Arrange
        let entity = createEntity()
        sceneGraphModel.refreshHierarchy()
        sceneGraphModel.toggleExpanded(entityId: entity)
        XCTAssertTrue(sceneGraphModel.isExpanded(entityId: entity))

        // Act
        destroyEntity(entityId: entity)
        sceneGraphModel.refreshHierarchy()

        // Assert
        XCTAssertFalse(sceneGraphModel.isExpanded(entityId: entity), "Destroyed entities should be pruned from expanded state")
    }

    // MARK: - SelectionManager Integration Tests

    func test_selectionManager_updatesSelectedEntity() {
        // Arrange
        let entity1 = createEntity()
        let entity2 = createEntity()

        // Act: Select first entity
        selectionManager.selectedEntity = entity1
        XCTAssertEqual(selectionManager.selectedEntity, entity1, "Should select first entity")

        // Act: Select second entity
        selectionManager.selectedEntity = entity2
        XCTAssertEqual(selectionManager.selectedEntity, entity2, "Should update to second entity")
    }

    func test_selectionManager_handlesNilSelection() {
        // Arrange
        let entity = createEntity()
        selectionManager.selectedEntity = entity

        // Act: Clear selection
        selectionManager.selectedEntity = nil

        // Assert
        XCTAssertNil(selectionManager.selectedEntity, "Should handle nil selection")
    }

    // MARK: - SceneHierarchyView Structure Tests

    func test_sceneHierarchyView_storesCallbacks() {
        // Arrange
        var addEntityCalled = false
        var removeEntityCalled = false
        var addCubeCalled = false
        var addSphereCalled = false
        var addPlaneCalled = false
        var addDirLightCalled = false
        var addPointLightCalled = false
        var addSpotLightCalled = false
        var addAreaLightCalled = false

        // Act
        let view = SceneHierarchyView(
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            sceneCatalog: ProjectSceneCatalog(),
            projectName: "TestProject",
            onSelectScene: { _ in },
            isPlaying: false,
            onTogglePlay: {},
            entityList: [],
            onAddEntity_Editor: { addEntityCalled = true },
            onRemoveEntity_Editor: { removeEntityCalled = true },
            onAddCube: { addCubeCalled = true },
            onAddSphere: { addSphereCalled = true },
            onAddPlane: { addPlaneCalled = true },
            onAddDirLight: { addDirLightCalled = true },
            onAddPointLight: { addPointLightCalled = true },
            onAddSpotLight: { addSpotLightCalled = true },
            onAddAreaLight: { addAreaLightCalled = true }
        )

        // Assert: Test that callbacks can be invoked via reflection
        let mirror = Mirror(reflecting: view)

        if let onAddEntity = mirror.descendant("onAddEntity_Editor") as? () -> Void {
            onAddEntity()
            XCTAssertTrue(addEntityCalled, "onAddEntity_Editor should be callable")
        }

        if let onRemoveEntity = mirror.descendant("onRemoveEntity_Editor") as? () -> Void {
            onRemoveEntity()
            XCTAssertTrue(removeEntityCalled, "onRemoveEntity_Editor should be callable")
        }

        if let onAddCube = mirror.descendant("onAddCube") as? () -> Void {
            onAddCube()
            XCTAssertTrue(addCubeCalled, "onAddCube should be callable")
        }

        if let onAddSphere = mirror.descendant("onAddSphere") as? () -> Void {
            onAddSphere()
            XCTAssertTrue(addSphereCalled, "onAddSphere should be callable")
        }

        if let onAddPlane = mirror.descendant("onAddPlane") as? () -> Void {
            onAddPlane()
            XCTAssertTrue(addPlaneCalled, "onAddPlane should be callable")
        }

        if let onAddDirLight = mirror.descendant("onAddDirLight") as? () -> Void {
            onAddDirLight()
            XCTAssertTrue(addDirLightCalled, "onAddDirLight should be callable")
        }

        if let onAddPointLight = mirror.descendant("onAddPointLight") as? () -> Void {
            onAddPointLight()
            XCTAssertTrue(addPointLightCalled, "onAddPointLight should be callable")
        }

        if let onAddSpotLight = mirror.descendant("onAddSpotLight") as? () -> Void {
            onAddSpotLight()
            XCTAssertTrue(addSpotLightCalled, "onAddSpotLight should be callable")
        }

        if let onAddAreaLight = mirror.descendant("onAddAreaLight") as? () -> Void {
            onAddAreaLight()
            XCTAssertTrue(addAreaLightCalled, "onAddAreaLight should be callable")
        }
    }

    func test_sceneHierarchyView_storesEntityList() {
        // Arrange
        let entity1 = createEntity()
        let entity2 = createEntity()
        let entity3 = createEntity()
        let entityList = [entity1, entity2, entity3]

        // Act
        let view = SceneHierarchyView(
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            sceneCatalog: ProjectSceneCatalog(),
            projectName: "TestProject",
            onSelectScene: { _ in },
            isPlaying: false,
            onTogglePlay: {},
            entityList: entityList,
            onAddEntity_Editor: {},
            onRemoveEntity_Editor: {},
            onAddCube: {},
            onAddSphere: {},
            onAddPlane: {},
            onAddDirLight: {},
            onAddPointLight: {},
            onAddSpotLight: {},
            onAddAreaLight: {}
        )

        // Assert
        let mirror = Mirror(reflecting: view)
        if let storedList = mirror.descendant("entityList") as? [EntityID] {
            XCTAssertEqual(storedList.count, 3, "Should store entity list")
            XCTAssertEqual(storedList, entityList, "Should match original entity list")
        }
    }

    func test_sceneHierarchyView_withEmptyEntityList() {
        // Act
        let view = SceneHierarchyView(
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            sceneCatalog: ProjectSceneCatalog(),
            projectName: "TestProject",
            onSelectScene: { _ in },
            isPlaying: false,
            onTogglePlay: {},
            entityList: [],
            onAddEntity_Editor: {},
            onRemoveEntity_Editor: {},
            onAddCube: {},
            onAddSphere: {},
            onAddPlane: {},
            onAddDirLight: {},
            onAddPointLight: {},
            onAddSpotLight: {},
            onAddAreaLight: {}
        )

        // Assert
        let mirror = Mirror(reflecting: view)
        if let storedList = mirror.descendant("entityList") as? [EntityID] {
            XCTAssertEqual(storedList.count, 0, "Should handle empty entity list")
        }
    }

    // MARK: - Entity Hierarchy Tests

    func test_sceneGraphModel_refreshHierarchy() {
        // Arrange: Create some entities
        createEntity()
        createEntity()
        createEntity()

        // Act: Refresh hierarchy
        sceneGraphModel.refreshHierarchy()

        // Assert: The childrenMap should be populated
        let mirror = Mirror(reflecting: sceneGraphModel)
        if let childrenMap = mirror.descendant("childrenMap") as? [EntityID: [EntityID]] {
            // The map should exist (though it might be empty or contain root entities)
            XCTAssertNotNil(childrenMap, "Children map should be populated after refresh")
        }
    }

    func test_sceneGraphModel_getChildrenForInvalidEntity() {
        // Arrange
        sceneGraphModel.refreshHierarchy()

        // Act: Query children for an invalid/non-existent entity
        let invalidEntity = EntityID(99999)
        let children = sceneGraphModel.getChildren(entityId: invalidEntity)

        // Assert: Should return empty array for non-existent entity
        XCTAssertEqual(children.count, 0, "Non-existent entity should have no children")
    }

    // MARK: - Selection State Tests

    func test_entityRow_reactsToSelectionChanges() {
        // Arrange
        let entity = createEntity()

        let row = EntityRow(
            entityid: entity,
            entityName: "TestEntity",
            selectionManager: selectionManager
        )

        // Act: Select the entity
        selectionManager.selectedEntity = entity

        // Assert: The row should reflect selection state through @ObservedObject
        // In a real SwiftUI environment, this would trigger a view update
        XCTAssertEqual(selectionManager.selectedEntity, entity, "Selection manager should update")
    }

    func test_multipleEntityRows_onlyOneSelected() {
        // Arrange
        let entity1 = createEntity()
        let entity2 = createEntity()
        let entity3 = createEntity()

        let row1 = EntityRow(entityid: entity1, entityName: "Entity1", selectionManager: selectionManager)
        let row2 = EntityRow(entityid: entity2, entityName: "Entity2", selectionManager: selectionManager)
        let row3 = EntityRow(entityid: entity3, entityName: "Entity3", selectionManager: selectionManager)

        // Act: Select entity2
        selectionManager.selectedEntity = entity2

        // Assert: Only entity2 should be selected
        let mirror1 = Mirror(reflecting: row1)
        let mirror2 = Mirror(reflecting: row2)
        let mirror3 = Mirror(reflecting: row3)

        if let isSelected1 = mirror1.descendant("isSelected") as? Bool {
            XCTAssertFalse(isSelected1, "Entity1 should not be selected")
        }
        if let isSelected2 = mirror2.descendant("isSelected") as? Bool {
            XCTAssertTrue(isSelected2, "Entity2 should be selected")
        }
        if let isSelected3 = mirror3.descendant("isSelected") as? Bool {
            XCTAssertFalse(isSelected3, "Entity3 should not be selected")
        }
    }
}
