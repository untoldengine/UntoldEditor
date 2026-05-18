//
//  AssetNodeEditingPolicyTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class AssetNodeEditingPolicyTests: XCTestCase {
    private var selectionManager: SelectionManager!
    private var sceneGraphModel: SceneGraphModel!

    override func setUp() {
        super.setUp()
        scene = Scene()
        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
    }

    override func tearDown() {
        sceneGraphModel = nil
        selectionManager = nil
        super.tearDown()
    }

    private func createTransformEntity(name: String) -> EntityID {
        let entityId = createEntity()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)
        return entityId
    }

    private func markAssetRoot(_ entityId: EntityID) {
        registerComponent(entityId: entityId, componentType: AssetInstanceComponent.self)
        let assetInstance = scene.get(component: AssetInstanceComponent.self, for: entityId)
        assetInstance?.assetURL = URL(fileURLWithPath: "/tmp/room.untold")
        assetInstance?.assetName = "room"
        assetInstance?.importMode = "preserveHierarchy"
    }

    private func markDerived(_ entityId: EntityID, rootId: EntityID, nodePath: String) {
        registerComponent(entityId: entityId, componentType: DerivedAssetNodeComponent.self)
        let derived = scene.get(component: DerivedAssetNodeComponent.self, for: entityId)
        derived?.assetRootEntityId = rootId
        derived?.nodePath = nodePath
    }

    func testDerivedAssetNodeCanBeSelectedAsTransformTarget() {
        let rootId = createTransformEntity(name: "Room")
        markAssetRoot(rootId)

        let chairId = createTransformEntity(name: "Chair")
        setParent(childId: chairId, parentId: rootId)
        markDerived(chairId, rootId: rootId, nodePath: "Room/Chair")

        XCTAssertEqual(assetRootEntityId(for: chairId), rootId)
        XCTAssertEqual(sceneTransformEntity(for: chairId), chairId)
        XCTAssertTrue(canEditSceneTransform(entityId: chairId))
        XCTAssertEqual(selectableTransformEntity(for: chairId), chairId)
    }

    func testNormalSelectionTargetsAssetRootForDerivedNode() {
        let rootId = createTransformEntity(name: "Room")
        markAssetRoot(rootId)

        let chairId = createTransformEntity(name: "Chair")
        setParent(childId: chairId, parentId: rootId)
        markDerived(chairId, rootId: rootId, nodePath: "Room/Chair")

        selectionManager.selectEntity(entityId: chairId)

        XCTAssertEqual(selectionManager.selectedEntity, rootId)
    }

    func testHierarchyInspectionTargetsExactDerivedNode() {
        let rootId = createTransformEntity(name: "Room")
        markAssetRoot(rootId)

        let chairId = createTransformEntity(name: "Chair")
        setParent(childId: chairId, parentId: rootId)
        markDerived(chairId, rootId: rootId, nodePath: "Room/Chair")

        selectionManager.inspectEntity(entityId: chairId)

        XCTAssertEqual(selectionManager.selectedEntity, chairId)
    }

    func testSceneHierarchyIncludesDerivedAssetNodes() {
        let rootId = createTransformEntity(name: "Room")
        markAssetRoot(rootId)

        let chairId = createTransformEntity(name: "Chair")
        setParent(childId: chairId, parentId: rootId)
        markDerived(chairId, rootId: rootId, nodePath: "Room/Chair")

        sceneGraphModel.refreshHierarchy()

        XCTAssertTrue(sceneGraphModel.getChildren(entityId: nil).contains(rootId))
        XCTAssertTrue(sceneGraphModel.getChildren(entityId: rootId).contains(chairId))
    }

    func testSceneCompositionInspectorShowsDerivedTransformComponent() {
        let rootId = createTransformEntity(name: "Room")
        markAssetRoot(rootId)

        let chairId = createTransformEntity(name: "Chair")
        setParent(childId: chairId, parentId: rootId)
        markDerived(chairId, rootId: rootId, nodePath: "Room/Chair")

        XCTAssertTrue(canShowComponentInInspector(componentType: LocalTransformComponent.self, for: chairId))
        XCTAssertTrue(canShowComponentInInspector(componentType: RenderComponent.self, for: chairId))
    }

    func testSerializeSceneStoresNestedDerivedTransformOverride() {
        let rootId = createTransformEntity(name: "Room")
        markAssetRoot(rootId)

        let groupId = createTransformEntity(name: "Furniture")
        setParent(childId: groupId, parentId: rootId)
        markDerived(groupId, rootId: rootId, nodePath: "Room/Furniture")

        let chairId = createTransformEntity(name: "Chair")
        setParent(childId: chairId, parentId: groupId)
        markDerived(chairId, rootId: rootId, nodePath: "Room/Furniture/Chair")
        translateTo(entityId: chairId, position: simd_float3(1.0, 2.0, 3.0))
        scaleTo(entityId: chairId, scale: simd_float3(1.5, 1.5, 1.5))

        let sceneData = serializeScene()
        let overrides = sceneData.entities.first?.assetInstance?.overrides ?? []
        let chairOverride = overrides.first { $0.nodePath == "Room/Furniture/Chair" }

        XCTAssertEqual(sceneData.entities.count, 1)
        XCTAssertNotNil(chairOverride)
        XCTAssertEqual(chairOverride?.transform?.position, simd_float3(1.0, 2.0, 3.0))
        XCTAssertEqual(chairOverride?.transform?.scale, simd_float3(1.5, 1.5, 1.5))
    }
}
