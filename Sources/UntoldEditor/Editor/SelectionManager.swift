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
    func didInspectMesh(_ entityId: EntityID, meshIndex: Int)
    func resetActiveAxis()
}

struct MeshInspectionSelection: Equatable {
    let transformEntityId: EntityID
    let entityId: EntityID
    let meshIndex: Int
}

class SceneGraphModel: ObservableObject {
    @Published var childrenMap: [EntityID: [EntityID]] = [:]

    func refreshHierarchy() {
        let allEntities = getAllGameEntities()

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
    @Published var inspectedMesh: MeshInspectionSelection?

    init() {}

    func selectEntity(entityId: EntityID) {
        inspectedMesh = nil
        let selectedEntityId = editableAssetRootEntity(for: entityId)
        selectEntity(entityId: selectedEntityId, inspectEntityId: selectedEntityId)
    }

    func inspectEntity(entityId: EntityID) {
        inspectedMesh = nil
        selectEntity(entityId: sceneTransformEntity(for: entityId), inspectEntityId: entityId)
    }

    func inspectMesh(entityId: EntityID, meshIndex: Int) {
        let transformEntityId = sceneTransformEntity(for: entityId)
        selectedEntity = entityId
        inspectedMesh = MeshInspectionSelection(
            transformEntityId: transformEntityId,
            entityId: entityId,
            meshIndex: meshIndex
        )

        guard canEditSceneTransform(entityId: transformEntityId) else {
            activeEntity = .invalid
            gizmoActive = false
            removeGizmo()
            return
        }

        let hasRenderCapability = entityOrChildrenHaveRenderComponent(entityId: transformEntityId)

        if hasRenderCapability, hasComponent(entityId: transformEntityId, componentType: LocalTransformComponent.self) {
            activeEntity = transformEntityId

            if let highlightBoundingBox = meshBoundsInAncestorSpace(
                entityId: entityId,
                meshIndex: meshIndex,
                ancestorId: transformEntityId
            ) {
                updateBoundingBoxBuffer(min: highlightBoundingBox.min, max: highlightBoundingBox.max)
            } else {
                let highlightBoundingBox = getRenderableHierarchyBoundingBox(entityId: transformEntityId)
                updateBoundingBoxBuffer(min: highlightBoundingBox.min, max: highlightBoundingBox.max)
            }

            createGizmo(name: "translateGizmo")
        } else {
            activeEntity = .invalid
        }
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

func meshLocalBounds(_ mesh: Mesh) -> (min: simd_float3, max: simd_float3) {
    let bounds = mesh.modelMDLMesh.boundingBox
    let minBounds = simd_float3(bounds.minBounds.x, bounds.minBounds.y, bounds.minBounds.z)
    let maxBounds = simd_float3(bounds.maxBounds.x, bounds.maxBounds.y, bounds.maxBounds.z)
    return (min: simd_min(minBounds, maxBounds), max: simd_max(minBounds, maxBounds))
}

func transformedBoundingBox(
    min: simd_float3,
    max: simd_float3,
    transform: simd_float4x4
) -> (min: simd_float3, max: simd_float3) {
    var minBounds = simd_float3(
        Float.greatestFiniteMagnitude,
        Float.greatestFiniteMagnitude,
        Float.greatestFiniteMagnitude
    )
    var maxBounds = simd_float3(
        -Float.greatestFiniteMagnitude,
        -Float.greatestFiniteMagnitude,
        -Float.greatestFiniteMagnitude
    )

    for corner in boundingBoxCorners(min: min, max: max) {
        let transformed = simd_mul(transform, simd_float4(corner, 1.0))
        let point = simd_float3(transformed.x, transformed.y, transformed.z)
        minBounds = simd_min(minBounds, point)
        maxBounds = simd_max(maxBounds, point)
    }

    return (min: minBounds, max: maxBounds)
}

func localTransformMatrix(from entityId: EntityID, to ancestorId: EntityID) -> simd_float4x4? {
    guard entityId != .invalid, ancestorId != .invalid else { return nil }

    var lineage: [EntityID] = []
    var currentEntity: EntityID? = entityId

    while let current = currentEntity, current != ancestorId {
        lineage.append(current)
        currentEntity = getEntityParent(entityId: current)
    }

    guard currentEntity == ancestorId else { return nil }

    var transform = matrix_identity_float4x4
    for entity in lineage.reversed() {
        guard let localTransform = scene.get(component: LocalTransformComponent.self, for: entity) else {
            return nil
        }
        transform = simd_mul(transform, localMatrix(for: localTransform))
    }

    return transform
}

func meshBoundsInAncestorSpace(
    entityId: EntityID,
    meshIndex: Int,
    ancestorId: EntityID
) -> (min: simd_float3, max: simd_float3)? {
    guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId),
          renderComponent.mesh.indices.contains(meshIndex),
          let entityToAncestor = localTransformMatrix(from: entityId, to: ancestorId)
    else {
        return nil
    }

    let mesh = renderComponent.mesh[meshIndex]
    let localBounds = meshLocalBounds(mesh)
    let meshToAncestor = simd_mul(entityToAncestor, mesh.localSpace)
    return transformedBoundingBox(min: localBounds.min, max: localBounds.max, transform: meshToAncestor)
}

func pickMeshIndexForEntity(
    entityId: EntityID,
    rayOrigin: simd_float3,
    rayDirection: simd_float3
) -> Int? {
    guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId),
          let worldTransform = scene.get(component: WorldTransformComponent.self, for: entityId)
    else {
        return nil
    }

    let rayLengthSquared = simd_length_squared(rayDirection)
    guard rayLengthSquared.isFinite, rayLengthSquared > Float.ulpOfOne else { return nil }
    let normalizedRayDirection = rayDirection / sqrt(rayLengthSquared)

    var bestMeshIndex: Int?
    var bestDistance = Float.greatestFiniteMagnitude

    for (meshIndex, mesh) in renderComponent.mesh.enumerated() {
        let localBounds = meshLocalBounds(mesh)
        let meshWorldTransform = simd_mul(worldTransform.space, mesh.localSpace)
        let worldBounds = transformedBoundingBox(
            min: localBounds.min,
            max: localBounds.max,
            transform: meshWorldTransform
        )

        guard let distance = rayAABBIntersectionDistance(
            rayOrigin: rayOrigin,
            rayDirection: normalizedRayDirection,
            minBounds: worldBounds.min,
            maxBounds: worldBounds.max
        ) else {
            continue
        }

        if distance < bestDistance {
            bestDistance = distance
            bestMeshIndex = meshIndex
        }
    }

    return bestMeshIndex
}

private func rayAABBIntersectionDistance(
    rayOrigin: simd_float3,
    rayDirection: simd_float3,
    minBounds: simd_float3,
    maxBounds: simd_float3
) -> Float? {
    var tMin = -Float.greatestFiniteMagnitude
    var tMax = Float.greatestFiniteMagnitude

    for axis in 0 ..< 3 {
        let origin = rayOrigin[axis]
        let direction = rayDirection[axis]
        let minValue = minBounds[axis]
        let maxValue = maxBounds[axis]

        if abs(direction) < Float.ulpOfOne {
            if origin < minValue || origin > maxValue {
                return nil
            }
            continue
        }

        let invDirection = 1.0 / direction
        var t0 = (minValue - origin) * invDirection
        var t1 = (maxValue - origin) * invDirection

        if t0 > t1 {
            swap(&t0, &t1)
        }

        tMin = max(tMin, t0)
        tMax = min(tMax, t1)

        if tMax < tMin {
            return nil
        }
    }

    if tMax < 0 {
        return nil
    }

    return max(tMin, 0.0)
}
