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

private func localMatrix(for transform: LocalTransformComponent) -> simd_float4x4 {
    let translation = matrix4x4Translation(
        transform.position.x,
        transform.position.y,
        transform.position.z
    )
    let rotation = getMatrix4x4FromQuaternion(q: transform.rotation)
    let scale = matrix4x4Scale(
        transform.scale.x,
        transform.scale.y,
        transform.scale.z
    )
    return translation * rotation * scale
}

private func boundingBoxCorners(min: simd_float3, max: simd_float3) -> [simd_float3] {
    [
        simd_float3(min.x, min.y, min.z),
        simd_float3(min.x, min.y, max.z),
        simd_float3(min.x, max.y, min.z),
        simd_float3(min.x, max.y, max.z),
        simd_float3(max.x, min.y, min.z),
        simd_float3(max.x, min.y, max.z),
        simd_float3(max.x, max.y, min.z),
        simd_float3(max.x, max.y, max.z),
    ]
}

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

            let highlightBoundingBox = getRenderableHierarchyBoundingBox(entityId: entityId)
            updateBoundingBoxBuffer(min: highlightBoundingBox.min, max: highlightBoundingBox.max)

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
        var foundBounds = false

        accumulateBoundsInRootSpace(
            entityId: entityId,
            localToRoot: matrix_identity_float4x4,
            minBounds: &minBounds,
            maxBounds: &maxBounds,
            foundBounds: &foundBounds
        )

        if foundBounds == false {
            return (min: .zero, max: .zero)
        }

        return (min: minBounds, max: maxBounds)
    }

    private func getRenderableHierarchyBoundingBox(entityId: EntityID) -> (min: simd_float3, max: simd_float3) {
        var minBounds = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var foundRenderableBounds = false

        accumulateRenderableBoundsInRootSpace(
            entityId: entityId,
            localToRoot: matrix_identity_float4x4,
            minBounds: &minBounds,
            maxBounds: &maxBounds,
            foundBounds: &foundRenderableBounds
        )

        if foundRenderableBounds {
            return (min: minBounds, max: maxBounds)
        }

        return getHierarchyBoundingBox(entityId: entityId)
    }

    private func accumulateBoundsInRootSpace(
        entityId: EntityID,
        localToRoot: simd_float4x4,
        minBounds: inout simd_float3,
        maxBounds: inout simd_float3,
        foundBounds: inout Bool
    ) {
        guard let localTransform = scene.get(component: LocalTransformComponent.self, for: entityId) else {
            for childId in getEntityChildren(parentId: entityId) {
                accumulateBoundsInRootSpace(
                    entityId: childId,
                    localToRoot: localToRoot,
                    minBounds: &minBounds,
                    maxBounds: &maxBounds,
                    foundBounds: &foundBounds
                )
            }
            return
        }

        for corner in boundingBoxCorners(min: localTransform.boundingBox.min, max: localTransform.boundingBox.max) {
            let transformed = simd_mul(localToRoot, simd_float4(corner, 1.0))
            let point = simd_float3(transformed.x, transformed.y, transformed.z)
            minBounds = simd_min(minBounds, point)
            maxBounds = simd_max(maxBounds, point)
            foundBounds = true
        }

        let childLocalToRoot = simd_mul(localToRoot, localMatrix(for: localTransform))
        for childId in getEntityChildren(parentId: entityId) {
            accumulateBoundsInRootSpace(
                entityId: childId,
                localToRoot: childLocalToRoot,
                minBounds: &minBounds,
                maxBounds: &maxBounds,
                foundBounds: &foundBounds
            )
        }
    }

    private func accumulateRenderableBoundsInRootSpace(
        entityId: EntityID,
        localToRoot: simd_float4x4,
        minBounds: inout simd_float3,
        maxBounds: inout simd_float3,
        foundBounds: inout Bool
    ) {
        guard let localTransform = scene.get(component: LocalTransformComponent.self, for: entityId) else {
            for childId in getEntityChildren(parentId: entityId) {
                accumulateRenderableBoundsInRootSpace(
                    entityId: childId,
                    localToRoot: localToRoot,
                    minBounds: &minBounds,
                    maxBounds: &maxBounds,
                    foundBounds: &foundBounds
                )
            }
            return
        }

        if hasComponent(entityId: entityId, componentType: RenderComponent.self) {
            for corner in boundingBoxCorners(min: localTransform.boundingBox.min, max: localTransform.boundingBox.max) {
                let transformed = simd_mul(localToRoot, simd_float4(corner, 1.0))
                let point = simd_float3(transformed.x, transformed.y, transformed.z)
                minBounds = simd_min(minBounds, point)
                maxBounds = simd_max(maxBounds, point)
                foundBounds = true
            }
        }

        let childLocalToRoot = simd_mul(localToRoot, localMatrix(for: localTransform))
        for childId in getEntityChildren(parentId: entityId) {
            accumulateRenderableBoundsInRootSpace(
                entityId: childId,
                localToRoot: childLocalToRoot,
                minBounds: &minBounds,
                maxBounds: &maxBounds,
                foundBounds: &foundBounds
            )
        }
    }
}
