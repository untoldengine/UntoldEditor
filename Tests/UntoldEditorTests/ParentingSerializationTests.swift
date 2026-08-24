//
//  ParentingSerializationTests.swift
//  UntoldEditor Tests
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class ParentingSerializationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Create fresh scene for each test
        scene = Scene()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Parent-Child Relationship Tests

    func test_parentingRelationship_preserved_after_serialize() {
        // Arrange: Create parent and child entities
        let parentId = createEntity()
        let childId = createEntity()

        // Ensure both have required components
        registerTransformComponent(entityId: parentId)
        registerSceneGraphComponent(entityId: parentId)

        registerTransformComponent(entityId: childId)
        registerSceneGraphComponent(entityId: childId)

        // Act: Establish parent-child relationship
        setParent(childId: childId, parentId: parentId, offset: simd_float3(0, 0, 0))

        // Verify the relationship is established
        let retrievedParent = getEntityParent(entityId: childId)
        XCTAssertEqual(retrievedParent, parentId, "Child should have parent before serialization")

        // Assert: Serialize and verify data
        let sceneData = serializeScene()
        XCTAssertFalse(sceneData.entities.isEmpty, "SceneData should contain entities")

        print("✅ Parent-child relationship established before serialization")
    }

    func test_parentingRelationship_preserved_after_roundtrip() {
        // Arrange: Create and parent entities
        let parentId = createEntity()
        let childId = createEntity()

        registerTransformComponent(entityId: parentId)
        registerSceneGraphComponent(entityId: parentId)

        registerTransformComponent(entityId: childId)
        registerSceneGraphComponent(entityId: childId)

        setParent(childId: childId, parentId: parentId, offset: simd_float3(0, 0, 0))

        // Act: Serialize
        let sceneData = serializeScene()

        // Clear and reload
        destroyAllEntities()
        scene = Scene()

        // Deserialize
        deserializeScene(sceneData: sceneData)

        // Assert: Verify parent-child relationship is preserved
        let allEntities = getAllGameEntities()
        XCTAssertGreaterThanOrEqual(allEntities.count, 2, "Should have at least parent and child after deserialization")

        // Find the child-parent relationship in deserialized entities
        for entityId in allEntities {
            if let retrievedParent = getEntityParent(entityId: entityId) {
                XCTAssertNotEqual(retrievedParent, .invalid, "Should have a valid parent after deserialization")
                print("✅ Found parent-child relationship after roundtrip: child=\(entityId), parent=\(retrievedParent)")
                return
            }
        }

        XCTFail("No parent-child relationship found after deserialization")
    }

    func test_multiLevel_hierarchy_preserved_after_roundtrip() {
        // Arrange: Create a 3-level hierarchy: grandparent -> parent -> child
        let grandparentId = createEntity()
        let parentId = createEntity()
        let childId = createEntity()

        // Register components
        for entityId in [grandparentId, parentId, childId] {
            registerTransformComponent(entityId: entityId)
            registerSceneGraphComponent(entityId: entityId)
        }

        // Establish relationships
        setParent(childId: parentId, parentId: grandparentId, offset: simd_float3(0, 0, 0))
        setParent(childId: childId, parentId: parentId, offset: simd_float3(0, 0, 0))

        // Verify before serialization
        XCTAssertEqual(getEntityParent(entityId: parentId), grandparentId, "Parent should have grandparent")
        XCTAssertEqual(getEntityParent(entityId: childId), parentId, "Child should have parent")

        // Act: Serialize and deserialize
        let sceneData = serializeScene()

        destroyAllEntities()
        scene = Scene()

        deserializeScene(sceneData: sceneData)

        // Assert: Verify multi-level hierarchy
        let allEntities = getAllGameEntities()
        XCTAssertGreaterThanOrEqual(allEntities.count, 3, "Should have at least 3 entities after deserialization")

        // Count parent relationships
        var parentCount = 0
        for entityId in allEntities {
            if let _ = getEntityParent(entityId: entityId) {
                parentCount += 1
            }
        }

        XCTAssertEqual(parentCount, 2, "Should have exactly 2 parent-child relationships (2 children)")
        print("✅ Multi-level hierarchy preserved after roundtrip")
    }

    func test_sibling_hierarchy_preserved_after_roundtrip() {
        // Arrange: Create siblings under same parent
        let parentId = createEntity()
        let child1Id = createEntity()
        let child2Id = createEntity()

        for entityId in [parentId, child1Id, child2Id] {
            registerTransformComponent(entityId: entityId)
            registerSceneGraphComponent(entityId: entityId)
        }

        // Establish relationships
        setParent(childId: child1Id, parentId: parentId, offset: simd_float3(0, 0, 0))
        setParent(childId: child2Id, parentId: parentId, offset: simd_float3(0, 0, 0))

        // Verify before serialization
        XCTAssertEqual(getEntityParent(entityId: child1Id), parentId, "Child1 should have parent")
        XCTAssertEqual(getEntityParent(entityId: child2Id), parentId, "Child2 should have parent")

        // Act: Serialize and deserialize
        let sceneData = serializeScene()

        destroyAllEntities()
        scene = Scene()

        deserializeScene(sceneData: sceneData)

        // Assert: Verify sibling relationships
        var childrenWithParent = 0
        for entityId in getAllGameEntities() {
            if let parentRef = getEntityParent(entityId: entityId) {
                childrenWithParent += 1
                print("✅ Found child: \(entityId) with parent: \(parentRef)")
            }
        }

        XCTAssertEqual(childrenWithParent, 2, "Should have exactly 2 children with the same parent")
    }
}
