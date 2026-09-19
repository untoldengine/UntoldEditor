//
//  WhiteBalanceEditorView.swift
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

struct WhiteBalanceEditorView: View {
    @ObservedObject var settings = ColorGradingParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectSlider(label: "Temperature", undoName: "Change Temperature", range: -100.0 ... 100.0, get: { settings.temperature }, set: { settings.temperature = $0 })
            UndoableEffectSlider(label: "Tint", undoName: "Change Tint", range: -100.0 ... 100.0, get: { settings.tint }, set: { settings.tint = $0 })

//            TextInputVectorView(label: "Lift", value: Binding(
//                get: { settings.lift },
//                set: { newLift in
//                    settings.lift = newLift
//                }))
//
//            TextInputVectorView(label: "Gamma", value: Binding(
//                get: { settings.gamma },
//                set: { newGamma in
//                    settings.gamma = newGamma
//                }))
//
//            TextInputVectorView(label: "Gain", value: Binding(
//                get: { settings.gain },
//                set: { newGain in
//                    settings.gain = newGain
//                }))
        }
        .padding(.vertical, 4)
    }
}
