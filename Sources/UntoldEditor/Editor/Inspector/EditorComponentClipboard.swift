//
//  EditorComponentClipboard.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import UntoldEngine

/// Component values copied from one entity's section, to paste into another's:
/// a transform, or the material of a mesh.
final class EditorComponentClipboard: ObservableObject {
    static let shared = EditorComponentClipboard()

    @Published private(set) var transform: EditorTransformSnapshot?
    @Published private(set) var material: MaterialSnapshot?

    func copyTransform(of entityId: EntityID) {
        guard hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) else { return }
        transform = EditorTransformSnapshot(entityId: entityId)
    }

    /// Applies the copied transform as one undo step. False when nothing was
    /// copied or the entity has no transform.
    @discardableResult
    func pasteTransform(into entityId: EntityID) -> Bool {
        guard let transform, hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) else {
            return false
        }
        editTransform(of: entityId) {
            transform.apply(to: entityId)
        }
        return true
    }

    func copyMaterial(of entityId: EntityID, meshIndex: Int) {
        guard hasComponent(entityId: entityId, componentType: RenderComponent.self) else { return }
        material = MaterialSnapshot(entityId: entityId, meshIndex: meshIndex)
    }

    /// Applies the copied material to a mesh. False when nothing was copied or
    /// the entity has no render component. Not on the undo stack: material
    /// edits are not undoable yet.
    @discardableResult
    func pasteMaterial(into entityId: EntityID, meshIndex: Int) -> Bool {
        guard let material, hasComponent(entityId: entityId, componentType: RenderComponent.self) else {
            return false
        }
        material.apply(to: entityId, meshIndex: meshIndex)
        EditorSceneDirtyState.shared.markDirty()
        return true
    }

    func clear() {
        transform = nil
        material = nil
    }
}
