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
import UntoldEngine

/// The Transform section's editor: position, rotation and scale, one undo
/// step per committed field.
struct TransformationEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            if hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) {
                TransformVectorRow(label: "Position", value: Binding(
                    get: { getLocalPosition(entityId: entityId) },
                    set: { newPosition in
                        edit { translateTo(entityId: entityId, position: newPosition) }
                    }
                ))
                TransformVectorRow(label: "Rotation", value: Binding(
                    get: { getAxisRotations(entityId: entityId) },
                    set: { newRotation in
                        edit { applyAxisRotations(entityId: entityId, axis: newRotation) }
                    }
                ))
                TransformVectorRow(label: "Scale", value: Binding(
                    get: { getScale(entityId: entityId) },
                    set: { newScale in
                        edit { scaleTo(entityId: entityId, scale: newScale) }
                    }
                ))
            } else {
                Text("No transform data")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
            }
        }
    }

    private func edit(_ change: () -> Void) {
        editTransform(of: entityId, change)
        refreshView()
    }
}
