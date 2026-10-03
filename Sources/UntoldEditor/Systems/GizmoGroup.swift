//
//  GizmoGroup.swift
//  UntoldEditor
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

// With several entities selected one gizmo stands in the middle of them and
// works on all: a move carries each by the same distance, a turn takes them
// round the gizmo, and a scale grows them and their distance from it.

/// The entities the gizmo moves when several are selected. The selection
/// sets it; empty, the gizmo moves the active entity alone.
var gizmoTargets: [EntityID] = []

/// Where an entity stood and how big it was when a drag began. A drag works
/// from there, so what it did so far never adds up with what it does next.
struct GizmoTargetStart {
    let entityId: EntityID
    let localPosition: simd_float3
    let worldPosition: simd_float3
    let scale: simd_float3

    init(entityId: EntityID) {
        self.entityId = entityId
        localPosition = getLocalPosition(entityId: entityId)
        worldPosition = hasComponent(entityId: entityId, componentType: WorldTransformComponent.self)
            ? getPosition(entityId: entityId)
            : getLocalPosition(entityId: entityId)
        scale = getScale(entityId: entityId)
    }
}

/// The entities a drag of the gizmo works on: the active one, or with several
/// selected every one of them that is still in the scene.
func gizmoTransformTargets() -> [EntityID] {
    guard activeEntity != .invalid else {
        return []
    }
    let several = gizmoTargets.filter { canEditSceneTransform(entityId: $0) }
    guard several.count > 1, several.contains(activeEntity) else {
        return [activeEntity]
    }
    return several
}

/// Where the gizmo stands for several entities: the middle of the box, along
/// the world's axes, around everything they draw. One that draws nothing
/// counts as the point where it stands.
func gizmoGroupAnchorWorldPosition(of targets: [EntityID]) -> simd_float3? {
    var minimum = simd_float3(repeating: .greatestFiniteMagnitude)
    var maximum = simd_float3(repeating: -.greatestFiniteMagnitude)
    var found = false

    for target in targets {
        if let box = worldBoundsOfRenderableHierarchy(entityId: target) {
            minimum = simd_min(minimum, box.min)
            maximum = simd_max(maximum, box.max)
            found = true
        } else if hasComponent(entityId: target, componentType: WorldTransformComponent.self) {
            let position = getPosition(entityId: target)
            minimum = simd_min(minimum, position)
            maximum = simd_max(maximum, position)
            found = true
        }
    }
    return found ? (minimum + maximum) * 0.5 : nil
}

/// Puts the gizmo back in the middle of the entities it moves, which a turn
/// or a scale may have shifted. With one entity the gizmo stays where it is.
func reanchorGizmoOnTargets() {
    let targets = gizmoTransformTargets()
    guard gizmoActive, parentEntityIdGizmo != .invalid, targets.count > 1,
          let anchor = gizmoGroupAnchorWorldPosition(of: targets)
    else {
        return
    }
    translateTo(entityId: parentEntityIdGizmo, position: anchor)
}

/// A point of the world as the entity's parent measures it, which is how the
/// entity's position is kept.
func localPosition(ofWorld position: simd_float3, for entityId: EntityID) -> simd_float3 {
    guard let parent = parentInSceneGraph(of: entityId),
          let parentSpace = scene.get(component: WorldTransformComponent.self, for: parent)?.space
    else {
        return position
    }

    let determinant = simd_determinant(parentSpace)
    guard determinant.isFinite, abs(determinant) > 1e-12 else {
        // A parent squashed flat has no way back: the entity stays where it is.
        return getLocalPosition(entityId: entityId)
    }
    let local = simd_mul(parentSpace.inverse, simd_float4(position, 1))
    return simd_float3(local.x, local.y, local.z)
}

// MARK: - Moving

/// Moves the targets of a drag to where they stood plus `translation`, a
/// movement in world space that each takes in its parent's measure.
func translateGizmoTargets(_ starts: [GizmoTargetStart], byWorld translation: simd_float3) {
    for start in starts {
        let local = localTranslation(ofWorld: translation, for: start.entityId)
        translateTo(entityId: start.entityId, position: start.localPosition + local)
    }
}

/// Moves what the gizmo works on by `translation`, from where it is now.
func applyGizmoTranslation(byWorld translation: simd_float3) {
    for target in gizmoTransformTargets() {
        translateBy(entityId: target, position: localTranslation(ofWorld: translation, for: target))
    }
}

// MARK: - Turning

/// Turns the targets together by `degrees` about `axis`, the world's, through
/// `pivot`: each goes round the pivot and turns by the same angle itself.
func rotateGizmoTargets(_ targets: [EntityID], around pivot: simd_float3, axis: simd_float3, degrees: Float) {
    guard degrees.isFinite, degrees != 0, simd_length_squared(axis) > 0.0001 else {
        return
    }
    let turn = simd_quatf(angle: degreesToRadians(degrees: degrees), axis: simd_normalize(axis))

    // Where each one goes is taken before any of them moves.
    let destinations = targets.map { target -> simd_float3 in
        let position = hasComponent(entityId: target, componentType: WorldTransformComponent.self)
            ? getPosition(entityId: target)
            : pivot
        return pivot + simd_act(turn, position - pivot)
    }
    for (target, destination) in zip(targets, destinations) {
        applyGizmoRotationDelta(entityId: target, axis: axis, degrees: degrees)
        translateTo(entityId: target, position: localPosition(ofWorld: destination, for: target))
    }
}

/// Turns what the gizmo works on: the active entity about itself, as ever,
/// or several entities round the gizmo.
func applyGizmoRotation(axis: simd_float3, degrees: Float) {
    let targets = gizmoTransformTargets()
    guard targets.count > 1 else {
        applyGizmoRotationDelta(entityId: activeEntity, axis: axis, degrees: degrees)
        return
    }
    rotateGizmoTargets(targets, around: gizmoRootWorldPosition(), axis: axis, degrees: degrees)
}

// MARK: - Scaling

/// The smallest a scale may get, as the engine keeps it for one entity.
let gizmoMinimumScale: Float = 0.01

/// How much several entities grow for a drag of `amount` along the gizmo's
/// axis: a drag of one unit doubles them, and one back by half halves them.
func gizmoGroupScaleFactor(forAmount amount: Float) -> Float {
    guard amount.isFinite else {
        return 1
    }
    return max(gizmoMinimumScale, 1 + amount)
}

/// The scale of an entity grown by `factor` along `axis`, the world's. An
/// entity keeps its scale along its own axes, so each of them takes the
/// share of the growth that the world's axis has along it.
func gizmoScale(_ scale: simd_float3, of entityId: EntityID, grownBy factor: Float, along axis: simd_float3) -> simd_float3 {
    guard let local = scene.get(component: LocalTransformComponent.self, for: entityId) else {
        return scale
    }
    let axisForParent = localAxis(ofWorld: axis, for: entityId)
    let toOwnSpace = simd_transpose(transformQuaternionToMatrix3x3(q: local.rotation))
    let own = simd_mul(toOwnSpace, axisForParent)
    let length = simd_length(own)
    guard length.isFinite, length > 0.0001 else {
        return scale
    }

    let share = simd_abs(own / length)
    let grown = scale * (simd_float3(repeating: 1) + share * (factor - 1))
    return simd_max(grown, simd_float3(repeating: gizmoMinimumScale))
}

/// Scales the targets together by `factor` along `axis`, the world's, from
/// `pivot`: each grows along the axis, and so does its distance from the
/// pivot. A light keeps its size and only moves.
func scaleGizmoTargets(_ starts: [GizmoTargetStart], from pivot: simd_float3, axis: simd_float3, factor: Float) {
    guard factor.isFinite, simd_length_squared(axis) > 0.0001 else {
        return
    }
    let direction = simd_normalize(axis)

    for start in starts {
        let offset = start.worldPosition - pivot
        let destination = start.worldPosition + direction * ((factor - 1) * simd_dot(offset, direction))
        translateTo(entityId: start.entityId, position: localPosition(ofWorld: destination, for: start.entityId))

        if hasComponent(entityId: start.entityId, componentType: LightComponent.self) == false {
            scaleTo(
                entityId: start.entityId,
                scale: gizmoScale(start.scale, of: start.entityId, grownBy: factor, along: direction)
            )
        }
    }
}

/// Scales what the gizmo works on by `amount` more along `axis`, the world
/// direction of the `handle` dragged: the active entity as ever, or several
/// entities from the gizmo.
func applyGizmoScale(axis: simd_float3, amount: Float, handle: TransformAxis) {
    let targets = gizmoTransformTargets()
    guard targets.count > 1 else {
        if hasComponent(entityId: activeEntity, componentType: LightComponent.self) {
            // The engine takes the axis as which components of the scale to change.
            handleLightScaleInput(projectedAmount: amount, axis: worldDirection(for: handle))
        } else {
            // The engine takes the axis as the entity's parent sees it.
            applyWorldSpaceScaleDelta(entityId: activeEntity, worldAxis: localAxis(ofWorld: axis, for: activeEntity), projectedAmount: amount)
        }
        return
    }
    scaleGizmoTargets(
        targets.map(GizmoTargetStart.init(entityId:)),
        from: gizmoRootWorldPosition(),
        axis: axis,
        factor: gizmoGroupScaleFactor(forAmount: amount)
    )
}
