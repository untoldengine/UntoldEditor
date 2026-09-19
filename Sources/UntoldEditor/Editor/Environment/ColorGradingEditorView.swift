//
//  ColorGradingEditorView.swift
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

struct ColorGradingEditorView: View {
    @ObservedObject var settings = ColorGradingParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Color Grading",
                isOn: $settings.enabled
            ) {
                Text("Enable Color Grading")
            }

            UndoableEffectSlider(label: "Exposure", undoName: "Change Exposure", range: -5.0 ... 5.0, get: { settings.exposure }, set: { settings.exposure = $0 })
            UndoableEffectSlider(label: "Brightness", undoName: "Change Brightness", range: -1.0 ... 1.0, get: { settings.brightness }, set: { settings.brightness = $0 })
            UndoableEffectSlider(label: "Contrast", undoName: "Change Contrast", range: -5.0 ... 5.0, get: { settings.contrast }, set: { settings.contrast = $0 })
            UndoableEffectSlider(label: "Saturation", undoName: "Change Saturation", range: 0.0 ... 5.0, get: { settings.saturation }, set: { settings.saturation = $0 })
        }
        .padding(.vertical, 4)
    }
}
