//
//  SelectionManager+Several.swift
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

/// A selection of several entities: the rectangle dragged over the viewport
/// selects them at once, a ⇧ click adds one or takes it out. Each one shows
/// its box, and one gizmo in the middle of them moves, turns and scales them
/// together.
extension SelectionManager {
    var hasSeveralSelected: Bool {
        selectedEntities.count > 1
    }

    func isSelected(_ entityId: EntityID) -> Bool {
        selectedEntities.contains(entityId)
    }

    /// Selects `entityIds`, in their order and each once; the last one is the
    /// one the Inspector names. One entity is selected as a click on its row
    /// selects it, and none clears the selection.
    func selectEntities(_ entityIds: [EntityID]) {
        var seen = Set<EntityID>()
        let entities = entityIds.filter { $0 != .invalid && seen.insert($0).inserted }

        guard entities.count > 1 else {
            if let only = entities.first {
                inspectEntity(entityId: only)
            } else {
                clearSelection()
            }
            return
        }
        setSelection(toSeveral: entities)
    }

    /// Adds an entity to the selection, or takes it out when it is selected.
    func toggleSelection(of entityId: EntityID) {
        guard entityId != .invalid else { return }
        if isSelected(entityId) {
            selectEntities(selectedEntities.filter { $0 != entityId })
        } else {
            selectEntities(selectedEntities + [entityId])
        }
    }

    /// Entities that left the scene leave a selection of several, which goes
    /// on with the rest. One entity selected alone is the caller's to clear.
    func forgetEntitiesThatLeftTheScene() {
        guard hasSeveralSelected else { return }
        let inTheScene = Set(getAllGameEntities())
        let remaining = selectedEntities.filter(inTheScene.contains)
        if remaining != selectedEntities {
            selectEntities(remaining)
        }
    }

    /// The selected entities the gizmo moves: those it may go on, without the
    /// ones under another of them, which move with their parent.
    var transformTargets: [EntityID] {
        let movable = selectedEntities.filter(takesGizmo)
        let among = Set(movable)
        return movable.filter { hasAncestor($0, in: among) == false }
    }

    private func hasAncestor(_ entityId: EntityID, in set: Set<EntityID>) -> Bool {
        var current = parentInSceneGraph(of: entityId)
        var depth = 0
        while let id = current, depth < 64 {
            if set.contains(id) {
                return true
            }
            current = parentInSceneGraph(of: id)
            depth += 1
        }
        return false
    }

    /// Hands the selection of several to the viewport: the boxes to draw, the
    /// entities the gizmo moves and the gizmo itself, in the middle of them.
    func activateSeveral() {
        EditorRepresentationHandles.select(nil)
        SelectionHighlights.shared.boxes = highlightBoxes()

        let targets = transformTargets
        // The gizmo's own axes, in Local space, are those of the last one
        // selected that it moves.
        guard let active = targets.last(where: { $0 == selectedEntity }) ?? targets.last else {
            gizmoTargets = []
            activeEntity = .invalid
            gizmoActive = false
            removeGizmo()
            return
        }

        gizmoTargets = targets
        activeEntity = active
        createGizmo(forTool: EditorViewportSettings.shared.tool)
    }

    /// One entity alone is selected, or none: nothing is kept of several.
    func forgetSeveral() {
        if gizmoTargets.isEmpty == false {
            gizmoTargets = []
        }
        SelectionHighlights.shared.boxes = []
    }

    /// The box of every selected entity that shows in the viewport, hidden
    /// ones left out: around what it draws, or where it stands when it draws
    /// nothing.
    func highlightBoxes() -> [SelectionHighlightBox] {
        selectedEntities.compactMap { entityId in
            guard isEffectivelyHidden(entityId) == false,
                  hasComponent(entityId: entityId, componentType: WorldTransformComponent.self)
            else {
                return nil
            }
            guard let bounds = renderableBoundsInOwnSpace(entityId: entityId) else {
                return SelectionHighlightBox.point(entityId: entityId)
            }
            return SelectionHighlightBox(entityId: entityId, minimum: bounds.min, maximum: bounds.max, isPoint: false)
        }
    }
}
