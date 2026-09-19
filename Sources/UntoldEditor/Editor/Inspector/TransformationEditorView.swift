//
//  TransformationEditorView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

struct TransformationEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @State private var showStaticBatchWarning = false

    var body: some View {
        Text("Transform Properties")

        // Warning banner if entity is marked as static
        if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.editorWarning)
                Text("This entity is marked for static batching. Transforming it will disable batching.")
                    .font(.caption)
                    .foregroundColor(.editorWarning)
            }
            .padding(6)
            .background(Color.editorWarning.opacity(0.1))
            .cornerRadius(6)
        }

        if let localTransformComponent = scene.get(component: LocalTransformComponent.self, for: entityId) {
            let position = getLocalPosition(entityId: entityId)
            let orientation = simd_float3(localTransformComponent.rotationX, localTransformComponent.rotationY, localTransformComponent.rotationZ)
            let scale = getScale(entityId: entityId)

            TextInputVectorView(label: "Position", value: Binding(
                get: { position },
                set: { newPosition in
                    let before = EditorTransformSnapshot(entityId: entityId)
                    handleTransformChange()
                    translateTo(entityId: entityId, position: newPosition)
                    EditorUndoManager.shared.registerTransformChange(
                        entityId: entityId,
                        before: before,
                        after: EditorTransformSnapshot(entityId: entityId)
                    )
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Orientation", value: Binding(
                get: { orientation },
                set: { newOrientation in
                    let before = EditorTransformSnapshot(entityId: entityId)
                    handleTransformChange()
                    applyAxisRotations(entityId: entityId, axis: newOrientation)
                    syncLightDirectionHandleToActiveLight(entityId: entityId)
                    EditorUndoManager.shared.registerTransformChange(
                        entityId: entityId,
                        before: before,
                        after: EditorTransformSnapshot(entityId: entityId)
                    )
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Scale", value: Binding(
                get: { scale },
                set: { newScale in
                    let before = EditorTransformSnapshot(entityId: entityId)
                    handleTransformChange()
                    scaleTo(entityId: entityId, scale: newScale)
                    EditorUndoManager.shared.registerTransformChange(
                        entityId: entityId,
                        before: before,
                        after: EditorTransformSnapshot(entityId: entityId)
                    )
                    refreshView()
                }
            ))
        } else {
            Text("No transform data")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)
        }
    }

    private func handleTransformChange() {
        if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
            removeEntityStaticBatchComponent(entityId: entityId)
            // Optionally regenerate batches without this entity
            if isBatchingEnabled() {
                generateBatches()
            }
        }
    }
}
