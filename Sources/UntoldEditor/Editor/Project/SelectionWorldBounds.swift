//
//  SelectionWorldBounds.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
import UntoldEngine

/// The box along the world's axes around what an entity and everything under
/// it draw: each one's own bounds, carried into the world by the transform the
/// renderer draws it with. Nil when nothing under the entity draws anything.
func worldBoundsOfRenderableHierarchy(entityId: EntityID) -> (min: simd_float3, max: simd_float3)? {
    var minimum = simd_float3(repeating: .greatestFiniteMagnitude)
    var maximum = simd_float3(repeating: -.greatestFiniteMagnitude)
    var found = false
    var pending = [entityId]
    var visited = 0

    // The depth of a scene is small; the count only guards against a cycle.
    while let current = pending.popLast(), visited < 100_000 {
        visited += 1
        pending.append(contentsOf: getEntityChildren(parentId: current))

        guard hasComponent(entityId: current, componentType: RenderComponent.self)
            || hasComponent(entityId: current, componentType: GaussianComponent.self),
            let local = scene.get(component: LocalTransformComponent.self, for: current),
            let world = scene.get(component: WorldTransformComponent.self, for: current)
        else {
            continue
        }

        let box = local.boundingBox
        for corner in 0 ..< 8 {
            let point = simd_float4(
                corner & 1 == 0 ? box.min.x : box.max.x,
                corner & 2 == 0 ? box.min.y : box.max.y,
                corner & 4 == 0 ? box.min.z : box.max.z,
                1
            )
            let moved = simd_mul(world.space, point)
            let position = simd_float3(moved.x, moved.y, moved.z)
            guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
                continue
            }
            minimum = simd_min(minimum, position)
            maximum = simd_max(maximum, position)
            found = true
        }
    }

    return found ? (minimum, maximum) : nil
}
