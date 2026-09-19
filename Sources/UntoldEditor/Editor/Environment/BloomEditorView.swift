//
//  BloomEditorView.swift
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

struct BloomEditorView: View {
    @ObservedObject var settings = BloomThresholdParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Bloom",
                isOn: $settings.enabled
            ) {
                Text("Enable Bloom")
            }

            UndoableEffectSlider(label: "Threshold", undoName: "Change Bloom Threshold", range: 0.0 ... 5.0, get: { settings.threshold }, set: { settings.threshold = $0 })
            UndoableEffectSlider(label: "Intensity", undoName: "Change Bloom Intensity", range: 0.0 ... 100.0, get: { settings.intensity }, set: { settings.intensity = $0 })
        }
        .padding(.vertical, 4)
    }
}
