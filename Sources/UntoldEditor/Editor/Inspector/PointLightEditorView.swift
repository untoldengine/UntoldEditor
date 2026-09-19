//
//  PointLightEditorView.swift
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

struct PointLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: PointLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)
                let falloff: Float = getLightFalloff(entityId: entityId)
                let radius: Float = getLightRadius(entityId: entityId)
                let range: Float = scene.get(component: PointLightComponent.self, for: entityId)?.range ?? 0.0
                let castsShadow: Bool = getPointLightCastsShadow(entityId: entityId)

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
                            setLight(entityId: entityId, .point(.range(newRange)))
                            EditorSceneDirtyState.shared.markDirty()
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Radius", value: Binding(
                        get: { radius },
                        set: { newRadius in
                            updateLightRadius(entityId: entityId, radius: newRadius)
                            EditorSceneDirtyState.shared.markDirty()
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextInputNumberView(label: "Legacy Falloff", value: Binding(
                    get: { falloff },
                    set: { newFalloff in
                        updateLightFalloff(entityId: entityId, falloff: newFalloff)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: Binding(
                    get: { castsShadow },
                    set: { enabled in
                        setLight(entityId: entityId, .point(.castsShadow(enabled)))
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                )) {
                    Text("Shadow")
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
