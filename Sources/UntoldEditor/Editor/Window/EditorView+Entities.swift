//
//  EditorView+Entities.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    func editor_addNewEntity() {
        removeGizmo()

        let entityId = createEntity()

        let name = generateEntityName()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)

        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    func editor_removeEntity() {
        guard let entityId = selectionManager.selectedEntity else {
            print("No entity is selected.") // Handle case where no entity is selected
            return
        }
        guard isDerivedAssetNode(entityId) == false else {
            print("⚠️ Asset nodes cannot be removed directly")
            return
        }

        destroyEntity(entityId: entityId)
        EditorSceneDirtyState.shared.markDirty()

        editor_entities = getAllGameEntities()
        activeEntity = .invalid
        selectionManager.selectedEntity = nil
        removeGizmo()
        sceneGraphModel.refreshHierarchy()
    }

    /// Delete a specific entity (used by the Scene Graph right-click menu).
    func editor_removeEntity(_ entityId: EntityID) {
        guard isDerivedAssetNode(entityId) == false else {
            print("⚠️ Asset nodes cannot be removed directly")
            return
        }

        destroyEntity(entityId: entityId)
        EditorSceneDirtyState.shared.markDirty()

        editor_entities = getAllGameEntities()
        if selectionManager.selectedEntity == entityId {
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
            removeGizmo()
        }
        sceneGraphModel.refreshHierarchy()
    }

    func editor_addName() {
        guard let entity = selectionManager.selectedEntity else {
            print("No entity is selected.") // Handle case where no entity is selected
            return
        }

        setEntityName(entityId: entity, name: getEntityName(entityId: entity))
    }

    func editor_addEntityWithAsset() {
        editor_addNewEntity()

        let filename = selectedAsset?.path.deletingPathExtension().lastPathComponent
        let withExtension = selectedAsset?.path.pathExtension

        guard let entityId = selectionManager.selectedEntity,
              let fname = filename,
              let ext = withExtension else { return }

        setEntityMeshAsync(entityId: entityId, filename: fname, withExtension: ext) { success in
            if success {
                print("✅ Asset loaded: \(fname).\(ext)")
            } else {
                print("⚠️ Failed to load asset, using fallback: \(fname).\(ext)")
            }
        }

        guard let camera = CameraSystem.shared.activeCamera, let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)

        forward *= -1.0

        let camPosition = cameraComponent.localPosition

        let spawnPosition = camPosition + forward * spawnDistance

        translateTo(entityId: selectionManager.selectedEntity!, position: spawnPosition)
    }

    // MARK: - Primitive Creation Functions

    func editor_createPrimitive(name: String, meshes: [Mesh]) {
        removeGizmo()

        let entityId = createEntity()
        EditorSceneDirtyState.shared.markDirty()
        // Append entity ID to make the name unique
        let uniqueName = "\(name)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        // Use setEntityMeshDirect which follows the same pattern as setEntityMesh
        setEntityMeshDirect(entityId: entityId, meshes: meshes, assetName: name)

        // Spawn in front of camera
        guard let camera = CameraSystem.shared.activeCamera, let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)
        forward *= -1.0
        let camPosition = cameraComponent.localPosition
        let spawnPosition = camPosition + forward * spawnDistance
        translateTo(entityId: entityId, position: simd_float3(0.0, 0.0, 0.0))

        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    func editor_createCylinder() {
        let meshes = BasicPrimitives.createCylinder()
        editor_createPrimitive(name: "Cylinder", meshes: meshes)
    }

    func editor_createCone() {
        let meshes = BasicPrimitives.createCone()
        editor_createPrimitive(name: "Cone", meshes: meshes)
    }

    // MARK: - Parenting Functions

    func editor_parentEntity(childId: EntityID, parentId: EntityID) {
        guard isDerivedAssetNode(childId) == false, isDerivedAssetNode(parentId) == false else {
            print("⚠️ Asset nodes cannot be reparented directly")
            return
        }

        // Ensure both entities exist and have ScenegraphComponent
        guard hasComponent(entityId: childId, componentType: ScenegraphComponent.self),
              hasComponent(entityId: parentId, componentType: ScenegraphComponent.self)
        else {
            print("⚠️ Cannot parent entity: missing ScenegraphComponent")
            return
        }

        // Ensure child has LocalTransformComponent
        guard hasComponent(entityId: childId, componentType: LocalTransformComponent.self) else {
            print("⚠️ Cannot parent entity: child missing LocalTransformComponent")
            return
        }

        // Ensure parent has LocalTransformComponent and WorldTransformComponent
        guard hasComponent(entityId: parentId, componentType: LocalTransformComponent.self),
              hasComponent(entityId: parentId, componentType: WorldTransformComponent.self)
        else {
            print("⚠️ Cannot parent entity: parent missing transform components")
            return
        }

        // Use the engine's setParent function
        setParent(childId: childId, parentId: parentId, offset: simd_float3(0, 0, 0))
        EditorSceneDirtyState.shared.markDirty()

        // Refresh the scene hierarchy to reflect the change
        sceneGraphModel.refreshHierarchy()

        print("✅ Parented entity \(childId) to \(parentId)")
    }

    func editor_unparentEntity(childId: EntityID) {
        guard isDerivedAssetNode(childId) == false else {
            print("⚠️ Asset nodes cannot be unparented directly")
            return
        }

        // Ensure entity has ScenegraphComponent
        guard hasComponent(entityId: childId, componentType: ScenegraphComponent.self) else {
            print("⚠️ Cannot unparent entity: missing ScenegraphComponent")
            return
        }

        // Ensure entity has LocalTransformComponent
        guard hasComponent(entityId: childId, componentType: LocalTransformComponent.self) else {
            print("⚠️ Cannot unparent entity: missing LocalTransformComponent")
            return
        }

        // Ensure entity has WorldTransformComponent
        guard hasComponent(entityId: childId, componentType: WorldTransformComponent.self) else {
            print("⚠️ Cannot unparent entity: missing WorldTransformComponent")
            return
        }

        // Check if entity actually has a parent
        guard let _ = getEntityParent(entityId: childId) else {
            print("⚠️ Entity has no parent to remove")
            return
        }

        // Use the engine's removeParent function
        removeParent(childId: childId)
        EditorSceneDirtyState.shared.markDirty()

        // Refresh the scene hierarchy to reflect the change
        sceneGraphModel.refreshHierarchy()

        print("✅ Unparented entity \(childId)")
    }
}
