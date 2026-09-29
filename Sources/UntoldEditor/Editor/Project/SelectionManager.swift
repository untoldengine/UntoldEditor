//
//  SelectionManager.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
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
    /// A click on empty viewport space: nothing is selected any more.
    func didClearSelection()
    func resetActiveAxis()
}

struct MeshInspectionSelection: Equatable {
    let transformEntityId: EntityID
    let entityId: EntityID
    let meshIndex: Int
}

class SceneGraphModel: ObservableObject {
    @Published var childrenMap: [EntityID: [EntityID]] = [:]
    /// Every node is collapsed by default; we track only the ones the user
    /// expanded. Opening a project therefore shows a tidy, collapsed tree.
    @Published private(set) var expandedEntityIds: Set<EntityID> = []

    func refreshHierarchy() {
        let allEntities = getAllGameEntities()

        childrenMap = Dictionary(grouping: allEntities) { entityId in
            // If there's no ScenegraphComponent (e.g., camera), treat as root
            if !hasComponent(entityId: entityId, componentType: ScenegraphComponent.self) {
                return .invalid
            }
            return getEntityParent(entityId: entityId) ?? .invalid
        }

        let currentEntityIds = Set(allEntities)
        expandedEntityIds = expandedEntityIds.intersection(currentEntityIds)
    }

    func getChildren(entityId: EntityID?) -> [EntityID] {
        childrenMap[entityId ?? .invalid] ?? []
    }

    func hasChildren(entityId: EntityID) -> Bool {
        getChildren(entityId: entityId).isEmpty == false
    }

    func isExpanded(entityId: EntityID) -> Bool {
        expandedEntityIds.contains(entityId)
    }

    /// Whether the entity is in the tree, for state that must not outlive it.
    func contains(_ entityId: EntityID) -> Bool {
        childrenMap.values.contains { $0.contains(entityId) }
    }

    func toggleExpanded(entityId: EntityID) {
        if expandedEntityIds.contains(entityId) {
            expandedEntityIds.remove(entityId)
        } else {
            expandedEntityIds.insert(entityId)
        }
    }
}

class SelectionManager: ObservableObject {
    @Published var selectedEntity: EntityID? = .invalid
    @Published var inspectedMesh: MeshInspectionSelection?
    /// True when the project itself is selected in the Scene Graph panel. Drives
    /// the right panel to show Environment/Effects instead of the Inspector.
    @Published var projectSelected: Bool = false
    /// True when the active scene node is selected. Drives the right panel to
    /// show the scene inspector.
    @Published var sceneSelected: Bool = false
    /// Entities whose eye is off in the hierarchy: hidden in the viewport with
    /// everything under them. Session-only; the scene file does not carry it yet.
    @Published private(set) var hiddenEntities: Set<EntityID> = []
    /// Entities the viewport must not select or move, with everything under
    /// them. Session-only, like `hiddenEntities`; the hierarchy can still inspect them.
    @Published private(set) var lockedEntities: Set<EntityID> = []
    /// The entity the Inspector keeps showing while the selection changes,
    /// from its pin. Nil follows the selection.
    @Published var pinnedInspection: EntityID?

    init() {}

    /// Select the project (deselects any entity/scene). The right panel switches
    /// to the Environment/Effects editors.
    func selectProject() {
        projectSelected = true
        sceneSelected = false
        inspectedMesh = nil
        selectedEntity = nil
    }

    /// Select the active scene (deselects project/entity). The right panel shows
    /// the scene inspector.
    func selectScene() {
        sceneSelected = true
        projectSelected = false
        inspectedMesh = nil
        selectedEntity = nil
    }

    /// Nothing selected: no entity, mesh, scene or project, and no gizmo in the
    /// viewport. What a click on empty viewport space leaves behind.
    func clearSelection() {
        projectSelected = false
        sceneSelected = false
        inspectedMesh = nil
        selectedEntity = nil
        activeEntity = .invalid
        gizmoActive = false
        removeGizmo()
    }

    func selectEntity(entityId: EntityID) {
        projectSelected = false
        sceneSelected = false
        inspectedMesh = nil
        let selectedEntityId = editableAssetRootEntity(for: entityId)
        selectEntity(entityId: selectedEntityId, inspectEntityId: selectedEntityId)
    }

    func inspectEntity(entityId: EntityID) {
        projectSelected = false
        sceneSelected = false
        inspectedMesh = nil
        selectEntity(entityId: sceneTransformEntity(for: entityId), inspectEntityId: entityId)
    }

    func inspectMesh(entityId: EntityID, meshIndex: Int) {
        projectSelected = false
        sceneSelected = false
        let transformEntityId = sceneTransformEntity(for: entityId)
        selectedEntity = entityId
        inspectedMesh = MeshInspectionSelection(
            transformEntityId: transformEntityId,
            entityId: entityId,
            meshIndex: meshIndex
        )

        guard canEditSceneTransform(entityId: transformEntityId), canMove(transformEntityId) else {
            activeEntity = .invalid
            gizmoActive = false
            removeGizmo()
            return
        }

        let hasRenderCapability = entityOrChildrenHaveRenderableRepresentation(entityId: transformEntityId)

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

            createGizmo(forTool: EditorViewportSettings.shared.tool)
        } else {
            activeEntity = .invalid
        }
    }

    private func selectEntity(entityId: EntityID, inspectEntityId: EntityID) {
        selectedEntity = inspectEntityId

        // A hidden or locked entity is inspected but never moved: no gizmo.
        guard canEditSceneTransform(entityId: entityId), canMove(entityId) else {
            activeEntity = .invalid
            gizmoActive = false
            removeGizmo()
            return
        }

        // Check if entity or any of its children have a render component. An entity written in
        // code that shows itself only through its editor representation (a spawn point's flag)
        // counts too: it is visible, so it can be moved.
        let hasRenderCapability = entityOrChildrenHaveRenderableRepresentation(entityId: entityId)
            || EditorRepresentationRenderer.drawing(for: entityId) != nil

        if hasRenderCapability, hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) {
            activeEntity = entityId

            let highlightBoundingBox = getRenderableHierarchyBoundingBox(entityId: entityId)
            updateBoundingBoxBuffer(min: highlightBoundingBox.min, max: highlightBoundingBox.max)

            createGizmo(forTool: EditorViewportSettings.shared.tool)
        } else {
            activeEntity = .invalid
        }
    }

    /// The world bounds of the selection's renderable hierarchy, for framing it.
    func selectionBounds() -> (min: simd_float3, max: simd_float3)? {
        guard let selected = selectedEntity, selected != .invalid else { return nil }
        let entity = sceneTransformEntity(for: selected)
        guard hasComponent(entityId: entity, componentType: LocalTransformComponent.self) else { return nil }
        return getRenderableHierarchyBoundingBox(entityId: entity)
    }

    // MARK: - Hidden and locked entities

    /// Whether the hierarchy's eye is off for this entity.
    func isHidden(_ entityId: EntityID) -> Bool {
        hiddenEntities.contains(entityId)
    }

    /// Whether the entity or an ancestor is hidden: what the viewport shows.
    func isEffectivelyHidden(_ entityId: EntityID?) -> Bool {
        hasAncestorOrSelf(entityId, in: hiddenEntities)
    }

    func isLocked(_ entityId: EntityID) -> Bool {
        lockedEntities.contains(entityId)
    }

    /// Whether the entity or an ancestor is locked.
    func isEffectivelyLocked(_ entityId: EntityID?) -> Bool {
        hasAncestorOrSelf(entityId, in: lockedEntities)
    }

    /// Whether the gizmo may move an entity: neither hidden nor locked, itself
    /// or through an ancestor.
    func canMove(_ entityId: EntityID) -> Bool {
        isEffectivelyHidden(entityId) == false && isEffectivelyLocked(entityId) == false
    }

    /// Hides or shows an entity in the viewport, with everything under it, by
    /// the render flag the passes, picking and shadows already honour. The flag
    /// is not saved with the scene, so this lasts the session.
    func setHidden(_ entityId: EntityID, _ hidden: Bool) {
        if hidden {
            hiddenEntities.insert(entityId)
        } else {
            hiddenEntities.remove(entityId)
        }
        applyVisibility(under: entityId)
        refreshGizmo()
    }

    func toggleHidden(_ entityId: EntityID) {
        setHidden(entityId, isHidden(entityId) == false)
    }

    /// Shows every hidden entity again.
    func showAllEntities() {
        let hidden = hiddenEntities
        hiddenEntities = []
        for entityId in hidden {
            applyVisibility(under: entityId)
        }
        refreshGizmo()
    }

    /// Locks or unlocks an entity: the viewport neither selects nor moves a
    /// locked entity or anything under it; the hierarchy can still inspect it.
    func setLocked(_ entityId: EntityID, _ locked: Bool) {
        if locked {
            lockedEntities.insert(entityId)
        } else {
            lockedEntities.remove(entityId)
        }
        refreshGizmo()
    }

    func toggleLocked(_ entityId: EntityID) {
        setLocked(entityId, isLocked(entityId) == false)
    }

    /// Forgets the hidden and locked entities and the Inspector's pin, for a
    /// cleared or reloaded scene.
    func resetEntityStates() {
        hiddenEntities = []
        lockedEntities = []
        pinnedInspection = nil
    }

    /// Pins the Inspector on an entity, or unpins it when it is the pinned one.
    func togglePinnedInspection(_ entityId: EntityID) {
        pinnedInspection = pinnedInspection == entityId ? nil : entityId
    }

    private func hasAncestorOrSelf(_ entityId: EntityID?, in set: Set<EntityID>) -> Bool {
        var current = entityId
        while let id = current, id != .invalid {
            if set.contains(id) {
                return true
            }
            current = getEntityParent(entityId: id)
        }
        return false
    }

    /// Writes the render flags under `entityId` from the hidden set: an entity
    /// shows when neither it nor an ancestor is hidden.
    private func applyVisibility(under entityId: EntityID) {
        applyVisibility(to: entityId, parentVisible: isEffectivelyHidden(getEntityParent(entityId: entityId)) == false)
    }

    private func applyVisibility(to entityId: EntityID, parentVisible: Bool) {
        let visible = parentVisible && hiddenEntities.contains(entityId) == false
        if let render = scene.get(component: RenderComponent.self, for: entityId) {
            render.isVisible = visible
        }
        for child in getEntityChildren(parentId: entityId) {
            applyVisibility(to: child, parentVisible: visible)
        }
    }

    /// Re-runs the current selection so the gizmo leaves an entity that was
    /// hidden or locked, comes back when it is shown or unlocked, and follows
    /// the tool when that changes.
    func refreshGizmo() {
        guard let selected = selectedEntity, selected != .invalid else { return }
        if let mesh = inspectedMesh {
            inspectMesh(entityId: mesh.entityId, meshIndex: mesh.meshIndex)
        } else {
            selectEntity(entityId: sceneTransformEntity(for: selected), inspectEntityId: selected)
        }
    }

    // Helper: Check if the entity or any child has something drawn in the viewport.
    private func entityOrChildrenHaveRenderableRepresentation(entityId: EntityID) -> Bool {
        // Check entity itself
        if hasComponent(entityId: entityId, componentType: RenderComponent.self)
            || hasComponent(entityId: entityId, componentType: GaussianComponent.self)
        {
            return true
        }

        // Check children
        let children = getEntityChildren(parentId: entityId)
        for childId in children {
            if entityOrChildrenHaveRenderableRepresentation(entityId: childId) {
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

        if hasComponent(entityId: entityId, componentType: RenderComponent.self)
            || hasComponent(entityId: entityId, componentType: GaussianComponent.self)
        {
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
    let bounds = mesh.localBounds
    return (min: simd_min(bounds.min, bounds.max), max: simd_max(bounds.min, bounds.max))
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
