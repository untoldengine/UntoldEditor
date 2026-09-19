//
//  AreaLightEditorView.swift
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

struct AreaLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: AreaLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)
                let scale: simd_float3 = getScale(entityId: entityId)
                let areaLightComponent = scene.get(component: AreaLightComponent.self, for: entityId)
                let range: Float = areaLightComponent?.range ?? 0.0
                let twoSided: Bool = areaLightComponent?.twoSided ?? false

                TextInputVectorView(label: "Color", value: Binding(
                    get: { color },
                    set: { newColor in
                        updateLightColor(entityId: entityId, color: newColor)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    TextInputNumberView(label: "Power (W)", value: Binding(
                        get: { intensity },
                        set: { newIntensity in
                            setLight(entityId: entityId, .power(newIntensity))
                            EditorSceneDirtyState.shared.markDirty()
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Range", value: Binding(
                        get: { range },
                        set: { newRange in
                            setLight(entityId: entityId, .area(.range(newRange)))
                            EditorSceneDirtyState.shared.markDirty()
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    TextInputNumberView(label: "Size X", value: Binding(
                        get: { scale.x },
                        set: { newSizeX in
                            let before = EditorTransformSnapshot(entityId: entityId)
                            let nextSizeX = max(newSizeX, 0.001)
                            scaleTo(entityId: entityId, scale: simd_float3(nextSizeX, scale.y, scale.z))
                            EditorUndoManager.shared.registerTransformChange(
                                entityId: entityId,
                                before: before,
                                after: EditorTransformSnapshot(entityId: entityId)
                            )
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Size Y", value: Binding(
                        get: { scale.y },
                        set: { newSizeY in
                            let before = EditorTransformSnapshot(entityId: entityId)
                            let nextSizeY = max(newSizeY, 0.001)
                            scaleTo(entityId: entityId, scale: simd_float3(scale.x, nextSizeY, scale.z))
                            EditorUndoManager.shared.registerTransformChange(
                                entityId: entityId,
                                before: before,
                                after: EditorTransformSnapshot(entityId: entityId)
                            )
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle(isOn: Binding(
                    get: { twoSided },
                    set: { enabled in
                        setLight(entityId: entityId, .area(.twoSided(enabled)))
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                )) {
                    Text("Two Sided")
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
