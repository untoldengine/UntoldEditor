//
//  VignetteEditorView.swift
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

struct VignetteEditorView: View {
    @ObservedObject var settings = VignetteParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Vignette",
                isOn: $settings.enabled
            ) {
                Text("Enable Vignette")
            }

            UndoableEffectSlider(label: "Intensity", undoName: "Change Vignette Intensity", range: 0.0 ... 1.0, get: { settings.intensity }, set: { settings.intensity = $0 })
            UndoableEffectSlider(label: "Radius", undoName: "Change Vignette Radius", range: 0.0 ... 1.0, get: { settings.radius }, set: { settings.radius = $0 })
            UndoableEffectSlider(label: "Softness", undoName: "Change Vignette Softness", range: 0.0 ... 1.0, get: { settings.softness }, set: { settings.softness = $0 })

//            TextInputVectorView(label: "Center", value: Binding(
//                get: { settings.center },
//                set: { newCenter in
//                    settings.center = newCenter
//                }))
        }
        .padding(.vertical, 4)
    }
}
