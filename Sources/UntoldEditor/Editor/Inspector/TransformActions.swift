//
//  TransformActions.swift
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

/// Runs one edit of an entity's transform and puts the change on the undo
/// stack. A statically batched entity leaves its batch first, since a moved
/// entity cannot stay in one.
func editTransform(of entityId: EntityID, _ change: () -> Void) {
    let before = EditorTransformSnapshot(entityId: entityId)
    if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
        removeEntityStaticBatchComponent(entityId: entityId)
        if isBatchingEnabled() {
            generateBatches()
        }
    }
    change()
    syncGizmoToTurn(of: entityId)
    EditorUndoManager.shared.registerTransformChange(
        entityId: entityId,
        before: before,
        after: EditorTransformSnapshot(entityId: entityId)
    )
}

/// The Transform section's Reset: back to the origin, unrotated, at scale one.
func resetTransform(entityId: EntityID) {
    guard hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) else { return }
    editTransform(of: entityId) {
        translateTo(entityId: entityId, position: simd_float3(repeating: 0))
        applyAxisRotations(entityId: entityId, axis: simd_float3(repeating: 0))
        scaleTo(entityId: entityId, scale: simd_float3(repeating: 1))
    }
}
