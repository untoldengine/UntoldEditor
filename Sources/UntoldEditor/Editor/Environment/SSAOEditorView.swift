//
//  SSAOEditorView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CShaderTypes
import simd
import SwiftUI
import UntoldEngine

struct SSAOEditorView: View {
    @ObservedObject var settings = SSAOParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle SSAO",
                isOn: $settings.enabled
            ) {
                Text("Enable SSAO")
            }

            UndoableEffectSlider(
                label: "Radius",
                undoName: "Change SSAO Radius",
                range: 0.1 ... 1.0,
                help: "World-space distance (scene units) SSAO searches for nearby occluding geometry. Larger values give broader, softer shadowing; smaller values keep it tight to contact points.",
                get: { settings.radius },
                set: { settings.radius = $0 }
            )
            UndoableEffectSlider(
                label: "Bias",
                undoName: "Change SSAO Bias",
                range: 0.0 ... 0.1,
                format: "%.4f",
                help: "Angular tolerance that suppresses false self-shadowing. Raise it if flat or sloped surfaces (floors, walls) darken as the camera moves, or if low-poly geometry shows dark seams along facet edges. Too high loses fine contact shadows.",
                get: { settings.bias },
                set: { settings.bias = $0 }
            )
            UndoableEffectSlider(
                label: "Intensity",
                undoName: "Change SSAO Intensity",
                range: 0.0 ... 2.0,
                help: "Overall strength of the ambient occlusion effect. 0 disables the visual darkening entirely; higher values deepen shadowing in creases and contact points.",
                get: { settings.intensity },
                set: { settings.intensity = $0 }
            )
        }
        .padding(.vertical, 4)
    }
}
