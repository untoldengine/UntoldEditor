//
//  EditorRepresentationHandles.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import simd
import UntoldComponentKit
import UntoldEngine

/// The draggable points of an entity written in code: each is the value of one of its
/// `SIMD3<Float>` properties, named by `.handles` in the entity's editor representation.
///
/// A click on one selects its entity and puts the move gizmo on the point instead of on the
/// entity. Dragging the gizmo writes the property, through the same call the Inspector uses,
/// so the entity rebuilds as it does after an Inspector edit, and the drag is one undo step.
/// The selection lasts while the entity stays the active one; clicking anything else drops it.
enum EditorRepresentationHandles {
    struct Handle: Equatable {
        let entityId: EntityID
        let property: String
    }

    struct Placed: Equatable {
        let handle: Handle
        let worldPosition: SIMD3<Float>
        let tint: SIMD3<Float>
    }

    private static var selected: Handle?
    private static var dragStartValue: UntoldAttributeValue?

    // MARK: Selection

    /// The handle the gizmo is on, if any. It holds only while its entity is the active one
    /// and the property is still there, so a selection change or a reload never leaves a stale one.
    static var active: Handle? {
        guard let selected, selected.entityId == activeEntity, plugin(for: selected) != nil else { return nil }
        return selected
    }

    static func select(_ handle: Handle?) {
        selected = handle
        dragStartValue = nil
    }

    // MARK: Positions

    /// Every handle in the scene, with where it is in the world and how it is tinted.
    static func placed() -> [Placed] {
        EditorRepresentationRenderer.drawings().flatMap { drawing in
            placed(in: drawing.representation, on: drawing.entityId)
        }
    }

    static func placed(in representation: EditorRepresentation, on entityId: EntityID) -> [Placed] {
        guard let plugin = ScenePluginSystem.shared.entityPlugin(on: entityId) else { return [] }
        let space = worldSpace(of: entityId)
        var result: [Placed] = []
        for case let .handles(properties, tint) in representation.items {
            for property in properties {
                guard let local = vector(of: property, on: plugin) else { continue }
                let world = space * SIMD4<Float>(local.x, local.y, local.z, 1)
                result.append(Placed(handle: Handle(entityId: entityId, property: property), worldPosition: SIMD3<Float>(world.x, world.y, world.z), tint: tint))
            }
        }
        return result
    }

    static func worldPosition(of handle: Handle) -> SIMD3<Float>? {
        guard let plugin = plugin(for: handle), let local = vector(of: handle.property, on: plugin) else { return nil }
        let world = worldSpace(of: handle.entityId) * SIMD4<Float>(local.x, local.y, local.z, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    /// Writes the property so the point lands at `world`, in the entity's local space. Marks
    /// the scene dirty and refreshes the Inspector, whose fields show the property live.
    @discardableResult
    static func move(_ handle: Handle, toWorld world: SIMD3<Float>) -> Bool {
        guard let plugin = plugin(for: handle) else { return false }
        let local = worldSpace(of: handle.entityId).inverse * SIMD4<Float>(world.x, world.y, world.z, 1)
        guard local.x.isFinite, local.y.isFinite, local.z.isFinite else { return false }
        let value = UntoldAttributeValue.array([Double(local.x), Double(local.y), Double(local.z)])
        guard ScenePluginSystem.shared.setAttribute(handle.property, of: type(of: plugin).typeName, on: handle.entityId, to: value) else {
            return false
        }
        EditorSceneDirtyState.shared.markDirty()
        editorController?.refreshInspector()
        return true
    }

    // MARK: Picking

    /// How far from a handle's centre, in points, a click still counts.
    static let pickDistancePoints: Float = 14

    /// The handle under a click. `location` and `viewSize` are in the viewport view's own
    /// coordinates (points, origin bottom-left, as its gesture recognizers report them). Each
    /// handle is projected with the camera's matrices, so this matches what is on screen on
    /// any display; the nearest one within `pickDistancePoints` wins.
    static func pick(
        atViewLocation location: CGPoint,
        viewSize: CGSize,
        viewSpace: simd_float4x4,
        perspectiveSpace: simd_float4x4
    ) -> Handle? {
        pick(among: placed(), atViewLocation: location, viewSize: viewSize, viewSpace: viewSpace, perspectiveSpace: perspectiveSpace)
    }

    static func pick(
        among candidates: [Placed],
        atViewLocation location: CGPoint,
        viewSize: CGSize,
        viewSpace: simd_float4x4,
        perspectiveSpace: simd_float4x4,
        maxDistance: Float = pickDistancePoints
    ) -> Handle? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let viewProjection = perspectiveSpace * viewSpace
        var best: (handle: Handle, distance: Float)?
        for candidate in candidates {
            guard let projected = project(candidate.worldPosition, viewProjection: viewProjection, viewSize: viewSize) else { continue }
            let distance = hypot(projected.x - Float(location.x), projected.y - Float(location.y))
            guard distance <= maxDistance else { continue }
            if best == nil || distance < best!.distance {
                best = (candidate.handle, distance)
            }
        }
        return best?.handle
    }

    /// Where a world position lands in the view, in points with the origin bottom-left, the
    /// frame `rayDirectionInWorldSpace` reads clicks in. `nil` behind the camera.
    static func project(_ world: SIMD3<Float>, viewProjection: simd_float4x4, viewSize: CGSize) -> SIMD2<Float>? {
        let clip = viewProjection * SIMD4<Float>(world.x, world.y, world.z, 1)
        guard clip.w > 0.0001 else { return nil }
        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        guard ndc.x.isFinite, ndc.y.isFinite else { return nil }
        return SIMD2<Float>((ndc.x + 1) * 0.5 * Float(viewSize.width), (ndc.y + 1) * 0.5 * Float(viewSize.height))
    }

    // MARK: Drag undo

    /// Call when a gizmo drag begins: remembers the value so the drag is one undo step.
    static func dragDidBegin() {
        guard let handle = active, let plugin = plugin(for: handle) else {
            dragStartValue = nil
            return
        }
        dragStartValue = attributeValue(of: handle.property, on: plugin)
    }

    static func dragDidEnd() {
        guard let start = dragStartValue else { return }
        dragStartValue = nil
        guard let handle = active, let plugin = plugin(for: handle),
              let end = attributeValue(of: handle.property, on: plugin), end != start
        else { return }

        let entity = handle.entityId
        let typeName = type(of: plugin).typeName
        let property = handle.property
        let label = plugin.untoldAttributes().first { $0.name == property }?.displayLabel ?? property
        EditorUndoManager.shared.registerValueChange(name: "Move \(label)", oldValue: start, newValue: end) { restored in
            ScenePluginSystem.shared.setAttribute(property, of: typeName, on: entity, to: restored)
            EditorSceneDirtyState.shared.markDirty()
            editorController?.refreshInspector()
        }
    }

    // MARK: Helpers

    private static func plugin(for handle: Handle) -> EntityPlugin? {
        guard scene.mask(for: handle.entityId) != nil,
              let plugin = ScenePluginSystem.shared.entityPlugin(on: handle.entityId),
              vector(of: handle.property, on: plugin) != nil
        else { return nil }
        return plugin
    }

    private static func attributeValue(of property: String, on plugin: ScenePlugin) -> UntoldAttributeValue? {
        plugin.untoldAttributes().first { $0.name == property }?.attribute.attributeValue
    }

    /// The property's value when it is a three-component vector; anything else is not a handle.
    static func vector(of property: String, on plugin: ScenePlugin) -> SIMD3<Float>? {
        guard case let .array(components)? = attributeValue(of: property, on: plugin), components.count == 3 else { return nil }
        return SIMD3<Float>(Float(components[0]), Float(components[1]), Float(components[2]))
    }

    static func worldSpace(of entityId: EntityID) -> simd_float4x4 {
        if hasComponent(entityId: entityId, componentType: WorldTransformComponent.self),
           let world = scene.get(component: WorldTransformComponent.self, for: entityId)
        {
            return world.space
        }
        return scene.get(component: LocalTransformComponent.self, for: entityId)?.space ?? matrix_identity_float4x4
    }
}
