//
//  SelectionManager.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import Foundation
import simd
import UntoldEngine

protocol SelectionDelegate: AnyObject {
    func didSelectEntity(_ entityId: EntityID)
    func didInspectEntity(_ entityId: EntityID)
    func resetActiveAxis()
}

class SceneGraphModel: ObservableObject {
    @Published var childrenMap: [EntityID: [EntityID]] = [:]

    func refreshHierarchy() {
        let allEntities = getAllGameEntities().filter { entityId in
            EditorAuthoringMode.sceneCompositionOnly == false || isDerivedAssetNode(entityId) == false
        }

        childrenMap = Dictionary(grouping: allEntities) { entityId in
            // If there's no ScenegraphComponent (e.g., camera), treat as root
            if !hasComponent(entityId: entityId, componentType: ScenegraphComponent.self) {
                return .invalid
            }
            return getEntityParent(entityId: entityId) ?? .invalid
        }
    }

    func getChildren(entityId: EntityID?) -> [EntityID] {
        childrenMap[entityId ?? .invalid] ?? []
    }
}

class SelectionManager: ObservableObject {
    @Published var selectedEntity: EntityID? = .invalid

    init() {}

    func selectEntity(entityId: EntityID) {
        selectEntity(entityId: editableAssetRootEntity(for: entityId), inspectEntityId: editableAssetRootEntity(for: entityId))
    }

    func inspectEntity(entityId: EntityID) {
        selectEntity(entityId: editableAssetRootEntity(for: entityId), inspectEntityId: entityId)
    }

    private func selectEntity(entityId: EntityID, inspectEntityId: EntityID) {
        selectedEntity = inspectEntityId

        guard canEditSceneTransform(entityId: entityId) else {
            activeEntity = .invalid
            gizmoActive = false
            removeGizmo()
            return
        }

        // Check if entity or any of its children have a render component
        let hasRenderCapability = entityOrChildrenHaveRenderComponent(entityId: entityId)

        if hasRenderCapability, hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) {
            activeEntity = entityId

            // Get bounding box from hierarchy (entity or children)
            let hierarchyBoundingBox = getHierarchyBoundingBox(entityId: entityId)
            updateBoundingBoxBuffer(min: hierarchyBoundingBox.min, max: hierarchyBoundingBox.max)

            createGizmo(name: "translateGizmo")
        } else {
            activeEntity = .invalid
        }
    }

    // Helper: Check if entity or any children have RenderComponent
    private func entityOrChildrenHaveRenderComponent(entityId: EntityID) -> Bool {
        // Check entity itself
        if hasComponent(entityId: entityId, componentType: RenderComponent.self) {
            return true
        }

        // Check children
        let children = getEntityChildren(parentId: entityId)
        for childId in children {
            if entityOrChildrenHaveRenderComponent(entityId: childId) {
                return true
            }
        }

        return false
    }

    // Helper: Get combined bounding box for entity hierarchy
    private func getHierarchyBoundingBox(entityId: EntityID) -> (min: simd_float3, max: simd_float3) {
        var minBounds = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        // Check entity itself
        if let localTransform = scene.get(component: LocalTransformComponent.self, for: entityId) {
            minBounds = simd_min(minBounds, localTransform.boundingBox.min)
            maxBounds = simd_max(maxBounds, localTransform.boundingBox.max)
        }

        accumulateChildBounds(parentId: entityId, minBounds: &minBounds, maxBounds: &maxBounds)

        return (min: minBounds, max: maxBounds)
    }

    private func accumulateChildBounds(parentId: EntityID, minBounds: inout simd_float3, maxBounds: inout simd_float3) {
        for childId in getEntityChildren(parentId: parentId) {
            if let childTransform = scene.get(component: LocalTransformComponent.self, for: childId) {
                minBounds = simd_min(minBounds, childTransform.boundingBox.min)
                maxBounds = simd_max(maxBounds, childTransform.boundingBox.max)
            }

            accumulateChildBounds(parentId: childId, minBounds: &minBounds, maxBounds: &maxBounds)
        }
    }
}
