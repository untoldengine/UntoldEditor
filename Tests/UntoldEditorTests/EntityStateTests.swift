//
//  EntityStateTests.swift
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

/// The hierarchy's eye and lock on the selection manager.
final class EntityStateTests: XCTestCase {
    private var selectionManager: SelectionManager!

    override func setUp() {
        super.setUp()
        scene = Scene()
        selectionManager = SelectionManager()
        activeEntity = .invalid
        gizmoActive = false
    }

    override func tearDown() {
        selectionManager = nil
        super.tearDown()
    }

    private func renderable(named name: String) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerComponent(entityId: entity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: entity, componentType: WorldTransformComponent.self)
        registerComponent(entityId: entity, componentType: ScenegraphComponent.self)
        registerComponent(entityId: entity, componentType: RenderComponent.self)
        return entity
    }

    private func isRendered(_ entity: EntityID) -> Bool {
        scene.get(component: RenderComponent.self, for: entity)?.isVisible ?? false
    }

    func test_setHidden_writesTheRenderFlagOfTheEntityAndItsChildren() {
        let parent = renderable(named: "Rig")
        let child = renderable(named: "Spot")
        setParent(childId: child, parentId: parent)

        selectionManager.setHidden(parent, true)

        XCTAssertTrue(selectionManager.isHidden(parent))
        XCTAssertFalse(selectionManager.isHidden(child), "The child's own eye stays on")
        XCTAssertTrue(selectionManager.isEffectivelyHidden(child), "but it is hidden through its parent")
        XCTAssertFalse(isRendered(parent))
        XCTAssertFalse(isRendered(child))

        selectionManager.setHidden(parent, false)

        XCTAssertTrue(isRendered(parent))
        XCTAssertTrue(isRendered(child))
    }

    func test_showingAChild_keepsItHiddenUnderAHiddenParent() {
        let parent = renderable(named: "Rig")
        let child = renderable(named: "Spot")
        setParent(childId: child, parentId: parent)

        selectionManager.setHidden(parent, true)
        selectionManager.setHidden(child, true)
        selectionManager.setHidden(child, false)
        XCTAssertFalse(isRendered(child))

        selectionManager.setHidden(parent, false)
        XCTAssertTrue(isRendered(child))
    }

    func test_showAllEntities_restoresEveryFlag() {
        let a = renderable(named: "A")
        let b = renderable(named: "B")
        selectionManager.setHidden(a, true)
        selectionManager.setHidden(b, true)

        selectionManager.showAllEntities()

        XCTAssertTrue(selectionManager.hiddenEntities.isEmpty)
        XCTAssertTrue(isRendered(a))
        XCTAssertTrue(isRendered(b))
    }

    func test_lockedOrHiddenEntity_staysSelectable_butGetsNoGizmo() {
        let entity = renderable(named: "Cube")

        selectionManager.setLocked(entity, true)
        selectionManager.selectEntity(entityId: entity)
        XCTAssertEqual(selectionManager.selectedEntity, entity, "The hierarchy can still inspect a locked entity")
        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertFalse(gizmoActive)
        XCTAssertFalse(selectionManager.canMove(entity))

        selectionManager.clearSelection()
        selectionManager.setLocked(entity, false)
        selectionManager.setHidden(entity, true)
        selectionManager.selectEntity(entityId: entity)
        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertFalse(selectionManager.canMove(entity))
    }

    func test_lockOnAParent_coversItsChildren() {
        let parent = renderable(named: "Rig")
        let child = renderable(named: "Spot")
        setParent(childId: child, parentId: parent)

        selectionManager.setLocked(parent, true)

        XCTAssertFalse(selectionManager.isLocked(child))
        XCTAssertTrue(selectionManager.isEffectivelyLocked(child))
        XCTAssertFalse(selectionManager.canMove(child))
    }

    func test_resetEntityStates_forgetsBoth() {
        let entity = renderable(named: "Cube")
        selectionManager.setHidden(entity, true)
        selectionManager.setLocked(entity, true)

        selectionManager.resetEntityStates()

        XCTAssertTrue(selectionManager.hiddenEntities.isEmpty)
        XCTAssertTrue(selectionManager.lockedEntities.isEmpty)
        XCTAssertTrue(selectionManager.canMove(entity))
    }
}
