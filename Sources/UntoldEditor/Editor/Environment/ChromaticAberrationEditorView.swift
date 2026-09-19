//
//  ChromaticAberrationEditorView.swift
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

struct ChromaticAberrationEditorView: View {
    @ObservedObject var settings = ChromaticAberrationParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Chromatic Aberration",
                isOn: $settings.enabled
            ) {
                Text("Enable Chromatic Aberration")
            }

            UndoableEffectSlider(label: "Intensity", undoName: "Change Chromatic Aberration Intensity", range: 0.0 ... 0.01, format: "%.4f", get: { settings.intensity }, set: { settings.intensity = $0 })

//            TextInputVectorView(label: "Center", value: Binding(
//                get: { settings.center },
//                set: { newCenter in
//                    settings.center = newCenter
//                }))
        }
        .padding(.vertical, 4)
    }
}
