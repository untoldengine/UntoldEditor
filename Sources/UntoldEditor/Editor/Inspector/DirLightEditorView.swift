//
//  DirLightEditorView.swift
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

struct DirLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: DirectionalLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)

                TextInputVectorView(label: "Color", value: Binding(
                    get: { color },
                    set: { newColor in
                        updateLightColor(entityId: entityId, color: newColor)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                TextInputNumberView(label: "Strength (W/m\u{b2})", value: Binding(
                    get: { intensity },
                    set: { newIntensity in
                        setLight(entityId: entityId, .strength(newIntensity))
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sun Direction")
                        .font(.headline)

                    TextInputNumberView(label: "Elevation", value: Binding(
                        get: { getSunElevationAzimuth(entityId: entityId).elevation },
                        set: { newElevation in
                            let before = EditorTransformSnapshot(entityId: entityId)
                            editorSetSunElevation(entityId: entityId, elevation: newElevation)
                            EditorUndoManager.shared.registerTransformChange(
                                entityId: entityId,
                                before: before,
                                after: EditorTransformSnapshot(entityId: entityId)
                            )
                            refreshView()
                        }
                    ), fractionDigits: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Azimuth", value: Binding(
                        get: { getSunElevationAzimuth(entityId: entityId).azimuth },
                        set: { newAzimuth in
                            let before = EditorTransformSnapshot(entityId: entityId)
                            editorSetSunAzimuth(entityId: entityId, azimuth: newAzimuth)
                            EditorUndoManager.shared.registerTransformChange(
                                entityId: entityId,
                                before: before,
                                after: EditorTransformSnapshot(entityId: entityId)
                            )
                            refreshView()
                        }
                    ), fractionDigits: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
