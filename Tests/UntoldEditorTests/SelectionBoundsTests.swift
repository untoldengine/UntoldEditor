//
//  SelectionBoundsTests.swift
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

/// The selection's box in the world, which F frames.
final class SelectionBoundsTests: XCTestCase {
    private var originalScene: Scene!
    private var selectionManager: SelectionManager!

    override func setUp() {
        super.setUp()
        originalScene = scene
        scene = Scene()
        selectionManager = SelectionManager()
    }

    override func tearDown() {
        scene = originalScene
        originalScene = nil
        selectionManager = nil
        super.tearDown()
    }

    /// An entity that draws a box of `halfExtent` around its own origin.
    private func makeBox(name: String, halfExtent: Float = 0.5) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        registerComponent(entityId: entity, componentType: RenderComponent.self)
        scene.get(component: LocalTransformComponent.self, for: entity)?.boundingBox = (
            min: simd_float3(repeating: -halfExtent),
            max: simd_float3(repeating: halfExtent)
        )
        return entity
    }

    private func assertNearlyEqual(_ lhs: simd_float3, _ rhs: simd_float3, accuracy: Float = 0.001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
    }

    func test_nothingSelected_hasNoBounds() {
        XCTAssertNil(selectionManager.selectionBounds())
    }

    func test_theBounds_areWhereTheEntityIsInTheWorld() throws {
        let box = makeBox(name: "Box")
        translateTo(entityId: box, position: simd_float3(5, 2, -3))
        selectionManager.selectedEntity = box

        let bounds = try XCTUnwrap(selectionManager.selectionBounds())

        assertNearlyEqual(bounds.min, simd_float3(4.5, 1.5, -3.5))
        assertNearlyEqual(bounds.max, simd_float3(5.5, 2.5, -2.5))
    }

    func test_theBounds_followTheEntitysSize() throws {
        let box = makeBox(name: "Box")
        translateTo(entityId: box, position: simd_float3(1, 0, 0))
        scaleTo(entityId: box, scale: simd_float3(2, 4, 6))
        selectionManager.selectedEntity = box

        let bounds = try XCTUnwrap(selectionManager.selectionBounds())

        assertNearlyEqual(bounds.min, simd_float3(0, -2, -3))
        assertNearlyEqual(bounds.max, simd_float3(2, 2, 3))
    }

    func test_theBounds_followAParentThatMoved() throws {
        let parent = makeBox(name: "Parent")
        translateTo(entityId: parent, position: simd_float3(10, 0, 0))
        let child = makeBox(name: "Child")
        setParent(childId: child, parentId: parent)
        translateTo(entityId: child, position: simd_float3(0, 3, 0))
        selectionManager.selectedEntity = child

        let bounds = try XCTUnwrap(selectionManager.selectionBounds())

        assertNearlyEqual(bounds.min, simd_float3(9.5, 2.5, -0.5))
        assertNearlyEqual(bounds.max, simd_float3(10.5, 3.5, 0.5))
    }

    func test_aSelectionThatDrawsNothing_hasNoBounds_andIsFramedWhereItStands() throws {
        let light = createEntity()
        registerTransformComponent(entityId: light)
        registerSceneGraphComponent(entityId: light)
        translateTo(entityId: light, position: simd_float3(3, 4, 5))
        selectionManager.selectedEntity = light

        XCTAssertNil(selectionManager.selectionBounds())

        let framing = try XCTUnwrap(selectionManager.selectionFramingBounds())
        assertNearlyEqual(framing.min, simd_float3(2.5, 3.5, 4.5))
        assertNearlyEqual(framing.max, simd_float3(3.5, 4.5, 5.5))
    }

    func test_framing_takesTheBoundsOfWhatIsDrawn() throws {
        let box = makeBox(name: "Box", halfExtent: 2)
        translateTo(entityId: box, position: simd_float3(5, 0, 0))
        selectionManager.selectedEntity = box

        let framing = try XCTUnwrap(selectionManager.selectionFramingBounds())

        assertNearlyEqual(framing.min, simd_float3(3, -2, -2))
        assertNearlyEqual(framing.max, simd_float3(7, 2, 2))
    }

    func test_theBounds_holdTheChildrenOfTheSelection() throws {
        let parent = makeBox(name: "Parent")
        translateTo(entityId: parent, position: simd_float3(10, 0, 0))
        let child = makeBox(name: "Child")
        setParent(childId: child, parentId: parent)
        translateTo(entityId: child, position: simd_float3(0, 3, 0))
        selectionManager.selectedEntity = parent

        let bounds = try XCTUnwrap(selectionManager.selectionBounds())

        assertNearlyEqual(bounds.min, simd_float3(9.5, -0.5, -0.5))
        assertNearlyEqual(bounds.max, simd_float3(10.5, 3.5, 0.5))
    }
}
