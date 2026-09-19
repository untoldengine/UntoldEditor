//
//  CameraEditorView.swift
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

struct CameraEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Camera System")

        if hasComponent(entityId: entityId, componentType: CameraComponent.self) {
            let eye: simd_float3 = getCameraEye(entityId: entityId)
            let up: simd_float3 = getCameraUp(entityId: entityId)
            let target: simd_float3 = getCameraTarget(entityId: entityId)

            TextInputVectorView(label: "Eye", value: Binding(
                get: { eye },
                set: { newEye in
                    cameraLookAt(entityId: entityId, eye: newEye, target: target, up: up)
                    EditorSceneDirtyState.shared.markDirty()
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Up", value: Binding(
                get: { up },
                set: { newUp in
                    cameraLookAt(entityId: entityId, eye: eye, target: target, up: newUp)
                    EditorSceneDirtyState.shared.markDirty()
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Target", value: Binding(
                get: { target },
                set: { newTarget in
                    cameraLookAt(entityId: entityId, eye: eye, target: newTarget, up: up)
                    EditorSceneDirtyState.shared.markDirty()
                    refreshView()
                }
            ))
        }
    }
}
