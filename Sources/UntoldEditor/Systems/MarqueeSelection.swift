//
//  MarqueeSelection.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics
import simd
import UntoldEngine

/// What the rectangle dragged over the viewport selects: every entity that
/// stands inside it and that a click could select.
///
/// An entity is inside when all of its box is, so the floor under what the
/// rectangle is drawn around, or the wall behind it, is left out: it reaches
/// out of the rectangle. What has a place and no box, such as a light, is
/// inside where it stands. Of what draws meshes, only what is seen counts:
/// what stands behind a wall or under a floor is left out though it is
/// inside. Telling what is seen takes a pass of the renderer, handed in as
/// `seen`; without one, being inside is enough.
enum MarqueeSelection {
    /// Tells which of the entities that draw meshes show in a rectangle of
    /// the viewport, or nil when it cannot tell.
    typealias Seen = (_ rect: CGRect, _ view: MarqueeGeometry.View, _ drawn: [EntityID]) -> Set<EntityID>?

    /// The entities inside the rectangle, the farthest from the camera first
    /// and the nearest last. `rect` is in points from the bottom left of the
    /// viewport, as the canvas measures the pointer.
    static func entities(
        inside rect: CGRect,
        view: MarqueeGeometry.View,
        selectionManager: SelectionManager?,
        seen: Seen? = nil
    ) -> [EntityID] {
        let eye = simd_mul(simd_inverse(view.viewSpace), simd_float4(0, 0, 0, 1))
        let camera = simd_float3(eye.x, eye.y, eye.z)
        var inside: [(entityId: EntityID, distance: Float, drawsMeshes: Bool)] = []

        let everyEntity = getAllGameEntities()
        for entityId in everyEntity {
            guard canBeSelected(entityId, selectionManager: selectionManager),
                  let world = scene.get(component: WorldTransformComponent.self, for: entityId)?.space
            else {
                continue
            }
            let position = simd_float3(world.columns.3.x, world.columns.3.y, world.columns.3.z)

            let isInside: Bool
            if draws(entityId), let local = scene.get(component: LocalTransformComponent.self, for: entityId) {
                isInside = MarqueeGeometry.contains(
                    rect,
                    boxMinimum: local.boundingBox.min,
                    boxMaximum: local.boundingBox.max,
                    modelSpace: world,
                    view: view
                )
            } else if showsWhereItStands(entityId) {
                isInside = MarqueeGeometry.contains(rect, point: position, view: view)
            } else {
                isInside = false
            }

            if isInside {
                inside.append((entityId, simd_distance(position, camera), drawsMeshes(entityId)))
            }
        }

        // Whatever draws a mesh hides what is behind it, selectable or not: a
        // locked wall is not selected, and neither is what it covers. The pass
        // is only asked when something it can tell about is inside.
        if inside.contains(where: \.drawsMeshes), let shown = seen?(rect, view, everyEntity.filter(drawsMeshes)) {
            inside.removeAll { $0.drawsMeshes && shown.contains($0.entityId) == false }
        }
        return inside.sorted { $0.distance > $1.distance }.map(\.entityId)
    }

    /// The asset each entity belongs to, in the same order and each once: what
    /// the rectangle selects with ⌘ held, as a ⌘ click selects the asset of
    /// what it hits.
    static func assetRoots(of entityIds: [EntityID]) -> [EntityID] {
        var seen = Set<EntityID>()
        // The nearest entity decides where its asset stands in the order.
        let roots = entityIds.reversed().map(editableAssetRootEntity(for:)).filter { seen.insert($0).inserted }
        return roots.reversed()
    }

    /// Whether a click could select the entity: it is the scene's, the
    /// picking takes it, and it is neither hidden nor locked.
    static func canBeSelected(_ entityId: EntityID, selectionManager: SelectionManager?) -> Bool {
        guard hasComponent(entityId: entityId, componentType: GizmoComponent.self) == false,
              hasComponent(entityId: entityId, componentType: CameraComponent.self) == false,
              hasComponent(entityId: entityId, componentType: SceneCameraComponent.self) == false
        else {
            return false
        }
        if let picking = scene.get(component: PickInteractionComponent.self, for: entityId),
           picking.participatesInPicking == false || picking.hitRepresentationMode == .none
        {
            return false
        }
        guard isSceneEntityPickableByChannel(entityId: entityId) else {
            return false
        }
        if let selectionManager,
           selectionManager.isEffectivelyHidden(entityId) || selectionManager.isEffectivelyLocked(entityId)
        {
            return false
        }
        return true
    }

    /// Whether the scene draws meshes of this entity, which the pass that
    /// tells what is seen can draw too.
    static func drawsMeshes(_ entityId: EntityID) -> Bool {
        guard let render = scene.get(component: RenderComponent.self, for: entityId),
              render.isVisible,
              hasComponent(entityId: entityId, componentType: LightComponent.self) == false,
              hasComponent(entityId: entityId, componentType: CameraComponent.self) == false,
              hasComponent(entityId: entityId, componentType: GizmoComponent.self) == false,
              shouldHideSceneEntity(entityId: entityId) == false
        else {
            return false
        }
        return render.mesh.contains(where: SelectionVisibilityPass.hasThePositionsThePipelineReads)
    }

    /// Whether the entity itself draws something with a box around it.
    static func draws(_ entityId: EntityID) -> Bool {
        if let render = scene.get(component: RenderComponent.self, for: entityId) {
            return render.isVisible
        }
        return hasComponent(entityId: entityId, componentType: GaussianComponent.self)
    }

    /// Whether the editor shows where an entity that draws nothing stands: a
    /// light by its icon, an entity written in code by its representation.
    static func showsWhereItStands(_ entityId: EntityID) -> Bool {
        guard hasComponent(entityId: entityId, componentType: RenderComponent.self) == false else {
            return false
        }
        return hasComponent(entityId: entityId, componentType: LightComponent.self)
            || EditorRepresentationRenderer.drawing(for: entityId) != nil
    }
}
